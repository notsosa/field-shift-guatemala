// Decisión tras perder el cultivo principal: ayudas puras (sin archivos). Regla fijada antes de ver resultados:
// la decisión para el año Y usa solo años anteriores a Y (bundle recortado al 31 de marzo de Y y filtro de años, como decision.js);
// se resume el relYield del cultivo resembrado con la prioridad (typical = mediana, cautious = percentil 20) y gana el mayor;
// en empate (±1e-12) gana dejar el campo sin cultivo y luego el orden de ACTIONS.
import { computeEt0Series, agriculturalYears, resolveMainSowIdx } from '../../web/js/model/simulate.js';
import { climateFeatures } from '../../web/js/model/emulator.js';
import { featuresV2 } from '../../web/js/model/emulatorV2.js';
import { featuresV3 } from '../../web/js/model/emulatorV3.js';
import { summarize, truncateBundle, pastYears, winTieLoss, mean, quantile, TOLERANCE } from '../../web/js/model/decision.js';
import { simulateSuccessionYear } from './succession_lib.mjs';

export const FALLOW = 'fallow';
export const RESOW_CROPS = ['maiz', 'frijol', 'ajonjoli', 'papa', 'cebolla', 'brocoli', 'lechuga'];
export const ACTIONS = [...RESOW_CROPS, FALLOW];
export const LOSS_DAYS = [30, 45, 60];
export const GAP_AFTER_LOSS = 14; // la siembra siguiente es 14 días después de que el campo queda libre (el día siguiente a la pérdida)
export const RULE = { maizeMinDays: 120, beansMinDays: 70, deadline: '11-15' };
const TIE_EPS = 1e-12;

/** Desfase de la resiembra respecto de la regla de inicio de lluvias = días hasta la pérdida + 1 (campo libre) + 14. */
export const resowOffset = (lossDay) => lossDay + 1 + GAP_AFTER_LOSS;

/** Días entre la fecha de siembra (ISO) y el 15 de noviembre de ese mismo año calendario. */
export function daysBeforeNov15(sowDate) {
  const y = sowDate.slice(0, 4);
  return Math.round((Date.parse(`${y}-${RULE.deadline}`) - Date.parse(sowDate)) / 864e5);
}

/** Regla agronómica simple: maíz si quedan ≥ 120 días antes del 15 de nov., si no frijol si quedan ≥ 70, si no dejar el campo. */
export function ruleAction(sowDate) {
  const d = daysBeforeNov15(sowDate);
  if (d >= RULE.maizeMinDays) return 'maiz';
  if (d >= RULE.beansMinDays) return 'frijol';
  return FALLOW;
}

/** Acción con el mayor valor; empate → dejar el campo, luego el orden de ACTIONS. summaries = [{action, value}]. */
export function chooseAction(summaries) {
  const rank = (a) => (a === FALLOW ? -1 : ACTIONS.indexOf(a));
  let best = null;
  for (const s of summaries) {
    if (!Number.isFinite(s.value)) continue;
    if (!best || s.value > best.value + TIE_EPS) { best = s; continue; }
    if (Math.abs(s.value - best.value) <= TIE_EPS && rank(s.action) < rank(best.action)) best = s;
  }
  if (!best) throw new Error('chooseAction: no action with a finite value');
  return best.action;
}

/**
 * La decisión: outcomes = [{action, year, value}] (relYield del cultivo resembrado por año); solo cuentan los años < targetYear.
 * Dejar el campo vale 0 en todo año. Aunque el llamador pase de más, nada del año objetivo o posterior entra a los resúmenes.
 */
export function decideAction({ outcomes, targetYear, priority }) {
  const used = outcomes.filter((o) => o.year < targetYear && Number.isFinite(o.value) && RESOW_CROPS.includes(o.action));
  if (used.length === 0) throw new Error(`decideAction: no past year before ${targetYear}`);
  const summaries = RESOW_CROPS
    .map((action) => ({ action, values: used.filter((o) => o.action === action).map((o) => o.value) }))
    .filter((s) => s.values.length > 0)
    .map((s) => ({ action: s.action, value: summarize(s.values, priority) }));
  summaries.push({ action: FALLOW, value: 0 });
  return chooseAction(summaries);
}

