"""Servidor HTTP local para el Dashboard Topográfico y Agroclimático 2D/3D (Field Shift Guatemala).

Ejecución desde la raíz del repositorio:
    python graphics/dashboard/servidor_dashboard.py --port 8090

Rutas expuestas:
    - GET /, /index.html, /topo3d.html, /dashboard  -> graphics/dashboard/index.html
    - GET /api/aw3d30?lat=..&lon=..&radius_km=5&n=68 -> Malla JAXA ALOS AW3D30 v4.1 (local o COG)
"""

import argparse
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import sys
import urllib.parse

DASHBOARD_DIR = Path(__file__).resolve().parent
GRAPHICS_DIR = DASHBOARD_DIR.parent
DASHBOARD_HTML = DASHBOARD_DIR / "index.html"
FALLBACK_HTML = GRAPHICS_DIR / "topo3d.html"

if str(GRAPHICS_DIR) not in sys.path:
    sys.path.insert(0, str(GRAPHICS_DIR))

import servidor_topo3d  # noqa: E402


class DashboardHandler(SimpleHTTPRequestHandler):
    """Manejador HTTP que sirve el dashboard estático y el respaldo DEM AW3D30."""

    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=str(DASHBOARD_DIR), **kwargs)

    def _send_bytes(self, payload: bytes, content_type: str) -> None:
        self.send_response(200)
        self.send_header("Content-Type", content_type)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self) -> None:
        parsed = urllib.parse.urlparse(self.path)
        if parsed.path in ("/", "/index.html", "/topo3d.html", "/dashboard", "/dashboard/"):
            target = DASHBOARD_HTML if DASHBOARD_HTML.exists() else FALLBACK_HTML
            self._send_bytes(target.read_bytes(), "text/html; charset=utf-8")
            return

        if parsed.path == "/api/aw3d30":
            qs = urllib.parse.parse_qs(parsed.query)
            lat = float(qs.get("lat", ["14.8000"])[0])
            lon = float(qs.get("lon", ["-89.5400"])[0])
            radius_km = float(qs.get("radius_km", ["5.0"])[0])
            n = max(16, min(120, int(qs.get("n", ["68"])[0])))
            data = servidor_topo3d.extract_grid(lat, lon, radius_km, n)
            self._send_bytes(json.dumps(data).encode("utf-8"), "application/json; charset=utf-8")
            return

        super().do_GET()

    def log_message(self, format: str, *args) -> None:
        return


def main() -> None:
    """Inicia el servidor local multi-hilo para el dashboard."""
    parser = argparse.ArgumentParser(description="Servidor local del Dashboard 2D/3D Field Shift Guatemala")
    parser.add_argument("--port", type=int, default=8090, help="Puerto HTTP local (por defecto: 8090)")
    args = parser.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), DashboardHandler)
    print(f"Dashboard Field Shift activo en http://localhost:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
