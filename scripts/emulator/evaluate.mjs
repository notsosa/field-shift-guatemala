// Evalua la red embudo (forward JS), entrena la ELM en Node, mide tiempos/memoria y escribe web/data/emulator_*.json.
// Uso: node --expose-gc scripts/emulator/evaluate.mjs  (requiere samples.json y web/data/emulator_mlp.json)
import { readFileSync, writeFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series, runSequence } from '../../web/js/model/simulate.js';
import { trainELM, elmPredict, mlpPredict, r2, rmse, mulberry32 } from '../../web/js/model/emulator.js';

const here = (p) => new URL(p, import.meta.url);
const readJson = (u) => JSON.parse(readFileSync(u, 'utf8'));
const { featureNames, targetNames, X, Y, meta } = readJson(here('./samples.json'));
const points = readJson(here('./points.json'));
const net = readJson(here('../../web/data/emulator_mlp.json'));
const held = new Set(points.filter((p) => p.heldOut).map((p) => p.id));
const inYears = (m) => m.year >= 2019 && m.year <= 2024;
const isTest = (m) => inYears(m) || held.has(m.pointId);

const trIdx = [], teIdx = [];
meta.forEach((m, i) => (isTest(m) ? teIdx : trIdx).push(i));
const pick = (idx, A) => idx.map((i) => A[i]);
const Xte = pick(teIdx, X);
console.log(`nTrain ${trIdx.length}, nTest ${teIdx.length}`);

const T = targetNames.length;
const meanOf = (a) => a.reduce((x, y) => x + y, 0) / a.length;
const metrics = (rows, preds) => ({
  r2: Array.from({ length: T }, (_, o) => r2(rows.map((i) => Y[i][o]), preds.map((p) => p[o]))),
  rmse: Array.from({ length: T }, (_, o) => rmse(rows.map((i) => Y[i][o]), preds.map((p) => p[o]))),
});

// --- Red embudo: forward JS ---
const mlpPred = Xte.map((x) => mlpPredict(net, x));
let maxDiff = 0;
net.checkPredictions.forEach(({ index, pred }, k) => {
  if (net.checkInputs[k].some((v, j) => v !== X[index][j])) throw new Error(`checkInputs[${k}] no coincide con samples[${index}]`);
  const js = mlpPredict(net, net.checkInputs[k]);
  for (let o = 0; o < T; o++) maxDiff = Math.max(maxDiff, Math.abs(js[o] - pred[o]));
});
if (!(maxDiff < 1e-4)) throw new Error(`JS y PyTorch discrepan: ${maxDiff}`);
console.log(`JS vs PyTorch (100 filas espaciadas): max |dif| = ${maxDiff.toExponential(2)}`);

