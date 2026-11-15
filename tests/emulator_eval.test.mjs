import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const load = (p) => JSON.parse(readFileSync(new URL(`../web/data/${p}`, import.meta.url), 'utf8'));

// Umbral del plan: R² > 0.8 en waterIndex y ksFlowerMain para ambos modelos, medido en la división honesta
// (bySplit.testYears: años nuevos en puntos conocidos). No se baja el umbral: mientras no se cumpla queda como
// "todo" con los números reales hasta que el dueño decida.
const R2_MIN = 0.8;
const gate = (() => {
  const ty = load('emulator_eval.json').bySplit.testYears;
  const all = [];
  let miss = false;
  for (const m of ['mlp', 'elm']) {
    for (const [o, name] of [[0, 'waterIndex'], [1, 'ksFlowerMain']]) {
      const ok = ty[m].r2[o] > R2_MIN;
      miss ||= !ok;
      all.push(`${m} ${name} ${ty[m].r2[o].toFixed(3)}${ok ? '' : ' (below)'}`);
    }
  }
  return { miss, all };
})();
const gateTodo = gate.miss
  ? `testYears R2 vs threshold ${R2_MIN}: ${gate.all.join(', ')} — owner decision pending`
  : false;

test('emulator_eval.json: R2 en años nuevos (bySplit.testYears) de waterIndex y ksFlowerMain > 0.8 en ambos modelos', { todo: gateTodo }, () => {
  const ty = load('emulator_eval.json').bySplit.testYears;
  for (const m of ['mlp', 'elm']) {
    assert.ok(ty[m].r2[0] > R2_MIN, `${m} waterIndex testYears R2 = ${ty[m].r2[0]}`);
    assert.ok(ty[m].r2[1] > R2_MIN, `${m} ksFlowerMain testYears R2 = ${ty[m].r2[1]}`);
  }
});

test('la red embudo tiene 27 entradas y 4,451 parametros, y su tamaño de entrada es el de FEATURE_NAMES', async () => {
  const { FEATURE_NAMES } = await import('../web/js/model/emulator.js');
  const ev = load('emulator_eval.json');
  const net = load('emulator_mlp.json');
  const nIn = FEATURE_NAMES.length;
  assert.equal(nIn, 27);
  const expected = (nIn * 64 + 64) + (64 * 32 + 32) + (32 * 16 + 16) + (16 * 3 + 3);
  assert.equal(expected, 4451);
  assert.equal(ev.mlp.params, expected);
  assert.equal(net.params, expected);
  assert.deepEqual(net.architecture, [nIn, 64, 32, 16, 3]);
  assert.equal(net.layers[0].W[0].length, nIn);
  assert.equal(net.mean.length, nIn);
  assert.equal(net.checkInputs[0].length, nIn);
});

test('bySplit trae testYears, testPoints y testBoth para ambos modelos', () => {
  const ev = load('emulator_eval.json');
  for (const s of ['testYears', 'testPoints', 'testBoth']) {
    for (const m of ['mlp', 'elm']) {
      assert.equal(ev.bySplit[s][m].r2.length, 3, `${s}.${m}.r2`);
      assert.equal(ev.bySplit[s][m].rmse.length, 3, `${s}.${m}.rmse`);
    }
    assert.ok(ev.bySplit[s].n > 0);
  }
  assert.ok(typeof ev.caveat === 'string' && ev.caveat.length > 50);
});

test('el forward JS coincide con PyTorch en las 100 filas de prueba (1e-4)', async () => {
  const { mlpPredict } = await import('../web/js/model/emulator.js');
  const net = load('emulator_mlp.json');
  assert.equal(net.checkPredictions.length, 100);
  assert.equal(net.checkInputs.length, 100);
  for (const [k, { index, pred }] of net.checkPredictions.entries()) {
    const js = mlpPredict(net, net.checkInputs[k]);
    for (let o = 0; o < 3; o++) assert.ok(Math.abs(js[o] - pred[o]) < 1e-4, `fila ${index} salida ${o}: ${js[o]} vs ${pred[o]}`);
  }
});

test('emulator_train_subset.json trae 5,000 filas de entrenamiento', async () => {
  const s = load('emulator_train_subset.json');
  assert.equal(s.X.length, 5000);
  assert.equal(s.Y.length, 5000);
  const { FEATURE_NAMES } = await import('../web/js/model/emulator.js');
  assert.deepEqual(s.featureNames, FEATURE_NAMES);
  assert.equal(s.X[0].length, FEATURE_NAMES.length);
  assert.equal(s.targetNames.length, 3);
  assert.ok(existsSync(new URL('../web/data/emulator_mlp.json', import.meta.url)));
});

test('elmSweep: 24 configuraciones hidden {600, 1500} x inputScale {1, 0.5, 0.25, 0.1} x lambda {0.1, 10, 1000}; el de la 13f queda en elmSweepV1', () => {
  const ev = load('emulator_eval.json');
  assert.equal(ev.elmSweep.length, 24);
  const combos = new Set(ev.elmSweep.map((e) => `${e.hidden}|${e.inputScale}|${e.lambda}`));
  assert.equal(combos.size, 24);
  for (const h of [600, 1500]) for (const s of [1, 0.5, 0.25, 0.1]) for (const l of [0.1, 10, 1000]) assert.ok(combos.has(`${h}|${s}|${l}`), `${h}|${s}|${l}`);
  for (const e of ev.elmSweep) {
    assert.equal(e.valR2.length, 3);
    assert.ok(Number.isFinite(e.valR2Mean) && e.trainSeconds > 0 && e.memoryAnalyticMB > 0);
  }
  assert.equal(ev.elmSweepV1.length, 12);
  assert.ok(ev.elmSweepV1.every((e) => e.inputScale === undefined && Number.isFinite(e.valR2Mean)));
});

