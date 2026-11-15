import test from 'node:test'; import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  median, quantile, medianDate, sowAfterHarvest, simulateSuccessionYear, compareOrders, majority, teammateDirection, screen, summarizePair,
} from '../scripts/compare/succession_lib.mjs';
import { loadCrops } from '../web/js/model/crops.js';
import { computeEt0Series, runSequence } from '../web/js/model/simulate.js';

const rj = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));

test('mediana y cuantil por interpolación lineal, calculados a mano', () => {
  assert.equal(median([3, 1, 2]), 2);
  assert.equal(median([4, 1, 2, 3]), 2.5);
  assert.equal(median([]), null);
  // [0,1,2,3,4]: q=0.1 → pos 0.4 → 0.4; q=0.5 → 2
  assert.ok(Math.abs(quantile([4, 0, 3, 1, 2], 0.1) - 0.4) < 1e-12);
  assert.equal(quantile([4, 0, 3, 1, 2], 0.5), 2);
  assert.equal(quantile([7], 0.1), 7);
});

test('mediana de fechas ordena por año agrícola (enero va después de diciembre)', () => {
  assert.equal(medianDate(['2002-01-10', '2001-12-20', '2001-09-01']), '2001-12-20');
  assert.equal(medianDate(['2001-09-01', '2001-10-01']), '2001-09-01'); // par: la anterior
  assert.equal(medianDate([]), null);
});

test('el sucesor se siembra el día siguiente a la cosecha más 14 días', () => {
  assert.equal(sowAfterHarvest(100), 115);
  assert.equal(sowAfterHarvest(100, 7), 108);
});

// Año sintético: 2001-04-01 … 2002-03-31, tmax 30 / tmin 22 (tmean 26 = TREF), lluvia 10 mm/día, sin viento ni nada raro.
function syntheticBundle() {
  const dates = [];
  for (let t = Date.UTC(2001, 3, 1); t <= Date.UTC(2002, 2, 31); t += 864e5) dates.push(new Date(t).toISOString().slice(0, 10));
  const n = dates.length;
  return { dates, tmax: Array(n).fill(30), tmin: Array(n).fill(22), rain: Array(n).fill(10) };
}
// tbase 6 → 20 GDD/día a 26 °C; etapas de 20·días GDD → la etapa dura exactamente `days` días.
const mkCrop = (id, days) => ({ id, tbase: 6, days, kc: { ini: 0.5, mid: 1, end: 0.5 }, zrMax: 0.5, p: 0.5, ky: 1, kyStages: null });

test('sucesión sintética: siembra de A en el inicio de lluvias, de B 15 días después de la cosecha de A', () => {
  const bundle = syntheticBundle();
  const crops = new Map([['a', mkCrop('a', { ini: 2, dev: 3, mid: 3, late: 2 })], ['b', mkCrop('b', { ini: 1, dev: 2, mid: 4, late: 3 })]]);
  const et0 = Array(bundle.dates.length).fill(3);
  const r = simulateSuccessionYear({ idA: 'a', idB: 'b', bundle, et0, crops, texture: 'loam', year: 2001, startIdx: 0, endIdx: bundle.dates.length - 1 });
  // Lluvia 10 mm/día: 3 días ≥ 20 mm se cumple el 3 de mayo (1 mayo + 2). A dura 10 días: 3–12 mayo. B: 12 + 1 + 14 = 27 de mayo, 10 días.
  assert.equal(r.a.sowDate, '2001-05-03');
  assert.equal(r.a.harvestDate, '2001-05-12');
  assert.equal(r.a.cycleDays, 10);
  assert.equal(r.b.sowDate, '2001-05-27');
  assert.equal(r.b.harvestDate, '2001-06-05');
  assert.equal(r.b.cycleDays, 10);
  assert.equal(r.fit, true);
  assert.ok(Math.abs(r.a.etcMm - (r.a.etaMm + r.a.deficitMm)) < 1e-9);
  assert.equal(r.a.tmaxMean, 30);
});

