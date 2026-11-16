// Tarea 41: los cuatro sistemas de la auditoría en nuestro simulador (web/data/banana_audit_check_v3.json): calendario, signo, orden y la comparación con el café con malezas.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const load = (f) => JSON.parse(readFileSync(new URL(`../${f}`, import.meta.url)));
const o = load('web/data/banana_audit_check_v3.json');
const near = (a, b, tol = 0.011) => assert.ok(Math.abs(a - b) <= tol, `${a} vs ${b}`);

test('v3: el calendario de los tres Kc reproduce las cuatro ETc anuales de la auditoría (con su ET0)', () => {
  for (const id of ['limpio', 'regulado', 'malezas', 'denso']) near(o.calendar_check[id].diff_mm, 0, 0.011);
  near(o.run_C_v3.limpio.demand_mm, 1404.76); near(o.run_C_v3.regulado.demand_mm, 1525.49); near(o.run_C_v3.malezas.demand_mm, 1630.07); near(o.run_C_v3.denso.demand_mm, 1699.12);
});

test('v3: signo y orden iguales a la auditoría, magnitud dentro de las tolerancias fijadas', () => {
  const c = o.comparison;
  assert.equal(c.sign_ok, true); assert.equal(c.order_ok, true);
  assert.equal(c.regulated_close, true); assert.equal(c.dense_close, true);
  const r = o.run_C_v3;
  assert.ok(r.limpio.deficit_mm < r.regulado.deficit_mm && r.regulado.deficit_mm < r.malezas.deficit_mm && r.malezas.deficit_mm < r.denso.deficit_mm);
});

test('v3: el banano regulado con mulch tiene menos déficit que el café al sol con malezas, como en la auditoría', () => {
  const c = o.comparison;
  assert.equal(c.regulated_less_deficit_than_weedy_reproduces, true);
  assert.ok(c.differences.regulated_minus_weedy.deficit_mm < 0);
  assert.equal(c.audit_era5_differences.regulated_minus_weedy_deficit_mm, -87.16);
  assert.equal(c.regulated_vs_weedy_inside_audit_range, true);
});

test('v3: las clases y su fuente están en el artefacto', () => {
  assert.deepEqual(o.meta.systems.regulado.kc_ini_mid_end, [0.95, 1.05, 1.0]); assert.equal(o.meta.systems.denso.p, 0.35);
  assert.match(o.meta.systems_source, /parametros_auditados/);
  assert.equal(o.meta.task, 41);
});
