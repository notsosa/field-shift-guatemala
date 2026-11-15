// Núcleo del emulador: features, ELM (sin backprop), forward de la red embudo y métricas.
// Sin dependencias externas (solo el propio modelo); corre en Node y en el navegador.
import { buildPhase, kcOnDay } from './phenology.js';
import { resolveMainSowIdx, agriculturalYears, dayOfYear, floweringWindow } from './simulate.js';

export const CLIMATE_FEATURE_NAMES = ['rainMJJ', 'rainASO', 'rainYear', 'caniculaDays', 'et0MeanMO', 'tmeanMO', 'elevation'];
// Candidatas de agua antecedente a la floración (Tarea 19); solo las de ANTECEDENT_SELECTED entran a la red.
export const ANTECEDENT_CANDIDATES = ['rainPre30', 'drySpellPre20', 'balancePre30', 'balanceSeason', 'rainPreSow30', 'apiFlower', 'storeProxy'];
export const API_DECAY = 0.9;
export const STORE_PROXY_CAP_MM = 150;
// Elegidas con el cribado en validación (scripts/emulator/feature_screening.json).
export const ANTECEDENT_SELECTED = ['apiFlower', 'storeProxy'];
// Fenología del cultivo principal (maíz, fase 0 de toda secuencia) sembrado con la regla de inicio + desfase.
export const PHENO_FEATURE_NAMES = ['sowDoy', 'rainFlower', 'drySpellFlower', 'deficitFlower', ...ANTECEDENT_SELECTED];

const TEXTURES = ['sand', 'loam', 'clay'];
const SLOPES = ['flat', 'moderate', 'steep'];
const IRRIGATIONS = ['none', 'limited', 'full'];
const SEQUENCES = ['actual', 'proteger', 'extra_secano', 'extra_riego'];

export const FEATURE_NAMES = [
  ...CLIMATE_FEATURE_NAMES,
  ...PHENO_FEATURE_NAMES,
  ...TEXTURES.map((t) => `texture_${t}`),
  ...SLOPES.map((s) => `slope_${s}`),
  ...IRRIGATIONS.map((i) => `irrigation_${i}`),
  ...SEQUENCES.map((s) => `sequence_${s}`),
  'sowOffset30',
];

export const TARGET_NAMES = ['waterIndex', 'ksFlowerMain', 'bareFrac'];

// Índices [lo, hi] (inclusivos) de las fechas dentro de [from, to]; dates ordenadas.
function windowIdx(dates, from, to) {
  let lo = -1, hi = -1;
  for (let i = 0; i < dates.length; i++) {
    if (dates[i] >= from && lo < 0) lo = i;
    if (dates[i] <= to) hi = i;
  }
  return lo < 0 || hi < lo ? null : [lo, hi];
}

const sum = (a, [lo, hi]) => { let s = 0; for (let i = lo; i <= hi; i++) s += a[i]; return s; };
const mean = (a, w) => sum(a, w) / (w[1] - w[0] + 1);
function maxDry(rain, [lo, hi]) {
  let best = 0, cur = 0;
  for (let i = lo; i <= hi; i++) { cur = rain[i] < 1 ? cur + 1 : 0; if (cur > best) best = cur; }
  return best;
}

export function climateFeatures(bundle, year, et0) {
  const { dates, rain, tmax, tmin } = bundle;
  const y = year, y1 = year + 1;
  const ag = windowIdx(dates, `${y}-04-01`, `${y1}-03-31`);
  if (!ag || dates[ag[0]] !== `${y}-04-01` || dates[ag[1]] !== `${y1}-03-31` || ag[1] - ag[0] + 1 < 365) {
    throw new Error(`climateFeatures: agricultural year ${year} is not complete in bundle.dates`);
  }
  const w = (a, b) => windowIdx(dates, a, b);
  const mo = w(`${y}-05-01`, `${y}-10-31`);
  const tmean = tmax.map((t, i) => (t + tmin[i]) / 2);
  return [
    sum(rain, w(`${y}-05-01`, `${y}-07-31`)),
    sum(rain, w(`${y}-08-01`, `${y}-10-31`)),
    sum(rain, ag),
    maxDry(rain, w(`${y}-07-01`, `${y}-08-31`)),
    mean(et0, mo),
    mean(tmean, mo),
    bundle.elevation,
  ];
}

