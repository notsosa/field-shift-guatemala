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
  const stageGddCum = {};
  let acc = 0;
  for (const s of STAGES) { acc += gdd[s]; stageGddCum[s] = acc; }
  const gddCum = [];
  let run = 0;
  for (let i = sowIdx; i <= endIdx.late; i++) { run += Math.max(0, tmean[i] - crop.tbase); gddCum.push(run); }
  const a = endIdx.dev + 1;
  const b = a + Math.max(0, Math.round(0.4 * (endIdx.mid - endIdx.dev)) - 1);
  return { cropId: crop.id, sowIdx, endIdx, harvestIdx: endIdx.late, floweringIdx: [a, b], cycleIncomplete, gddCum, stageGddCum };
}

/** Fase de un cultivo perenne (café): activo todos los días 0..n-1, sin siembra ni cosecha, sin ciclo por GDD. */
export function buildPerennialPhase(crop, n) {
  const last = n - 1;
  return { cropId: crop.id, sowIdx: 0, endIdx: { ini: 0, dev: 0, mid: last, late: last }, harvestIdx: last, floweringIdx: [0, -1], cycleIncomplete: false, perennial: true, gddCum: [], stageGddCum: {} };
}

/** Kc del día idx: constante en ini y mid, lineal en dev y late; 0 fuera del ciclo. */
export function kcOnDay(crop, phase, idx) {
  const { endIdx, sowIdx, harvestIdx } = phase;
  const { kc } = crop;
  if (idx < sowIdx || idx > harvestIdx) return 0;
  if (crop.perennial) return kc.mid; // perenne: un solo Kc todo el año (el de la etapa media de FAO-56)
  // Interpolación por fracción de GDD acumulada de la etapa hasta el día idx.
  const lerp = (from, to, prevStage, stage) => {
    const lo = phase.stageGddCum[prevStage];
    const span = phase.stageGddCum[stage] - lo;
    if (!(span > 0)) return to;
    const f = (phase.gddCum[idx - sowIdx] - lo) / span;
    return from + (to - from) * Math.min(1, Math.max(0, f));
  };
  if (idx <= endIdx.ini) return kc.ini;
  if (idx <= endIdx.dev) return lerp(kc.ini, kc.mid, 'ini', 'dev');
  if (idx <= endIdx.mid) return kc.mid;
  return lerp(kc.mid, kc.end, 'mid', 'late');
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
