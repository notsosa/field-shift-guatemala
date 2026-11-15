# AquaCrop referee

An independent crop model (AquaCrop-OSPy 3.1.0) run on the same daily weather and ET0 as the team simulator. Use it to check whether a model change improves agreement, and to score the recommendations of competing models (this simulator + emulator, or a policy network).

## What it is and is not
- It tests logic and robustness (year ranking, dynamic range, response to sowing date). It is **not** field truth: AquaCrop runs with its default crop parameters and no local calibration. Do not quote its absolute yields (default maize potential is about 14.5 t/ha).
- One crop per run: no relay, no intercropping, no cover-crop effect. A rotation becomes separate runs with the water reset.
- Crops with parameters: `Maize`, `DryBean`, `Sorghum`. There are none for sesame, watermelon or velvet bean.
- It shares the team's weather and ET0, so input errors are not tested.
- Results depend on conventions. Default `initial: 'dry'` = soil at wilting point on 1 April, matching the simulator's dry start. With `'fc'` (field capacity) AquaCrop gives almost the same yield every year, so state the convention whenever you quote a number. Seasons run 1 April to 31 March of the next year.

## Setup
```
python -m venv .venv-referee
.venv-referee/Scripts/python -m pip install -r scripts/referee/requirements.txt
```
(Linux/macOS: `.venv-referee/bin/python`.) Node 18+ for the JS side, no packages.

## Run
```
node scripts/referee/export_weather.mjs --bundle web/data/snapshots/chiquimula.json --out scripts/referee/out/weather_chiquimula
node scripts/referee/resolve_site_cases.mjs --cases scripts/referee/cases_chiquimula.json --out scripts/referee/out/cases_resolved.json
.venv-referee/Scripts/python scripts/referee/aquacrop_referee.py --weather scripts/referee/out/weather_chiquimula.txt --cases scripts/referee/out/cases_resolved.json --out scripts/referee/out/aquacrop_results.json
node scripts/referee/compare.mjs --aquacrop scripts/referee/out/aquacrop_results.json --bundle web/data/snapshots/chiquimula.json --out web/data/referee_aquacrop.json
```
About 10 cases x 24 seasons, 5 s per 24-season run per core. `--jobs N` sets the number of worker processes.

Before/after for a model change: export the old model next to the repo (`git archive <commit> web/js/model web/js/data web/data/crops.json | tar -x -C <tmp>`) and add `--before-root <tmp> --before-label <commit>` to `compare.mjs`. The AquaCrop run is shared, so only the simulator side changes.

`web/data/referee_aquacrop.json` holds, per case: Spearman of AquaCrop vs simulator `relYield`, overlap of the 5 worst years, ranks (1 = worst) of 2014/2015/2018/2019, CV of both indices, number of simulator years at exactly 1.0, and the per-year table. It also holds the maize sowing-date curve (median and mean of both models).

## Case format
`cases.json` is `{"cases": [...]}` or a bare list. A case: `{id, crop: 'Maize'|'DryBean'|'Sorghum', sowDate: 'MM-DD', years: [2001, ...] or "2001-2024", soil: 'Loam' | {thetaFC, thetaWP, thetaSat?, ksat?}, initial: 'dry'|'fc'}`. Extra fields (such as `group`) pass through. `compare.mjs` maps `Maize/DryBean/Sorghum` to `maiz/frijol/sorgo` and `Loam/Sand/Clay` to the simulator textures; object soils run in AquaCrop only, except `soil: "site"` with `"site": "<pilot id>"`: run `node scripts/referee/resolve_site_cases.mjs --cases <cases.json> --out scripts/referee/out/cases_resolved.json` first and give the resolved file to `aquacrop_referee.py`; AquaCrop then uses a custom soil with the pilot's SoilGrids thetaFC/thetaWP and `compare.mjs` runs the simulator with the pilot's full soil object from `scripts/emulator/points.json` (CN included).

## Protocol (3 levels)
1. **Emulator fidelity**: emulator vs the JS simulator on held-out years and sowing offsets (R2, MAE of `relYield`, rank correlation, error by sowing date). It shows only that the network reproduces the simulator, shortcuts included.
2. **Cross-model agreement**: simulator vs AquaCrop with the same weather and dry start. Report Spearman, worst-5 overlap, drought-year ranks, CV (the simulator index is much flatter: do not justify a recommendation with a gain below the noise floor), and the sowing-date curve.
3. **Independent referee for recommendations**: for each held-out year and site take the model's recommended action (sowing date, crop) and a baseline (fixed calendar date, or onset +0 days). Score both in AquaCrop. Report win rate (share of years with recommended >= baseline), mean and p10 gain (t/ha and %), with bootstrap confidence intervals over years. Flag "simulator-only wins": recommendations that win in the team simulator but lose or tie in AquaCrop. Do not average disagreement away.

## How to score another model's recommendations
1. For every (year, site) write two cases, one for the recommended action and one for the baseline, with `years: [that year]`, e.g. `{"id": "policy_2015_rec", "crop": "Maize", "sowDate": "06-10", "years": [2015], "soil": "Loam", "initial": "dry"}` and `{"id": "policy_2015_base", ..., "sowDate": "05-20", ...}`. Several years of one action can share a case.
2. Export weather for that site with `export_weather.mjs` and run `aquacrop_referee.py --weather ... --cases policy_cases.json --out policy_results.json`.
3. Per year, gain = `yieldTHa(rec) - yieldTHa(base)`; win = gain >= 0. Compute win rate, mean gain and p10 gain per case group. Use raw `yieldTHa` for gains (the per-case `relYield` divides by that case's own maximum and is not comparable across cases).
4. Do the same with the team simulator's `relYield` and list the years where the simulator says win and AquaCrop says lose or tie.