// --- ELM ---
// trainELM estandariza Y por dentro y elmPredict devuelve la escala original.
// Barrido de capacidad: mismas filas que la red (train_mlp.py): val = filas de entrenamiento de 2017-2018,
// fit = resto de entrenamiento. Las filas de prueba no se usan para elegir nada.
const VAL_YEARS = [2017, 2018];
const fitIdx = trIdx.filter((i) => !VAL_YEARS.includes(meta[i].year));
const valIdx = trIdx.filter((i) => VAL_YEARS.includes(meta[i].year));
const Xfit = pick(fitIdx, X), Yfit = pick(fitIdx, Y), Xval = pick(valIdx, X);
const nIn = X[0].length;
const elmBytesOf = (hid) => 8 * (hid * hid + hid * T + hid * nIn + hid + hid * T); // A + B + W + b + beta (Float64)
const elmSweep = [];
for (const hidden of [300, 600, 1000, 1500]) {
  for (const lambda of [1e-3, 1e-2, 1e-1]) {
    const t0 = performance.now();
    const mdl = trainELM(Xfit, Yfit, { hidden, lambda, seed: 42 });
    const trainSeconds = (performance.now() - t0) / 1000;
    const valR2 = metrics(valIdx, Xval.map((x) => elmPredict(mdl, x))).r2;
    elmSweep.push({ hidden, lambda, valR2, valR2Mean: meanOf(valR2), trainSeconds, memoryAnalyticMB: elmBytesOf(hidden) / 1048576 });
    console.log(`sweep hidden ${hidden} lambda ${lambda}: val R2 [${valR2.map((v) => v.toFixed(4))}] mean ${meanOf(valR2).toFixed(4)} (${trainSeconds.toFixed(1)} s)`);
  }
}
const argmax = (arr) => arr.reduce((b, e) => (e.valR2Mean > b.valR2Mean || (e.valR2Mean === b.valR2Mean && e.hidden < b.hidden) ? e : b));
const bestCfg = argmax(elmSweep);
const ELM_CFG = { hidden: bestCfg.hidden, lambda: bestCfg.lambda, seed: 42 };
const bestBrowser = argmax(elmSweep.filter((e) => e.hidden <= 600));
const fmt = (e) => `hidden ${e.hidden}, lambda ${e.lambda}: val R2 mean ${e.valR2Mean.toFixed(3)}, ${e.trainSeconds.toFixed(1)} s in Node`;
const browserElmRecommendation = {
  hidden: bestBrowser.hidden, lambda: bestBrowser.lambda,
  note: `Best validation R2 among hidden <= 600 (${fmt(bestBrowser)}) versus the overall best (${fmt(bestCfg)}). In-browser training on the 5,000-row subset is O(rows x hidden^2), so the cap trades some accuracy for a short wait; training times are measured in Node on the full fit set, the browser subset is about ${Math.round(fitIdx.length / 5000)}x smaller.`,
};
if (global.gc) global.gc();
const rss0 = process.memoryUsage().rss;
const e0 = performance.now();
const elm = trainELM(Xfit, Yfit, ELM_CFG);
const elmSeconds = (performance.now() - e0) / 1000;
const rssDelta = process.memoryUsage().rss - rss0; // delta de RSS tras entrenar (no es un pico)
const h = ELM_CFG.hidden;
const elmBytes = elmBytesOf(h);
const elmPred = Xte.map((x) => elmPredict(elm, x));

// --- Linea base ingenua: media de entrenamiento por grupo de manejo ---
const key = (m) => [m.sequenceId, m.irrigation, m.texture, m.slopeClass, m.sowOffsetDays].join('|');
const gSum = new Map();
const gAll = Array(T).fill(0);
for (const i of trIdx) {
  const k = key(meta[i]);
  const g = gSum.get(k) ?? { n: 0, s: Array(T).fill(0) };
  g.n++;
  for (let o = 0; o < T; o++) { g.s[o] += Y[i][o]; gAll[o] += Y[i][o]; }
  gSum.set(k, g);
}
const gMean = gAll.map((v) => v / trIdx.length);
let fallbacks = 0;
const basePred = teIdx.map((i) => {
  const g = gSum.get(key(meta[i]));
  if (!g) { fallbacks++; return gMean; }
  return g.s.map((v) => v / g.n);
});

// --- Subconjuntos ---
const sub = (f) => {
  const pos = teIdx.map((_, j) => j).filter((j) => f(meta[teIdx[j]]));
  const rows = pos.map((j) => teIdx[j]);
  const m = (P) => metrics(rows, pos.map((j) => P[j]));
  return { n: rows.length, mlp: m(mlpPred), elm: m(elmPred), baseline: m(basePred) };
};
const bySplit = {
  testYears: sub((m) => inYears(m) && !held.has(m.pointId)),
  testPoints: sub((m) => held.has(m.pointId) && !inYears(m)),
  testBoth: sub((m) => held.has(m.pointId) && inYears(m)),
};

