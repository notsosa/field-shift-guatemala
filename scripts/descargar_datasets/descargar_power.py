"""Descarga la serie diaria de NASA POWER para una parcela.

Uso:
    py scripts/descargar_power.py
    py scripts/descargar_power.py --lat 14.80 --lon -89.54 --nombre chiquimula --inicio 2001-01-01 --fin 2025-12-31

Guarda en datos/power/:
    <nombre>_power_diario_<inicio>_<fin>.json  respuesta original de la API
    <nombre>_power_diario_<inicio>_<fin>.csv   tabla limpia (un día por fila, vacíos en lugar de -999)
    <nombre>_power_diario_<inicio>_<fin>.meta.json  procedencia, unidades y resumen de completitud

Solo usa la biblioteca estándar de Python (3.8+). La API de POWER no requiere cuenta.
Documentación: https://power.larc.nasa.gov/docs/services/api/temporal/daily/
"""

import argparse
import csv
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

API_URL = "https://power.larc.nasa.gov/api/temporal/daily/point"

# Variables necesarias para ET0 FAO-56 (Penman-Monteith) y el balance hídrico.
PARAMETROS = [
    "T2M",                # temperatura media a 2 m (°C)
    "T2M_MAX",            # temperatura máxima a 2 m (°C)
    "T2M_MIN",            # temperatura mínima a 2 m (°C)
    "T2MDEW",             # punto de rocío a 2 m (°C)
    "RH2M",               # humedad relativa a 2 m (%)
    "WS2M",               # viento a 2 m (m/s)
    "ALLSKY_SFC_SW_DWN",  # radiación solar en superficie (MJ/m²/día en comunidad AG)
    "CLRSKY_SFC_SW_DWN",  # radiación de cielo despejado (MJ/m²/día en comunidad AG)
    "PRECTOTCORR",        # precipitación corregida (mm/día)
    "PS",                 # presión superficial (kPa)
    # Humedad del suelo de MERRA-2 servida por POWER (fracción 0–1 de saturación, sin unidad).
    "GWETTOP",            # humedad superficial del suelo (0–5 cm)
    "GWETROOT",           # humedad de la zona de raíces (0–100 cm)
    "GWETPROF",           # humedad del perfil completo (superficie hasta lecho rocoso)
    "EVLAND",             # evaporación desde tierra (mm/día)
]

VALOR_FALTANTE = -999.0

# Parcela piloto PROVISIONAL: cabecera de Chiquimula (Corredor Seco).
# Es un supuesto del equipo hasta elegir la finca real; cambiar con --lat/--lon.
LAT_PILOTO = 14.80
LON_PILOTO = -89.54
NOMBRE_PILOTO = "chiquimula"


def construir_url(lat, lon, inicio, fin):
    consulta = {
        "parameters": ",".join(PARAMETROS),
        "community": "AG",
        "longitude": f"{lon:.4f}",
        "latitude": f"{lat:.4f}",
        "start": inicio.replace("-", ""),
        "end": fin.replace("-", ""),
        "format": "JSON",
        "time-standard": "LST",
    }
    return f"{API_URL}?{urllib.parse.urlencode(consulta)}"


