"""Descarga datos de JAXA Earth API (sin cuenta) para la parcela.

1. ALOS World 3D 30 m (AW3D30 v4.1, DSM): recorte alrededor del punto y pendiente.
2. GSMaP v6 calibrado con pluviómetros, mensual 2001–2025, en la celda del punto.

Uso (desde la raíz del repo):
    .venv/Scripts/python scripts/descargar_jaxa.py
    .venv/Scripts/python scripts/descargar_jaxa.py --lat 14.80 --lon -89.54 --nombre chiquimula

Requiere: pip install numpy rasterio truststore
Términos de uso de JAXA: https://earth.jaxa.jp/en/data/policy/
"""

import argparse
import calendar
import csv
import json
import math
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import os
import tempfile
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import rasterio
import truststore
from rasterio.windows import from_bounds

# El servidor de JAXA no envía la cadena de certificados completa y GDAL (schannel) no puede
# leerlo en remoto. Se descarga cada archivo con el almacén de certificados del sistema.
truststore.inject_into_ssl()

RAIZ = Path(__file__).resolve().parent.parent
JE = "https://s3.ap-northeast-1.wasabisys.com/je-pds/cog/v1"
AW3D30 = "JAXA.EORC_ALOS.PRISM_AW3D30.v4.1_global"
GSMAP = "JAXA.EORC_GSMaP_standard.Gauge.00Z-23Z.v6_monthly"


def bajar(url, destino):
    with urllib.request.urlopen(url, timeout=300) as r, open(destino, "wb") as f:
        while bloque := r.read(1 << 20):
            f.write(bloque)
    return destino


def leer_json(url):
    with urllib.request.urlopen(url, timeout=120) as r:
        return json.load(r)


def borde(valor, paso):
    return math.floor(valor / paso) * paso


def etiqueta_lon(v):
    return f"{'W' if v < 0 else 'E'}{abs(v):06.2f}"


def etiqueta_lat(v):
    return f"{'S' if v < 0 else 'N'}{abs(v):05.2f}"


def url_aw3d30(lat, lon):
    """Mosaico de 1° del nivel más fino (3)."""
    w, s = borde(lon, 1), borde(lat, 1)
    carpeta = f"{JE}/{AW3D30}/2024-04/3/{etiqueta_lon(w)}-{etiqueta_lon(w + 1)}"
    item = leer_json(f"{carpeta}/{etiqueta_lat(s)}-{etiqueta_lat(s + 1)}.json")
    return f"{carpeta}/{item['assets']['DSM']['href'][2:]}"


def url_gsmap(anio, mes, lat, lon):
    """Mosaico de 90° × 90° del nivel 1."""
    w, s = borde(lon, 90), borde(lat, 90)
    lon_txt = f"{etiqueta_lon(w)}-{etiqueta_lon(w + 90)}"
    nombre = f"{etiqueta_lon(w)}-{etiqueta_lat(s)}-{etiqueta_lon(w + 90)}-{etiqueta_lat(s + 90)}-PRECIP.tiff"
    return f"{JE}/{GSMAP}/{anio:04d}-{mes:02d}/1/{lon_txt}/{nombre}"


def relieve(args, carpeta):
    url = url_aw3d30(args.lat, args.lon)
    r = args.radio_dem
    temporal = bajar(url, Path(tempfile.gettempdir()) / Path(url).name)
    with rasterio.open(temporal) as src:
        ventana = from_bounds(args.lon - r, args.lat - r, args.lon + r, args.lat + r, src.transform)
        dsm = src.read(1, window=ventana)
        transform = src.window_transform(ventana)
        perfil = src.profile.copy()
        perfil.update(width=dsm.shape[1], height=dsm.shape[0], transform=transform, compress="deflate", tiled=False)
        perfil.pop("blockxsize", None)
        perfil.pop("blockysize", None)
    salida = carpeta / f"{args.nombre}_aw3d30_dsm.tif"
    with rasterio.open(salida, "w", **perfil) as dst:
        dst.write(dsm, 1)

    # Pendiente con diferencias centrales; el paso en metros depende de la latitud.
    z = dsm.astype("float64")
    dy = abs(transform.e) * 111_320.0
    dx = transform.a * 111_320.0 * math.cos(math.radians(args.lat))
    gy, gx = np.gradient(z, dy, dx)
    pendiente = 100.0 * np.hypot(gx, gy)
    fila, col = rasterio.transform.rowcol(transform, args.lon, args.lat)
    vecindad = pendiente[max(fila - 1, 0):fila + 2, max(col - 1, 0):col + 2]
    os.remove(temporal)
    return {
        "archivo": salida.name,
        "url_origen": url,
        "recorte_grados": [args.lon - r, args.lat - r, args.lon + r, args.lat + r],
        "elevacion_punto_m": float(z[fila, col]),
        "pendiente_punto_pct_3x3": round(float(vecindad.mean()), 1),
        "pendiente_recorte_pct": {
            "p25": round(float(np.percentile(pendiente, 25)), 1),
            "mediana": round(float(np.median(pendiente)), 1),
            "p75": round(float(np.percentile(pendiente, 75)), 1),
        },
        "nota": "AW3D30 es un modelo de superficie (DSM): incluye árboles y edificios. En la cabecera urbana la pendiente refleja techos y calles.",
    }


