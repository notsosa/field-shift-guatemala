// Simulación de una secuencia de cultivos sobre cada año agrícola (1 abr Y → 31 mar Y+1).
import { et0PenmanMonteith } from './et0.js';
import { buildPhase, kcOnDay, onsetSowIdx } from './phenology.js';
import { simulateDays } from './waterBalance.js';

export const KS_STRESS = 0.7;

const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
const sum = (a) => a.reduce((s, x) => s + x, 0);

export function dayOfYear(date) {
  const [y, m, d] = date.split('-').map(Number);
  return Math.round((Date.UTC(y, m - 1, d) - Date.UTC(y, 0, 0)) / 864e5);
}

/** ET0 diaria (mm/día) FAO-56 Penman-Monteith con ea derivada del punto de rocío. */
export function computeEt0Series(bundle) {
  return bundle.dates.map((date, i) => et0PenmanMonteith({
    tmax: bundle.tmax[i], tmin: bundle.tmin[i], tdew: bundle.tdew[i], rs: bundle.rs[i], u2: bundle.u2[i],
    pressure: bundle.pressure[i], elevation: bundle.elevation, latDeg: bundle.lat, doy: dayOfYear(date),
  }));
}

/** Años agrícolas completos: [{year, startIdx, endIdx}] con índices inclusivos. */
export function agriculturalYears(dates) {
  const out = [];
  const first = Number(dates[0].slice(0, 4));
  const lastYear = Number(dates[dates.length - 1].slice(0, 4));
  for (let year = first; year <= lastYear; year++) {
    const startIdx = dates.indexOf(`${year}-04-01`);
    const endIdx = dates.indexOf(`${year + 1}-03-31`);
    if (startIdx >= 0 && endIdx >= 0) out.push({ year, startIdx, endIdx });
  }
  return out;
}

/**
 * Siembra del cultivo principal (fase 0, 'onset'): inicio de lluvias + desfase, acotada al año agrícola.
 * idx es local al año (0 = 1 de abril). Lo usan runSequence y phenoFeatures del emulador.
 */
export function resolveMainSowIdx(bundle, year, sowOffsetDays = 0) {
  const startIdx = bundle.dates.indexOf(`${year}-04-01`);
  const endIdx = bundle.dates.indexOf(`${year + 1}-03-31`);
  if (startIdx < 0 || endIdx < 0) throw new Error(`Año agrícola ${year} incompleto`);
  const o = onsetSowIdx(bundle.rain, bundle.dates, year);
  return { idx: clamp(o.idx - startIdx + sowOffsetDays, 0, endIdx - startIdx), onsetFallback: o.onsetFallback };
}

/** Ventana de floración [a, b] (índices locales) acotada al último día del año agrícola; única fuente para ksFlowerMean y stageYield. */
export function floweringWindow(phase, lastIdx) {
  return [Math.min(phase.floweringIdx[0], lastIdx), Math.min(phase.floweringIdx[1], lastIdx)];
}

/**
 * Rendimiento relativo por Ky de FAO-33. Por etapa i: ratio_i = Σ(ks·Kc·ET0)/Σ(Kc·ET0) en sus días (Kc del propio cultivo) y
 * factor_i = clamp(1 − ky_i·(1 − ratio_i), 0, 1); relYield = Π factor_i (efectos de etapa multiplicativos: producto de fracciones de rendimiento, regla del
 * método por balance diario de CROPWAT según WEAP/SEI; FAO-66 cap. 2 solo describe CROPWAT sin dar la fórmula). Etapas vacías valen 1. Sin kyStages se usa la fórmula estacional.
 * Ventanas (índices locales): veg = siembra..fin de desarrollo; flor = ventana de floración acotada;
 * formación = tras la floración..fin de mid; maduración = tras mid..cosecha.
 * sl = { et0, ks } (diarios del año agrícola). Devuelve { etaOverEtc, relYieldSeasonal, relYield, stageRatios }.
 */
export function stageYield(crop, phase, sl) {
  const { sowIdx, harvestIdx, endIdx } = phase;
  const ratio = (lo, hi) => {
    let num = 0;
    let den = 0;
    for (let i = lo; i <= hi; i++) {
      const w = kcOnDay(crop, phase, i) * sl.et0[i];
      num += sl.ks[i] * w;
      den += w;
    }
    return den > 0 ? num / den : null;
  };
  const etaOverEtc = ratio(sowIdx, harvestIdx) ?? 1;
  const relYieldSeasonal = crop.ky == null ? null : clamp(1 - crop.ky * (1 - etaOverEtc), 0, 1);
  if (crop.ky == null || crop.kyStages == null) {
    return { etaOverEtc, relYieldSeasonal, relYield: relYieldSeasonal, stageRatios: null };
  }
  const [fa, fb] = floweringWindow(phase, sl.ks.length - 1);
  const stageRatios = {
    veg: ratio(sowIdx, endIdx.dev),
    flower: ratio(fa, fb),
    yieldForm: ratio(fb + 1, endIdx.mid),
    ripen: ratio(endIdx.mid + 1, harvestIdx),
  };
  let relYield = 1;
  for (const [stage, r] of Object.entries(stageRatios)) {
    if (r != null) relYield *= clamp(1 - crop.kyStages[stage] * (1 - r), 0, 1);
  }
  return { etaOverEtc, relYieldSeasonal, relYield, stageRatios };
}

