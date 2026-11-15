import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCrops } from '../web/js/model/crops.js';
import { computeEt0Series, agriculturalYears, runSequence } from '../web/js/model/simulate.js';
import { climateFeatures, phenoFeatures, mlpPredict } from '../web/js/model/emulator.js';
import {
  SOW_OFFSETS, median, pickBestOffset, compareRanking, yearSlices, findBestSowing, simulateOffset, renderSowingResult,
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
  // El tiempo fino se mide en el navegador (verify_emulator.py); aquí solo un tope holgado.
  assert.ok(r.emulator.ms < 10000, `búsqueda con el emulador tardó ${r.emulator.ms} ms`);
  // Solo se proponen desfases >= 0; el borde de la búsqueda se marca.
  assert.ok(r.best.offset >= 0);
  assert.equal(r.atEdge, r.best.offset >= 26);
  // Por cultivo (maíz y frijol) en 0 y en la propuesta, y días de traslape entre cultivos seguidos.
  for (const side of [r.simulator.cropsZero, r.simulator.cropsBest]) {
    assert.deepEqual(side.map((c) => c.cropId), ['maiz', 'frijol']);
    for (const c of side) assert.ok(c.median >= 0 && c.median <= 1);
  }
  for (const side of [r.simulator.overlapsZero, r.simulator.overlapsBest]) {
    assert.deepEqual(side.map((o) => [o.a, o.b]), [['maiz', 'frijol']]);
    assert.ok(side[0].days >= 0);
  }
});

const fakeNet = (score) => (x) => [score(Math.round(x[24] * 30)), 1, 0.2];
const mgmt = { texture: 'loam', slopeClass: 'moderate', irrigation: 'none', sequenceId: 'actual' };

test('findBestSowing: un óptimo antes del inicio no se propone (retrospectiva); se queda en el mejor desfase >= 0', () => {
  const r = findBestSowing({
    bundle, et0, slices: yearSlices(bundle, et0, years), crops, sequence: sequences.actual,
    predict: fakeNet((off) => 0.9 - ((off + 10) / 100) ** 2), management: mgmt,
  });
  assert.equal(r.best.offset, 0);
  assert.equal(r.verdict, 'same');
  assert.equal(r.hindsight.offset, -10);
  assert.equal(r.rows.length, 26); // la curva conserva los desfases negativos
  assert.equal(r.atEdge, false);
});

test('findBestSowing: mejor desfase pegado al borde (+30) → atEdge', () => {
  const r = findBestSowing({
    bundle, et0, slices: yearSlices(bundle, et0, years), crops, sequence: sequences.actual,
    predict: fakeNet((off) => 0.5 + off / 100), management: mgmt,
  });
  assert.equal(r.best.offset, 30);
  assert.equal(r.atEdge, true);
  assert.equal(r.hindsight, null);
});

test('simulateOffset: un cultivo que no termina en el año cuenta como 0 por cultivo y en el índice', () => {
  const sm = readJson('snapshots/sanmartin.json');
  const smEt0 = computeEt0Series(sm);
  const smYears = agriculturalYears(sm.dates).map((a) => a.year);
  const args = { sequence: sequences.extra_secano, bundle: sm, et0: smEt0, crops, years: smYears, texture: 'loam', slopeClass: 'moderate', irrigation: 'none', offset: 0 };
  const r = simulateOffset(args);
  const res = runSequence({ ...args, sowOffsetDays: 0 });
  const sesame = res.map((y) => (y.crops[1].cycleIncomplete ? 0 : y.crops[1].relYield));
  assert.ok(r.crops[1].incomplete > 0, 'el ajonjolí no termina en algunos años a 1,516 m');
  assert.equal(r.crops[1].cropId, 'ajonjoli');
  assert.equal(r.crops[1].median, median(sesame));
  assert.equal(r.incompleteYears, res.filter((y) => y.crops.some((c) => c.relYield != null && c.cycleIncomplete)).length);
});

const fakeResult = (verdict, bestOffset, extra = {}) => ({
  verdict, best: { offset: bestOffset, sowDoy: 160 + bestOffset }, zero: { offset: 0, sowDoy: 160 }, years: [2001, 2024],
  rows: [], atEdge: false, maxOffset: 30, hindsight: null,
  emulator: { zero: 0.9, best: 0.95, ms: 10, dates: 26 },
  simulator: {
    zero: 0.93, best: verdict === 'disagree' ? 0.91 : 0.97, ms: 12, dates: 2, n: 24,
    cropsZero: [{ cropId: 'maiz', median: 0.99, incomplete: 0 }, { cropId: 'frijol', median: 0.92, incomplete: 0 }],
    cropsBest: [{ cropId: 'maiz', median: 1, incomplete: 0 }, { cropId: 'frijol', median: 0.96, incomplete: 0 }],
    overlapsZero: [{ a: 'maiz', b: 'frijol', days: 33.5 }], overlapsBest: [{ a: 'maiz', b: 'frijol', days: 67.5 }],
    incompleteYears: 0,
  },
  ...extra,
});
const ctx = { lang: 'en', modelShort: 'MLP', cropName: (id) => ({ maiz: 'Maize', frijol: 'Beans' }[id]) };
const html = (r, c = ctx) => { const el = { innerHTML: '' }; renderSowingResult(el, r, c); return el.innerHTML; };

test('renderSowingResult: el titular sigue al veredicto del simulador', () => {
  assert.match(html(fakeResult('agree', 28)), /Proposal: sow <strong>28 days after<\/strong> the rain onset/);
  assert.match(html(fakeResult('agree', 28)), /agrees it beats sowing at the onset/);
  for (const v of ['disagree', 'tie']) {
    const h = html(fakeResult(v, 28));
    assert.doesNotMatch(h, /Proposal/, v);
    assert.doesNotMatch(h, /confirms/, v);
  }
  assert.match(html(fakeResult('disagree', 28)), /Keep sowing at the rain onset/);
  assert.match(html(fakeResult('tie', 28)), /No clear gain/);
  assert.match(html(fakeResult('same', 0)), /Keep sowing at the rain onset/);
});

test('renderSowingResult: borde de búsqueda, tabla por cultivo con traslape, simplificación y aviso de solo agua', () => {
  const h = html(fakeResult('agree', 30, { atEdge: true }));
  assert.match(h, /still rising/i);
  assert.match(h, /data-testid="sow-crops"/);
  assert.match(h, /Maize/);
  assert.match(h, /Beans/);
  assert.match(h, /99\.0%/);
  assert.match(h, /96\.0%/);
  assert.match(h, /33\.5/);
  assert.match(h, /67\.5/);
  assert.match(h, /one soil-water bucket/);
  assert.match(h, /Water only/);
  assert.doesNotMatch(html(fakeResult('agree', 20)), /still rising/i);
  const es = html(fakeResult('agree', 30, { atEdge: true }), { ...ctx, lang: 'es' });
  assert.match(es, /sigue subiendo/i);
  assert.match(es, /Solo agua/);
});

test('findBestSowing: secuencia con riego obligatorio y sin riego → notApplicable', () => {
  const r = findBestSowing({
    bundle, et0, slices: yearSlices(bundle, et0, years), crops, sequence: sequences.extra_riego,
    predict: (x) => mlpPredict(net, x),
    management: { texture: 'loam', slopeClass: 'moderate', irrigation: 'none', sequenceId: 'extra_riego' },
  });
  assert.equal(r.notApplicable, true);
});
