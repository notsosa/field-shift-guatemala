"""Descarga suelo (ISRIC SoilGrids 2.0) y cobertura del suelo (ESA WorldCover 2021) para la parcela.

1. SoilGrids vía WCS: textura, densidad, carbono, pH, fragmentos y agua a 33 y 1500 kPa
   en seis profundidades. Calcula el agua disponible total (ADT) de 0–100 cm.
2. ESA WorldCover 10 m v200 (2021): recorte alrededor del punto y proporción de clases.

Uso (desde la raíz del repo):
    .venv/Scripts/python scripts/descargar_suelo_cobertura.py
    .venv/Scripts/python scripts/descargar_suelo_cobertura.py --lat 14.80 --lon -89.54 --nombre chiquimula

Requiere: pip install numpy rasterio truststore
Licencias: SoilGrids CC BY 4.0 (ISRIC) · WorldCover CC BY 4.0 (ESA/VITO).
"""

import argparse
import csv
import json
import math
import os
import sys
import tempfile
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import rasterio
import truststore
from rasterio.io import MemoryFile
from rasterio.windows import from_bounds

truststore.inject_into_ssl()

RAIZ = Path(__file__).resolve().parent.parent
WCS = "https://maps.isric.org/mapserv"
EPSG4326 = "http://www.opengis.net/def/crs/EPSG/0/4326"
PROFUNDIDADES = [("0-5cm", 0, 5), ("5-15cm", 5, 15), ("15-30cm", 15, 30), ("30-60cm", 30, 60), ("60-100cm", 60, 100), ("100-200cm", 100, 200)]
# propiedad: (factor para unidades convencionales, unidad convencional)
PROPIEDADES = {
    "clay": (10, "%"), "sand": (10, "%"), "silt": (10, "%"),
    "bdod": (100, "g/cm³"), "soc": (10, "g/kg"), "phh2o": (10, "pH"),
    "cfvo": (10, "% vol"), "wv0033": (1000, "m³/m³"), "wv1500": (1000, "m³/m³"),
}
WORLDCOVER = "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{tile}_Map.tif"
CLASES = {10: "Árboles", 20: "Arbustos", 30: "Pastizal", 40: "Cultivos", 50: "Construido", 60: "Suelo desnudo o poca vegetación",
          70: "Nieve y hielo", 80: "Agua permanente", 90: "Humedal herbáceo", 95: "Manglar", 100: "Musgo y liquen"}


def soilgrids_valor(propiedad, profundidad, lat, lon, r=0.01):
    consulta = urllib.parse.urlencode([
        ("map", f"/map/{propiedad}.map"), ("SERVICE", "WCS"), ("VERSION", "2.0.1"), ("REQUEST", "GetCoverage"),
        ("COVERAGEID", f"{propiedad}_{profundidad}_mean"), ("FORMAT", "image/tiff"),
        ("SUBSET", f"long({lon - r},{lon + r})"), ("SUBSET", f"lat({lat - r},{lat + r})"),
        ("SUBSETTINGCRS", EPSG4326), ("OUTPUTCRS", EPSG4326),
    ])
    with urllib.request.urlopen(f"{WCS}?{consulta}", timeout=180) as respuesta:
        contenido = respuesta.read()
    with MemoryFile(contenido) as mem, mem.open() as src:
        datos = src.read(1).astype("float64")
        validos = datos[(datos != src.nodata) & (datos > 0)] if src.nodata is not None else datos[datos > 0]
        centro = float(next(src.sample([(lon, lat)]))[0])
    return centro, (float(validos.mean()) if validos.size else None)


