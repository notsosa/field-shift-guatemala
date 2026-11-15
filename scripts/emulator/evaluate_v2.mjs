// Evalúa el emulador v2 (red embudo y ELM) contra la simulación y una línea base; escribe web/data/emulator_v2_eval.json.
// Uso: node scripts/emulator/evaluate_v2.mjs  (requiere samples_v2.json y web/data/emulator_v2_mlp.json)
import { readFileSync, writeFileSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
import { trainELM, elmPredict, mlpPredict, r2, rmse } from '../../web/js/model/emulator.js';

const here = (p) => new URL(p, import.meta.url);
const readJson = (u) => JSON.parse(readFileSync(u, 'utf8'));
const { featureNames, targetNames, X, Y, meta, provenance } = readJson(here('./samples_v2.json'));
const net = readJson(here('../../web/data/emulator_v2_mlp.json'));
const points = readJson(here('./points.json'));
const held = new Set(points.filter((p) => p.heldOut).map((p) => p.id));
const inYears = (m) => m.year >= 2019 && m.year <= 2024;
const trIdx = [], teIdx = [];
meta.forEach((m, i) => ((inYears(m) || held.has(m.pointId)) ? teIdx : trIdx).push(i));
const pick = (idx, A) => idx.map((i) => A[i]);
const T = targetNames.length;
const FIT = 2;
const ELM_CFG = { hidden: 1500, inputScale: 0.1, lambda: 0.1, seed: 42 };

// MLP
const mlpAll = X.map((x) => mlpPredict(net, x));
let maxDiff = 0;
net.checkPredictions.forEach(({ index, pred }, k) => {
  const js = mlpPredict(net, net.checkInputs[k]);
  for (let o = 0; o < T; o++) maxDiff = Math.max(maxDiff, Math.abs(js[o] - pred[o]));
});
if (!(maxDiff < 1e-4)) throw new Error(`JS y PyTorch discrepan: ${maxDiff}`);

// ELM: ajuste en entrenamiento sin los años de validación 2017-2018 (como v1)
const fitIdx = trIdx.filter((i) => ![2017, 2018].includes(meta[i].year));
const e0 = performance.now();
const elm = trainELM(pick(fitIdx, X), pick(fitIdx, Y), ELM_CFG);
const elmSeconds = (performance.now() - e0) / 1000;
const elmAll = X.map((x) => elmPredict(elm, x));

// Línea base: media de entrenamiento por A x B x suelo
const key = (m) => [m.A, m.B, m.soil].join('|');
const g = new Map(); const gAll = Array(T).fill(0);
for (const i of trIdx) {
  const k = key(meta[i]); const e = g.get(k) ?? { n: 0, s: Array(T).fill(0) };
  e.n++; for (let o = 0; o < T; o++) { e.s[o] += Y[i][o]; gAll[o] += Y[i][o]; } g.set(k, e);
}
let fallbacks = 0;
const baseAll = X.map((_, i) => { const e = g.get(key(meta[i])); if (!e) { fallbacks++; return gAll.map((v) => v / trIdx.length); } return e.s.map((v) => v / e.n); });

const confusion = (rows, P) => {
  let tp = 0, fp = 0, fn = 0, tn = 0;
  for (const i of rows) { const t = Y[i][FIT] >= 0.5, p = P[i][FIT] >= 0.5; if (t && p) tp++; else if (!t && p) fp++; else if (t) fn++; else tn++; }
  const precision = tp + fp ? tp / (tp + fp) : null, recall = tp + fn ? tp / (tp + fn) : null;
  return { accuracy: (tp + tn) / rows.length, precision, recall, f1: precision != null && recall != null && precision + recall > 0 ? (2 * precision * recall) / (precision + recall) : null, tp, fp, fn, tn };
};
const score = (rows, P) => ({
  r2: Array.from({ length: T }, (_, o) => r2(rows.map((i) => Y[i][o]), rows.map((i) => P[i][o]))),
  rmse: Array.from({ length: T }, (_, o) => rmse(rows.map((i) => Y[i][o]), rows.map((i) => P[i][o]))),
  fitClassification: confusion(rows, P),
});
const SPLITS = {
  all: () => true,
  newYears: (m) => inYears(m) && !held.has(m.pointId),
  newPoints: (m) => held.has(m.pointId) && !inYears(m),
};
const models = { mlp: mlpAll, elm: elmAll, baseline: baseAll };
const bySplit = {};
for (const [name, f] of Object.entries(SPLITS)) {
  const rows = teIdx.filter((i) => f(meta[i]));
  bySplit[name] = { n: rows.length, ...Object.fromEntries(Object.entries(models).map(([k, P]) => [k, score(rows, P)])) };
}

// Tiempos por predicción (µs) con las filas de prueba
const timeIt = (fn, reps) => { let s = 0; const t = performance.now(); for (let r = 0; r < reps; r++) for (const i of teIdx) s += fn(X[i])[0]; if (!Number.isFinite(s)) throw new Error('no finito'); return ((performance.now() - t) * 1000) / (reps * teIdx.length); };
timeIt((x) => mlpPredict(net, x), 1);
const mlpMicros = timeIt((x) => mlpPredict(net, x), 2);
const elmMicros = timeIt((x) => elmPredict(elm, x), 1);
const nIn = featureNames.length;
const out = {
  meta: { ...provenance, evaluated: new Date().toISOString().slice(0, 10) },
  description: 'Emulator v2: successions of seven crops (A then B or none), 20 points, years 2001-2024, soil sand/loam/clay, flat, rainfed, sowing offset 0/15/30 days. Truth = the JS simulator (simulateSuccessionYear). relYield of an incomplete cycle = 0; fit = 1 if every sown crop completes inside the agricultural year.',
  features: featureNames, targets: targetNames,
  split: `test = year 2019-2024 OR pointId heldOut (${[...held].sort().join(', ')}); validation (early stopping, ELM excluded from fit) = 2017-2018; train = rest`,
  nTrain: trIdx.length, nFitElm: fitIdx.length, nTest: teIdx.length,
  bySplit,
  fitThreshold: 0.5,
  mlp: { architecture: net.architecture, params: net.params, trainSeconds: net.trainSeconds, device: net.device, deviceName: net.deviceName, epochs: net.epochs, bestValLoss: net.bestValLoss, predictMicros: mlpMicros, jsVsTorchMaxDiff: maxDiff },
  elm: { ...ELM_CFG, params: ELM_CFG.hidden * nIn + ELM_CFG.hidden + ELM_CFG.hidden * T, trainableParams: ELM_CFG.hidden * T, trainSeconds: elmSeconds, predictMicros: elmMicros, note: 'No backpropagation: random hidden layer, output weights by ridge least squares (trainELM); configuration selected for v1, not re-swept.' },
  baseline: { description: 'Mean of the training rows within the same A x B x soil group (no climate); global train mean for an empty group.', groupFallbacks: fallbacks, nGroups: g.size },
  simulatorMicrosPerSample: provenance.simulatorMicrosPerSample,
  speedupVsSimulator: { mlp: provenance.simulatorMicrosPerSample / mlpMicros, elm: provenance.simulatorMicrosPerSample / elmMicros },
};
writeFileSync(here('../../web/data/emulator_v2_eval.json'), JSON.stringify(out, null, 1));
const f = (a) => a.map((v) => v.toFixed(3)).join(' ');
for (const s of Object.keys(SPLITS)) console.log(s, bySplit[s].n, 'R2 mlp', f(bySplit[s].mlp.r2), '| elm', f(bySplit[s].elm.r2), '| base', f(bySplit[s].baseline.r2), '| F1', bySplit[s].mlp.fitClassification.f1?.toFixed(3), bySplit[s].elm.fitClassification.f1?.toFixed(3), bySplit[s].baseline.fitClassification.f1?.toFixed(3));
console.log('elm s', elmSeconds.toFixed(1), 'us', mlpMicros.toFixed(1), elmMicros.toFixed(1));
