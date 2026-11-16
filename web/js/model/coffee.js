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

// --- Banano como sombra (Tarea 38). SUPUESTO PROVISIONAL: no hay una medida del uso de agua del banano disperso como sombra del café (ver research_notes/sombra-banano.md).
// Entrada: bananaCover = fracción del suelo del lote cubierta por copa de banano (0–1, la declara el agricultor; 0.15 y 0.30 en los escenarios son convenciones).
// Supuesto 1: la misma reducción de evaporación del suelo en lluvias (0.52 mm/día, Padovan 2018) que los otros árboles; sin cobertura (0) no hay sombra y no hay reducción.
// Supuesto 2: uso de agua del banano = bananaCover × Kc × ET0 × KsBanana, con Kc = 1.10 (FAO-56 Tabla 12, banano de segundo año/retoño, fin de temporada; entre 1.00 y 1.20, convención)
// y KsBanana con la fracción de agotamiento del propio banano p = 0.35 (FAO-56 Tabla 22): el banano deja de gastar antes que el café (p = 0.40). No se modela que el banano ceda agua al café.
// No es una medida del banano disperso: el único estudio de campo (Sarmiento-Soler 2019, Uganda, solo resumen) vio la humedad del suelo bajar 6 % bajo banano contra 59 % bajo Cordia.
export const BANANA = { kc: 1.10, p: 0.35, source: 'FAO-56 Tabla 12 (banano, segundo año: Kc 1.00/1.20/1.10) y Tabla 22 (p = 0.35); supuesto provisional, no medido en banano disperso', provisional: true };
export const BANANA_COVERS = [0.15, 0.30]; // convención de los escenarios
export const TREE_TYPES_ALL = [...TREE_TYPES, 'banana'];

const month = (date) => Number(date.slice(5, 7));
export const isRainySeason = (date) => month(date) >= 5 && month(date) <= 10; // mayo–octubre
export const isDrySeason = (date) => !isRainySeason(date); // noviembre–abril

/** Coeficiente de estrés del banano: 1 mientras Dr ≤ p·TAW con p = 0.35, luego baja linealmente a 0 en Dr = TAW (FAO-56 ec. 84 con la p del banano). */
export function bananaKs(dr, taw) {
  const raw = BANANA.p * taw;
  if (dr <= raw) return 1;
  return Math.max(0, (taw - dr) / ((1 - BANANA.p) * taw));
}
/** Agua que gasta el banano en el día (mm): bananaCover × 1.10 × ET0 × KsBanana (sin KsBanana si ks = false: variante de sensibilidad). */
export function bananaUseMm({ cover, et0, dr, taw, ks = true }) {
  return cover * BANANA.kc * et0 * (ks ? bananaKs(dr, taw) : 1);
}

/**
 * Ajuste del lote por sombra, diario: { reduce[], add[] } (mm/día) para simulateDays; null sin sombra.
 * Banano (provisional): opts = { bananaCover (obligatorio), bananaKs = true }; devuelve además addFn({ et0, dr, taw }), el gasto del banano ese día, que depende del estado del suelo.
 */
export function plotAdjust(dates, shade, treeType, opts = {}) {
  if (shade === 'none') return null;
  if (shade !== 'trees') throw new Error(`plotAdjust: unknown shade "${shade}"`);
  if (treeType === 'banana') {
    const cover = opts.bananaCover;
    if (!(cover >= 0 && cover <= 1)) throw new Error('plotAdjust: banana needs bananaCover between 0 and 1');
    const withKs = opts.bananaKs !== false;
    return {
      reduce: dates.map((d) => (cover > 0 && isRainySeason(d) ? SHADE.rainyEvapCutMm : 0)),
      add: dates.map(() => 0),
      addFn: ({ et0, dr, taw }) => bananaUseMm({ cover, et0, dr, taw, ks: withKs }),
    };
  }
  const use = SHADE.treeUseMm[treeType];
  if (!use) throw new Error(`plotAdjust: unknown tree type "${treeType}"`);
  return {
    reduce: dates.map((d) => (isRainySeason(d) ? SHADE.rainyEvapCutMm : 0)),
    add: dates.map((d) => (isRainySeason(d) ? use.rainy : use.dry)),
  };
}

