import test from 'node:test'; import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FEATURE_NAMES_V2, featuresV2, targetsV2, CROPS_V2 } from '../web/js/model/emulatorV2.js';
import { simulateSuccessionYear } from '../scripts/compare/succession_lib.mjs';
import { loadCrops } from '../web/js/model/crops.js';
import { computeEt0Series, agriculturalYears } from '../web/js/model/simulate.js';
import { climateFeatures } from '../web/js/model/emulator.js';

const rj = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));

test('targetsV2: fit exige que todo lo sembrado termine; sin B vale 0 en relYieldB', () => {
  const ok = { a: { relYield: 0.8, cycleIncomplete: false }, b: { relYield: 0.5, cycleIncomplete: false } };
  assert.deepEqual(targetsV2(ok, true), [0.8, 0.5, 1]);
  assert.deepEqual(targetsV2({ a: ok.a, b: null }, false), [0.8, 0, 1]);
  assert.deepEqual(targetsV2({ a: ok.a, b: null }, true), [0.8, 0, 0]); // B pedido pero no se pudo sembrar
  assert.deepEqual(targetsV2({ a: { relYield: 0, cycleIncomplete: true }, b: null }, false), [0, 0, 0]);
});

test('succesión con B = none y desfase: A se siembra más tarde, no hay B y el desfase 0 no cambia nada', () => {
  const bundle = rj('../web/data/snapshots/chiquimula.json');
  const crops = loadCrops(rj('../web/data/crops.json'));
  const et0 = computeEt0Series(bundle);
  const ag = agriculturalYears(bundle.dates).find((a) => a.year === 2019);
  const base = { idA: 'maiz', bundle, et0, crops, texture: 'loam', year: 2019, startIdx: ag.startIdx, endIdx: ag.endIdx };
  const s0 = simulateSuccessionYear({ ...base, idB: 'frijol' });
  assert.deepEqual(simulateSuccessionYear({ ...base, idB: 'frijol', offsetDays: 0 }), s0);
  const n0 = simulateSuccessionYear({ ...base, idB: null });
  const n30 = simulateSuccessionYear({ ...base, idB: null, offsetDays: 30 });
  assert.equal(n0.b, null);
  assert.equal(n0.a.relYield, s0.a.relYield); // A no depende de B
  assert.equal((Date.parse(n30.a.sowDate) - Date.parse(n0.a.sowDate)) / 864e5, 30);
  // entradas: 31 columnas, unos exactos en las codificaciones
  const clim = climateFeatures(bundle, 2019, et0);
  const x = featuresV2({ bundle, et0, year: 2019, climFeats: clim, sowLocal: 40, offsetDays: 15, idA: 'papa', idB: null, soil: 'clay' });
  assert.equal(x.length, FEATURE_NAMES_V2.length);
  assert.equal(x[FEATURE_NAMES_V2.indexOf('A_papa')], 1);
  assert.equal(x[FEATURE_NAMES_V2.indexOf('B_none')], 1);
  assert.equal(x[FEATURE_NAMES_V2.indexOf('soil_clay')], 1);
  assert.equal(x.slice(12, 19).reduce((s, v) => s + v, 0), 1);
  assert.equal(x.at(-1), 0.5);
  // lluvia de los primeros 60 días = suma a mano desde el bundle
  const s = ag.startIdx + 40;
  let r = 0; for (let i = s; i < s + 60; i++) r += bundle.rain[i];
  assert.ok(Math.abs(x[FEATURE_NAMES_V2.indexOf('rain0to60')] - r) < 1e-9);
  assert.equal(CROPS_V2.length, 7);
});