// Contexto del maíz (fase 0) con la misma siembra y ventana de floración que runSequence (índices locales al año agrícola).
function mainMaizeContext(bundle, year, crops, sowOffsetDays, who) {
  const ag = agriculturalYears(bundle.dates).find((a) => a.year === year);
  if (!ag) throw new Error(`${who}: agricultural year ${year} is not complete in bundle.dates`);
  const { startIdx, endIdx } = ag;
  const maize = crops.get('maiz');
  const tmean = [];
  for (let i = startIdx; i <= endIdx; i++) tmean.push((bundle.tmax[i] + bundle.tmin[i]) / 2);
  const { idx: sowIdx } = resolveMainSowIdx(bundle, year, sowOffsetDays);
  const phase = buildPhase(maize, sowIdx, tmean);
  const [fa, fb] = floweringWindow(phase, tmean.length - 1);
  return { startIdx, endIdx, maize, sowIdx, phase, fa, fb };
}

/** [sowDoy, rainFlower, drySpellFlower, deficitFlower, ...ANTECEDENT_SELECTED] del maíz (fase 0) con la misma siembra y ventana que runSequence. */
export function phenoFeatures(bundle, year, et0, crops, sowOffsetDays) {
  const { startIdx, maize, sowIdx, fa, fb } = mainMaizeContext(bundle, year, crops, sowOffsetDays, 'phenoFeatures');
  const lo = startIdx + fa;
  const hi = startIdx + fb;
  let deficit = 0;
  for (let i = lo; i <= hi; i++) deficit += Math.max(0, maize.kc.mid * et0[i] - bundle.rain[i]);
  const base = [dayOfYear(bundle.dates[startIdx + sowIdx]), sum(bundle.rain, [lo, hi]), maxDry(bundle.rain, [lo, hi]), deficit];
  if (ANTECEDENT_SELECTED.length === 0) return base;
  const cand = antecedentFeatures(bundle, year, et0, crops, sowOffsetDays);
  return [...base, ...ANTECEDENT_SELECTED.map((n) => cand[n])];
}

/**
 * Las siete candidatas de agua antecedente de la Tarea 19 (maíz, fase 0), solo desde el clima, ET0 y los parámetros del maíz:
 * sin balance hídrico simulado y sin suelo, pendiente, riego ni rotación. f0 = primer día de la ventana de floración acotada
 * (la de phenoFeatures), s = día de siembra; las ventanas se recortan al 1 de abril, cuando el simulador arranca con suelo seco.
 * kc_t = kcOnDay desde la siembra y kc.ini antes. storeProxy NO es el simulador: balance corrido con un tope fijo de 150 mm
 * para todo suelo, un indicador del agua almacenada que no conoce el suelo.
 */
export function antecedentFeatures(bundle, year, et0, crops, sowOffsetDays) {
  const { startIdx, endIdx, maize, sowIdx, phase, fa: f0 } = mainMaizeContext(bundle, year, crops, sowOffsetDays, 'antecedentFeatures');
  const rain = bundle.rain.slice(startIdx, endIdx + 1);
  const e = et0.slice(startIdx, endIdx + 1);
  const kc = (t) => (t < sowIdx ? maize.kc.ini : kcOnDay(maize, phase, t));
  const win = (a, b) => [Math.max(0, a), b]; // [a, b] recortado al día 0; vacío si b < a
  const sumW = (a, b, f) => { const [lo, hi] = win(a, b); let t = 0; for (let i = lo; i <= hi; i++) t += f(i); return t; };
  const bal = (i) => rain[i] - kc(i) * e[i];
  const [dlo, dhi] = win(f0 - 20, f0 - 1);
  let api = 0, store = 0;
  for (let t = 0; t <= f0 - 1; t++) {
    api = API_DECAY * api + rain[t];
    store = Math.min(STORE_PROXY_CAP_MM, Math.max(0, store + bal(t)));
  }
  return {
    rainPre30: sumW(f0 - 30, f0 - 1, (i) => rain[i]),
    drySpellPre20: dhi < dlo ? 0 : maxDry(rain, [dlo, dhi]),
    balancePre30: sumW(f0 - 30, f0 - 1, bal),
    balanceSeason: sumW(sowIdx, f0 - 1, bal),
    rainPreSow30: sumW(sowIdx - 30, sowIdx - 1, (i) => rain[i]),
    apiFlower: api,
    storeProxy: store,
  };
}

