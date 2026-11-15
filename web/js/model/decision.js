// Decisión de la demora de siembra con información previa. Puro (sin E/S): corre en Node y en el navegador.
// Regla fijada de antemano: para el año objetivo Y solo se miran los años agrícolas anteriores a Y; cada demora se resume
// con una prioridad (typical = mediana, cautious = percentil 20) y gana la de mayor resumen; en empate, la más cercana a 0.

/** Demoras factibles (días después de la regla de inicio de lluvias). Las negativas necesitan saber cuándo llegará la lluvia. */
export const DECISION_OFFSETS = [0, 5, 10, 15, 20, 25, 30];
export const PRIORITIES = ['typical', 'cautious'];
/** Tolerancia para ganar/empatar/perder (índice de agua y relYield; también t/ha en AquaCrop). */
export const TOLERANCE = 0.001;
const TIE_EPS = 1e-12;

export const mean = (values) => (values.length === 0 ? null : values.reduce((s, x) => s + x, 0) / values.length);

/** Cuantil con interpolación lineal entre estadísticos de orden (el mismo de scripts/referee/compare.mjs); null si está vacío. */
export function quantile(values, q) {
  if (values.length === 0) return null;
  const s = [...values].sort((a, b) => a - b);
  const pos = (s.length - 1) * q;
  const lo = Math.floor(pos);
  return s[lo] + (s[Math.min(lo + 1, s.length - 1)] - s[lo]) * (pos - lo);
}

export const median = (values) => quantile(values, 0.5);

/** Resumen de los valores de los años pasados según la prioridad. */
export function summarize(values, priority) {
  if (priority === 'typical') return median(values);
  if (priority === 'cautious') return quantile(values, 0.2);
  throw new Error(`summarize: unknown priority "${priority}" (use typical or cautious)`);
}

/** Demora con el mayor valor; empate (±1e-12) → la de menor |demora|, y a igual distancia la más temprana. summaries = [{offset, value}]. */
export function chooseOffset(summaries) {
  let best = null;
  for (const s of summaries) {
    if (!Number.isFinite(s.value)) continue;
    if (!best || s.value > best.value + TIE_EPS) { best = s; continue; }
    if (Math.abs(s.value - best.value) <= TIE_EPS) {
      const a = Math.abs(s.offset), b = Math.abs(best.offset);
      if (a < b || (a === b && s.offset < best.offset)) best = s;
    }
  }
  if (!best) throw new Error('chooseOffset: no offset with a finite value');
  return best.offset;
}

/** Años estrictamente anteriores al objetivo. */
export const pastYears = (years, targetYear) => years.filter((y) => y < targetYear);

/**
 * Recorta el bundle diario hasta el 31 de marzo del año objetivo (el último día antes del año agrícola Y): lo único que
 * puede ver una decisión para Y. Las series diarias se cortan, los escalares se conservan y rainAlt (series de comparación) se descarta.
 */
export function truncateBundle(bundle, targetYear) {
  const cut = bundle.dates.indexOf(`${targetYear}-04-01`);
  if (cut < 0) throw new Error(`truncateBundle: 1 April ${targetYear} is not in the bundle (target year before the data or after it)`);
  const n = bundle.dates.length;
  const out = {};
  for (const [k, v] of Object.entries(bundle)) {
    if (k === 'rainAlt') continue;
    out[k] = Array.isArray(v) && v.length === n ? v.slice(0, cut) : v;
  }
  return out;
}

/**
 * La decisión: outcomes = [{offset, year, value}] (índice de agua por demora y año); solo cuentan los años < targetYear.
 * Aunque el llamador pase de más, nada del año objetivo o posterior entra a los resúmenes.
 */
export function decideOffset({ outcomes, targetYear, priority, offsets = DECISION_OFFSETS }) {
  const used = outcomes.filter((o) => o.year < targetYear && Number.isFinite(o.value) && offsets.includes(o.offset));
  if (used.length === 0) throw new Error(`decideOffset: no past year before ${targetYear}`);
  const summaries = offsets
    .map((offset) => ({ offset, values: used.filter((o) => o.offset === offset).map((o) => o.value) }))
    .filter((s) => s.values.length > 0)
    .map((s) => ({ offset: s.offset, value: summarize(s.values, priority) }));
  return chooseOffset(summaries);
}

