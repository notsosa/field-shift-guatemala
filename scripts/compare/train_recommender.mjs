// Entrena y evalúa la red que recomienda (Tarea 31). Diseño fijado de antemano (no se ajusta tras ver resultados de prueba):
// embudo 32 -> 64 -> 32 -> 16 -> 1, estrategia de evolución (mu, lambda): población 32, padres 8, sigma 0.05 en todos los pesos, elitismo 1, 150 generaciones,
// 512 escenarios de entrenamiento por generación (los mismos para todos los individuos, sorteados con la semilla de la generación), cada uno con las dos prioridades.
// Aptitud = promedio de [media de y (prioridad 0), media de y - max(0, 0.5 - y) (prioridad 1)]. El mejor de cada generación se puntúa con todo el conjunto de validación; se guarda el mejor.
// Desde la Tarea 33 el entrenamiento corre en GPU (scripts/gpu/train_recommender.py, núcleo compartido scripts/gpu/es_core.py); este archivo arma la tabla, evalúa y escribe los artefactos.
// El entrenamiento en JS (trainSeed) se conserva como implementación de referencia (--seed) y es el que midió los tiempos "antes" (en web/data/recommender_eval.json de la Tarea 31).
// Uso (en orden): node scripts/compare/train_recommender.mjs --dump                  (escribe scripts/compare/out/recommender_table.json)
//      C:/Users/velas/venv_lab4/Scripts/python.exe scripts/gpu/train_recommender.py   (escribe scripts/compare/out/recommender_es_seed{S}.json)
//      node scripts/compare/train_recommender.mjs                                      (evalúa y escribe web/data/recommender_{mlp,eval}.json y web/data/gpu_checks.json recomendador)
//      node scripts/compare/train_recommender.mjs --seed 17 --work DIR   (solo una semilla, en JS; escribe DIR/seed17.json)
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import { mulberry32 } from '../../web/js/model/emulator.js';
import {
  ACTION_IDS, INPUT_NAMES, N_INPUTS, LAYER_SIZES, paramCount, initParams, standardize, pickAction, recommend, forward, inputRows, outcomeValue, esNext, scoreActions,
} from '../../web/js/model/recommender.js';
import { lossMetrics } from './loss_decision_lib.mjs';
import { outcomeCounts, summarizeObjects } from './aligned_lib.mjs';
import { buildTable } from './recommender_scenarios.mjs';
import { root, readJson } from './loss_decision_core.mjs';

export const DESIGN = { popSize: 32, parents: 8, sigma: 0.05, elite: 1, generations: 150, batch: 512, seeds: [17, 29, 43], layers: LAYER_SIZES };
const PRI = [0, 1];
const PRI_NAME = { 0: 'typical', 1: 'cautious' };

// Estandarización con filas de entrenamiento solamente: escenario x prioridad x acción.
function fitStandardization(train) {
  const n = train.length * PRI.length * ACTION_IDS.length;
  const mean = new Array(N_INPUTS).fill(0), std = new Array(N_INPUTS).fill(0);
  const each = (f) => { for (const s of train) for (const p of PRI) for (const r of inputRows(s.state, p, s.actionRows)) f(r); };
  each((r) => r.forEach((v, j) => { mean[j] += v / n; }));
  each((r) => r.forEach((v, j) => { std[j] += (v - mean[j]) ** 2 / n; }));
  return { mean, std: std.map(Math.sqrt) };
}
const withInputs = (list, mean, std) => list.forEach((s) => { s.xs = PRI.map((p) => inputRows(s.state, p, s.actionRows).map((r) => standardize(r, mean, std))); });

/** Elige la acción de un escenario con una red (entradas ya estandarizadas en s.xs). */
function chooseIdx(params, s, p) {
  const scores = ACTION_IDS.map((a, i) => (i === s.ruleIdx ? 1 : 0) + Math.tanh(forward(params, s.xs[p][i])));
  return ACTION_IDS.indexOf(pickAction(scores, s.rule));
}
/** Aptitud en un conjunto de escenarios: promedio entre prioridades de la media del valor del resultado. */
function fitness(params, list) {
  let total = 0;
  for (const p of PRI) { let s = 0; for (const sc of list) s += outcomeValue(sc.y[chooseIdx(params, sc, p)], p); total += s / list.length; }
  return total / PRI.length;
}
const ruleFitness = (list) => PRI.reduce((t, p) => t + list.reduce((s, sc) => s + outcomeValue(sc.y[sc.ruleIdx], p), 0) / list.length, 0) / PRI.length;

