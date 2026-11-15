import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  CLIMATE_FEATURE_NAMES, PHENO_FEATURE_NAMES, FEATURE_NAMES, TARGET_NAMES, climateFeatures, phenoFeatures, antecedentFeatures, ANTECEDENT_CANDIDATES, encodeFeatures,
  targetsOf, cropRelYields, mulberry32, trainELM, elmPredict, mlpPredict, r2, rmse,
} from '../web/js/model/emulator.js';
import { loadCrops } from '../web/js/model/crops.js';
import { buildPhase } from '../web/js/model/phenology.js';
import { resolveMainSowIdx } from '../web/js/model/simulate.js';

const crops = loadCrops(JSON.parse(readFileSync(new URL('../web/data/crops.json', import.meta.url), 'utf8')));

function makeBundle() {
  const dates = [];
  for (let d = new Date(Date.UTC(2001, 3, 1)); d <= new Date(Date.UTC(2002, 2, 31)); d = new Date(d.getTime() + 864e5)) {
    dates.push(d.toISOString().slice(0, 10));
  }
  const n = dates.length;
  const rain = dates.map((s) => {
    const md = s.slice(5);
    const m = Number(s.slice(5, 7));
    if (m < 5 || m > 10) return 0;
    if (md >= '07-01' && md <= '08-15') return 0;
    return 5;
  });
  return {
    dates, rain, tmax: Array(n).fill(30), tmin: Array(n).fill(20), tdew: Array(n).fill(18),
    rs: Array(n).fill(18), u2: Array(n).fill(2), pressure: Array(n).fill(96), elevation: 400, lat: 14.8, lon: -90,
  };
}

test('nombres: 7 de clima, 6 de fenología y agua antecedente, 27 totales, 3 objetivos', () => {
  assert.deepEqual(CLIMATE_FEATURE_NAMES, ['rainMJJ', 'rainASO', 'rainYear', 'caniculaDays', 'et0MeanMO', 'tmeanMO', 'elevation']);
  assert.deepEqual(PHENO_FEATURE_NAMES, ['sowDoy', 'rainFlower', 'drySpellFlower', 'deficitFlower', 'apiFlower', 'storeProxy']);
  assert.equal(FEATURE_NAMES.length, 27);
  assert.equal(FEATURE_NAMES[7], 'sowDoy');
  assert.equal(FEATURE_NAMES[26], 'sowOffset30');
  assert.deepEqual(TARGET_NAMES, ['waterIndex', 'ksFlowerMain', 'bareFrac']);
});

test('climateFeatures: 7 valores (canícula de 46 días, lluvias estacionales)', () => {
  const b = makeBundle();
  const f = climateFeatures(b, 2001, Array(b.dates.length).fill(4));
  assert.equal(f.length, 7);
  const get = (k) => f[CLIMATE_FEATURE_NAMES.indexOf(k)];
  assert.equal(get('caniculaDays'), 46);
  assert.equal(get('rainMJJ'), 31 * 5 + 30 * 5);
  assert.equal(get('rainASO'), 16 * 5 + 30 * 5 + 31 * 5);
  assert.equal(get('rainYear'), 5 * (184 - 46));
  assert.equal(get('et0MeanMO'), 4);
  assert.equal(get('tmeanMO'), 25);
  assert.equal(get('elevation'), 400);
  assert.throws(() => climateFeatures(b, 2005, []), /2005/);
});

