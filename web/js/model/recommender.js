// Red que recomienda (Tarea 31): puntúa cada acción tras perder el maíz. Puro (sin E/S): corre en Node y en el navegador.
// Puntaje de una acción = puntaje de la regla (1 si es la acción de la regla, 0 si no) + tanh(corrección de la red); gana el mayor.
// La red es un embudo entradas → 64 → 32 → 16 → 1 con tanh y capa de salida en cero: al inicio recomienda exactamente lo que la regla.
// Entradas: solo lo que se sabe el día de la decisión (el día de la pérdida, con el clima de ese día incluido). No hay finanzas ni historial de plagas o abonos: el proyecto no tiene esos datos.
import { buildPhase, kcOnDay } from './phenology.js';
import { resolveMainSowIdx, dayOfYear } from './simulate.js';
import { resolveSoil } from './soil.js';
import { mulberry32 } from './emulator.js';

export const ACTION_IDS = ['maiz', 'frijol', 'ajonjoli', 'papa', 'cebolla', 'brocoli', 'lechuga', 'fallow'];
export const FALLOW_ID = 'fallow';
export const PRIORITY_VALUES = { typical: 0, cautious: 1 }; // 0 = rendir más en un año típico, 1 = no perder en un año malo
export const DRY_DAY_MM = 1; // día seco: lluvia < 1 mm (el mismo umbral de las características del emulador)
export const STORE_CAP_MM = 150; // tope del balance antecedente (el mismo de storeProxy del emulador)

export const STATE_NAMES = [
  'doy', 'daysSinceOnset', 'daysToNov15', 'daysToYearEnd', 'lossDay',
  'rain7', 'et0_7', 'rain28', 'et0_28', 'rainSinceApr1', 'et0SinceApr1',
  'dryspell28', 'tmean28', 'storeProxy', 'soilAWmmPerM', 'cnCrop', 'elevation',
];
export const ACTION_FEATURE_NAMES = [...ACTION_IDS.map((a) => `act_${a}`), 'nominalDays', 'kcMid', 'rootDepthM', 'p', 'ky', 'fitsInYear'];
export const INPUT_NAMES = [...STATE_NAMES, 'priority', ...ACTION_FEATURE_NAMES];
export const N_INPUTS = INPUT_NAMES.length; // 17 + 1 + 14 = 32
export const LAYER_SIZES = [N_INPUTS, 64, 32, 16, 1];

const sumRange = (a, lo, hi) => { let s = 0; for (let i = Math.max(0, lo); i <= hi; i++) s += a[i]; return s; };
function maxDryRun(rain, lo, hi) {
  let best = 0, cur = 0;
  for (let i = Math.max(0, lo); i <= hi; i++) { cur = rain[i] < DRY_DAY_MM ? cur + 1 : 0; if (cur > best) best = cur; }
  return best;
}

/**
 * Balance antecedente acotado hasta el índice `upto` (inclusive), local al año agrícola (0 = 1 de abril):
 * store ← min(150, max(0, store + lluvia − kc(t)·ET0)). kcAt(t) da el Kc de cada día; la misma lógica de storeProxy del emulador.
 */
export function storeProxyAt({ rain, et0, kcAt, upto, cap = STORE_CAP_MM }) {
  let store = 0;
  for (let t = 0; t <= upto; t++) store = Math.min(cap, Math.max(0, store + rain[t] - kcAt(t) * et0[t]));
  return store;
}

/**
 * Kc del día t para el balance antecedente: antes de la siembra, kc.ini del maíz (como en el emulador); de la siembra al día de la pérdida
 * (inclusive), la curva del maíz; después de la pérdida, suelo desnudo = kc.ini del maíz (la regla fijada para el campo sin cultivo).
 */
export function maizeKcAt(maize, phase, sowIdx, lossIdx) {
  return (t) => (t < sowIdx ? maize.kc.ini : t <= lossIdx ? kcOnDay(maize, phase, t) : maize.kc.ini);
}

