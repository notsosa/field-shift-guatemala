// Final-model agreement at the 3 pilots (own weather, maize 05-20, three soils) and rain-product sensitivity at Chiquimula.
// Two phases around the AquaCrop runs (python, see README):
//   node scripts/referee/pilots.mjs prepare --dir <work dir>   -> weather + cases per run, and manifest.json
//   (run aquacrop_referee.py once per manifest entry; the README shows the loop)
//   node scripts/referee/pilots.mjs score --dir <work dir> [--artifact web/data/referee_aquacrop.json]
//        -> adds `pilots` and `rainSensitivity` to the artifact written by compare.mjs.
// Rain products come from the snapshot's `rainAlt` (ERA5, IMERG, CHIRPS; POWER is never used). Gap days are never filled: an
// agricultural year with any missing rain day of a product is excluded from every comparison that involves that product. AquaCrop's
// weather file needs a number on every day, so gap days are written as 0 there (and in the simulator bundle of that run), but they
// sit only in excluded years and every season starts from the same dry state, so no scored season sees them.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { spearman, worstK, overlap, caseMetrics, meanAbsDiff, loadSimulator, simulate, SOIL_NAMES } from './compare.mjs';
import { weatherRows, WEATHER_COLUMNS } from './export_weather.mjs';
import { SOILS } from '../../web/js/model/soil.js';
import { agriculturalYears } from '../../web/js/model/simulate.js';

export const PILOTS = ['chiquimula', 'jutiapa', 'sanmartin'];
export const RAIN_PRODUCTS = ['ERA5', 'IMERG', 'CHIRPS'];
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
const round = (x, d = 4) => (x == null ? null : Number(x.toFixed(d)));

/** Agricultural years (1 Apr Y .. 31 Mar Y+1, complete) in which `series` has no null/non-finite day. */
export function validYearsOf(dates, series) {
  return agriculturalYears(dates)
    .filter(({ startIdx, endIdx }) => series.slice(startIdx, endIdx + 1).every((v) => Number.isFinite(v)))
    .map((y) => y.year);
}

/** Copy of the bundle with rain replaced by a product's series; gap days (null) become 0 (see the header: only in excluded years). */
export function rainVariant(bundle, series) {
  return { ...bundle, rain: series.map((v) => (Number.isFinite(v) ? v : 0)), rainSource: 'variant' };
}

function arg(name, argv) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
}
const snap = (id) => readJson(path.join(root, 'web/data/snapshots', `${id}.json`));
const pointOf = (id) => readJson(path.join(root, 'scripts/emulator/points.json')).find((p) => p.id === id);

async function prepare(dir) {
  const sim = await loadSimulator(root);
  fs.mkdirSync(dir, { recursive: true });
  const manifest = [];
  const mk = (id, bundle, cases) => {
    const rows = weatherRows(bundle, sim.computeEt0Series(bundle));
    fs.writeFileSync(path.join(dir, `weather_${id}.txt`), [WEATHER_COLUMNS.join('\t'), ...rows.map((r) => r.join('\t'))].join('\n') + '\n');
    fs.writeFileSync(path.join(dir, `cases_${id}.json`), JSON.stringify({ cases }, null, 1));
    manifest.push({ id, weather: `weather_${id}.txt`, cases: `cases_${id}.json`, out: `aq_${id}.json` });
  };
  for (const id of PILOTS) {
    const soil = pointOf(id).soil;
    const base = { crop: 'Maize', sowDate: '05-20', years: '2001-2024', initial: 'dry' };
    mk(`pilot_${id}`, snap(id), [
      { id: 'loam', ...base, soil: 'Loam' },
      { id: 'site', ...base, soil: { thetaFC: soil.thetaFC, thetaWP: soil.thetaWP }, site: id },
      { id: 'nearest', ...base, soil: SOIL_NAMES[soil.nearestTexture] },
    ]);
  }
  const chi = snap('chiquimula');
  const common = RAIN_PRODUCTS.map((p) => validYearsOf(chi.dates, chi.rainAlt[p])).reduce((a, b) => a.filter((y) => b.includes(y)));
  for (const p of RAIN_PRODUCTS) {
    mk(`rain_${p}`, rainVariant(chi, chi.rainAlt[p]), [{ id: 'maiz_0520', crop: 'Maize', sowDate: '05-20', years: common, soil: 'Loam', initial: 'dry' }]);
  }
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ common, manifest }, null, 1));
  console.log(`Prepared ${manifest.length} runs in ${dir}; rain comparison years: ${common.length} (${common[0]}..${common.at(-1)})`);
}