def descargar(url, intentos=3, espera_s=300):
    ultimo_error = None
    for intento in range(1, intentos + 1):
        try:
            peticion = urllib.request.Request(url, headers={"User-Agent": "field-shift-guatemala/0.1"})
            with urllib.request.urlopen(peticion, timeout=espera_s) as respuesta:
                return json.loads(respuesta.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            cuerpo = error.read().decode("utf-8", errors="replace")[:500]
            ultimo_error = f"HTTP {error.code}: {cuerpo}"
            if 400 <= error.code < 500:
                break  # error en la consulta: reintentar no ayuda
        except (urllib.error.URLError, TimeoutError) as error:
            ultimo_error = str(error)
        print(f"Intento {intento} falló: {ultimo_error}", file=sys.stderr)
    raise RuntimeError(f"No se pudo descargar POWER: {ultimo_error}")


def a_filas(datos):
    serie = datos["properties"]["parameter"]
    fechas = sorted(next(iter(serie.values())).keys())
    filas = []
    for fecha in fechas:
        fila = {"fecha": f"{fecha[:4]}-{fecha[4:6]}-{fecha[6:]}"}
        for parametro in PARAMETROS:
            valor = serie.get(parametro, {}).get(fecha)
            fila[parametro] = None if valor is None or valor == VALOR_FALTANTE else valor
        filas.append(fila)
    return filas


def resumir(filas):
    faltantes = {p: sum(1 for f in filas if f[p] is None) for p in PARAMETROS}
    lluvia_anual = {}
    for fila in filas:
        if fila["PRECTOTCORR"] is not None:
            anio = fila["fecha"][:4]
            lluvia_anual[anio] = lluvia_anual.get(anio, 0.0) + fila["PRECTOTCORR"]
    return {
        "dias": len(filas),
        "primer_dia": filas[0]["fecha"] if filas else None,
        "ultimo_dia": filas[-1]["fecha"] if filas else None,
        "dias_faltantes_por_parametro": faltantes,
        "lluvia_anual_mm": {a: round(v, 1) for a, v in sorted(lluvia_anual.items())},
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--lat", type=float, default=LAT_PILOTO)
    parser.add_argument("--lon", type=float, default=LON_PILOTO)
    parser.add_argument("--nombre", default=NOMBRE_PILOTO, help="identificador corto de la parcela")
    parser.add_argument("--inicio", default="2001-01-01", help="AAAA-MM-DD")
    parser.add_argument("--fin", default="2025-12-31", help="AAAA-MM-DD")
    parser.add_argument("--salida", default=str(Path(__file__).resolve().parent.parent / "datos" / "power"))
    args = parser.parse_args()

    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")  # acentos legibles en la consola de Windows

    url =construir_url(args.lat, args.lon, args.inicio, args.fin)
    print(f"Descargando NASA POWER diario para {args.nombre} ({args.lat}, {args.lon}), {args.inicio} a {args.fin}...")
    datos = descargar(url)

    filas = a_filas(datos)
    resumen = resumir(filas)

    carpeta = Path(args.salida)
    carpeta.mkdir(parents=True, exist_ok=True)
    base = carpeta / f"{args.nombre}_power_diario_{args.inicio.replace('-', '')}_{args.fin.replace('-', '')}"

    base.with_suffix(".json").write_text(json.dumps(datos, ensure_ascii=False), encoding="utf-8")

    with open(base.with_suffix(".csv"), "w", newline="", encoding="utf-8") as archivo:
        escritor = csv.DictWriter(archivo, fieldnames=["fecha"] + PARAMETROS)
        escritor.writeheader()
        for fila in filas:
            escritor.writerow({k: ("" if v is None else v) for k, v in fila.items()})

    coordenadas = datos.get("geometry", {}).get("coordinates", [])
    parametros_info = datos.get("parameters", {})
    meta = {
        "fuente": "NASA POWER, API temporal diaria por punto, comunidad AG",
        "documentacion": "https://power.larc.nasa.gov/docs/services/api/temporal/daily/",
        "url_consulta": url,
        "descargado_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "parcela": {
            "nombre": args.nombre,
            "lat_solicitada": args.lat,
            "lon_solicitada": args.lon,
            "supuesto": "Coordenada provisional del equipo hasta elegir la finca piloto." if (args.lat, args.lon) == (LAT_PILOTO, LON_PILOTO) else None,
        },
        "elevacion_celda_m": coordenadas[2] if len(coordenadas) > 2 else None,
        "unidades": {p: parametros_info.get(p, {}).get("units") for p in PARAMETROS},
        "nombres_largos": {p: parametros_info.get(p, {}).get("longname") for p in PARAMETROS},
        "notas": [
            "Los valores -999 de POWER se guardan vacíos en el CSV.",
            "POWER representa una celda regional (meteorología MERRA-2 ~0.5° x 0.625°, radiación CERES ~1°), no la parcela.",
            "Contrastar lluvia con pluviómetro o estación INSIVUMEH antes de usarla en una decisión.",
            "GWETTOP/GWETROOT/GWETPROF son grado de saturación (0 = seco, 1 = saturado) del modelo MERRA-2, no contenido volumétrico en m³/m³; para comparar con SMAP o con un sensor de campo hace falta la porosidad del suelo.",
            "La elevación de la celda puede diferir mucho de la parcela; corregir presión y temperatura si se usa la elevación real.",
        ],
        "header_api": datos.get("header", {}),
        "resumen": resumen,
    }
    base.with_suffix(".meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"Días descargados: {resumen['dias']} ({resumen['primer_dia']} a {resumen['ultimo_dia']})")
    print(f"Elevación de la celda: {meta['elevacion_celda_m']} m")
    print("Días faltantes por parámetro:", resumen["dias_faltantes_por_parametro"])
    print("Archivos:")
    for sufijo in (".json", ".csv", ".meta.json"):
        print("  ", base.with_suffix(sufijo))


if __name__ == "__main__":
    main()
