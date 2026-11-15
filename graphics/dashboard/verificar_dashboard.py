"""Verificación automatizada del paquete del dashboard (`graphics/dashboard/`).

Comprueba sin dependencias externas:
1. Paridad exacta entre `graphics/dashboard/index.html` y `graphics/topo3d.html`.
2. Integridad de IDs HTML↔JS y ausencia de regresiones en `state.closestWater` / `wb.isPermanent`.
3. Compilación de sintaxis de `servidor_dashboard.py` y `../servidor_topo3d.py`.
4. Ejecución opcional en Chrome/Edge headless con WebGL SwiftShader y mocks offline.
"""

from html.parser import HTMLParser
import json
from pathlib import Path
import py_compile
import re
import shutil
import subprocess
import sys
import tempfile


DASHBOARD_DIR = Path(__file__).resolve().parent
GRAPHICS_DIR = DASHBOARD_DIR.parent
INDEX_HTML = DASHBOARD_DIR / "index.html"
LEGACY_HTML = GRAPHICS_DIR / "topo3d.html"


class _IdCollector(HTMLParser):
    """Recolecta todos los atributos `id` definidos en el HTML."""

    def __init__(self):
        super().__init__()
        self.ids = set()

    def handle_starttag(self, tag, attrs):
        for k, v in attrs:
            if k == "id" and v:
                self.ids.add(v)


def check_html_contracts(html_text: str) -> list[str]:
    """Verifica IDs DOM y contratos de objetos en JavaScript."""
    issues = []
    parser = _IdCollector()
    parser.feed(html_text)
    js_refs = set(re.findall(r'getElementById\(\s*["\']([^"\']+)["\']\s*\)', html_text))
    missing = sorted(js_refs - parser.ids)
    if missing:
        issues.append(f"IDs referenciados en JS inexistentes en HTML: {missing}")

    for required_id in ("v01-mode-subtitle", "v01-bars-sub", "m-water-dist", "m-water-sub", "irr-mode-natural", "irr-mode-drip"):
        if required_id not in js_refs:
            issues.append(f"ID requerido '{required_id}' no actualizado desde JS")

    if "closestWater.wb" in html_text or "cw.wb" in html_text:
        issues.append("Referencia obsoleta a `.wb` detectada en closestWater")

    if "wb.type ===" in html_text:
        issues.append("Referencia obsoleta a `wb.type` detectada en renderScene")

    return issues


def find_headless_chrome() -> str | None:
    """Busca Chrome en rutas estándar de Windows/Linux para prueba WebGL opcional."""
    candidates = [
        r"C:\Program Files\Google\Chrome\Application\chrome.exe",
        r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
        shutil.which("google-chrome"),
        shutil.which("chromium"),
    ]
    for c in candidates:
        if c and Path(c).exists():
            return str(c)
    return None


