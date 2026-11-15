// Evalúa las políticas de riego del café en validación y prueba y escribe web/data/coffee_eval.json y web/data/coffee_recommender.json (Tarea 32).
// Requiere: node scripts/coffee/scenarios.mjs, train_es.py, ptc_mlp.py (y opcionalmente bench_js.mjs). El ELM (1500 ocultas, escala 0.1, lambda 0.1) se ajusta en GPU, una vez por semilla (python scripts/gpu/elm_gpu.py coffee; antes, en JS dentro de este archivo: tiempos en meta.timing.elmSecondsJs, del commit 4778afc).
// Uso: node scripts/coffee/evaluate.mjs
import fs from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { r2, rmse } from '../../web/js/model/emulator.js';
import { forward, standardize } from '../../web/js/model/recommender.js';
import { STATE_NAMES, PRICE, IRRIGATION_MM, HORIZON_DAYS, DECISION_DAYS } from '../../web/js/model/coffee.js';
import { summarizeObjects } from '../compare/aligned_lib.mjs';
import { metrics, oracleIrrigates } from './eval_lib.mjs';
import { RESERVED, SPLITS, MIN_ELEVATION } from './scenarios.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const cache = (f) => path.join(root, 'scripts/coffee/cache', f);
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
const SEEDS = [17, 29, 43];
const ELM_CFG = { hidden: 1500, inputScale: 0.1, lambda: 0.1 };
const T = readJson(cache('coffee_table.json'));
const S = T.scenarios;
const idxOf = (pred) => S.map((s, i) => (pred(s) ? i : -1)).filter((i) => i >= 0);
const SET = {
  val: idxOf((s) => s.split === 'val'), test: idxOf((s) => s.split === 'test'), reserved2022_2024: idxOf((s) => s.split === 'test' && RESERVED.includes(s.year)),
};
const GROUPS = { all: () => true, noShade: (s) => s.shade === 'none', withTrees: (s) => s.shade !== 'none', evergreen: (s) => s.shade === 'evergreen', deciduous: (s) => s.shade === 'deciduous' };
const PRI = [0, 1], PRI_NAME = { 0: 'saveWater', 1: 'protectCrop' };
const FIELDS = ['meanUtility', 'gainVsRule', 'win', 'tie', 'loss', 'regretVsOracle', 'irrigations', 'stressDaysLeft', 'departsFromRule'];

// --- políticas: decisiones (0/1) para cada escenario y prioridad ---
const ruleDec = () => S.map((s) => [s.rule, s.rule]);
const neverDec = () => S.map(() => [0, 0]);
const alwaysDec = () => S.map(() => [1, 1]);
const oracleDec = () => S.map((s) => PRI.map((p) => (oracleIrrigates(s, p) ? 1 : 0)));
const ptcDec = (pred) => S.map((_, i) => PRI.map((p) => (pred[i] > PRICE[p] ? 1 : 0)));

function recommenderScores(net, s, p) {
  const x = (a) => standardize([...s.state, p, a], net.mean, net.std);
  const sNot = (1 - s.rule) + Math.tanh(forward(net.params, x(0), net.layerSizes));
  const sIrr = s.rule + Math.tanh(forward(net.params, x(1), net.layerSizes));
  return { sNot, sIrr };
}
function recommenderDec(net) {
  return S.map((s) => PRI.map((p) => { const { sNot, sIrr } = recommenderScores(net, s, p); const d = sIrr - sNot; return Math.abs(d) <= 1e-12 ? s.rule : d > 0 ? 1 : 0; }));
}

