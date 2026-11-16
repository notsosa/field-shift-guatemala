import test from 'node:test'; import assert from 'node:assert/strict';
import {
  percentile, rankWorst, isHit, auc, WORST_THIRD, sumBetween, longestDrySpell, completeYears, simulateSowing, sowLocalIndex, loadSite, loadAllCrops, soilOfPoint, loadPoints,
} from '../scripts/compare/rain_sources_lib.mjs';
import { simulateResow, resowOffset } from '../scripts/compare/loss_decision_lib.mjs';

const close = (a, b, eps = 1e-12) => assert.ok(Math.abs(a - b) <= eps, `${a} != ${b}`);

test('percentil por rango medio, a mano: [0.2, 0.5, 0.5, 0.9]', () => {
  const v = [0.2, 0.5, 0.5, 0.9];
  close(percentile(v, 0.2), (0 + 0.5) / 4); // ninguno menor, uno igual (él mismo)
  close(percentile(v, 0.5), (1 + 0.5 * 2) / 4); // uno menor, dos iguales = 0.5
  close(percentile(v, 0.9), (3 + 0.5) / 4);
  close(percentile([1, 1, 1], 1), 0.5); // todos empatados: ni peor ni mejor
});

test('puesto (1 = el peor) y empates, a mano', () => {
  assert.deepEqual(rankWorst([0.2, 0.5, 0.5, 0.9], 0.5), { rank: 2, tied: 2, of: 4 });
  assert.deepEqual(rankWorst([0.2, 0.5, 0.5, 0.9], 0.2), { rank: 1, tied: 1, of: 4 });
});

test('acierto: peor tercio = percentil <= 1/3 (umbral fijo)', () => {
  assert.equal(WORST_THIRD, 1 / 3);
  const six = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6];
  assert.equal(isHit(percentile(six, 0.2)), true); // (1 + 0.5)/6 = 0.25
  assert.equal(isHit(percentile(six, 0.3)), false); // 2.5/6 = 0.4167
  assert.equal(isHit(1 / 3), true); // el borde cuenta
  assert.equal(isHit(0.34), false);
  // 24 años con 8 ceros: percentil medio de un cero = (0 + 4)/24 = 1/6 -> acierto
  assert.equal(isHit(percentile([...Array(8).fill(0), ...Array(16).fill(1)], 0)), true);
});

test('AUC de Mann-Whitney, a mano', () => {
  // eventos [0.9, 0.5] contra controles [0.5, 0.1, 0.2]: 0.9 gana 3; 0.5 empata 1 (0.5) y gana 2 -> (3 + 2.5)/6
  close(auc([0.9, 0.5], [0.5, 0.1, 0.2]), 5.5 / 6);
  assert.equal(auc([3, 4], [1, 2]), 1); // separación perfecta
  assert.equal(auc([1, 2], [3, 4]), 0); // al revés
  assert.equal(auc([1, 1], [1, 1]), 0.5); // todo empatado
  assert.equal(auc([], [1]), null);
  assert.equal(auc([1], []), null);
});

test('suma y racha seca (< 1 mm) a mano; un día sin dato anula el periodo (no se rellena)', () => {
  const dates = Array.from({ length: 10 }, (_, i) => `2021-06-${String(i + 1).padStart(2, '0')}`);
  const rain = [0, 0.5, 2, 0, 0, 0, 3, 0.9, 0.99, 1]; // rachas secas: 2, 3, 2 (el 1.0 no es seco)
  assert.equal(longestDrySpell(dates, rain, '2021-06-01', '2021-06-10'), 3);
  assert.equal(longestDrySpell(dates, rain, '2021-06-08', '2021-06-10'), 2);
  close(sumBetween(dates, rain, '2021-06-01', '2021-06-03'), 2.5);
  const holey = rain.slice(); holey[4] = null;
  assert.equal(longestDrySpell(dates, holey, '2021-06-01', '2021-06-10'), null);
  assert.equal(sumBetween(dates, holey, '2021-06-01', '2021-06-10'), null);
  assert.equal(sumBetween(dates, holey, '2021-06-06', '2021-06-10') !== null, true);
});

test('un año agrícola con un día sin lluvia queda fuera de completeYears', () => {
  const site = loadSite('chiquimula');
  const rain = site.rain.ERA5.slice();
  assert.equal(completeYears(site.dates, rain).length, 24);
  rain[site.dates.indexOf('2009-08-10')] = null;
  const ys = completeYears(site.dates, rain);
  assert.equal(ys.includes(2009), false);
  assert.equal(ys.length, 23);
  rain[site.dates.indexOf('2010-02-10')] = null; // el 10 feb 2010 también cae en el año agrícola 2009
  assert.equal(completeYears(site.dates, rain).length, 23);
});