// --- Sistemas de la auditoría del asesor (Tarea 41): cuatro clases con un Kc compuesto y una p para TODO el lote (café + lo que crece entre los surcos). Reemplazan a la fórmula por cobertura de la Tarea 38,
// que sumaba un término de banano y contaba su estrés dos veces. Fuente: auditorias/prueba cafe banano 2025/datos/cultivos/parametros_auditados.json (origin/main, commit ac37f1b), que cita FAO-56 Tablas 12 y 22:
// café con suelo limpio o mulch 0.90/0.95/0.95; café con malezas 1.05/1.10/1.10; café + banano regulado (35–45 % de sombra) con mulch de Musa 0.95/1.05/1.00, p 0.38; café + banano denso sin deshije 1.00/1.20/1.10, p 0.35.
// Son valores de referencia de FAO-56, no medidos en campo (el propio asesor pide confirmarlos). La raíz sigue siendo la nuestra (1.2 m; la auditoría usa 1.0 m).
// Calendario de los tres Kc (el de la auditoría, que reproduce sus ETc anuales con sus ET0 al centésimo de mm): etapas de 365 días desde el 1 de enero, ini 60 d (Kc ini), desarrollo 90 d (lineal ini → mid),
// media 125 d (Kc mid), final 90 d (lineal mid → fin). Como el café es perenne, el mismo calendario se repite cada año civil por día del año (el 31 de dic. de un año bisiesto usa el Kc final).
export const SYSTEMS = {
  limpio: { kc: [0.90, 0.95, 0.95], p: 0.40, label: 'café solo, suelo limpio o con mulch (calendario de la auditoría)' },
  malezas: { kc: [1.05, 1.10, 1.10], p: 0.40, label: 'café solo con cobertura viva o malezas entre los surcos' },
  regulado: { kc: [0.95, 1.05, 1.00], p: 0.38, label: 'café + banano regulado (35–45 % de sombra) con mulch de Musa' },
  denso: { kc: [1.00, 1.20, 1.10], p: 0.35, label: 'café + banano denso sin deshije' },
};
export const SYSTEM_IDS = Object.keys(SYSTEMS);
export const SYSTEM_STAGE_DAYS = { ini: 60, dev: 90, mid: 125, late: 90 };
export const SYSTEMS_SOURCE = 'auditorias/prueba cafe banano 2025/datos/cultivos/parametros_auditados.json (origin/main ac37f1b), valores de referencia FAO-56 Tablas 12 y 22, sin calibración local; Zr propio de este modelo (1.2 m, la auditoría usa 1.0 m)';
export const GROUND = ['limpio', 'malezas']; // suelo entre los surcos
export const BANANA_CLASS = ['ninguno', 'regulado', 'denso']; // banano entre los surcos

/** Kc de un sistema el día del año doy (1–366), con el calendario de la auditoría. */
export function systemKc(kc, doy) {
  const i = Math.min(doy, 365) - 1;
  const { ini, dev, mid, late } = SYSTEM_STAGE_DAYS;
  if (i < ini) return kc[0];
  if (i < ini + dev) return kc[0] + (kc[1] - kc[0]) * (i - ini + 1) / dev;
  if (i < ini + dev + mid) return kc[1];
  return kc[1] + (kc[2] - kc[1]) * (i - ini - dev - mid + 1) / late;
}
/** Ajuste del lote para simulateDays con un sistema auditado: Kc diario y p únicos, sin recorte ni término extra (nada se cuenta dos veces). */
export function systemAdjust(dates, system) {
  const s = SYSTEMS[system];
  if (!s) throw new Error(`systemAdjust: unknown system "${system}"`);
  return { reduce: dates.map(() => 0), add: dates.map(() => 0), kcSeries: dates.map((d) => systemKc(s.kc, dayOfYear(d))), p: s.p };
}
/**
 * Sistema que corresponde a lo que declara el agricultor: suelo entre los surcos (limpio | malezas) y banano (ninguno | regulado | denso).
 * Con banano, el suelo es el de la auditoría (con mulch de Musa) y `suelo` se ignora. Sin banano y suelo limpio devuelve null: el café de siempre (Kc 0.95 constante, p 0.40), sin opción de sistema.
 */
