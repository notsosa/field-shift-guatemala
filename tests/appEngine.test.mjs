import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { isoToDay, dayToIso, diaDelAnio, et0PenmanMonteith, prepararClima, simularBalance, factorRendimiento, CATALOGO, SUELOS } from '../web/js/model/appEngine.js';

const fixture = JSON.parse(readFileSync(new URL('./fixtures/app_engine_dart.json', import.meta.url), 'utf8'));
const TOL = 1e-9;
const near = (a, b, what) => assert.ok(Math.abs(a - b) <= TOL, `${what}: ${a} vs ${b}`);

test('día del año y fechas: mismos valores que la app (prueba motor_test.dart)', () => {
  assert.equal(diaDelAnio(isoToDay('2026-01-01')), 1);
  assert.equal(diaDelAnio(isoToDay('2026-07-06')), 187);
  assert.equal(dayToIso(isoToDay('2024-02-29')), '2024-02-29');
});

test('ET0: ejemplo 18 de FAO-56 (Bruselas, 6 de julio) da 3,9 mm/día como en la prueba de la app', () => {
  const et0 = et0PenmanMonteith({ tmax: 21.5, tmin: 12.3, ea: 1.409, u2: 2.078, rs: 22.07, diaDelAnio: 187, latitud: 50.8, elevacion: 100 });
  assert.ok(Math.abs(et0 - 3.9) <= 0.05, String(et0));
});

test('catálogo de la app: parámetros iguales a los que imprime el Dart real', () => {
  for (const c of fixture.cases) {
    const j = CATALOGO[c.input.cultivo]; const d = c.dart.catalogo;
    assert.deepEqual(d.ciclos, j.ciclos);
    for (const k of ['kcInicial', 'kcMedio', 'kcFinal', 'raizMaxima', 'p', 'ky']) assert.equal(d[k], j[k], `${c.input.cultivo}.${k}`);
    assert.deepEqual(d.etapas, j.etapas);
  }
  assert.deepEqual(Object.values(SUELOS), [100, 150, 180]);
});

for (const c of fixture.cases) {
  test(`el port coincide con el Dart a 1e-9: ${c.input.id}`, () => {
    const clima = c.input.clima.map((j) => ({ dia: isoToDay(j.f), tmax: j.x, tmin: j.n, humedad: j.h, viento: j.v, radiacion: j.r, lluvia: j.l }));
    const hoy = isoToDay(c.input.hoy);
    const dias = prepararClima(clima, { latitud: c.input.latitud, elevacion: c.input.elevacion }, hoy);
    assert.equal(dias.length, c.dart.dias.length);
    dias.forEach((d, i) => {
      const e = c.dart.dias[i];
      assert.equal(dayToIso(d.dia), e.f); assert.equal(d.estimado, e.estimado);
      near(d.et0, e.et0, `et0 ${e.f}`); near(d.lluvia, e.lluvia, `lluvia ${e.f}`);
    });
    assert.ok(dias.some((d) => d.estimado), 'el caso incluye días completados con la regla de huecos');
    const riegos = new Map(Object.entries(c.input.riegos).map(([f, mm]) => [isoToDay(f), mm]));
    const estados = simularBalance({ dias, siembra: isoToDay(c.input.siembra), cultivo: CATALOGO[c.input.cultivo], ciclo: c.input.ciclo, aguaDisponible: c.input.aguaDisponible, riegos });
    assert.equal(estados.length, c.dart.estados.length);
    estados.forEach((s, i) => {
      const e = c.dart.estados[i];
      assert.equal(dayToIso(s.dia), e.f); assert.equal(s.etapa, e.etapa); assert.equal(s.estimado, e.estimado);
      for (const k of ['kc', 'etc', 'eta', 'ks', 'agotamiento', 'aguaTotal', 'aguaFacil', 'lluvia', 'riego', 'reserva']) near(s[k], e[k], `${k} ${e.f}`);
    });
    near(factorRendimiento(estados, CATALOGO[c.input.cultivo].ky), c.dart.factor, 'factor');
  });
}

test('los tres casos cubren estrés, cosecha, riego y huecos', () => {
  const all = fixture.cases.flatMap((c) => c.dart.estados);
  assert.ok(all.some((s) => s.ks < 1)); assert.ok(all.some((s) => s.etapa === 'cosechado')); assert.ok(all.some((s) => s.riego > 0));
  for (const e of ['inicial', 'desarrollo', 'media', 'finalCiclo']) assert.ok(all.some((s) => s.etapa === e), e);
});
