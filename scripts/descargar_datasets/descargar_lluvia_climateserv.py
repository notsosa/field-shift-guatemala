"""Descarga lluvia diaria CHIRPS e IMERG para la parcela mediante ClimateSERV (NASA–USAID SERVIR).

Sirve para contrastar la lluvia de NASA POWER (tarea T07). No requiere cuenta.

Uso (desde la raíz del repo, con el entorno virtual):
    .venv/Scripts/python scripts/descargar_lluvia_climateserv.py
    .venv/Scripts/python scripts/descargar_lluvia_climateserv.py --lat 14.80 --lon -89.54 --nombre chiquimula

Requiere: pip install climateserv truststore

ClimateSERV promedia las celdas que tocan el polígono. Se usa un cuadro de ±0.03° (~3 km)
alrededor del punto, que cae dentro de una o pocas celdas de CHIRPS (0.05°) e IMERG (0.1°).
"""

import argparse
import csv
import json
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import truststore

truststore.inject_into_ssl()  # usa el almacén de certificados del sistema operativo

import climateserv.api as climateserv  # noqa: E402

DATASETS = {"chirps_mm": 0, "imerg_mm": 26}  # identificadores de ClimateSERV
RAIZ = Path(__file__).resolve().parent.parent


def pedir(dataset_id, inicio, fin, poligono, intentos=3):
    for intento in range(1, intentos + 1):
        respuesta = climateserv.request_data(dataset_id, "Average", inicio, fin, poligono, None, None, "memory_object")
        if respuesta and respuesta.get("data"):
            return respuesta["data"]
        print(f"  intento {intento} sin datos, reintentando...", file=sys.stderr)
        time.sleep(5)
    # Un año sin datos (por ejemplo, IMERG Final aún no publicado) no detiene la descarga.
    print(f"  AVISO: sin datos para dataset {dataset_id}, {inicio}–{fin}; se deja vacío", file=sys.stderr)
    return []


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lat", type=float, default=14.80)
    parser.add_argument("--lon", type=float, default=-89.54)
    parser.add_argument("--nombre", default="chiquimula")
    parser.add_argument("--anio-inicio", type=int, default=2001)
    parser.add_argument("--anio-fin", type=int, default=2025)
    parser.add_argument("--radio", type=float, default=0.03, help="medio lado del cuadro en grados")
    args = parser.parse_args()

    r = args.radio
    poligono = json.dumps([
        [args.lon - r, args.lat - r], [args.lon + r, args.lat - r],
        [args.lon + r, args.lat + r], [args.lon - r, args.lat + r], [args.lon - r, args.lat - r],
    ])

    serie = {}
    for columna, dataset_id in DATASETS.items():
        for anio in range(args.anio_inicio, args.anio_fin + 1):
            print(f"{columna} {anio}...", flush=True)
            for dia in pedir(dataset_id, f"01/01/{anio}", f"12/31/{anio}", poligono):
                valor = dia.get("value", {}).get("avg")
                fecha = f"{dia['year']:04d}-{dia['month']:02d}-{dia['day']:02d}"
                serie.setdefault(fecha, {})[columna] = None if valor is None or valor < 0 else round(valor, 3)

    carpeta = RAIZ / "datos" / "lluvia"
    carpeta.mkdir(parents=True, exist_ok=True)
    base = carpeta / f"{args.nombre}_lluvia_diaria_{args.anio_inicio}_{args.anio_fin}"
    with open(base.with_suffix(".csv"), "w", newline="", encoding="utf-8") as archivo:
        escritor = csv.writer(archivo)
        escritor.writerow(["fecha"] + list(DATASETS))
        for fecha in sorted(serie):
            escritor.writerow([fecha] + ["" if serie[fecha].get(c) is None else serie[fecha][c] for c in DATASETS])

    anual = {}
    for fecha, valores in serie.items():
        for c in DATASETS:
            if valores.get(c) is not None:
                anual.setdefault(c, {}).setdefault(fecha[:4], 0.0)
                anual[c][fecha[:4]] += valores[c]
    meta = {
        "fuente": "ClimateSERV (NASA–USAID SERVIR), operación Average sobre un polígono",
        "api": "https://climateserv.servirglobal.net/api/",
        "datasets": {
            "chirps_mm": "CHIRPS v2.0 diario, 0.05°, UCSB Climate Hazards Center (estaciones + satélite)",
            "imerg_mm": "GPM IMERG diario, 0.1°, NASA, servido por ClimateSERV (id 26)",
        },
        "poligono_lon_lat": json.loads(poligono),
        "descargado_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "unidades": "mm/día",
        "lluvia_anual_mm": {c: {a: round(v, 1) for a, v in sorted(d.items())} for c, d in anual.items()},
        "dias": len(serie),
        "dias_faltantes": {c: sum(1 for v in serie.values() if v.get(c) is None) for c in DATASETS},
    }
    base.with_suffix(".meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Listo:", base.with_suffix(".csv"))
    print("Faltantes:", meta["dias_faltantes"])


if __name__ == "__main__":
    main()
