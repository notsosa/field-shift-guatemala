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
  const base = { ...same, et0: Array(N).fill(1.5), phases: [phF, phM], irrigation: 'none', drInit: 0, dsInit: 0 }; // perfil entero a capacidad de campo: el Dr de las aserciones no depende del subsuelo seco
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

test('residueMask: día sin fase con residuo usa cobertura residue y menos escorrentía que bare', () => {
  const rain = Array(5).fill(40);
  const base = { rain, et0: Array(5).fill(4), phases: [], crops, texture: 'loam', slopeClass: 'moderate', irrigation: 'none' };
  const bare = simulateDays(base);
  const res = simulateDays({ ...base, residueMask: [false, true, true, true, true] });
  assert.equal(bare.cover[1], 'bare');
  assert.equal(res.cover[0], 'bare');
  assert.equal(res.cover[1], 'residue');
  assert.equal(res.kc[1], 0.15);
  assert.ok(res.runoff[1] < bare.runoff[1]);
});

// --- Reserva de agua del subsuelo (Tarea 15) ---
const sum = (a, from = 0, to = a.length - 1) => { let s = 0; for (let i = from; i <= to; i++) s += a[i]; return s; };

test('subsuelo: sin agua almacenada las raíces no crean agua (sin lluvia ni riego, eta ≈ 0)', () => {
  const d = simulateDays({ ...same, rain: Array(120).fill(0), et0: Array(120).fill(5), irrigation: 'none' });
  assert.ok(sum(d.eta, 0, ph.harvestIdx) < 1, `eta total = ${sum(d.eta, 0, ph.harvestIdx)}`);
});

test('subsuelo: el agua guardada en el subsuelo (dsInit 0) la usan las raíces al crecer', () => {
  const d = simulateDays({ ...same, rain: Array(120).fill(0), et0: Array(120).fill(5), irrigation: 'none', dsInit: 0 });
  const grow = d.ks.slice(1, ph.endIdx.dev + 1);
  assert.ok(Math.max(...grow) > 0.5, `Ks máx = ${Math.max(...grow)}`);
  assert.ok(sum(d.eta, 0, ph.harvestIdx) > 20);
});

function lcg(seed) { let s = seed; return () => { s = (s * 1664525 + 1013904223) % 4294967296; return s / 4294967296; }; }

for (const irrigation of ['none', 'limited', 'full']) {
  test(`subsuelo: conservación de agua (${irrigation})`, () => {
    const M = 300;
    const rnd = lcg(42);
    const rain = Array.from({ length: M }, () => (rnd() < 0.35 ? rnd() * 60 : 0));
    const et0 = Array.from({ length: M }, () => 2 + rnd() * 4);
    const phase = buildPhase(maiz, 20, Array(M).fill(26));
    const d = simulateDays({ rain, et0, phases: [phase], crops, texture: 'loam', slopeClass: 'moderate', irrigation });
    const soil = SOILS.loam;
    const zp = maiz.zrMax;
    const tawProfile = totalAvailableWater(soil.thetaFC, soil.thetaWP, zp);
    const dr0 = irrigation === 'full' ? 0 : d.taw[0];
    const ds0 = irrigation === 'full' ? 0 : totalAvailableWater(soil.thetaFC, soil.thetaWP, zp - d.zr[0]);
    assert.ok(dr0 + ds0 <= tawProfile + 1e-9);
    const inflow = sum(rain) - sum(d.runoff) + sum(d.irr);
    const outflow = sum(d.eta) + sum(d.drainOut);
    const last = M - 1;
    const stored0 = dr0 + ds0;
    const storedEnd = d.dr[last] + d.ds[last];
    assert.ok(Math.abs((inflow - outflow) - (stored0 - storedEnd)) < 1e-6, `balance = ${(inflow - outflow) - (stored0 - storedEnd)}`);
  });
}

