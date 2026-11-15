"""AquaCrop-OSPy referee: runs single-crop, rainfed seasons for a list of cases.

Usage:
  python aquacrop_referee.py --weather weather.txt --cases cases.json --out results.json [--jobs 4]

weather.txt: tab-separated, columns Day Month Year MinTemp MaxTemp Precipitation ReferenceET.
cases.json:  {"cases": [...]} or a bare list. A case is
  {id, crop: 'Maize'|'DryBean'|'Sorghum', sowDate: 'MM-DD', years: [2001, ...] or "2001-2024",
   soil: 'Loam' | {thetaFC, thetaWP, thetaSat?, ksat?}, initial: 'dry'|'fc'}
  Optional extra fields (group, ...) are copied to the output untouched.

Conventions (results depend on them, they are recorded in the output):
  - A season runs from 1 April of the year to 31 March of the next (long enough for a 1 September bean to mature).
  - initial 'dry' = soil water at wilting point on 1 April (default, matches the simulator's dry start);
    'fc' = field capacity on 1 April.
  - Default AquaCrop crop parameters, no calibration: absolute yields are not field truth.
Output per case and year: yieldTHa, relYield (yield / max over that case's years), harvestDate, error (if the run failed).
"""
import argparse
import datetime
import json
import os
import sys
import warnings
from concurrent.futures import ProcessPoolExecutor

warnings.filterwarnings('ignore')

INITIAL = {'dry': 'WP', 'fc': 'FC'}
CROPS = ('Maize', 'DryBean', 'Sorghum')


def parse_years(y):
    if isinstance(y, str):
        a, b = y.split('-')
        return list(range(int(a), int(b) + 1))
    return [int(v) for v in y]


def make_soil(spec):
    from aquacrop import Soil
    if isinstance(spec, str):
        return Soil(spec)
    soil = Soil('custom')
    th_fc, th_wp = spec['thetaFC'], spec['thetaWP']
    th_s = spec.get('thetaSat', min(0.6, th_fc + 0.15))
    ksat = spec.get('ksat', 500.0)
    soil.add_layer(1.2, th_wp, th_fc, th_s, ksat, 100)
    return soil


def soil_profiles(cases):
    """Profile AquaCrop actually uses for each distinct soil of the cases (read from the package, never typed):
    one entry per layer with thickness (m), theta at wilting point / field capacity / saturation and Ksat (mm/day)."""
    seen, out = set(), []
    for c in cases:
        key = json.dumps(c['soil'], sort_keys=True)
        if key in seen:
            continue
        seen.add(key)
        prof = make_soil(c['soil']).profile
        layers = []
        for lid, g in prof.groupby('Layer', sort=True):
            r = g.iloc[0]
            layers.append({'layer': int(lid), 'thicknessM': round(float(g['dz'].sum()), 4), 'thetaWP': float(r['th_wp']), 'thetaFC': float(r['th_fc']),
                           'thetaSat': float(r['th_s']), 'ksatMmDay': float(r['Ksat'])})
        out.append({'soil': c['soil'], 'layers': layers})
    return out


def run_one(args):
    weather_path, case, year = args
    from aquacrop import AquaCropModel, Crop, InitialWaterContent
    from aquacrop.utils import prepare_weather
    try:
        wdf = prepare_weather(weather_path)
        model = AquaCropModel(f'{year}/04/01', f'{year + 1}/03/31', wdf, make_soil(case['soil']),
                              Crop(case['crop'], planting_date=case['sowDate'].replace('-', '/')),
                              InitialWaterContent(value=[INITIAL[case.get('initial', 'dry')]]))
        model.run_model(till_termination=True)
        r = model.get_simulation_results().iloc[0]
        return {'year': year, 'yieldTHa': float(r['Dry yield (tonne/ha)']),
                'harvestDate': str(r['Harvest Date (YYYY/MM/DD)'])[:10]}
    except Exception as e:  # keep the batch going; the caller sees the error per year
        return {'year': year, 'yieldTHa': None, 'harvestDate': None, 'error': str(e)[:200]}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--weather', required=True)
    ap.add_argument('--cases', required=True)
    ap.add_argument('--out', required=True)
    ap.add_argument('--jobs', type=int, default=max(1, (os.cpu_count() or 2) // 2))
    a = ap.parse_args()

    import aquacrop
    version = getattr(aquacrop, '__version__', None)
    if version is None:
        from importlib.metadata import version as pkg_version
        version = pkg_version('aquacrop')
    raw = json.load(open(a.cases, encoding='utf-8'))
    cases = raw['cases'] if isinstance(raw, dict) else raw
    for c in cases:
        if c['crop'] not in CROPS:
            sys.exit(f"case {c['id']}: crop must be one of {CROPS}")
        if c.get('initial', 'dry') not in INITIAL:
            sys.exit(f"case {c['id']}: initial must be 'dry' or 'fc'")

    jobs = [(os.path.abspath(a.weather), c, y) for c in cases for y in parse_years(c['years'])]
    with ProcessPoolExecutor(max_workers=a.jobs) as ex:
        results = list(ex.map(run_one, jobs, chunksize=4))

    out_cases = []
    k = 0
    for c in cases:
        rows = results[k:k + len(parse_years(c['years']))]
        k += len(rows)
        ys = [r['yieldTHa'] for r in rows if r['yieldTHa'] is not None]
        mx = max(ys) if ys else None
        for r in rows:
            r['relYield'] = (r['yieldTHa'] / mx) if (mx and r['yieldTHa'] is not None) else None
        out_cases.append({**c, 'years': parse_years(c['years']), 'initial': c.get('initial', 'dry'), 'results': rows})

    json.dump({'aquacropVersion': version, 'generated': datetime.date.today().isoformat(),
               'convention': 'season 1 Apr Y .. 31 Mar Y+1; initial water at wilting point (dry) or field capacity (fc) on 1 Apr; default crop parameters',
               'soilProfiles': soil_profiles(cases), 'cases': out_cases}, open(a.out, 'w', encoding='utf-8'), indent=1)
    failed = sum(1 for r in results if r['yieldTHa'] is None)
    print(f'AquaCrop {version}: {len(results)} seasons, {failed} failed -> {a.out}')


if __name__ == '__main__':
    main()
