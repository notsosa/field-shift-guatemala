// Café (Tarea 32): cultivo perenne, sombra como entrada, avisos con fuente y la decisión de riego. Puro (sin E/S): corre en Node y en el navegador.
// Año cafetalero Y = del 1 de noviembre de Y al 31 de octubre de Y+1 (la floración cae en febrero–mayo de Y+1). Es una convención de este modelo.
// Café no tiene Ky en FAO: no hay estimación de rendimiento, solo medidas de estrés hídrico.
import { buildPerennialPhase } from './phenology.js';
import { simulateDays } from './waterBalance.js';

export const COFFEE_ID = 'cafe';
export const KS_FREE = 1; // día con estrés: Ks < 1
export const FLOWER_LAG_DAYS = 9; // las flores abren 8–10 días después de la lluvia (Anacafe 2020; se usa el centro)
export const FLOWER_RAIN_MM = 10; // lluvias "desde 10 mm" disparan la floración (Anacafe 2014 vía Pons)
export const FLOWER_FALLBACK = '05-09'; // sin lluvia disparadora: 9 de mayo, con noTrigger
export const WINDOWS = { fruitSet: [0, 90], grainFill: [91, 120] }; // días tras la floración (Anacafe, El Cafetal 44)

export const SHADE = {
  reference: 'Padovan et al. 2018, Agric. For. Meteorol. 248:1-14 (Nicaragua, 455 m, copa 57 % de irradiancia; un solo sitio)',
  rainyEvapCutMm: 0.52, // 2.50 − 1.98 mm/día de evaporación del suelo en periodo húmedo; sin diferencia en la seca
  treeUseMm: { evergreen: { rainy: 0.2, dry: 0.2 }, deciduous: { rainy: 1.2, dry: 0.06 } },
};
export const SHADE_TYPES = ['none', 'trees'];
export const TREE_TYPES = ['evergreen', 'deciduous'];

const month = (date) => Number(date.slice(5, 7));
export const isRainySeason = (date) => month(date) >= 5 && month(date) <= 10; // mayo–octubre
export const isDrySeason = (date) => !isRainySeason(date); // noviembre–abril

/** Ajuste del lote por sombra, diario: { reduce[], add[] } (mm/día) para simulateDays; null sin sombra. */
export function plotAdjust(dates, shade, treeType) {
  if (shade === 'none') return null;
  if (shade !== 'trees') throw new Error(`plotAdjust: unknown shade "${shade}"`);
  const use = SHADE.treeUseMm[treeType];
  if (!use) throw new Error(`plotAdjust: unknown tree type "${treeType}"`);
  return {
    reduce: dates.map((d) => (isRainySeason(d) ? SHADE.rainyEvapCutMm : 0)),
    add: dates.map((d) => (isRainySeason(d) ? use.rainy : use.dry)),
  };
}

/** Floración del año calendario F: primer día del 15 feb al 30 abr con lluvia ≥ 10 mm, más 9 días; si no hay, 9 de mayo con noTrigger. */
export function floweringFor(dates, rain, F) {
  const a = dates.indexOf(`${F}-02-15`), b = dates.indexOf(`${F}-04-30`);
  if (a < 0 || b < 0) throw new Error(`floweringFor: dates of ${F} are not in the series`);
  for (let i = a; i <= b; i++) if (rain[i] >= FLOWER_RAIN_MM) return { triggerIdx: i, idx: i + FLOWER_LAG_DAYS, noTrigger: false };
  return { triggerIdx: null, idx: dates.indexOf(`${F}-${FLOWER_FALLBACK}`), noTrigger: true };
}

/** Balance continuo del café sobre toda la serie, sin riego. Devuelve la salida de simulateDays (dr, ds, ks, eta, etc…). */
export function simulateCoffee({ dates, rain, et0, crops, texture, shade = 'none', treeType = 'evergreen', slopeClass = 'flat', drInit, dsInit }) {
  const crop = crops.get(COFFEE_ID);
  return simulateDays({
    rain, et0, phases: [buildPerennialPhase(crop, rain.length)], crops, texture, slopeClass, irrigation: 'none', drInit, dsInit,
    plotAdjust: plotAdjust(dates, shade, treeType) ?? undefined,
  });
}

/** Días con Ks < 1 y ETa/ETc en los índices [lo, hi] (inclusive). */
export function stressOver(sim, lo, hi) {
  let stressDays = 0, eta = 0, etc = 0;
  for (let i = lo; i <= hi; i++) { if (sim.ks[i] < KS_FREE) stressDays++; eta += sim.eta[i]; etc += sim.etc[i]; }
  return { stressDays, n: hi - lo + 1, etaOverEtc: etc > 0 ? eta / etc : null };
}

/** Medidas de estrés del año cafetalero Y: ventanas tras la floración y estación seca (nov–abr). Sin rendimiento. */
export function coffeeYearMeasures({ sim, dates, rain, year }) {
  const fl = floweringFor(dates, rain, year + 1);
  const win = (r) => stressOver(sim, fl.idx + r[0], fl.idx + r[1]);
  const dry = stressOver(sim, dates.indexOf(`${year}-11-01`), dates.indexOf(`${year + 1}-04-30`));
  return { year, floweringDate: dates[fl.idx], noTrigger: fl.noTrigger, fruitSet: win(WINDOWS.fruitSet), grainFill: win(WINDOWS.grainFill), drySeason: dry };
}