def muestrear_mes(anio, mes, lat, lon):
    url = url_gsmap(anio, mes, lat, lon)
    temporal = Path(tempfile.gettempdir()) / f"gsmap_{anio}{mes:02d}.tif"
    try:
        bajar(url, temporal)
        with rasterio.open(temporal) as src:
            valor = float(next(src.sample([(lon, lat)]))[0])
            faltante = valor < 0 or (src.nodata is not None and valor == src.nodata)
    except Exception as error:  # mes no publicado o error de red
        print(f"  {anio}-{mes:02d}: {error}", file=sys.stderr)
        faltante, valor = True, None
    finally:
        if temporal.exists():
            os.remove(temporal)
    dias = calendar.monthrange(anio, mes)[1]
    mm = None if faltante else round(valor * 24 * dias, 1)  # mm/h promedio → mm/mes
    return {"mes": f"{anio:04d}-{mes:02d}", "gsmap_mm_mes": mm}


def lluvia_mensual(args, carpeta):
    meses = [(a, m) for a in range(args.anio_inicio, args.anio_fin + 1) for m in range(1, 13)]
    print(f"GSMaP: {len(meses)} meses (cada archivo pesa ~2 MB)...")
    with ThreadPoolExecutor(max_workers=8) as pool:
        filas = list(pool.map(lambda am: muestrear_mes(am[0], am[1], args.lat, args.lon), meses))
    salida = carpeta / f"{args.nombre}_gsmap_mensual_{args.anio_inicio}_{args.anio_fin}.csv"
    with open(salida, "w", newline="", encoding="utf-8") as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=["mes", "gsmap_mm_mes"])
        escritor.writeheader()
        escritor.writerows({k: ("" if v is None else v) for k, v in f.items()} for f in filas)
    anual = {}
    for f in filas:
        if f["gsmap_mm_mes"] is not None:
            anual[f["mes"][:4]] = round(anual.get(f["mes"][:4], 0.0) + f["gsmap_mm_mes"], 1)
    return {
        "archivo": salida.name,
        "producto": GSMAP,
        "unidad_original": "mm/h (tasa media del mes); convertida a mm/mes × 24 × días",
        "meses": len(filas),
        "meses_faltantes": sum(1 for f in filas if f["gsmap_mm_mes"] is None),
        "lluvia_anual_mm": anual,
    }


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lat", type=float, default=14.80)
    parser.add_argument("--lon", type=float, default=-89.54)
    parser.add_argument("--nombre", default="chiquimula")
    parser.add_argument("--radio-dem", type=float, default=0.05, help="medio lado del recorte DEM en grados")
    parser.add_argument("--anio-inicio", type=int, default=2001)
    parser.add_argument("--anio-fin", type=int, default=2025)
    args = parser.parse_args()

    meta = {
        "fuente": "JAXA Earth API (STAC + COG, sin registro)",
        "terminos": "https://earth.jaxa.jp/en/data/policy/",
        "punto": {"lat": args.lat, "lon": args.lon, "nombre": args.nombre},
        "descargado_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    carpeta_relieve = RAIZ / "datos" / "relieve"
    carpeta_relieve.mkdir(parents=True, exist_ok=True)
    meta["aw3d30"] = relieve(args, carpeta_relieve)
    print("AW3D30:", meta["aw3d30"]["elevacion_punto_m"], "m,", meta["aw3d30"]["pendiente_punto_pct_3x3"], "% de pendiente")
    (carpeta_relieve / f"{args.nombre}_aw3d30.meta.json").write_text(
        json.dumps({k: meta[k] for k in ("fuente", "terminos", "punto", "descargado_utc", "aw3d30")}, ensure_ascii=False, indent=2),
        encoding="utf-8")

    carpeta_lluvia = RAIZ / "datos" / "lluvia"
    carpeta_lluvia.mkdir(parents=True, exist_ok=True)
    meta["gsmap"] = lluvia_mensual(args, carpeta_lluvia)
    (carpeta_lluvia / f"{args.nombre}_gsmap_mensual.meta.json").write_text(
        json.dumps({k: meta[k] for k in ("fuente", "terminos", "punto", "descargado_utc", "gsmap")}, ensure_ascii=False, indent=2),
        encoding="utf-8")
    print("GSMaP: meses faltantes", meta["gsmap"]["meses_faltantes"])


if __name__ == "__main__":
    main()
