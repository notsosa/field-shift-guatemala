// Sistemas de la auditoría del asesor (Tarea 41): Kc y p por clase, calendario de los tres Kc, y que sin la opción el café es idéntico al de siempre. Cuentas a mano.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCrops } from '../web/js/model/crops.js';
import { simulateDays } from '../web/js/model/waterBalance.js';
import { buildPerennialPhase } from '../web/js/model/phenology.js';
import { SYSTEMS, systemKc, systemAdjust, systemFor, systemFlags, simulateCoffee, STATE_NAMES, STATE_NAMES_V3, coffeeDecisionState, coffeeDecisionStateV3, counterfactual, COFFEE_ID } from '../web/js/model/coffee.js';

const crops = loadCrops(JSON.parse(readFileSync(new URL('../web/data/crops.json', import.meta.url), 'utf8')));
const near = (a, b, tol = 1e-12) => assert.ok(Math.abs(a - b) < tol, `${a} vs ${b}`);
const TAW = 156; // franco, café: 1000 · 0.13 · 1.2

test('clases de la auditoría: Kc y p exactos de parametros_auditados.json', () => {
  assert.deepEqual(SYSTEMS.limpio.kc, [0.90, 0.95, 0.95]); assert.equal(SYSTEMS.limpio.p, 0.40);
  assert.deepEqual(SYSTEMS.malezas.kc, [1.05, 1.10, 1.10]); assert.equal(SYSTEMS.malezas.p, 0.40);
  assert.deepEqual(SYSTEMS.regulado.kc, [0.95, 1.05, 1.00]); assert.equal(SYSTEMS.regulado.p, 0.38);
  assert.deepEqual(SYSTEMS.denso.kc, [1.00, 1.20, 1.10]); assert.equal(SYSTEMS.denso.p, 0.35);
});

test('calendario del Kc: 60 d ini, 90 d lineal, 125 d media, 90 d lineal; el día 366 usa el Kc final', () => {
  const k = SYSTEMS.regulado.kc; // 0.95 / 1.05 / 1.00
  assert.equal(systemKc(k, 1), 0.95); assert.equal(systemKc(k, 60), 0.95);
  near(systemKc(k, 61), 0.95 + 0.10 / 90); // primer día de desarrollo
  near(systemKc(k, 105), 0.95 + 0.10 * 45 / 90); // mitad del desarrollo
  near(systemKc(k, 150), 1.05); // fin del desarrollo = Kc mid
  assert.equal(systemKc(k, 151), 1.05); assert.equal(systemKc(k, 275), 1.05);
  near(systemKc(k, 276), 1.05 - 0.05 / 90); // primer día de la etapa final
  near(systemKc(k, 320), 1.05 - 0.05 * 45 / 90);
  near(systemKc(k, 365), 1.00); near(systemKc(k, 366), 1.00);
  near(systemKc(SYSTEMS.malezas.kc, 200), 1.10); near(systemKc(SYSTEMS.denso.kc, 200), 1.20); near(systemKc(SYSTEMS.limpio.kc, 30), 0.90);
});

test('calendario: suma anual de Kc·ET0 con ET0 = 1 mm/día es la de las etapas (limpio: 60·0.90 + 90·(0.925) + 125·0.95 + 90·0.95)', () => {
  const dates = Array.from({ length: 365 }, (_, i) => new Date(Date.UTC(2025, 0, 1 + i)).toISOString().slice(0, 10));
  const a = systemAdjust(dates, 'limpio');
  const s = a.kcSeries.reduce((x, y) => x + y, 0);
  // desarrollo: Kc de 0.90 + 0.05·j/90, j = 1..90 -> media (0.90·90 + 0.05·(91/2))
  const expected = 60 * 0.90 + (90 * 0.90 + 0.05 * (90 * 91 / 2) / 90) + 125 * 0.95 + 90 * 0.95;
  near(s, expected, 1e-9);
  assert.equal(a.p, 0.40); assert.ok(a.reduce.every((v) => v === 0) && a.add.every((v) => v === 0));
});

test('un día del balance por sistema, a mano (franco, ET0 4 mm, Dr0 100 mm)', () => {
  // regulado, 1 de febrero (día 32, Kc 0.95), p 0.38: Ks = 56 / (0.62·156) = 56/96.72
  const reg = simulateCoffee({ dates: ['2020-02-01'], rain: [0], et0: [4], crops, texture: 'loam', system: 'regulado', drInit: 100 });
  near(reg.etc[0], 0.95 * 4); near(reg.ks[0], 56 / 96.72); near(reg.eta[0], (56 / 96.72) * 3.8); near(reg.kc[0], 0.95);
  // denso, 19 de julio (día 201, Kc mid 1.20), p 0.35: Ks = 56 / (0.65·156) = 56/101.4; ETc = 4.8
  const den = simulateCoffee({ dates: ['2020-07-19'], rain: [0], et0: [4], crops, texture: 'loam', system: 'denso', drInit: 100 });
  near(den.etc[0], 4.8); near(den.ks[0], 56 / 101.4); near(den.eta[0], (56 / 101.4) * 4.8);
  // malezas, mismo día: Kc 1.10, p 0.40: Ks = 56 / 93.6
  const mal = simulateCoffee({ dates: ['2020-07-19'], rain: [0], et0: [4], crops, texture: 'loam', system: 'malezas', drInit: 100 });
  near(mal.etc[0], 4.4); near(mal.ks[0], 56 / 93.6);
  // un solo Kc y una sola p: no hay término de banano aparte, la demanda es exactamente Kc·ET0 (no se cuenta dos veces)
  near(reg.etc[0], reg.kc[0] * 4);
  // sistemas con Dr bajo p·TAW: sin estrés
  const ok = simulateCoffee({ dates: ['2020-07-19'], rain: [0], et0: [4], crops, texture: 'loam', system: 'denso', drInit: 50 });
  assert.equal(ok.ks[0], 1);
});

