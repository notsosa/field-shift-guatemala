// Emulador v3 (Tarea 33): las entradas v2 más entradas nuevas por cultivo sobre la fenología de ese cultivo. Puro (sin E/S); corre en Node y en el navegador.
// Son entradas de una temporada CONOCIDA (retrospectiva), igual que rainYear o caniculaDays de v2: leen el clima diario del año agrícola (1 abril a 31 marzo) del bundle,
// la ET0 calculada de ese clima, los parámetros del cultivo y el día de siembra. NO leen ninguna salida del simulador (ni balance de agua del suelo, ni Ks, ni rendimiento).
// Qué período cubre cada una (índices locales al año agrícola, 0 = 1 de abril; fa..fb = ventana de floración del cultivo según buildPhase/floweringWindow):
//   rainPre30, et0Pre30  lluvia y ET0 de los 30 días ANTES del primer día de la ventana: [fa-30, fa-1] (recortado al 1 de abril)
//   apiFlower            índice de lluvia antecedente (API, decaimiento 0.9 por día) acumulado del 1 de abril hasta fa-1
//   storeProxy           balance corrido acotado a 150 mm del 1 de abril hasta fa-1 con el Kc del propio cultivo (kc.ini antes de sembrar): la lógica de v1, no es el simulador
//   rainFlower           lluvia dentro de la ventana [fa, fb]
//   deficitFlower        déficit climático dentro de la ventana: suma de max(0, kc.mid·ET0 − lluvia) en [fa, fb]
//   cycleDays            días del ciclo simulado por grados-día: de la siembra a la cosecha (si no termina en el año, hasta el 31 de marzo)
//   daysLeft             días que quedan al fin del año agrícola en la siembra: último día − día de siembra
// Para el cultivo B (el que se siembra tras cosechar A, con GAP_DAYS de intervalo) las mismas ocho entradas; si no hay B (o A no termina, o B ya no se puede sembrar en el año) valen 0.
import { buildPhase, kcOnDay } from './phenology.js';
import { floweringWindow, resolveMainSowIdx } from './simulate.js';
import { API_DECAY, STORE_PROXY_CAP_MM } from './emulator.js';
import { FEATURE_NAMES_V2, featuresV2 } from './emulatorV2.js';

export const GAP_DAYS = 14; // intervalo entre la cosecha de A y la siembra de B (el mismo de scripts/compare/succession_lib.mjs)
export const CROP_INPUT_NAMES = ['rainPre30', 'et0Pre30', 'apiFlower', 'storeProxy', 'rainFlower', 'deficitFlower', 'cycleDays', 'daysLeft'];
export const EXTRA_NAMES_V3 = [...CROP_INPUT_NAMES.map((n) => `A_${n}`), ...CROP_INPUT_NAMES.map((n) => `B_${n}`)];
export const FEATURE_NAMES_V3 = [...FEATURE_NAMES_V2, ...EXTRA_NAMES_V3];

const sum = (a, lo, hi) => { let s = 0; for (let i = Math.max(0, lo); i <= hi; i++) s += a[i]; return s; };

/**
 * Las ocho entradas de un cultivo sembrado en sowLocal. rain, et0, tmean: series locales al año agrícola (índice 0 = 1 de abril).
 * Devuelve el arreglo en el orden de CROP_INPUT_NAMES y la fase (para encadenar B).
 */
export function cropSeasonInputs({ crop, sowLocal, rain, et0, tmean }) {
  const last = tmean.length - 1;
  const phase = buildPhase(crop, sowLocal, tmean);
  const [fa, fb] = floweringWindow(phase, last);
  let api = 0, store = 0;
  for (let t = 0; t <= fa - 1; t++) {
    api = API_DECAY * api + rain[t];
    const kc = t < sowLocal ? crop.kc.ini : kcOnDay(crop, phase, t);
    store = Math.min(STORE_PROXY_CAP_MM, Math.max(0, store + rain[t] - kc * et0[t]));
  }
  let deficit = 0;
  for (let i = Math.max(0, fa); i <= fb; i++) deficit += Math.max(0, crop.kc.mid * et0[i] - rain[i]);
  const values = [
    sum(rain, fa - 30, fa - 1), sum(et0, fa - 30, fa - 1), api, store, sum(rain, fa, fb), deficit,
    phase.harvestIdx - sowLocal + 1, last - sowLocal,
  ];
  return { values, phase };
}

/** Las 16 entradas nuevas (A y B) de un caso de sucesión; idB null = sin sucesor (ceros). */
export function extraInputsV3({ bundle, et0, year, offsetDays, idA, idB, crops }) {
  const startIdx = bundle.dates.indexOf(`${year}-04-01`);
  const endIdx = bundle.dates.indexOf(`${year + 1}-03-31`);
  const rain = bundle.rain.slice(startIdx, endIdx + 1);
  const e0 = et0.slice(startIdx, endIdx + 1);
  const tmean = bundle.tmax.slice(startIdx, endIdx + 1).map((t, i) => (t + bundle.tmin[startIdx + i]) / 2);
  const last = tmean.length - 1;
  const sowA = resolveMainSowIdx(bundle, year, offsetDays).idx;
  const a = cropSeasonInputs({ crop: crops.get(idA), sowLocal: sowA, rain, et0: e0, tmean });
  let b = CROP_INPUT_NAMES.map(() => 0);
  if (idB != null) {
    const sowB = a.phase.harvestIdx + 1 + GAP_DAYS;
    if (!a.phase.cycleIncomplete && sowB <= last) b = cropSeasonInputs({ crop: crops.get(idB), sowLocal: sowB, rain, et0: e0, tmean }).values;
  }
  return [...a.values, ...b];
}

/** Entradas v3 = entradas v2 + las 16 nuevas. Mismos argumentos que featuresV2 más `crops`. */
export function featuresV3(args) {
  return [...featuresV2(args), ...extraInputsV3(args)];
}