def run_headless_check(chrome_exe: str, html_text: str) -> dict:
    """Ejecuta una carga offline y una simulación DEM+POWER+Overpass en Chrome headless."""
    with tempfile.TemporaryDirectory() as tmp:
        tmp_dir = Path(tmp)
        prof_dir = tmp_dir / "chrome_prof"
        probe_end = """
setTimeout(() => {
  const gl = state.glCtx ? state.glCtx.gl : null;
  setLayer("rain");
  setIrrigationMode("drip");
  placePoiByRowCol(80, 90, "Check CI");
  const out = {
    errors: window.__ERRS__ || [],
    hasDEM: Boolean(state.dem),
    demCells: state.dem ? state.dem.elev.length : 0,
    shaderLink: gl ? gl.getProgramParameter(state.glCtx.prog, gl.LINK_STATUS) : false,
    glError: gl ? gl.getError() : -1,
    mWaterDist: document.getElementById("m-water-dist")?.textContent,
    modeSub: document.getElementById("v01-mode-subtitle")?.textContent.trim(),
    barsSub: document.getElementById("v01-bars-sub")?.textContent.trim(),
  };
  const pre = document.createElement("pre");
  pre.id = "__VERIFY__";
  pre.textContent = JSON.stringify(out);
  document.body.appendChild(pre);
}, 1400);
"""
        mock_head = """
<script>
window.__ERRS__ = [];
window.addEventListener("error", (e) => window.__ERRS__.push(e.message || String(e)));
window.addEventListener("unhandledrejection", (e) => window.__ERRS__.push(String(e.reason)));
window.fetch = async (url) => {
  const s = String(url);
  if (s.includes("climatology")) {
    const m = (v) => Object.fromEntries(["JAN","FEB","MAR","APR","MAY","JUN","JUL","AUG","SEP","OCT","NOV","DEC"].map((k) => [k, v]));
    return new Response(JSON.stringify({geometry:{coordinates:[-89.33,14.53,820]},properties:{parameter:{T2M:m(24),RH2M:m(75),PRECTOTCORR:m(4),GWETTOP:m(0.5),GWETROOT:m(0.55)}}}), {status: 200});
  }
  if (s.includes("daily")) {
    const d = (v) => Object.fromEntries(Array.from({length: 16}, (_, i) => [`202511${String(i+1).padStart(2,"0")}`, v]));
    return new Response(JSON.stringify({properties:{parameter:{T2M:d(24),T2M_MAX:d(30),T2M_MIN:d(18),RH2M:d(76),PRECTOTCORR:d(3.5),GWETTOP:d(0.45),GWETROOT:d(0.42)}}}), {status: 200});
  }
  if (s.includes("overpass")) {
    return new Response(JSON.stringify({elements:[]}), {status: 200});
  }
  return Promise.reject(new Error("offline"));
};
</script>
"""
        tile_stub = """
    function loadTileImage(url) {
      if (tileCache.has(url)) return tileCache.get(url);
      const p = new Promise((resolve) => {
        const c = document.createElement("canvas");
        c.width = 256; c.height = 256;
        const ctx = c.getContext("2d");
        const d = ctx.createImageData(256, 256);
        for (let i = 0; i < d.data.length; i += 4) {
          d.data[i] = 131; d.data[i+1] = 200; d.data[i+2] = 0; d.data[i+3] = 255;
        }
        ctx.putImageData(d, 0, 0);
        resolve(c);
      });
      tileCache.set(url, p);
      return p;
    }
"""
        test_html = html_text.replace('<link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css" />', "")
        test_html = test_html.replace('<script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>', mock_head)
        i1 = test_html.index("    function loadTileImage(url) {")
        i2 = test_html.index("    function lon2tileFloat(lon, z) {")
        test_html = test_html[:i1] + tile_stub + "\n" + test_html[i2:]
        test_html = test_html.replace("    // Initial load\n    loadPointData();", "    // Initial load\n    loadPointData();\n" + probe_end)

        target = tmp_dir / "verify.html"
        target.write_text(test_html, encoding="utf-8")
        res = subprocess.run(
            [
                chrome_exe,
                "--headless=new",
                "--no-sandbox",
                f"--user-data-dir={prof_dir}",
                "--use-gl=angle",
                "--use-angle=swiftshader",
                "--enable-unsafe-swiftshader",
                "--virtual-time-budget=3000",
                "--dump-dom",
                target.as_uri(),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            timeout=25,
        )
        m = re.search(r'<pre id="__VERIFY__">(.*?)</pre>', res.stdout, re.S)
        if not m:
            raise RuntimeError(f"Chrome headless no devolvió reporte (exit={res.returncode})")
        return json.loads(m.group(1))


def main() -> int:
    """Ejecuta la batería de verificación y devuelve 0 si todo pasa."""
    html_text = INDEX_HTML.read_text(encoding="utf-8")
    issues = check_html_contracts(html_text)
    if LEGACY_HTML.exists() and LEGACY_HTML.read_bytes() != INDEX_HTML.read_bytes():
        issues.append("`graphics/dashboard/index.html` difiere de `graphics/topo3d.html`")

    for py_file in (DASHBOARD_DIR / "servidor_dashboard.py", GRAPHICS_DIR / "servidor_topo3d.py"):
        if py_file.exists():
            py_compile.compile(str(py_file), doraise=True)

    print(f"[OK] Sintaxis Python y contratos HTML ({len(html_text)} chars)" if not issues else f"[FAIL] {issues}")
    if issues:
        return 1

    chrome = find_headless_chrome()
    if chrome:
        report = run_headless_check(chrome, html_text)
        print("[CHROME HEADLESS]", json.dumps(report, ensure_ascii=False))
        if report["errors"] or not report["hasDEM"] or not report["shaderLink"] or report["mWaterDist"] == "Sin cauce":
            return 1
    else:
        print("[SKIP] Chrome no detectado; solo se ejecutó verificación estática.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
