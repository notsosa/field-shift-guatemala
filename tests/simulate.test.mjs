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
