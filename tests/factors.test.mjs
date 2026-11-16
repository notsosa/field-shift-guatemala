import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCrops } from '../web/js/model/crops.js';
import { runSequence } from '../web/js/model/simulate.js';
import {
  logisticFall, heatCoefficientDay, heatMultiplier, hasHeatFactor, fertilityMultiplier, FERTILITY_CLASSES, degreeDaysAbove, lobellMultiplier,
  applyFactors, normalizeConstraints,
} from '../web/js/model/factors.js';

const read = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));
const near = (a, b, eps = 1e-4) => assert.ok(Math.abs(a - b) < eps, `${a} vs ${b}`);

test('logistica: extremos exactos y centro 0.5', () => {
  assert.equal(logisticFall(0), 1);
  assert.equal(logisticFall(-1), 1);
  assert.equal(logisticFall(1), 0);
  assert.equal(logisticFall(2), 0);
  near(logisticFall(0.5), 0.5, 1e-12);
  // x = 0.2, k = 10: s(v) = 1/(1+exp(-10(v-0.5))); (s(1)-s(0.2))/(s(1)-s(0)) = (0.993307-0.047426)/0.986614 = 0.95871
  near(logisticFall(0.2), 0.95871);
  near(logisticFall(0.8), 1 - 0.95871);
});

test('calor diario: umbrales 40 C y 10 C del maiz y el tomate', () => {
  assert.equal(heatCoefficientDay('maiz', 40, 20), 1);
  assert.equal(heatCoefficientDay('maiz', 35, 10), 1);
  near(heatCoefficientDay('maiz', 42.5, 20), 0.5, 1e-9); // a mitad de los 5 C
  assert.equal(heatCoefficientDay('maiz', 45, 20), 0);
  near(heatCoefficientDay('maiz', 30, 7.5), 0.5, 1e-9); // frio: Tmin 7.5 = 2.5 C bajo 10
  assert.equal(heatCoefficientDay('maiz', 30, 5), 0);
  near(heatCoefficientDay('tomate', 42.5, 20), 0.5, 1e-9);
  // calor y frio a la vez: gana el menor
  near(heatCoefficientDay('maiz', 41, 7.5), Math.min(logisticFall(0.2), 0.5));
});

test('frijol, cafe y otros: sin umbral publicado, sin factor', () => {
  for (const id of ['frijol', 'cafe', 'sorgo', 'papa', 'cebolla', 'ajonjoli']) {
    assert.equal(hasHeatFactor(id), false);
    assert.equal(heatCoefficientDay(id, 48, 0), 1);
  }
  assert.deepEqual(heatMultiplier('frijol', [50, 50], [0, 0], 0, 1), { mean: 1, min: 1, daysBelow1: 0 });
});

test('multiplicador de ventana = media del coeficiente diario', () => {
  const tmax = [30, 42.5, 45, 30]; const tmin = [20, 20, 20, 20];
  const m = heatMultiplier('maiz', tmax, tmin, 0, 3);
  near(m.mean, (1 + 0.5 + 0 + 1) / 4, 1e-9);
  assert.equal(m.min, 0);
  assert.equal(m.daysBelow1, 2);
  assert.deepEqual(heatMultiplier('maiz', tmax, tmin, 3, 2), { mean: 1, min: 1, daysBelow1: 0 }); // ventana vacia
});

test('fertilidad: tabla 2.13a de AquaCrop; no declarada = 1; clase desconocida falla', () => {
  assert.deepEqual(FERTILITY_CLASSES, { 'near-optimal': 0.8, moderate: 0.6, 'about-half': 0.5, poor: 0.4, 'very-poor': 0.25 });
  assert.equal(fertilityMultiplier(null), 1);
  assert.equal(fertilityMultiplier(undefined), 1);
  assert.equal(fertilityMultiplier('poor'), 0.4);
  assert.throws(() => fertilityMultiplier('fertilizado'), /desconocida/);
});