export function systemFor({ suelo = 'limpio', banano = 'ninguno' } = {}) {
  if (!GROUND.includes(suelo)) throw new Error(`systemFor: unknown suelo "${suelo}"`);
  if (!BANANA_CLASS.includes(banano)) throw new Error(`systemFor: unknown banano "${banano}"`);
  if (banano !== 'ninguno') return banano;
  return suelo === 'malezas' ? 'malezas' : null;
}

/** Floración del año calendario F: primer día del 15 feb al 30 abr con lluvia ≥ 10 mm, más 9 días; si no hay, 9 de mayo con noTrigger. */
export function floweringFor(dates, rain, F) {
  const a = dates.indexOf(`${F}-02-15`), b = dates.indexOf(`${F}-04-30`);
  if (a < 0 || b < 0) throw new Error(`floweringFor: dates of ${F} are not in the series`);
  for (let i = a; i <= b; i++) if (rain[i] >= FLOWER_RAIN_MM) return { triggerIdx: i, idx: i + FLOWER_LAG_DAYS, noTrigger: false };
  return { triggerIdx: null, idx: dates.indexOf(`${F}-${FLOWER_FALLBACK}`), noTrigger: true };
}

/** Balance continuo del café sobre toda la serie, sin riego. Devuelve la salida de simulateDays (dr, ds, ks, eta, etc…). */
export function simulateCoffee({ dates, rain, et0, crops, texture, shade = 'none', treeType = 'evergreen', slopeClass = 'flat', drInit, dsInit, bananaCover, bananaKs: withBananaKs = true, system }) {
  const crop = crops.get(COFFEE_ID);
  if (system != null) {
    // Sistema auditado (Tarea 41, opt-in): no se combina con la sombra de árboles ni con la fórmula de banano por cobertura (Tarea 38).
    if (shade !== 'none') throw new Error('simulateCoffee: a system cannot be combined with tree shade');
    return simulateDays({ rain, et0, phases: [buildPerennialPhase(crop, rain.length)], crops, texture, slopeClass, irrigation: 'none', drInit, dsInit, plotAdjust: systemAdjust(dates, system) });
  }
  return simulateDays({
    rain, et0, phases: [buildPerennialPhase(crop, rain.length)], crops, texture, slopeClass, irrigation: 'none', drInit, dsInit,
    plotAdjust: plotAdjust(dates, shade, treeType, { bananaCover, bananaKs: withBananaKs }) ?? undefined,
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

// --- Parte C: decisión de riego (20 mm ahora o no) a 30, 60 y 90 días tras la floración ---
export const IRRIGATION_MM = 20; // única lámina con ensayo centroamericano en las notas (una finca, Nicaragua)
export const HORIZON_DAYS = 30; // se puntúa el estrés de los 30 días siguientes al día de la decisión
export const DECISION_DAYS = [30, 60, 90];
export const PRICE = { 0: 3, 1: 1 }; // prioridad 0 = ahorrar agua y trabajo (3 días de estrés); 1 = proteger el cultivo (1 día). Convenciones.
export const DRY_DAY_MM = 1;
export const STATE_NAMES = [
  'daysSinceFlowering', 'doy', 'rain7', 'et0_7', 'rain28', 'et0_28', 'rainSinceNov1', 'et0SinceNov1', 'dryspell28',
  'tmean28', 'tmaxMax28', 'runningDepletion', 'soilAWmm', 'elevation', 'shadeTrees', 'deciduous',
];
/** Utilidad de regar = días de estrés evitados − precio; no regar = 0. */
export const irrigationUtility = (avoided, priority) => avoided - PRICE[priority];

const dayOfYear = (date) => { const [y, m, d] = date.split('-').map(Number); return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(y, 0, 0)) / 864e5); };
function maxDryRun(rain, lo, hi) {
  let best = 0, cur = 0;
  for (let i = lo; i <= hi; i++) { cur = rain[i] < DRY_DAY_MM ? cur + 1 : 0; if (cur > best) best = cur; }
  return best;
}

/**
 * Balance corrido acotado desde el 1 de noviembre del año cafetalero (regla fijada): D = 0 (suelo a capacidad de campo) el 1 de noviembre y,
 * cada día, D ← min(TAW, max(0, D + Kc·ET0 − lluvia)) con Kc = 0.95 (el del café). Sin escorrentía, sin sombra, sin riego pasado: solo datos observables.
 * Devuelve D (mm) al final del día t. Solo mira hasta t.
 */
export function runningDepletion({ rain, et0, nov1Idx, t, taw, kc }) {
  let d = 0;
  for (let i = nov1Idx; i <= t; i++) d = Math.min(taw, Math.max(0, d + kc * et0[i] - rain[i]));
  return d;
}

/**
 * Entradas del día de la decisión t (índice en la serie diaria). Los arreglos diarios se cortan en t: nada posterior entra.
 * floweringIdx = floración del año (ya conocida el día t, que es ≥ 30 días después). Devuelve { state (STATE_NAMES), depletion, taw }.
 */
export function coffeeDecisionState({ dates, rain, et0, tmax, tmin, t, year, floweringIdx, soil, crop, elevation, shade, treeType }) {
  const cut = (a) => a.slice(0, t + 1);
  const d = cut(dates), r = cut(rain), e = cut(et0), tx = cut(tmax), tn = cut(tmin);
  const nov1 = d.indexOf(`${year}-11-01`);
  const taw = 1000 * (soil.thetaFC - soil.thetaWP) * crop.zrMax;
  const depletion = runningDepletion({ rain: r, et0: e, nov1Idx: nov1, t, taw, kc: crop.kc.mid });
  let tm = 0, tmx = -Infinity;
  for (let i = t - 27; i <= t; i++) { tm += (tx[i] + tn[i]) / 2; if (tx[i] > tmx) tmx = tx[i]; }
  const state = [
    t - floweringIdx, dayOfYear(d[t]), sum(r, t - 6, t), sum(e, t - 6, t), sum(r, t - 27, t), sum(e, t - 27, t), sum(r, nov1, t), sum(e, nov1, t),
    maxDryRun(r, t - 27, t), tm / 28, tmx, depletion, taw, elevation, shade === 'trees' ? 1 : 0, shade === 'trees' && treeType === 'deciduous' ? 1 : 0,
  ];
  return { state, depletion, taw };
}

// Red v2 (Tarea 38, provisional): las 16 entradas de siempre más banana (0/1) y bananaCover (0–1; 0 si no hay banano). Con banano, shadeTrees = 1 y deciduous = 0.
export const STATE_NAMES_V2 = [...STATE_NAMES, 'banana', 'bananaCover'];
export function coffeeDecisionStateV2(args) {
  const r = coffeeDecisionState(args);
  const isBanana = args.shade === 'trees' && args.treeType === 'banana';
  return { ...r, state: [...r.state, isBanana ? 1 : 0, isBanana ? args.bananaCover : 0] };
}

// Red v3 (Tarea 41): las 16 entradas de siempre más weeds, bananaRegulated y bananaDense (0/1 cada una; los sistemas de la auditoría, mutuamente excluyentes). Con un sistema, shadeTrees = 0 y deciduous = 0 (no se combina con árboles).
// Sin sistema (café de siempre, suelo limpio) las tres entradas nuevas valen 0. La regla y el balance corrido de las 16 entradas siguen siendo los del café (Kc 0.95, p 0.40): es lo que el agricultor puede observar.
export const STATE_NAMES_V3 = [...STATE_NAMES, 'weeds', 'bananaRegulated', 'bananaDense'];
export const systemFlags = (system) => [system === 'malezas' ? 1 : 0, system === 'regulado' ? 1 : 0, system === 'denso' ? 1 : 0];
export function coffeeDecisionStateV3(args) {
  const { system, ...rest } = args;
  if (system != null && !(system in SYSTEMS)) throw new Error(`coffeeDecisionStateV3: unknown system "${system}"`);
  if (system != null && rest.shade === 'trees') throw new Error('coffeeDecisionStateV3: a system cannot be combined with tree shade');
  const r = coffeeDecisionState(rest);
  return { ...r, state: [...r.state, ...systemFlags(system)] };
}

/** La regla: regar si el balance corrido dice que la zona radicular gastó más de p (0.40) de su agua disponible (FAO-56). */
export const ruleIrrigates = (depletion, taw, p) => depletion > p * taw;

/**
 * Contrafactual desde el estado del día t (de la corrida continua `sim` sin riego): los 30 días siguientes sin riego y regando 20 mm al final del día t.
 * Estrés = días con Ks < 1. El riego sobre lo que falta se pierde hacia el subsuelo (que en este perfil, Zp = Zr, no tiene capacidad).
 */
export function counterfactual({ dates, rain, et0, crops, texture, shade, treeType, sim, t, slopeClass = 'flat', irrigationMm = IRRIGATION_MM, horizon = HORIZON_DAYS, returnKs = false, bananaCover, bananaKs: withBananaKs = true, system }) {
  const lo = t + 1, hi = t + horizon;
  if (hi >= rain.length) throw new Error('counterfactual: the 30-day window goes past the end of the series');
  const run = (mm) => {
    const dr0 = Math.max(0, sim.dr[t] - mm);
    const excess = Math.max(0, mm - sim.dr[t]);
    const ds0 = Math.max(0, sim.ds[t] - excess);
    const w = simulateCoffee({ dates: dates.slice(lo, hi + 1), rain: rain.slice(lo, hi + 1), et0: et0.slice(lo, hi + 1), crops, texture, shade, treeType, slopeClass, drInit: dr0, dsInit: ds0, bananaCover, bananaKs: withBananaKs, system });
    const m = stressOver(w, 0, horizon - 1);
    return { stressDays: m.stressDays, etaOverEtc: m.etaOverEtc, ks: returnKs ? w.ks : undefined };
  };
  const no = run(0), yes = run(irrigationMm);
  const ksOut = returnKs ? { ksNo: no.ks, ksYes: yes.ks } : {}; // opt-in (Tarea 36): Ks diario de los 30 días siguientes, para contar días de aviso
  return { ...ksOut, stressNo: no.stressDays, stressYes: yes.stressDays, stressDaysAvoided: no.stressDays - yes.stressDays, etaOverEtcNo: no.etaOverEtc, etaOverEtcYes: yes.etaOverEtc };
}

/**
 * Regla aprobada en principio por el dueño (Tarea 36): si el aviso de antracnosis está activo POR ESTRÉS HÍDRICO (Ks < 1 en más de la mitad de los últimos 28 días),
 * la prioridad del riego pasa a 1 = proteger el cultivo (precio 1 día), sea cual sea la que declaró el agricultor. Si el aviso está activo solo por roya, o no está
 * activo, la prioridad no cambia: ninguna fuente enlaza la roya con el riego. `antracnosis` es la salida de antracnosisNotice.
 */
export function effectivePriority(priority, antracnosis) {
  return antracnosis?.triggers?.byStress ? 1 : priority;
}
