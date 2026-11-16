import test from 'node:test';
import assert from 'node:assert/strict';
import { isoToDay, et0DeDia, CATALOGO } from '../web/js/model/appEngine.js';
import { appInputs, withEt0, windowStart, truthFrom, APP_INPUT_NAMES, N_INPUTS } from '../web/js/model/appInputs.js';

const col = (x, name) => x[APP_INPUT_NAMES.indexOf(name)];
const close = (a, b, what, tol = 1e-9) => assert.ok(Math.abs(a - b) <= tol, `${what}: ${a} vs ${b}`);

// Serie constante de 400 días desde 2020-01-01, con la lluvia diaria dada.
function constantSeries(lluvia, first = isoToDay('2020-01-01'), n = 400) {
  const f = (v) => Array.from({ length: n }, () => v);
  return { first, tmax: f(30), tmin: f(20), humedad: f(60), viento: f(2), radiacion: f(20), lluvia: f(lluvia) };
}
const FARM = { lat: 14.8, lon: -89.54, cellElevation: 762.46 };
// ET0 del día `d` con el clima constante (cambia con el día del año por la radiación extraterrestre).
const e = (d) => et0DeDia({ dia: d, tmax: 30, tmin: 20, humedad: 60, viento: 2, radiacion: 20 }, 14.8, 762.46);
const esum = (d0, d1) => { let s = 0; for (let d = d0; d <= d1; d++) s += e(d); return s; };

test('ventana de clima de la app: desde la siembra, mínimo 60 y máximo 240 días atrás', () => {
  const hoy = 1000;
  assert.equal(windowStart(hoy - 100, hoy), hoy - 100); // siembra más antigua que 60 días: desde la siembra
  assert.equal(windowStart(hoy - 30, hoy), hoy - 60); // siembra reciente: 60 días
  assert.equal(windowStart(hoy - 300, hoy), hoy - 240); // tope de 240 días
});

test('entradas calculadas a mano con lluvia fuerte (maíz 120 d, suelo franco, 80 días después de la siembra)', () => {
  const siembra = isoToDay('2020-05-01');
  const hoy = siembra + 80;
  const r = appInputs(constantSeries(30), FARM, { crop: 'maiz', cycle: 120, soil: 'franco', siembra }, hoy);
  const x = r.x;
  assert.equal(x.length, N_INPUTS);
  assert.equal(N_INPUTS, 40);
  assert.equal(col(x, 'lat'), 14.8); assert.equal(col(x, 'lon'), -89.54); assert.equal(col(x, 'cellElevation'), 762.46);
  // 2020 es bisiesto: 1 de mayo = día 122; 80 días después = día 202.
  close(col(x, 'sowSin'), Math.sin((2 * Math.PI * 122) / 365), 'sowSin'); close(col(x, 'sowCos'), Math.cos((2 * Math.PI * 122) / 365), 'sowCos');
  close(col(x, 'todaySin'), Math.sin((2 * Math.PI * 202) / 365), 'todaySin'); close(col(x, 'todayCos'), Math.cos((2 * Math.PI * 202) / 365), 'todayCos');
  assert.deepEqual([col(x, 'crop_maiz'), col(x, 'crop_frijol'), col(x, 'crop_tomate')], [1, 0, 0]);
  assert.equal(col(x, 'cycleDays'), 120); close(col(x, 'fractionElapsed'), 80 / 120, 'frac'); assert.equal(col(x, 'daysToHarvest'), 40); assert.equal(col(x, 'soilAvailableWater'), 150);
  assert.deepEqual([col(x, 'kcMid'), col(x, 'rootDepth'), col(x, 'p'), col(x, 'ky')], [1.2, 1.0, 0.55, 1.25]);
  // Lluvia de 30 mm cada día: el suelo está lleno (agotamiento 0), sin estrés, factor 1.
  assert.equal(col(x, 'reserve'), 1); assert.equal(col(x, 'depletionOverTaw'), 0); assert.equal(col(x, 'ks'), 1);
  // t = 80: maíz 120 d tiene f1 = 24, f2 = 66, f3 = 114, así que está en etapa media.
  assert.deepEqual([col(x, 'stage_inicial'), col(x, 'stage_desarrollo'), col(x, 'stage_media'), col(x, 'stage_finalCiclo')], [0, 0, 1, 0]);
  close(col(x, 'factorSoFar'), 1, 'factor'); assert.equal(col(x, 'stressDays7'), 0); assert.equal(col(x, 'stressDaysSinceSowing'), 0);
  // Sumas: 7, 14 y 28 días de 30 mm; desde la siembra son 81 días (t = 0..80).
  assert.equal(col(x, 'rain7'), 210); assert.equal(col(x, 'rain14'), 420); assert.equal(col(x, 'rain28'), 840); assert.equal(col(x, 'rainSinceSowing'), 30 * 81);
  close(col(x, 'et0Sum7'), esum(hoy - 6, hoy), 'et0 7'); close(col(x, 'et0Sum14'), esum(hoy - 13, hoy), 'et0 14'); close(col(x, 'et0Sum28'), esum(hoy - 27, hoy), 'et0 28'); close(col(x, 'et0SumSinceSowing'), esum(siembra, hoy), 'et0 siembra');
  assert.equal(col(x, 'longestDrySpell28'), 0);
  assert.equal(col(x, 'tmaxMean14'), 30); assert.equal(col(x, 'tminMean14'), 20);
  close(col(x, 'cropNeed7'), 1.2 * esum(hoy - 6, hoy), 'necesidad 7 d'); // Kc medio 1.2 los 7 días
  // Referencias: la app hoy muestra factor 1 y 0 días de estrés; con la lluvia ya acumulada y sin lluvia adelante, el suelo lleno aguanta 7 días.
  assert.deepEqual(r.refApp, [1, 0, 0]);
});