function oneHot(list, value, what) {
  const i = list.indexOf(value);
  if (i < 0) throw new Error(`encodeFeatures: unknown ${what} "${value}"`);
  return list.map((_, j) => (j === i ? 1 : 0));
}

export function encodeFeatures(climFeats, phenoFeats, { texture, slopeClass, irrigation, sequenceId, sowOffsetDays }) {
  return [
    ...climFeats,
    ...phenoFeats,
    ...oneHot(TEXTURES, texture, 'texture'),
    ...oneHot(SLOPES, slopeClass, 'slopeClass'),
    ...oneHot(IRRIGATIONS, irrigation, 'irrigation'),
    ...oneHot(SEQUENCES, sequenceId, 'sequenceId'),
    sowOffsetDays / 30,
  ];
}

/**
 * relYield efectivo de cada cultivo de comida (ky ≠ null), en orden: un cultivo que no termina
 * dentro del año agrícola (cycleIncomplete) no se cosecha y cuenta como 0. Abonos verdes (null) fuera.
 */
export function cropRelYields(yearResult) {
  return yearResult.crops
    .filter((c) => c.relYield !== null && c.relYield !== undefined)
    .map((c) => (c.cycleIncomplete ? 0 : c.relYield));
}

export function targetsOf(yearResult) {
  const ys = cropRelYields(yearResult);
  if (ys.length === 0) return null;
  return [ys.reduce((a, b) => a + b, 0) / ys.length, yearResult.crops[0].ksFlowerMean, yearResult.bareDaysRainy / 214];
}

export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6D2B79F5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// Cholesky A = L Lᵀ (A n×n row-major, triángulo inferior, destructiva); resuelve A·X = B (B n×m).
function choleskySolve(A, B, n, m) {
  for (let j = 0; j < n; j++) {
    let d = A[j * n + j];
    for (let k = 0; k < j; k++) d -= A[j * n + k] * A[j * n + k];
    if (!(d > 0)) throw new Error('trainELM: Cholesky failed (non-positive pivot)');
    const ljj = Math.sqrt(d);
    A[j * n + j] = ljj;
    for (let i = j + 1; i < n; i++) {
      let s = A[i * n + j];
      for (let k = 0; k < j; k++) s -= A[i * n + k] * A[j * n + k];
      A[i * n + j] = s / ljj;
    }
  }
  for (let c = 0; c < m; c++) {
    for (let i = 0; i < n; i++) { // L z = b
      let s = B[i * m + c];
      for (let k = 0; k < i; k++) s -= A[i * n + k] * B[k * m + c];
      B[i * m + c] = s / A[i * n + i];
    }
    for (let i = n - 1; i >= 0; i--) { // Lᵀ x = z
      let s = B[i * m + c];
      for (let k = i + 1; k < n; k++) s -= A[k * n + i] * B[k * m + c];
      B[i * m + c] = s / A[i * n + i];
    }
  }
  return B;
}

/**
 * ELM: capa oculta tanh con W y b fijos ~ U(−inputScale, inputScale) sobre entradas estandarizadas,
 * y β por mínimos cuadrados con ridge λ. inputScale < 1 deja menos neuronas saturadas.
 */
