"""Descarga capas del geoportal del MAGA (GeoServer WFS público) para la zona piloto.

Capas: cobertura vegetal y uso de la tierra 2025, capacidad de uso (USDA), taxonomía de suelos,
fisiografía, zonas de vida, amenaza de sequía, vulnerabilidad agropecuaria 2026,
afectaciones a cultivos 2024–2025 y límites municipales.

Uso (desde la raíz del repo):
    .venv/Scripts/python scripts/descargar_maga.py
    .venv/Scripts/python scripts/descargar_maga.py --bbox -90.0 14.3 -89.15 15.1 --nombre chiquimula

Requiere: pip install truststore
Servicio: https://geoportal.maga.gob.gt/geoserver/ows (WFS)
"""

import argparse
import json
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import truststore

truststore.inject_into_ssl()

RAIZ = Path(__file__).resolve().parent.parent
WFS = "https://geoportal.maga.gob.gt/geoserver/ows"

# capa: (archivo, usar recorte pequeño alrededor del punto)
CAPAS = {
    "COBERTURA_VEGETAL_USO_DE_LA_TIERRA:cobertura_vegetal_y_uso_de_la_tierra_2025": ("cobertura_uso_tierra_2025", True),
    "SUELOS:capacidad_de_uso_de_la_tierra_usda": ("capacidad_uso_tierra_usda", False),
    "SUELOS:taxonomia_de_suelos": ("taxonomia_suelos", False),
    "SUELOS:fisiografia": ("fisiografia", False),
    "CAPAS_TEMÁTICAS:zonas_de_vida": ("zonas_de_vida", False),
    "AGROCLIMA:amenaza_a_sequia": ("amenaza_sequia", False),
    "AGROCLIMA:MUY_ALTA_VULN_AGROP": ("vulnerabilidad_agropecuaria_2026_muy_alta", False),
    "AGROCLIMA:ALTA_VULN_AGROP": ("vulnerabilidad_agropecuaria_2026_alta", False),
    "AGROCLIMA:MEDIA_VULN_AGROP": ("vulnerabilidad_agropecuaria_2026_media", False),
    "AGROCLIMA:afectaciones_a_cultivos_2024": ("afectaciones_cultivos_2024", False),
    "AGROCLIMA:afectaciones_a_cultivos_2025": ("afectaciones_cultivos_2025", False),
    "CAPAS_TEMÁTICAS:limites_municipales": ("limites_municipales", False),
}


def descargar(capa, bbox):
    consulta = urllib.parse.urlencode({
        "service": "WFS", "version": "1.0.0", "request": "GetFeature", "typeName": capa,
        "outputFormat": "application/json", "srsName": "EPSG:4326",
        "bbox": ",".join(f"{v}" for v in bbox),  # WFS 1.0.0: lon/lat
    })
    with urllib.request.urlopen(f"{WFS}?{consulta}", timeout=600) as respuesta:
        return json.load(respuesta)


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--bbox", type=float, nargs=4, default=[-90.0, 14.3, -89.15, 15.1],
                        metavar=("OESTE", "SUR", "ESTE", "NORTE"), help="zona de estudio (departamento de Chiquimula por defecto)")
    parser.add_argument("--lat", type=float, default=14.80)
    parser.add_argument("--lon", type=float, default=-89.54)
    parser.add_argument("--radio", type=float, default=0.1, help="medio lado del recorte para capas pesadas")
    parser.add_argument("--nombre", default="chiquimula")
    args = parser.parse_args()

    carpeta = RAIZ / "datos" / "maga"
    carpeta.mkdir(parents=True, exist_ok=True)
    recorte = [args.lon - args.radio, args.lat - args.radio, args.lon + args.radio, args.lat + args.radio]
    resumen = {}
    for capa, (archivo, pesada) in CAPAS.items():
        bbox = recorte if pesada else args.bbox
        datos = descargar(capa, bbox)
        salida = carpeta / f"{args.nombre}_{archivo}.geojson"
        salida.write_text(json.dumps(datos, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
        atributos = sorted(datos["features"][0]["properties"]) if datos.get("features") else []
        resumen[archivo] = {"capa_wfs": capa, "bbox": bbox, "elementos": len(datos.get("features", [])), "atributos": atributos}
        print(f"{archivo}: {resumen[archivo]['elementos']} elementos")

    meta = {
        "fuente": "MAGA Guatemala, geoportal institucional (GeoServer WFS)",
        "servicio": WFS,
        "visor": "https://geoportal.maga.gob.gt/",
        "descargado_utc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "crs": "EPSG:4326",
        "notas": [
            "Las capas se recortan por caja envolvente: los polígonos que tocan la caja se descargan completos.",
            "La cobertura 2025 se limita a ±radio alrededor del punto por su tamaño.",
            "Consultar al MAGA (DIGEGR) la licencia de uso y redistribución antes de publicar derivados.",
        ],
        "capas": resumen,
    }
    (carpeta / f"{args.nombre}_maga.meta.json").write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
