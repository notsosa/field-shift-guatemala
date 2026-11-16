import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const ev = JSON.parse(readFileSync(new URL('../web/data/app_eval.json', import.meta.url), 'utf8'));
const MODELS = ['mlp_s17', 'mlp_s29', 'mlp_s43', 'elm_s17', 'elm_s29', 'elm_s43', 'refApp', 'refDry'];

test('app_eval.json: los conteos de las particiones cuadran y no hay fuga entre años', () => {
  const c = ev.counts;
  assert.equal(c.trainUsed, 150000);
  assert.ok(c.trainAvailable > c.trainUsed);
  assert.equal(c.total, c.trainAvailable + c.validation + c.test + c.unused2025);
  for (const m of MODELS) {
    assert.equal(ev.metrics[m].test.factorFinal.n, c.test);
    assert.equal(ev.metrics[m].reserved2022_2024.factorFinal.n, c.reserved2022_2024);
    assert.equal(ev.metrics[m].pilots.factorFinal.n, c.pilotsTest);
  }
  assert.deepEqual(ev.split.test, 'years 2019-2024');
});

test('app_eval.json: la clase de estrés es coherente (conteos, precisión, recall y F1)', () => {
  for (const m of MODELS) for (const s of ['test', 'reserved2022_2024', 'pilots']) for (const t of ['estres7', 'estres14']) {
    const x = ev.metrics[m][s][t];
    assert.equal(x.tp + x.fp + x.fn + x.tn, x.n);
    assert.equal(x.tp + x.fn, x.positives);
    if (x.precision != null && x.recall != null && x.precision + x.recall > 0) assert.ok(Math.abs(x.f1 - (2 * x.precision * x.recall) / (x.precision + x.recall)) < 1e-12);
  }
});

test('app_eval.json: el desglose por fracción y por cultivo suma el total de la prueba', () => {
  for (const m of MODELS) {
    const byF = Object.values(ev.breakdownTest[m].byFraction).reduce((a, b) => a + b.factorFinal.n, 0);
    const byC = Object.values(ev.breakdownTest[m].byCrop).reduce((a, b) => a + b.factorFinal.n, 0);
    assert.equal(byF, ev.counts.test); assert.equal(byC, ev.counts.test);
  }
});

test('app_eval.json: los veredictos cuentan semillas de 0 a 3 y salen de las métricas', () => {
  for (const s of ['test', 'reserved2022_2024', 'pilots']) for (const t of ev.targets) for (const [k, v] of Object.entries(ev.verdicts[s][t])) {
    assert.ok(v.maeBeatsInSeeds >= 0 && v.maeBeatsInSeeds <= 3, k);
    const fam = k.split('_vs_')[0], ref = k.split('_vs_')[1];
    const wins = [17, 29, 43].filter((sd) => ev.metrics[`${fam}_s${sd}`][s][t].mae < ev.metrics[ref][s][t].mae).length;
    assert.equal(v.maeBeatsInSeeds, wins);
  }
});