function drawBatch(n, size, seed, gen) { // submuestra sin reemplazo con la semilla de la generación
  const rng = mulberry32(seed * 100003 + gen), idx = Array.from({ length: n }, (_, i) => i);
  for (let i = 0; i < size; i++) { const j = i + Math.floor(rng() * (n - i)); [idx[i], idx[j]] = [idx[j], idx[i]]; }
  return idx.slice(0, size);
}

function trainSeed(seed, table) {
  const { train, val } = table;
  const { mean, std } = fitStandardization(train);
  withInputs(train, mean, std); withInputs(val, mean, std);
  const rng = mulberry32(seed);
  const init = initParams(seed);
  // individuo 0 = la red inicial (igual a la regla); el resto, mutaciones suyas
  let pop = esNext(Array(DESIGN.popSize).fill(init), Array(DESIGN.popSize).fill(0), rng, DESIGN).next;
  const curve = [];
  let best = null, evals = 0;
  const t0 = performance.now();
  for (let g = 0; g < DESIGN.generations; g++) {
    const batch = drawBatch(train.length, DESIGN.batch, seed, g).map((i) => train[i]);
    const fit = pop.map((ind) => fitness(ind, batch));
    evals += pop.length * batch.length * PRI.length;
    const { next, order } = esNext(pop, fit, rng, DESIGN);
    const champion = pop[order[0]];
    const valFit = fitness(champion, val);
    curve.push({ gen: g, trainBest: fit[order[0]], trainMean: fit.reduce((a, b) => a + b, 0) / fit.length, val: valFit });
    if (!best || valFit > best.val) best = { gen: g, val: valFit, params: Array.from(champion) };
    pop = next;
  }
  return { seed, seconds: (performance.now() - t0) / 1000, scenarioEvals: evals, curve, best, mean, std, ruleVal: ruleFitness(val), initVal: fitness(init, val) };
}

// --- Evaluación en los casos de prueba ---
const caseRows = (params, list, p) => list.map((s) => {
  const idx = params ? chooseIdx(params, s, p) : s.ruleIdx;
  return { idx, action: ACTION_IDS[idx], value: s.y[idx], executable: s.executable[idx], ruleValue: s.y[s.ruleIdx], oracleValue: Math.max(...s.y), simAction: s.rule };
});
function metricsOf(params, list, p) {
  const rows = caseRows(params, list, p);
  const m = lossMetrics(rows);
  const c = outcomeCounts(rows.map((r, i) => ({ value: r.value, action: r.action, ruleAction: list[i].rule })));
  const departures = rows.map((r, i) => ({ r, s: list[i] })).filter(({ r, s }) => r.action !== s.rule)
    .map(({ r, s }) => ({ site: s.point, year: s.year, lossDay: s.lossDay, rule: s.rule, chose: r.action, valueChosen: r.value, valueRule: r.ruleValue, oracle: s.oracle }));
  return { n: m.n, chosenMean: m.chosenMean, meanGainVsRule: m.meanGainVsRule, win: m.win, tie: m.tie, loss: m.loss, meanRegret: m.meanRegret, p10: m.p10, worst: m.worst, executable: m.executable, below05: c.below05, departsFromRule: c.departsFromRule, actions: m.actions, departures };
}
const FIELDS = ['chosenMean', 'meanGainVsRule', 'win', 'tie', 'loss', 'meanRegret', 'p10', 'worst', 'executable', 'below05', 'departsFromRule'];

const OUT_DIR = path.join(root, 'scripts/compare/out');
const sameTop = (a, b) => ACTION_IDS[a.indexOf(Math.max(...a))] === ACTION_IDS[b.indexOf(Math.max(...b))];

