// Factores de rendimiento mas alla del agua (Tarea 36). Funciones puras; todo es opt-in (la opcion `factors` por defecto no existe y
// el simulador reproduce exactamente sus resultados de antes). Solo entra al rendimiento un factor con numero publicado leido de la fuente:
//   * calor en la floracion (maiz y tomate): AquaCrop v7.3, Annex I (umbrales 40 C / 10 C, "Estimate") y cap. 3, 3.12.5, Fig. 3.12k (forma logistica, 5 C);
//   * fertilidad del suelo como clase declarada: AquaCrop cap. 2, tabla 2.13a (biomasa relativa por defecto).
// Plagas, dinero y capacidad de resembrar NO cambian el rendimiento (ver PEST_NOTE, MONEY_NOTE y las restricciones de la decision).

/** Umbrales de polinizacion de AquaCrop v7.3 Annex I (todos "Estimate"). Frijol, cafe y los demas cultivos: sin umbral en la fuente. */
export const HEAT_CROPS = {
  maiz: { tmaxThreshold: 40, tminThreshold: 10 },
  tomate: { tmaxThreshold: 40, tminThreshold: 10 },
};
/** Ancho de la caida de 1 a 0 (AquaCrop cap. 3, 3.12.5): 5 C mas alla del umbral. */
export const HEAT_RANGE_C = 5;
/** Pendiente de la logistica normalizada. La fuente da la forma ("logistica") y los extremos (1 en el umbral, 0 a 5 C), no la pendiente: 10 es nuestra eleccion. */
export const LOGISTIC_STEEPNESS = 10;

/** Cultivos con umbral publicado (los unicos con factor de calor). */
export const hasHeatFactor = (cropId) => Object.prototype.hasOwnProperty.call(HEAT_CROPS, cropId);

/**
 * Curva de AquaCrop: de 1 a 0 cuando x (0..1, fraccion del rango de 5 C ya recorrida) crece, logistica con centro en 0.5,
 * normalizada para que valga exactamente 1 en x = 0 y exactamente 0 en x = 1:
 *   s(x) = 1 / (1 + exp(-k (x - 0.5)));  Ks(x) = (s(1) - s(x)) / (s(1) - s(0)),  k = LOGISTIC_STEEPNESS.
 */
export function logisticFall(x, k = LOGISTIC_STEEPNESS) {
  if (x <= 0) return 1;
  if (x >= 1) return 0;
  const s = (v) => 1 / (1 + Math.exp(-k * (v - 0.5)));
  return (s(1) - s(x)) / (s(1) - s(0));
}

/**
 * Coeficiente diario de polinizacion = min(Kspol_h, Kspol_c): Kspol_h baja de 1 a 0 entre Tmax_umbral y Tmax_umbral + 5 C;
 * Kspol_c baja de 1 a 0 entre Tmin_umbral y Tmin_umbral - 5 C. Cultivo sin umbral publicado: 1.
 */
export function heatCoefficientDay(cropId, tmax, tmin, { k = LOGISTIC_STEEPNESS } = {}) {
  const thr = HEAT_CROPS[cropId];
  if (!thr) return 1;
  const hot = logisticFall((tmax - thr.tmaxThreshold) / HEAT_RANGE_C, k);
  const cold = logisticFall((thr.tminThreshold - tmin) / HEAT_RANGE_C, k);
  return Math.min(hot, cold);
}

/**
 * Multiplicador de calor de un ciclo: media del coeficiente diario sobre la ventana de floracion [a, b] (indices inclusivos de tmax/tmin).
 * AquaCrop lo aplica al indice de cosecha; aqui (simplificacion nuestra) la media multiplica el rendimiento relativo limitado por agua.
 * Devuelve { mean, min, daysBelow1, hotDays, coldDays }; sin umbral o ventana vacia: mean 1.
 */
export function heatMultiplier(cropId, tmax, tmin, a, b, opts) {
  if (!hasHeatFactor(cropId) || b < a) return { mean: 1, min: 1, daysBelow1: 0, hotDays: 0, coldDays: 0 };
  const thr = HEAT_CROPS[cropId];
  let sum = 0; let min = 1; let daysBelow1 = 0; let hotDays = 0; let coldDays = 0;
  for (let i = a; i <= b; i++) {
    const c = heatCoefficientDay(cropId, tmax[i], tmin[i], opts);
    sum += c; if (c < min) min = c; if (c < 1) daysBelow1++;
    if (tmax[i] > thr.tmaxThreshold) hotDays++; // dias con Tmax sobre el umbral de calor
    if (tmin[i] < thr.tminThreshold) coldDays++; // dias con Tmin bajo el umbral de frio
  }
  return { mean: sum / (b - a + 1), min, daysBelow1, hotDays, coldDays };
}

