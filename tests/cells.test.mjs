import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sharedCells } from '../scripts/emulator/cells.mjs';

// Bundle con la temperatura ya corregida: cellElevation de la celda, elevation de la parcela y ΔT = -0.0065 x (parcela - celda).
const b = (cellElevation, siteElevation, t, rain, rs = [20, 21]) => {
  const deltaT = -0.0065 * (siteElevation - cellElevation);
  return {
    elevation: siteElevation, cellElevation, temperatureCorrection: { deltaT },
    tmax: [t + 8 + deltaT, t + 9 + deltaT], tmin: [t - 8 + deltaT, t - 7 + deltaT], tdew: [t - 10, t - 9], rs, u2: [1, 1],
    pressure: [90 + siteElevation / 1000, 90], rain,
  };
};

test('sharedCells: misma celda de temperatura aunque la parcela corrija distinto; entradas idénticas = además rs, u2 y lluvia', () => {
  const cells = sharedCells({
    a: b(762.46, 403, 25, [0, 5]),
    c: b(762.46, 403, 25, [0, 5]), // idéntico a "a"
    d: b(762.46, 933, 25, [1, 5], [19, 22]), // misma celda de POWER (otra parcela, otra lluvia y radiación)
    f: b(762.46, 459, 25, [0, 5]), // misma celda y mismas rs, u2, lluvia que "a" pero otra elevación de parcela
    e: b(1515.75, 1787, 18, [0, 5]), // otra celda
  });
  assert.deepEqual(cells.a, { weatherMates: ['c', 'd', 'f'], identicalMates: ['c', 'f'] });
  assert.deepEqual(cells.d, { weatherMates: ['a', 'c', 'f'], identicalMates: [] });
  assert.deepEqual(cells.e, { weatherMates: [], identicalMates: [] });
});

test('sharedCells: mismas temperaturas pero otra elevación de celda no es la misma celda; un bundle sin corrección falla', () => {
  const x = b(762.46, 403, 25, [0, 5]);
  const y = { ...b(800, 403, 25, [0, 5]) };
  assert.deepEqual(sharedCells({ x, y }).x.weatherMates, []);
  assert.throws(() => sharedCells({ x, z: { elevation: 400, tmax: [1], tmin: [0] } }), /cellElevation/);
});
