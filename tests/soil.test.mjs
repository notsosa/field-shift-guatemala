import test from 'node:test'; import assert from 'node:assert/strict';
import { SOILS, SLOPE_CLASSES, totalAvailableWater, scsRunoff, curveNumber, resolveSoil, usdaTextureClass, hydrologicGroupOf, cnForGroup, nearestTexture } from '../web/js/model/soil.js';
test('TAW manual del equipo', () => { assert.equal(Math.round(totalAvailableWater(0.30, 0.15, 0.40)), 60); assert.equal(Math.round(totalAvailableWater(0.30, 0.15, 0.20)), 30); });
test('SCS: P=50, CN=80 -> 13.8 mm', () => assert.ok(Math.abs(scsRunoff(50, 80) - 13.80) < 0.05));
test('SCS: P menor que Ia -> 0', () => assert.equal(scsRunoff(10, 80), 0));
test('SCS: lluvia no positiva -> 0', () => { assert.equal(scsRunoff(0, 80), 0); assert.equal(scsRunoff(-5, 80), 0); });
test('CN suelo desnudo > cultivo', () => assert.ok(curveNumber('loam', 'bare', 'moderate') > curveNumber('loam', 'crop', 'moderate')));
test('CN empinado <= 98', () => assert.ok(curveNumber('clay', 'bare', 'steep') <= 98));
test('CN pendiente: +5 empinado, -3 plano, 0 moderado', () => {
  assert.equal(curveNumber('loam', 'crop', 'moderate'), 78);
  assert.equal(curveNumber('loam', 'crop', 'steep'), 83);
  assert.equal(curveNumber('loam', 'crop', 'flat'), 75);
  assert.equal(curveNumber('clay', 'bare', 'steep'), 98);
});
test('tablas SOILS y SLOPE_CLASSES', () => {
  assert.deepEqual(Object.keys(SOILS), ['sand', 'loam', 'clay']);
  assert.equal(SOILS.clay.thetaFC, 0.36); assert.equal(SOILS.sand.thetaWP, 0.045);
  assert.equal(SOILS.loam.hydrologicGroup, 'B'); assert.deepEqual(SOILS.sand.cn, { crop: 67, residue: 64, bare: 77 });
  assert.ok(SOILS.loam.source.includes('cuadro 19') && SOILS.loam.source.includes('2-2b'));
  assert.deepEqual(SLOPE_CLASSES.steep, { pct: 20, erosionFactor: 2 });
});
test('textura o pendiente desconocida lanza error', () => {
  assert.throws(() => curveNumber('silt', 'crop', 'flat'), /silt/);
  assert.throws(() => curveNumber('loam', 'crop', 'cliff'), /cliff/);
});

const siteSoil = { thetaFC: 0.34, thetaWP: 0.19, cn: { crop: 89, residue: 87, bare: 94 }, label: 'SoilGrids clay loam', source: 'SoilGrids 2.0; CN: TR-55 2-2b' };
test('curveNumber acepta un objeto de suelo (mismos ajustes de pendiente y topes)', () => {
  assert.equal(curveNumber(siteSoil, 'crop', 'moderate'), 89);
  assert.equal(curveNumber(siteSoil, 'crop', 'flat'), 86);
  assert.equal(curveNumber(siteSoil, 'bare', 'steep'), 98);
  assert.equal(curveNumber(SOILS.loam, 'residue', 'steep'), curveNumber('loam', 'residue', 'steep'));
});
test('resolveSoil: clave o objeto; formas desconocidas lanzan error', () => {
  assert.equal(resolveSoil('clay'), SOILS.clay);
  assert.equal(resolveSoil(siteSoil), siteSoil);
  assert.throws(() => resolveSoil('silt'), /silt/);
  assert.throws(() => resolveSoil(undefined), /suelo|Textura/i);
  assert.throws(() => resolveSoil({ thetaFC: 0.3 }), /suelo/i);
  assert.throws(() => resolveSoil({ ...siteSoil, thetaWP: 0.4 }), /thetaWP|thetaFC/);
  assert.throws(() => resolveSoil({ ...siteSoil, cn: { crop: 80, residue: 78 } }), /cn/);
  assert.throws(() => resolveSoil({ ...siteSoil, source: '' }), /source/);
});
test('usdaTextureClass: tres ejemplos revisados a mano con el triangulo USDA', () => {
  // arcilla 31.9, arena 42.3 (limo 25.8): arcilla 27-40 y arena 20-45 -> franco arcilloso
  assert.equal(usdaTextureClass(31.9, 42.3), 'clay loam');
  // arcilla 5, arena 92 (limo 3): limo+1.5*arcilla = 10.5 < 15 -> arena
  assert.equal(usdaTextureClass(5, 92), 'sand');
  // arcilla 50, arena 20 (limo 30): arcilla >= 40, limo < 40, arena <= 45 -> arcilla
  assert.equal(usdaTextureClass(50, 20), 'clay');
  // arcilla 20, arena 40 (limo 40): arcilla 7-27, limo 28-50, arena <= 52 -> franco
  assert.equal(usdaTextureClass(20, 40), 'loam');
});
test('usdaTextureClass: porcentajes imposibles lanzan error', () => {
  assert.throws(() => usdaTextureClass(60, 50), /100/);
  assert.throws(() => usdaTextureClass(-1, 50), /clay|arcilla/i);
});
test('grupo hidrologico por clase de textura y CN del cuadro 2-2b', () => {
  assert.equal(hydrologicGroupOf('sand'), 'A');
  assert.equal(hydrologicGroupOf('loam'), 'B');
  assert.equal(hydrologicGroupOf('sandy clay loam'), 'C');
  assert.equal(hydrologicGroupOf('clay loam'), 'D');
  assert.throws(() => hydrologicGroupOf('gravel'), /gravel/);
  // A, B y D coinciden con las clases del simulador; C = fila SR bueno 85 / SR+CR bueno 82 / barbecho 91
  assert.deepEqual(cnForGroup('A'), SOILS.sand.cn);
  assert.deepEqual(cnForGroup('B'), SOILS.loam.cn);
  assert.deepEqual(cnForGroup('D'), SOILS.clay.cn);
  assert.deepEqual(cnForGroup('C'), { crop: 85, residue: 82, bare: 91 });
  assert.throws(() => cnForGroup('E'), /E/);
});
test('nearestTexture: la clase del simulador con agua disponible (thetaFC - thetaWP) mas cercana', () => {
  assert.equal(nearestTexture(0.12, 0.045), 'sand');
  assert.equal(nearestTexture(0.25, 0.12), 'loam');
  assert.equal(nearestTexture(0.36, 0.22), 'clay');
  assert.equal(nearestTexture(0.3594, 0.3037), 'sand'); // 0.056 de agua disponible: mas cerca de arena (0.075)
  assert.equal(nearestTexture(0.3418, 0.2113), 'loam'); // 0.1305 -> loam (0.13)
});