test('sin la opción, el café es idéntico al de siempre (Kc 0.95 constante, p 0.40)', () => {
  const n = 120;
  const dates = Array.from({ length: n }, (_, i) => new Date(Date.UTC(2020, 5, 1 + i)).toISOString().slice(0, 10));
  const rain = dates.map((_, i) => (i % 7 === 0 ? 12 : 0)), et0 = dates.map((_, i) => 3 + (i % 5) * 0.3);
  const base = simulateDays({ rain, et0, phases: [buildPerennialPhase(crops.get(COFFEE_ID), n)], crops, texture: 'loam', slopeClass: 'flat', irrigation: 'none' });
  assert.deepEqual(simulateCoffee({ dates, rain, et0, crops, texture: 'loam' }), base);
  assert.deepEqual(simulateCoffee({ dates, rain, et0, crops, texture: 'loam', system: undefined }), base);
  assert.deepEqual(simulateCoffee({ dates, rain, et0, crops, texture: 'loam', system: null }), base);
  assert.ok(base.kc.every((k) => k === 0.95));
});

test('un sistema no se combina con la sombra de árboles', () => {
  assert.throws(() => simulateCoffee({ dates: ['2020-02-01'], rain: [0], et0: [4], crops, texture: 'loam', shade: 'trees', treeType: 'evergreen', system: 'regulado' }));
  assert.throws(() => systemAdjust(['2020-02-01'], 'banana'));
  assert.throws(() => coffeeDecisionStateV3({ system: 'regulado', shade: 'trees' }));
});

test('suelo y banano declarados -> sistema: con banano el suelo se ignora; sin banano y limpio = el café de siempre', () => {
  assert.equal(systemFor({ suelo: 'limpio', banano: 'ninguno' }), null);
  assert.equal(systemFor({}), null);
  assert.equal(systemFor({ suelo: 'malezas', banano: 'ninguno' }), 'malezas');
  for (const suelo of ['limpio', 'malezas']) { assert.equal(systemFor({ suelo, banano: 'regulado' }), 'regulado'); assert.equal(systemFor({ suelo, banano: 'denso' }), 'denso'); }
  assert.throws(() => systemFor({ suelo: 'mojado' })); assert.throws(() => systemFor({ banano: 'poco' }));
});

test('entradas de la red v3: las 16 de siempre más weeds, bananaRegulated y bananaDense', () => {
  assert.deepEqual(STATE_NAMES_V3, [...STATE_NAMES, 'weeds', 'bananaRegulated', 'bananaDense']);
  assert.deepEqual(systemFlags(null), [0, 0, 0]); assert.deepEqual(systemFlags('malezas'), [1, 0, 0]);
  assert.deepEqual(systemFlags('regulado'), [0, 1, 0]); assert.deepEqual(systemFlags('denso'), [0, 0, 1]);
});

test('estado de decisión v3: los primeros 16 valores son los de v1 y los tres últimos las marcas del sistema', () => {
  const n = 400;
  const dates = Array.from({ length: n }, (_, i) => new Date(Date.UTC(2019, 9, 1 + i)).toISOString().slice(0, 10));
  const rain = dates.map((_, i) => (i % 6 === 0 ? 9 : 0)), et0 = dates.map(() => 3.5);
  const tmax = dates.map(() => 27), tmin = dates.map(() => 15);
  const soil = { thetaFC: 0.30, thetaWP: 0.17 };
  const crop = crops.get(COFFEE_ID);
  const t = dates.indexOf('2020-06-15');
  const args = { dates, rain, et0, tmax, tmin, t, year: 2019, floweringIdx: dates.indexOf('2020-05-09'), soil, crop, elevation: 1200, shade: 'none', treeType: 'evergreen' };
  const v1 = coffeeDecisionState(args);
  const v3 = coffeeDecisionStateV3({ ...args, system: 'regulado' });
  assert.deepEqual(v3.state.slice(0, 16), v1.state); assert.deepEqual(v3.state.slice(16), [0, 1, 0]);
  assert.deepEqual(coffeeDecisionStateV3(args).state.slice(16), [0, 0, 0]);
});

test('contrafactual con sistema: corre los 30 días y el riego no empeora el estrés', () => {
  const n = 120;
  const dates = Array.from({ length: n }, (_, i) => new Date(Date.UTC(2020, 1, 1 + i)).toISOString().slice(0, 10));
  const rain = dates.map(() => 0), et0 = dates.map(() => 4);
  const sim = simulateCoffee({ dates, rain, et0, crops, texture: 'loam', system: 'denso' });
  const cf = counterfactual({ dates, rain, et0, crops, texture: 'loam', shade: 'none', treeType: 'evergreen', sim, t: 40, system: 'denso' });
  assert.ok(cf.stressYes <= cf.stressNo); assert.ok(cf.stressNo >= 0 && cf.stressNo <= 30);
});
