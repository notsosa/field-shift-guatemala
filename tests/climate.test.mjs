import test from 'node:test'; import assert from 'node:assert/strict';
import { isInsideGuatemala, fetchPowerDaily, fetchEra5Rain, buildBundle, climateservRain } from '../web/js/data/climate.js';

const compact = (d) => d.replace(/-/g, '');
function isoRange(start, n) {
  const out = []; const t = new Date(start + 'T00:00:00Z');
  for (let i = 0; i < n; i++) { out.push(t.toISOString().slice(0, 10)); t.setUTCDate(t.getUTCDate() + 1); }
  return out;
}
function fakePowerJson(dates, overrides = {}) {
  const series = (v) => Object.fromEntries(dates.map((d) => [compact(d), v]));
  const parameter = { T2M_MAX: series(30), T2M_MIN: series(18), T2MDEW: series(16), ALLSKY_SFC_SW_DWN: series(20), WS2M: series(2), PS: series(95), ...overrides };
  return { geometry: { coordinates: [-89.5, 14.8, 423] }, properties: { parameter }, header: { fill_value: -999 } };
}
const jsonFetch = (body, calls = []) => async (url) => { calls.push(url); return { ok: true, status: 200, json: async () => body }; };
const rainJson = (dates, v = 1) => ({ daily: { time: dates, precipitation_sum: dates.map(() => v) } });

test('isInsideGuatemala: Pacifico fuera, Chiquimula dentro', () => {
  assert.equal(isInsideGuatemala(12.5, -91.0), false);
  assert.equal(isInsideGuatemala(14.8, -89.5), true);
  assert.equal(isInsideGuatemala(14.8, -93), false);
});

test('fetchPowerDaily: -999 -> null, fechas ISO, elevacion y URL', async () => {
  const dates = isoRange('2010-01-01', 3);
  const body = fakePowerJson(dates, { T2M_MAX: { 20100101: 28.1, 20100102: -999, 20100103: 29 } });
  const calls = [];
  const p = await fetchPowerDaily(14.8, -89.5, jsonFetch(body, calls));
  assert.deepEqual(p.dates, dates);
  assert.deepEqual(p.tmax, [28.1, null, 29]);
  assert.equal(p.elevation, 423);
  assert.deepEqual(p.pressure, [95, 95, 95]);
  assert.match(calls[0], /power\.larc\.nasa\.gov\/api\/temporal\/daily\/point/);
  assert.match(calls[0], /community=AG/);
  assert.match(calls[0], /start=20010101/); assert.match(calls[0], /end=20251231/);
  assert.match(calls[0], /parameters=T2M_MAX,T2M_MIN,T2MDEW,ALLSKY_SFC_SW_DWN,WS2M,PS/);
});

test('fetchPowerDaily: opciones start/end y error HTTP', async () => {
  const calls = [];
  await fetchPowerDaily(14.8, -89.5, jsonFetch(fakePowerJson(isoRange('2010-01-01', 1)), calls), { start: '20100101', end: '20100101' });
  assert.match(calls[0], /start=20100101/); assert.match(calls[0], /end=20100101/);
  await assert.rejects(fetchPowerDaily(14.8, -89.5, async () => ({ ok: false, status: 503 })), /503/);
});

test('fetchEra5Rain: parametros y nulls, error HTTP', async () => {
  const calls = [];
  const body = { daily: { time: ['2010-01-01', '2010-01-02'], precipitation_sum: [0, null] } };
  const r = await fetchEra5Rain(14.8, -89.5, jsonFetch(body, calls));
  assert.deepEqual(r.dates, ['2010-01-01', '2010-01-02']);
  assert.deepEqual(r.rain, [0, null]);
  assert.match(calls[0], /archive-api\.open-meteo\.com\/v1\/archive/);
  assert.match(calls[0], /models=era5/); assert.match(calls[0], /daily=precipitation_sum/);
  assert.match(calls[0], /timezone=America%2FGuatemala/);
  assert.match(calls[0], /start_date=2001-01-01/); assert.match(calls[0], /end_date=2025-12-31/);
  await assert.rejects(fetchEra5Rain(14.8, -89.5, async () => ({ ok: false, status: 429 })), /429/);
});