/**
 * Entradas del estado del lote el día de la decisión (día de la pérdida = siembra + lossDay).
 * Solo lee los datos diarios hasta ese día: se cortan aquí (las fechas completas sirven solo de calendario).
 * Devuelve { state (STATE_NAMES), sowLocal, decisionLocal, startIdx, endLocal }.
 */
export function decisionState({ bundle, et0, year, lossDay, crops, soil }) {
  const startIdx = bundle.dates.indexOf(`${year}-04-01`);
  const endIdx = bundle.dates.indexOf(`${year + 1}-03-31`);
  if (startIdx < 0 || endIdx < 0) throw new Error(`decisionState: agricultural year ${year} is not complete in the bundle`);
  const { idx: sowLocal } = resolveMainSowIdx({ ...bundle, rain: bundle.rain.slice(0, startIdx + 80) }, year, 0); // el inicio de lluvias solo mira hasta el 15 de junio
  const dAbs = startIdx + sowLocal + lossDay;
  if (dAbs > endIdx) throw new Error('decisionState: the decision day is after the end of the agricultural year');
  const cut = (a) => a.slice(0, dAbs + 1); // nada posterior al día de la decisión
  const rainAll = cut(bundle.rain), et0All = cut(et0);
  const tmeanAll = cut(bundle.tmax).map((t, i) => (t + bundle.tmin[i]) / 2);
  const rain = rainAll.slice(startIdx), e0 = et0All.slice(startIdx), tmean = tmeanAll.slice(startIdx); // locales al año agrícola
  const d = dAbs - startIdx;
  const maize = crops.get('maiz');
  const phase = buildPhase(maize, sowLocal, tmean);
  const s = resolveSoil(soil);
  const dateD = bundle.dates[dAbs];
  const nov15 = Date.parse(`${dateD.slice(0, 4)}-11-15`);
  const state = [
    dayOfYear(dateD), d - sowLocal, Math.round((nov15 - Date.parse(dateD)) / 864e5), endIdx - dAbs, lossDay,
    sumRange(rain, d - 6, d), sumRange(e0, d - 6, d), sumRange(rain, d - 27, d), sumRange(e0, d - 27, d), sumRange(rain, 0, d), sumRange(e0, 0, d),
    maxDryRun(rain, d - 27, d), sumRange(tmean, d - 27, d) / 28,
    storeProxyAt({ rain, et0: e0, kcAt: maizeKcAt(maize, phase, sowLocal, d), upto: d }),
    1000 * (s.thetaFC - s.thetaWP), s.cn.crop, bundle.elevation,
  ];
  return { state, sowLocal, decisionLocal: d, startIdx, endLocal: endIdx - startIdx };
}

/** Entradas de una acción: one-hot de 8, ciclo nominal (días), Kc medio, profundidad de raíz, p, Ky y si el ciclo nominal cabe antes del fin del año agrícola. Dejar el campo: ceros y "cabe" = 1 (no hay ciclo que completar). */
export function actionFeatures(crops, action, resowLocal, endLocal) {
  const oneHot = ACTION_IDS.map((a) => (a === action ? 1 : 0));
  if (!oneHot.includes(1)) throw new Error(`actionFeatures: unknown action "${action}"`);
  if (action === FALLOW_ID) return [...oneHot, 0, 0, 0, 0, 0, 1];
  const c = crops.get(action);
  const nominal = c.days.ini + c.days.dev + c.days.mid + c.days.late;
  return [...oneHot, nominal, c.kc.mid, c.zrMax, c.p, c.ky, resowLocal + nominal <= endLocal ? 1 : 0];
}

/** Las 8 filas de entrada (una por acción) de un caso: [estado, prioridad, acción]. */
export function inputRows(state, priority, actionRows) {
  return actionRows.map((a) => [...state, priority, ...a]);
}

// --- Red: vector plano de parámetros ---
export const paramCount = (sizes = LAYER_SIZES) => sizes.slice(1).reduce((n, o, l) => n + o * sizes[l] + o, 0);