test('simulateSowing con la regla de inicio y el desfase de historical_check coincide con simulateResow del repositorio (ERA5, Zacapa y Chiquimula)', () => {
  const crops = loadAllCrops();
  const pts = Object.fromEntries(loadPoints().map((p) => [p.id, p]));
  for (const id of ['chiquimula', 'zacapa']) {
    const site = loadSite(id); const soil = soilOfPoint(pts[id]);
    for (const year of [2009, 2015]) for (const lossDay of [30, 60]) {
      const off = resowOffset(lossDay);
      const mine = simulateSowing({ bundle: site.bundle, et0: site.et0, rain: site.rain.ERA5, crops, soil, year, cropId: 'maiz', sowLocal: sowLocalIndex(site.bundle, site.rain.ERA5, year, 'onset', off) });
      const ref = simulateResow({ bundle: site.bundle, et0: site.et0, crops, texture: soil, year, cropId: 'maiz', offsetDays: off });
      close(mine.relYield, ref.relYield, 1e-12);
      assert.equal(mine.cycleCompletes, ref.executable);
      assert.equal(mine.sowDate, ref.sowDate);
    }
  }
});

test('siembra el 15 ago: la fecha de siembra es la pedida y la lluvia usada es la de la fuente', () => {
  const crops = loadAllCrops();
  const site = loadSite('zacapa');
  const wet = simulateSowing({ bundle: site.bundle, et0: site.et0, rain: site.rain.ERA5, crops, soil: 'loam', year: 2009, cropId: 'frijol', sowLocal: sowLocalIndex(site.bundle, site.rain.ERA5, 2009, '08-15') });
  assert.equal(wet.sowDate, '2009-08-15');
  const dry = simulateSowing({ bundle: site.bundle, et0: site.et0, rain: site.rain.ERA5.map(() => 0), crops, soil: 'loam', year: 2009, cropId: 'frijol', sowLocal: sowLocalIndex(site.bundle, site.rain.ERA5, 2009, '08-15') });
  assert.ok(dry.relYield < wet.relYield);
  assert.ok(dry.stressDays > wet.stressDays);
});

import { chooseRainSource } from '../scripts/compare/rain_sources_lib.mjs';
test('regla preregistrada de la fuente: reemplaza a ERA5 solo con +0.05 de AUC', () => {
  assert.equal(chooseRainSource({ ERA5: 0.60, POWER: 0.65, CHIRPS: 0.62 }).recommended, 'POWER'); // 0.65 - 0.60 = 0.05 justo
  const r = chooseRainSource({ ERA5: 0.60, POWER: 0.64, CHIRPS: 0.62 });
  assert.equal(r.recommended, 'ERA5'); assert.equal(r.switched, false); assert.equal(r.best, 'POWER');
  assert.equal(chooseRainSource({ ERA5: 0.7, POWER: 0.5, CHIRPS: 0.6 }).recommended, 'ERA5');
  assert.equal(chooseRainSource({ ERA5: 0.6, POWER: 0.6, CHIRPS: 0.6 }).recommended, 'ERA5'); // empate: ERA5
  assert.equal(chooseRainSource({ ERA5: 0.5, POWER: null, CHIRPS: 0.8 }).recommended, 'CHIRPS');
  assert.equal(chooseRainSource({ ERA5: null, POWER: 0.9, CHIRPS: 0.8 }).recommended, 'ERA5');
});

import { buildUnits, normDept, hitSummary } from '../scripts/compare/real_events_check.mjs';
test('buildUnits con datos inventados, contado a mano', () => {
  const points = [{ id: 'p1', department: 'Zacapa' }, { id: 'p2', department: 'Zacapa' }, { id: 'p3', department: 'Jutiapa' }, { id: 'p4', department: 'Santa Rosa' }];
  const file = {
    events: [
      { year: 2012, season: 'primera', departments: ['Zacapa', 'Jutiapa'], crop: 'ambos' }, // 1 calendario x 2 cultivos x 3 puntos = 6
      { year: 2014, season: 'ambas', departments: ['zacapa'], crop: 'maiz' }, // 2 calendarios x 1 cultivo x 2 puntos = 4
      { year: 2001, season: 'primera', departments: [], crop: 'ambos' }, // sin departamentos: no se puntúa
      { year: 2020, season: 'primera', departments: ['Quiché'], crop: 'maiz' }, // departamento sin puntos: no se puntúa
    ],
    noEventYears: [{ year: 2015, season: 'postrera' }, { year: 2017, season: 'ambas' }],
  };
  const u = buildUnits(file, points);
  assert.equal(u.eventUnits.length, 10);
  assert.deepEqual(u.skippedEvents.map((s) => s.id), ['E03', 'E04']);
  assert.deepEqual(u.siteSets['postrera|maiz'].sort(), ['p1', 'p2']);
  assert.equal(u.siteSets['postrera|frijol'], undefined);
  // controles noEvent: 2015 postrera maiz en p1,p2 (2) + 2017 ambas: primera maiz 3, primera frijol 3, postrera maiz 2 (8)
  assert.equal(u.noEventUnits.length, 10);
  // otros años: primera maiz sin {2001, 2012, 2014, 2020} = 20 x 3; primera frijol sin {2001, 2012} (el evento 2020 es solo de maíz) = 22 x 3; postrera maiz sin {2014} = 23 x 2
  assert.equal(u.otherUnits.length, 60 + 66 + 46);
  assert.equal(u.eventUnits.some((x) => x.point === 'p4'), false);
  assert.equal(normDept('Quiché'), 'quiche');
  assert.deepEqual(hitSummary([{ hit: true }, { hit: false }, { hit: true }, { hit: false }]), { n: 4, hits: 2, hitRate: 0.5 });
});
