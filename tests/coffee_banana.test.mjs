// Banano como sombra del café (Tarea 38, SUPUESTO PROVISIONAL): cuentas a mano del ajuste y de un día del balance.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCrops } from '../web/js/model/crops.js';
import { plotAdjust, simulateCoffee, bananaKs, bananaUseMm, BANANA, STATE_NAMES, STATE_NAMES_V2, coffeeDecisionStateV2 } from '../web/js/model/coffee.js';

const crops = loadCrops(JSON.parse(readFileSync(new URL('../web/data/crops.json', import.meta.url), 'utf8')));
const near = (a, b, tol = 1e-12) => assert.ok(Math.abs(a - b) < tol, `${a} vs ${b}`);
const TAW = 156; // loam, café: 1000 · 0.13 · 1.2

test('constantes del banano: Kc 1.10 y p 0.35 (FAO-56), provisional', () => {
  assert.equal(BANANA.kc, 1.1); assert.equal(BANANA.p, 0.35); assert.equal(BANANA.provisional, true);
});

test('KsBanana: 1 hasta 0.35·TAW (54.6 mm), luego lineal hasta 0 en TAW', () => {
  assert.equal(bananaKs(0, TAW), 1);
  assert.equal(bananaKs(54.6, TAW), 1);
  near(bananaKs(100, TAW), 56 / (0.65 * 156)); // 0.552268…
  assert.equal(bananaKs(156, TAW), 0);
});

test('plotAdjust banano: día lluvioso y día seco, cobertura 0.3, a mano', () => {
  const dates = ['2020-07-15', '2020-01-15'];
  const a = plotAdjust(dates, 'trees', 'banana', { bananaCover: 0.3 });
  assert.deepEqual(a.reduce, [0.52, 0]); // mismo recorte de evaporación que los otros árboles: solo en lluvias
  assert.deepEqual(a.add, [0, 0]);
  near(a.addFn({ et0: 4, dr: 40, taw: TAW }), 0.3 * 1.1 * 4 * 1); // 1.32, suelo húmedo
  near(a.addFn({ et0: 4, dr: 100, taw: TAW }), 0.3 * 1.1 * 4 * (56 / 101.4)); // 0.72899…, suelo secándose
  near(a.addFn({ et0: 4, dr: 156, taw: TAW }), 0); // suelo agotado: el banano deja de gastar
});

test('plotAdjust banano: cobertura 0 = sin gasto de banano y sin sombra; sin cobertura declarada falla', () => {
  const a = plotAdjust(['2020-07-15', '2020-01-15'], 'trees', 'banana', { bananaCover: 0 });
  assert.deepEqual(a.reduce, [0, 0]); assert.deepEqual(a.add, [0, 0]);
  assert.equal(a.addFn({ et0: 5, dr: 10, taw: TAW }), 0);
  assert.throws(() => plotAdjust(['2020-07-15'], 'trees', 'banana'));
  assert.throws(() => plotAdjust(['2020-07-15'], 'trees', 'banana', { bananaCover: 1.5 }));
});

test('plotAdjust de los otros árboles no cambia (sin addFn)', () => {
  assert.deepEqual(plotAdjust(['2020-07-15', '2020-01-15'], 'trees', 'evergreen'), { reduce: [0.52, 0], add: [0.2, 0.2] });
});

test('variante sin KsBanana: gasta lo mismo con el suelo seco', () => {
  near(bananaUseMm({ cover: 0.3, et0: 4, dr: 150, taw: TAW, ks: false }), 1.32);
  const a = plotAdjust(['2020-01-15'], 'trees', 'banana', { bananaCover: 0.3, bananaKs: false });
  near(a.addFn({ et0: 4, dr: 150, taw: TAW }), 1.32);
});

test('un día del balance con banano (cobertura 0.3, ET0 4, Dr0 40, día lluvioso): ETc = (0.95·4 − 0.52) + 1.32', () => {
  const sim = simulateCoffee({ dates: ['2020-07-15'], rain: [0], et0: [4], crops, texture: 'loam', shade: 'trees', treeType: 'banana', bananaCover: 0.3, drInit: 40 });
  near(sim.etc[0], 3.28 + 1.32); near(sim.ks[0], 1); near(sim.dr[0], 40 + 4.6);
});

test('un día del balance con banano en día seco con Dr0 = 100: Ks del café 56/93.6 aplicado a todo el ETc del lote', () => {
  const sim = simulateCoffee({ dates: ['2020-01-15'], rain: [0], et0: [4], crops, texture: 'loam', shade: 'trees', treeType: 'banana', bananaCover: 0.3, drInit: 100 });
  const etc = 0.95 * 4 + 0.3 * 1.1 * 4 * (56 / 101.4);
  near(sim.etc[0], etc);
  near(sim.eta[0], (56 / 93.6) * etc);
});

test('entradas de la red v2: las 16 de siempre más banana y bananaCover', () => {
  assert.deepEqual(STATE_NAMES_V2, [...STATE_NAMES, 'banana', 'bananaCover']);
  assert.equal(STATE_NAMES_V2.length, 18);
});
