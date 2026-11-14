import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';

const load = (p) => JSON.parse(readFileSync(new URL(`../web/data/${p}`, import.meta.url), 'utf8'));

test('emulator_eval.json: R2 de waterIndex y ksFlowerMain > 0.8 en ambos modelos', () => {
  const ev = load('emulator_eval.json');
  for (const m of ['mlp', 'elm']) {
    assert.ok(ev[m].r2[0] > 0.8, `${m} waterIndex R2 = ${ev[m].r2[0]}`);
    assert.ok(ev[m].r2[1] > 0.8, `${m} ksFlowerMain R2 = ${ev[m].r2[1]}`);
  }
});

test('la red embudo tiene 4,323 parametros', () => {
  const ev = load('emulator_eval.json');
  assert.equal(ev.mlp.params, 4323);
  assert.equal(load('emulator_mlp.json').params, 4323);
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

test('emulator_train_subset.json trae 5,000 filas de entrenamiento', () => {
  const s = load('emulator_train_subset.json');
  assert.equal(s.X.length, 5000);
  assert.equal(s.Y.length, 5000);
  assert.equal(s.featureNames.length, 25);
  assert.equal(s.targetNames.length, 3);
  assert.ok(existsSync(new URL('../web/data/emulator_mlp.json', import.meta.url)));
});

test('elmSweep: 12 configuraciones hidden x lambda con metricas de validacion', () => {
  const ev = load('emulator_eval.json');
  assert.equal(ev.elmSweep.length, 12);
  const combos = new Set(ev.elmSweep.map((e) => `${e.hidden}|${e.lambda}`));
  assert.equal(combos.size, 12);
  for (const e of ev.elmSweep) {
    assert.equal(e.valR2.length, 3);
    assert.ok(Number.isFinite(e.valR2Mean) && e.trainSeconds > 0 && e.memoryAnalyticMB > 0);
  }
});

test('elmConfig es el argmax de valR2Mean (empates: menor hidden) y la recomendacion de navegador tiene hidden <= 600', () => {
  const ev = load('emulator_eval.json');
  const best = [...ev.elmSweep].sort((a, b) => b.valR2Mean - a.valR2Mean || a.hidden - b.hidden || a.lambda - b.lambda)[0];
  assert.equal(ev.elmConfig.hidden, best.hidden);
  assert.equal(ev.elmConfig.lambda, best.lambda);
  assert.equal(ev.elmConfig.seed, 42);
  assert.match(ev.elmConfig.fitRows, /^fit \(train minus val years 2017/);
  const rec = ev.browserElmRecommendation;
  assert.ok(rec.hidden <= 600);
  const cand = ev.elmSweep.filter((e) => e.hidden <= 600);
  const bestB = [...cand].sort((a, b) => b.valR2Mean - a.valR2Mean || a.hidden - b.hidden || a.lambda - b.lambda)[0];
  assert.equal(rec.hidden, bestB.hidden);
  assert.equal(rec.lambda, bestB.lambda);
  assert.ok(typeof rec.note === 'string' && rec.note.length > 20);
});
