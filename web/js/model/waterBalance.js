// Balance hídrico diario en la zona radicular (FAO-56 ecs. 84-85). Unidades: mm, m.
import { SOILS, totalAvailableWater, scsRunoff, curveNumber } from './soil.js';
import { kcOnDay } from './phenology.js';

const BARE_KC = 0.15;
const BARE_ZR = 0.15;
const BARE_P = 0.5;
const IRRIGATION_MODES = ['none', 'limited', 'full'];

/** FAO-56 ec. 85: Dr = Dr_prev − (P − RO) − I + ETc_aj; lo que baja de 0 es drenaje profundo. */
export function stepDepletion({ drPrev, rain, runoff, irr, etcAdj, taw }) {
  const raw = drPrev - (rain - runoff) - irr + etcAdj;
  return { dr: Math.min(taw, Math.max(0, raw)), deepPerc: Math.max(0, -raw) };
}

/** FAO-56 ec. 84: Ks = (TAW − Dr)/((1 − p)·TAW) si Dr > RAW, si no 1. */
export function stressCoefficient(dr, taw, p) {
  const raw = p * taw;
  if (dr <= raw) return 1;
  return Math.max(0, (taw - dr) / ((1 - p) * taw));
}

/** Zr (m) de una fase en el día idx: lineal de 0.15 m al sembrar a zrMax al fin de dev. */
function rootDepth(crop, phase, idx) {
  const span = phase.endIdx.dev - phase.sowIdx;
  if (!(span > 0)) return crop.zrMax;
  const f = Math.min(1, (idx - phase.sowIdx) / span);
  return BARE_ZR + (crop.zrMax - BARE_ZR) * f;
}

/**
 * Simula el balance diario. Fases activas el día i: sowIdx ≤ i ≤ harvestIdx.
 * Kc y Zr = máximo de las activas; p = el del cultivo activo con mayor Kc ese día.
 * residueMask (opcional): día sin fase activa con residuo de abono verde → cobertura 'residue' (CN menor; Kc sigue 0.15).
 * El riego se aplica al final del día, después de calcular Dr.
 * Supuesto: drInit por defecto = TAW del primer día, es decir, solo la capa superior de
 * 0.15 m (zona sin cultivo) arranca seca al inicio del año agrícola, fin de la estación seca.
 * Con riego 'full' el predio arranca a capacidad de campo (drInit = 0), porque un predio
 * regado no empieza el ciclo en marchitez.
 * Supuesto (simplificación, revisar en la Tarea 8): cuando las raíces crecen y TAW aumenta,
 * Dr no cambia, así que el suelo nuevo que alcanzan las raíces se supone a capacidad de campo
 * (agotamiento 0) aunque venga de la estación seca. Esto agrega agua al crecer las raíces.
 */
export function simulateDays({ rain, et0, phases, crops, texture, slopeClass, irrigation, drInit, residueMask }) {
  if (!IRRIGATION_MODES.includes(irrigation)) throw new Error(`Riego desconocido: ${irrigation}`);
  const soil = SOILS[texture];
  if (!soil) throw new Error(`Textura desconocida: ${texture}`);
  const n = rain.length;
  const last = n - 1;
  const tawOf = (zr) => totalAvailableWater(soil.thetaFC, soil.thetaWP, zr);
  const out = { dr: [], ks: [], kc: [], etc: [], eta: [], irr: [], runoff: [], cover: [], taw: [] };

  let dr = 0;
  for (let i = 0; i < n; i++) {
    const active = phases.filter((ph) => ph.sowIdx <= i && i <= ph.harvestIdx);
    let kc = BARE_KC;
    let zr = BARE_ZR;
    let p = BARE_P;
    if (active.length) {
      kc = 0;
      for (const ph of active) {
        const crop = crops.get(ph.cropId);
        const k = kcOnDay(crop, ph, i);
        zr = Math.max(zr, rootDepth(crop, ph, i));
        if (k > kc) { kc = k; p = crop.p; }
      }
    }
    const taw = tawOf(zr);
    if (i === 0) dr = drInit ?? (irrigation === 'full' ? 0 : taw);
    // Dr se conserva cuando TAW crece: el suelo recién alcanzado por las raíces entra a capacidad de campo.
    // Cuando TAW baja (fase nueva con raíz corta), Dr se acota a TAW.
    dr = Math.min(taw, Math.max(0, dr));

    const ks = stressCoefficient(dr, taw, p);
    const etc = kc * et0[i];
    const eta = ks * etc;
    const cover = active.length ? 'crop' : (residueMask?.[i] ? 'residue' : 'bare');
    const runoff = scsRunoff(rain[i], curveNumber(texture, cover, slopeClass));
    dr = stepDepletion({ drPrev: dr, rain: rain[i], runoff, irr: 0, etcAdj: eta, taw }).dr;

    let irr = 0;
    if (irrigation !== 'none' && active.length && dr > p * taw) {
      const inWindow = irrigation === 'full' || active.some((ph) => {
        const a = Math.min(ph.floweringIdx[0], last);
        const b = Math.min(ph.floweringIdx[1], last);
        return i >= a && i <= b;
      });
      if (inWindow) { irr = dr; dr = 0; }
    }

    out.dr.push(dr); out.ks.push(ks); out.kc.push(kc); out.etc.push(etc); out.eta.push(eta);
    out.irr.push(irr); out.runoff.push(runoff); out.cover.push(cover); out.taw.push(taw);
  }
  return out;
}
