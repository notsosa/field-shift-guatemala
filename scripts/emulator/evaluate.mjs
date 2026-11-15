// Evalua la red embudo (forward JS), entrena la ELM en Node, mide tiempos/memoria y escribe web/data/emulator_*.json.
// Uso: node --expose-gc scripts/emulator/evaluate.mjs  (requiere samples.json, grid_features.json y web/data/emulator_mlp.json)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { performance } from 'node:perf_hooks';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series, runSequence, agriculturalYears, KS_STRESS } from '../../web/js/model/simulate.js';
import {
  trainELM, elmPredict, mlpPredict, r2, rmse, mulberry32, encodeFeatures, targetsOf, climateFeatures, phenoFeatures,
} from '../../web/js/model/emulator.js';
import { yearSlices, clamp01 } from '../../web/js/ui/bestSowing.js';
import { sharedCells } from './cells.mjs';

const here = (p) => new URL(p, import.meta.url);
const readJson = (u) => JSON.parse(readFileSync(u, 'utf8'));
const { featureNames, targetNames, X, Y, meta, provenance } = readJson(here('./samples.json'));
if (!provenance) throw new Error('samples.json sin provenance: regenera con generate.mjs');
const points = readJson(here('./points.json'));
const net = readJson(here('../../web/data/emulator_mlp.json'));
const OUT = here('../../web/data/emulator_eval.json');
const prev = existsSync(OUT) ? readJson(OUT) : {};
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
// Barrido v2 (solo validación): tamaño x escala de los pesos de entrada x ridge. Con W ~ U(-1, 1) sobre las entradas (25 al diseñarse el barrido; ahora 27)
// estandarizadas ~la mitad de las neuronas tanh quedan saturadas, y lambda 1e-3–1e-1 es ~1e-5 de diag(HᵀH) (≈ N·E[h²]).
const SWEEP = { hidden: [600, 1500], inputScale: [1, 0.5, 0.25, 0.1], lambda: [0.1, 10, 1000] };
const elmSweep = [];
for (const hidden of SWEEP.hidden) {
  for (const inputScale of SWEEP.inputScale) {
    for (const lambda of SWEEP.lambda) {
      const t0 = performance.now();
      const mdl = trainELM(Xfit, Yfit, { hidden, inputScale, lambda, seed: 42 });
      const trainSeconds = (performance.now() - t0) / 1000;
      const valR2 = metrics(valIdx, Xval.map((x) => elmPredict(mdl, x))).r2;
      elmSweep.push({ hidden, inputScale, lambda, valR2, valR2Mean: meanOf(valR2), trainSeconds, memoryAnalyticMB: elmBytesOf(hidden) / 1048576 });
      console.log(`sweep hidden ${hidden} scale ${inputScale} lambda ${lambda}: val R2 [${valR2.map((v) => v.toFixed(4))}] mean ${meanOf(valR2).toFixed(4)} (${trainSeconds.toFixed(1)} s)`);
    }
  }
}
// Elección por R² medio de validación; empates: menor hidden, luego mayor lambda, luego mayor inputScale.
const beats = (e, b) => e.valR2Mean > b.valR2Mean || (e.valR2Mean === b.valR2Mean
  && (e.hidden < b.hidden || (e.hidden === b.hidden && (e.lambda > b.lambda || (e.lambda === b.lambda && e.inputScale > b.inputScale)))));