/** Lo único que ve una decisión para `year`: el bundle recortado al 31 de marzo de `year` y su ET0 recalculada sobre él. */
export function pastData(bundle, year) {
  const past = truncateBundle(bundle, year);
  return { bundle: past, et0: computeEt0Series(past), years: pastYears(agriculturalYears(past.dates).map((a) => a.year), year) };
}

/** Un cultivo resembrado en `year` con el desfase dado, por el simulador (la misma simulación de la matriz de sucesiones, sin sucesor). */
export function simulateResow({ bundle, et0, crops, texture, year, cropId, offsetDays }) {
  const ag = agriculturalYears(bundle.dates).find((a) => a.year === year);
  const r = simulateSuccessionYear({ idA: cropId, idB: null, bundle, et0, crops, texture, year, startIdx: ag.startIdx, endIdx: ag.endIdx, offsetDays });
  return { relYield: r.a.relYield, executable: !r.a.cycleIncomplete, sowDate: r.a.sowDate };
}

/** Motores: devuelven [{action, year, value}] sobre los años pasados. */
export const simulatorOutcomes = ({ crops, simSoil }, past, offsetDays) => past.years.flatMap((year) => RESOW_CROPS.map((cropId) => ({
  action: cropId, year, value: simulateResow({ bundle: past.bundle, et0: past.et0, crops, texture: simSoil, year, cropId, offsetDays }).relYield,
})));

/** predict(x) → [relYieldA, relYieldB, fit]; la entrada codifica el cultivo como A con su fecha de siembra real y B = ninguno. */
export function networkOutcomes({ emuTexture, predict, crops = null }, past, offsetDays) { // crops dado = entradas v3 (Tarea 33); sin crops, las de v2
  const clamp01 = (v) => Math.min(1, Math.max(0, v));
  return past.years.flatMap((year) => {
    const climFeats = climateFeatures(past.bundle, year, past.et0);
    const sowLocal = resolveMainSowIdx(past.bundle, year, offsetDays).idx;
    return RESOW_CROPS.map((cropId) => ({
      action: cropId, year,
      value: clamp01(predict((crops ? featuresV3 : featuresV2)({ bundle: past.bundle, et0: past.et0, year, climFeats, sowLocal, offsetDays, idA: cropId, idB: null, soil: emuTexture, crops }))[0]),
    }));
  });
}

const col = (rows, k) => rows.map((r) => r[k]);
/**
 * Métricas de una política en un grupo de casos. Cada fila: action (elegida), value (relYield real de lo elegido), ruleValue (de la regla),
 * oracleValue (mejor acción en el año Y), executable (el ciclo de lo elegido termina dentro del año agrícola), simAction (la del simulador, misma prioridad).
 * No incluye margen: el modelo no tiene precios ni costos.
 */
export function lossMetrics(rows, tol = TOLERANCE) {
  if (rows.length === 0) throw new Error('lossMetrics: no rows');
  const gains = rows.map((r) => r.value - r.ruleValue);
  const actions = {};
  for (const r of rows) actions[r.action] = (actions[r.action] ?? 0) + 1;
  const vals = col(rows, 'value');
  return {
    n: rows.length,
    chosenMean: mean(vals), ruleMean: mean(col(rows, 'ruleValue')), oracleMean: mean(col(rows, 'oracleValue')),
    meanGainVsRule: mean(gains), ...winTieLoss(gains, tol),
    meanRegret: mean(rows.map((r) => r.oracleValue - r.value)),
    p10: quantile(vals, 0.1), worst: Math.min(...vals),
    executable: rows.filter((r) => r.executable).length, executableShare: rows.filter((r) => r.executable).length / rows.length,
    actions,
    agreesWithSimulator: rows.filter((r) => r.action === r.simAction).length,
  };
}