async function runAll() {
  const { table, seconds: tableSeconds } = buildTable();
  const OLD_COMMIT = '4778afc'; // Tarea 31/32: artefacto con el entrenamiento en JS, para los tiempos "antes" y los números anteriores
  const oldEval = JSON.parse(execFileSync('git', ['-C', root, 'show', `${OLD_COMMIT}:web/data/recommender_eval.json`], { encoding: 'utf8', maxBuffer: 1 << 28 }));
  const gpu = DESIGN.seeds.map((s) => readJson(path.join(OUT_DIR, `recommender_es_seed${s}.json`)));
  const runs = gpu.map((g) => ({
    seed: g.seed, seconds: g.seconds, scenarioEvals: g.scenarioEvals, mean: g.mean, std: g.std, ruleVal: g.valFitness.rule, initVal: g.valFitness.initialIdentity,
    best: { gen: g.bestGen, val: g.valFitness.best, params: g.params }, curve: g.curve,
  }));
  const aligned = readJson(path.join(root, 'web/data/aligned_eval.json'));
  const YEARS = { years2019_2024: [2019, 2020, 2021, 2022, 2023, 2024], reserved2022_2024: [2022, 2023, 2024] };
  const nets = {};
  for (const run of runs) { const test = table.test.map((s) => ({ ...s })); withInputs(test, run.mean, run.std); nets[run.seed] = { params: run.best.params, test }; }
  // Comprobación cruzada JS vs PyTorch: los puntajes de las 8 acciones (con la regla) de una muestra de escenarios de validación y prueba, calculados aquí con recommender.js.
  const crossCheck = {};
  for (const g of gpu) {
    let maxDiff = 0, same = 0, n = 0;
    for (const c of g.check) {
      const sc = table[c.split][c.index];
      const js = scoreActions({ params: Float64Array.from(g.params), mean: g.mean, std: g.std }, inputRows(sc.state, c.priority, sc.actionRows), sc.rule);
      js.forEach((v, i) => { maxDiff = Math.max(maxDiff, Math.abs(v - c.scores[i])); });
      if (pickAction(js, sc.rule) === c.action) same++;
      n++;
    }
    crossCheck[g.seed] = { rows: n, maxScoreDiff: maxDiff, sameRecommendation: same };
    if (!(maxDiff < 1e-5) || same !== n) throw new Error(`JS y PyTorch discrepan (semilla ${g.seed}): ${maxDiff}, ${same}/${n}`);
  }
  const decision = { perSeed: {}, summary: {}, reference: {} };
  for (const [setName, years] of Object.entries(YEARS)) {
    const sub = (list) => list.filter((s) => years.includes(s.year));
    const ref = sub(nets[DESIGN.seeds[0]].test);
    decision.reference[setName] = {
      n: ref.length, years,
      ruleRecomputed: metricsOf(null, ref, 0),
      oracle: aligned.decision.noSeed[setName].oracle,
      simulatorPolicy: aligned.decision.noSeed[setName].simulator,
      predictThenChoose: Object.fromEntries(DESIGN.seeds.map((s) => [s, aligned.decision.perSeed[setName][s]])),
    };
    decision.perSeed[setName] = {}; decision.summary[setName] = {};
    for (const p of PRI) {
      const list = DESIGN.seeds.map((s) => metricsOf(nets[s].params, sub(nets[s].test), p));
      DESIGN.seeds.forEach((s, k) => { (decision.perSeed[setName][s] ??= {})[PRI_NAME[p]] = list[k]; });
      decision.summary[setName][PRI_NAME[p]] = summarizeObjects(list, FIELDS);
    }
  }
  // tiempo por recomendación (8 acciones, con estandarización) sobre los 54 casos de prueba, 20 vueltas
  const net = { params: nets[DESIGN.seeds[0]].params, mean: runs[0].mean, std: runs[0].std };
  const raw = table.test.map((s) => ({ rows: inputRows(s.state, 0, s.actionRows), rule: s.rule }));
  const tr = performance.now(); let nrec = 0;
  for (let rep = 0; rep < 20; rep++) for (const r of raw) { recommend(net, r.rows, r.rule); nrec++; }
  const msPerRecommendation = (performance.now() - tr) / nrec;
  const best = runs.reduce((a, b) => (b.best.val > a.best.val ? b : a));
  const git = (...a) => execFileSync('git', ['-C', root, ...a], { encoding: 'utf8' }).trim();
  const out = {
    meta: {
      simulatorCommit: git('rev-parse', '--short', 'HEAD'), generated: new Date().toISOString().slice(0, 10), design: DESIGN, parameterCount: paramCount(), inputNames: INPUT_NAMES,
      scenarios: { train: table.train.length, val: table.val.length, test: table.test.length }, tableSeconds, gpu: { device: gpu[0].deviceName, torch: gpu[0].torchVersion, secondsPerSeed: Object.fromEntries(gpu.map((g) => [g.seed, g.seconds])), randomStream: 'torch CUDA generator seeded per seed (not mulberry32): same design and distributions as the JS run, other numbers', jsReference: `training.* of the Task 31 artifact (commit ${OLD_COMMIT}; JS, one process per seed, 3 in parallel) is kept in meta.jsBaseline` }, jsBaseline: oldEval.training ? Object.fromEntries(Object.entries(oldEval.training).map(([k, v]) => [k, { seconds: v.seconds, scenarioEvalsPerSecond: v.scenarioEvalsPerSecond, bestGen: v.bestGen, valBest: v.valFitness.best }])) : null, msPerRecommendation,
      priorityMap: { 0: 'typical (rendir más en un año típico)', 1: 'cautious (no perder en un año malo)' },
      referenceNote: 'oracle, simulator-policy and predict-then-choose rows are copied from web/data/aligned_eval.json (same seeds), not recomputed; the rule row is recomputed here as a check.',
      noMargin: 'Margin is not computed: the judge has no prices or costs.',
      selected: { seed: best.seed, generation: best.best.gen, valFitness: best.best.val },
    },
    training: Object.fromEntries(runs.map((r) => [r.seed, {
      seconds: r.seconds, scenarioEvals: r.scenarioEvals, scenarioEvalsPerSecond: r.scenarioEvals / r.seconds, bestGen: r.best.gen,
      valFitness: { first: r.curve[0].val, best: r.best.val, last: r.curve.at(-1).val, initialIdentity: r.initVal, rule: r.ruleVal },
      trainBest: { first: r.curve[0].trainBest, last: r.curve.at(-1).trainBest },
      curve: r.curve.map((c) => ({ gen: c.gen, trainBest: c.trainBest, val: c.val })),
    }])),
    jsVsTorchCheck: crossCheck,
    decision,
  };
  fs.writeFileSync(path.join(root, 'web/data/recommender_eval.json'), JSON.stringify(out, null, 1));
  fs.writeFileSync(path.join(root, 'web/data/recommender_mlp.json'), JSON.stringify({
    kind: 'recommender', seed: best.seed, generation: best.best.gen, valFitness: best.best.val, layerSizes: LAYER_SIZES, inputNames: INPUT_NAMES, actions: ACTION_IDS,
    activation: 'tanh hidden, linear output; score = rule score + tanh(output)', mean: best.mean, std: best.std, params: best.best.params,
    standardisation: 'mean and std over training rows only (scenario x priority x action)',
  }));
  for (const r of runs) console.log(`seed ${r.seed}: val first/best/last ${r.curve[0].val.toFixed(4)}/${r.best.val.toFixed(4)}/${r.curve.at(-1).val.toFixed(4)} (best gen ${r.best.gen}; identity ${r.initVal.toFixed(4)})`);
}

