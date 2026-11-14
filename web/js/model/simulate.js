// Simulación de una secuencia de cultivos sobre cada año agrícola (1 abr Y → 31 mar Y+1).
import { et0PenmanMonteith } from './et0.js';
import { buildPhase, kcOnDay, onsetSowIdx } from './phenology.js';
import { simulateDays } from './waterBalance.js';

export const KS_STRESS = 0.7;

const clamp = (x, lo, hi) => Math.min(hi, Math.max(lo, x));
const sum = (a) => a.reduce((s, x) => s + x, 0);

function dayOfYear(date) {
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

/** Métricas de un cultivo en sus propios días; Ks compartido, Kc propio (útil cuando las fases se traslapan). */
function cropYear({ phase, crop, sl, active }) {
  const { sowIdx, harvestIdx } = phase;
  let num = 0;
  let den = 0;
  let irrigationMm = 0;
  for (let i = sowIdx; i <= harvestIdx; i++) {
    const w = kcOnDay(crop, phase, i) * sl.et0[i];
    num += sl.ks[i] * w;
    den += w;
    irrigationMm += sl.irr[i] / active[i];
  }
  const etaOverEtc = den > 0 ? num / den : 1;
  const last = sl.ks.length - 1;
  const a = Math.min(phase.floweringIdx[0], last);
  const b = Math.min(phase.floweringIdx[1], last);
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
    relYield: crop.ky == null ? null : clamp(1 - crop.ky * (1 - etaOverEtc), 0, 1),
    harvestRainEvent,
    irrigationMm,
    cycleIncomplete: phase.cycleIncomplete,
  };
}

/** Simula la secuencia en cada año agrícola completo. [] si exige riego y irrigation === 'none'. */
export function runSequence({ sequence, bundle, et0, crops, texture, slopeClass, irrigation }) {
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
    for (const spec of sequence.phases) {
      let sowIdx;
      if (spec.sow === 'onset') {
        const o = onsetSowIdx(bundle.rain, bundle.dates, year);
        sowIdx = o.idx - startIdx;
        if (o.onsetFallback) onsetFallback = true;
      } else if (typeof spec.sow === 'string') {
        const mm = Number(spec.sow.slice(0, 2));
        sowIdx = localIdx(`${mm >= 4 ? year : year + 1}-${spec.sow}`);
      } else {
        sowIdx = phases[spec.sow.relayOf].sowIdx + spec.sow.daysAfterSow;
      }
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