export function trainELM(X, Y, { hidden = 300, lambda = 1e-2, seed = 42, inputScale = 1 } = {}) {
  const N = X.length, nIn = X[0].length, nOut = Y[0].length;
  const mu = new Float64Array(nIn), sd = new Float64Array(nIn);
  for (let j = 0; j < nIn; j++) {
    let s = 0;
    for (let i = 0; i < N; i++) s += X[i][j];
    mu[j] = s / N;
    let v = 0;
    for (let i = 0; i < N; i++) v += (X[i][j] - mu[j]) ** 2;
    const sdj = Math.sqrt(v / N);
    sd[j] = sdj === 0 ? 1 : sdj;
  }
  // Y se estandariza por columna (sin sesgo de salida, β sobre Y sin centrar fallaría); elmPredict deshace la transformación.
  const yMean = new Float64Array(nOut), yStd = new Float64Array(nOut);
  for (let o = 0; o < nOut; o++) {
    let s = 0;
    for (let i = 0; i < N; i++) s += Y[i][o];
    yMean[o] = s / N;
    let v = 0;
    for (let i = 0; i < N; i++) v += (Y[i][o] - yMean[o]) ** 2;
    const sdo = Math.sqrt(v / N);
    yStd[o] = sdo === 0 ? 1 : sdo;
  }
  const rnd = mulberry32(seed);
  const W = new Float64Array(hidden * nIn);
  for (let i = 0; i < W.length; i++) W[i] = (rnd() * 2 - 1) * inputScale;
  const b = new Float64Array(hidden);
  for (let i = 0; i < hidden; i++) b[i] = (rnd() * 2 - 1) * inputScale;

  const A = new Float64Array(hidden * hidden);
  const B = new Float64Array(hidden * nOut);
  const h = new Float64Array(hidden);
  const z = new Float64Array(nIn);
  for (let r = 0; r < N; r++) { // una fila de H a la vez: H nunca se guarda
    for (let j = 0; j < nIn; j++) z[j] = (X[r][j] - mu[j]) / sd[j];
    for (let k = 0; k < hidden; k++) {
      let s = b[k];
      for (let j = 0; j < nIn; j++) s += W[k * nIn + j] * z[j];
      h[k] = Math.tanh(s);
    }
    for (let p = 0; p < hidden; p++) {
      const hp = h[p];
      for (let q = 0; q <= p; q++) A[p * hidden + q] += hp * h[q];
      for (let o = 0; o < nOut; o++) B[p * nOut + o] += hp * ((Y[r][o] - yMean[o]) / yStd[o]);
    }
  }
  for (let p = 0; p < hidden; p++) A[p * hidden + p] += lambda;
  const beta = choleskySolve(A, B, hidden, nOut);
  return { nIn, nOut, hidden, lambda, seed, inputScale, mean: mu, std: sd, yMean, yStd, W, b, beta };
}

export function elmPredict(model, x) {
  const { nIn, nOut, hidden, mean: mu, std: sd, yMean, yStd, W, b, beta } = model;
  const z = new Float64Array(nIn);
  for (let j = 0; j < nIn; j++) z[j] = (x[j] - mu[j]) / sd[j];
  const y = new Array(nOut).fill(0);
  for (let k = 0; k < hidden; k++) {
    let s = b[k];
    for (let j = 0; j < nIn; j++) s += W[k * nIn + j] * z[j];
    const hk = Math.tanh(s);
    for (let o = 0; o < nOut; o++) y[o] += beta[k * nOut + o] * hk;
  }
  for (let o = 0; o < nOut; o++) y[o] = y[o] * yStd[o] + yMean[o];
  return y;
}

export function mlpPredict(net, x) {
  let a = x.map((v, j) => (v - net.mean[j]) / (net.std[j] === 0 ? 1 : net.std[j]));
  net.layers.forEach((L, li) => {
    const last = li === net.layers.length - 1;
    a = L.W.map((row, o) => {
      let s = L.b[o];
      for (let j = 0; j < row.length; j++) s += row[j] * a[j];
      return last ? s : Math.max(0, s);
    });
  });
  if (net.yMean && net.yStd) a = a.map((v, o) => v * net.yStd[o] + net.yMean[o]);
  if (net.baseline) {
    // Red residual: el valor de la red es y menos la media del grupo de manejo (tabla de entrenamiento); se suma de vuelta.
    // Clave = columnas de manejo a 6 decimales (+ 0 evita "-0"); un grupo no visto usa la media global (fallback).
    const key = net.baseline.cols.map((j) => (x[j] + 0).toFixed(6)).join('|');
    const base = net.baseline.table[key] ?? net.baseline.fallback;
    a = a.map((v, o) => v + base[o]);
  }
  return a;
}

function checkPair(yTrue, yPred) {
  if (yTrue.length !== yPred.length) throw new Error('metrics: length mismatch');
  if (yTrue.length === 0) throw new Error('metrics: empty arrays');
}

export function r2(yTrue, yPred) {
  checkPair(yTrue, yPred);
  const m = yTrue.reduce((a, b) => a + b, 0) / yTrue.length;
  let res = 0, tot = 0;
  for (let i = 0; i < yTrue.length; i++) { res += (yTrue[i] - yPred[i]) ** 2; tot += (yTrue[i] - m) ** 2; }
  if (tot === 0) return res === 0 ? 1 : 0;
  return 1 - res / tot;
}

export function rmse(yTrue, yPred) {
  checkPair(yTrue, yPred);
  let s = 0;
  for (let i = 0; i < yTrue.length; i++) s += (yTrue[i] - yPred[i]) ** 2;
  return Math.sqrt(s / yTrue.length);
}
