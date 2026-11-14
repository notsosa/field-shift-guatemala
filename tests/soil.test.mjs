import test from 'node:test'; import assert from 'node:assert/strict';
import { SOILS, SLOPE_CLASSES, totalAvailableWater, scsRunoff, curveNumber } from '../web/js/model/soil.js';
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
