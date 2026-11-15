import test from 'node:test'; import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { CROP_INPUT_NAMES, EXTRA_NAMES_V3, FEATURE_NAMES_V3, GAP_DAYS, cropSeasonInputs, extraInputsV3, featuresV3 } from '../web/js/model/emulatorV3.js';
import { FEATURE_NAMES_V2 } from '../web/js/model/emulatorV2.js';
import { GAP_DAYS as SUCCESSION_GAP } from '../scripts/compare/succession_lib.mjs';
import { loadCrops } from '../web/js/model/crops.js';
import { climateFeatures } from '../web/js/model/emulator.js';

const rj = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));
const crops = loadCrops(rj('../web/data/crops.json'));
const near = (a, b, eps = 1e-6) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);
const I = Object.fromEntries(CROP_INPUT_NAMES.map((n, i) => [n, i]));

// Año sintético 2001 (agrícola: 1 abr 2001 = índice local 0 ... 31 mar 2002 = 364): lluvia 30 mm el 3 de mayo (local 32; inicio de lluvias), 10 mm el 1 de junio (61), 5 mm el 2 de junio (62); ET0 = 4; Tmax 30, Tmin 20 (Tmean 25: 15 GDD/día con Tbase 10).
function synth() {
  const dates = [];
  for (let t = Date.UTC(2001, 0, 1); t <= Date.UTC(2002, 11, 31); t += 864e5) dates.push(new Date(t).toISOString().slice(0, 10));
  const n = dates.length;
  const rain = new Array(n).fill(0);
  rain[dates.indexOf('2001-05-03')] = 30; rain[dates.indexOf('2001-06-01')] = 10; rain[dates.indexOf('2001-06-02')] = 5;
  return { dates, rain, tmax: new Array(n).fill(30), tmin: new Array(n).fill(20), tdew: new Array(n).fill(15), rs: new Array(n).fill(20), u2: new Array(n).fill(2), pressure: new Array(n).fill(95), elevation: 500, lat: 14.5 };
}
const flat = (n, v) => new Array(n).fill(v);

// Cultivo corto de prueba: Tbase 10, días ini 4 / dev 4 / mid 10 / late 4, Kc ini .3 mid 1.2. A 15 GDD/día: etapas de 64, 64, 160, 64 GDD.
const SHORT = { id: 'corto', tbase: 10, days: { ini: 4, dev: 4, mid: 10, late: 4 }, kc: { ini: 0.3, mid: 1.2, end: 0.35 } };

function shortSeason(extraRain = {}) {
  const n = 365;
  const rain = flat(n, 0); rain[32] = 30; Object.entries(extraRain).forEach(([i, v]) => { rain[i] = v; });
  return { rain, et0: flat(n, 4), tmean: flat(n, 25) };
}

test('entradas de un cultivo, calculadas a mano (cultivo corto sembrado el día local 32)', () => {
  // fases: ini termina en 32+4 = 36 (15·5 = 75 ≥ 64), dev en 40 (135 ≥ 128), mid en 51 (300 ≥ 288), cosecha en 55 (360 ≥ 352); ventana de floración [41, 41 + round(0.4·(51−40)) − 1] = [41, 44]
  const { rain, et0, tmean } = shortSeason({ 42: 7 });
  const { values: v, phase } = cropSeasonInputs({ crop: SHORT, sowLocal: 32, rain, et0, tmean });
  assert.deepEqual(phase.floweringIdx, [41, 44]);
  assert.equal(phase.harvestIdx, 55);
  near(v[I.rainPre30], 30); // [11, 40] contiene los 30 mm del día 32; los 7 mm del día 42 caen dentro de la ventana, no antes
  near(v[I.et0Pre30], 120); // 30 días × 4 mm
  near(v[I.apiFlower], 30 * 0.9 ** 8); // 30 mm en el día 32, 8 días de decaimiento hasta el día 40 (= fa − 1) → 12.9140163
  // balance acotado: día 32: 30 − 0.3·4 = 28.8; días 33–36 (Kc ini): −1.2 cada uno → 24; días 37–40 (Kc de 0.665625, 0.876563, 1.0875, 1.2): −2.6625 −3.50625 −4.35 −4.8 → 8.68125
  near(v[I.storeProxy], 8.68125);
  near(v[I.rainFlower], 7);
  near(v[I.deficitFlower], 14.4); // días 41, 43, 44: 1.2·4 = 4.8 cada uno; día 42: max(0, 4.8 − 7) = 0
  assert.equal(v[I.cycleDays], 24); // 32..55
  assert.equal(v[I.daysLeft], 332); // 364 − 32
});

test('el balance antecedente tiene tope de 150 mm y piso en 0', () => {
  const { rain, et0, tmean } = shortSeason();
  rain[10] = 400; // un aguacero antes de sembrar: el almacén se queda en 150 y luego baja con Kc.ini·ET0 = 1.2 por día
  const v = cropSeasonInputs({ crop: SHORT, sowLocal: 32, rain, et0, tmean }).values;
  // día 10: 150 (tope). Días 11–31: −1.2 cada uno (21 días) → 124.8; día 32: +30 − 1.2 → 153.6 → tope 150; 33–36: −4.8 → 145.2; 37–40: −15.31875 → 129.88125
  near(v[I.storeProxy], 129.88125);
});

