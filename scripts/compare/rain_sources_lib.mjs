// Ayudas de la Tarea 35: lluvia de tres fuentes (ERA5, NASA POWER, CHIRPS) para los 20 puntos, estadísticas de lluvia,
// una siembra en una fecha dada por el simulador existente, y las funciones de percentil, acierto y AUC.
// Nada de aquí ajusta parámetros: reutiliza buildPhase, simulateDays y stageYield tal como están. Un día de lluvia sin dato
// nunca se rellena: el año agrícola que lo contiene queda fuera para esa fuente y ese sitio.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series, agriculturalYears, KS_STRESS, stageYield } from '../../web/js/model/simulate.js';
import { buildPhase, onsetSowIdx } from '../../web/js/model/phenology.js';
import { simulateDays } from '../../web/js/model/waterBalance.js';
import { applyFactors } from '../../web/js/model/factors.js';

export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
export const SOURCES = ['ERA5', 'POWER', 'CHIRPS'];
export const YEARS = Array.from({ length: 24 }, (_, i) => 2001 + i); // años agrícolas 2001..2024 (el 2024 termina el 31 mar 2025)
export const PILOTS = ['chiquimula', 'jutiapa', 'sanmartin'];
export const WORST_THIRD = 1 / 3; // umbral fijado antes de ver resultados: "peor tercio" = percentil <= 1/3
export const round = (x, d = 3) => (x == null || !Number.isFinite(x) ? null : Math.round(x * 10 ** d) / 10 ** d);

export const loadAllCrops = () => loadCrops(readJson(path.join(root, 'web/data/crops.json')));
export const loadPoints = () => readJson(path.join(root, 'scripts/emulator/points.json'));
/** Suelo de la simulación: el del sitio (SoilGrids) en los pilotos, franco ('loam') en los demás; igual que historical_check. */
export const soilOfPoint = (p) => (PILOTS.includes(p.id) ? p.soil : 'loam');

/**
 * Series de lluvia diaria de un punto por fuente, alineadas con las fechas del paquete ERA5 (2001-01-01..2025-12-31).
 * @returns {{bundle, et0, dates, rain: Record<string,(number|null)[]|null>}} CHIRPS = null si no hay caché del punto.
 */
export function loadSite(id) {
  const bundle = readJson(path.join(root, `scripts/emulator/cache/${id}.json`));
  const dates = bundle.dates;
  const power = readJson(path.join(root, `scripts/emulator/cache_power_app/${id}.json`));
  const rain = { ERA5: bundle.rain.map((v) => (v == null ? null : v)) };
  const pByDate = new Map(power.dates.map((d, i) => [d, power.lluvia[i]]));
  rain.POWER = dates.map((d) => (pByDate.has(d) && pByDate.get(d) != null ? pByDate.get(d) : null));
  const cf = path.join(root, `scripts/emulator/cache_rain/${id}_chirps.json`);
  const doc = fs.existsSync(cf) ? readJson(cf) : null;
  // CHIRPS solo cuenta si se bajaron los 25 años pedidos (2001-2025); una descarga a medias (tope de tiempo) es "no bajado", no un hueco de la fuente.
  if (doc && Array.from({ length: 25 }, (_, i) => 2001 + i).every((y) => doc.yearsDone.includes(y))) {
    rain.CHIRPS = dates.map((d) => (typeof doc.days[d] === 'number' ? doc.days[d] : null));
  } else rain.CHIRPS = null;
  return { bundle, et0: computeEt0Series(bundle), dates, rain };
}

const agiRange = (dates, y) => [dates.indexOf(`${y}-04-01`), dates.indexOf(`${y + 1}-03-31`)];

/** Años agrícolas (de YEARS) cuyos 365/366 días de lluvia están todos presentes en la serie. */
export function completeYears(dates, rain) {
  return YEARS.filter((y) => {
    const [a, b] = agiRange(dates, y);
    if (a < 0 || b < 0) return false;
    for (let i = a; i <= b; i++) if (rain[i] == null) return false;
    return true;
  });
}

/** Suma de lluvia entre dos fechas ISO inclusivas; null si falta algún día (no se rellena). */
export function sumBetween(dates, rain, from, to) {
  const a = dates.indexOf(from); const b = dates.indexOf(to);
  if (a < 0 || b < 0) return null;
  let s = 0;
  for (let i = a; i <= b; i++) { if (rain[i] == null) return null; s += rain[i]; }
  return s;
}

