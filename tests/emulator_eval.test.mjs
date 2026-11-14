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