// Lluvia de 10 mm/día en mayo-octubre: el inicio de lluvias cae el 3 de mayo (10+10+10 >= 20); tmean constante 26 °C.
function phenoBundle() {
  const b = makeBundle();
  b.tmax = Array(b.dates.length).fill(32);
  b.tmin = Array(b.dates.length).fill(20);
  b.rain = b.dates.map((s) => { const m = Number(s.slice(5, 7)); return m >= 5 && m <= 10 ? 10 : 0; });
  return b;
}
const doy = (s) => Math.round((Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10)) - Date.UTC(+s.slice(0, 4), 0, 0)) / 864e5);
function floweringWindow(b, offset) {
  const sowIdx = resolveMainSowIdx(b, 2001, offset).idx;
  const tmean = b.tmax.map((t, i) => (t + b.tmin[i]) / 2);
  const [lo, hi] = buildPhase(crops.get('maiz'), sowIdx, tmean).floweringIdx;
  return { sowIdx, lo, hi };
}

test('phenoFeatures: sowDoy = día del inicio de lluvias + desfase', () => {
  const b = phenoBundle();
  const et0 = Array(b.dates.length).fill(4);
  assert.equal(resolveMainSowIdx(b, 2001, 0).onsetFallback, false);
  assert.equal(b.dates[resolveMainSowIdx(b, 2001, 0).idx], '2001-05-03');
  const f0 = phenoFeatures(b, 2001, et0, crops, 0);
  const f5 = phenoFeatures(b, 2001, et0, crops, 5);
  assert.equal(f0.length, PHENO_FEATURE_NAMES.length);
  assert.equal(f0[PHENO_FEATURE_NAMES.indexOf('sowDoy')], doy('2001-05-03'));
  assert.equal(f5[0], doy('2001-05-03') + 5);
  assert.equal(phenoFeatures(b, 2001, et0, crops, -20)[0], doy('2001-05-03') - 20);
});

test('phenoFeatures: ventana de floración húmeda y seca', () => {
  const b = phenoBundle();
  const et0 = Array(b.dates.length).fill(4);
  const { lo, hi } = floweringWindow(b, 0);
  const len = hi - lo + 1;
  const wet = phenoFeatures(b, 2001, et0, crops, 0);
  assert.equal(wet[1], 10 * len); // rainFlower
  assert.equal(wet[2], 0);        // drySpellFlower
  assert.equal(wet[3], 0);        // deficitFlower: 1.2 * 4 - 10 < 0
  for (let i = lo; i <= hi; i++) b.rain[i] = 0;
  const dry = phenoFeatures(b, 2001, et0, crops, 0);
  assert.equal(dry[1], 0);
  assert.equal(dry[2], len);
  assert.ok(Math.abs(dry[3] - len * crops.get('maiz').kc.mid * 4) < 1e-9);
});

test('phenoFeatures: sin inicio de lluvias siembra el 15 de junio y el desfase se acota al año', () => {
  const b = makeBundle(); // 5 mm/día: nunca 20 mm en 3 días
  const r = resolveMainSowIdx(b, 2001, 0);
  assert.equal(r.onsetFallback, true);
  assert.equal(b.dates[r.idx], '2001-06-15');
  assert.equal(resolveMainSowIdx(b, 2001, 5000).idx, b.dates.length - 1);
  assert.equal(resolveMainSowIdx(b, 2001, -5000).idx, 0);
});

test('encodeFeatures: 27 valores (= FEATURE_NAMES) con one-hot en su lugar', () => {
  const clim = Array.from({ length: 7 }, (_, i) => i + 1);
  const pheno = [100, 50, 3, 20, 40.5, 12.5];
  const v = encodeFeatures(clim, pheno, { texture: 'clay', slopeClass: 'flat', irrigation: 'full', sequenceId: 'extra_riego', sowOffsetDays: 15 });
  assert.equal(v.length, 27);
  assert.equal(v.length, FEATURE_NAMES.length);
  assert.deepEqual(v.slice(0, 7), clim);
  assert.deepEqual(v.slice(7, 13), pheno);
  assert.deepEqual(v.slice(13, 16), [0, 0, 1]);
  assert.deepEqual(v.slice(16, 19), [1, 0, 0]);
  assert.deepEqual(v.slice(19, 22), [0, 0, 1]);
  assert.deepEqual(v.slice(22, 26), [0, 0, 0, 1]);
  assert.equal(v[26], 0.5);
  assert.throws(() => encodeFeatures(clim, pheno, { texture: 'rock', slopeClass: 'flat', irrigation: 'none', sequenceId: 'actual', sowOffsetDays: 0 }), /rock/);
});

