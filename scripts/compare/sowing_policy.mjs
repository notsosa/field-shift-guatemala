// Decisión de la demora de siembra con información previa (tres motores, la misma regla) y su puntaje.
// Fases alrededor de AquaCrop (python, ver scripts/compare/README.md):
//   node scripts/compare/sowing_policy.mjs prepare --dir <work>    -> clima y casos de AquaCrop por piloto + manifest.json
//   (correr aquacrop_referee.py una vez por entrada del manifest)
//   node scripts/compare/sowing_policy.mjs score --dir <work> [--out web/data/decision_eval.json]
// La regla, los desfases, las prioridades, la tolerancia, los años y los sitios están fijados en web/js/model/decision.js y aquí abajo;
// no se ajustan después de ver resultados. La decisión para el año Y solo recibe el bundle recortado al 31 de marzo de Y.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { computeEt0Series, agriculturalYears, runSequence, resolveMainSowIdx } from '../../web/js/model/simulate.js';
import { loadCrops } from '../../web/js/model/crops.js';
import {
  climateFeatures, phenoFeatures, encodeFeatures, targetsOf, mlpPredict, elmPredict, trainELM,
} from '../../web/js/model/emulator.js';
import { yearSlices, clamp01 } from '../../web/js/ui/bestSowing.js';
import {
  DECISION_OFFSETS, PRIORITIES, TOLERANCE, truncateBundle, pastYears, decideOffset, chooseOffset, overlapDays,
  aggregateMetrics, aquacropMetrics,
} from '../../web/js/model/decision.js';
import { weatherRows, WEATHER_COLUMNS } from '../referee/export_weather.mjs';
import { resolveSiteCases } from '../referee/resolve_site_cases.mjs';
import { requireYields } from '../referee/pilots.mjs';

export const SITES = ['chiquimula', 'jutiapa', 'sanmartin'];
export const TARGET_YEARS = [2019, 2020, 2021, 2022, 2023, 2024];
export const CLASS_SOILS = ['sand', 'loam', 'clay'];
export const POLICIES = ['simulator', 'mlp', 'elmBrowser'];
/** Solo informativas (retrospectiva): sembrar antes de la regla de inicio exige saber cuándo llegará la lluvia. */
export const HINDSIGHT_OFFSETS = [-20, -15, -10, -5];
export const SEQUENCE_ID = 'actual';
export const MANAGEMENT = { slopeClass: 'flat', irrigation: 'none' };
export const RULE_TEXT = 'For target year Y, use only agricultural years before Y at that site (all complete years from 2001 to Y-1). For each delay in {0,5,...,30} days after the rain-onset rule, collect the rotation water index (first emulator output) of those past years; summarise it with the priority (typical = median, cautious = 20th percentile); choose the delay with the highest summary, ties to the delay closest to 0. Baseline = delay 0. Oracle = the feasible delay with the best simulator water index in year Y itself.';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
const dataJson = (rel) => readJson(path.join(root, 'web/data', rel));
const round = (x, d = 6) => (x == null ? null : Number(x.toFixed(d)));

/** Todo lo que necesitan los motores; los motores aprendidos se cargan/entrenan aquí. */
export function loadContext() {
  const crops = loadCrops(dataJson('crops.json'));
  const sequence = dataJson('sequences.json')[SEQUENCE_ID];
  const points = readJson(path.join(root, 'scripts/emulator/points.json'));
  const bundles = Object.fromEntries(SITES.map((s) => [s, dataJson(`snapshots/${s}.json`)]));
  const evalJson = dataJson('emulator_eval.json');
  const rec = evalJson.browserElmRecommendation;
  // La ELM de la página (emulatorPage.js elmOptions): trainELM(subset, {hidden, inputScale, lambda, seed}) de la recomendación guardada.
  const elmOptions = { hidden: rec.hidden, inputScale: rec.inputScale ?? 1, lambda: rec.lambda, seed: rec.seed ?? 42 };
  const subset = dataJson('emulator_train_subset.json');
  const t0 = performance.now();
  const elm = trainELM(subset.X, subset.Y, elmOptions);
  const elmTrainSeconds = (performance.now() - t0) / 1000;
  const mlp = dataJson('emulator_mlp.json');
  const siteSoil = Object.fromEntries(SITES.map((s) => [s, points.find((p) => p.id === s).soil]));
  return { crops, sequence, bundles, siteSoil, mlp, elm, elmOptions, elmTrainSeconds, subsetRows: subset.X.length, evalJson };
}

