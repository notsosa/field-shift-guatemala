import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mlpPredict } from '../web/js/model/emulator.js';
import { APP_INPUT_NAMES, TARGET_NAMES } from '../web/js/model/appInputs.js';

const net = JSON.parse(readFileSync(new URL('../web/data/app_mlp.json', import.meta.url), 'utf8'));

test('app_mlp.json: nombres y orden de las entradas y de las salidas coinciden con appInputs.js', () => {
  assert.deepEqual(net.inputNames, APP_INPUT_NAMES);
  assert.deepEqual(net.targetNames, TARGET_NAMES);
  assert.deepEqual(net.architecture, [APP_INPUT_NAMES.length, 64, 32, 16, 3]);
  assert.equal(net.mean.length, APP_INPUT_NAMES.length); assert.equal(net.std.length, APP_INPUT_NAMES.length);
  assert.equal(net.layers.length, 4);
});

test('app_mlp.json: el forward de JS (mlpPredict) coincide con PyTorch a 1e-5 en 100 filas de prueba', () => {
  assert.equal(net.checkInputs.length, 100);
  let maxDiff = 0;
  net.checkPredictions.forEach((c, i) => {
    const y = mlpPredict(net, net.checkInputs[i]);
    c.pred.forEach((v, o) => { maxDiff = Math.max(maxDiff, Math.abs(v - y[o])); });
  });
  assert.ok(maxDiff <= 1e-5, `diferencia máxima ${maxDiff}`);
});
