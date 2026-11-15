import { test } from 'node:test';
import assert from 'node:assert/strict';
import { sharedCells } from '../scripts/emulator/cells.mjs';

const b = (elevation, t, rain, rs = [20, 21]) => ({
  elevation, tmax: [t + 8, t + 9], tmin: [t - 8, t - 7], tdew: [t - 10, t - 9], rs, u2: [1, 1], pressure: [90, 90], rain,
});

test('sharedCells: misma celda de temperatura (elevación + tmax/tmin/tdew) y entradas idénticas (además rs, u2, presión y lluvia)', () => {
  const cells = sharedCells({
    a: b(762.46, 25, [0, 5]),
    c: b(762.46, 25, [0, 5]), // idéntico a "a"
    d: b(762.46, 25, [1, 5], [19, 22]), // misma celda de temperatura, otra lluvia y radiación
    e: b(1515.75, 18, [0, 5]), // otra celda
  });
  assert.deepEqual(cells.a, { weatherMates: ['c', 'd'], identicalMates: ['c'] });
  assert.deepEqual(cells.d, { weatherMates: ['a', 'c'], identicalMates: [] });
  assert.deepEqual(cells.e, { weatherMates: [], identicalMates: [] });
});