test('nada posterior a la ventana de floración (lluvia, ET0) ni a la cosecha (temperatura) cambia las entradas', () => {
  const s = shortSeason({ 42: 7 });
  const base = cropSeasonInputs({ crop: SHORT, sowLocal: 32, ...s }).values;
  const bad = { rain: s.rain.map((v, i) => (i > 44 ? 999 : v)), et0: s.et0.map((v, i) => (i > 44 ? 999 : v)), tmean: s.tmean.map((v, i) => (i > 55 ? -50 : v)) };
  assert.deepEqual(cropSeasonInputs({ crop: SHORT, sowLocal: 32, ...bad }).values, base);
  // y no hay salida del simulador: ni suelo ni Ks entran (la función no los recibe)
  assert.equal(cropSeasonInputs.length, 1);
});

test('maíz sintético (A) y frijol (B): ocho valores a mano, B en ceros si no hay B', () => {
  const b = synth(); const et0 = flat(b.dates.length, 4);
  const x = extraInputsV3({ bundle: b, et0, year: 2001, offsetDays: 0, idA: 'maiz', idB: null, crops });
  assert.equal(x.length, 16);
  // maíz sembrado el día 32; ini 20·16 = 320 GDD → termina en 53 (15·22 = 330); dev hasta 880 GDD → día 90 (15·59 = 885); mid hasta 1520 → 133; late hasta 1920 → cosecha 159
  // floración [91, 91 + round(0.4·43) − 1] = [91, 107]
  near(x[I.rainPre30], 15); // [61, 90]: 10 + 5 mm
  near(x[I.et0Pre30], 120);
  near(x[I.apiFlower], 30 * 0.9 ** 58 + 10 * 0.9 ** 29 + 5 * 0.9 ** 28); // de las lluvias de los días 32, 61 y 62 al día 90
  near(x[I.storeProxy], 0); // 10.83 mm el día 62 y luego −2.2 a −3.2 mm por día: se agota
  near(x[I.rainFlower], 0);
  near(x[I.deficitFlower], 17 * 4.8); // 17 días × 1.2·4
  assert.equal(x[I.cycleDays], 128); // 32..159
  assert.equal(x[I.daysLeft], 332);
  assert.deepEqual(x.slice(8), flat(8, 0));
  // con B = frijol: siembra el 159 + 1 + 14 = 174; ciclo de 1072 GDD → 72 días (15·72 = 1080 ≥ 1072) → cosecha 245
  const y = extraInputsV3({ bundle: b, et0, year: 2001, offsetDays: 0, idA: 'maiz', idB: 'frijol', crops });
  assert.deepEqual(y.slice(0, 8), x.slice(0, 8));
  assert.equal(y[8 + I.cycleDays], 72);
  assert.equal(y[8 + I.daysLeft], 190); // 364 − 174
  assert.equal(GAP_DAYS, SUCCESSION_GAP);
});

test('B en ceros si A no termina en el año; el desfase mueve la siembra de A', () => {
  const b = synth(); const et0 = flat(b.dates.length, 4);
  // frío: Tmean 14 → 4 GDD/día; el maíz (1920 GDD) no termina en 365 días → ciclo incompleto y no hay B
  const cold = { ...b, tmax: flat(b.dates.length, 18), tmin: flat(b.dates.length, 10) };
  const x = extraInputsV3({ bundle: cold, et0, year: 2001, offsetDays: 0, idA: 'maiz', idB: 'frijol', crops });
  assert.equal(x[I.cycleDays], 364 - 32 + 1); // hasta el 31 de marzo
  assert.deepEqual(x.slice(8), flat(8, 0));
  const late = extraInputsV3({ bundle: b, et0, year: 2001, offsetDays: 15, idA: 'maiz', idB: null, crops });
  assert.equal(late[I.daysLeft], 364 - 47); // siembra 15 días después de la regla (día 32 + 15)
});

test('nada posterior al 31 de marzo del año agrícola entra, y los nombres son 31 + 16', () => {
  const b = synth(); const et0 = flat(b.dates.length, 4);
  const i0 = b.dates.indexOf('2002-04-01');
  const bad = { ...b, rain: b.rain.map((v, i) => (i >= i0 ? 999 : v)), tmax: b.tmax.map((v, i) => (i >= i0 ? -40 : v)) };
  const f = (bundle) => extraInputsV3({ bundle, et0: et0.map((v, i) => (i >= i0 ? 999 : v)), year: 2001, offsetDays: 0, idA: 'frijol', idB: 'lechuga', crops });
  assert.deepEqual(f(bad), f(b));
  assert.equal(EXTRA_NAMES_V3.length, 16);
  assert.equal(FEATURE_NAMES_V3.length, FEATURE_NAMES_V2.length + 16);
  const clim = climateFeatures(b, 2001, et0);
  const full = featuresV3({ bundle: b, et0, year: 2001, climFeats: clim, sowLocal: 32, offsetDays: 0, idA: 'maiz', idB: null, soil: 'loam', crops });
  assert.equal(full.length, FEATURE_NAMES_V3.length);
});
