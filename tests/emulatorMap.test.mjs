import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { mlpPredict } from '../web/js/model/emulator.js';
import { loadCrops } from '../web/js/model/crops.js';
import {
  computeMapValues, divergingColor, DIVERGING_STOPS, niceLimit, foodCropIds, compareFoodCrops, summarize, diffBand, cellGroups, cellLines, accuracyText,
  tooltipAim,
} from '../web/js/ui/emulatorMap.js';

const readJson = (p) => JSON.parse(readFileSync(new URL(`../web/data/${p}`, import.meta.url), 'utf8'));

test('foodCropIds: cultivos de la secuencia con ky ≠ null (los que promedia waterIndex)', () => {
  const crops = loadCrops(readJson('crops.json'));
  const seqs = readJson('sequences.json');
  assert.deepEqual(foodCropIds(seqs.actual, crops), ['maiz', 'frijol']);
  assert.deepEqual(foodCropIds(seqs.proteger, crops), ['maiz']);
  assert.deepEqual(foodCropIds(seqs.extra_riego, crops), ['maiz', 'frijol', 'sandia']);
});

test('compareFoodCrops: detecta cuándo waterIndex no compara los mismos cultivos', () => {
  const crops = loadCrops(readJson('crops.json'));
  const seqs = readJson('sequences.json');
  assert.deepEqual(compareFoodCrops(seqs.actual, seqs.actual, crops),
    { same: true, alt: ['maiz', 'frijol'], current: ['maiz', 'frijol'], missing: [], added: [] });
  const p = compareFoodCrops(seqs.proteger, seqs.actual, crops);
  assert.equal(p.same, false);
  assert.deepEqual(p.missing, ['frijol']);
  assert.deepEqual(p.added, []);
  const s = compareFoodCrops(seqs.extra_secano, seqs.actual, crops);
  assert.equal(s.same, false);
  assert.deepEqual([s.missing, s.added], [['frijol'], ['ajonjoli']]);
  const r = compareFoodCrops(seqs.extra_riego, seqs.actual, crops);
  assert.deepEqual([r.same, r.missing, r.added], [false, [], ['sandia']]);
});
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
  // El tiempo fino se mide en el navegador (verify_emulator.py); aquí solo un tope holgado.
  assert.ok(r.ms < 10000, `mapa tardó ${r.ms} ms`);
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

const pt = (id, median) => ({ point: { id, name: id }, median });

test('summarize: la banda de "casi igual" es la que se le pasa (error medido de la diferencia)', () => {
  const vals = [pt('a', 0.01), pt('b', -0.002), pt('c', 0.03), pt('d', -0.05)];
  const s = summarize(vals, 'waterIndex', 0.02);
  assert.deepEqual([s.better, s.same, s.worse, s.n], [1, 2, 1, 4]);
  assert.equal(s.top.point.id, 'c');
  assert.equal(s.bottom.point.id, 'd');
  // Suelo desnudo: menos días es mejor.
  const b = summarize([pt('a', -0.05), pt('b', 0.001)], 'bareFrac', 0.01);
  assert.deepEqual([b.better, b.same, b.worse], [1, 1, 0]);
});

test('diffBand: RMSE de la diferencia por modelo, alternativa y objetivo, con respaldo si falta', () => {
  const ev = { diffError: { mlp: { proteger: { bareFrac: { rmse: 0.012, signAgreement: 0.98 } } } } };
  assert.deepEqual(diffBand(ev, 'mlp', 'proteger', 'bareFrac'), { band: 0.012, signAgreement: 0.98, measured: true });
  const f = diffBand(ev, 'elmBrowser', 'proteger', 'bareFrac');
  assert.equal(f.measured, false);
  assert.ok(f.band > 0);
});

