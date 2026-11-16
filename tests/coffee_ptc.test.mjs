// Pesos exportados de "predecir y luego elegir" del café: el paso hacia adelante en JS reproduce PyTorch y la red exportada es la que se midió.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mlpPredict } from '../web/js/model/emulator.js';
import { STATE_NAMES, PRICE } from '../web/js/model/coffee.js';

const load = (f) => JSON.parse(readFileSync(new URL(`../web/data/${f}`, import.meta.url)));
const net = load('coffee_ptc_mlp.json');
const ev = load('coffee_eval.json');

test('las entradas son las del día de la decisión, en el mismo orden que coffee.js', () => {
  assert.deepEqual(net.inputNames, STATE_NAMES);
  assert.deepEqual(net.architecture, [16, 64, 32, 16, 1]);
  assert.equal(net.params, 16 * 64 + 64 + 64 * 32 + 32 + 32 * 16 + 16 + 16 + 1);
});

test('mlpPredict reproduce las predicciones de PyTorch en los casos guardados (1e-5)', () => {
  assert.equal(net.checkInputs.length, 50);
  net.checkInputs.forEach((x, i) => {
    const y = mlpPredict(net, x);
    assert.equal(y.length, 1);
    assert.ok(Math.abs(y[0] - net.checkPredictions[i].pred[0]) < 1e-5, `caso ${i}: ${y[0]} vs ${net.checkPredictions[i].pred[0]}`);
  });
});

test('la red exportada es la misma que se midió en coffee_eval.json (misma semilla, misma utilidad, mismas decisiones)', () => {
  const seeds = [17, 29, 43];
  const k = seeds.indexOf(net.seed);
  assert.ok(k >= 0);
  const measured = ev.policies.perSeed.predictThenChooseMlp[k].test.all;
  const u = net.utilityOfExported.test2019_2024;
  assert.equal(u.n, measured.saveWater.n);
  assert.ok(Math.abs(u.saveWater.meanUtility - measured.saveWater.meanUtility) < 1e-12);
  assert.ok(Math.abs(u.protectCrop.meanUtility - measured.protectCrop.meanUtility) < 1e-12);
  assert.equal(u.saveWater.price, PRICE[0]);
  assert.equal(u.protectCrop.price, PRICE[1]);
  for (const s of seeds) {
    const r = net.reexport.bySeed[s];
    assert.equal(r.sameDecisionsVsMeasured.saveWater, r.scenarios);
    assert.equal(r.sameDecisionsVsMeasured.protectCrop, r.scenarios);
  }
  // la semilla exportada es la de menor pérdida de validación
  assert.equal(Math.min(...Object.values(net.valLossBySeed)), net.valLossBySeed[net.seed]);
});
