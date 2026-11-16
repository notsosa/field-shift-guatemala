// Red v2 del café con banano (Tarea 38, supuesto provisional): el paso hacia adelante en JS reproduce PyTorch y los archivos dicen que el banano es provisional.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mlpPredict } from '../web/js/model/emulator.js';
import { STATE_NAMES_V2, PRICE } from '../web/js/model/coffee.js';

const load = (f) => JSON.parse(readFileSync(new URL(`../web/data/${f}`, import.meta.url)));
const net = load('coffee_ptc_mlp_v2.json');
const ev = load('coffee_eval_v2.json');

test('entradas v2: las 16 del café más banana y bananaCover', () => {
  assert.deepEqual(net.inputNames, STATE_NAMES_V2);
  assert.deepEqual(net.architecture, [18, 64, 32, 16, 1]);
  assert.equal(net.params, 18 * 64 + 64 + 64 * 32 + 32 + 32 * 16 + 16 + 16 + 1);
});

test('mlpPredict reproduce las predicciones de PyTorch de la red v2 (1e-5)', () => {
  assert.equal(net.checkInputs.length, 50);
  net.checkInputs.forEach((x, i) => {
    const y = mlpPredict(net, x);
    assert.ok(Math.abs(y[0] - net.checkPredictions[i].pred[0]) < 1e-5, `caso ${i}: ${y[0]} vs ${net.checkPredictions[i].pred[0]}`);
  });
});

test('el banano está marcado como provisional en la red y en la evaluación', () => {
  assert.match(net.provisional, /PROVISIONAL/);
  assert.match(net.provisional, /Sarmiento-Soler/);
  assert.match(ev.meta.provisionalBanana, /PROVISIONAL/);
});

test('la evaluación v2 cubre las cinco sombras, ambos precios y la sensibilidad sin KsBanana', () => {
  assert.deepEqual(ev.meta.shades, ['none', 'evergreen', 'deciduous', 'banana0.15', 'banana0.30']);
  assert.equal(ev.meta.decision.price.saveWater, PRICE[0]);
  for (const g of ev.meta.shades) for (const p of ['saveWater', 'protectCrop']) assert.ok(Number.isFinite(ev.utility.predictThenChooseV2.test2019_2024[g][p].meanUtility.mean));
  assert.deepEqual(ev.meta.sensitivityShades, ['banana0.15_noKs', 'banana0.30_noKs']);
  assert.equal(ev.meta.originalRowsCheck.sameOutcomes, true);
  assert.equal(ev.meta.originalRowsCheck.maxAbsStateDiffVsV1, 0);
});

test('la utilidad exportada coincide con la medida en coffee_eval_v2.json para la semilla exportada', () => {
  const k = ev.meta.seeds.indexOf(net.seed);
  assert.ok(k >= 0);
  // media sobre las cinco sombras (540 casos de prueba cada una) = la del conjunto completo de prueba
  const shades = ev.meta.shades;
  const mean = (p) => shades.reduce((s, g) => s + ev.utility.predictThenChooseV2PerSeed[k].test2019_2024[g][p].meanUtility, 0) / shades.length;
  assert.ok(Math.abs(net.utilityOfExported.test2019_2024.saveWater.meanUtility - mean('saveWater')) < 1e-9);
  assert.ok(Math.abs(net.utilityOfExported.test2019_2024.protectCrop.meanUtility - mean('protectCrop')) < 1e-9);
  assert.equal(Math.min(...Object.values(net.valLossBySeed)), net.valLossBySeed[net.seed]);
});