test('Lobell (sensibilidad): 1 % y 1.7 % por grado-dia sobre 30 C', () => {
  const dd = degreeDaysAbove([28, 32, 35, 31], 0, 3); // 0 + 2 + 5 + 1
  assert.equal(dd, 8);
  near(lobellMultiplier(dd, false), 0.92, 1e-12);
  near(lobellMultiplier(dd, true), 1 - 8 * 0.017, 1e-12);
  assert.equal(lobellMultiplier(100, true), 0);
});

test('applyFactors: agua x calor x fertilidad; sin factors no toca nada', () => {
  assert.deepEqual(applyFactors({ cropId: 'maiz', relYield: 0.9, factors: null }), { relYield: 0.9, heat: null, fertility: 1 });
  const r = applyFactors({ cropId: 'maiz', relYield: 0.8, tmax: [42.5], tmin: [20], flowerIdx: [0, 0], factors: { heat: true, fertilityClass: 'moderate' } });
  near(r.relYield, 0.8 * 0.5 * 0.6, 1e-9);
  const noHeat = applyFactors({ cropId: 'maiz', relYield: 0.8, tmax: [42.5], tmin: [20], flowerIdx: [0, 0], factors: { fertilityClass: 'poor' } });
  near(noHeat.relYield, 0.32, 1e-12);
  assert.equal(noHeat.heat, null);
});

test('restricciones declaradas', () => {
  assert.deepEqual(normalizeConstraints(), { canResow: true, hasIrrigation: false, irrigationType: null, pestLevel: null });
  assert.deepEqual(normalizeConstraints({ canResow: false, hasIrrigation: true, irrigationType: 'drip', pestLevel: 'high' }), { canResow: false, hasIrrigation: true, irrigationType: 'drip', pestLevel: 'high' });
  assert.equal(normalizeConstraints({ hasIrrigation: false, irrigationType: 'drip' }).irrigationType, null);
});

// Integracion: runSequence con y sin `factors`.
const crops = loadCrops(read('../web/data/crops.json'));
function makeBundle(tmax, tmin) {
  const dates = [];
  for (let d = new Date(Date.UTC(2001, 3, 1)); d <= new Date(Date.UTC(2003, 2, 31)); d = new Date(d.getTime() + 864e5)) dates.push(d.toISOString().slice(0, 10));
  const n = dates.length;
  const rain = dates.map((s) => { const m = Number(s.slice(5, 7)); return m >= 5 && m <= 10 ? 8 : 0; });
  return { dates, rain, tmax: Array(n).fill(tmax), tmin: Array(n).fill(tmin), tdew: Array(n).fill(20), rs: Array(n).fill(18), u2: Array(n).fill(2), pressure: Array(n).fill(96), elevation: 400, lat: 14.8, lon: -90, rainSource: 'test', sources: [], fallback: false };
}
const et0 = (b) => Array(b.dates.length).fill(4);
const maizeOnly = { id: 'solo-maiz', requiresIrrigation: false, phases: [{ cropId: 'maiz', sow: 'onset' }] };

test('runSequence: sin factors identico; con calor de 42.5 C el maiz baja a la mitad', () => {
  const b = makeBundle(42.5, 20);
  const base = { sequence: maizeOnly, bundle: b, et0: et0(b), crops, texture: 'loam', slopeClass: 'moderate', irrigation: 'none' };
  const plain = runSequence(base);
  assert.deepEqual(runSequence({ ...base, factors: null }), plain);
  assert.ok(!('relYieldWaterOnly' in plain[0].crops[0]));
  const hot = runSequence({ ...base, factors: { heat: true } });
  near(hot[0].crops[0].heatMultiplier, 0.5, 1e-9);
  near(hot[0].crops[0].relYield, plain[0].crops[0].relYield * 0.5, 1e-9);
  near(hot[0].crops[0].relYieldWaterOnly, plain[0].crops[0].relYield, 1e-12);
  const poor = runSequence({ ...base, factors: { fertilityClass: 'poor' } });
  near(poor[0].crops[0].relYield, plain[0].crops[0].relYield * 0.4, 1e-9);
});