const cellPts = [
  { id: 'a', name: 'A', elevation: 403, cellElevation: 762.46, weatherMates: ['b', 'c'], identicalMates: ['b'] },
  { id: 'b', name: 'B', elevation: 459, cellElevation: 762.46, weatherMates: ['a', 'c'], identicalMates: ['a'] },
  { id: 'c', name: 'C', elevation: 222, cellElevation: 762.46, weatherMates: ['a', 'b'], identicalMates: [] },
  { id: 'd', name: 'D', elevation: 1787, cellElevation: 1515.75, weatherMates: ['e'], identicalMates: [] },
  { id: 'e', name: 'E', elevation: 946, cellElevation: 1515.75, weatherMates: ['d'], identicalMates: [] },
  { id: 'f', name: 'F', elevation: 545, cellElevation: 607.66, weatherMates: [], identicalMates: [] },
];

test('cellGroups: municipios que comparten celda (con la elevación de la celda), pueblos arriba de 1,500 m e insumos idénticos', () => {
  const g = cellGroups(cellPts);
  assert.equal(g.nShared, 5);
  assert.deepEqual(g.groups.map((x) => x.ids), [['a', 'b', 'c'], ['d', 'e']]);
  assert.deepEqual(g.groups.map((x) => x.elevation), [762.46, 1515.75]);
  assert.deepEqual(g.high, [{ ids: ['d'], elevation: 1787 }]); // E comparte la celda de 1,516 m pero el pueblo está a 946 m
  assert.deepEqual(g.identical, [['a', 'b']]);
});

test('cellLines: banderas del tooltip con la celda compartida, su elevación y la del pueblo', () => {
  const byId = new Map(cellPts.map((p) => [p.id, p]));
  const [shared, same] = cellLines('en', cellPts[0], byId);
  assert.equal(shared, 'Coarse weather cell shared with B and C; cell elevation 762 m, town 403 m (temperature moved to the town)');
  assert.equal(same, 'Identical rain, radiation and wind inputs to B');
  assert.deepEqual(cellLines('en', cellPts[3], byId), ['Coarse weather cell shared with E; cell elevation 1,516 m, town 1,787 m (temperature moved to the town)']);
  assert.deepEqual(cellLines('en', cellPts[5], byId), ['Own weather cell; cell elevation 608 m, town 545 m (temperature moved to the town)']);
});

test('accuracyText: con la ELM usa los puntajes de la ELM del navegador (elmBrowser)', () => {
  const ev = {
    mlp: { r2: [0.9, 0.8, 0.97], rmse: [0.04, 0.04, 0.01] }, bySplit: { testYears: { mlp: { r2: [0.81, 0.7, 0.96] } } },
    elmBrowser: { r2: [0.66, 0.44, 0.94], rmse: [0.07, 0.05, 0.02], bySplit: { testYears: { r2: [0.55, 0.1, 0.93] } } },
  };
  assert.equal(accuracyText('en', ev, 'elmBrowser', 2), 'ELM on this output: R² 0.94 on all tests, 0.93 on new years.');
  assert.equal(accuracyText('en', ev, 'mlp', 0), 'MLP on this output: R² 0.90 on all tests, 0.81 on new years.');
});

test('tooltipAim: el tooltip se abre lejos del borde y se corre para caber en el mapa', () => {
  // Arriba a la izquierda (Cubulco): hacia abajo y corrido a la derecha, sin salirse por arriba.
  assert.deepEqual(tooltipAim(100, 50, 640, 470), { direction: 'bottom', offset: [30, 10] });
  // Abajo a la derecha: hacia arriba y corrido a la izquierda.
  assert.deepEqual(tooltipAim(600, 440, 640, 470), { direction: 'top', offset: [-90, -10] });
  // En medio a la izquierda / derecha: hacia el lado con espacio.
  assert.deepEqual(tooltipAim(60, 240, 640, 470), { direction: 'right', offset: [12, 0] });
  assert.deepEqual(tooltipAim(600, 240, 640, 470), { direction: 'left', offset: [-12, 0] });
  assert.deepEqual(tooltipAim(320, 240, 640, 470), { direction: 'top', offset: [0, -10] });
});
