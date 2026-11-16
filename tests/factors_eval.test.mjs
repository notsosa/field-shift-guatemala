// Tarea 36: el artefacto factors_eval.json es coherente con sus fuentes y con las reglas fijadas de antemano.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const load = (f) => JSON.parse(readFileSync(new URL(`../web/data/${f}`, import.meta.url)));
const ev = load('factors_eval.json');

test('regla de reentrenar: menos del 1 % de sitios-anio cambian en mas de 0.01 -> no se reentrena', () => {
  assert.equal(ev.heat.total.siteYears, ev.heat.totalByCalendar.primera.siteYears + ev.heat.totalByCalendar.postrera.siteYears);
  assert.equal(ev.heat.retrainNeeded, ev.heat.total.shareChangeOver001 >= 0.01);
  assert.equal(ev.retrained.anything, ev.heat.retrainNeeded);
  assert.equal(ev.heat.byPoint.length, 20);
  assert.equal(ev.heat.total.hotDays, 0);
});

test('eventos reales: la corrida sin calor es la de real_events_check.json', () => {
  const base = load('real_events_check.json').summary.ERA5.all;
  assert.deepEqual(ev.realEvents.waterOnly.all.events, base.events);
  assert.equal(ev.realEvents.waterOnly.all.aucVsNoEventYears.auc, base.aucVsNoEventYears.auc);
});

test('perdida del maiz: canResow falso deja solo el campo; la fertilidad no cambia la eleccion', () => {
  for (const set of ['years2019_2024', 'reserved2022_2024']) {
    const d = ev.cropLoss.decision[set];
    for (const p of ['typical', 'cautious']) {
      assert.equal(d.canResowFalse[p].chosenMean.mean, 0);
      assert.equal(Object.keys(d.canResowFalse[p].actionsBySeed[17]).join(), 'fallow');
      assert.ok(d.canResowTrue[p].chosenMean.mean > 0.9);
      assert.ok(d.fertility_poor[p].chosenMean.mean < d.canResowTrue[p].chosenMean.mean);
      assert.ok(Math.abs(d.fertility_poor[p].chosenMean.mean - 0.4 * d.canResowTrue[p].chosenMean.mean) < 0.02);
    }
    for (const [name, byP] of Object.entries(ev.cropLoss.sameChoiceAsNotStated[set])) {
      for (const counts of Object.values(byP)) assert.deepEqual(counts, [d.n, d.n, d.n], name);
    }
  }
});

test('cafe: la regla del aviso solo agrega riegos y coincide con coffee_eval.json en las politicas sin aviso', () => {
  const c = ev.coffee.all2019_2024;
  const e = load('coffee_eval.json').policies;
  assert.equal(c.scenarios, 1620);
  assert.equal(c.policies.rule.saveWater.irrigations, e.noSeed.rule.test.all.saveWater.irrigations);
  assert.ok(Math.abs(c.policies.ptc.saveWater.utilityUnderSaveWater - e.perSeed.predictThenChooseMlp[1].test.all.saveWater.meanUtility) < 1e-3);
  assert.equal(c.noticeRuleChangesPtcDecision.scenarios, c.noticeRuleChangesPtcDecision.ofWhichAddedIrrigation);
  assert.equal(c.policies.rule.saveWaterWithNoticeRule.irrigations, c.policies.rule.saveWater.irrigations); // la regla FAO-56 no usa la prioridad
  assert.ok(c.policies.ptc.saveWaterWithNoticeRule.irrigations > c.policies.ptc.saveWater.irrigations);
});

test('factorTable: calor sin numero para frijol y cafe; plagas sin numero', () => {
  const by = Object.fromEntries(ev.factorTable.map((f) => [f.factor, f]));
  assert.equal(by['Heat, beans, coffee and the other crops'].publishedNumber, false);
  assert.equal(by.Pests.publishedNumber, false);
  assert.equal(by.Money.numbers.maizeQ_per_qq_2023, 224.53);
  assert.equal(by.Money.numbers.beanQ_per_qq_2023, 639.28);
});
