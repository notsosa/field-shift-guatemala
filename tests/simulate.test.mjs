import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCrops } from '../web/js/model/crops.js';
import { et0PenmanMonteith } from '../web/js/model/et0.js';
import { computeEt0Series, agriculturalYears, runSequence } from '../web/js/model/simulate.js';

const read = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));
const crops = loadCrops(read('../web/data/crops.json'));
const seq = read('../web/data/sequences.json');

function makeBundle(temp) {
  const dates = [];
  for (let d = new Date(Date.UTC(2001, 3, 1)); d <= new Date(Date.UTC(2004, 2, 31)); d = new Date(d.getTime() + 864e5)) {
    dates.push(d.toISOString().slice(0, 10));
  }
  const n = dates.length;
  const rain = dates.map((s) => { const m = Number(s.slice(5, 7)); return m >= 5 && m <= 10 ? 8 : 0; });
  return {
    dates, rain, tmax: Array(n).fill(temp), tmin: Array(n).fill(temp), tdew: Array(n).fill(temp - 6),
    rs: Array(n).fill(18), u2: Array(n).fill(2), pressure: Array(n).fill(96), elevation: 400, lat: 14.8, lon: -90,
    rainSource: 'test', sources: [], fallback: false,
  };
}
const bundle = makeBundle(26);
const et0 = Array(bundle.dates.length).fill(4);
const run = (id, extra = {}) => runSequence({ sequence: seq[id], bundle, et0, crops, texture: 'loam', slopeClass: 'moderate', irrigation: 'none', ...extra });

test('3 años completos', () => {
  const ys = agriculturalYears(bundle.dates);
  assert.equal(ys.length, 3);
  assert.deepEqual(ys[0], { year: 2001, startIdx: 0, endIdx: 364 });
  assert.equal(bundle.dates[ys[2].endIdx], '2004-03-31');
});
test('años incompletos se excluyen', () => assert.equal(agriculturalYears(bundle.dates.slice(10, -10)).length, 1));
test('computeEt0Series: un día igual a la llamada directa', () => {
  const i = 100;
  const doy = Math.round((Date.UTC(2001, 6, 10) - Date.UTC(2001, 0, 0)) / 864e5);
  assert.equal(bundle.dates[i], '2001-07-10');
  const series = computeEt0Series(bundle);
  assert.equal(series.length, bundle.dates.length);
  const direct = et0PenmanMonteith({ tmax: 26, tmin: 26, tdew: 20, rs: 18, u2: 2, pressure: 96, elevation: 400, latDeg: 14.8, doy });
  assert.equal(series[i], direct);
});
test('actual: maíz sin estrés con lluvia abundante', () => {
  const r = run('actual');
  assert.equal(r.length, 3);
  assert.equal(r[0].crops[0].stressFlowering, false);
  assert.ok(r[0].crops[0].relYield > 0.9);
  assert.equal(r[0].crops[0].sowDate.length, 10);
  assert.equal(r[0].onsetFallback, false);
});
test('suelo desnudo: proteger < actual', () => assert.ok(run('proteger')[0].bareDaysRainy < run('actual')[0].bareDaysRainy));
test('mucuna sin ky: relYield null', () => assert.equal(run('proteger')[0].crops[1].relYield, null));
test('extra_riego sin riego -> []', () => assert.deepEqual(run('extra_riego'), []));
test('extra_riego con riego completo corre', () => {
  const r = run('extra_riego', { irrigation: 'full' });
  assert.equal(r[0].crops.length, 3);
  assert.ok(r[0].irrigationMm >= 0);
});
test('altura: cycleIncomplete propagado', () => {
  const b = makeBundle(12);
  const r = runSequence({ sequence: seq.actual, bundle: b, et0, crops, texture: 'loam', slopeClass: 'moderate', irrigation: 'none' });
  assert.equal(r[0].cycleIncomplete, true);
  assert.equal(r[0].crops[0].cycleIncomplete, true);
});
test('sowOffsetDays = 10 mueve la siembra del maíz exactamente 10 días', () => {
  const base = run('actual')[0].crops[0].sowDate;
  const moved = run('actual', { sowOffsetDays: 10 })[0].crops[0].sowDate;
  assert.equal((Date.parse(moved) - Date.parse(base)) / 864e5, 10);
});
test('sowOffsetDays fuera del año agrícola queda acotado', () => {
  const early = run('actual', { sowOffsetDays: -400 })[0];
  const late = run('actual', { sowOffsetDays: 400 })[0];
  assert.equal(early.crops[0].sowDate, '2001-04-01');
  assert.equal(late.crops[0].sowDate, '2002-03-31');
});

