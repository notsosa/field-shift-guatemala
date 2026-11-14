import test from 'node:test'; import assert from 'node:assert/strict';
import { et0PenmanMonteith, extraterrestrialRadiation, netLongwave } from '../web/js/model/et0.js';
const ex18 = { tmax: 21.5, tmin: 12.3, ea: 1.409, rs: 22.07, u2: 2.078, elevation: 100, latDeg: 50.8, doy: 187 };
test('Ra FAO-56 ej.18', () => assert.ok(Math.abs(extraterrestrialRadiation(50.8, 187) - 41.09) < 0.1));
test('Rnl FAO-56 ej.18', () => assert.ok(Math.abs(netLongwave({ tmax: 21.5, tmin: 12.3, ea: 1.409, rs: 22.07, rso: 30.90 }) - 3.71) < 0.05));
test('ET0 FAO-56 ej.18 = 3.9 mm/d', () => assert.ok(Math.abs(et0PenmanMonteith(ex18) - 3.9) < 0.1));
test('ET0 nunca negativa', () => assert.ok(et0PenmanMonteith({ ...ex18, rs: 0, tmax: 5, tmin: 4 }) >= 0));