function evaluateDec(dec) {
  const out = {};
  for (const [setName, idx] of Object.entries(SET)) {
    out[setName] = {};
    for (const [gName, gf] of Object.entries(GROUPS)) {
      const ids = idx.filter((i) => gf(S[i]));
      out[setName][gName] = Object.fromEntries(PRI.map((p) => [PRI_NAME[p], metrics(ids.map((i) => S[i]), ids.map((i) => dec[i][p]), p)]));
    }
  }
  return out;
}
const summarize = (perSeed) => { // perSeed: [evaluateDec(...)] -> mean/min/max por conjunto, grupo, prioridad y campo
  const out = {};
  for (const setName of Object.keys(perSeed[0])) {
    out[setName] = {};
    for (const g of Object.keys(perSeed[0][setName])) {
      out[setName][g] = {};
      for (const p of Object.values(PRI_NAME)) out[setName][g][p] = summarizeObjects(perSeed.map((e) => e[setName][g][p]), FIELDS);
    }
  }
  return out;
};

// --- redes ---
const es = SEEDS.map((s) => readJson(cache(`es_seed${s}.json`)));
const mlp = SEEDS.map((s) => readJson(cache(`ptc_mlp_seed${s}.json`)));

// comprobación cruzada JS vs PyTorch del pase hacia adelante (puntajes y recomendación) en la muestra guardada por train_es.py
const crossCheck = es.map((r) => {
  let maxDiff = 0, same = 0, n = 0;
  const net = { params: r.params, mean: r.mean, std: r.std, layerSizes: r.layerSizes };
  r.check.index.forEach((i, k) => PRI.forEach((p) => {
    const { sNot, sIrr } = recommenderScores(net, S[i], p);
    maxDiff = Math.max(maxDiff, Math.abs(sNot - r.check.sNot[k][p]), Math.abs(sIrr - r.check.sIrr[k][p]));
    const d = sIrr - sNot; const js = Math.abs(d) <= 1e-12 ? S[i].rule : d > 0 ? 1 : 0;
    same += js === r.check.irrigate[k][p] ? 1 : 0; n++;
  }));
  return { seed: r.seed, rows: n, maxAbsScoreDiff: maxDiff, sameRecommendation: same };
});
for (const c of crossCheck) if (c.maxAbsScoreDiff > 1e-5 || c.sameRecommendation !== c.rows) throw new Error(`JS and PyTorch forward passes disagree for seed ${c.seed}: ${JSON.stringify(c)}`);

// ELM por semilla: filas de entrenamiento 2001-2016
const trainIdx = idxOf((s) => s.split === 'train');
const elmPred = [], elmSeconds = [];
for (const seed of SEEDS) {
  const f = readJson(cache(`elm_seed${seed}.json`)); // predicción de todos los escenarios (ajuste en GPU con las filas train)
  if (f.seed !== seed || f.pred.length !== S.length) throw new Error(`elm_seed${seed}.json no coincide con la tabla`);
  elmPred.push(f.pred); elmSeconds.push(f.trainSeconds);
  console.log(`ELM seed ${seed} (GPU): ${f.trainSeconds.toFixed(2)} s`);
}
const OLD_COMMIT = '4778afc';
const elmSecondsJs = JSON.parse(execFileSync('git', ['-C', root, 'show', `${OLD_COMMIT}:web/data/coffee_eval.json`], { encoding: 'utf8', maxBuffer: 1 << 28 })).meta.timing.elmSeconds;

const regr = (pred) => Object.fromEntries(Object.entries(SET).map(([k, idx]) => [k, { n: idx.length, r2: r2(idx.map((i) => S[i].avoided), idx.map((i) => pred[i])), rmse: rmse(idx.map((i) => S[i].avoided), idx.map((i) => pred[i])) }]));

const nets = es.map((r) => ({ params: r.params, mean: r.mean, std: r.std, layerSizes: r.layerSizes }));
const recDec = nets.map(recommenderDec);
const perSeed = {
  recommender: es.map((r, k) => evaluateDec(recDec[k])),
  predictThenChooseMlp: mlp.map((r) => evaluateDec(ptcDec(r.pred))),
  predictThenChooseElm: elmPred.map((p) => evaluateDec(ptcDec(p))),
};
const noSeed = { rule: evaluateDec(ruleDec()), never: evaluateDec(neverDec()), always: evaluateDec(alwaysDec()), oracle: evaluateDec(oracleDec()) };
const summary = Object.fromEntries(Object.entries(perSeed).map(([k, v]) => [k, summarize(v)]));