/** Suelo del simulador y textura para los emuladores de un caso: 'site' → objeto SoilGrids y la clase más cercana del piloto. */
export function soilOf(ctx, site, soilCase) {
  if (soilCase === 'site') return { simSoil: ctx.siteSoil[site], emuTexture: ctx.siteSoil[site].nearestTexture };
  return { simSoil: soilCase, emuTexture: soilCase };
}

/** Lo único que ve una decisión para `year`: el bundle recortado al 31 de marzo de `year` y su ET0 recalculada sobre él. */
export function pastData(bundle, year) {
  const past = truncateBundle(bundle, year);
  return { bundle: past, et0: computeEt0Series(past), years: pastYears(agriculturalYears(past.dates).map((a) => a.year), year) };
}

/** Motores: cada uno devuelve [{offset, year, value}] (índice de agua por demora y año pasado). */
const simulatorEngine = (ctx, past, { simSoil }) => DECISION_OFFSETS.flatMap((offset) => runSequence({
  sequence: ctx.sequence, bundle: past.bundle, et0: past.et0, crops: ctx.crops, texture: simSoil, ...MANAGEMENT, sowOffsetDays: offset,
}).flatMap((yr) => { const t = targetsOf(yr); return t ? [{ offset, year: yr.year, value: t[0] }] : []; }));

function emulatorEngine(predict) {
  return (ctx, past, { emuTexture }) => {
    const slices = yearSlices(past.bundle, past.et0, past.years);
    const clim = slices.map((s) => climateFeatures(s.bundle, s.year, s.et0));
    return DECISION_OFFSETS.flatMap((offset) => slices.map((s, k) => {
      const ph = phenoFeatures(s.bundle, s.year, s.et0, ctx.crops, offset);
      const x = encodeFeatures(clim[k], ph, { texture: emuTexture, ...MANAGEMENT, sequenceId: SEQUENCE_ID, sowOffsetDays: offset });
      return { offset, year: s.year, value: clamp01(predict(x)[0]) };
    }));
  };
}

export const ENGINES = {
  simulator: simulatorEngine,
  mlp: (ctx, past, soil) => emulatorEngine((x) => mlpPredict(ctx.mlp, x))(ctx, past, soil),
  elmBrowser: (ctx, past, soil) => emulatorEngine((x) => elmPredict(ctx.elm, x))(ctx, past, soil),
};

/** Decisiones {policy: {priority: offset}} para un sitio, año objetivo y suelo. El bundle completo se recorta aquí, antes de cualquier motor. */
export function decideAll(ctx, site, year, soilCase, past = pastData(ctx.bundles[site], year)) {
  const soil = soilOf(ctx, site, soilCase);
  const out = {};
  for (const policy of POLICIES) {
    const outcomes = ENGINES[policy](ctx, past, soil);
    out[policy] = Object.fromEntries(PRIORITIES.map((priority) => [priority, decideOffset({ outcomes, targetYear: year, priority })]));
  }
  return out;
}

/** Verdad del simulador, por año y demora (factibles y retrospectivas), para un sitio y suelo: el bundle completo. */
export function truthTable(ctx, site, soilCase) {
  const bundle = ctx.bundles[site];
  const et0 = computeEt0Series(bundle);
  const { simSoil } = soilOf(ctx, site, soilCase);
  const table = {};
  for (const offset of [...HINDSIGHT_OFFSETS, ...DECISION_OFFSETS]) {
    const res = runSequence({ sequence: ctx.sequence, bundle, et0, crops: ctx.crops, texture: simSoil, ...MANAGEMENT, sowOffsetDays: offset });
    table[offset] = new Map(res.map((yr) => {
      const [maize, beans] = yr.crops;
      const t = targetsOf(yr);
      return [yr.year, {
        waterIndex: round(t[0]), ksFlowerMain: round(t[1]), bareFrac: round(t[2]),
        maizeRelYield: round(maize.cycleIncomplete ? 0 : maize.relYield), beansRelYield: round(beans.cycleIncomplete ? 0 : beans.relYield),
        overlapDays: overlapDays(maize, beans),
        maizeSowDate: maize.sowDate, maizeHarvestDate: maize.harvestDate,
        maizeCycleIncomplete: maize.cycleIncomplete, beansCycleIncomplete: beans.cycleIncomplete,
      }];
    }));
  }
  return table;
}