// --- Estabilidad de semillas de la ELM ---
const SEEDS = [42, 1, 2, 3, 4];
const seedR2 = SEEDS.map((s) => {
  const mdl = s === 42 ? elm : trainELM(Xfit, Yfit, { ...ELM_CFG, seed: s });
  return metrics(teIdx, Xte.map((x) => elmPredict(mdl, x))).r2;
});
const r2Mean = Array.from({ length: T }, (_, o) => meanOf(seedR2.map((r) => r[o])));
const r2Std = Array.from({ length: T }, (_, o) => Math.sqrt(meanOf(seedR2.map((r) => (r[o] - r2Mean[o]) ** 2))));

// --- Tiempos por prediccion ---
const timePredict = (fn, reps) => {
  let sink = 0;
  const t = performance.now();
  for (let r = 0; r < reps; r++) for (let i = 0; i < Xte.length; i++) sink += fn(Xte[i])[0];
  const us = ((performance.now() - t) * 1000) / (reps * Xte.length);
  if (!Number.isFinite(sink)) throw new Error('prediccion no finita');
  return us;
};
const mlpMicros = timePredict((x) => mlpPredict(net, x), 3);
const elmMicros = timePredict((x) => elmPredict(elm, x), 3);

// --- Simulador: un punto x una combinacion x 24 anios ---
const crops = loadCrops(readJson(here('../../web/data/crops.json')));
const sequences = readJson(here('../../web/data/sequences.json'));
const bundles = Object.fromEntries(points.map((p) => [p.id, readJson(here(`./cache/${p.id}.json`))]));
const b0 = bundles[points[0].id];
const et0 = computeEt0Series(b0);
const runOnce = () => runSequence({ sequence: sequences.actual, bundle: b0, et0, crops, texture: 'loam', slopeClass: 'moderate', irrigation: 'none', sowOffsetDays: 0 });
runOnce();
const simRuns = [];
let nYears = 0;
for (let r = 0; r < 5; r++) {
  const t = performance.now();
  nYears = runOnce().length;
  simRuns.push(((performance.now() - t) * 1000) / nYears);
}
const simMicros = meanOf(simRuns);

// --- Celdas POWER compartidas ---
const sig = (b) => `${b.elevation}|${JSON.stringify(b.tmax)}`;
const trainPointIds = points.filter((p) => !p.heldOut).map((p) => p.id);
const shared = {};
for (const id of held) {
  const mates = trainPointIds.filter((o) => sig(bundles[o]) === sig(bundles[id]));
  if (mates.length) shared[id] = mates;
}
const sharedTxt = Object.keys(shared).length
  ? Object.entries(shared).map(([a, b]) => `${a} (with ${b.join(', ')})`).join('; ')
  : 'none';
const caveat = `The spatial hold-out is not fully independent: NASA POWER cells are 0.5 degrees, so some held-out points fall in the same cell as a training point (identical elevation and tmax series). Held-out points sharing a POWER cell with a training point: ${sharedTxt}. Rainfall (IMERG/ERA5) and some other climate features may still differ, but temperature and radiation are shared. Use bySplit.testYears (temporal hold-out at non-held-out points) as the cleanest generalization estimate; testPoints and testBoth mix both effects.`;