def suelo(args):
    filas = []
    for nombre_prof, arriba, abajo in PROFUNDIDADES:
        fila = {"profundidad": nombre_prof, "desde_cm": arriba, "hasta_cm": abajo}
        for propiedad, (factor, _) in PROPIEDADES.items():
            print(f"SoilGrids {propiedad} {nombre_prof}...")
            centro, media = soilgrids_valor(propiedad, nombre_prof, args.lat, args.lon)
            valor = centro if centro > 0 else media
            fila[propiedad] = None if valor is None else round(valor / factor, 4)
        filas.append(fila)

    # Agua disponible total (FAO-56): 1000 × (θ_CC − θ_PMP) × espesor, sumando capas hasta 100 cm.
    adt = 0.0
    for fila in filas:
        if fila["hasta_cm"] <= 100 and fila["wv0033"] is not None and fila["wv1500"] is not None:
            adt += 1000 * (fila["wv0033"] - fila["wv1500"]) * (fila["hasta_cm"] - fila["desde_cm"]) / 100
    carpeta = RAIZ / "datos" / "suelo"
    carpeta.mkdir(parents=True, exist_ok=True)
    salida = carpeta / f"{args.nombre}_soilgrids.csv"
    with open(salida, "w", newline="", encoding="utf-8") as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=list(filas[0]))
        escritor.writeheader()
        escritor.writerows(filas)
    meta = {
        "fuente": "ISRIC SoilGrids 2.0, WCS (media de la predicción, celda de 250 m)",
        "documentacion": "https://docs.isric.org/globaldata/soilgrids/",
        "licencia": "CC BY 4.0",
        "punto": {"lat": args.lat, "lon": args.lon, "nombre": args.nombre},
        "descargado_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "unidades": {p: u for p, (_, u) in PROPIEDADES.items()},
        "agua_disponible_total_0_100cm_mm": round(adt, 1),
        "notas": [
            "Valor de la celda del punto; si no hay dato (por ejemplo, zona urbana) se usa la media de las celdas válidas en ±0.01°.",
            "wv0033 ≈ capacidad de campo y wv1500 ≈ punto de marchitez permanente. Son estimaciones de modelo con incertidumbre; contrastar con análisis de suelo.",
            "El ADT supone raíces hasta 100 cm; para cada cultivo usar su profundidad radicular efectiva (FAO-56).",
        ],
    }
    (carpeta / f"{args.nombre}_soilgrids.meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    return meta


def tile_worldcover(lat, lon):
    s, w = math.floor(lat / 3) * 3, math.floor(lon / 3) * 3
    return f"{'N' if s >= 0 else 'S'}{abs(s):02d}{'E' if w >= 0 else 'W'}{abs(w):03d}"


def cobertura(args):
    url = WORLDCOVER.format(tile=tile_worldcover(args.lat, args.lon))
    temporal = Path(tempfile.gettempdir()) / Path(url).name
    if not temporal.exists():
        print("WorldCover: descargando mosaico de 3° (~80 MB)...")
        with urllib.request.urlopen(url, timeout=600) as r, open(temporal, "wb") as f:
            while bloque := r.read(1 << 20):
                f.write(bloque)
    r = args.radio_cobertura
    carpeta = RAIZ / "datos" / "cobertura"
    carpeta.mkdir(parents=True, exist_ok=True)
    salida = carpeta / f"{args.nombre}_worldcover2021.tif"
    with rasterio.open(temporal) as src:
        ventana = from_bounds(args.lon - r, args.lat - r, args.lon + r, args.lat + r, src.transform)
        clases = src.read(1, window=ventana)
        transform = src.window_transform(ventana)
        perfil = src.profile.copy()
        perfil.update(width=clases.shape[1], height=clases.shape[0], transform=transform, compress="deflate", tiled=False)
        perfil.pop("blockxsize", None)
        perfil.pop("blockysize", None)
        colores = src.colormap(1) if src.colorinterp else None
    with rasterio.open(salida, "w", **perfil) as dst:
        dst.write(clases, 1)
        if colores:
            dst.write_colormap(1, colores)
    os.remove(temporal)

    def proporciones(arreglo):
        valores, cuentas = np.unique(arreglo[arreglo > 0], return_counts=True)
        total = cuentas.sum()
        return {CLASES.get(int(v), str(v)): round(100 * c / total, 1) for v, c in sorted(zip(valores, cuentas), key=lambda x: -x[1])}

    fila, col = rasterio.transform.rowcol(transform, args.lon, args.lat)
    return {
        "fuente": "ESA WorldCover 10 m 2021 v200",
        "documentacion": "https://esa-worldcover.org/en",
        "licencia": "CC BY 4.0 · © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium",
        "url_origen": url,
        "archivo": salida.name,
        "recorte_grados": [args.lon - r, args.lat - r, args.lon + r, args.lat + r],
        "clase_en_el_punto": CLASES.get(int(clases[fila, col])),
        "proporcion_clases_recorte_pct": proporciones(clases),
        "descargado_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lat", type=float, default=14.80)
    parser.add_argument("--lon", type=float, default=-89.54)
    parser.add_argument("--nombre", default="chiquimula")
    parser.add_argument("--radio-cobertura", type=float, default=0.1, help="medio lado del recorte WorldCover en grados")
    args = parser.parse_args()

    meta_suelo = suelo(args)
    print("Agua disponible total 0–100 cm:", meta_suelo["agua_disponible_total_0_100cm_mm"], "mm")
    meta_cob = cobertura(args)
    (RAIZ / "datos" / "cobertura" / f"{args.nombre}_worldcover2021.meta.json").write_text(
        json.dumps(meta_cob, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Clase en el punto:", meta_cob["clase_en_el_punto"])
    print("Proporciones:", meta_cob["proporcion_clases_recorte_pct"])


if __name__ == "__main__":
    main()
