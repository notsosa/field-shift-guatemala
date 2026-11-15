import test from 'node:test'; import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mlpPredict, elmPredict } from '../web/js/model/emulator.js';
import { FEATURE_NAMES_V3 } from '../web/js/model/emulatorV3.js';

const rj = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));

for (const seed of [17, 29, 43]) {
  test(`emulator_v3_mlp_seed${seed}.json: 47 entradas, y mlpPredict reproduce las predicciones de PyTorch (1e-4)`, () => {
    const net = rj(`../web/data/emulator_v3_mlp_seed${seed}.json`);
    assert.equal(net.seed, seed);
    assert.deepEqual(net.architecture, [FEATURE_NAMES_V3.length, 64, 32, 16, 3]);
    assert.equal(net.mean.length, 47);
    assert.equal(net.layers[0].W[0].length, 47);
    let maxDiff = 0;
    net.checkPredictions.forEach(({ pred }, k) => {
      assert.equal(net.checkInputs[k].length, 47);
      mlpPredict(net, net.checkInputs[k]).forEach((v, o) => { maxDiff = Math.max(maxDiff, Math.abs(v - pred[o])); });
    });
    assert.ok(maxDiff < 1e-4, `max diff ${maxDiff}`);
  });
}

test('el ELM de la GPU (formato de trainELM) predice con elmPredict: forma y valores finitos', () => {
  // el archivo de la GPU vive en scripts/compare/out (no se versiona); aquí solo se comprueba la lectura de un modelo con el formato exacto
  const m = { nIn: 2, nOut: 1, hidden: 2, mean: [0, 0], std: [1, 1], yMean: [1], yStd: [2], W: [1, 0, 0, 1], b: [0, 0], beta: [0.5, -0.25] };
  // z = (1, 2): h = (tanh 1, tanh 2); y = (0.5·tanh 1 − 0.25·tanh 2)·2 + 1
  const y = elmPredict(m, [1, 2])[0];
  assert.ok(Math.abs(y - ((0.5 * Math.tanh(1) - 0.25 * Math.tanh(2)) * 2 + 1)) < 1e-12);
});
