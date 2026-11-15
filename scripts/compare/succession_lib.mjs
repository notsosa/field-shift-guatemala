// Ayudas puras de la matriz de sucesiones (scripts/compare/succession_matrix.mjs). Sin red, sin archivos.
import { resolveMainSowIdx, stageYield } from '../../web/js/model/simulate.js';
import { buildPhase } from '../../web/js/model/phenology.js';
import { simulateDays } from '../../web/js/model/waterBalance.js';

export const GAP_DAYS = 14; // intervalo de referencia de las auditorías del equipo
export const MIN_FIT_YEARS = 20; // "cabe" = las dos etapas completas en al menos 20 de 24 años

export const round = (x, d = 3) => (x == null ? null : Math.round(x * 10 ** d) / 10 ** d);

/** Mediana; null si no hay datos. */
export function median(a) {
  if (!a.length) return null;
  const s = [...a].sort((x, y) => x - y);
  const m = s.length >> 1;
  return s.length % 2 ? s[m] : (s[m - 1] + s[m]) / 2;
}

/** Cuantil q en [0,1] por interpolación lineal entre estadísticos de orden (método 7 de R); null si no hay datos. */
export function quantile(a, q) {
  if (!a.length) return null;
  const s = [...a].sort((x, y) => x - y);
  const pos = (s.length - 1) * q;
  const lo = Math.floor(pos);
  const hi = Math.ceil(pos);
  return s[lo] + (s[hi] - s[lo]) * (pos - lo);
}

// Orden dentro del año agrícola (1 abr → 31 mar): los meses 1–3 van después de diciembre.
function agYearOrder(date) {
  const [, m, d] = date.split('-').map(Number);
  return ((m + 8) % 12) * 100 + d;
}

/** Mediana de fechas ISO como una fecha del conjunto (la anterior si el conteo es par), ordenadas por día del año agrícola. */
export function medianDate(dates) {
  if (!dates.length) return null;
  const s = [...dates].sort((a, b) => agYearOrder(a) - agYearOrder(b));
  return s[(s.length - 1) >> 1];
}

/** Día de siembra del sucesor: el día siguiente a la cosecha más el intervalo. */
export const sowAfterHarvest = (harvestIdx, gapDays = GAP_DAYS) => harvestIdx + 1 + gapDays;

/** Métricas de un cultivo en sus días [sowIdx, harvestIdx]: ETc, ETa, déficit, tmax media, longitud del ciclo. */
export function cropWindowMetrics(sim, tmax, phase) {
  const { sowIdx, harvestIdx } = phase;
  let etc = 0;
  let eta = 0;
  let tx = 0;
  for (let i = sowIdx; i <= harvestIdx; i++) { etc += sim.etc[i]; eta += sim.eta[i]; tx += tmax[i]; }
  const n = harvestIdx - sowIdx + 1;
  return { etcMm: etc, etaMm: eta, deficitMm: etc - eta, tmaxMean: tx / n, cycleDays: n };
}

/**
 * Un año agrícola de la sucesión A→B: A en el inicio de lluvias, B el día siguiente a la cosecha de A más `gapDays`.
 * Mismo balance (simulateDays) y Ky (stageYield) que runSequence, sin traslape. Un ciclo incompleto (o un B que ya no se
 * puede sembrar dentro del año) cuenta relYield 0. Devuelve { year, fit, a, b } con b = null si no se sembró.
 */
export function simulateSuccessionYear({ idA, idB, bundle, et0, crops, texture, year, startIdx, endIdx, gapDays = GAP_DAYS }) {
  const end = endIdx + 1;
  const dates = bundle.dates.slice(startIdx, end);
  const rain = bundle.rain.slice(startIdx, end);
  const e0 = et0.slice(startIdx, end);
  const tmax = bundle.tmax.slice(startIdx, end);
  const tmean = tmax.map((t, i) => (t + bundle.tmin[startIdx + i]) / 2);
  const last = dates.length - 1;
  const cropA = crops.get(idA);
  const cropB = crops.get(idB);
  const phaseA = buildPhase(cropA, resolveMainSowIdx(bundle, year, 0).idx, tmean);
  const sowB = sowAfterHarvest(phaseA.harvestIdx, gapDays);
  const phaseB = !phaseA.cycleIncomplete && sowB <= last ? buildPhase(cropB, sowB, tmean) : null;
  const phases = phaseB ? [phaseA, phaseB] : [phaseA];
  const sim = simulateDays({ rain, et0: e0, phases, crops, texture, slopeClass: 'flat', irrigation: 'none', residueMask: Array(dates.length).fill(false) });
  const one = (crop, phase) => {
    if (!phase) return null;
    const { relYield } = stageYield(crop, phase, { et0: e0, ks: sim.ks });
    return {
      sowDate: dates[phase.sowIdx], harvestDate: dates[phase.harvestIdx], cycleIncomplete: phase.cycleIncomplete,
      relYield: phase.cycleIncomplete ? 0 : relYield, ...cropWindowMetrics(sim, tmax, phase),
    };
  };
  const a = one(cropA, phaseA);
  const b = one(cropB, phaseB);
  return { year, fit: !!(b && !a.cycleIncomplete && !b.cycleIncomplete), a, b };
}