/** Métricas de un cultivo en sus propios días; Ks compartido, Kc propio (útil cuando las fases se traslapan). */
function cropYear({ phase, crop, sl, active }) {
  const { sowIdx, harvestIdx } = phase;
  let irrigationMm = 0;
  for (let i = sowIdx; i <= harvestIdx; i++) irrigationMm += sl.irr[i] / active[i];
  const { etaOverEtc, relYieldSeasonal, relYield, stageRatios } = stageYield(crop, phase, sl);
  const [a, b] = floweringWindow(phase, sl.ks.length - 1);
  const ksFlowerMean = sum(sl.ks.slice(a, b + 1)) / (b - a + 1);
  let harvestRainEvent = false;
  if (crop.harvestRainSensitive) {
    let wet = 0;
    for (let i = Math.max(0, harvestIdx - 9); i <= harvestIdx; i++) if (sl.rain[i] > 10) wet++;
    harvestRainEvent = wet >= 2;
  }
  return {
    cropId: crop.id,
    sowDate: sl.dates[sowIdx],
    harvestDate: sl.dates[harvestIdx],
    etaOverEtc,
    ksFlowerMean,
    stressFlowering: ksFlowerMean < KS_STRESS,
    relYield,
    relYieldSeasonal,
    stageRatios,
    harvestRainEvent,
    irrigationMm,
    cycleIncomplete: phase.cycleIncomplete,
  };
}

/** Simula la secuencia en cada año agrícola completo. [] si exige riego y irrigation === 'none'. */
export function runSequence({ sequence, bundle, et0, crops, texture, slopeClass, irrigation, sowOffsetDays = 0 }) {
  if (sequence.requiresIrrigation && irrigation === 'none') return [];
  return agriculturalYears(bundle.dates).map(({ year, startIdx, endIdx }) => {
    const end = endIdx + 1;
    const sl = {
      dates: bundle.dates.slice(startIdx, end),
      rain: bundle.rain.slice(startIdx, end),
      et0: et0.slice(startIdx, end),
    };
    const tmean = bundle.tmax.slice(startIdx, end).map((t, i) => (t + bundle.tmin[startIdx + i]) / 2);
    const localIdx = (date) => {
      const i = sl.dates.indexOf(date);
      if (i < 0) throw new Error(`Fecha ${date} fuera del año agrícola ${year}`);
      return i;
    };

    let onsetFallback = false;
    const phases = [];
    for (const [k, spec] of sequence.phases.entries()) {
      let sowIdx;
      if (spec.sow === 'onset') {
        const o = resolveMainSowIdx(bundle, year, k === 0 ? sowOffsetDays : 0);
        sowIdx = o.idx;
        if (o.onsetFallback) onsetFallback = true;
      } else if (typeof spec.sow === 'string') {
        const mm = Number(spec.sow.slice(0, 2));
        sowIdx = localIdx(`${mm >= 4 ? year : year + 1}-${spec.sow}`);
      } else {
        sowIdx = phases[spec.sow.relayOf].sowIdx + spec.sow.daysAfterSow;
      }
      // El desfase solo mueve la fase 0 (los relevos la siguen); para 'onset' ya lo aplicó resolveMainSowIdx.
      if (k === 0 && spec.sow !== 'onset') sowIdx = clamp(sowIdx + sowOffsetDays, 0, sl.dates.length - 1);
      phases.push(buildPhase(crops.get(spec.cropId), sowIdx, tmean));
    }

    const residueMask = Array(sl.dates.length).fill(false);
    for (const ph of phases) {
      if (crops.get(ph.cropId).residueCover) residueMask.fill(true, ph.harvestIdx + 1);
    }
    const sim = simulateDays({ rain: sl.rain, et0: sl.et0, phases, crops, texture, slopeClass, irrigation, residueMask });
    const active = sl.dates.map((_, i) => Math.max(1, phases.filter((ph) => ph.sowIdx <= i && i <= ph.harvestIdx).length));
    const slim = { ...sl, ks: sim.ks, irr: sim.irr };

    let bareDaysRainy = 0;
    let runoffBareMm = 0;
    for (let i = localIdx(`${year}-05-01`); i <= localIdx(`${year}-11-30`); i++) {
      if (sim.cover[i] === 'bare') { bareDaysRainy++; runoffBareMm += sim.runoff[i]; }
    }
    return {
      year,
      crops: phases.map((phase) => cropYear({ phase, crop: crops.get(phase.cropId), sl: slim, active })),
      bareDaysRainy,
      runoffBareMm,
      irrigationMm: sum(sim.irr),
      onsetFallback,
      cycleIncomplete: phases.some((ph) => ph.cycleIncomplete),
    };
  });
}
