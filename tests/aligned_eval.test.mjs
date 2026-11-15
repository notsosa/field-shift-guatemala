import test from 'node:test'; import assert from 'node:assert/strict';
import { summarizeSeeds, outcomeCounts, summarizeObjects } from '../scripts/compare/aligned_lib.mjs';
import { filterYears } from '../scripts/compare/loss_decision_core.mjs';

test('filterYears: deja solo los años pedidos (a mano: 2021-2024 x 2 casos -> 2022-2024 = 6)', () => {
  const rows = [2021, 2022, 2023, 2024].flatMap((year) => [{ year, lossDay: 30 }, { year, lossDay: 45 }]);
  const sub = filterYears(rows, [2022, 2023, 2024]);
  assert.equal(sub.length, 6);
  assert.deepEqual([...new Set(sub.map((r) => r.year))], [2022, 2023, 2024]);
  assert.equal(filterYears(rows, [2025]).length, 0); // 2025 no existe en los datos: no se inventa
});

test('summarizeSeeds: media, mínimo y máximo de tres semillas (a mano)', () => {
  // (0.6 + 0.9 + 0.3) / 3 = 0.6
  const s = summarizeSeeds([0.6, 0.9, 0.3]);
  assert.ok(Math.abs(s.mean - 0.6) < 1e-12); assert.equal(s.min, 0.3); assert.equal(s.max, 0.9); assert.equal(s.n, 3);
  assert.equal(summarizeSeeds([0.5, null, 0.7]).mean, null);
  assert.deepEqual(summarizeObjects([{ a: 1, b: 10 }, { a: 3, b: 20 }, { a: 5, b: 30 }], ['a', 'b']).b, { mean: 20, min: 10, max: 30, n: 3 });
});

test('outcomeCounts: resultados < 0.5 (estricto) y apartarse de la regla (a mano)', () => {
  const items = [
    { value: 0.49, action: 'maiz', ruleAction: 'maiz' }, // bajo, igual a la regla
    { value: 0.5, action: 'frijol', ruleAction: 'maiz' }, // no bajo (0.5 no es < 0.5), se aparta
    { value: 0, action: 'fallow', ruleAction: 'frijol' }, // bajo, se aparta
    { value: 1, action: 'maiz', ruleAction: 'maiz' },
  ];
  assert.deepEqual(outcomeCounts(items), { n: 4, below05: 2, departsFromRule: 2 });
});