test('si el ciclo de A no cabe en el año, B no se siembra y la sucesión no cabe (relYield 0)', () => {
  const bundle = syntheticBundle();
  const crops = new Map([['a', mkCrop('a', { ini: 100, dev: 100, mid: 100, late: 100 })], ['b', mkCrop('b', { ini: 1, dev: 1, mid: 1, late: 1 })]]);
  const et0 = Array(bundle.dates.length).fill(3);
  const r = simulateSuccessionYear({ idA: 'a', idB: 'b', bundle, et0, crops, texture: 'loam', year: 2001, startIdx: 0, endIdx: bundle.dates.length - 1 });
  assert.equal(r.fit, false);
  assert.equal(r.b, null);
  assert.equal(r.a.cycleIncomplete, true);
  assert.equal(r.a.relYield, 0);
  const s = summarizePair([r]);
  assert.equal(s.fitYears, 0);
  assert.equal(s.b.relYieldMedian, 0);
  assert.equal(s.a.medianCycleDays, null);
});

const yr = (fit, da, db, ya = 1, yb = 1) => ({ fit, a: fit ? { deficitMm: da, relYield: ya } : null, b: fit ? { deficitMm: db, relYield: yb } : null });

test('comparación de órdenes: déficit y relYield por año, solo donde caben ambos', () => {
  const ab = [yr(true, 10, 20, 1, 0.5), yr(true, 5, 5, 1, 1), yr(false), yr(true, 50, 0, 0.9, 0.9)];
  const ba = [yr(true, 20, 20, 0.5, 0.5), yr(true, 5, 5, 1, 1), yr(true, 1, 1), yr(true, 10, 10, 1, 1)];
  const c = compareOrders(ab, ba);
  // año 1: 30 vs 40 → AB menor déficit; relYield .75 vs .5 → AB. año 2: empate. año 3: no cabe. año 4: 50 vs 20 → BA menor; .9 vs 1 → BA.
  assert.deepEqual(c, { yearsBothFit: 3, abLowerDeficit: 1, baLowerDeficit: 1, tieDeficit: 1, abHigherRelYield: 1, baHigherRelYield: 1, tieRelYield: 1 });
  assert.equal(majority(1, 1), 'tie');
  assert.equal(majority(3, 1), 'AB');
  assert.equal(majority(0, 2), 'BA');
});

test('dirección del equipo: el orden con menor déficit; null si falta una fila', () => {
  assert.equal(teammateDirection({ deficit: 100 }, { deficit: 120 }), 'AB');
  assert.equal(teammateDirection({ deficit: 130 }, { deficit: 120 }), 'BA');
  assert.equal(teammateDirection({ deficit: 1 }, { deficit: 1 }), 'tie');
  assert.equal(teammateDirection({ deficit: 1 }, undefined), null);
});

test('pantalla: cabe en ≥ 20 años, ordenada por el menor de los dos relYield medianos', () => {
  const e = (pair, fitYears, a, b) => ({ pair, fitYears, a: { relYieldMedian: a }, b: { relYieldMedian: b } });
  const s = screen([e('x>y', 24, 0.9, 0.5), e('p>q', 20, 0.8, 0.7), e('m>n', 19, 1, 1), e('u>v', 21, 0.95, 0.4)]);
  assert.deepEqual(s.fits.map((f) => f.pair), ['p>q', 'x>y', 'u>v']);
  assert.equal(s.fits[0].lowestMedianRelYield, 0.7);
  assert.deepEqual(s.notFit, [{ pair: 'm>n', fitYears: 19 }]);
});

test('agregar los cuatro cultivos no cambia las rotaciones existentes (Chiquimula, 24 años, las 4 rotaciones)', () => {
  const all = rj('../web/data/crops.json');
  const original = ['maiz', 'frijol', 'sorgo', 'ajonjoli', 'sandia', 'melon', 'tomate', 'mucuna'];
  const cropsOld = loadCrops(all.filter((c) => original.includes(c.id)));
  const cropsNew = loadCrops(all);
  assert.equal(cropsOld.size, 8);
  assert.equal(cropsNew.size, 12);
  const bundle = rj('../web/data/snapshots/chiquimula.json');
  const et0 = computeEt0Series(bundle);
  const seqs = rj('../web/data/sequences.json');
  for (const sequence of Object.values(seqs)) {
    const run = (crops) => runSequence({ sequence, bundle, et0, crops, texture: 'loam', slopeClass: 'flat', irrigation: 'limited', sowOffsetDays: 0 });
    assert.deepEqual(run(cropsNew), run(cropsOld), sequence.id);
  }
});
