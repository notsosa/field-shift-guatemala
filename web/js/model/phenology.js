// Fenología por grados-día (GDD), curva Kc de FAO-56 y regla de inicio de lluvias.
export const TREF = 26;

const STAGES = ['ini', 'dev', 'mid', 'late'];
const EPS = 1e-9;

/** GDD por etapa a temperatura de referencia: días × (TREF − tbase). */
export function stageGdd(crop) {
  const out = {};
  for (const s of STAGES) out[s] = crop.days[s] * (TREF - crop.tbase);
  return out;
}

/** Fases del cultivo sembrado en sowIdx; los GDD acumulan max(0, tmean − tbase) desde sowIdx inclusive. */
export function buildPhase(crop, sowIdx, tmean) {
  const gdd = stageGdd(crop);
  const last = tmean.length - 1;
  const endIdx = {};
  let stage = 0;
  let thr = gdd[STAGES[0]];
  let cum = 0;
  for (let i = sowIdx; i <= last && stage < STAGES.length; i++) {
    cum += Math.max(0, tmean[i] - crop.tbase);
    while (stage < STAGES.length && cum >= thr - EPS) {
      endIdx[STAGES[stage]] = i;
      stage++;
      if (stage < STAGES.length) thr += gdd[STAGES[stage]];
    }
  }
  const cycleIncomplete = stage < STAGES.length;
  for (; stage < STAGES.length; stage++) endIdx[STAGES[stage]] = last;
  const a = endIdx.dev + 1;
  const b = a + Math.max(0, Math.round(0.4 * (endIdx.mid - endIdx.dev)) - 1);
  return { cropId: crop.id, sowIdx, endIdx, harvestIdx: endIdx.late, floweringIdx: [a, b], cycleIncomplete };
}

/** Kc del día idx: constante en ini y mid, lineal en dev y late; 0 fuera del ciclo. */
export function kcOnDay(crop, phase, idx) {
  const { endIdx, sowIdx, harvestIdx } = phase;
  const { kc } = crop;
  if (idx < sowIdx || idx > harvestIdx) return 0;
  const lerp = (from, to, prevEnd, end) => {
    const len = end - prevEnd;
    return len > 0 ? from + (to - from) * ((idx - prevEnd) / len) : to;
  };
  if (idx <= endIdx.ini) return kc.ini;
  if (idx <= endIdx.dev) return lerp(kc.ini, kc.mid, endIdx.ini, endIdx.dev);
  if (idx <= endIdx.mid) return kc.mid;
  return lerp(kc.mid, kc.end, endIdx.mid, endIdx.late);
}

/** Inicio de lluvias: primer día desde el 1 de mayo con ≥ 20 mm en 3 días; si no, 15 de junio (respaldo). */
export function onsetSowIdx(rain, dates, year) {
  const iStart = dates.indexOf(`${year}-05-01`);
  const iEnd = dates.indexOf(`${year}-06-14`);
  const iFallback = dates.indexOf(`${year}-06-15`);
  if (iStart < 0 || iEnd < 0 || iFallback < 0) throw new Error(`Fechas del año ${year} ausentes: no se puede calcular el inicio de lluvias`);
  for (let i = iStart + 2; i <= iEnd; i++) {
    if (rain[i - 2] + rain[i - 1] + rain[i] >= 20) return { idx: i, onsetFallback: false };
  }
  return { idx: iFallback, onsetFallback: true };
}