const argmax = (arr) => arr.reduce((b, e) => (beats(e, b) ? e : b));
const bestCfg = argmax(elmSweep);
const ELM_CFG = { hidden: bestCfg.hidden, inputScale: bestCfg.inputScale, lambda: bestCfg.lambda, seed: 42 };
const bestBrowser = argmax(elmSweep.filter((e) => e.hidden <= 600));
const fmt = (e) => `hidden ${e.hidden}, inputScale ${e.inputScale}, lambda ${e.lambda}: val R2 mean ${e.valR2Mean.toFixed(3)}, ${e.trainSeconds.toFixed(1)} s in Node`;
const browserElmRecommendation = {
  hidden: bestBrowser.hidden, inputScale: bestBrowser.inputScale, lambda: bestBrowser.lambda, seed: 42,
  note: `Best validation R2 among hidden <= 600 (${fmt(bestBrowser)}) versus the overall best (${fmt(bestCfg)}). In-browser training on the 5,000-row subset is O(rows x hidden^2), so the cap trades some accuracy for a short wait; training times are measured in Node on the full fit set, the browser subset is about ${Math.round(fitIdx.length / 5000)}x smaller. Its real test scores are in elmBrowser.`,
};
// Barrido de la Tarea 13f (inputScale 1, lambda 1e-3–1e-1, ejemplos anteriores a la corrección de cycleIncomplete), solo como historia.
const elmSweepV1 = prev.elmSweepV1 ?? (prev.elmSweep ?? []).filter((e) => e.inputScale === undefined);
if (global.gc) global.gc();
const rss0 = process.memoryUsage().rss;
const e0 = performance.now();
const elm = trainELM(Xfit, Yfit, ELM_CFG);
const elmSeconds = (performance.now() - e0) / 1000;
const rssDelta = process.memoryUsage().rss - rss0; // delta de RSS tras entrenar (no es un pico)
const h = ELM_CFG.hidden;
const elmBytes = elmBytesOf(h);
const elmPred = Xte.map((x) => elmPredict(elm, x));

// --- Subconjunto de entrenamiento para la ELM en el navegador y la ELM exacta del navegador ---
const rnd = mulberry32(7);
const order = trIdx.slice();
for (let i = order.length - 1; i > 0; i--) { const j = Math.floor(rnd() * (i + 1)); [order[i], order[j]] = [order[j], order[i]]; }
const subIdx = order.slice(0, 5000);
const subset = { featureNames, targetNames, X: pick(subIdx, X), Y: pick(subIdx, Y) };
writeFileSync(here('../../web/data/emulator_train_subset.json'), JSON.stringify(subset));
// Misma llamada que la página: trainELM(subset, browserElmRecommendation) con semilla 42.
const BROWSER_CFG = { hidden: bestBrowser.hidden, inputScale: bestBrowser.inputScale, lambda: bestBrowser.lambda, seed: 42 };
const eb0 = performance.now();
const elmB = trainELM(subset.X, subset.Y, BROWSER_CFG);
const elmBrowserSeconds = (performance.now() - eb0) / 1000;
const elmBPred = Xte.map((x) => elmPredict(elmB, x));

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
  return { n: rows.length, mlp: m(mlpPred), elm: m(elmPred), baseline: m(basePred), elmBrowser: m(elmBPred) };
};
const SPLITS = {
  testYears: (m) => inYears(m) && !held.has(m.pointId),
  testPoints: (m) => held.has(m.pointId) && !inYears(m),
  testBoth: (m) => held.has(m.pointId) && inYears(m),
};
const splitAll = Object.fromEntries(Object.entries(SPLITS).map(([k, f]) => [k, sub(f)]));
const bySplit = Object.fromEntries(Object.entries(splitAll).map(([k, { elmBrowser: _, ...v }]) => [k, v]));

