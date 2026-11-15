import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { loadCrops } from '../web/js/model/crops.js';
import { computeEt0Series, runSequence } from '../web/js/model/simulate.js';
import { simulateDays } from '../web/js/model/waterBalance.js';
import { buildPerennialPhase } from '../web/js/model/phenology.js';
import { plotAdjust, floweringFor, simulateCoffee, stressOver, coffeeYearMeasures } from '../web/js/model/coffee.js';

const read = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));
const crops = loadCrops(read('../web/data/crops.json'));
const cafe = crops.get('cafe');
const isoDays = (from, n) => Array.from({ length: n }, (_, i) => new Date(Date.UTC(...from) + i * 864e5).toISOString().slice(0, 10));
const near = (a, b) => assert.ok(Math.abs(a - b) < 1e-12, `${a} vs ${b}`);

test('café: valores FAO-56 y sin Ky', () => {
  assert.deepEqual(cafe.kc, { ini: 0.9, mid: 0.95, end: 0.95 });
  assert.deepEqual(cafe.kcWeedCover, { ini: 1.05, mid: 1.1, end: 1.1 });
  assert.equal(cafe.zrMax, 1.2); assert.equal(cafe.p, 0.4); assert.equal(cafe.ky, null); assert.equal(cafe.perennial, true);
});
test('cultivos existentes: rotaciones idénticas en un piloto (hash fijado antes del cambio)', () => {
  const seq = read('../web/data/sequences.json');
  const bundle = read('../web/data/snapshots/jutiapa.json'); const et0 = computeEt0Series(bundle);
  const out = {};
  for (const id of Object.keys(seq)) for (const irrigation of ['none', 'limited', 'full']) out[`${id}|${irrigation}`] = runSequence({ sequence: seq[id], bundle, et0, crops, texture: 'loam', slopeClass: 'moderate', irrigation });
  assert.equal(createHash('sha256').update(JSON.stringify(out)).digest('hex'), 'f9ac5ec7fa456bc2b15ee0fcb24e65c9dee125ba37299ea5ac13eca0dc45ffdd');
});
test('perenne: Kc 0.95 todo el año y raíces constantes de 1.2 m (TAW loam = 1000·0.13·1.2 = 156 mm)', () => {
  const sim = simulateDays({ rain: [0, 0, 0], et0: [4, 4, 4], phases: [buildPerennialPhase(cafe, 3)], crops, texture: 'loam', slopeClass: 'flat', irrigation: 'none', drInit: 0 });
  assert.deepEqual(sim.kc, [0.95, 0.95, 0.95]); assert.deepEqual(sim.zr, [1.2, 1.2, 1.2]);
  near(sim.taw[0], 156);
  near(sim.dr[2], 3 * 3.8); // 3 días × 0.95 × 4 mm
});
test('sombra: tabla diaria del ajuste, a mano', () => {
  const dates = ['2020-07-15', '2020-01-15'];
  assert.equal(plotAdjust(dates, 'none', 'evergreen'), null);
  assert.deepEqual(plotAdjust(dates, 'trees', 'evergreen'), { reduce: [0.52, 0], add: [0.2, 0.2] });
  assert.deepEqual(plotAdjust(dates, 'trees', 'deciduous'), { reduce: [0.52, 0], add: [1.2, 0.06] });
  assert.throws(() => plotAdjust(dates, 'trees', 'palm'));
});
test('sombra: efecto 1 (−0.52 mm en lluvias, no bajo cero) y efecto 2 (transpiración de árboles) en la demanda', () => {
  const run = (date, et0, shade, treeType) => simulateCoffee({ dates: [date], rain: [0], et0: [et0], crops, texture: 'loam', shade, treeType, drInit: 0 }).etc[0];
  near(run('2020-07-15', 4, 'none'), 3.8);
  near(run('2020-07-15', 4, 'trees', 'evergreen'), 3.8 - 0.52 + 0.2);
  near(run('2020-07-15', 4, 'trees', 'deciduous'), 3.8 - 0.52 + 1.2);
  near(run('2020-01-15', 4, 'trees', 'evergreen'), 3.8 + 0.2); // estación seca: sin recorte de evaporación
  near(run('2020-01-15', 4, 'trees', 'deciduous'), 3.8 + 0.06);
  near(run('2020-07-15', 0.4, 'trees', 'evergreen'), 0.2); // 0.38 − 0.52 < 0 → 0, luego + 0.2
});
test('floración: primer día ≥ 10 mm entre el 15 feb y el 30 abr, más 9 días', () => {
  const dates = isoDays([2021, 0, 1], 365); const rain = Array(365).fill(0);
  rain[dates.indexOf('2021-02-14')] = 50; // fuera de la ventana
  rain[dates.indexOf('2021-03-03')] = 9.9; // < 10
  rain[dates.indexOf('2021-03-10')] = 10; rain[dates.indexOf('2021-04-01')] = 40;
  const f = floweringFor(dates, rain, 2021);
  assert.equal(dates[f.triggerIdx], '2021-03-10'); assert.equal(dates[f.idx], '2021-03-19'); assert.equal(f.noTrigger, false);
  const g = floweringFor(dates, Array(365).fill(0), 2021);
  assert.equal(dates[g.idx], '2021-05-09'); assert.equal(g.noTrigger, true); assert.equal(g.triggerIdx, null);
});
test('medidas de estrés: días con Ks<1 y ETa/ETc por ventana, a mano', () => {
  const sim = { ks: [1, 0.5, 0.8, 1], eta: [4, 2, 3, 4], etc: [4, 4, 4, 4] };
  const m = stressOver(sim, 1, 3);
  assert.equal(m.stressDays, 2); assert.equal(m.n, 3); near(m.etaOverEtc, 9 / 12);
});
test('medidas del año cafetalero: ventanas 0–90 y 91–120 tras la floración y nov–abr', () => {
  const dates = isoDays([2020, 10, 1], 365 + 31);
  const n = dates.length; const rain = Array(n).fill(0);
  rain[dates.indexOf('2021-03-01')] = 20; // floración 10 mar 2021
  const ks = Array(n).fill(1); const fl = dates.indexOf('2021-03-10');
  ks[fl] = 0.9; ks[fl + 90] = 0.9; ks[fl + 91] = 0.9; ks[fl + 120] = 0.9; ks[fl + 121] = 0.9;
  const sim = { ks, eta: Array(n).fill(1), etc: Array(n).fill(2) };
  const r = coffeeYearMeasures({ sim, dates, rain, year: 2020 });
  assert.equal(r.floweringDate, '2021-03-10'); assert.equal(r.fruitSet.stressDays, 2); assert.equal(r.fruitSet.n, 91);
  assert.equal(r.grainFill.stressDays, 2); assert.equal(r.grainFill.n, 30); assert.equal(r.drySeason.stressDays, 1); assert.equal(r.drySeason.n, 181);
  near(r.fruitSet.etaOverEtc, 0.5);
});