async function bundleFrom(dates, powerOver, rain) {
  const power = await fetchPowerDaily(14.8, -89.5, jsonFetch(fakePowerJson(dates, powerOver)));
  const era5 = await fetchEra5Rain(14.8, -89.5, jsonFetch({ daily: { time: dates, precipitation_sum: rain ?? dates.map(() => 1) } }));
  return buildBundle(power, era5, { lat: 14.8, lon: -89.5 });
}

test('buildBundle: campos, ERA5 y fuentes', async () => {
  const dates = isoRange('2010-01-01', 10);
  const b = await bundleFrom(dates);
  assert.equal(b.rainSource, 'ERA5'); assert.equal(b.fallback, false);
  assert.equal(b.elevation, 423); assert.equal(b.lat, 14.8); assert.equal(b.lon, -89.5);
  assert.deepEqual(b.invalidYears, []);
  assert.equal(b.dates.length, 10);
  for (const k of ['tmax', 'tmin', 'tdew', 'rs', 'u2', 'pressure', 'rain']) assert.equal(b[k].length, 10);
  assert.equal(b.sources.length, 2);
  assert.match(b.sources[0], /NASA POWER.*power\.larc\.nasa\.gov/);
  assert.match(b.sources[1], /ERA5.*open-meteo\.com/);
});

test('buildBundle: hueco de 2 dias se interpola linealmente', async () => {
  const dates = isoRange('2010-06-01', 10);
  const tmax = Object.fromEntries(dates.map((d, i) => [compact(d), 30 + i]));
  tmax[compact(dates[4])] = -999; tmax[compact(dates[5])] = -999;
  const b = await bundleFrom(dates, { T2M_MAX: tmax });
  assert.equal(b.tmax[4], 34); assert.equal(b.tmax[5], 35);
  assert.deepEqual(b.invalidYears, []);
});

test('buildBundle: hueco de 5 dias en junio 2010 marca 2010 invalido', async () => {
  const dates = isoRange('2010-01-01', 800);
  const rs = Object.fromEntries(dates.map((d) => [compact(d), 20]));
  for (const d of ['2010-06-10', '2010-06-11', '2010-06-12', '2010-06-13', '2010-06-14']) rs[compact(d)] = -999;
  const b = await bundleFrom(dates, { ALLSKY_SFC_SW_DWN: rs });
  assert.deepEqual(b.invalidYears, [2010]);
  assert.equal(b.rs[dates.indexOf('2010-06-12')], null);
});

test('buildBundle: un dia sin lluvia NO se interpola: queda null y su anio agricola es invalido', async () => {
  const dates = isoRange('2012-04-01', 10);
  const rain = dates.map(() => 2); rain[3] = null; rain[0] = null;
  const b = await bundleFrom(dates, {}, rain);
  assert.equal(b.rain[3], null); assert.equal(b.rain[0], null);
  assert.deepEqual(b.invalidYears, [2012]);
});

test('buildBundle: un solo dia de lluvia null en medio del anio invalida ese anio y los huecos de otras series <= 3 dias siguen interpolando', async () => {
  const dates = isoRange('2010-01-01', 800);
  const rain = dates.map(() => 1); rain[dates.indexOf('2010-07-15')] = null;
  const tmax = Object.fromEntries(dates.map((d, i) => [compact(d), 30 + (i % 2)]));
  tmax[compact('2011-02-10')] = -999; // otro anio agricola (2010), hueco de 1 dia: se interpola
  const b = await bundleFrom(dates, { T2M_MAX: tmax }, rain);
  assert.deepEqual(b.invalidYears, [2010]);
  assert.equal(b.rain[dates.indexOf('2010-07-15')], null);
  assert.notEqual(b.tmax[dates.indexOf('2011-02-10')], null);
});

