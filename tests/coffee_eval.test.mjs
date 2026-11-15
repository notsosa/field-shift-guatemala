import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { metrics, utilityOf } from '../scripts/coffee/eval_lib.mjs';
import { forward, standardize } from '../web/js/model/recommender.js';

const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-12, `${a} vs ${b}`);
// 4 casos: evitados 0, 2, 5, 10; la regla riega en los casos 1 y 3 (índices 0 y 2); sin riego hay 8, 9, 12, 20 días de estrés
const list = [
  { rule: 1, avoided: 0, stressNo: 8, stressYes: 8 }, { rule: 0, avoided: 2, stressNo: 9, stressYes: 7 },
  { rule: 1, avoided: 5, stressNo: 12, stressYes: 7 }, { rule: 0, avoided: 10, stressNo: 20, stressYes: 10 },
];
test('utilidad: regar = evitados − precio, no regar = 0', () => {
  assert.equal(utilityOf(1, list[2], 0), 2); assert.equal(utilityOf(1, list[2], 1), 4); assert.equal(utilityOf(0, list[2], 0), 0);
});
test('métricas a mano (prioridad 0, precio 3): una política que riega los casos 2 y 3 (índices 2 y 3)', () => {
  const m = metrics(list, [0, 0, 1, 1], 0);
  // utilidad: 0, 0, 2, 7 → media 2.25; regla: −3, 0, 2, 0 → media −0.25; oráculo: 0, 0, 2, 7 (evitados − 3 > 0 en 5 y 10) → 2.25
  near(m.meanUtility, 2.25); near(m.ruleMeanUtility, -0.25); near(m.oracleMeanUtility, 2.25); near(m.gainVsRule, 2.5); near(m.regretVsOracle, 0);
  assert.deepEqual([m.win, m.tie, m.loss], [2, 2, 0]); // diferencias con la regla: +3, 0, 0, +7
  assert.equal(m.irrigations, 2); assert.deepEqual(m.wasted, { count: 0, of: 2, rate: 0 }); assert.deepEqual(m.missed, { count: 0, of: 2, rate: 0 });
  near(m.stressDaysLeft, (8 + 9 + 7 + 10) / 4); near(m.stressDaysNoIrrigation, (8 + 9 + 12 + 20) / 4); assert.equal(m.departsFromRule, 2); // casos 0 y 3
});
test('métricas a mano: la regla en prioridad 0 desperdicia el riego del caso 0 y pierde el caso 3', () => {
  const m = metrics(list, list.map((s) => s.rule), 0);
  assert.deepEqual(m.wasted, { count: 1, of: 2, rate: 0.5 }); assert.deepEqual(m.missed, { count: 1, of: 2, rate: 0.5 });
  near(m.regretVsOracle, 2.5); assert.equal(m.departsFromRule, 0); assert.deepEqual([m.win, m.tie, m.loss], [0, 4, 0]);
  // prioridad 1 (precio 1): necesarios = evitados > 1 → casos 1, 2, 3
  const m1 = metrics(list, [1, 1, 1, 1], 1);
  assert.deepEqual(m1.wasted, { count: 1, of: 4, rate: 0.25 }); assert.deepEqual(m1.missed, { count: 0, of: 3, rate: 0 });
});

const art = JSON.parse(readFileSync(new URL('../web/data/coffee_eval.json', import.meta.url), 'utf8'));
const rec = JSON.parse(readFileSync(new URL('../web/data/coffee_recommender.json', import.meta.url), 'utf8'));
test('artefacto: el pase hacia adelante de JS y el de PyTorch coinciden (1e-5) y recomiendan igual', () => {
  for (const c of art.meta.crossCheckJsVsTorch) { assert.ok(c.maxAbsScoreDiff < 1e-5); assert.equal(c.sameRecommendation, c.rows); }
});
test('coffee_recommender.json: pesos exportados con la forma del embudo y salida finita', () => {
  assert.deepEqual(rec.layerSizes, [18, 64, 32, 16, 1]); assert.equal(rec.params.length, 18 * 64 + 64 + 64 * 32 + 32 + 32 * 16 + 16 + 16 + 1);
  const y = forward(rec.params, standardize(Array(18).fill(0), rec.mean, rec.std), rec.layerSizes);
  assert.ok(Number.isFinite(y));
});
test('artefacto: conteos y semillas del diseño', () => {
  assert.deepEqual(art.meta.design.seeds, [17, 29, 43]);
  assert.equal(art.meta.scenarios.test, 1620); assert.equal(art.meta.scenarios.reserved2022_2024, 810);
  for (const k of ['recommender', 'predictThenChooseMlp', 'predictThenChooseElm']) assert.equal(art.policies.perSeed[k].length, 3);
  assert.equal(art.policies.noSeed.rule.test.all.saveWater.n, 1620);
});