const caseId = (site, year, soil) => `${site}_${year}_${soil}`;

/** Una fila por caso (sitio × año × suelo): verdad por demora, oráculo, retrospectiva y las seis decisiones. */
export function evaluateCases(ctx) {
  const cases = [];
  for (const site of SITES) {
    const pasts = new Map(TARGET_YEARS.map((y) => [y, pastData(ctx.bundles[site], y)]));
    for (const soil of [...CLASS_SOILS, 'site']) {
      const truth = truthTable(ctx, site, soil);
      for (const year of TARGET_YEARS) {
        const at = (offset) => truth[offset].get(year);
        const feasible = DECISION_OFFSETS.map((offset) => ({ offset, value: at(offset).waterIndex }));
        const oracleOffset = chooseOffset(feasible);
        const all = [...HINDSIGHT_OFFSETS, ...DECISION_OFFSETS].map((offset) => ({ offset, value: at(offset).waterIndex }));
        const hindsightOffset = chooseOffset(all);
        cases.push({
          id: caseId(site, year, soil), site, year, soil,
          emulatorTexture: soilOf(ctx, site, soil).emuTexture,
          nPastYears: pasts.get(year).years.length,
          truth: Object.fromEntries([...HINDSIGHT_OFFSETS, ...DECISION_OFFSETS].map((o) => [o, at(o)])),
          oracleOffset, oracleWaterIndex: at(oracleOffset).waterIndex,
          hindsight: { offset: hindsightOffset, waterIndex: at(hindsightOffset).waterIndex, maizeRelYield: at(hindsightOffset).maizeRelYield, negative: hindsightOffset < 0 },
          decisions: decideAll(ctx, site, year, soil, pasts.get(year)),
        });
      }
    }
  }
  return cases;
}

/** Fila de aggregateMetrics para una política y prioridad. */
const metricRow = (c, policy, priority) => {
  const off = c.decisions[policy][priority];
  const simOff = c.decisions.simulator[priority];
  const at = (o) => c.truth[o];
  return {
    offset: off, simOffset: simOff,
    wi: at(off).waterIndex, wiBase: at(0).waterIndex, wiOracle: c.oracleWaterIndex,
    maize: at(off).maizeRelYield, maizeBase: at(0).maizeRelYield, maizeSim: at(simOff).maizeRelYield,
    overlap: at(off).overlapDays, overlapBase: at(0).overlapDays, wiSim: at(simOff).waterIndex,
  };
};

const aqRow = (c, policy, priority) => {
  const off = c.decisions[policy][priority];
  return { id: c.id, aq: c.aquacrop[off], aqBase: c.aquacrop[0], simMaizeGain: c.truth[off].maizeRelYield - c.truth[0].maizeRelYield };
};

/** Métricas de un grupo de casos para las tres políticas y las dos prioridades (AquaCrop solo en los casos con suelo del sitio). */
export function groupAggregates(cases) {
  const withAq = cases.filter((c) => c.aquacrop);
  const policies = {};
  const aquacrop = {};
  for (const policy of POLICIES) {
    policies[policy] = {};
    aquacrop[policy] = {};
    for (const priority of PRIORITIES) {
      policies[policy][priority] = aggregateMetrics(cases.map((c) => metricRow(c, policy, priority)));
      if (withAq.length) aquacrop[policy][priority] = aquacropMetrics(withAq.map((c) => aqRow(c, policy, priority)));
    }
  }
  const hindsight = cases.filter((c) => c.hindsight.negative);
  return {
    n: cases.length, policies, ...(withAq.length ? { aquacrop } : {}),
    hindsightNegative: { count: hindsight.length, meanGainOverOracle: hindsight.length ? hindsight.reduce((s, c) => s + c.hindsight.waterIndex - c.oracleWaterIndex, 0) / hindsight.length : null },
  };
}

export function aggregates(cases) {
  const siteCases = (s) => cases.filter((c) => c.site === s);
  return {
    all: groupAggregates(cases),
    classSoils: groupAggregates(cases.filter((c) => c.soil !== 'site')),
    siteSoil: groupAggregates(cases.filter((c) => c.soil === 'site')),
    byPilot: Object.fromEntries(SITES.map((s) => [s, groupAggregates(siteCases(s))])),
  };
}

// ----------------------------------------------------------------------------- AquaCrop