/** Racha seca más larga (días seguidos con lluvia < 1 mm) entre dos fechas ISO inclusivas; null si falta algún día. */
export function longestDrySpell(dates, rain, from, to) {
  const a = dates.indexOf(from); const b = dates.indexOf(to);
  if (a < 0 || b < 0) return null;
  let run = 0; let best = 0;
  for (let i = a; i <= b; i++) {
    if (rain[i] == null) return null;
    run = rain[i] < 1 ? run + 1 : 0;
    if (run > best) best = run;
  }
  return best;
}

/** Estadísticas de lluvia por año (agrícola para el total anual; calendario para los periodos dentro de mayo-octubre). */
export function rainStatsByYear(dates, rain) {
  const f = (fn) => YEARS.map((y) => fn(y));
  const r1 = (v) => (v == null ? null : Math.round(v * 10) / 10);
  return {
    annualMm: f((y) => r1(sumBetween(dates, rain, `${y}-04-01`, `${y + 1}-03-31`))),
    mayOctMm: f((y) => r1(sumBetween(dates, rain, `${y}-05-01`, `${y}-10-31`))),
    julAugMm: f((y) => r1(sumBetween(dates, rain, `${y}-07-01`, `${y}-08-31`))),
    longestDrySpellJunSep: f((y) => longestDrySpell(dates, rain, `${y}-06-01`, `${y}-09-30`)),
  };
}

/** Cobertura: días sin dato en todo 2001-01-01..2025-12-31 y en los años agrícolas 2001..2024, y años excluidos. */
export function coverage(dates, rain) {
  const missingAll = rain.filter((v) => v == null).length;
  const ok = new Set(completeYears(dates, rain));
  let missingAgri = 0;
  for (const y of YEARS) { const [a, b] = agiRange(dates, y); for (let i = a; i <= b; i++) if (rain[i] == null) missingAgri++; }
  return { days: dates.length, missingDaysAll: missingAll, missingDaysAgriYears2001_2024: missingAgri, yearsExcluded: YEARS.filter((y) => !ok.has(y)), yearsUsable: ok.size };
}

/**
 * Siembra de `cropId` en `year` en el índice local `sowLocal` (0 = 1 de abril) con la lluvia de `rain` (paquete ERA5 con otra lluvia),
 * suelo `soil` y secano, con el balance de simulateDays y el rendimiento de stageYield (los mismos de runSequence).
 * relYield vale 0 si el ciclo no termina antes del 31 de marzo (convención del repositorio); `cycleCompletes` lo dice aparte.
 */
export function simulateSowing({ bundle, et0, rain, crops, soil, year, cropId, sowLocal, factors = null }) {
  const startIdx = bundle.dates.indexOf(`${year}-04-01`);
  const endIdx = bundle.dates.indexOf(`${year + 1}-03-31`);
  const end = endIdx + 1;
  const dates = bundle.dates.slice(startIdx, end);
  const r = rain.slice(startIdx, end);
  const e0 = et0.slice(startIdx, end);
  const tmean = bundle.tmax.slice(startIdx, end).map((t, i) => (t + bundle.tmin[startIdx + i]) / 2);
  const crop = crops.get(cropId);
  const phase = buildPhase(crop, sowLocal, tmean);
  const sim = simulateDays({ rain: r, et0: e0, phases: [phase], crops, texture: soil, slopeClass: 'flat', irrigation: 'none', residueMask: Array(dates.length).fill(false) });
  const { relYield: relYieldWater } = stageYield(crop, phase, { et0: e0, ks: sim.ks });
  let stressDays = 0;
  for (let i = phase.sowIdx; i <= phase.harvestIdx; i++) if (sim.ks[i] < KS_STRESS) stressDays++;
  const out = {
    sowDate: dates[phase.sowIdx], harvestDate: dates[phase.harvestIdx], cycleCompletes: !phase.cycleIncomplete,
    relYield: phase.cycleIncomplete ? 0 : relYieldWater, stressDays, cycleDays: phase.harvestIdx - phase.sowIdx + 1,
  };
  if (!factors) return out; // opt-in (Tarea 36): sin `factors` el resultado es el de siempre
  const tmax = bundle.tmax.slice(startIdx, end); const tmin = bundle.tmin.slice(startIdx, end);
  const fl = applyFactors({ cropId, relYield: relYieldWater, tmax, tmin, flowerIdx: [Math.min(phase.floweringIdx[0], dates.length - 1), Math.min(phase.floweringIdx[1], dates.length - 1)], factors });
  return { ...out, relYieldWaterOnly: out.relYield, relYield: phase.cycleIncomplete ? 0 : fl.relYield, heatMultiplier: fl.heat ? fl.heat.mean : null, heatMinCoefficient: fl.heat ? fl.heat.min : null, heatDaysBelow1: fl.heat ? fl.heat.daysBelow1 : null, fertilityMultiplier: fl.fertility };
}