// --- Decisión: ¿detecta el estrés en floración (ksFlowerMean < KS_STRESS) en años nuevos? ---
const tyPos = teIdx.map((_, j) => j).filter((j) => SPLITS.testYears(meta[teIdx[j]]));
const KS = 1;
const detect = (P) => {
  let tp = 0, fp = 0, fn = 0, tn = 0;
  for (const j of tyPos) {
    const truth = Y[teIdx[j]][KS] < KS_STRESS, pred = P[j][KS] < KS_STRESS;
    if (truth && pred) tp++; else if (!truth && pred) fp++; else if (truth) fn++; else tn++;
  }
  const precision = tp + fp ? tp / (tp + fp) : null;
  const recall = tp + fn ? tp / (tp + fn) : null;
  const f1 = precision != null && recall != null && precision + recall > 0 ? (2 * precision * recall) / (precision + recall) : null;
  return { precision, recall, f1, tp, fp, fn, tn };
};
const stressDetection = {
  target: 'ksFlowerMain', threshold: KS_STRESS, split: 'testYears', n: tyPos.length,
  baseRate: tyPos.filter((j) => Y[teIdx[j]][KS] < KS_STRESS).length / tyPos.length,
  description: `Stress at maize flowering = ksFlowerMean < ${KS_STRESS}, in the simulator (truth) and in the model's prediction, on bySplit.testYears rows. baseRate = share of rows that are truly stressed.`,
  mlp: detect(mlpPred), elm: detect(elmPred), elmBrowser: detect(elmBPred),
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
const elmBMicros = timePredict((x) => elmPredict(elmB, x), 3);

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

// --- De punta a punta: features del año (clima + fenología) + codificación + predicción, por año simulado ---
const years0 = agriculturalYears(b0.dates).map((a) => a.year).filter((y) => !(b0.invalidYears ?? []).includes(y));
const slices0 = yearSlices(b0, et0, years0);
const mgmt0 = { texture: 'loam', slopeClass: 'moderate', irrigation: 'none', sequenceId: 'actual', sowOffsetDays: 0 };
const timeEndToEnd = (predict, reps) => {
  let sink = 0;
  const t = performance.now();
  for (let r = 0; r < reps; r++) {
    for (const s of slices0) {
      const x = encodeFeatures(climateFeatures(s.bundle, s.year, s.et0), phenoFeatures(s.bundle, s.year, s.et0, crops, 0), mgmt0);
      sink += predict(x)[0];
    }
  }
  if (!Number.isFinite(sink)) throw new Error('prediccion no finita');
  return ((performance.now() - t) * 1000) / (reps * slices0.length);
};
const e2eFns = { mlp: (x) => mlpPredict(net, x), elm: (x) => elmPredict(elm, x), elmBrowser: (x) => elmPredict(elmB, x) };
for (const fn of Object.values(e2eFns)) timeEndToEnd(fn, 5); // calentamiento del JIT
const e2e = Object.fromEntries(Object.entries(e2eFns).map(([k, fn]) => [k, timeEndToEnd(fn, 20)]));
const endToEnd = {
  microsPerYear: e2e,
  speedupVsSimulator: Object.fromEntries(Object.entries(e2e).map(([k, v]) => [k, simMicros / v])),
  note: 'End to end per simulated year: climateFeatures + phenoFeatures on a one-year slice of the bundle (as the page does) + encodeFeatures + the forward pass, against runSequence per year. ET0 is precomputed for both.',
};

// --- Error de la diferencia (alternativa − actual), la cantidad que pinta el mapa ---
// Años nuevos 2019–2024 en los 20 puntos (todas son filas de prueba), desfase 0, toda la rejilla de manejo que ofrece el mapa.
const grid = readJson(here('../../web/data/grid_features.json'));
const TEST_YEARS = [2019, 2020, 2021, 2022, 2023, 2024];
const ALTS = ['proteger', 'extra_secano', 'extra_riego'];
const GRID_MGMT = [];
for (const texture of ['sand', 'loam', 'clay']) for (const slopeClass of ['flat', 'moderate', 'steep']) for (const irrigation of ['none', 'limited', 'full']) GRID_MGMT.push({ texture, slopeClass, irrigation });
const predictors = e2eFns;
const MODELS = Object.keys(predictors);
const acc = {}; // acc[model][alt][o] = { se, n, agree, nSigned, medTrue: [], medPred: [] }
for (const m of MODELS) acc[m] = Object.fromEntries(ALTS.map((a) => [a, targetNames.map(() => ({ se: 0, n: 0, agree: 0, nSigned: 0, medTrue: [], medPred: [] }))]));
const medianOf = (a) => { const v = [...a].sort((x, y) => x - y); const k = v.length >> 1; return v.length % 2 ? v[k] : (v[k - 1] + v[k]) / 2; };
const d0 = performance.now();
for (const gp of grid.points) {
  const bundle = bundles[gp.id];
  const et0p = computeEt0Series(bundle);
  for (const mg of GRID_MGMT) {
    const run = (seqId) => new Map(runSequence({ sequence: sequences[seqId], bundle, et0: et0p, crops, ...mg }).map((r) => [r.year, r]));
    const cur = run('actual');
    for (const alt of ALTS) {
      if (sequences[alt].requiresIrrigation && mg.irrigation === 'none') continue;
      const res = run(alt);
      const perYear = { true: [], pred: Object.fromEntries(MODELS.map((m) => [m, []])) };
      for (const y of TEST_YEARS) {
        const clim = grid.climate[gp.id]?.[y], ph = grid.pheno[gp.id]?.[y]?.['0'];
        const ta = res.get(y) && targetsOf(res.get(y)), tc = cur.get(y) && targetsOf(cur.get(y));
        if (!clim || !ph || !ta || !tc) continue;
        const xa = encodeFeatures(clim, ph, { ...mg, sequenceId: alt, sowOffsetDays: 0 });
        const xc = encodeFeatures(clim, ph, { ...mg, sequenceId: 'actual', sowOffsetDays: 0 });
        perYear.true.push(ta.map((v, o) => v - tc[o]));
        for (const m of MODELS) {
          const pa = predictors[m](xa), pc = predictors[m](xc);
          perYear.pred[m].push(pa.map((v, o) => clamp01(v) - clamp01(pc[o])));
        }
      }
      if (!perYear.true.length) continue;
      for (const m of MODELS) {
        for (let o = 0; o < T; o++) {
          const a = acc[m][alt][o];
          perYear.true.forEach((tv, k) => {
            const pv = perYear.pred[m][k][o];
            a.se += (pv - tv[o]) ** 2; a.n++;
            if (Math.abs(tv[o]) > 1e-9) { a.nSigned++; if (Math.sign(pv) === Math.sign(tv[o])) a.agree++; }
          });
          a.medTrue.push(medianOf(perYear.true.map((tv) => tv[o])));
          a.medPred.push(medianOf(perYear.pred[m].map((pv) => pv[o])));
        }
      }
    }
  }
}
const diffError = {
  description: 'Error of the map quantity, alternative minus current rotation, per target. Truth = simulator (runSequence) difference; prediction = clamp01(model(alternative)) − clamp01(model(current)), exactly as the map computes it. Rows: new years 2019–2024 at all 20 points (test rows only), sowing offset 0, every texture x slope x irrigation the map offers (alternatives that need irrigation only with limited/full). rmse = per point-year-setting RMSE of the difference; signAgreement = share of cases with a non-zero true difference where the predicted difference has the same sign (null if the true difference is always 0); rmseOfMedians = RMSE of the per point-setting median over the 6 years; meanAbsTrue = mean |true difference| of those medians.',
  years: TEST_YEARS, nPoints: grid.points.length, offset: 0,
};
for (const m of MODELS) {
  diffError[m] = Object.fromEntries(ALTS.map((alt) => [alt, Object.fromEntries(targetNames.map((tn, o) => {
    const a = acc[m][alt][o];
    return [tn, {
      rmse: Math.sqrt(a.se / a.n), signAgreement: a.nSigned ? a.agree / a.nSigned : null, n: a.n, nSigned: a.nSigned,
      rmseOfMedians: rmse(a.medTrue, a.medPred), meanAbsTrue: meanOf(a.medTrue.map(Math.abs)),
    }];
  }))]));
}
const diffSeconds = (performance.now() - d0) / 1000;

// --- Celdas POWER compartidas ---
const cells = sharedCells(bundles);
const trainPointIds = new Set(points.filter((p) => !p.heldOut).map((p) => p.id));
const shared = {};
for (const id of held) {
  const mates = cells[id].weatherMates.filter((o) => trainPointIds.has(o));
  if (mates.length) shared[id] = mates;
}
const nShared = Object.keys(shared).length;
const sharedTxt = nShared ? Object.entries(shared).map(([a, b]) => `${a} (with ${b.join(', ')})`).join('; ') : 'none';
const caveat = `The spatial hold-out is not fully independent: NASA POWER temperature cells are about 0.5 degrees, and ${nShared === held.size ? `all ${held.size}` : `${nShared} of the ${held.size}`} held-out points share a cell with at least one training point (identical elevation, tmax, tmin and dew-point series): ${sharedTxt}. Rainfall (ERA5) and, for some points, solar radiation still differ, but temperature and humidity are shared. Use bySplit.testYears (temporal hold-out at non-held-out points) as the cleanest generalization estimate; testPoints and testBoth mix both effects. Task 13e's features were designed after seeing Task 13d's test R²; the models were never fit on test rows, but test results steered one design round.`;

const overall = { mlp: metrics(teIdx, mlpPred), elm: metrics(teIdx, elmPred), baseline: metrics(teIdx, basePred), elmBrowser: metrics(teIdx, elmBPred) };
const evalOut = {
  meta: { ...provenance, evaluated: new Date().toISOString().slice(0, 10) },
  targets: targetNames,
  mlp: { rmse: overall.mlp.rmse, r2: overall.mlp.r2, trainSeconds: net.trainSeconds, params: net.params,
    trainDevice: net.device ?? 'cpu', trainDeviceName: net.deviceName ?? 'CPU', torchVersion: net.torchVersion ?? null,
    trainSecondsCpu: net.trainSecondsCpu ?? null, trainSecondsCuda: net.trainSecondsCuda ?? null, trainMemoryAnalyticMB: net.trainMemoryAnalyticMB, trainMemoryMeasuredMB: net.trainMemoryMeasuredMB, memoryMethod: net.memoryMethod, epochs: net.epochs, bestValLoss: net.bestValLoss, valYears: net.valYears, predictMicros: mlpMicros,
    speedupVsSimulator: simMicros / mlpMicros },
  elm: { rmse: overall.elm.rmse, r2: overall.elm.r2, trainSeconds: elmSeconds, params: h * nIn + h + h * T,
    trainMemoryAnalyticMB: elmBytes / 1048576, trainMemoryMeasuredMB: rssDelta / 1048576,
    note: 'trainELM standardizes the targets internally (yMean/yStd stored in the model); elmPredict de-standardizes.',
    memoryMethod: 'trainMemoryAnalyticMB = bytes of A (hidden^2) + B (hidden x 3) + W + b + beta as Float64. trainMemoryMeasuredMB = process.memoryUsage().rss after trainELM minus rss before (after global.gc(), run with node --expose-gc); an RSS delta, not a peak, and noisy at this size.',
    predictMicros: elmMicros, speedupVsSimulator: simMicros / elmMicros },
  elmBrowser: { ...BROWSER_CFG, rows: 'emulator_train_subset.json', nRows: subset.X.length, trainSeconds: elmBrowserSeconds,
    note: 'The exact ELM the page trains: trainELM(emulator_train_subset.json, browserElmRecommendation) with seed 42, trained here in Node; scored on the same test rows as mlp and elm.',
    r2: overall.elmBrowser.r2, rmse: overall.elmBrowser.rmse,
    bySplit: Object.fromEntries(Object.entries(splitAll).map(([k, v]) => [k, { n: v.n, ...v.elmBrowser }])),
    trainMemoryAnalyticMB: elmBytesOf(BROWSER_CFG.hidden) / 1048576, predictMicros: elmBMicros, speedupVsSimulator: simMicros / elmBMicros },
  elmSweep,
  elmSweepGrid: SWEEP,
  elmSweepV1,
  elmSweepV1Note: 'Task 13f sweep (inputScale 1, lambda 1e-3 to 1e-1, samples before cycleIncomplete counted as relYield 0), kept for history only.',
  elmConfig: { ...ELM_CFG, fitRows: 'fit (train minus val years 2017–2018)', nFit: fitIdx.length, nVal: valIdx.length,
    rule: 'argmax of mean validation R2 over elmSweep; ties: smaller hidden, then larger lambda, then larger inputScale. Test rows never used.' },
  browserElmRecommendation,
  stressDetection,
  diffError,
  endToEnd,
  elmSeeds: { seeds: SEEDS, r2Mean, r2Std },
  baseline: { rmse: overall.baseline.rmse, r2: overall.baseline.r2,
    description: 'Predicts each target as the TRAIN mean within the same (sequenceId, irrigation, texture, slopeClass, sowOffsetDays) group, ignoring climate; falls back to the global train mean when a group is empty.',
    groupFallbacks: fallbacks, nGroups: gSum.size },
  simulatorMicrosPerYear: simMicros,
  speedupNote: 'speedupVsSimulator is per prediction with the inputs precomputed: the model forward pass against the simulator core (runSequence, 24 years averaged per year) with features and ET0 already computed. endToEnd adds the feature extraction.',
  targetsNote: 'waterIndex = mean relYield of the food crops (ky not null); a crop whose cycle does not finish within the agricultural year (cycleIncomplete) counts as relYield 0.',
  nTrain: trIdx.length, nTest: teIdx.length,
  split: `test = year 2019-2024 OR pointId heldOut (${[...held].sort().join(', ')}); train = rest`,
  bySplit, caveat,
};
writeFileSync(OUT, JSON.stringify(evalOut, null, 1));

const f = (a) => a.map((v) => v.toFixed(4)).join(', ');
console.log(`\nR2 [${targetNames}]`);
for (const m of ['mlp', 'elm', 'elmBrowser', 'baseline']) console.log(`  ${m.padEnd(10)} r2 [${f(evalOut[m].r2)}]  rmse [${f(evalOut[m].rmse)}]`);
console.log(`ELM seeds ${SEEDS}: r2Mean [${f(r2Mean)}], r2Std [${f(r2Std)}]`);
for (const [s, v] of Object.entries(splitAll)) {
  console.log(`bySplit.${s} (n=${v.n})`);
  for (const m of ['mlp', 'elm', 'elmBrowser', 'baseline']) console.log(`  ${m.padEnd(10)} r2 [${f(v[m].r2)}]`);
}
console.log(`MLP train ${net.trainSeconds}s on ${net.deviceName ?? 'CPU'} (cpu ${net.trainSecondsCpu ?? '—'} s, cuda ${net.trainSecondsCuda ?? '—'} s), ${net.epochs} epochs, measured ${net.trainMemoryMeasuredMB} MB (analytic ${net.trainMemoryAnalyticMB} MB)`);
console.log(`ELM chosen ${JSON.stringify(ELM_CFG)}; browser ${JSON.stringify(BROWSER_CFG)} trained on the subset in ${elmBrowserSeconds.toFixed(2)} s`);
console.log(`ELM train ${elmSeconds.toFixed(2)}s, analytic ${(elmBytes / 1048576).toFixed(3)} MB, RSS delta ${(rssDelta / 1048576).toFixed(1)} MB`);
console.log(`predict us: mlp ${mlpMicros.toFixed(2)}, elm ${elmMicros.toFixed(2)}; simulator ${simMicros.toFixed(1)} us/year (${nYears} years); speedup mlp x${(simMicros / mlpMicros).toFixed(0)}, elm x${(simMicros / elmMicros).toFixed(0)}`);
console.log(`baseline groups ${gSum.size}, fallbacks ${fallbacks}`);
console.log(`Shared POWER cells: ${sharedTxt}`);
const p3 = (v) => (v == null ? '—' : v.toFixed(3));
console.log(`Stress detection (ksFlower < ${KS_STRESS}, testYears n ${stressDetection.n}, base rate ${p3(stressDetection.baseRate)}):`);
for (const m of MODELS) { const d = stressDetection[m]; console.log(`  ${m.padEnd(10)} precision ${p3(d.precision)} recall ${p3(d.recall)} F1 ${p3(d.f1)}`); }
console.log(`diffError (${diffSeconds.toFixed(1)} s), rmse / sign agreement per alternative:`);
for (const m of MODELS) for (const alt of ALTS) console.log(`  ${m.padEnd(10)} ${alt.padEnd(12)} ${targetNames.map((tn) => `${tn} ${f([diffError[m][alt][tn].rmse])} / ${p3(diffError[m][alt][tn].signAgreement)}`).join('  ')}`);
console.log(`end to end us/year: ${Object.entries(e2e).map(([k, v]) => `${k} ${v.toFixed(1)} (x${(simMicros / v).toFixed(1)})`).join(', ')}`);
