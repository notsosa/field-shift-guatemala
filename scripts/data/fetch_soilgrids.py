"""Fetch SoilGrids 2.0 soil properties for the three pilots through the ISRIC WCS (no account) and
depth-weight them to 0-100 cm. Output: scripts/data/soilgrids_pilots.json (read by build_pilot_soil.mjs).

Layers (coverage id {layer}_{depth}_mean): clay, sand, wv0033 (water content at 33 kPa = field capacity),
wv1500 (at 1500 kPa = permanent wilting point). Depths 0-5, 5-15, 15-30, 30-60, 60-100 cm.

Unit conversion factors (SoilGrids "conversion factor" column, ISRIC docs: https://docs.isric.org/globaldata/soilgrids/):
    clay, sand : mapped g/kg  -> divide by 10   -> %
    wv0033, wv1500 : mapped 10^-3 cm3/cm3 -> divide by 1000 -> m3/m3
Value 0 is the no-data of these coverages (masked cells, e.g. urban). Each layer takes the pixel at the point
(request box +-0.01 deg, ~2.4 km pixels of 0.0024 deg) when valid; otherwise the mean of the valid pixels in the box
(the teammate script scripts/descargar_suelo_cobertura.py on origin/main does the same). The method is recorded
per layer. The 0-100 cm value is the thickness-weighted mean (5, 10, 15, 30, 40 cm).

Usage (data venv): python scripts/data/fetch_soilgrids.py [--points chiquimula jutiapa sanmartin]
"""

import argparse
import io
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import tifffile
import truststore

truststore.inject_into_ssl()

ROOT = Path(__file__).resolve().parent.parent.parent
POINTS = ROOT / "scripts" / "emulator" / "points.json"
OUT = ROOT / "scripts" / "data" / "soilgrids_pilots.json"
WCS = "https://maps.isric.org/mapserv"
EPSG4326 = "http://www.opengis.net/def/crs/EPSG/0/4326"
PILOTS = ["chiquimula", "jutiapa", "sanmartin"]
DEPTHS = [("0-5cm", 0, 5), ("5-15cm", 5, 15), ("15-30cm", 15, 30), ("30-60cm", 30, 60), ("60-100cm", 60, 100)]
FACTORS = {"clay": 10, "sand": 10, "wv0033": 1000, "wv1500": 1000}  # divide the mapped value by this


def get_pixel(layer, depth, lat, lon, r=0.01, tries=4):
    q = urllib.parse.urlencode([
        ("map", f"/map/{layer}.map"), ("SERVICE", "WCS"), ("VERSION", "2.0.1"), ("REQUEST", "GetCoverage"),
        ("COVERAGEID", f"{layer}_{depth}_mean"), ("FORMAT", "image/tiff"),
        ("SUBSET", f"long({lon - r},{lon + r})"), ("SUBSET", f"lat({lat - r},{lat + r})"),
        ("SUBSETTINGCRS", EPSG4326), ("OUTPUTCRS", EPSG4326),
    ])
    last = None
    for attempt in range(1, tries + 1):
        try:
            with urllib.request.urlopen(f"{WCS}?{q}", timeout=120) as resp:
                body = resp.read()
            with tifffile.TiffFile(io.BytesIO(body)) as tf:
                page = tf.pages[0]
                arr = page.asarray().astype("float64")
                scale = page.tags["ModelPixelScaleTag"].value
                tie = page.tags["ModelTiepointTag"].value
            col = int((lon - tie[3]) / scale[0])
            row = int((tie[4] - lat) / scale[1])
            valid = arr[arr > 0]
            if 0 <= row < arr.shape[0] and 0 <= col < arr.shape[1] and arr[row, col] > 0:
                return float(arr[row, col]), "point pixel", int(valid.size)
            if valid.size:
                return float(valid.mean()), f"mean of {valid.size} valid pixels in +-{r} deg", int(valid.size)
            return None, "no valid pixel", 0
        except Exception as e:
            last = e
            time.sleep(5 * attempt)
    raise RuntimeError(f"{layer} {depth}: {last}")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--points", nargs="*", default=PILOTS)
    args = ap.parse_args()
    pts = [p for p in json.loads(POINTS.read_text(encoding="utf-8")) if p["id"] in args.points]
    result = {
        "source": "ISRIC SoilGrids 2.0 WCS (mean prediction, 250 m native), CC BY 4.0",
        "url": "https://maps.isric.org/",
        "factors": {k: f"mapped value / {v}" for k, v in FACTORS.items()},
        "downloadedUtc": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "points": {},
    }
    for p in pts:
        layers = {}
        try:
            for layer, factor in FACTORS.items():
                rows = []
                for name, top, bottom in DEPTHS:
                    raw, method, nvalid = get_pixel(layer, name, p["lat"], p["lon"])
                    rows.append({"depth": name, "topCm": top, "bottomCm": bottom, "mapped": raw,
                                 "value": None if raw is None else round(raw / factor, 4), "method": method})
                    print(p["id"], layer, name, rows[-1]["value"], method, flush=True)
                layers[layer] = rows
        except Exception as e:
            print(f"{p['id']}: FAILED ({e}); no soil for this pilot", file=sys.stderr)
            result["points"][p["id"]] = {"lat": p["lat"], "lon": p["lon"], "error": str(e)}
            continue
        weighted = {}
        for layer, rows in layers.items():
            if any(r["value"] is None for r in rows):
                weighted[layer] = None
                continue
            w = sum((r["bottomCm"] - r["topCm"]) * r["value"] for r in rows) / 100
            weighted[layer] = round(w, 4)
        result["points"][p["id"]] = {"lat": p["lat"], "lon": p["lon"], "layers": layers, "weighted0to100cm": weighted}
        print(p["id"], "weighted 0-100 cm", weighted, flush=True)
    OUT.write_text(json.dumps(result, indent=1), encoding="utf-8")
    print("Wrote", OUT)


if __name__ == "__main__":
    main()