/** Índice local de siembra: 'onset' = regla de inicio de lluvias con `rain`; o 'MM-DD' del año `year`; `offsetDays` se suma al inicio. */
export function sowLocalIndex(bundle, rain, year, when, offsetDays = 0) {
  const startIdx = bundle.dates.indexOf(`${year}-04-01`);
  const endIdx = bundle.dates.indexOf(`${year + 1}-03-31`);
  if (when === 'onset') return Math.min(endIdx - startIdx, Math.max(0, onsetSowIdx(rain, bundle.dates, year).idx - startIdx + offsetDays));
  const i = bundle.dates.indexOf(`${year}-${when}`);
  if (i < 0) throw new Error(`fecha ${when} fuera de los datos`);
  return i - startIdx;
}

/**
 * Percentil por rango medio de `value` entre `values` (que lo incluyen): (#menores + 0.5·#iguales) / n. 0 = el peor año, 1 = el mejor.
 * Con empates (muchos años en 1.0 o en 0) el rango medio no favorece a ningún lado.
 */
export function percentile(values, value) {
  let lt = 0; let eq = 0;
  for (const v of values) { if (v < value) lt++; else if (v === value) eq++; }
  return (lt + 0.5 * eq) / values.length;
}

/** Puesto (1 = el peor) = 1 + #años estrictamente peores; `tied` = cuántos años tienen exactamente ese valor. */
export function rankWorst(values, value) {
  return { rank: 1 + values.filter((v) => v < value).length, tied: values.filter((v) => v === value).length, of: values.length };
}

/** Acierto: el percentil está en el peor tercio (percentil <= 1/3, umbral fijado de antemano). */
export const isHit = (pct) => pct <= WORST_THIRD + 1e-12;

/** AUC (Mann-Whitney, empates cuentan 1/2): P(puntaje de un evento > puntaje de un control). null si falta alguno de los dos grupos. */
export function auc(eventScores, controlScores) {
  if (!eventScores.length || !controlScores.length) return null;
  let s = 0;
  for (const e of eventScores) for (const c of controlScores) s += e > c ? 1 : e === c ? 0.5 : 0;
  return s / (eventScores.length * controlScores.length);
}

export const SWITCH_MARGIN = 0.05; // regla fijada de antemano: otra fuente reemplaza a ERA5 solo si su AUC supera al de ERA5 en al menos 0.05

/**
 * Regla preregistrada para elegir la fuente de lluvia (con los eventos de 2001-2016 únicamente): gana la fuente de mayor AUC;
 * reemplaza a ERA5 solo si su AUC supera al de ERA5 en al menos SWITCH_MARGIN; si no, se queda ERA5. Una fuente con AUC null no compite.
 * Un empate en el máximo se resuelve a favor de ERA5 si participa, si no a favor de la primera en el orden dado.
 */
export function chooseRainSource(aucBySource, margin = SWITCH_MARGIN) {
  const era5 = aucBySource.ERA5;
  const entries = Object.entries(aucBySource).filter(([, v]) => v != null);
  if (era5 == null || !entries.length) return { recommended: 'ERA5', switched: false, best: null, reason: 'ERA5 has no AUC on these events, so nothing can be compared; ERA5 stays' };
  const top = Math.max(...entries.map(([, v]) => v));
  const best = entries.filter(([, v]) => v === top).map(([k]) => k);
  const winner = best.includes('ERA5') ? 'ERA5' : best[0];
  const diff = top - era5;
  if (winner !== 'ERA5' && diff >= margin - 1e-12) return { recommended: winner, switched: true, best: winner, margin: diff, reason: `${winner} beats ERA5 by ${diff.toFixed(3)} AUC (>= ${margin})` };
  return { recommended: 'ERA5', switched: false, best: winner, margin: diff, reason: winner === 'ERA5' ? 'ERA5 has the highest AUC' : `${winner} has the highest AUC but beats ERA5 by only ${diff.toFixed(3)} (< ${margin}); ERA5 stays` };
}
