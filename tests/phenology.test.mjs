import test from 'node:test'; import assert from 'node:assert/strict';
import { buildPhase, kcOnDay, onsetSowIdx, TREF, stageGdd } from '../web/js/model/phenology.js';

const crop = { id: 't', tbase: 10, days: { ini: 20, dev: 35, mid: 40, late: 25 }, kc: { ini: 0.3, mid: 1.2, end: 0.35 } };

// Año 2010 completo, lluvia 0 salvo 7 mm el 10, 11 y 12 de mayo.
const dates = [];
for (let d = new Date(Date.UTC(2010, 0, 1)); d.getUTCFullYear() === 2010; d.setUTCDate(d.getUTCDate() + 1)) dates.push(d.toISOString().slice(0, 10));
const zeros = dates.map(() => 0);
const rain = dates.map((s) => (['2010-05-10', '2010-05-11', '2010-05-12'].includes(s) ? 7 : 0));

test('TREF y grados-día por etapa', () => {
  assert.equal(TREF, 26);
  assert.deepEqual(stageGdd(crop), { ini: 320, dev: 560, mid: 640, late: 400 });
});
test('tmean = TREF: cosecha a los 120 días', () => {
  const ph = buildPhase(crop, 0, Array(400).fill(26));
  assert.equal(ph.harvestIdx, 119);
  assert.equal(ph.endIdx.ini, 19);
  assert.equal(ph.cycleIncomplete, false);
  assert.equal(ph.cropId, 't');
  assert.deepEqual(ph.floweringIdx, [ph.endIdx.dev + 1, ph.endIdx.dev + 16]);
});
test('tmean 18 °C: ciclo el doble de largo', () => {
  const ph = buildPhase(crop, 0, Array(400).fill(18));
  assert.ok(Math.abs(ph.harvestIdx - 239) <= 1);
});
test('Kc: ini 0.3, mitad de dev 0.75, mid 1.2, fuera 0', () => {
  const ph = buildPhase(crop, 0, Array(400).fill(26));
  assert.equal(kcOnDay(crop, ph, 5), 0.3);
  assert.ok(Math.abs(kcOnDay(crop, ph, 37) - 0.75) < 0.03);
  assert.equal(kcOnDay(crop, ph, 70), 1.2);
  assert.ok(Math.abs(kcOnDay(crop, ph, 107) - 0.775) < 0.03);
  assert.equal(kcOnDay(crop, ph, 120), 0);
  const ph2 = buildPhase(crop, 10, Array(400).fill(26));
  assert.equal(kcOnDay(crop, ph2, 9), 0);
});
test('altura: ciclo incompleto marcado, sin pasar del arreglo', () => {
  const ph = buildPhase(crop, 300, Array(365).fill(12));
  assert.equal(ph.cycleIncomplete, true);
  assert.equal(ph.harvestIdx, 364);
  assert.equal(ph.endIdx.late, 364);
});
test('grados-día no acumulan bajo tbase', () => {
  const t = Array(200).fill(5).fill(26, 100);
  const ph = buildPhase(crop, 0, t);
  assert.equal(ph.endIdx.ini, 119);
});
test('inicio de lluvias: 7+7+7 mm desde el 10 de mayo', () => {
  const r = onsetSowIdx(rain, dates, 2010);
  assert.equal(dates[r.idx], '2010-05-12'); assert.equal(r.onsetFallback, false);
});
test('año sin inicio: 15 de junio con respaldo', () => {
  const r = onsetSowIdx(zeros, dates, 2010);
  assert.equal(dates[r.idx], '2010-06-15'); assert.equal(r.onsetFallback, true);
});
test('año ausente en las fechas: error que nombra el año', () => {
  assert.throws(() => onsetSowIdx(zeros, dates, 1999), /1999/);
});