test('subsuelo: la percolación profunda recarga el subsuelo antes de salir del perfil', () => {
  const M = 40;
  const rain = Array(M).fill(0); rain[3] = 40; rain[4] = 40; rain[5] = 40; rain[6] = 40;
  const d = simulateDays({ rain, et0: Array(M).fill(0), phases: [buildPhase(maiz, 0, Array(M).fill(26))], crops, texture: 'loam', slopeClass: 'flat', irrigation: 'none' });
  assert.ok(d.ds[2] > d.ds[6], `ds ${d.ds[2]} -> ${d.ds[6]}`);
  for (let i = 0; i < M; i++) {
    if (d.drainOut[i] > 0) assert.ok(d.ds[i] === 0, `drainOut ${d.drainOut[i]} con ds ${d.ds[i]} en ${i}`);
  }
});

test('subsuelo: al cosechar las raíces se acortan y dr + ds no salta', () => {
  const M = 200;
  const phase = buildPhase(maiz, 0, Array(M).fill(26));
  const rnd = lcg(7);
  const rain = Array.from({ length: M }, () => (rnd() < 0.3 ? rnd() * 30 : 0));
  const et0 = Array(M).fill(3);
  const d = simulateDays({ rain, et0, phases: [phase], crops, texture: 'loam', slopeClass: 'flat', irrigation: 'none', drInit: 30, dsInit: 20 });
  const h = phase.harvestIdx + 1;
  assert.ok(h < M);
  assert.ok(d.zr[h] < d.zr[h - 1]);
  const dayFlux = rain[h] - d.runoff[h] - d.eta[h] - d.drainOut[h];
  const expected = (d.dr[h - 1] + d.ds[h - 1]) - dayFlux;
  assert.ok(Math.abs((d.dr[h] + d.ds[h]) - expected) < 1e-9, `dr+ds ${d.dr[h] + d.ds[h]} vs ${expected}`);
});

test('subsuelo: salidas ds, zr y drainOut tienen un valor por día', () => {
  const d = simulateDays({ ...same, irrigation: 'none' });
  for (const k of ['ds', 'zr', 'drainOut']) assert.equal(d[k].length, N);
  assert.equal(d.zr[0], 0.15);
});

test('simulateDays con objeto de suelo == con la clase equivalente cuando theta y CN coinciden', () => {
  const rain = Array.from({ length: N }, (_, i) => (i % 9 === 0 ? 22 : 0));
  const args = { ...same, rain, irrigation: 'none', slopeClass: 'moderate' };
  const asKey = simulateDays({ ...args, texture: 'loam' });
  const asObject = simulateDays({ ...args, texture: { ...SOILS.loam, label: 'equivalent loam' } });
  assert.deepEqual(asObject, asKey);
  assert.ok(asKey.runoff.some((r) => r > 0));
});
test('simulateDays con suelo propio usa su theta y su CN', () => {
  const rain = Array.from({ length: N }, (_, i) => (i % 9 === 0 ? 22 : 0));
  const site = { thetaFC: 0.34, thetaWP: 0.19, cn: { crop: 89, residue: 87, bare: 94 }, label: 'site', source: 'test fixture' };
  const d = simulateDays({ ...same, rain, texture: site, irrigation: 'none', slopeClass: 'moderate' });
  assert.ok(Math.abs(d.taw[0] - totalAvailableWater(0.34, 0.19, 0.15)) < 1e-9);
  const cn89 = simulateDays({ ...same, rain, texture: 'clay', irrigation: 'none', slopeClass: 'moderate' });
  assert.deepEqual(d.runoff, cn89.runoff);
});
test('simulateDays: suelo de forma desconocida lanza error', () => {
  assert.throws(() => simulateDays({ ...same, irrigation: 'none', texture: { thetaFC: 0.3 } }), /suelo/i);
  assert.throws(() => simulateDays({ ...same, irrigation: 'none', texture: 42 }), /suelo|Textura/i);
});
