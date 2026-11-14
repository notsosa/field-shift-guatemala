import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCrops } from '../web/js/model/crops.js';
import { buildPhase, kcOnDay } from '../web/js/model/phenology.js';
import { totalAvailableWater, SOILS } from '../web/js/model/soil.js';
import { stepDepletion, stressCoefficient, simulateDays } from '../web/js/model/waterBalance.js';

const crops = loadCrops(JSON.parse(readFileSync(new URL('../web/data/crops.json', import.meta.url), 'utf8')));
const maiz = crops.get('maiz');
const N = 150;
const ph = buildPhase(maiz, 0, Array(N).fill(26));
const same = { rain: Array(N).fill(0), et0: Array(N).fill(5), phases: [ph], crops, texture: 'loam', slopeClass: 'flat' };

test('ejemplo didáctico del manual: 18 − (12 − 4) + 3 = 13', () => assert.equal(stepDepletion({ drPrev: 18, rain: 12, runoff: 4, irr: 0, etcAdj: 3, taw: 60 }).dr, 13));
test('con escorrentía 8 mm queda en 17', () => assert.equal(stepDepletion({ drPrev: 18, rain: 12, runoff: 8, irr: 0, etcAdj: 3, taw: 60 }).dr, 17));
test('exceso de lluvia: dr = 0 y el resto drena', () => {
  const r = stepDepletion({ drPrev: 5, rain: 40, runoff: 0, irr: 0, etcAdj: 2, taw: 60 });
  assert.equal(r.dr, 0);
  assert.equal(r.deepPerc, 33);
});
test('Ks: TAW 60, p 0.5, Dr 45 -> 0.5', () => assert.equal(stressCoefficient(45, 60, 0.5), 0.5));
test('Ks = 1 si Dr <= RAW', () => assert.equal(stressCoefficient(20, 60, 0.5), 1));
test('riego full mantiene Ks = 1 en sequía', () => {
  const d = simulateDays({ ...same, irrigation: 'full' });
  assert.ok(Math.min(...d.ks.slice(0, ph.harvestIdx + 1)) >= 0.99);
  assert.ok(d.irr.reduce((a, b) => a + b) > 0);
});
test('sin riego en sequía Ks cae por debajo de 0.7 durante el ciclo (arranca húmedo)', () => {
  const d = simulateDays({ ...same, irrigation: 'none', drInit: 0 });
  assert.equal(d.ks[0], 1);
  const mid = ph.endIdx.dev + 10;
  assert.ok(mid < ph.endIdx.mid);
  assert.ok(d.ks[mid] < 0.7, `Ks en mid = ${d.ks[mid]}`);
});
test('suelo desnudo: Kc 0.15, cover bare, sin fases', () => {
  const d = simulateDays({ ...same, phases: [], irrigation: 'full' });
  assert.ok(d.kc.every((k) => k === 0.15));
  assert.ok(d.cover.every((c) => c === 'bare'));
  assert.ok(d.irr.every((x) => x === 0));
  assert.equal(d.taw[0], totalAvailableWater(SOILS.loam.thetaFC, SOILS.loam.thetaWP, 0.15));
});
test('riego limitado solo riega dentro de la ventana de floración', () => {
  const d = simulateDays({ ...same, irrigation: 'limited' });
  const [a, b] = ph.floweringIdx;
  d.irr.forEach((x, i) => { if (x > 0) assert.ok(i >= a && i <= b, `riego fuera de ventana en ${i}`); });
  assert.ok(d.irr.some((x) => x > 0));
});
test('Zr crece: TAW sube del día de siembra al fin de dev y se queda', () => {
  const d = simulateDays({ ...same, irrigation: 'none' });
  assert.ok(d.taw[ph.endIdx.dev] > d.taw[0]);
  assert.equal(d.taw[ph.endIdx.dev], totalAvailableWater(SOILS.loam.thetaFC, SOILS.loam.thetaWP, maiz.zrMax));
});
test('irrigation desconocido lanza error con su nombre', () => {
  assert.throws(() => simulateDays({ ...same, irrigation: 'xyz' }), /xyz/);
});
test('fases traslapadas: Kc, Zr (TAW) y p siguen al cultivo activo de mayor Kc', () => {
  const frijol = crops.get('frijol');
  const t = Array(N).fill(26);
  const phF = buildPhase(frijol, 0, t); // frijol en mid el día 40
  const phM = buildPhase(maiz, 30, t); // maíz en ini el día 40
  const i = 40;
  assert.ok(i > phF.endIdx.dev && i <= phF.endIdx.mid && i <= phM.endIdx.ini);
  const base = { ...same, et0: Array(N).fill(1.5), phases: [phF, phM], irrigation: 'none', drInit: 0 };
  const d = simulateDays(base);
  assert.equal(d.kc[i], Math.max(kcOnDay(frijol, phF, i), kcOnDay(maiz, phM, i)));
  assert.equal(d.kc[i], kcOnDay(frijol, phF, i));
  // Zr máxima de las activas: frijol ya está en zrMax (0.7), maíz aún crece.
  assert.equal(d.taw[i], totalAvailableWater(SOILS.loam.thetaFC, SOILS.loam.thetaWP, frijol.zrMax));
  // p del frijol (0.45), no el del maíz (0.55): con este Dr los dos darían Ks distintos.
  const dr = d.dr[i - 1];
  assert.ok(dr > 0.45 * d.taw[i] && dr < 0.55 * d.taw[i]);
  assert.equal(d.ks[i], stressCoefficient(dr, d.taw[i], frijol.p));
  assert.notEqual(d.ks[i], stressCoefficient(dr, d.taw[i], maiz.p));
  // Día con maíz en mid y frijol en ini (frijol sembrado tarde): Kc del maíz.
  const phF2 = buildPhase(frijol, 60, t);
  const d2 = simulateDays({ ...base, phases: [ph, phF2] });
  assert.equal(d2.kc[60], kcOnDay(maiz, ph, 60));
  assert.ok(kcOnDay(maiz, ph, 60) > kcOnDay(frijol, phF2, 60));
});