// tiempo por decisión de la red que recomienda (4 filas, con estandarización), 20 vueltas sobre el conjunto de prueba
const t1 = performance.now(); let nrec = 0;
for (let rep = 0; rep < 20; rep++) for (const i of SET.test) { recommenderScores(nets[0], S[i], 0); nrec++; }
const msPerRecommendation = (performance.now() - t1) / nrec;

// estrés por año cafetalero con y sin sombra (medidas de la Parte A), media sobre sitios, suelos y años 2001-2024
const ym = T.yearMeasures;
const meanOf = (a) => a.reduce((x, y) => x + y, 0) / a.length;
const shadeStress = Object.fromEntries(['none', 'evergreen', 'deciduous'].map((sh) => {
  const r = ym.filter((y) => y.shade === sh);
  const f = (k, q) => meanOf(r.map((y) => y[k][q]));
  return [sh, { n: r.length, fruitSetStressDays: f('fruitSet', 'stressDays'), grainFillStressDays: f('grainFill', 'stressDays'), drySeasonStressDays: f('drySeason', 'stressDays'),
    fruitSetEtaOverEtc: f('fruitSet', 'etaOverEtc'), grainFillEtaOverEtc: f('grainFill', 'etaOverEtc'), drySeasonEtaOverEtc: f('drySeason', 'etaOverEtc') }];
}));
const noTrigger = { years: ym.filter((y) => y.shade === 'none' && y.soil === 'loam').length, noTrigger: ym.filter((y) => y.shade === 'none' && y.soil === 'loam' && y.noTrigger).length };
const git = (...a) => execFileSync('git', ['-C', root, ...a], { encoding: 'utf8' }).trim();
const jsBench = fs.existsSync(cache('bench_js.json')) ? readJson(cache('bench_js.json')) : null;
const best = es.reduce((a, b) => (b.valFitness.best > a.valFitness.best ? b : a));
const sites = T.sites.map((s) => ({ ...s, arabicaOptimumC: [18, 21], inArabicaOptimum: s.meanTempC >= 18 && s.meanTempC <= 21 }));

