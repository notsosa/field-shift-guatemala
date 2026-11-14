import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCrops } from '../web/js/model/crops.js';
import { computeEt0Series, agriculturalYears } from '../web/js/model/simulate.js';
import { climateFeatures, phenoFeatures, mlpPredict } from '../web/js/model/emulator.js';
import {
  SOW_OFFSETS, median, pickBestOffset, compareRanking, yearSlices, findBestSowing,
} from '../web/js/ui/bestSowing.js';

const readJson = (p) => JSON.parse(readFileSync(new URL(`../web/data/${p}`, import.meta.url), 'utf8'));

test('SOW_OFFSETS va de -20 a +30 cada 2 días (26 fechas)', () => {
  assert.equal(SOW_OFFSETS.length, 26);
  assert.equal(SOW_OFFSETS[0], -20);
  assert.equal(SOW_OFFSETS.at(-1), 30);
  assert.ok(SOW_OFFSETS.every((o, i) => i === 0 || o - SOW_OFFSETS[i - 1] === 2));
});

test('median: impar, par, sin mutar la entrada, vacío → null', () => {
  const a = [5, 1, 3];
  assert.equal(median(a), 3);
  assert.deepEqual(a, [5, 1, 3]);
  assert.equal(median([4, 1, 3, 2]), 2.5);
  assert.equal(median([]), null);
});

test('pickBestOffset: máxima mediana; empates → el desfase más cercano a 0', () => {
  assert.equal(pickBestOffset([{ offset: -2, median: 0.5 }, { offset: 4, median: 0.9 }, { offset: 0, median: 0.7 }]).offset, 4);
  assert.equal(pickBestOffset([{ offset: -6, median: 1 }, { offset: 4, median: 1 }, { offset: -2, median: 1 }]).offset, -2);
  assert.equal(pickBestOffset([{ offset: 2, median: 1 }, { offset: -2, median: 1 }]).offset, -2);
  assert.equal(pickBestOffset([{ offset: 0, median: null }, { offset: 2, median: 0.4 }]).offset, 2);
  assert.equal(pickBestOffset([]), null);
});

test('compareRanking: confirma, contradice o empata según el simulador', () => {
  assert.equal(compareRanking(0.90, 0.95), 'agree');
  assert.equal(compareRanking(0.95, 0.90), 'disagree');
  assert.equal(compareRanking(0.9300, 0.9304), 'tie');
});

const bundle = readJson('snapshots/chiquimula.json');
const et0 = computeEt0Series(bundle);
const crops = loadCrops(readJson('crops.json'));
const sequences = readJson('sequences.json');
const net = readJson('emulator_mlp.json');
const years = agriculturalYears(bundle.dates).map((a) => a.year);

test('yearSlices: las features del año recortado son idénticas a las del bundle completo', () => {
  const slices = yearSlices(bundle, et0, years);
  assert.equal(slices.length, 24);
  for (const s of slices.filter((x) => [2005, 2015, 2023].includes(x.year))) {
    assert.deepEqual(climateFeatures(s.bundle, s.year, s.et0), climateFeatures(bundle, s.year, et0));
    for (const off of [-20, 0, 30]) {
      assert.deepEqual(phenoFeatures(s.bundle, s.year, s.et0, crops, off), phenoFeatures(bundle, s.year, et0, crops, off));
    }
  }
});

test('findBestSowing (MLP, Chiquimula, rotación actual): propone un desfase y lo confirma con runSequence', () => {
  const slices = yearSlices(bundle, et0, years);
  const r = findBestSowing({
    bundle, et0, slices, crops, sequence: sequences.actual,
    predict: (x) => mlpPredict(net, x),
    management: { texture: 'loam', slopeClass: 'moderate', irrigation: 'none', sequenceId: 'actual' },
  });
  assert.equal(r.rows.length, 26);
  for (const row of r.rows) assert.ok(row.median >= 0 && row.median <= 1, `offset ${row.offset}: ${row.median}`);
  assert.ok(SOW_OFFSETS.includes(r.best.offset));
  assert.ok(r.emulator.best >= r.emulator.zero);
  for (const v of [r.simulator.zero, r.simulator.best]) assert.ok(v >= 0 && v <= 1);
  assert.equal(r.simulator.n, 24);
  assert.ok(['agree', 'disagree', 'tie', 'same'].includes(r.verdict));
  assert.ok(r.emulator.ms >= 0 && r.simulator.ms >= 0);
  assert.ok(r.emulator.ms < 2000, `búsqueda con el emulador tardó ${r.emulator.ms} ms`);
});

test('findBestSowing: secuencia con riego obligatorio y sin riego → notApplicable', () => {
  const r = findBestSowing({
    bundle, et0, slices: yearSlices(bundle, et0, years), crops, sequence: sequences.extra_riego,
    predict: (x) => mlpPredict(net, x),
    management: { texture: 'loam', slopeClass: 'moderate', irrigation: 'none', sequenceId: 'extra_riego' },
  });
  assert.equal(r.notApplicable, true);
});
