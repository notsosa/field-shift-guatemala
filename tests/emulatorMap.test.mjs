import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mlpPredict } from '../web/js/model/emulator.js';
import { computeMapValues, divergingColor, DIVERGING_STOPS, niceLimit } from '../web/js/ui/emulatorMap.js';

const readJson = (p) => JSON.parse(readFileSync(new URL(`../web/data/${p}`, import.meta.url), 'utf8'));
const grid = readJson('grid_features.json');
const net = readJson('emulator_mlp.json');
const predict = (x) => mlpPredict(net, x);
const mgmt = { texture: 'loam', slopeClass: 'moderate', irrigation: 'none' };

test('computeMapValues: un valor por punto, mediana de 24 años, en < 1 s con la MLP', () => {
  const r = computeMapValues({ grid, predict, alternative: 'proteger', targetIdx: 0, ...mgmt });
  assert.equal(r.values.length, grid.points.length);
  assert.equal(r.predictions, grid.points.length * grid.years.length * 2);
  for (const v of r.values) {
    assert.equal(v.n, 24);
    assert.ok(Number.isFinite(v.median) && Math.abs(v.median) <= 1);
  }
  assert.ok(r.ms < 1000, `mapa tardó ${r.ms} ms`);
});

test('computeMapValues: la alternativa "actual" contra sí misma da 0 en todos los puntos', () => {
  const r = computeMapValues({ grid, predict, alternative: 'actual', targetIdx: 2, ...mgmt });
  assert.ok(r.values.every((v) => v.median === 0));
});

test('computeMapValues: usa la predicción recortada a [0, 1] de cada objetivo', () => {
  const fake = () => [1.4, -0.2, 0.5];
  const r = computeMapValues({ grid, predict: fake, alternative: 'proteger', targetIdx: 0, ...mgmt });
  assert.ok(r.values.every((v) => v.median === 0));
});

test('divergingColor: extremos y centro de la paleta divergente', () => {
  assert.equal(divergingColor(-1), DIVERGING_STOPS[0]);
  assert.equal(divergingColor(1), DIVERGING_STOPS.at(-1));
  assert.equal(divergingColor(0), DIVERGING_STOPS[(DIVERGING_STOPS.length - 1) / 2]);
  assert.equal(divergingColor(5), DIVERGING_STOPS.at(-1));
  assert.match(divergingColor(0.37), /^#[0-9a-f]{6}$/);
});

test('niceLimit: redondea hacia arriba a 1, 1.5, 2, 2.5, 3, 4, 5, 6, 8 o 10 × 10^k', () => {
  assert.equal(niceLimit(0.043), 0.05);
  assert.equal(niceLimit(1.7), 2);
  assert.equal(niceLimit(2.2), 2.5);
  assert.equal(niceLimit(7), 8);
  assert.equal(niceLimit(12.3), 15);
  assert.equal(niceLimit(9), 10);
  assert.equal(niceLimit(0), 1);
});