const out = {
  meta: {
    simulatorCommit: git('rev-parse', '--short', 'HEAD'), generated: new Date().toISOString().slice(0, 10),
    decision: { irrigationMm: IRRIGATION_MM, horizonDays: HORIZON_DAYS, decisionDaysAfterFlowering: DECISION_DAYS, price: { saveWater: PRICE[0], protectCrop: PRICE[1] }, utility: 'irrigate: stressDaysAvoided - price; do not irrigate: 0' },
    splits: SPLITS, reserved: RESERVED, minElevationM: MIN_ELEVATION, scenarios: Object.fromEntries(Object.entries(SET).map(([k, v]) => [k, v.length])), trainScenarios: trainIdx.length,
    inputNames: STATE_NAMES, soils: ['sand', 'loam', 'clay'], shades: ['none', 'evergreen', 'deciduous'],
    caseDefinition: 'one case = site x soil x coffee year x decision day (30/60/90) x shade configuration; coffee year Y = 1 Nov Y to 31 Oct Y+1; test cases of different shades/soils at the same site-year share the weather',
    noTrigger, tableSeconds: T.meta.seconds,
    design: { layers: [18, 64, 32, 16, 1], popSize: 32, parents: 8, sigma: 0.05, elite: 1, generations: 150, batch: 512, seeds: SEEDS, elm: { ...ELM_CFG, seedNote: 'per seed (random hidden layer)' }, ptcMlp: { layers: [16, 64, 32, 16, 1], recipe: 'fit_network of scripts/emulator/train_mlp.py (Adam 1e-3, batch 256, patience 10 on 2017-2018), N_OUT = 1' } },
    randomStreamNote: 'The recommender was trained by the evolution strategy implemented in PyTorch on the GPU (scripts/coffee/train_es.py). Its random stream is torch\'s CUDA generator seeded with 17/29/43, not the mulberry32 stream of the JS recommender; design and distributions are the same, the numbers differ.',
    crossCheckJsVsTorch: crossCheck,
    timing: {
      gpuEs: Object.fromEntries(es.map((r) => [r.seed, { seconds: r.seconds, scenarioEvals: r.scenarioEvals, scenarioEvalsPerSecond: r.scenarioEvalsPerSecond }])),
      jsEsBenchmark: jsBench, device: es[0].deviceName, torchVersion: es[0].torchVersion,
      ptcMlpSeconds: Object.fromEntries(mlp.map((r) => [r.seed, { seconds: r.trainSeconds, epochs: r.epochs }])), elmSeconds: Object.fromEntries(SEEDS.map((s, k) => [s, elmSeconds[k]])), elmSecondsJs, elmFit: 'GPU (scripts/gpu/elm_gpu.py); elmSecondsJs = the JS fit of the previous commit', msPerRecommendation,
    },
    selected: { seed: best.seed, generation: best.bestGen, valFitness: best.valFitness.best },
    noMargin: 'No yield and no money: coffee has no FAO Ky. The judge is our simulator.',
  },
  sites, shadeStress,
  training: Object.fromEntries(es.map((r) => [r.seed, { seconds: r.seconds, bestGen: r.bestGen, valFitness: r.valFitness, curve: r.curve.map((c) => ({ gen: c.gen, trainBest: c.trainBest, val: c.val })) }])),
  regression: { mlp: Object.fromEntries(SEEDS.map((s, k) => [s, regr(mlp[k].pred)])), elm: Object.fromEntries(SEEDS.map((s, k) => [s, regr(elmPred[k])])) },
  policies: { noSeed, perSeed, summary },
};
fs.writeFileSync(path.join(root, 'web/data/coffee_eval.json'), JSON.stringify(out, null, 1));
fs.writeFileSync(path.join(root, 'web/data/coffee_recommender.json'), JSON.stringify({
  kind: 'coffee_irrigation_recommender', seed: best.seed, generation: best.bestGen, valFitness: best.valFitness.best, layerSizes: best.layerSizes,
  inputNames: [...STATE_NAMES, 'priority', 'irrigate'], actions: ['do_not_irrigate', 'irrigate'],
  activation: 'tanh hidden, linear output; score of an action = (1 if it is the rule action) + tanh(output)', rule: 'irrigate if the capped running water balance since 1 Nov exceeds p = 0.40 of the available water (FAO-56)',
  mean: best.mean, std: best.std, params: best.params, standardisation: 'mean and std over training rows only (scenario x priority x action); trained on the GPU, see meta.randomStreamNote in coffee_eval.json',
}));
const pr = (name, e) => console.log(name.padEnd(12), PRI.map((p) => `${PRI_NAME[p]}: util ${e.test.all[PRI_NAME[p]].meanUtility?.toFixed(3)} irr ${e.test.all[PRI_NAME[p]].irrigations}`).join(' | '));
for (const [k, v] of Object.entries(noSeed)) pr(k, v);
SEEDS.forEach((s, k) => { pr(`rec ${s}`, perSeed.recommender[k]); pr(`mlp ${s}`, perSeed.predictThenChooseMlp[k]); pr(`elm ${s}`, perSeed.predictThenChooseElm[k]); });
SEEDS.forEach((s) => console.log(`R2 test mlp ${s}: ${out.regression.mlp[s].test.r2.toFixed(3)}  elm: ${out.regression.elm[s].test.r2.toFixed(3)}`));
console.log('cross-check', JSON.stringify(crossCheck));
