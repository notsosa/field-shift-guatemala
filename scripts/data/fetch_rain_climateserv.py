"""Download daily IMERG (and CHIRPS) rain for the emulator points through ClimateSERV (NASA-USAID SERVIR).

No account or key. For every point in scripts/emulator/points.json it asks ClimateSERV for the "Average" of the
datasets over a box of +-0.03 deg around the point, one request per (point, dataset, calendar year), and caches
the raw result in scripts/emulator/cache_rain/{id}_{dataset}.json (gitignored). The cache file is rewritten after
every year, so an interrupted run resumes where it stopped. Nothing is invented: a day ClimateSERV does not return
(or returns negative / null) is stored as null and counted as missing.

Usage (from the repo root, inside the data venv):
    python scripts/data/fetch_rain_climateserv.py                      # all points, pilots first
    python scripts/data/fetch_rain_climateserv.py --workers 12 --budget-minutes 30
    python scripts/data/fetch_rain_climateserv.py --points chiquimula --datasets imerg

ClimateSERV data ids: chirps = 0, imerg = 26 (GPM IMERG daily, 0.1 deg; the response does not state the product
run, so none is claimed). --budget-minutes stops submitting new requests after that wall-clock time; requests
already running are allowed to finish.
"""

import argparse
import json
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

import truststore

truststore.inject_into_ssl()  # use the operating-system certificate store

import climateserv.api as climateserv  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent.parent
POINTS = ROOT / "scripts" / "emulator" / "points.json"
CACHE = ROOT / "scripts" / "emulator" / "cache_rain"
PILOTS = ["chiquimula", "jutiapa", "sanmartin"]
DATASETS = {"imerg": 26, "chirps": 0}
URL = "https://climateserv.servirglobal.net/"
LOCK = threading.Lock()


def box(lat, lon, r):
    return [[lon - r, lat - r], [lon + r, lat - r], [lon + r, lat + r], [lon - r, lat + r], [lon - r, lat - r]]


def request_year(dataset_id, year, polygon, tries=4):
    """One ClimateSERV request for a calendar year; retries with backoff. Returns (rows, info) or raises."""
    last = None
    for attempt in range(1, tries + 1):
        try:
            resp = climateserv.request_data(dataset_id, "Average", f"01/01/{year}", f"12/31/{year}", polygon, None, None, "memory_object")
            if resp and resp.get("data"):
                info = {k: resp[k] for k in ("datatype", "operationtype", "intervaltype", "derived_product") if k in resp}
                return resp["data"], info
            last = RuntimeError("empty response")
        except Exception as e:  # network / server errors: back off and retry
            last = e
        time.sleep(10 * attempt)
    raise RuntimeError(f"{dataset_id} {year}: {last}")


def load(path, point, dataset, r, y0, y1):
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {
        "id": point["id"], "lat": point["lat"], "lon": point["lon"], "dataset": dataset, "datasetId": DATASETS[dataset],
        "operation": "Average", "boxLonLat": box(point["lat"], point["lon"], r), "requested": [f"{y0}-01-01", f"{y1}-12-31"],
        "service": URL, "clientPackage": "climateserv 1.0.8", "response": {}, "days": {}, "yearsDone": [], "yearsFailed": {},
    }


def save(path, doc, y0, y1):
    doc["downloadedUtc"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    doc["complete"] = all(y in doc["yearsDone"] for y in range(y0, y1 + 1))
    dates = sorted(doc["days"])
    doc["obtained"] = [dates[0], dates[-1]] if dates else None
    doc["missingDays"] = sum(1 for v in doc["days"].values() if v is None)
    text = json.dumps(doc)
    # The repo may live in a synced folder (OneDrive) that briefly locks files: retry the atomic replace,
    # then fall back to a plain write.
    tmp = path.with_suffix(".tmp")
    for attempt in range(5):
        try:
            tmp.write_text(text, encoding="utf-8")
            tmp.replace(path)
            return
        except OSError:
            time.sleep(1 + attempt)
    path.write_text(text, encoding="utf-8")


def main():
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--points", nargs="*", help="point ids (default: all, pilots first)")
    ap.add_argument("--datasets", nargs="*", default=list(DATASETS), choices=list(DATASETS))
    ap.add_argument("--year-start", type=int, default=2001)
    ap.add_argument("--year-end", type=int, default=2025)
    ap.add_argument("--radius", type=float, default=0.03, help="half side of the box, degrees")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--budget-minutes", type=float, default=30.0)
    args = ap.parse_args()

    pts = json.loads(POINTS.read_text(encoding="utf-8"))
    pts.sort(key=lambda p: (p["id"] not in PILOTS, PILOTS.index(p["id"]) if p["id"] in PILOTS else 0))
    if args.points:
        pts = [p for p in pts if p["id"] in args.points]
    CACHE.mkdir(parents=True, exist_ok=True)
    t0 = time.time()
    deadline = t0 + args.budget_minutes * 60
    docs = {}
    tasks = []
    # Pilots first (both datasets), then the other points, IMERG before CHIRPS.
    ordered = [(p, ds) for p in pts if p["id"] in PILOTS for ds in args.datasets] + \
              [(p, ds) for ds in args.datasets for p in pts if p["id"] not in PILOTS]
    for p, ds in ordered:
        path = CACHE / f"{p['id']}_{ds}.json"
        doc = load(path, p, ds, args.radius, args.year_start, args.year_end)
        docs[(p["id"], ds)] = (path, doc)
        for y in range(args.year_start, args.year_end + 1):
            if y not in doc["yearsDone"]:
                tasks.append((p, ds, y))

    def run(task):
        p, ds, y = task
        if time.time() > deadline:
            return (p["id"], ds, y, "skipped (time box)")
        path, doc = docs[(p["id"], ds)]
        polygon = json.dumps(box(p["lat"], p["lon"], args.radius))
        try:
            rows, info = request_year(DATASETS[ds], y, polygon)
        except Exception as e:
            with LOCK:
                doc["yearsFailed"][str(y)] = str(e)
                save(path, doc, args.year_start, args.year_end)
            return (p["id"], ds, y, f"FAILED {e}")
        with LOCK:
            for row in rows:
                v = row.get("value", {}).get("avg")
                doc["days"][f"{row['year']:04d}-{row['month']:02d}-{row['day']:02d}"] = None if v is None or v < 0 else round(v, 3)
            doc["response"] = info
            doc["yearsDone"].append(y)
            doc["yearsFailed"].pop(str(y), None)
            save(path, doc, args.year_start, args.year_end)
        return (p["id"], ds, y, f"ok ({len(rows)} days) t={time.time() - t0:.0f}s")

    print(f"{len(tasks)} requests pending, {args.workers} workers, budget {args.budget_minutes} min", flush=True)
    with ThreadPoolExecutor(args.workers) as ex:
        for res in ex.map(run, tasks):
            print("RESULT", *res, flush=True)
    done = sum(1 for _, d in docs.values() if d.get("complete"))
    print(f"Elapsed {(time.time() - t0) / 60:.1f} min; complete files: {done}/{len(docs)}")
    for (pid, ds), (_, d) in docs.items():
        print(f"  {pid} {ds}: years {len(d['yearsDone'])}/{args.year_end - args.year_start + 1}, missing days {d.get('missingDays')}")


if __name__ == "__main__":
    main()
