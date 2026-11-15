// Compares the team simulator with AquaCrop results and writes web/data/referee_aquacrop.json.
// Usage:
//   node scripts/referee/compare.mjs --aquacrop <aquacrop_results.json> --bundle <bundle.json> --out web/data/referee_aquacrop.json
//        [--before-root <dir holding web/js/model + web/data/crops.json> --before-label d02febe]
//        [--after-root <repo root> --after-label <label>]
// Without --before-root only the "after" block is written. The AquaCrop results come from aquacrop_referee.py.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const DROUGHT_YEARS = [2014, 2015, 2018, 2019];
export const CROP_IDS = { Maize: 'maiz', DryBean: 'frijol', Sorghum: 'sorgo' };
export const SOIL_TEXTURES = { Loam: 'loam', Sand: 'sand', Clay: 'clay' };

const mean = (a) => a.reduce((s, x) => s + x, 0) / a.length;

/** Average ranks, 1 = smallest; ties share the mean of their positions. */
export function averageRanks(values) {
  const order = values.map((v, i) => [v, i]).sort((p, q) => p[0] - q[0]);
  const ranks = new Array(values.length);
  for (let i = 0; i < order.length;) {
    let j = i;
    while (j + 1 < order.length && order[j + 1][0] === order[i][0]) j++;
    const r = (i + j) / 2 + 1;
    for (let k = i; k <= j; k++) ranks[order[k][1]] = r;
    i = j + 1;
  }
  return ranks;
}

/** Spearman rank correlation (Pearson on average ranks, so ties are handled). null if either side is constant. */
export function spearman(a, b) {
  if (a.length !== b.length || a.length < 2) throw new Error('spearman: need two arrays of equal length >= 2');
  const ra = averageRanks(a);
  const rb = averageRanks(b);
  const ma = mean(ra);
  const mb = mean(rb);
  let sab = 0;
  let saa = 0;
  let sbb = 0;
  for (let i = 0; i < ra.length; i++) {
    sab += (ra[i] - ma) * (rb[i] - mb);
    saa += (ra[i] - ma) ** 2;
    sbb += (rb[i] - mb) ** 2;
  }
  return saa === 0 || sbb === 0 ? null : sab / Math.sqrt(saa * sbb);
}

/** Labels of the k lowest values, sorted ascending; ties broken by `tiebreak` (ascending) and then by position. */
export function worstK(values, labels, k, tiebreak = null) {
  return values
    .map((v, i) => ({ v, t: tiebreak ? tiebreak[i] : 0, l: labels[i], i }))
    .sort((p, q) => p.v - q.v || p.t - q.t || p.i - q.i)
    .slice(0, k)
    .map((x) => x.l)
    .sort((x, y) => x - y);
}

export function overlap(a, b) {
  const s = new Set(b);
  return a.filter((x) => s.has(x)).length;
}

/** Coefficient of variation with the sample standard deviation (n - 1). */
export function cv(values) {
  const m = mean(values);
  const sd = Math.sqrt(values.reduce((s, x) => s + (x - m) ** 2, 0) / (values.length - 1));
  return sd / m;
}

/** Competition rank of the label (1 = lowest value; ties share the lowest rank). */
export function rankOf(values, labels, label) {
  const v = values[labels.indexOf(label)];
  return 1 + values.filter((x) => x < v).length;
}

export function countAtOne(values, tol = 1e-4) {
  return values.filter((x) => x >= 1 - tol).length;
}

export function quantile(values, q) {
  const s = [...values].sort((a, b) => a - b);
  const pos = (s.length - 1) * q;
  const lo = Math.floor(pos);
  return s[lo] + (s[Math.min(lo + 1, s.length - 1)] - s[lo]) * (pos - lo);
}

const round = (x, d = 4) => (x == null ? null : Number(x.toFixed(d)));

/** Agreement metrics for one case; rows = [{year, aq (t/ha), sim (relYield), ks (simulator flowering Ks, tiebreak)}]. */
export function caseMetrics(rows) {
  const years = rows.map((r) => r.year);
  const aq = rows.map((r) => r.aq);
  const sim = rows.map((r) => r.sim);
  const aqWorst = worstK(aq, years, 5);
  const simWorst = worstK(sim, years, 5, rows.map((r) => r.ks));
  return {
    n: rows.length,
    spearman: round(spearman(aq, sim)),
    worst5: { aquacrop: aqWorst, simulator: simWorst, overlap: overlap(aqWorst, simWorst) },
    droughtRanks: Object.fromEntries(DROUGHT_YEARS.filter((y) => years.includes(y)).map((y) => [y, { aquacrop: rankOf(aq, years, y), simulator: rankOf(sim, years, y) }])),
    cv: { aquacrop: round(cv(aq)), simulator: round(cv(sim)) },
    simYearsAtOne: countAtOne(sim),
  };
}

async function loadSimulator(root) {
  const url = (rel) => pathToFileURL(path.join(root, rel)).href;
  const { computeEt0Series, runSequence } = await import(url('web/js/model/simulate.js'));
  const { loadCrops } = await import(url('web/js/model/crops.js'));
  const crops = loadCrops(JSON.parse(fs.readFileSync(path.join(root, 'web/data/crops.json'), 'utf8')));
  return { computeEt0Series, runSequence, crops };
}