function cropSummary(yearRows, pick) {
  const fit = yearRows.filter((y) => y.fit);
  const all = yearRows.map((y) => (y[pick] ? y[pick].relYield : 0));
  const f = (key) => fit.map((y) => y[pick][key]);
  return {
    medianCycleDays: median(f('cycleDays')),
    medianSowDate: medianDate(fit.map((y) => y[pick].sowDate)),
    medianHarvestDate: medianDate(fit.map((y) => y[pick].harvestDate)),
    relYieldMedian: round(median(all)), relYieldP10: round(quantile(all, 0.1)), relYieldWorst: round(Math.min(...all)),
    medianEtcMm: round(median(f('etcMm')), 1), medianEtaMm: round(median(f('etaMm')), 1),
    medianDeficitMm: round(median(f('deficitMm')), 1),
    medianTmaxMeanC: round(median(f('tmaxMean')), 1),
  };
}

/** Resumen de una sucesión: años que caben, y por cultivo ciclo, fechas, déficit y tmax (solo años en que cabe) y relYield (los N años, incompleto = 0). */
export function summarizePair(yearRows) {
  return {
    years: yearRows.length,
    fitYears: yearRows.filter((y) => y.fit).length,
    a: cropSummary(yearRows, 'a'),
    b: cropSummary(yearRows, 'b'),
  };
}

/** Compara los dos órdenes de una pareja año a año (solo años en que caben ambos): déficit total de ET y relYield medio de la pareja. */
export function compareOrders(rowsAB, rowsBA) {
  const c = { yearsBothFit: 0, abLowerDeficit: 0, baLowerDeficit: 0, tieDeficit: 0, abHigherRelYield: 0, baHigherRelYield: 0, tieRelYield: 0 };
  for (let i = 0; i < rowsAB.length; i++) {
    const x = rowsAB[i];
    const y = rowsBA[i];
    if (!x.fit || !y.fit) continue;
    c.yearsBothFit++;
    const dx = x.a.deficitMm + x.b.deficitMm;
    const dy = y.a.deficitMm + y.b.deficitMm;
    if (Math.abs(dx - dy) < 1e-9) c.tieDeficit++; else if (dx < dy) c.abLowerDeficit++; else c.baLowerDeficit++;
    const yx = (x.a.relYield + x.b.relYield) / 2;
    const yy = (y.a.relYield + y.b.relYield) / 2;
    if (Math.abs(yx - yy) < 1e-9) c.tieRelYield++; else if (yx > yy) c.abHigherRelYield++; else c.baHigherRelYield++;
  }
  return c;
}

/** Dirección de un conteo: 'AB' | 'BA' | 'tie' (mayoría estricta). */
export const majority = (ab, ba) => (ab > ba ? 'AB' : ba > ab ? 'BA' : 'tie');

/** Dirección del equipo: el orden con menor déficit de ET (números {deficit}); null si falta una de las dos filas. */
export function teammateDirection(rowAB, rowBA) {
  if (!rowAB || !rowBA) return null;
  if (rowAB.deficit === rowBA.deficit) return 'tie';
  return rowAB.deficit < rowBA.deficit ? 'AB' : 'BA';
}

/** Pantalla de un piloto: las que caben en ≥ minFit años ordenadas por el menor de los dos relYield medianos (desc.), y las que no. */
export function screen(entries, minFit = MIN_FIT_YEARS) {
  const lowest = (e) => Math.min(e.a.relYieldMedian, e.b.relYieldMedian);
  const fits = entries.filter((e) => e.fitYears >= minFit).sort((x, y) => lowest(y) - lowest(x) || (x.pair < y.pair ? -1 : 1));
  const notFit = entries.filter((e) => e.fitYears < minFit).map((e) => ({ pair: e.pair, fitYears: e.fitYears }));
  return {
    fits: fits.map((e) => ({ pair: e.pair, fitYears: e.fitYears, lowestMedianRelYield: round(lowest(e)), aMedianRelYield: e.a.relYieldMedian, bMedianRelYield: e.b.relYieldMedian })),
    notFit,
  };
}