/** Capas ocultas ~ N(0, 1/fan_in), sesgos en 0; la capa de salida (pesos y sesgo) en cero. */
export function initParams(seed, sizes = LAYER_SIZES) {
  const rng = mulberry32(seed);
  const p = new Float64Array(paramCount(sizes));
  let o = 0;
  for (let l = 0; l < sizes.length - 1; l++) {
    const nIn = sizes[l], nOut = sizes[l + 1], last = l === sizes.length - 2;
    for (let i = 0; i < nOut * nIn; i++) p[o + i] = last ? 0 : gaussian(rng) / Math.sqrt(nIn);
    o += nOut * nIn + nOut;
  }
  return p;
}

export function gaussian(rng) {
  const u = 1 - rng(), v = rng();
  return Math.sqrt(-2 * Math.log(u)) * Math.cos(2 * Math.PI * v);
}

/** Salida (corrección, sin tanh) de la red para una entrada ya estandarizada. Capas ocultas tanh, salida lineal. */
export function forward(params, x, sizes = LAYER_SIZES) {
  let a = x, o = 0;
  for (let l = 0; l < sizes.length - 1; l++) {
    const nIn = sizes[l], nOut = sizes[l + 1], last = l === sizes.length - 2;
    const out = new Array(nOut);
    for (let r = 0; r < nOut; r++) {
      let s = params[o + nOut * nIn + r];
      const w = o + r * nIn;
      for (let j = 0; j < nIn; j++) s += params[w + j] * a[j];
      out[r] = last ? s : Math.tanh(s);
    }
    o += nOut * nIn + nOut;
    a = out;
  }
  return a[0];
}

export const standardize = (x, mean, std) => x.map((v, j) => (v - mean[j]) / (std[j] === 0 ? 1 : std[j]));

/** Puntajes de las 8 acciones: 1 para la de la regla + tanh(corrección). rows = entradas crudas por acción (ACTION_IDS). */
export function scoreActions({ params, mean, std }, rows, ruleAction, sizes = LAYER_SIZES) {
  return ACTION_IDS.map((a, i) => (a === ruleAction ? 1 : 0) + Math.tanh(forward(params, standardize(rows[i], mean, std), sizes)));
}

/** Acción con el mayor puntaje; empate (±1e-12) → la de la regla, y entre otras, dejar el campo y luego el orden de ACTION_IDS. */
export function pickAction(scores, ruleAction, eps = 1e-12) {
  const rank = (a) => (a === FALLOW_ID ? -1 : ACTION_IDS.indexOf(a));
  let best = -Infinity;
  for (const s of scores) if (s > best) best = s;
  const tied = ACTION_IDS.filter((_, i) => scores[i] >= best - eps);
  if (tied.includes(ruleAction)) return ruleAction;
  return tied.sort((a, b) => rank(a) - rank(b))[0];
}

export function recommend(net, rows, ruleAction, sizes = LAYER_SIZES) {
  const scores = scoreActions(net, rows, ruleAction, sizes);
  return { action: pickAction(scores, ruleAction), scores };
}

// --- Aptitud por resultado de la decisión ---
/** Prioridad 0 (típico): y. Prioridad 1 (no perder en un año malo): y − max(0, 0.5 − y). */
export const outcomeValue = (y, priority) => (priority === 0 ? y : y - Math.max(0, 0.5 - y));

/** Estrategia de evolución (μ, λ) con elitismo, sin retropropagación: ordena por aptitud (mayor mejor; empate por índice), conserva `elite` y llena el resto con hijos de los `parents` mejores. */
export function esNext(population, fitness, rng, { parents = 8, sigma = 0.05, elite = 1 } = {}) {
  const order = fitness.map((f, i) => i).sort((a, b) => fitness[b] - fitness[a] || a - b);
  const top = order.slice(0, parents);
  const next = order.slice(0, elite).map((i) => Float64Array.from(population[i]));
  while (next.length < population.length) {
    const parent = population[top[Math.min(parents - 1, Math.floor(rng() * parents))]];
    const child = new Float64Array(parent.length);
    for (let j = 0; j < parent.length; j++) child[j] = parent[j] + sigma * gaussian(rng);
    next.push(child);
  }
  return { next, order };
}