test('targetsOf: media de relYield, ks del primer cultivo, bareFrac', () => {
  const yr = { crops: [{ relYield: 0.8, ksFlowerMean: 0.9 }, { relYield: null, ksFlowerMean: 1 }, { relYield: 0.6, ksFlowerMean: 1 }], bareDaysRainy: 107 };
  const t = targetsOf(yr);
  assert.ok(Math.abs(t[0] - 0.7) < 1e-12);
  assert.equal(t[1], 0.9);
  assert.equal(t[2], 0.5);
  assert.equal(targetsOf({ crops: [{ relYield: null, ksFlowerMean: 1 }], bareDaysRainy: 0 }), null);
});

test('targetsOf: un cultivo que no termina en el año agrícola (cycleIncomplete) cuenta como relYield 0', () => {
  const yr = { crops: [{ relYield: 0.9, ksFlowerMean: 0.8, cycleIncomplete: false }, { relYield: 0.4, ksFlowerMean: 1, cycleIncomplete: true }], bareDaysRainy: 0 };
  const t = targetsOf(yr);
  assert.ok(Math.abs(t[0] - 0.45) < 1e-12, `waterIndex ${t[0]}`);
  assert.equal(t[1], 0.8);
  // Un cultivo sin ky (abono verde) sigue fuera del promedio aunque no termine.
  const g = targetsOf({ crops: [{ relYield: 0.6, ksFlowerMean: 1 }, { relYield: null, ksFlowerMean: 1, cycleIncomplete: true }], bareDaysRainy: 0 });
  assert.equal(g[0], 0.6);
  assert.deepEqual(cropRelYields(yr), [0.9, 0]);
});

test('trainELM: inputScale acota W y b a U(−s, s), se guarda en el modelo y 1 es el valor por defecto', () => {
  const { X, Y } = linearData(200);
  const a = trainELM(X, Y, { hidden: 30, seed: 4 });
  const q = trainELM(X, Y, { hidden: 30, seed: 4, inputScale: 0.25 });
  assert.equal(a.inputScale, 1);
  assert.equal(q.inputScale, 0.25);
  assert.ok(a.W.some((w) => Math.abs(w) > 0.25));
  for (let i = 0; i < a.W.length; i++) assert.ok(Math.abs(q.W[i] - 0.25 * a.W[i]) < 1e-15);
  for (let i = 0; i < a.b.length; i++) assert.ok(Math.abs(q.b[i] - 0.25 * a.b[i]) < 1e-15);
  assert.ok(r2(Y.map((y) => y[0]), X.map((x) => elmPredict(q, x)[0])) > 0.99);
});

test('mulberry32 en [0,1) y determinista', () => {
  const a = mulberry32(7), b = mulberry32(7);
  for (let i = 0; i < 100; i++) { const x = a(); assert.ok(x >= 0 && x < 1); assert.equal(x, b()); }
});

function linearData(n, seed = 1) {
  const r = mulberry32(seed);
  const X = [], Y = [];
  for (let i = 0; i < n; i++) { const x1 = r() * 4 - 2, x2 = r() * 4 - 2; X.push([x1, x2]); Y.push([2 * x1 - x2]); }
  return { X, Y };
}

test('ELM aprende y = 2x1 - x2 (R2 > 0.99) y un punto de entrenamiento queda cerca', () => {
  const { X, Y } = linearData(300);
  const m = trainELM(X, Y, { hidden: 50, lambda: 1e-6, seed: 3 });
  const pred = X.map((x) => elmPredict(m, x)[0]);
  assert.ok(r2(Y.map((y) => y[0]), pred) > 0.99);
  assert.ok(Math.abs(pred[0] - Y[0][0]) < 0.1);
  assert.equal(m.nIn, 2); assert.equal(m.nOut, 1); assert.equal(m.hidden, 50);
});