function simulate(sim, bundle, et0, c) {
  const cropId = CROP_IDS[c.crop];
  const texture = typeof c.soil === 'string' ? SOIL_TEXTURES[c.soil] : null;
  if (!cropId || !texture) throw new Error(`case ${c.id}: simulator mapping not available for crop ${c.crop} / soil ${JSON.stringify(c.soil)}`);
  const sequence = { id: c.id, name: { en: c.id, es: c.id }, phases: [{ cropId, sow: c.sowDate }], requiresIrrigation: false };
  return sim.runSequence({ sequence, bundle, et0, crops: sim.crops, texture, slopeClass: 'flat', irrigation: 'none' })
    .map((r) => ({ year: r.year, relYield: r.crops[0].relYield, ks: r.crops[0].ksFlowerMean }));
}

async function block(root, label, bundle, aqCases) {
  const sim = await loadSimulator(root);
  const et0 = sim.computeEt0Series(bundle);
  const cases = {};
  const sweepRaw = [];
  for (const c of aqCases) {
    const simByYear = new Map(simulate(sim, bundle, et0, c).map((r) => [r.year, r]));
    const rows = c.results.filter((r) => r.yieldTHa != null && simByYear.has(r.year)).map((r) => {
      const s = simByYear.get(r.year);
      return { year: r.year, aq: r.yieldTHa, aqRel: r.relYield, sim: s.relYield, ks: s.ks };
    });
    if (c.group === 'sowing_sweep') sweepRaw.push({ c, rows });
    cases[c.id] = {
      crop: c.crop,
      sowDate: c.sowDate,
      group: c.group ?? null,
      ...caseMetrics(rows),
      ...(c.group === 'sowing_sweep' ? {} : { perYear: rows.map((r) => ({ year: r.year, aquacropYieldTHa: round(r.aq), aquacropRelYield: round(r.aqRel), simulatorRelYield: round(r.sim) })) }),
    };
  }
  // AquaCrop's relative scale across the sweep uses one common denominator: the best yield at any date and year.
  const maxAq = Math.max(...sweepRaw.flatMap((s) => s.rows.map((r) => r.aq)));
  const points = sweepRaw.map(({ c, rows }) => {
    const aq = rows.map((r) => r.aq);
    const sm = rows.map((r) => r.sim);
    return {
      sowDate: c.sowDate,
      aquacrop: { medianTHa: round(quantile(aq, 0.5)), meanTHa: round(mean(aq)), p10THa: round(quantile(aq, 0.1)), medianRel: round(quantile(aq, 0.5) / maxAq) },
      simulator: { medianRel: round(quantile(sm, 0.5)), meanRel: round(mean(sm)), p10Rel: round(quantile(sm, 0.1)) },
    };
  });
  return { label, cases, sowingCurve: { crop: sweepRaw[0]?.c.crop ?? null, aquacropRelativeTo: 'best yield over all sweep dates and years', points } };
}

function arg(name, argv) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
}

async function main(argv) {
  const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
  const aqPath = arg('aquacrop', argv);
  const bundlePath = arg('bundle', argv);
  const out = arg('out', argv) ?? path.join(repoRoot, 'web/data/referee_aquacrop.json');
  if (!aqPath || !bundlePath) throw new Error('Usage: compare.mjs --aquacrop <results.json> --bundle <bundle.json> [--out f] [--before-root d --before-label l] [--after-root d --after-label l]');
  const aq = JSON.parse(fs.readFileSync(aqPath, 'utf8'));
  const bundle = JSON.parse(fs.readFileSync(bundlePath, 'utf8'));
  const afterRoot = arg('after-root', argv) ?? repoRoot;
  let afterLabel = arg('after-label', argv);
  if (!afterLabel) {
    try { afterLabel = execFileSync('git', ['-C', afterRoot, 'rev-parse', '--short', 'HEAD'], { encoding: 'utf8' }).trim(); } catch { afterLabel = 'working tree'; }
  }
  const result = {
    meta: {
      aquacropVersion: aq.aquacropVersion,
      generated: new Date().toISOString().slice(0, 10),
      weatherSource: { bundle: path.relative(repoRoot, path.resolve(bundlePath)).replace(/\\/g, '/'), rainSource: bundle.rainSource, lat: bundle.lat, lon: bundle.lon, elevation: bundle.elevation },
      aquacropConvention: aq.convention,
      initialCondition: [...new Set(aq.cases.map((c) => c.initial))].join(','),
      soil: [...new Set(aq.cases.map((c) => JSON.stringify(c.soil)))].map((s) => JSON.parse(s)),
      simulatorSetup: 'texture loam, flat slope, rainfed, dry start on 1 April, single crop with fixed sowing date',
      note: 'AquaCrop uses default crop parameters (no local calibration): this tests logic and robustness, not field truth. Do not quote AquaCrop absolute yields. AquaCrop relYield = yield / max over the case years.',
    },
  };
  const beforeRoot = arg('before-root', argv);
  if (beforeRoot) result.before = await block(beforeRoot, arg('before-label', argv) ?? 'before', bundle, aq.cases);
  result.after = await block(afterRoot, afterLabel, bundle, aq.cases);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, JSON.stringify(result, null, 1) + '\n');
  console.log(`Wrote ${out}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main(process.argv.slice(2));