// ---- Tarea 15b: respuesta del rendimiento por etapa (FAO-33) ----
import { buildPhase } from '../web/js/model/phenology.js';
import { stageYield } from '../web/js/model/simulate.js';

const maiz = crops.get('maiz');
const synPhase = buildPhase(maiz, 10, Array(365).fill(26)); // ini 20, dev 35, mid 40, late 25 días
const synN = 365;
const synEt0 = Array(synN).fill(4);
const ksWith = (lo, hi, v) => Array.from({ length: synN }, (_, i) => (i >= lo && i <= hi ? v : 1));
const [fa, fb] = synPhase.floweringIdx;
const windows = {
  veg: [synPhase.sowIdx, synPhase.endIdx.dev],
  flower: [fa, fb],
  yieldForm: [fb + 1, synPhase.endIdx.mid],
  ripen: [synPhase.endIdx.mid + 1, synPhase.harvestIdx],
};
const syn = (crop, ks) => stageYield(crop, synPhase, { et0: synEt0, ks });

test('stageYield: sin estrés relYield = relYieldSeasonal = 1', () => {
  const r = syn(maiz, ksWith(0, 0, 1));
  assert.equal(r.relYield, 1);
  assert.equal(r.relYieldSeasonal, 1);
});
test('stageYield: déficit solo en floración (ratio 0.5): 1 − 1.5·0.5 = 0.25, menor que el estacional', () => {
  const r = syn(maiz, ksWith(...windows.flower, 0.5));
  assert.ok(Math.abs(r.relYield - 0.25) < 1e-9);
  assert.ok(r.relYield < r.relYieldSeasonal);
  assert.ok(Math.abs(r.stageRatios.flower - 0.5) < 1e-9);
  assert.equal(r.stageRatios.veg, 1);
});
test('stageYield: el mismo déficit en la etapa vegetativa: 1 − 0.4·0.5 = 0.8', () => {
  const r = syn(maiz, ksWith(...windows.veg, 0.5));
  assert.ok(Math.abs(r.relYield - 0.8) < 1e-9);
});
test('stageYield: dos etapas con estrés se multiplican', () => {
  const ks = ksWith(0, 0, 1);
  for (const [lo, hi] of [windows.veg, windows.yieldForm]) for (let i = lo; i <= hi; i++) ks[i] = 0.5;
  const r = syn(maiz, ks);
  assert.ok(Math.abs(r.relYield - (1 - 0.4 * 0.5) * (1 - 0.5 * 0.5)) < 1e-9); // 0.8 · 0.75 = 0.6
});
test('stageYield: kyStages null → relYield === relYieldSeasonal (fórmula estacional)', () => {
  const sorgo = crops.get('sorgo');
  const ph = buildPhase(sorgo, 10, Array(365).fill(26));
  const ks = Array.from({ length: synN }, (_, i) => (i % 3 === 0 ? 0.6 : 1));
  const r = stageYield(sorgo, ph, { et0: synEt0, ks });
  assert.equal(r.relYield, r.relYieldSeasonal);
  assert.ok(r.relYield < 1);
  assert.equal(r.stageRatios, null);
});
test('stageYield: mucuna sin ky → relYield null', () => {
  const m = crops.get('mucuna');
  const r = stageYield(m, buildPhase(m, 10, Array(365).fill(26)), { et0: synEt0, ks: ksWith(0, 0, 1) });
  assert.equal(r.relYield, null);
  assert.equal(r.relYieldSeasonal, null);
});
test('runSequence: CropYear trae relYieldSeasonal y stageRatios', () => {
  const c = run('actual')[0].crops[0];
  assert.equal(typeof c.relYieldSeasonal, 'number');
  assert.deepEqual(Object.keys(c.stageRatios), ['veg', 'flower', 'yieldForm', 'ripen']);
});
