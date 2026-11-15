import test from 'node:test'; import assert from 'node:assert/strict';
import { annualRainStats, compareSources, coverageOf } from '../web/js/data/rainCompare.js';

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

test('compareSources: cinco productos, una serie con un dia null; medias comunes solo en los anios completos de todas (cifras a mano)', () => {
  const ds = isoRange('2001-04-01', 365 + 365 + 366); // anios agricolas 2001, 2002, 2003 (2003 incluye el 29 feb 2004)
  const flat = (v) => ds.map(() => v);
  const imerg = flat(1); imerg[400] = null;           // un dia dentro del anio agricola 2002
  const rainAlt = { ERA5: flat(1), IMERG: imerg, CHIRPS: flat(2), POWER: flat(0.5), IMERG_LATE: flat(3) };
  const labels = { IMERG: 'conjunto 26', IMERG_LATE: 'conjunto 226' };
  const out = compareSources(ds, rainAlt, [2001, 2002, 2003], labels, { sinImerg: ['ERA5', 'CHIRPS', 'POWER', 'IMERG_LATE'] });
  assert.deepEqual(Object.keys(out.sources), ['ERA5', 'IMERG', 'CHIRPS', 'POWER', 'IMERG_LATE']);
  assert.equal(out.sources.IMERG_LATE.label, 'conjunto 226');
  assert.deepEqual(out.sources.IMERG_LATE.annualMm, [1095, 1095, 1098]);
  assert.deepEqual(out.sources.IMERG.annualMm, [365, null, 366]);
  assert.deepEqual(out.sources.IMERG.missingDays, [0, 1, 0]);
  assert.equal(out.sources.IMERG.validYears, 2);
  assert.equal(out.sources.IMERG_LATE.validYears, 3);
  assert.equal(out.sources.IMERG_LATE.meanAnnualMm, 1096);     // (1095 + 1095 + 1098) / 3
  assert.equal(out.sources.IMERG.meanAnnualMm, 365.5);          // solo los 2 anios completos
  assert.deepEqual(out.common.years, [2001, 2003]);             // 2002 tiene un hueco en IMERG
  assert.equal(out.common.meanAnnualMm.IMERG_LATE, 1096.5);     // (1095 + 1098) / 2
  assert.equal(out.common.meanAnnualMm.ERA5, 365.5);
  assert.equal(out.common.products, undefined);
  // conjunto nombrado: sin IMERG (el de la brecha) los tres anios son comunes y las medias cambian
  assert.deepEqual(out.commonSets.sinImerg.years, [2001, 2002, 2003]);
  assert.deepEqual(out.commonSets.sinImerg.products, ['ERA5', 'CHIRPS', 'POWER', 'IMERG_LATE']);
  assert.equal(out.commonSets.sinImerg.meanAnnualMm.ERA5, 365.3);   // (365 + 365 + 366) / 3 = 365.33
  assert.equal(out.commonSets.sinImerg.meanAnnualMm.IMERG_LATE, 1096);
  assert.equal(out.common.meanCaniculaDays.ERA5, 0);            // 1 mm/dia: ningun dia < 1 mm
  assert.equal(out.common.meanCaniculaDays.POWER, 62);          // 0.5 mm/dia: 1 jul - 31 ago completo (62 dias)
});

import { readFileSync } from 'node:fs';
test('rain_compare.json: IMERG_LATE (dataset 226) is in every pilot, with the three gap years left null and the earlier four-source means kept', () => {
  const j = JSON.parse(readFileSync(new URL('../web/data/rain_compare.json', import.meta.url), 'utf8'));
  for (const [id, p] of Object.entries(j.pilots)) {
    const s = p.sources.IMERG_LATE;
    assert.equal(s.validYears, 21, id);
    for (const y of [2014, 2023, 2024]) assert.equal(s.annualMm[j.years.indexOf(y)], null, `${id} ${y}`);
    assert.deepEqual(p.commonSets.withoutImergLate.years.length, 22, id);
    assert.ok(!('IMERG_LATE' in p.commonSets.withoutImergLate.meanAnnualMm), id);
    assert.ok(!p.common.years.includes(2014) && !p.common.years.includes(2023), id);
  }
  assert.equal(j.pilots.chiquimula.commonSets.withoutImergLate.meanAnnualMm.ERA5, 1098.9);
});

test('coverageOf: primer/ultimo dia con dato, dias sin dato y sus rangos, y total del anio calendario solo si esta completo (a mano)', () => {
  const ds = isoRange('2024-12-25', 7 + 365); // 25 dic 2024 .. 31 dic 2025 (2025 completo en fechas)
  const rain = ds.map(() => 1);
  rain[0] = null; rain[1] = null;                       // 25-26 dic 2024
  const a = coverageOf(ds, rain, 2025);
  assert.equal(a.first, '2024-12-27'); assert.equal(a.last, '2025-12-31');
  assert.equal(a.missingDays, 2); assert.deepEqual(a.missingRanges, [['2024-12-25', '2024-12-26']]);
  assert.equal(a.calendarYearTotalMm, 365);             // 365 dias de 1 mm
  const g = rain.slice(); g[10] = null; g[40] = null; g[41] = null; // 4 ene 2025, 3-4 feb 2025
  const b = coverageOf(ds, g, 2025);
  assert.deepEqual(b.missingRanges, [['2024-12-25', '2024-12-26'], ['2025-01-04', '2025-01-04'], ['2025-02-03', '2025-02-04']]);
  assert.equal(b.missingDays, 5); assert.equal(b.calendarYearTotalMm, null);  // 2025 tiene huecos: sin total
  assert.equal(coverageOf(ds.slice(0, 100), rain.slice(0, 100), 2025).calendarYearTotalMm, null); // 2025 incompleto en fechas
});
