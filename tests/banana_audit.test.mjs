// Tarea 40: el banano de nuestro simulador frente a la auditoría del asesor (Chiquimula 2025). Fija las cifras del artefacto web/data/banana_audit_check.json y el signo y el orden.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const load = (f) => JSON.parse(readFileSync(new URL(`../${f}`, import.meta.url)));
const out = load('web/data/banana_audit_check.json');
const ref = load('scripts/coffee/banana_audit_reference.json');
const near = (a, b, tol = 0.011) => assert.ok(Math.abs(a - b) <= tol, `${a} vs ${b}`);

test('banano y auditoría: las cifras de la auditoría copiadas coinciden con las del README del asesor (ERA5, 2025)', () => {
  const e = ref.audit.era5;
  near(e.cafe_solo_limpio.ETc_mm, 1404.76); near(e.cafe_banano_regulado.ETc_mm, 1525.49); near(e.cafe_banano_denso.ETc_mm, 1699.12); near(e.cafe_solo_malezas.ETc_mm, 1630.07);
  near(e.cafe_solo_limpio.deficit_mm, 648.26); near(e.cafe_banano_regulado.deficit_mm, 744.62);
  assert.equal(e.cafe_solo_limpio.dias_Ks_lt_095, 249); assert.equal(e.cafe_banano_regulado.dias_Ks_lt_095, 264);
  assert.equal(ref.dates.length, 365);
});

test('banano y auditoría: signo y orden iguales a los de la auditoría en las tres corridas', () => {
  for (const k of ['A', 'B', 'C']) {
    const c = out.comparison[k];
    assert.equal(c.sign_ok, true, `signo ${k}`);
    assert.equal(c.order_ok, true, `orden ${k}`);
    const r = out[`run_${k}`];
    assert.ok(r.alone.deficit_mm < r.banana015.deficit_mm && r.banana015.deficit_mm < r.banana030.deficit_mm, k);
    assert.ok(r.alone.demand_mm < r.banana015.demand_mm && r.banana015.demand_mm < r.banana030.demand_mm, k);
    assert.ok(r.alone.days_ks_lt_095 < r.banana015.days_ks_lt_095 && r.banana015.days_ks_lt_095 < r.banana030.days_ks_lt_095, k);
  }
});

test('banano y auditoría: cifras fijadas de la corrida B (suelo, escorrentía y reserva de la auditoría) y de la corrida C (entradas congeladas)', () => {
  const B = out.run_B, C = out.run_C;
  near(B.alone.deficit_mm, 749.39); near(B.banana015.deficit_mm, 769.81); near(B.banana030.deficit_mm, 840.41);
  assert.equal(B.alone.days_ks_lt_095, 264); assert.equal(B.banana015.days_ks_lt_095, 269); assert.equal(B.banana030.days_ks_lt_095, 276);
  near(C.alone.demand_mm, 1426.96); near(C.banana015.deficit_mm - C.alone.deficit_mm, 18.15); near(C.banana030.deficit_mm - C.alone.deficit_mm, 84.9);
  assert.equal(out.context.soil.ours_run_B_C.taw_mm, 130.7);
  assert.equal(out.context.runB_runoff_check_mm.run_B, 0);
  assert.equal(out.context.our_snapshot.rain_2025_mm, 1020.5);
});

test('banano y auditoría: veredicto de magnitud (cobertura 0.15 no cercana, 0.30 cercana en el intervalo ancho) y cobertura que reproduce el aumento de ETc', () => {
  assert.equal(out.comparison.B.cover015_magnitude_close, false);
  assert.equal(out.comparison.C.cover015_magnitude_close, false);
  assert.equal(out.comparison.B.cover030_magnitude_close, true);
  assert.equal(out.comparison.B.cover030_inside_strict_era5, false);
  const f = out.cover_that_reproduces_audit_etc_increase;
  near(f.run_C_audit_daily_inputs.formula_as_in_app.regulated, 0.2803, 0.0005); near(f.run_C_audit_daily_inputs.formula_as_in_app.dense, 0.5541, 0.0005);
  near(f.run_B_our_weather_audit_soil.formula_as_in_app.regulated, 0.2732, 0.0005); near(f.run_B_our_weather_audit_soil.formula_as_in_app.dense, 0.5411, 0.0005);
  assert.ok(f.at_derived_cover.run_C.regulated.deficit_diff_mm > 0 && f.at_derived_cover.run_C.dense.deficit_diff_mm > f.at_derived_cover.run_C.regulated.deficit_diff_mm);
});