test('sin lluvia: racha seca de 28 días, estrés y el adelanto en seco no mejora lo que la app muestra', () => {
  const siembra = isoToDay('2020-05-01');
  const r = appInputs(constantSeries(0), FARM, { crop: 'frijol', cycle: 80, soil: 'arenoso', siembra }, siembra + 40);
  assert.equal(col(r.x, 'longestDrySpell28'), 28);
  assert.equal(col(r.x, 'rain28'), 0);
  assert.ok(col(r.x, 'stressDaysSinceSowing') > 0);
  assert.ok(r.refDry[0] <= r.refApp[0] + 1e-12, 'en seco el factor final no puede ser mayor que el de hoy');
  assert.ok(r.refDry[1] >= 0 && r.refDry[1] <= 7 && r.refDry[2] >= r.refDry[1] && r.refDry[2] <= 14);
});

test('la referencia de lo que muestra la app: estrés 14 d es el doble del de 7 con tope 14', () => {
  const siembra = isoToDay('2020-05-01');
  const r = appInputs(constantSeries(0), FARM, { crop: 'tomate', cycle: 120, soil: 'arenoso', siembra }, siembra + 60);
  assert.equal(r.refApp[2], Math.min(2 * r.refApp[1], 14));
  assert.equal(r.refApp[1], col(r.x, 'stressDays7'));
});

function randomSeries(seed, n = 700) {
  let s = seed >>> 0; const rnd = () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
  const col2 = (g) => Array.from({ length: n }, g);
  return { first: isoToDay('2019-03-01'), tmax: col2(() => 28 + 6 * rnd()), tmin: col2(() => 16 + 5 * rnd()), humedad: col2(() => 40 + 40 * rnd()), viento: col2(() => 1 + 3 * rnd()),
    radiacion: col2(() => 12 + 10 * rnd()), lluvia: col2(() => (rnd() < 0.4 ? 20 * rnd() : 0)) };
}