/** AquaCrop cap. 2, tabla 2.13a: biomasa relativa por defecto por clase de fertilidad (genericos, no calibrados para Guatemala). */
export const FERTILITY_CLASSES = { 'near-optimal': 0.8, moderate: 0.6, 'about-half': 0.5, poor: 0.4, 'very-poor': 0.25 };
/** Multiplicador de la clase declarada; null/undefined = "no declarada" = 1. Una clase desconocida es un error (no se inventa). */
export function fertilityMultiplier(fertilityClass) {
  if (fertilityClass == null) return 1;
  if (!Object.prototype.hasOwnProperty.call(FERTILITY_CLASSES, fertilityClass)) throw new Error(`Clase de fertilidad desconocida: ${fertilityClass}`);
  return FERTILITY_CLASSES[fertilityClass];
}

/**
 * Sensibilidad (NO se usa en decisiones; apagada por defecto): Lobell et al. 2011, Nature Climate Change 1:42-45 (maiz, Africa, >20 000 ensayos):
 * cada grado-dia sobre 30 C baja el rendimiento 1 % con lluvia optima y 1.7 % bajo sequia. Es un proxy de otro continente.
 * Aqui los grados-dia sobre 30 C se aproximan por dia como max(0, Tmax - 30) sobre el ciclo (la fuente usa temperaturas horarias interpoladas).
 */
export const LOBELL = { perDegreeDayOptimal: 0.01, perDegreeDayDrought: 0.017, thresholdC: 30 };
export function degreeDaysAbove(tmax, lo, hi, thr = LOBELL.thresholdC) {
  let dd = 0;
  for (let i = lo; i <= hi; i++) dd += Math.max(0, tmax[i] - thr);
  return dd;
}
export const lobellMultiplier = (degreeDays, drought) => Math.max(0, 1 - degreeDays * (drought ? LOBELL.perDegreeDayDrought : LOBELL.perDegreeDayOptimal));

/**
 * Aplica los factores a un rendimiento relativo por agua. factors = { heat: true|false|{k}, fertilityClass: clave|null }.
 * Devuelve { relYield, heat, fertility } con relYield = agua x calor x fertilidad (acotado a [0,1]).
 */
export function applyFactors({ cropId, relYield, tmax, tmin, flowerIdx, factors }) {
  if (!factors) return { relYield, heat: null, fertility: 1 };
  const heat = factors.heat ? heatMultiplier(cropId, tmax, tmin, flowerIdx[0], flowerIdx[1], typeof factors.heat === 'object' ? factors.heat : undefined) : null;
  const fertility = fertilityMultiplier(factors.fertilityClass ?? null);
  return { relYield: Math.min(1, Math.max(0, relYield * (heat ? heat.mean : 1) * fertility)), heat, fertility };
}

/** Plagas: ninguna fuente da una funcion de dano; no cambian el rendimiento. El nivel observado por el agricultor es un dato declarado que se muestra. */
export const PEST_LEVELS = ['none', 'low', 'medium', 'high'];
export const PEST_NOTE = 'No source gives a damage function; pests do not change the yield. The 16 % fall of Central American coffee production in 2013 (Avelino et al. 2015) is a regional aggregate with uncertain estimates and is context only.';
export const MONEY_NOTE = 'MAGA 2023 prices are wholesale (La Terminal, zona 4), not farm-gate; there are no production costs and no usable attainable yields, so margin is not computed.';

/** Restricciones declaradas del agricultor (no son predicciones): si puede resembrar y si tiene riego (y de que tipo). */
export function normalizeConstraints(c = {}) {
  const canResow = c.canResow !== false; // por defecto se puede
  const hasIrrigation = c.hasIrrigation === true;
  return { canResow, hasIrrigation, irrigationType: hasIrrigation ? (c.irrigationType ?? null) : null, pestLevel: c.pestLevel ?? null };
}