const arg = (k) => { const i = process.argv.indexOf(k); return i < 0 ? null : process.argv[i + 1]; };
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  if (process.argv.includes('--dump')) {
    const { table, seconds } = buildTable();
    fs.mkdirSync(OUT_DIR, { recursive: true });
    const slim = (list) => list.map((s) => ({ state: s.state, actionRows: s.actionRows, y: s.y, ruleIdx: s.ruleIdx }));
    fs.writeFileSync(path.join(OUT_DIR, 'recommender_table.json'), JSON.stringify({ design: DESIGN, actions: ACTION_IDS, inputNames: INPUT_NAMES, train: slim(table.train), val: slim(table.val), test: slim(table.test) }));
    console.log(`tabla escrita (${table.train.length}/${table.val.length}/${table.test.length}) en ${seconds.toFixed(1)} s`);
  } else if (arg('--seed')) {
    const seed = Number(arg('--seed'));
    const { table, seconds } = buildTable();
    console.log(`seed ${seed}: tabla en ${seconds.toFixed(1)} s (${table.train.length}/${table.val.length}/${table.test.length})`);
    const r = trainSeed(seed, table);
    fs.writeFileSync(path.join(arg('--work'), `seed${seed}.json`), JSON.stringify(r));
    console.log(`seed ${seed}: ${r.seconds.toFixed(0)} s, val best ${r.best.val.toFixed(4)} en la generación ${r.best.gen}`);
  } else await runAll();
}