test('ELM estandariza Y por dentro: y = 1000 + 2*x1 con R2 > 0.99 y yMean/yStd guardados', () => {
  const r = mulberry32(11);
  const X = [], Y = [];
  for (let i = 0; i < 300; i++) { const x1 = r() * 4 - 2, x2 = r() * 4 - 2; X.push([x1, x2]); Y.push([1000 + 2 * x1, 5]); }
  const m = trainELM(X, Y, { hidden: 50, lambda: 1e-6, seed: 3 });
  const pred = X.map((x) => elmPredict(m, x));
  assert.ok(r2(Y.map((y) => y[0]), pred.map((p) => p[0])) > 0.99);
  assert.ok(Math.abs(m.yMean[0] - 1000) < 1);
  assert.ok(m.yStd[0] > 0.5);
  assert.equal(m.yStd[1], 1); // columna constante: std 0 -> 1
  assert.ok(Math.abs(pred[0][1] - 5) < 1e-6);
});

test('ELM: misma semilla, misma predicción', () => {
  const { X, Y } = linearData(100);
  const a = trainELM(X, Y, { hidden: 20, seed: 9 }), b = trainELM(X, Y, { hidden: 20, seed: 9 });
  assert.deepEqual(elmPredict(a, [0.3, -0.4]), elmPredict(b, [0.3, -0.4]));
});

test('ELM: 50 neuronas con 2,000 filas termina (sin guardar H)', () => {
  const { X, Y } = linearData(2000, 5);
  const m = trainELM(X, Y, { hidden: 50 });
  assert.ok(Number.isFinite(elmPredict(m, X[0])[0]));
});

test('trainELM lanza si Cholesky falla (lambda negativo grande)', () => {
  const { X, Y } = linearData(10);
  assert.throws(() => trainELM(X, Y, { hidden: 5, lambda: -1e6 }), /Cholesky/);
});

test('mlpPredict reproduce una red 2->2->1 a mano', () => {
  const net = {
    layers: [{ W: [[1, -1], [0.5, 2]], b: [0.1, -0.2] }, { W: [[1.5, -0.5]], b: [0.3] }],
    mean: [1, 2], std: [2, 0], yMean: [10], yStd: [3],
  };
  const x = [3, 5];
  const z = [(3 - 1) / 2, 5 - 2]; // std 0 -> 1
  const h = [Math.max(0, z[0] - z[1] + 0.1), Math.max(0, 0.5 * z[0] + 2 * z[1] - 0.2)];
  const exp = (1.5 * h[0] - 0.5 * h[1] + 0.3) * 3 + 10;
  assert.ok(Math.abs(mlpPredict(net, x)[0] - exp) < 1e-9);
});

test('r2 y rmse', () => {
  assert.equal(r2([1, 2, 3], [1, 2, 3]), 1);
  assert.equal(r2([2, 2], [2, 2]), 1);
  assert.equal(r2([2, 2], [1, 3]), 0);
  assert.ok(Math.abs(rmse([0, 0], [3, 4]) - Math.sqrt(12.5)) < 1e-12);
  assert.throws(() => r2([1], [1, 2]));
  assert.throws(() => rmse([], []));
});