const DAY_MS = 864e5;
/** Días en que dos cultivos comparten el campo (de la siembra más tardía a la cosecha más temprana; 0 si no se tocan). */
export function overlapDays(a, b) {
  const from = Math.max(Date.parse(a.sowDate), Date.parse(b.sowDate));
  const to = Math.min(Date.parse(a.harvestDate), Date.parse(b.harvestDate));
  return Math.max(0, (to - from) / DAY_MS);
}

/** Ganancias contra la línea base: ganar = ganancia > tol, perder = ganancia < −tol, empatar = el resto. */
export function winTieLoss(gains, tol = TOLERANCE) {
  let win = 0, tie = 0, loss = 0;
  for (const g of gains) {
    if (g > tol) win++; else if (g < -tol) loss++; else tie++;
  }
  return { win, tie, loss, n: gains.length };
}

const col = (rows, k) => rows.map((r) => r[k]);
const diffs = (rows, a, b) => rows.map((r) => r[a] - r[b]);

/**
 * Métricas de una política en un grupo de casos. Cada fila: offset (elegido), simOffset (el de la política `simulator` con la misma
 * prioridad), wi / wiBase / wiOracle (índice de agua de lo elegido, de la línea base y del oráculo), maize / maizeBase / maizeSim
 * (relYield del maíz; 0 si su ciclo no termina), overlap / overlapBase (días de traslape maíz–frijol), wiSim (índice de lo que elegiría el simulador).
 */
export function aggregateMetrics(rows, tol = TOLERANCE) {
  if (rows.length === 0) throw new Error('aggregateMetrics: no rows');
  const offsets = {};
  for (const r of rows) offsets[r.offset] = (offsets[r.offset] ?? 0) + 1;
  const wiGain = diffs(rows, 'wi', 'wiBase');
  const maizeGain = diffs(rows, 'maize', 'maizeBase');
  return {
    n: rows.length,
    offsets,
    waterIndex: {
      chosenMean: mean(col(rows, 'wi')), baselineMean: mean(col(rows, 'wiBase')), oracleMean: mean(col(rows, 'wiOracle')),
      meanGain: mean(wiGain), ...winTieLoss(wiGain, tol),
      meanRegret: mean(diffs(rows, 'wiOracle', 'wi')),
      chosenWorst: Math.min(...col(rows, 'wi')), chosenP10: quantile(col(rows, 'wi'), 0.1),
      baselineWorst: Math.min(...col(rows, 'wiBase')), baselineP10: quantile(col(rows, 'wiBase'), 0.1),
    },
    maize: { chosenMean: mean(col(rows, 'maize')), baselineMean: mean(col(rows, 'maizeBase')), meanGain: mean(maizeGain), ...winTieLoss(maizeGain, tol) },
    indexUpMaizeDown: rows.filter((_, i) => wiGain[i] > tol && maizeGain[i] < -tol).length,
    overlapMedian: { chosen: median(col(rows, 'overlap')), baseline: median(col(rows, 'overlapBase')) },
    agreement: {
      sameOffset: rows.filter((r) => r.offset === r.simOffset).length,
      meanWaterIndexDiff: mean(diffs(rows, 'wi', 'wiSim')),
      meanMaizeDiff: mean(diffs(rows, 'maize', 'maizeSim')),
    },
  };
}

/**
 * Revisión independiente (maíz, caso con suelo del sitio). Cada fila: id, aq y aqBase (rendimiento AquaCrop en t/ha de lo elegido y de la
 * línea base), simMaizeGain (relYield del maíz en el simulador, elegido − base). meanGainPct = ganancia media / rendimiento medio base.
 * "Gana solo el simulador" = ganancia del simulador > 0 y la de AquaCrop ≤ 0 (ganancia exacta, sin tolerancia).
 */
export function aquacropMetrics(rows, tol = TOLERANCE) {
  if (rows.length === 0) throw new Error('aquacropMetrics: no rows');
  const gains = diffs(rows, 'aq', 'aqBase');
  const only = rows.filter((r, i) => r.simMaizeGain > 0 && gains[i] <= 0);
  return {
    n: rows.length,
    meanGainTHa: mean(gains),
    meanGainPct: (100 * mean(gains)) / mean(col(rows, 'aqBase')),
    ...winTieLoss(gains, tol),
    simulatorOnlyWins: { count: only.length, ids: only.map((r) => r.id) },
  };
}