/** Fecha de siembra del maíz (MM-DD) para un desfase, por resolveMainSowIdx (regla de inicio + desfase, acotada al año agrícola). */
export function maizeSowDate(bundle, year, offset) {
  const start = bundle.dates.indexOf(`${year}-04-01`);
  return bundle.dates[start + resolveMainSowIdx(bundle, year, offset).idx].slice(5);
}

const aqCaseId = (site, year, offset) => `${site}_${year}_o${offset}`;

/** Casos de AquaCrop de un piloto (suelo del sitio): un año × una demora por caso, ya con el suelo resuelto. */
export function aquacropCases(ctx, site, points) {
  const bundle = ctx.bundles[site];
  const cases = TARGET_YEARS.flatMap((year) => DECISION_OFFSETS.map((offset) => ({
    id: aqCaseId(site, year, offset), crop: 'Maize', sowDate: maizeSowDate(bundle, year, offset), years: [year],
    soil: 'site', site, initial: 'dry', offset,
  })));
  return resolveSiteCases(cases, points);
}

function arg(name, argv) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
}

function prepare(dir) {
  const ctx = { bundles: Object.fromEntries(SITES.map((s) => [s, dataJson(`snapshots/${s}.json`)])) };
  const points = readJson(path.join(root, 'scripts/emulator/points.json'));
  fs.mkdirSync(dir, { recursive: true });
  const manifest = SITES.map((site) => {
    const rows = weatherRows(ctx.bundles[site], computeEt0Series(ctx.bundles[site]));
    fs.writeFileSync(path.join(dir, `weather_${site}.txt`), [WEATHER_COLUMNS.join('\t'), ...rows.map((r) => r.join('\t'))].join('\n') + '\n');
    fs.writeFileSync(path.join(dir, `cases_${site}.json`), JSON.stringify({ cases: aquacropCases(ctx, site, points) }, null, 1));
    return { id: site, weather: `weather_${site}.txt`, cases: `cases_${site}.json`, out: `aq_${site}.json` };
  });
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ manifest }, null, 1));
  console.log(`Prepared ${manifest.length} AquaCrop runs (${SITES.length * TARGET_YEARS.length * DECISION_OFFSETS.length} seasons) in ${dir}`);
}

function git(...args) {
  try { return execFileSync('git', ['-C', root, ...args], { encoding: 'utf8' }).trim(); } catch { return null; }
}

/** Mezcla los rendimientos de AquaCrop en las filas de los casos con suelo del sitio; falla fuerte si falta alguno. */
export function mergeAquacrop(cases, aqBySite, ctx) {
  for (const c of cases.filter((x) => x.soil === 'site')) {
    const aq = aqBySite[c.site];
    if (!aq) throw new Error(`AquaCrop results for ${c.site} are missing`);
    c.aquacrop = {};
    for (const offset of DECISION_OFFSETS) {
      const id = aqCaseId(c.site, c.year, offset);
      const found = aq.cases.find((x) => x.id === id);
      if (!found) throw new Error(`AquaCrop case ${id} is missing from the results`);
      requireYields(found, c.site);
      const expected = maizeSowDate(ctx.bundles[c.site], c.year, offset);
      if (found.sowDate !== expected) throw new Error(`AquaCrop case ${id} sowed on ${found.sowDate}, expected ${expected}`);
      if (c.truth[offset].maizeSowDate.slice(5) !== expected) throw new Error(`simulator sowing date of ${id} differs from resolveMainSowIdx (${c.truth[offset].maizeSowDate} vs ${expected})`);
      c.aquacrop[offset] = round(found.results[0].yieldTHa);
    }
  }
}