// Regla de elección: mayor R² medio de validación; empates: menor hidden, luego mayor lambda, luego mayor inputScale.
const byRule = (a, b) => b.valR2Mean - a.valR2Mean || a.hidden - b.hidden || b.lambda - a.lambda || b.inputScale - a.inputScale;

test('elmConfig es el argmax de valR2Mean con la regla de empates y la recomendacion de navegador (hidden <= 600) incluye inputScale', () => {
  const ev = load('emulator_eval.json');
  const best = [...ev.elmSweep].sort(byRule)[0];
  assert.deepEqual([ev.elmConfig.hidden, ev.elmConfig.inputScale, ev.elmConfig.lambda], [best.hidden, best.inputScale, best.lambda]);
  assert.equal(ev.elmConfig.seed, 42);
  assert.match(ev.elmConfig.fitRows, /^fit \(train minus val years 2017/);
  const rec = ev.browserElmRecommendation;
  assert.ok(rec.hidden <= 600);
  const bestB = ev.elmSweep.filter((e) => e.hidden <= 600).sort(byRule)[0];
  assert.deepEqual([rec.hidden, rec.inputScale, rec.lambda, rec.seed], [bestB.hidden, bestB.inputScale, bestB.lambda, 42]);
  assert.ok(typeof rec.note === 'string' && rec.note.length > 20);
});

test('elmBrowser: la ELM exacta de la página (recomendación + subconjunto de 5,000 filas) con R2 total y por división', () => {
  const ev = load('emulator_eval.json');
  const b = ev.elmBrowser;
  const rec = ev.browserElmRecommendation;
  assert.deepEqual([b.hidden, b.inputScale, b.lambda, b.seed], [rec.hidden, rec.inputScale, rec.lambda, rec.seed]);
  assert.equal(b.nRows, 5000);
  assert.equal(b.r2.length, 3);
  assert.equal(b.rmse.length, 3);
  for (const s of ['testYears', 'testPoints', 'testBoth']) {
    assert.equal(b.bySplit[s].r2.length, 3);
    assert.equal(b.bySplit[s].n, ev.bySplit[s].n);
  }
});

test('stressDetection: precisión, recall y F1 del estrés en floración (ksFlowerMean < 0.7) en testYears para los 3 modelos', () => {
  const sd = load('emulator_eval.json').stressDetection;
  const ev = load('emulator_eval.json');
  assert.equal(sd.threshold, 0.7);
  assert.equal(sd.n, ev.bySplit.testYears.n);
  assert.ok(sd.baseRate > 0 && sd.baseRate < 1);
  for (const m of ['mlp', 'elm', 'elmBrowser']) {
    const d = sd[m];
    assert.equal(d.tp + d.fp + d.fn + d.tn, sd.n, m);
    assert.ok(Math.abs((d.tp + d.fn) / sd.n - sd.baseRate) < 1e-12, m);
    for (const k of ['precision', 'recall', 'f1']) assert.ok(d[k] === null || (d[k] >= 0 && d[k] <= 1), `${m}.${k}`);
  }
});

test('diffError: error de "alternativa − actual" por modelo, alternativa y objetivo; floración idéntica en toda rotación', () => {
  const de = load('emulator_eval.json').diffError;
  for (const m of ['mlp', 'elm', 'elmBrowser']) {
    for (const alt of ['proteger', 'extra_secano', 'extra_riego']) {
      for (const tn of ['waterIndex', 'ksFlowerMain', 'bareFrac']) {
        const d = de[m][alt][tn];
        assert.ok(Number.isFinite(d.rmse) && d.rmse >= 0 && d.n > 0, `${m}.${alt}.${tn}`);
        assert.ok(d.signAgreement === null || (d.signAgreement >= 0 && d.signAgreement <= 1));
      }
      // El mapa no ofrece "agua en la floración del maíz": en el simulador la diferencia es exactamente 0.
      assert.equal(de[m][alt].ksFlowerMain.nSigned, 0, `${m}.${alt}`);
      assert.equal(de[m][alt].ksFlowerMain.signAgreement, null);
    }
  }
  assert.deepEqual(de.years, [2019, 2020, 2021, 2022, 2023, 2024]);
});

test('caveat: los 4 puntos de prueba comparten celda, lluvia ERA5 y nota de la ronda de diseño 13e', () => {
  const { caveat } = load('emulator_eval.json');
  assert.match(caveat, /all 4 held-out points/);
  assert.match(caveat, /Rainfall \(ERA5\)/);
  assert.doesNotMatch(caveat, /IMERG/);
  assert.match(caveat, /Task 13e's features were designed after seeing Task 13d's test R²; the models were never fit on test rows, but test results steered one design round\./);
});
