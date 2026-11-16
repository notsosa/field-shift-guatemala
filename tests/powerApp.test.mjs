import test from 'node:test';
import assert from 'node:assert/strict';
import { powerUrl, interpret } from '../scripts/app/fetch_power_app.mjs';

test('la petición usa los mismos parámetros que la app (clima.dart)', () => {
  const u = new URL(powerUrl(14.8, -89.54));
  assert.equal(u.hostname, 'power.larc.nasa.gov');
  assert.equal(u.pathname, '/api/temporal/daily/point');
  assert.equal(u.searchParams.get('parameters'), 'T2M_MAX,T2M_MIN,RH2M,WS2M,ALLSKY_SFC_SW_DWN,PRECTOTCORR');
  assert.equal(u.searchParams.get('community'), 'AG');
  assert.equal(u.searchParams.get('latitude'), '14.8000');
  assert.equal(u.searchParams.get('longitude'), '-89.5400');
  assert.equal(u.searchParams.get('time-standard'), 'LST');
  assert.equal(u.searchParams.get('format'), 'JSON');
});

test('interpret convierte -999 en nulo y toma la elevación de la celda', () => {
  const day = (v) => ({ 20240101: v, 20240102: v + 1 });
  const json = { geometry: { coordinates: [-89.5, 14.8, 762.46] }, properties: { parameter: {
    T2M_MAX: day(30), T2M_MIN: { 20240101: 20, 20240102: -999 }, RH2M: day(60), WS2M: day(2), ALLSKY_SFC_SW_DWN: day(20), PRECTOTCORR: { 20240101: 0, 20240102: -999 } } } };
  const d = interpret(json);
  assert.deepEqual(d.dates, ['2024-01-01', '2024-01-02']);
  assert.deepEqual(d.tmin, [20, null]);
  assert.deepEqual(d.lluvia, [0, null]);
  assert.equal(d.elevation, 762.46);
});