function score(dir, outPath) {
  const t0 = performance.now();
  const ctx = loadContext();
  const t1 = performance.now();
  const cases = evaluateCases(ctx);
  const t2 = performance.now();
  const aqBySite = {};
  for (const site of SITES) {
    const f = path.join(dir, `aq_${site}.json`);
    if (!fs.existsSync(f)) throw new Error(`AquaCrop results ${f} not found: run aquacrop_referee.py for every manifest entry first`);
    aqBySite[site] = readJson(f);
  }
  mergeAquacrop(cases, aqBySite, ctx);
  const secFile = path.join(dir, 'aquacrop_seconds.txt');
  const aqSeconds = fs.existsSync(secFile) ? Number(fs.readFileSync(secFile, 'utf8').trim()) : null;
  const aq0 = Object.values(aqBySite)[0];
  const dirty = git('status', '--porcelain', '--', 'web/js/model', 'web/data/crops.json', 'web/data/sequences.json', ':(exclude)web/js/model/decision.js');
  const ev = ctx.evalJson;
  const artifact = {
    meta: {
      generated: new Date().toISOString().slice(0, 10),
      repoCommit: git('rev-parse', '--short', 'HEAD'),
      simulatorCommit: git('log', '-1', '--format=%h', '--', 'web/js/model', 'web/data/crops.json', 'web/data/sequences.json'),
      simulatorDirty: dirty === null ? null : dirty.length > 0,
      rule: RULE_TEXT,
      sites: SITES, targetYears: TARGET_YEARS, sequence: SEQUENCE_ID, management: MANAGEMENT,
      soils: { classes: CLASS_SOILS, site: 'SoilGrids soil of the pilot (scripts/emulator/points.json); emulators receive the pilot nearestTexture', nearestTexture: Object.fromEntries(SITES.map((s) => [s, ctx.siteSoil[s].nearestTexture])) },
      feasibleOffsets: DECISION_OFFSETS, hindsightOffsets: HINDSIGHT_OFFSETS,
      priorities: { typical: 'median over past years', cautious: '20th percentile over past years (linear interpolation)' },
      tolerance: TOLERANCE, toleranceNote: 'win/tie/loss on the water index and the maize relYield; also used on AquaCrop yields in t/ha. Simulator-only win = simulator maize gain > 0 and AquaCrop gain <= 0, no tolerance.',
      policies: {
        simulator: 'the simulator (runSequence) on the past years',
        mlp: 'web/data/emulator_mlp.json (funnel network 27-64-32-16-3, backpropagation) via mlpPredict; waterIndex clamped to [0,1] as the page does',
        elmBrowser: 'ELM without backpropagation, trainELM(web/data/emulator_train_subset.json, browserElmRecommendation), as web/js/emulatorPage.js trains it; waterIndex clamped to [0,1]',
      },
      emulators: {
        mlp: { file: 'web/data/emulator_mlp.json', architecture: ctx.mlp.architecture, params: ctx.mlp.params, nFit: ctx.mlp.nFit, valYears: ctx.mlp.valYears },
        elmBrowser: { ...ctx.elmOptions, rows: 'web/data/emulator_train_subset.json', nRows: ctx.subsetRows, trainSecondsHere: round(ctx.elmTrainSeconds, 3) },
        trainedOn: ev.split,
        evalMeta: ev.meta,
        note: 'Both emulators were trained on rows of 20 municipalities (the 3 pilots among them) for agricultural years before 2019; the target years 2019-2024 were never used to train them.',
      },
      truth: 'simulator with the case soil (site soil object for site cases); relYield of the maize counts 0 if its cycle is incomplete; overlap = days from the later sowing to the earlier harvest of maize and beans',
      aquacrop: { version: aq0.aquacropVersion, convention: aq0.convention, scope: 'site-soil cases only, maize only, one season per case, same thetaFC/thetaWP as the simulator, dry start; sowing date from resolveMainSowIdx' },
      runtime: {
        contextSeconds: round((t1 - t0) / 1000, 2), elmTrainSeconds: round(ctx.elmTrainSeconds, 2),
        policyEvaluationSeconds: round((t2 - t1) / 1000, 2),
        policyEvaluationNote: 'truth tables for 12 site-soil combinations x 11 delays plus 3 policies x 2 priorities x 72 cases (each simulator decision re-runs the simulator on the past years)',
        aquacropSeconds: aqSeconds, aquacropSeasons: Object.values(aqBySite).reduce((s, a) => s + a.cases.length, 0),
      },
    },
    cases,
    aggregates: aggregates(cases),
  };
  fs.writeFileSync(outPath, JSON.stringify(artifact, null, 1) + '\n');
  console.log(`Wrote ${outPath} (${cases.length} cases; policy evaluation ${((t2 - t1) / 1000).toFixed(1)} s)`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const [cmd, ...rest] = process.argv.slice(2);
  const dir = arg('dir', rest);
  if (!dir || !['prepare', 'score'].includes(cmd)) throw new Error('Usage: sowing_policy.mjs prepare|score --dir <work dir> [--out web/data/decision_eval.json]');
  if (cmd === 'prepare') prepare(dir);
  else score(dir, arg('out', rest) ?? path.join(root, 'web/data/decision_eval.json'));
}