// --- Entradas de agua antecedente (candidatas de la Tarea 19), con un maíz de ciclo corto y Kc conocida ---
// Ciclo ini 2 d, dev 3 d, mid 10 d, late 5 d a 26 °C: floración empieza 5 días después de la siembra.
// Kc por día desde la siembra: 0.4, 0.4, 0.6, 0.8, 1.0 (ini 0.4, mid 1.0); antes de sembrar, kc.ini = 0.4. ET0 = 4 mm/día.
const shortMaize = { ...crops.get('maiz'), days: { ini: 2, dev: 3, mid: 10, late: 5 }, kc: { ini: 0.4, mid: 1.0, end: 0.4 } };
const shortCrops = new Map([['maiz', shortMaize]]);
function antBundle(rainByIdx) {
  const b = makeBundle();
  b.tmax = Array(b.dates.length).fill(32);
  b.tmin = Array(b.dates.length).fill(20);
  b.rain = Array(b.dates.length).fill(0);
  for (const [i, v] of Object.entries(rainByIdx)) b.rain[Number(i)] = v;
  return b;
}
const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-9, `${msg}: ${a} vs ${b}`);
const ET4 = (b) => Array(b.dates.length).fill(4);

test('antecedentFeatures: las siete candidatas, en el orden fijado', () => {
  assert.deepEqual(ANTECEDENT_CANDIDATES, ['rainPre30', 'drySpellPre20', 'balancePre30', 'balanceSeason', 'rainPreSow30', 'apiFlower', 'storeProxy']);
  const b = antBundle({ 30: 10, 31: 10, 32: 10 });
  assert.deepEqual(Object.keys(antecedentFeatures(b, 2001, ET4(b), shortCrops, 0)), ANTECEDENT_CANDIDATES);
});

test('antecedentFeatures: sumas de 30 días, racha seca, balances, API y almacén a mano (siembra día 32, floración día 37)', () => {
  // lluvia: días 2-11 = 5; 30,31,32 = 10 (inicio de lluvias en el día 32); día 34 = 2.
  const rain = { 34: 2 };
  for (let i = 2; i <= 11; i++) rain[i] = 5;
  Object.assign(rain, { 30: 10, 31: 10, 32: 10 });
  const b = antBundle(rain);
  const et0 = ET4(b);
  assert.equal(resolveMainSowIdx(b, 2001, 0).idx, 32);
  const tmean = b.tmax.map((t, i) => (t + b.tmin[i]) / 2);
  assert.deepEqual(buildPhase(shortMaize, 32, tmean).floweringIdx, [37, 40]); // la ventana arranca el día 37 (f0)
  const a = antecedentFeatures(b, 2001, et0, shortCrops, 0);
  near(a.rainPre30, 25 + 30 + 2, 'rainPre30');               // [7,36]: días 7-11 = 25, 30-32 = 30, día 34 = 2
  assert.equal(a.drySpellPre20, 13);                          // [17,36]: días 17-29 secos (13 días)
  near(a.balancePre30, 57 - 4 * (27 * 0.4 + 0.6 + 0.8 + 1.0), 'balancePre30'); // 57 − 52.8 = 4.2
  near(a.balanceSeason, 12 - 4 * (0.4 + 0.4 + 0.6 + 0.8 + 1.0), 'balanceSeason'); // [32,36]: 12 − 12.8 = −0.8
  near(a.rainPreSow30, 50 + 20, 'rainPreSow30');              // [2,31]: 50 + 20
  let api = 0;
  for (let i = 2; i <= 11; i++) api += 5 * 0.9 ** (36 - i);
  api += 10 * (0.9 ** 6 + 0.9 ** 5 + 0.9 ** 4) + 2 * 0.9 ** 2;
  near(a.apiFlower, api, 'apiFlower');
  // almacén: piso 0 en los días 0-1 (sin él valdría 3.2 menos), nunca llega al tope; 21.2 mm.
  near(a.storeProxy, 21.2, 'storeProxy');
});

