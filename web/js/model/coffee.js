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

// --- Parte B: avisos con fuente (no son predicciones ni porcentajes de daño). Cada aviso devuelve nivel, los números que lo activaron, la clave de fuente y la confianza.
// Los textos de las fuentes viven en web/data/coffee_sources.json (clave = sourceKey).
export const ROYA = { favorableC: [21, 25], possibleC: [16, 28], days: 14, months: [6, 12], latentDays: [31, 37] };
export const MINADOR = { days: 28, dryMm: 10 };
export const ANTRACNOSIS = { days: 28, stressShare: 0.5, royaLookback: 60 };
export const ABONO = { months: [5, 6, 8, 9, 10, 11], rainDays: 7, rainMm: 10 };

const sum = (a, lo, hi) => { let s = 0; for (let i = lo; i <= hi; i++) s += a[i]; return s; };
const median = (v) => { const s = [...v].sort((a, b) => a - b); const m = s.length >> 1; return s.length === 0 ? null : s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2; };

/** Mediana por mes calendario (1..12) de los días de años ANTERIORES a beforeYear; el sitio contra sí mismo. */
export function monthMedians(dates, values, beforeYear) {
  const by = Array.from({ length: 13 }, () => []);
  dates.forEach((d, i) => { if (Number(d.slice(0, 4)) < beforeYear) by[month(d)].push(values[i]); });
  return by.map(median);
}
/** Referencias del sitio hasta antes del año de hoy: mediana mensual del rango diurno (tmax − tmin) y de tmax. */
export function siteHistory(dates, tmax, tmin, beforeYear) {
  return { dtrMedian: monthMedians(dates, tmax.map((v, i) => v - tmin[i]), beforeYear), tmaxMedian: monthMedians(dates, tmax, beforeYear), beforeYear };
}

/** Roya: junio–diciembre; media de los últimos 14 días en 21–25 °C y rango diurno bajo la mediana del mes del sitio → "condiciones favorables"; 16–28 °C → "posible". */
export function royaNotice({ dates, tmax, tmin, t, history }) {
  const m = month(dates[t]);
  const inSeason = m >= ROYA.months[0] && m <= ROYA.months[1];
  const lo = t - ROYA.days + 1;
  if (lo < 0) throw new Error('royaNotice: fewer than 14 days of weather up to today');
  const meanT = (sum(tmax, lo, t) + sum(tmin, lo, t)) / (2 * ROYA.days);
  const dtr = (sum(tmax, lo, t) - sum(tmin, lo, t)) / ROYA.days;
  const dtrMedian = history.dtrMedian[m];
  const inFav = meanT >= ROYA.favorableC[0] && meanT <= ROYA.favorableC[1];
  const dtrLow = dtrMedian != null && dtr < dtrMedian;
  let level = 'none';
  if (inSeason && inFav && dtrLow) level = 'favorable';
  else if (inSeason && meanT >= ROYA.possibleC[0] && meanT <= ROYA.possibleC[1]) level = 'possible';
  return {
    notice: 'roya', level, inSeason, triggers: { meanTemp14: meanT, dtr14: dtr, dtrMedianMonth: dtrMedian, month: m },
    latent: level === 'favorable' ? { days: ROYA.latentDays, text: 'los síntomas aparecerían en unas 5 semanas' } : null,
    sourceKey: level === 'possible' ? 'roya_posible' : 'roya_favorable', latentSourceKey: 'roya_latencia', confidence: level === 'favorable' ? 'media-alta (correlación de campo, no un modelo)' : 'orientativa',
  };
}

/** Minador: últimos 28 días con lluvia total < 10 mm y tmax media sobre la mediana del mes del sitio → "condiciones probables" (la evidencia se contradice entre sitios). */
export function minadorNotice({ dates, tmax, rain, t, history }) {
  const lo = t - MINADOR.days + 1;
  if (lo < 0) throw new Error('minadorNotice: fewer than 28 days of weather up to today');
  const rain28 = sum(rain, lo, t), tmax28 = sum(tmax, lo, t) / MINADOR.days, med = history.tmaxMedian[month(dates[t])];
  const level = rain28 < MINADOR.dryMm && med != null && tmax28 > med ? 'probable' : 'none';
  return { notice: 'minador', level, triggers: { rain28, tmax28, tmaxMedianMonth: med }, sourceKey: 'minador', confidence: 'baja-media (probable; Costa Rica y Anacafe 2026 a favor, Chiapas en contra)' };
}

/** Antracnosis: Ks < 1 en más de la mitad de los últimos 28 días, o un aviso de roya "favorable" en los 60 días previos (días t−60..t−1). */
export function antracnosisNotice({ dates, tmax, tmin, ks, t, history }) {
  const lo = t - ANTRACNOSIS.days + 1;
  if (lo < 0) throw new Error('antracnosisNotice: fewer than 28 days of weather up to today');
  let stress = 0;
  for (let i = lo; i <= t; i++) if (ks[i] < KS_FREE) stress++;
  const share = stress / ANTRACNOSIS.days;
  let royaDay = null;
  for (let i = Math.max(ROYA.days - 1, t - ANTRACNOSIS.royaLookback); i < t; i++) {
    if (royaNotice({ dates, tmax, tmin, t: i, history }).level === 'favorable') { royaDay = dates[i]; break; }
  }
  const byStress = share > ANTRACNOSIS.stressShare;
  return { notice: 'antracnosis', level: byStress || royaDay ? 'notice' : 'none', triggers: { stressShare28: share, stressDays28: stress, royaFavorableDay: royaDay, byStress, byRoya: royaDay != null }, sourceKey: 'antracnosis', confidence: 'baja-media (referencia de una finca, Patulul)' };
}

/** Abono: "abonar ahora" solo en las ventanas de Anacafe (may–jun, ago–sep, oct–nov) con suelo húmedo (Dr < RAW y ≥ 10 mm de lluvia en 7 días); si no, "en espera". */
export function abonoNotice({ dates, rain, t, dr, taw, p }) {
  const m = month(dates[t]);
  const inWindow = ABONO.months.includes(m);
  const rain7 = sum(rain, Math.max(0, t - ABONO.rainDays + 1), t);
  const raw = p * taw;
  const moist = dr < raw && rain7 >= ABONO.rainMm;
  return { notice: 'abono', level: inWindow && moist ? 'apply_now' : 'wait', triggers: { month: m, inWindow, dr, raw, rain7, moist }, sourceKey: inWindow && moist ? 'abono_ventanas' : 'abono_suelo_seco', confidence: 'alta (Anacafe)' };
}
