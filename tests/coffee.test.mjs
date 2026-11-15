import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { loadCrops } from '../web/js/model/crops.js';
import { computeEt0Series, runSequence } from '../web/js/model/simulate.js';
import { simulateDays } from '../web/js/model/waterBalance.js';
import { buildPerennialPhase } from '../web/js/model/phenology.js';
import { plotAdjust, floweringFor, simulateCoffee, stressOver, coffeeYearMeasures } from '../web/js/model/coffee.js';

const read = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));
const crops = loadCrops(read('../web/data/crops.json'));
const cafe = crops.get('cafe');
const isoDays = (from, n) => Array.from({ length: n }, (_, i) => new Date(Date.UTC(...from) + i * 864e5).toISOString().slice(0, 10));
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-12, `${a} vs ${b}`);

test('café: valores FAO-56 y sin Ky', () => {
  assert.deepEqual(cafe.kc, { ini: 0.9, mid: 0.95, end: 0.95 });
  assert.deepEqual(cafe.kcWeedCover, { ini: 1.05, mid: 1.1, end: 1.1 });
  assert.equal(cafe.zrMax, 1.2); assert.equal(cafe.p, 0.4); assert.equal(cafe.ky, null); assert.equal(cafe.perennial, true);
});
test('cultivos existentes: rotaciones idénticas en un piloto (hash fijado antes del cambio)', () => {
  const seq = read('../web/data/sequences.json');
  const bundle = read('../web/data/snapshots/jutiapa.json'); const et0 = computeEt0Series(bundle);
  const out = {};
  for (const id of Object.keys(seq)) for (const irrigation of ['none', 'limited', 'full']) out[`${id}|${irrigation}`] = runSequence({ sequence: seq[id], bundle, et0, crops, texture: 'loam', slopeClass: 'moderate', irrigation });
  assert.equal(createHash('sha256').update(JSON.stringify(out)).digest('hex'), 'f9ac5ec7fa456bc2b15ee0fcb24e65c9dee125ba37299ea5ac13eca0dc45ffdd');
});
test('perenne: Kc 0.95 todo el año y raíces constantes de 1.2 m (TAW loam = 1000·0.13·1.2 = 156 mm)', () => {
  const sim = simulateDays({ rain: [0, 0, 0], et0: [4, 4, 4], phases: [buildPerennialPhase(cafe, 3)], crops, texture: 'loam', slopeClass: 'flat', irrigation: 'none', drInit: 0 });
  assert.deepEqual(sim.kc, [0.95, 0.95, 0.95]); assert.deepEqual(sim.zr, [1.2, 1.2, 1.2]);
  near(sim.taw[0], 156);
  near(sim.dr[2], 3 * 3.8); // 3 días × 0.95 × 4 mm
});
test('sombra: tabla diaria del ajuste, a mano', () => {
  const dates = ['2020-07-15', '2020-01-15'];
  assert.equal(plotAdjust(dates, 'none', 'evergreen'), null);
  assert.deepEqual(plotAdjust(dates, 'trees', 'evergreen'), { reduce: [0.52, 0], add: [0.2, 0.2] });
  assert.deepEqual(plotAdjust(dates, 'trees', 'deciduous'), { reduce: [0.52, 0], add: [1.2, 0.06] });
  assert.throws(() => plotAdjust(dates, 'trees', 'palm'));
});
test('sombra: efecto 1 (−0.52 mm en lluvias, no bajo cero) y efecto 2 (transpiración de árboles) en la demanda', () => {
  const run = (date, et0, shade, treeType) => simulateCoffee({ dates: [date], rain: [0], et0: [et0], crops, texture: 'loam', shade, treeType, drInit: 0 }).etc[0];
  near(run('2020-07-15', 4, 'none'), 3.8);
  near(run('2020-07-15', 4, 'trees', 'evergreen'), 3.8 - 0.52 + 0.2);
  near(run('2020-07-15', 4, 'trees', 'deciduous'), 3.8 - 0.52 + 1.2);
  near(run('2020-01-15', 4, 'trees', 'evergreen'), 3.8 + 0.2); // estación seca: sin recorte de evaporación
  near(run('2020-01-15', 4, 'trees', 'deciduous'), 3.8 + 0.06);
  near(run('2020-07-15', 0.4, 'trees', 'evergreen'), 0.2); // 0.38 − 0.52 < 0 → 0, luego + 0.2
});
test('floración: primer día ≥ 10 mm entre el 15 feb y el 30 abr, más 9 días', () => {
  const dates = isoDays([2021, 0, 1], 365); const rain = Array(365).fill(0);
  rain[dates.indexOf('2021-02-14')] = 50; // fuera de la ventana
  rain[dates.indexOf('2021-03-03')] = 9.9; // < 10
  rain[dates.indexOf('2021-03-10')] = 10; rain[dates.indexOf('2021-04-01')] = 40;
  const f = floweringFor(dates, rain, 2021);
  assert.equal(dates[f.triggerIdx], '2021-03-10'); assert.equal(dates[f.idx], '2021-03-19'); assert.equal(f.noTrigger, false);
  const g = floweringFor(dates, Array(365).fill(0), 2021);
  assert.equal(dates[g.idx], '2021-05-09'); assert.equal(g.noTrigger, true); assert.equal(g.triggerIdx, null);
});
test('medidas de estrés: días con Ks<1 y ETa/ETc por ventana, a mano', () => {
  const sim = { ks: [1, 0.5, 0.8, 1], eta: [4, 2, 3, 4], etc: [4, 4, 4, 4] };
  const m = stressOver(sim, 1, 3);
  assert.equal(m.stressDays, 2); assert.equal(m.n, 3); near(m.etaOverEtc, 9 / 12);
});
test('medidas del año cafetalero: ventanas 0–90 y 91–120 tras la floración y nov–abr', () => {
  const dates = isoDays([2020, 10, 1], 365 + 31);
  const n = dates.length; const rain = Array(n).fill(0);
  rain[dates.indexOf('2021-03-01')] = 20; // floración 10 mar 2021
  const ks = Array(n).fill(1); const fl = dates.indexOf('2021-03-10');
  ks[fl] = 0.9; ks[fl + 90] = 0.9; ks[fl + 91] = 0.9; ks[fl + 120] = 0.9; ks[fl + 121] = 0.9;
  const sim = { ks, eta: Array(n).fill(1), etc: Array(n).fill(2) };
  const r = coffeeYearMeasures({ sim, dates, rain, year: 2020 });
  assert.equal(r.floweringDate, '2021-03-10'); assert.equal(r.fruitSet.stressDays, 2); assert.equal(r.fruitSet.n, 91);
  assert.equal(r.grainFill.stressDays, 2); assert.equal(r.grainFill.n, 30); assert.equal(r.drySeason.stressDays, 1); assert.equal(r.drySeason.n, 181);
  near(r.fruitSet.etaOverEtc, 0.5);
});
