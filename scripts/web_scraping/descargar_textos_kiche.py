"""Descarga textos en K'iche' para el corpus de pre-entrenamiento.

Fuentes:
  - Ri Tyoxlaj Wuj: Biblia católica en K'iche' (iglesiacatolica.org.gt/bibliakiche)
  - K'iche' Maya Oral History Project, UNM Digital Repository (transcripciones 1968-1973)
  - Popol Vuh: Literal Translation (Allen J. Christenson, mesoweb.com)
  - Libro de cuentos de Chichicastenango (elizabethawood.github.io)
  - Cuentos en familia K'iche' (Mineduc / USAID Leer y Aprender)

Uso:
  python -I scripts/web_scraping/descargar_textos_kiche.py --out "C:/NASA Space Apps Challenge/Lenguas Mayas/pretraining/raw/kiche"
Además escribe <out>/fuentes.jsonl con url, título y autor de cada archivo (para CREDITOS.md).
"""
import argparse
import html
import json
import re
import ssl
import time
import urllib.parse
import urllib.request
from pathlib import Path

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36"
CTX = ssl.create_default_context()
BIBLIA = "https://www.iglesiacatolica.org.gt/bibliakiche/"
UNM = "https://digitalrepository.unm.edu/laii_kichemaya/"
SUELTOS = [
    ("https://www.mesoweb.com/publications/Christenson/PV-Literal.pdf", "popol_vuh_christenson",
     "Popol Vuh: Literal Translation (texto K'iche' con traducción literal al inglés)", "Allen J. Christenson (University of Oklahoma Press, 2004; edición electrónica Mesoweb)"),
    ("https://elizabethawood.github.io/files/LibroDeCuentos.pdf", "cuentos_chichicastenango",
     "Libro de cuentos de Chichicastenango (K'iche'-Español)", "Narradores de Chichicastenango; compilación: Elizabeth A. Wood"),
] + [
    (f"https://www.mineduc.gob.gt/mineduc/images/portal/DIGEFOCE/documents/usaid/{n}_kiche.pdf", "cuentos_en_familia",
     f"{n.replace('_', ' ')} (Colección Cuentos en familia, K'iche')", "Proyecto USAID Leer y Aprender / Ministerio de Educación de Guatemala")
    for n in ["El_Ratoncito", "La_Llorona_y_Tijereta", "Los_animales_y_la_selva"]
]


def get(url, binary=False):
    for i in range(3):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=120, context=CTX) as r:
                data = r.read()
                return data if binary else data.decode("utf-8", errors="replace")
        except urllib.error.HTTPError as e:
            if e.code in (403, 404):
                print(f"  {e.code}: {url}")
                return None
            time.sleep(3 * (i + 1))
        except Exception:
            time.sleep(3 * (i + 1))
    return None


def bajar(url, dest):
    if dest.exists() and dest.stat().st_size > 1000:
        return True
    data = get(url, binary=True)
    if not data or not data[:5] == b"%PDF-":
        return False
    dest.write_bytes(data)
    time.sleep(0.5)
    return True


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    out = Path(ap.parse_args().out)
    fuentes = []

    # 1) Biblia católica K'iche'
    d = out / "biblia_catolica"
    d.mkdir(parents=True, exist_ok=True)
    portada = get(BIBLIA) or ""
    secciones = sorted(set(re.findall(r'href="([a-z_]+\.htm)"', portada)) - {"index.htm", "faqs.htm"})
    pdfs = set()
    for s in secciones:
        pdfs |= set(re.findall(r'href="([^"]+\.pdf)"', get(BIBLIA + s) or "", re.I))
    print(f"Biblia K'iche': {len(pdfs)} PDF")
    for p in sorted(pdfs):
        url = urllib.parse.urljoin(BIBLIA, p)
        dest = d / Path(urllib.parse.urlparse(url).path).name
        if bajar(url, dest):
            fuentes.append({"archivo": f"biblia_catolica/{dest.name}", "url": url, "coleccion": "biblia_catolica",
                            "titulo": "Ri Tyoxlaj Wuj (Biblia católica en K'iche'): " + dest.stem.replace("BKiche-", "").replace("BKiche_", ""),
                            "autor": "Conferencia Episcopal de Guatemala, Pastoral K'iche'"})

    # 2) UNM K'iche' Maya Oral History Project
    d = out / "unm_historia_oral"
    d.mkdir(parents=True, exist_ok=True)
    items = set()
    for i in range(1, 20):
        pag = get(UNM + ("index.html" if i == 1 else f"index.{i}.html"))
        if not pag:
            break
        nuevos = set(re.findall(r'href="(https://digitalrepository\.unm\.edu/laii_kichemaya/\d+)/?"', pag))
        if not nuevos - items:
            break
        items |= nuevos
    print(f"UNM historia oral: {len(items)} registros")
    for it in sorted(items, key=lambda x: int(x.rsplit("/", 1)[1])):
        pag = get(it + "/") or ""
        m = re.search(r'href="([^"]*viewcontent\.cgi\?article=\d+[^"]*)"', pag)
        if not m:
            continue
        titulo = re.search(r'<meta name="bepress_citation_title" content="([^"]+)"', pag)
        autores = re.findall(r'<meta name="bepress_citation_author" content="([^"]+)"', pag)
        dest = d / f"unm_{it.rsplit('/', 1)[1]}.pdf"
        if bajar(html.unescape(m.group(1)), dest):
            fuentes.append({"archivo": f"unm_historia_oral/{dest.name}", "url": it, "coleccion": "unm_historia_oral",
                            "titulo": html.unescape(titulo.group(1)) if titulo else dest.stem,
                            "autor": "; ".join(html.unescape(a) for a in autores) or "K'iche' Maya Oral History Project (UNM)"})

    # 3) Fuentes sueltas
    for url, col, titulo, autor in SUELTOS:
        d = out / col
        d.mkdir(parents=True, exist_ok=True)
        dest = d / Path(urllib.parse.urlparse(url).path).name
        if bajar(url, dest):
            fuentes.append({"archivo": f"{col}/{dest.name}", "url": url, "coleccion": col, "titulo": titulo, "autor": autor})

    with open(out / "fuentes.jsonl", "w", encoding="utf-8") as f:
        for r in fuentes:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"Listo: {len(fuentes)} archivos en {out}")


if __name__ == "__main__":
    main()