const overall = { mlp: metrics(teIdx, mlpPred), elm: metrics(teIdx, elmPred), baseline: metrics(teIdx, basePred) };
const evalOut = {
  targets: targetNames,
  mlp: { rmse: overall.mlp.rmse, r2: overall.mlp.r2, trainSeconds: net.trainSeconds, params: net.params, trainMemoryAnalyticMB: net.trainMemoryAnalyticMB, trainMemoryMeasuredMB: net.trainMemoryMeasuredMB, memoryMethod: net.memoryMethod, epochs: net.epochs, bestValLoss: net.bestValLoss, valYears: net.valYears, predictMicros: mlpMicros,
    speedupVsSimulator: simMicros / mlpMicros },
  elm: { rmse: overall.elm.rmse, r2: overall.elm.r2, trainSeconds: elmSeconds, params: h * nIn + h + h * T,
    trainMemoryAnalyticMB: elmBytes / 1048576, trainMemoryMeasuredMB: rssDelta / 1048576,
    note: 'trainELM standardizes the targets internally (yMean/yStd stored in the model); elmPredict de-standardizes.',
    memoryMethod: 'trainMemoryAnalyticMB = bytes of A (hidden^2) + B (hidden x 3) + W + b + beta as Float64. trainMemoryMeasuredMB = process.memoryUsage().rss after trainELM minus rss before (after global.gc(), run with node --expose-gc); an RSS delta, not a peak, and noisy at this size.',
    predictMicros: elmMicros, speedupVsSimulator: simMicros / elmMicros },
  elmSweep,
  elmConfig: { ...ELM_CFG, fitRows: 'fit (train minus val years 2017–2018)', nFit: fitIdx.length, nVal: valIdx.length },
  browserElmRecommendation,
  elmSeeds: { seeds: SEEDS, r2Mean, r2Std },
  baseline: { rmse: overall.baseline.rmse, r2: overall.baseline.r2,
    description: 'Predicts each target as the TRAIN mean within the same (sequenceId, irrigation, texture, slopeClass, sowOffsetDays) group, ignoring climate; falls back to the global train mean when a group is empty.',
    groupFallbacks: fallbacks, nGroups: gSum.size },
  simulatorMicrosPerYear: simMicros,
  speedupNote: 'speedupVsSimulator compares the model forward pass against the simulator core (runSequence, 24 years averaged per year) with features and ET0 already precomputed.',
  nTrain: trIdx.length, nTest: teIdx.length,
  split: `test = year 2019-2024 OR pointId heldOut (${[...held].sort().join(', ')}); train = rest`,
  bySplit, caveat,
};
writeFileSync(here('../../web/data/emulator_eval.json'), JSON.stringify(evalOut, null, 1));

// --- Subconjunto de entrenamiento para la ELM en el navegador ---
const rnd = mulberry32(7);
const order = trIdx.slice();
for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
const subIdx = order.slice(0, 5000);
writeFileSync(here('../../web/data/emulator_train_subset.json'), JSON.stringify({ featureNames, targetNames, X: pick(subIdx, X), Y: pick(subIdx, Y) }));

const f = (a) => a.map((v) => v.toFixed(4)).join(', ');
console.log(`\nR2 [${targetNames}]`);
for (const m of ['mlp', 'elm', 'baseline']) console.log(`  ${m.padEnd(8)} r2 [${f(evalOut[m].r2)}]  rmse [${f(evalOut[m].rmse)}]`);
console.log(`ELM seeds ${SEEDS}: r2Mean [${f(r2Mean)}], r2Std [${f(r2Std)}]`);
for (const [s, v] of Object.entries(bySplit)) {
  console.log(`bySplit.${s} (n=${v.n})`);
  for (const m of ['mlp', 'elm', 'baseline']) console.log(`  ${m.padEnd(8)} r2 [${f(v[m].r2)}]`);
}
console.log(`MLP train ${net.trainSeconds}s, ${net.epochs} epochs, RSS delta ${net.trainMemoryMeasuredMB} MB (analytic ${net.trainMemoryAnalyticMB} MB)`);
console.log(`ELM chosen ${JSON.stringify(ELM_CFG)}; browser rec ${JSON.stringify({ hidden: bestBrowser.hidden, lambda: bestBrowser.lambda })}`);
console.log(`ELM train ${elmSeconds.toFixed(2)}s, analytic ${(elmBytes / 1048576).toFixed(3)} MB, RSS delta ${(rssDelta / 1048576).toFixed(1)} MB`);
console.log(`predict us: mlp ${mlpMicros.toFixed(2)}, elm ${elmMicros.toFixed(2)}; simulator ${simMicros.toFixed(1)} us/year (${nYears} years); speedup mlp x${(simMicros / mlpMicros).toFixed(0)}, elm x${(simMicros / elmMicros).toFixed(0)}`);
console.log(`baseline groups ${gSum.size}, fallbacks ${fallbacks}`);
console.log(`Shared POWER cells: ${sharedTxt}`);