/** Fails loudly (case and year) when AquaCrop gave no yield: a silent null would turn every Spearman into NaN. */
export function requireYields(aqCase, label) {
  const bad = aqCase.results.filter((r) => !Number.isFinite(r.yieldTHa));
  if (bad.length) throw new Error(`AquaCrop gave no yield in ${label} case ${aqCase.id}, years ${bad.map((r) => r.year).join(', ')}${bad[0].error ? `: ${bad[0].error}` : ''}`);
  return aqCase;
}

const metricsOf = (aqCase, simRows) => {
  const bySim = new Map(simRows.map((r) => [r.year, r]));
  const rows = aqCase.results.filter((r) => bySim.has(r.year)).map((r) => ({ year: r.year, aq: r.yieldTHa, sim: bySim.get(r.year).relYield, ks: bySim.get(r.year).ks }));
  return {
    ...caseMetrics(rows),
    simulatorIncompleteYears: simRows.filter((r) => r.incomplete).map((r) => r.year),
    aquacropMissingYears: aqCase.results.filter((r) => r.yieldTHa == null).map((r) => r.year),
  };
};

async function score(dir, artifactPath) {
  const sim = await loadSimulator(root);
  const { common, manifest } = readJson(path.join(dir, 'manifest.json'));
  const artifact = readJson(artifactPath);
  artifact.pilots = {};
  const profiles = [];
  for (const id of PILOTS) {
    const bundle = snap(id);
    const et0 = sim.computeEt0Series(bundle);
    const aqFile = readJson(path.join(dir, `aq_pilot_${id}.json`));
    profiles.push(...aqFile.soilProfiles);
    const aqCase = Object.fromEntries(aqFile.cases.map((c) => [c.id, requireYields(c, `pilot ${id}`)]));
    const pt = pointOf(id);
    const nearestTexture = pt.soil.nearestTexture;
    const run = (soil) => simulate(sim, bundle, et0, { id: 'x', crop: 'Maize', sowDate: '05-20', ...soil });
    const site = run({ site: id });
    const byClass = Object.fromEntries(Object.keys(SOIL_NAMES).map((k) => [k, run({ soil: SOIL_NAMES[k] })]));
    const rel = (rows) => rows.map((r) => r.relYield);
    const err = Object.fromEntries(Object.keys(SOIL_NAMES).map((k) => [k, round(meanAbsDiff(rel(site), rel(byClass[k])))]));
    const closest = Object.keys(err).sort((a, b) => err[a] - err[b])[0];
    artifact.pilots[id] = {
      lat: bundle.lat, lon: bundle.lon, rainSource: bundle.rainSource,
      soil: { thetaFC: pt.soil.thetaFC, thetaWP: pt.soil.thetaWP, availableWater: round(pt.soil.thetaFC - pt.soil.thetaWP), cn: pt.soil.cn, nearestTexture, source: pt.soil.source },
      loam: metricsOf(aqCase.loam, byClass.loam),
      site: metricsOf(aqCase.site, site),
      nearestTexture: { texture: nearestTexture, ...metricsOf(aqCase.nearest, byClass[nearestTexture]) },
      soilClassError: { ...err, closest, nearestTextureIsClosest: closest === nearestTexture, metric: 'mean absolute difference in simulator relYield, site soil vs class, maize 05-20, 2001-2024, same weather' },
    };
  }

  // Rain-product sensitivity at Chiquimula (loam, maize 05-20, only the years valid in every product).
  const chi = snap('chiquimula');
  const ag = agriculturalYears(chi.dates);
  const per = {};
  for (const p of RAIN_PRODUCTS) {
    const variant = rainVariant(chi, chi.rainAlt[p]);
    const aqFile = readJson(path.join(dir, `aq_rain_${p}.json`));
    profiles.push(...aqFile.soilProfiles);
    const aq = requireYields(aqFile.cases[0], `rain ${p}`);
    const simRows = simulate(sim, variant, sim.computeEt0Series(variant), { id: 'x', crop: 'Maize', sowDate: '05-20', soil: 'Loam' }).filter((r) => common.includes(r.year));
    per[p] = { aq, simRows, metrics: metricsOf(aq, simRows) };
  }
  const simOf = (p, y) => per[p].simRows.find((r) => r.year === y);
  const vec = (p) => common.map((y) => simOf(p, y).relYield);
  const aqv = (p) => common.map((y) => per[p].aq.results.find((r) => r.year === y).yieldTHa);
  const worst = (p) => worstK(vec(p), common, 5, common.map((y) => simOf(p, y).ks));
  const betweenProducts = {};
  for (let i = 0; i < RAIN_PRODUCTS.length; i++) for (let j = i + 1; j < RAIN_PRODUCTS.length; j++) {
    const a = RAIN_PRODUCTS[i];
    const b = RAIN_PRODUCTS[j];
    betweenProducts[`${a}-${b}`] = {
      simulatorSpearman: round(spearman(vec(a), vec(b))),
      simulatorWorst5Overlap: overlap(worst(a), worst(b)),
      aquacropSpearman: round(spearman(aqv(a), aqv(b))),
      meanAbsDiffRelYield: round(meanAbsDiff(vec(a), vec(b))),
    };
  }
  const meanRain = (p) => common.reduce((s, y) => {
    const { startIdx, endIdx } = ag.find((a) => a.year === y);
    return s + chi.rainAlt[p].slice(startIdx, endIdx + 1).reduce((x, v) => x + v, 0);
  }, 0) / common.length;
  artifact.rainSensitivity = {
    site: 'chiquimula', crop: 'Maize', sowDate: '05-20', soil: 'Loam', years: common, nYears: common.length,
    excludedYears: Object.fromEntries(RAIN_PRODUCTS.map((p) => [p, ag.map((y) => y.year).filter((y) => !validYearsOf(chi.dates, chi.rainAlt[p]).includes(y))])),
    note: 'Gap days of a product are never filled; years with a gap in any product are excluded from all of this comparison. The model keeps ERA5 as its rain source: this quantifies an information gap, it is not a choice of product.',
    meanRainMm: Object.fromEntries(RAIN_PRODUCTS.map((p) => [p, round(meanRain(p), 1)])),
    vsAquacrop: Object.fromEntries(RAIN_PRODUCTS.map((p) => [p, { spearman: per[p].metrics.spearman, worst5: per[p].metrics.worst5, cv: per[p].metrics.cv, simYearsAtOne: per[p].metrics.simYearsAtOne }])),
    betweenProducts,
  };
  const seen = new Set();
  artifact.soilComparison = {
    note: 'Class soils (Loam, Sand, Clay) are NOT the same soil in AquaCrop and in the simulator: AquaCrop uses its own default profile (read from the aquacrop package), the simulator its own class. Only the site-soil cases give both models the same thetaFC and thetaWP (thetaSat and Ksat of a site soil are the harness defaults: thetaFC + 0.15 capped at 0.6, Ksat 500 mm/day).',
    aquacrop: profiles.filter((p) => { const k = JSON.stringify(p.soil); return seen.has(k) ? false : seen.add(k); }),
    simulator: Object.fromEntries(Object.entries(SOILS).map(([k, v]) => [k, { thetaFC: v.thetaFC, thetaWP: v.thetaWP, hydrologicGroup: v.hydrologicGroup, cn: v.cn }])),
  };
  fs.writeFileSync(artifactPath, JSON.stringify(artifact, null, 1) + '\n');
  console.log(`Updated ${artifactPath} with pilots and rainSensitivity (${manifest.length} AquaCrop runs read)`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [cmd, ...rest] = process.argv.slice(2);
  const dir = arg('dir', rest);
  if (!dir || !['prepare', 'score'].includes(cmd)) throw new Error('Usage: pilots.mjs prepare|score --dir <work dir> [--artifact web/data/referee_aquacrop.json]');
  if (cmd === 'prepare') await prepare(dir);
  else await score(dir, arg('artifact', rest) ?? path.join(root, 'web/data/referee_aquacrop.json'));
}
