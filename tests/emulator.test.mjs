import test from 'node:test';
import assert from 'node:assert/strict';
import {
  CLIMATE_FEATURE_NAMES, FEATURE_NAMES, TARGET_NAMES, climateFeatures, encodeFeatures,
  targetsOf, mulberry32, trainELM, elmPredict, mlpPredict, r2, rmse,
} from '../web/js/model/emulator.js';

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

test('nombres: 11 de clima, 25 totales, 3 objetivos', () => {
  assert.equal(CLIMATE_FEATURE_NAMES.length, 11);
  assert.equal(FEATURE_NAMES.length, 25);
  assert.deepEqual(TARGET_NAMES, ['waterIndex', 'ksFlowerMain', 'bareFrac']);
});

test('climateFeatures: canícula de 46 días y lluvia de mayo 155', () => {
  const b = makeBundle();
  const f = climateFeatures(b, 2001, Array(b.dates.length).fill(4));
  const get = (k) => f[CLIMATE_FEATURE_NAMES.indexOf(k)];
  assert.equal(get('caniculaDays'), 46);
  assert.equal(get('rainMay'), 155);
  assert.equal(get('rainMJJ'), 31 * 5 + 30 * 5);
  assert.equal(get('rainASO'), 16 * 5 + 30 * 5 + 31 * 5);
  assert.equal(get('rainYear'), 5 * (184 - 46));
  assert.equal(get('rainyDaysMO'), 184 - 46);
  assert.equal(get('maxDrySpellMO'), 46);
  assert.equal(get('et0MeanMO'), 4);
  assert.equal(get('tmeanMO'), 25);
  assert.equal(get('rsMeanMO'), 18);
  assert.equal(get('elevation'), 400);
  assert.throws(() => climateFeatures(b, 2005, []), /2005/);
});

test('encodeFeatures: 25 valores con one-hot en su lugar', () => {
  const clim = Array.from({ length: 11 }, (_, i) => i + 1);
  const v = encodeFeatures(clim, { texture: 'clay', slopeClass: 'flat', irrigation: 'full', sequenceId: 'extra_riego', sowOffsetDays: 15 });
  assert.equal(v.length, 25);
  assert.deepEqual(v.slice(0, 11), clim);
  assert.deepEqual(v.slice(11, 14), [0, 0, 1]);
  assert.deepEqual(v.slice(14, 17), [1, 0, 0]);
  assert.deepEqual(v.slice(17, 20), [0, 0, 1]);
  assert.deepEqual(v.slice(20, 24), [0, 0, 0, 1]);
  assert.equal(v[24], 0.5);
  assert.throws(() => encodeFeatures(clim, { texture: 'rock', slopeClass: 'flat', irrigation: 'none', sequenceId: 'actual', sowOffsetDays: 0 }), /rock/);
});

test('targetsOf: media de relYield, ks del primer cultivo, bareFrac', () => {
  const yr = { crops: [{ relYield: 0.8, ksFlowerMean: 0.9 }, { relYield: null, ksFlowerMean: 1 }, { relYield: 0.6, ksFlowerMean: 1 }], bareDaysRainy: 107 };
  const t = targetsOf(yr);
  assert.ok(Math.abs(t[0] - 0.7) < 1e-12);
  assert.equal(t[1], 0.9);
  assert.equal(t[2], 0.5);
  assert.equal(targetsOf({ crops: [{ relYield: null, ksFlowerMean: 1 }], bareDaysRainy: 0 }), null);
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