test('las entradas no cambian si se altera el clima posterior a hoy o el de más de 240 días atrás', () => {
  const plan = { crop: 'maiz', cycle: 120, soil: 'franco', siembra: isoToDay('2020-05-11') };
  const hoy = plan.siembra + 60;
  const base = randomSeries(7);
  const mutate = (series, fromDay, toDay) => {
    const m = { ...series, tmax: series.tmax.slice(), tmin: series.tmin.slice(), humedad: series.humedad.slice(), viento: series.viento.slice(), radiacion: series.radiacion.slice(), lluvia: series.lluvia.slice() };
    for (let d = fromDay; d <= toDay; d++) { const i = d - series.first; if (i < 0 || i >= m.tmax.length) continue; m.tmax[i] += 9; m.tmin[i] -= 3; m.humedad[i] = 99; m.viento[i] += 5; m.radiacion[i] += 7; m.lluvia[i] += 300; }
    return m;
  };
  for (const withCache of [false, true]) {
    const prep = (s) => (withCache ? withEt0(s, FARM.lat, FARM.cellElevation, et0DeDia) : s);
    const ref = appInputs(prep(base), FARM, plan, hoy);
    const future = appInputs(prep(mutate(base, hoy + 1, base.first + 10000)), FARM, plan, hoy);
    const past = appInputs(prep(mutate(base, base.first - 10, hoy - 241)), FARM, plan, hoy);
    // Con la siembra a 60 días de hoy la ventana arranca en hoy-60: todo lo anterior a eso tampoco entra.
    const beforeWindow = appInputs(prep(mutate(base, base.first - 10, hoy - 61)), FARM, plan, hoy);
    for (const alt of [future, past, beforeWindow]) {
      assert.deepEqual(alt.x, ref.x); assert.deepEqual(alt.refApp, ref.refApp); assert.deepEqual(alt.refDry, ref.refDry);
    }
    // Y cambiar un día dentro de la ventana sí cambia las entradas (la prueba no es vacía).
    const inside = appInputs(prep(mutate(base, hoy - 3, hoy - 3)), FARM, plan, hoy);
    assert.notDeepEqual(inside.x, ref.x);
    const today = appInputs(prep(mutate(base, hoy, hoy)), FARM, plan, hoy);
    assert.notDeepEqual(today.x, ref.x);
  }
});

test('con la siembra a más de 240 días la ventana se corta en 240 días atrás', () => {
  const plan = { crop: 'tomate', cycle: 145, soil: 'franco', siembra: isoToDay('2019-04-01') };
  const hoy = plan.siembra + 300;
  const base = randomSeries(3, 800);
  const m = { ...base, lluvia: base.lluvia.slice() };
  for (let d = base.first; d <= hoy - 241; d++) m.lluvia[d - base.first] += 50;
  assert.deepEqual(appInputs(m, FARM, plan, hoy).x, appInputs(base, FARM, plan, hoy).x);
});

test('verdad: factor hasta el último día del ciclo y días con estrés después de hoy (a mano)', () => {
  // Estados sintéticos: 10 días de ciclo, ETc = 1 cada día; ETa = 1 los días 0-4 y 0.5 los días 5-9; Ks < 1 desde el día 5. Día 10 es cosechado (ETa 0).
  const mk = (i) => ({ dia: 100 + i, etapa: i === 10 ? 'cosechado' : 'media', etc: 1, eta: i < 5 ? 1 : i === 10 ? 0 : 0.5, ks: i < 5 ? 1 : 0.5 });
  const estados = Array.from({ length: 11 }, (_, i) => mk(i));
  const plan = { siembra: 100, cycle: 10 };
  const ky = CATALOGO.maiz.ky;
  const [fin, s7, s14] = truthFrom(estados, plan, CATALOGO.maiz, 102);
  // ETa/ETc = (5 + 2.5) / 10 = 0.75 sobre los 10 días del ciclo; el día 10 (cosecha) no cuenta.
  close(fin, 1 - ky * 0.25, 'factorFinal');
  assert.equal(s7, 5); // días 103..109: Ks<1 en 105..109
  assert.equal(s14, 5);
});