test('buildBundle: objeto de lluvia con source IMERG fija rainSource, fuente y detalle', async () => {
  const dates = isoRange('2010-01-01', 5);
  const power = await fetchPowerDaily(14.8, -89.5, jsonFetch(fakePowerJson(dates)));
  const rain = { dates, rain: dates.map(() => 3), source: 'IMERG', sourceDetail: 'caja +-0.03 deg, 2010' };
  const b = buildBundle(power, rain, { lat: 14.8, lon: -89.5 });
  assert.equal(b.rainSource, 'IMERG');
  assert.equal(b.sources.length, 2);
  assert.match(b.sources[0], /NASA POWER.*power\.larc\.nasa\.gov/);
  assert.match(b.sources[1], /IMERG.*https:\/\/climateserv\.servirglobal\.net\//);
  assert.match(b.sources[1], /caja \+-0\.03 deg, 2010/);
  assert.deepEqual(b.rain, [3, 3, 3, 3, 3]);
});

test('buildBundle: CHIRPS tambien se anuncia; fuente de lluvia desconocida lanza error', async () => {
  const dates = isoRange('2010-01-01', 3);
  const power = await fetchPowerDaily(14.8, -89.5, jsonFetch(fakePowerJson(dates)));
  const b = buildBundle(power, { dates, rain: [1, 1, 1], source: 'CHIRPS' }, { lat: 14.8, lon: -89.5 });
  assert.equal(b.rainSource, 'CHIRPS'); assert.match(b.sources[1], /CHIRPS/);
  assert.throws(() => buildBundle(power, { dates, rain: [1, 1, 1], source: 'POWER' }, { lat: 14.8, lon: -89.5 }), /POWER|fuente de lluvia/i);
});

test('climateservRain: alinea con las fechas pedidas; lo que ClimateSERV no devolvio queda null', () => {
  const doc = { days: { '2010-01-01': 0, '2010-01-02': 4.5, '2010-01-04': null } };
  const r = climateservRain(doc, ['2010-01-01', '2010-01-02', '2010-01-03', '2010-01-04'], 'IMERG');
  assert.deepEqual(r.rain, [0, 4.5, null, null]);
  assert.equal(r.source, 'IMERG');
  assert.deepEqual(r.dates, ['2010-01-01', '2010-01-02', '2010-01-03', '2010-01-04']);
});

test('fetchPowerDaily: PRECTOTCORR opcional -> rainPower (no es parte del bundle del modelo)', async () => {
  const dates = isoRange('2010-01-01', 3);
  const calls = [];
  const body = fakePowerJson(dates, { PRECTOTCORR: { 20100101: 1.5, 20100102: -999, 20100103: 0 } });
  const p = await fetchPowerDaily(14.8, -89.5, jsonFetch(body, calls));
  assert.deepEqual(p.rainPower, [1.5, null, 0]);
  assert.match(calls[0], /PRECTOTCORR/);
  const q = await fetchPowerDaily(14.8, -89.5, jsonFetch(fakePowerJson(dates)));
  assert.equal(q.rainPower, undefined);
  const power = await fetchPowerDaily(14.8, -89.5, jsonFetch(body));
  const b = buildBundle(power, { dates, rain: [1, 1, 1] }, { lat: 14.8, lon: -89.5 });
  assert.equal('rainPower' in b, false);
});

test('buildBundle: fechas desalineadas se recortan a la interseccion', async () => {
  const dPower = isoRange('2010-01-01', 10); // 01..10 ene
  const dRain = isoRange('2010-01-04', 10);  // 04..13 ene
  const power = await fetchPowerDaily(14.8, -89.5, jsonFetch(fakePowerJson(dPower)));
  const era5 = await fetchEra5Rain(14.8, -89.5, jsonFetch(rainJson(dRain)));
  const b = buildBundle(power, era5, { lat: 14.8, lon: -89.5 });
  assert.deepEqual(b.dates, isoRange('2010-01-04', 7));
  assert.equal(b.tmax.length, 7); assert.equal(b.rain.length, 7);
});
