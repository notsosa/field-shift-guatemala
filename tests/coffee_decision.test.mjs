import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCrops } from '../web/js/model/crops.js';
import { simulateCoffee, coffeeDecisionState, runningDepletion, ruleIrrigates, counterfactual, irrigationUtility, STATE_NAMES } from '../web/js/model/coffee.js';

const crops = loadCrops(JSON.parse(readFileSync(new URL('../web/data/crops.json', import.meta.url), 'utf8')));
const cafe = crops.get('cafe');
const isoDays = (from, n) => Array.from({ length: n }, (_, i) => new Date(Date.UTC(...from) + i * 864e5).toISOString().slice(0, 10));
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-9, `${a} vs ${b}`);

test('balance corrido: tope en TAW y piso en 0, a mano', () => {
  const rain = [0, 0, 0, 20, 0], et0 = [4, 4, 4, 4, 4];
  near(runningDepletion({ rain, et0, nov1Idx: 0, t: 2, taw: 156, kc: 0.95 }), 11.4);
  near(runningDepletion({ rain, et0, nov1Idx: 0, t: 2, taw: 10, kc: 0.95 }), 10); // tope
  near(runningDepletion({ rain, et0, nov1Idx: 0, t: 3, taw: 156, kc: 0.95 }), 0); // 11.4 + 3.8 − 20 < 0 → 0
  near(runningDepletion({ rain, et0, nov1Idx: 0, t: 4, taw: 156, kc: 0.95 }), 3.8);
});

const world = () => {
  const dates = isoDays([2020, 9, 1], 400); // 1 oct 2020 → 5 nov 2021
  const n = dates.length;
  return { dates, n, rain: Array(n).fill(0), et0: Array(n).fill(4), tmax: Array(n).fill(30), tmin: Array(n).fill(18) };
};
const soilLoam = { thetaFC: 0.25, thetaWP: 0.12 };

test('estado del día de la decisión: valores a mano y sin datos posteriores', () => {
  const w = world();
  const fl = w.dates.indexOf('2021-03-19'), t = fl + 30; // 18 abr 2021
  w.rain[t - 2] = 12; w.rain[t - 40] = 5; w.tmax[t - 5] = 35;
  const args = { ...w, t, year: 2020, floweringIdx: fl, soil: soilLoam, crop: cafe, elevation: 1200, shade: 'trees', treeType: 'deciduous' };
  const { state, depletion, taw } = coffeeDecisionState(args);
  const get = (k) => state[STATE_NAMES.indexOf(k)];
  assert.equal(state.length, STATE_NAMES.length);
  assert.equal(get('daysSinceFlowering'), 30); assert.equal(get('doy'), 108);
  near(get('rain7'), 12); near(get('rain28'), 12); near(get('et0_7'), 28); near(get('et0_28'), 112);
  const nDays = t - w.dates.indexOf('2020-11-01') + 1;
  near(get('et0SinceNov1'), 4 * nDays); near(get('rainSinceNov1'), 17);
  assert.equal(get('dryspell28'), 25); // la lluvia de 12 mm del día t−2 parte la racha: t−27..t−3 son 25 días secos
  near(get('tmean28'), (27 * 24 + 26.5) / 28); near(get('tmaxMax28'), 35);
  near(get('soilAWmm'), 156); assert.equal(get('elevation'), 1200); assert.equal(get('shadeTrees'), 1); assert.equal(get('deciduous'), 1);
  assert.equal(taw, 156); assert.ok(depletion >= 0 && depletion <= 156);
  const w2 = { ...args, rain: w.rain.map((v, i) => (i > t ? 300 : v)), et0: w.et0.map((v, i) => (i > t ? 0 : v)), tmax: w.tmax.map((v, i) => (i > t ? 60 : v)), tmin: w.tmin.map((v, i) => (i > t ? -9 : v)) };
  assert.deepEqual(coffeeDecisionState(w2), { state, depletion, taw });
  assert.equal(ruleIrrigates(60, 156, 0.4), false); assert.equal(ruleIrrigates(62.5, 156, 0.4), true);
});

test('contrafactual: sin riego igual a la corrida continua (lluvia irregular, sombra decidua)', () => {
  const w = world(); const t = 120;
  w.rain = w.rain.map((_, i) => (i % 17 === 0 ? 14 : 0));
  const sim = simulateCoffee({ dates: w.dates, rain: w.rain, et0: w.et0, crops, texture: 'loam', shade: 'trees', treeType: 'deciduous' });
  const cf = counterfactual({ ...w, crops, texture: 'loam', shade: 'trees', treeType: 'deciduous', sim, t });
  assert.equal(cf.stressNo, sim.ks.slice(t + 1, t + 31).filter((k) => k < 1).length);
  assert.ok(cf.stressYes <= cf.stressNo);
});

test('contrafactual: el riego de 20 mm evita días de estrés, a mano', () => {
  const w = world(); const t = 10;
  const base = { ...w, crops, texture: 'loam', shade: 'none', treeType: 'evergreen', t };
  const fake = (dr) => ({ dr: Array(w.n).fill(dr), ds: Array(w.n).fill(0) });
  // Dr = 96.8 > RAW 62.4 (loam: TAW 156, p 0.4): 20 mm lo dejan en 76.8, todavía sobre RAW → no evita nada
  const cf = counterfactual({ ...base, sim: fake(96.8) });
  assert.equal(cf.stressNo, 30); assert.equal(cf.stressYes, 30); assert.equal(cf.stressDaysAvoided, 0);
  // Dr = 70, regar → 50; el día k empieza con 50 + 3.8·(k−1) mientras Ks = 1: 50, 53.8, 57.6, 61.4 ≤ 62.4 y el día 5 empieza en 65.2 → 4 días sin estrés
  const cf2 = counterfactual({ ...base, sim: fake(70) });
  assert.equal(cf2.stressNo, 30); assert.equal(cf2.stressYes, 26); assert.equal(cf2.stressDaysAvoided, 4);
  assert.equal(irrigationUtility(4, 0), 1); assert.equal(irrigationUtility(4, 1), 3); assert.equal(irrigationUtility(3, 0), 0);
  // suelo casi lleno: Dr = 5. Sin riego, el día k empieza con 5 + 3.8·(k−1) ≤ 62.4 hasta k = 16 (62.0): 14 días de estrés.
  // Regando, Dr = 0 (el exceso se pierde): 3.8·(k−1) ≤ 62.4 hasta k = 17 (60.8): 13 días de estrés → evita 1.
  const cf3 = counterfactual({ ...base, sim: fake(5) });
  assert.equal(cf3.stressNo, 14); assert.equal(cf3.stressYes, 13); assert.equal(cf3.stressDaysAvoided, 1);
});
