import test from 'node:test'; import assert from 'node:assert/strict';
import { annualRainStats } from '../web/js/data/rainCompare.js';

function isoRange(start, n) {
  const out = []; const t = new Date(start + 'T00:00:00Z');
  for (let i = 0; i < n; i++) { out.push(t.toISOString().slice(0, 10)); t.setUTCDate(t.getUTCDate() + 1); }
  return out;
}

// Año agrícola 2001 = 1 abr 2001 .. 31 mar 2002 (365 días) + 10 días del año 2002 (incompleto).
const dates = isoRange('2001-04-01', 375);
const base = () => dates.map(() => 1);

test('annualRainStats: totales por año agrícola, mayo-octubre y canicula (cifras calculadas a mano)', () => {
  const rain = base();
  for (let d = 10; d <= 20; d++) rain[dates.indexOf(`2001-07-${d}`)] = 0;       // 11 dias secos seguidos en julio
  rain[dates.indexOf('2001-08-05')] = 0.9;                                      // 0.9 mm tambien cuenta como seco (< 1 mm)
  const m = annualRainStats(dates, rain);
  assert.deepEqual([...m.keys()], [2001]); // 2002 esta incompleto y no aparece
  const y = m.get(2001);
  // total: 365 dias de 1 mm menos 11 dias en 0 y un dia de 0.9 -> 365 - 11 - 0.1 = 353.9
  assert.ok(Math.abs(y.totalMm - 353.9) < 1e-9);
  // 1 mayo - 31 oct = 184 dias, menos lo mismo -> 184 - 11 - 0.1 = 172.9
  assert.ok(Math.abs(y.mayOctMm - 172.9) < 1e-9);
  assert.equal(y.caniculaDays, 11);
  assert.equal(y.missingDays, 0); assert.equal(y.days, 365);
});

test('annualRainStats: un dia null deja las cifras del anio en null y cuenta el faltante', () => {
  const rain = base(); rain[100] = null;
  const y = annualRainStats(dates, rain).get(2001);
  assert.equal(y.missingDays, 1);
  assert.equal(y.totalMm, null); assert.equal(y.mayOctMm, null); assert.equal(y.caniculaDays, null);
});

test('annualRainStats: la racha de canicula no cruza fuera de 1 jul - 31 ago y se corta con un dia >= 1 mm', () => {
  const rain = base();
  for (const d of ['2001-06-28', '2001-06-29', '2001-06-30', '2001-07-01', '2001-07-02']) rain[dates.indexOf(d)] = 0; // 3 de junio no cuentan
  for (let d = 20; d <= 31; d++) rain[dates.indexOf(`2001-08-${d}`)] = 0;     // 12 dias hasta el 31 ago
  rain[dates.indexOf('2001-09-01')] = 0; rain[dates.indexOf('2001-09-02')] = 0; // septiembre no cuenta
  assert.equal(annualRainStats(dates, rain).get(2001).caniculaDays, 12);
});