test('antecedentFeatures: storeProxy se topa en 150 mm y se vacía a 0', () => {
  const capped = antBundle({ 0: 100, 1: 100, 2: 100, 3: 100, 30: 10, 31: 10, 32: 10 });
  // 4 días de 100 mm con tope 150; 26 días secos a 1.6; 3 días +8.4; luego 1.6, 2.4, 3.2, 4.0.
  near(antecedentFeatures(capped, 2001, ET4(capped), shortCrops, 0).storeProxy, 150 - 26 * 1.6 + 3 * 8.4 - 1.6 - 2.4 - 3.2 - 4.0, 'tope');
  const dry = antBundle({ 30: 10, 31: 10, 32: 10 });
  // siembra día 42, floración día 47: 25.2 − 9·1.6 − 2·1.6 − 2.4 − 3.2 − 4.0 = −2.0, se queda en 0.
  assert.equal(resolveMainSowIdx(dry, 2001, 10).idx, 42);
  assert.equal(antecedentFeatures(dry, 2001, ET4(dry), shortCrops, 10).storeProxy, 0);
});

test('antecedentFeatures: las ventanas se recortan al 1 de abril (siembra el día 10, floración el día 15)', () => {
  // lluvia: día 0 = 6, día 5 = 3, días 10-14 = 5; 30,31,32 = 10 (inicio de lluvias, solo fija la siembra con el desfase −22).
  const rain = { 0: 6, 5: 3, 30: 10, 31: 10, 32: 10 };
  for (let i = 10; i <= 14; i++) rain[i] = 5;
  const b = antBundle(rain);
  assert.equal(resolveMainSowIdx(b, 2001, -22).idx, 10);
  const a = antecedentFeatures(b, 2001, ET4(b), shortCrops, -22);
  near(a.rainPre30, 6 + 3 + 25, 'rainPre30');                 // [0,14] en vez de [−15,14]
  assert.equal(a.drySpellPre20, 4);                           // [0,14]: rachas secas 1-4 y 6-9
  near(a.balancePre30, 34 - (10 * 1.6 + 1.6 + 1.6 + 2.4 + 3.2 + 4.0), 'balancePre30'); // 34 − 28.8 = 5.2
  near(a.balanceSeason, 25 - (1.6 + 1.6 + 2.4 + 3.2 + 4.0), 'balanceSeason');           // [10,14]
  near(a.rainPreSow30, 9, 'rainPreSow30');                    // [0,9]: sembrar a los 10 días, solo hay 10 días antes
  let api = 6 * 0.9 ** 14 + 3 * 0.9 ** 9;
  for (let k = 0; k <= 4; k++) api += 5 * 0.9 ** k;
  near(a.apiFlower, api, 'apiFlower');
  // almacén: 4.4, 2.8, 1.2, 0, 0, 1.4, 0 (piso), 0, 0, 0, +3.4, +3.4 -> 6.8, +2.6 -> 9.4, +1.8 -> 11.2, +1.0 -> 12.2.
  near(a.storeProxy, 12.2, 'storeProxy');
  assert.ok(Object.values(a).every(Number.isFinite));
});

test('antecedentFeatures: siembra y floración al final del año agrícola dan valores finitos', () => {
  const b = antBundle({ 30: 10, 31: 10, 32: 10 });
  const a = antecedentFeatures(b, 2001, ET4(b), shortCrops, 5000);
  assert.ok(Object.values(a).every(Number.isFinite));
});

test('phenoFeatures: la longitud sigue a PHENO_FEATURE_NAMES y las entradas elegidas salen de antecedentFeatures', () => {
  const b = phenoBundle();
  const et0 = Array(b.dates.length).fill(4);
  const f = phenoFeatures(b, 2001, et0, crops, 0);
  assert.equal(f.length, PHENO_FEATURE_NAMES.length);
  const cand = antecedentFeatures(b, 2001, et0, crops, 0);
  PHENO_FEATURE_NAMES.slice(4).forEach((n, i) => assert.equal(f[4 + i], cand[n], n));
  const v = encodeFeatures(Array(7).fill(0), f, { texture: 'loam', slopeClass: 'flat', irrigation: 'none', sequenceId: 'actual', sowOffsetDays: 0 });
  assert.equal(v.length, FEATURE_NAMES.length);
});
