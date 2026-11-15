// Emulador v2: entradas y salidas para sucesiones de siete cultivos (A y luego B o ninguno). Puro (sin E/S).
import { dayOfYear } from './simulate.js';

export const CROPS_V2 = ['maiz', 'frijol', 'ajonjoli', 'papa', 'cebolla', 'brocoli', 'lechuga'];
export const B_OPTIONS = [...CROPS_V2, 'none'];
export const SOILS_V2 = ['sand', 'loam', 'clay'];
export const OFFSETS_V2 = [0, 15, 30];
export const TARGET_NAMES_V2 = ['relYieldA', 'relYieldB', 'fit'];
export const FEATURE_NAMES_V2 = [
  'rainMJJ', 'rainASO', 'rainYear', 'caniculaDays', 'et0MeanMO', 'tmeanMO', 'elevation',
  'sowDoyA', 'rain0to60', 'et0_0to60', 'rain61to150', 'et0_61to150',
  ...CROPS_V2.map((c) => `A_${c}`), ...B_OPTIONS.map((c) => `B_${c}`), ...SOILS_V2.map((s) => `soil_${s}`), 'offset30',
];

const oneHot = (list, v, what) => {
  const i = list.indexOf(v);
  if (i < 0) throw new Error(`emulatorV2: unknown ${what} "${v}"`);
  return list.map((_, j) => (j === i ? 1 : 0));
};

/** Suma de a sobre los días [from, to] (índices absolutos del bundle), recortada a [lo, hi]. */
const sumWin = (a, from, to, hi) => { let s = 0; for (let i = from; i <= Math.min(to, hi); i++) s += a[i]; return s; };

/**
 * Entradas v2. climFeats = climateFeatures(...) del año; sowLocal = día de siembra de A (índice local al año agrícola, 0 = 1 abr);
 * offsetDays = días después de la regla de inicio (entra como offset/30); idB null = sin sucesor. Solo mira el bundle (lluvia, ET0).
 */
export function featuresV2({ bundle, et0, year, climFeats, sowLocal, offsetDays, idA, idB, soil }) {
  const startIdx = bundle.dates.indexOf(`${year}-04-01`);
  const endIdx = bundle.dates.indexOf(`${year + 1}-03-31`);
  const s = startIdx + sowLocal;
  return [
    ...climFeats,
    dayOfYear(bundle.dates[s]),
    sumWin(bundle.rain, s, s + 59, endIdx), sumWin(et0, s, s + 59, endIdx),
    sumWin(bundle.rain, s + 60, s + 149, endIdx), sumWin(et0, s + 60, s + 149, endIdx),
    ...oneHot(CROPS_V2, idA, 'cultivo A'), ...oneHot(B_OPTIONS, idB ?? 'none', 'cultivo B'), ...oneHot(SOILS_V2, soil, 'suelo'),
    offsetDays / 30,
  ];
}

/** Salidas v2 desde un resultado de simulateSuccessionYear: [relYieldA, relYieldB (0 sin B o incompleto), fit (1 si todo lo sembrado termina y B cabe)]. */
export function targetsV2(res, hasB) {
  const a = res.a.relYield;
  const b = res.b ? res.b.relYield : 0;
  const fit = !res.a.cycleIncomplete && (!hasB || (res.b && !res.b.cycleIncomplete)) ? 1 : 0;
  return [a, b, fit];
}
