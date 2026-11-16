// Red v3 del café con los sistemas de la auditoría (Tarea 41): el paso hacia adelante en JS reproduce PyTorch, las entradas son las 19 y los archivos dicen de dónde salen los parámetros.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mlpPredict } from '../web/js/model/emulator.js';
import { STATE_NAMES_V3, PRICE } from '../web/js/model/coffee.js';

const load = (f) => JSON.parse(readFileSync(new URL(`../web/data/${f}`, import.meta.url)));
const net = load('coffee_ptc_mlp_v3.json');
const ev = load('coffee_eval_v3.json');

test('entradas v3: las 16 del café más weeds, bananaRegulated y bananaDense', () => {
  assert.deepEqual(net.inputNames, STATE_NAMES_V3);
  assert.equal(net.inputNames.length, 19);
  assert.deepEqual(net.architecture, [19, 64, 32, 16, 1]);
  assert.equal(net.params, 19 * 64 + 64 + 64 * 32 + 32 + 32 * 16 + 16 + 16 + 1);
});

test('mlpPredict reproduce las predicciones de PyTorch de la red v3 (1e-5)', () => {
  assert.equal(net.checkInputs.length, 50);
  net.checkInputs.forEach((x, i) => {
    assert.equal(x.length, 19);
    const y = mlpPredict(net, x);
    assert.ok(Math.abs(y[0] - net.checkPredictions[i].pred[0]) < 1e-5, `caso ${i}: ${y[0]} vs ${net.checkPredictions[i].pred[0]}`);
  });
});

test('los archivos dicen de dónde salen los parámetros de los sistemas y que son valores de referencia', () => {
  assert.match(net.systemSource, /parametros_auditados\.json/);
  assert.match(net.systemSource, /ac37f1b/);
  assert.match(net.systemSource, /FAO-56/);
  assert.match(ev.meta.systemsSource, /parametros_auditados/);
  assert.equal(net.version, 3);
});

test('la evaluación v3 cubre las seis sombras y sistemas, ambos precios, y las filas originales son las de siempre', () => {
  assert.deepEqual(ev.meta.shades, ['none', 'evergreen', 'deciduous', 'weedy', 'regulated', 'dense']);
  assert.equal(ev.meta.decision.price.saveWater, PRICE[0]);
  for (const g of ev.meta.shades) for (const p of ['saveWater', 'protectCrop']) assert.ok(Number.isFinite(ev.utility.predictThenChooseV3.test2019_2024[g][p].meanUtility.mean));
  assert.equal(ev.meta.originalRowsCheck.sameOutcomes, true);
  assert.equal(ev.meta.originalRowsCheck.maxAbsStateDiffVsV1, 0);
  assert.equal(ev.meta.originalRowsCheck.rows, 6480);
});

test('la utilidad exportada coincide con la medida en coffee_eval_v3.json para la semilla exportada', () => {
  const k = ev.meta.seeds.indexOf(net.seed);
  assert.ok(k >= 0);
  const shades = ev.meta.shades; // 540 casos de prueba cada una
  const mean = (p) => shades.reduce((s, g) => s + ev.utility.predictThenChooseV3PerSeed[k].test2019_2024[g][p].meanUtility, 0) / shades.length;
  assert.ok(Math.abs(net.utilityOfExported.test2019_2024.saveWater.meanUtility - mean('saveWater')) < 1e-9);
  assert.ok(Math.abs(net.utilityOfExported.test2019_2024.protectCrop.meanUtility - mean('protectCrop')) < 1e-9);
  assert.equal(Math.min(...Object.values(net.valLossBySeed)), net.valLossBySeed[net.seed]);
});

test('con la red v3 exportada, el estrés del banano regulado es menor que el del café con malezas y mayor que el del café limpio (simulador, sin riego)', () => {
  const s = ev.stress.years2001_2024;
  assert.ok(s.regulated.drySeasonStressDays < s.weedy.drySeasonStressDays && s.regulated.drySeasonStressDays > s.none.drySeasonStressDays);
  assert.ok(s.dense.drySeasonStressDays > s.regulated.drySeasonStressDays);
});