// --- Parte B: avisos ---
import { siteHistory, royaNotice, minadorNotice, antracnosisNotice, abonoNotice, monthMedians } from '../web/js/model/coffee.js';
const src = read('../web/data/coffee_sources.json').sources;
const mk = () => {
  const dates = isoDays([2019, 0, 1], 1095); // 2019-01-01 .. 2021-12-31
  const n = dates.length;
  return { dates, n, tmax: Array(n).fill(30), tmin: Array(n).fill(18), rain: Array(n).fill(0) };
};
const setRange = (w, from, to, f) => { for (let i = w.dates.indexOf(from); i <= w.dates.indexOf(to); i++) f(i); };

test('mediana mensual del sitio solo con años anteriores', () => {
  const w = mk();
  w.tmax[w.dates.indexOf('2021-08-05')] = 99; // 2021 no entra
  const h = siteHistory(w.dates, w.tmax, w.tmin, 2021);
  assert.equal(h.dtrMedian[8], 12); assert.equal(h.tmaxMedian[8], 30);
  assert.equal(monthMedians([ '2019-03-01', '2019-03-02', '2020-03-01', '2020-03-02'], [1, 2, 3, 10], 2021)[3], 2.5);
});
test('roya: favorable con media 23 °C y rango 10 < mediana 12; latencia de unas 5 semanas; fuente existente', () => {
  const w = mk(); const h = siteHistory(w.dates, w.tmax, w.tmin, 2021);
  setRange(w, '2021-08-01', '2021-08-14', (i) => { w.tmax[i] = 28; w.tmin[i] = 18; });
  const r = royaNotice({ ...w, t: w.dates.indexOf('2021-08-14'), history: h });
  assert.equal(r.level, 'favorable'); near(r.triggers.meanTemp14, 23); near(r.triggers.dtr14, 10); near(r.triggers.dtrMedianMonth, 12);
  assert.equal(r.latent.text, 'los síntomas aparecerían en unas 5 semanas'); assert.deepEqual(r.latent.days, [31, 37]);
  assert.ok(src[r.sourceKey] && src[r.latentSourceKey]);
});
test('roya: rango diurno normal → solo posible; media fuera de 16–28 o fuera de jun–dic → ninguno', () => {
  const w = mk(); const h = siteHistory(w.dates, w.tmax, w.tmin, 2021);
  setRange(w, '2021-08-01', '2021-08-14', (i) => { w.tmax[i] = 30; w.tmin[i] = 16; }); // media 23, rango 14 > 12
  assert.equal(royaNotice({ ...w, t: w.dates.indexOf('2021-08-14'), history: h }).level, 'possible');
  setRange(w, '2021-08-01', '2021-08-14', (i) => { w.tmax[i] = 36; w.tmin[i] = 24; }); // media 30
  assert.equal(royaNotice({ ...w, t: w.dates.indexOf('2021-08-14'), history: h }).level, 'none');
  setRange(w, '2021-04-18', '2021-05-01', (i) => { w.tmax[i] = 28; w.tmin[i] = 18; });
  assert.equal(royaNotice({ ...w, t: w.dates.indexOf('2021-05-01'), history: h }).level, 'none');
});
test('minador: 28 días con < 10 mm y tmax sobre la mediana → probable; 10 mm o tmax normal → ninguno', () => {
  const w = mk(); const h = siteHistory(w.dates, w.tmax, w.tmin, 2021);
  setRange(w, '2021-02-01', '2021-02-28', (i) => { w.tmax[i] = 33; });
  const t = w.dates.indexOf('2021-02-28');
  const a = minadorNotice({ ...w, t, history: h });
  assert.equal(a.level, 'probable'); near(a.triggers.tmax28, 33); near(a.triggers.rain28, 0);
  w.rain[t - 3] = 10;
  assert.equal(minadorNotice({ ...w, t, history: h }).level, 'none');
  w.rain[t - 3] = 9.9; setRange(w, '2021-02-01', '2021-02-28', (i) => { w.tmax[i] = 30; });
  assert.equal(minadorNotice({ ...w, t, history: h }).level, 'none'); // tmax igual a la mediana, no mayor
});
test('antracnosis: más de la mitad de 28 días con Ks<1, o roya favorable en los 60 días previos', () => {
  const w = mk(); const h = siteHistory(w.dates, w.tmax, w.tmin, 2021);
  const t = w.dates.indexOf('2021-08-20'); const ks = Array(w.n).fill(1);
  assert.equal(antracnosisNotice({ ...w, ks, t, history: h }).level, 'none');
  for (let i = t - 13; i <= t; i++) ks[i] = 0.9; // 14 de 28 = la mitad exacta: no es "más de la mitad"
  assert.equal(antracnosisNotice({ ...w, ks, t, history: h }).level, 'none');
  ks[t - 14] = 0.9; // 15 de 28
  const a = antracnosisNotice({ ...w, ks, t, history: h });
  assert.equal(a.level, 'notice'); assert.equal(a.triggers.stressDays28, 15); assert.equal(a.triggers.byStress, true);
  const ks2 = Array(w.n).fill(1);
  setRange(w, '2021-07-10', '2021-07-23', (i) => { w.tmax[i] = 28; w.tmin[i] = 18; }); // primer día favorable: 10 de julio (13 días de 24 °C y rango 12 más uno de 23 °C y 10: 11.86 < 12)
  const b = antracnosisNotice({ ...w, ks: ks2, t, history: h });
  assert.equal(b.level, 'notice'); assert.equal(b.triggers.byRoya, true); assert.equal(b.triggers.royaFavorableDay, '2021-07-10');
  assert.ok(src[b.sourceKey].confidence.includes('Patulul'));
});
test('abono: ahora solo en ventana y con suelo húmedo (Dr < RAW y ≥ 10 mm en 7 días); si no, en espera', () => {
  const w = mk(); const t = w.dates.indexOf('2021-06-15'); w.rain[t - 2] = 10;
  const base = { dates: w.dates, rain: w.rain, t, taw: 156, p: 0.4 }; // RAW = 62.4
  assert.equal(abonoNotice({ ...base, dr: 62.3 }).level, 'apply_now');
  assert.equal(abonoNotice({ ...base, dr: 62.5 }).level, 'wait'); // sobre RAW (62.4)
  const dry = abonoNotice({ ...base, dr: 10, rain: Array(w.n).fill(0) });
  assert.equal(dry.level, 'wait'); assert.equal(dry.sourceKey, 'abono_suelo_seco'); assert.equal(dry.triggers.moist, false);
  const t2 = w.dates.indexOf('2021-07-15'); w.rain[t2 - 1] = 30; // julio: fuera de ventana
  const out = abonoNotice({ dates: w.dates, rain: w.rain, t: t2, dr: 0, taw: 156, p: 0.4 });
  assert.equal(out.level, 'wait'); assert.equal(out.triggers.inWindow, false);
  assert.equal(src.abono_suelo_seco.text, 'No aplique abono si el suelo está completamente seco, porque la planta no lo absorbe.');
});
test('avisos: alterar datos posteriores a hoy no cambia nada', () => {
  const w = mk(); const t = w.dates.indexOf('2021-08-14'); const h = siteHistory(w.dates, w.tmax, w.tmin, 2021);
  setRange(w, '2021-08-01', '2021-08-14', (i) => { w.tmax[i] = 28; w.tmin[i] = 18; });
  const ks = Array(w.n).fill(1);
  const all = (x) => JSON.stringify([royaNotice({ ...x, t, history: h }), minadorNotice({ ...x, t, history: h }), antracnosisNotice({ ...x, ks: x.ks ?? ks, t, history: h }), abonoNotice({ dates: x.dates, rain: x.rain, t, dr: 5, taw: 156, p: 0.4 })]);
  const before = all(w);
  const w2 = { ...w, tmax: w.tmax.map((v, i) => (i > t ? 99 : v)), tmin: w.tmin.map((v, i) => (i > t ? -9 : v)), rain: w.rain.map((v, i) => (i > t ? 500 : v)), ks: ks.map((v, i) => (i > t ? 0 : v)) };
  assert.equal(all(w2), before);
});
