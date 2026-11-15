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
 *
 * Dos almacenes sobre un perfil de profundidad fija Zp (= mayor zrMax de las fases; 1.0 m si no hay fases):
 *  - zona radicular: agotamiento Dr, capacidad TAWr = 1000·(θFC − θWP)·Zr(t);
 *  - subsuelo (bajo las raíces): agotamiento Ds, capacidad TAWs = 1000·(θFC − θWP)·(Zp − Zr(t)).
 * Cuando Zr cambia, el agotamiento viaja con la capa de suelo que cambia de almacén (se supone uniforme
 * dentro de cada almacén): al crecer, las raíces entran al suelo con el agotamiento del subsuelo (no con
 * agua gratis) y al acortarse (cosecha) la capa que sale conserva su agotamiento. La percolación profunda
 * de la zona radicular rellena primero el subsuelo; solo lo que sobra sale del perfil (drainOut).
 * Condición inicial: con riego 'none'/'limited' todo el perfil arranca seco (Dr = TAWr, Ds = TAWs: fin de
 * la estación seca, 1 de abril); con 'full' ambos arrancan en 0. drInit fija solo Dr; dsInit fija Ds.
 * Conservación: Σrain − Σrunoff + Σirr − Σeta − ΣdrainOut = (Dr0 + Ds0) − (Dr_fin + Ds_fin).
 */
export function simulateDays({ rain, et0, phases, crops, texture, slopeClass, irrigation, drInit, dsInit, residueMask }) {
  if (!IRRIGATION_MODES.includes(irrigation)) throw new Error(`Riego desconocido: ${irrigation}`);
  const soil = SOILS[texture];
  if (!soil) throw new Error(`Textura desconocida: ${texture}`);
  const n = rain.length;
  const last = n - 1;
  const tawOf = (zr) => totalAvailableWater(soil.thetaFC, soil.thetaWP, zr);
  const out = { dr: [], ks: [], kc: [], etc: [], eta: [], irr: [], runoff: [], cover: [], taw: [], ds: [], zr: [], drainOut: [] };

  const zp = phases.length ? Math.max(BARE_ZR, ...phases.map((ph) => crops.get(ph.cropId).zrMax)) : 1.0;
  let dr = 0;
  let ds = 0;
  let zrPrev = BARE_ZR;
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
    if (i === 0) {
      const full = irrigation === 'full';
      dr = Math.min(taw, drInit ?? (full ? 0 : taw));
      ds = dsInit ?? (full ? 0 : tawOf(zp - zr));
    } else if (zr > zrPrev && zp > zrPrev) {
      // Raíces crecen: la capa nueva trae el agotamiento del subsuelo.
      const moved = ds * (zr - zrPrev) / (zp - zrPrev);
      dr += moved; ds -= moved;
    } else if (zr < zrPrev) {
      // Raíces se acortan: la capa que sale conserva su agotamiento.
      const moved = dr * (zrPrev - zr) / zrPrev;
      dr -= moved; ds += moved;
    }
    zrPrev = zr;

    const ks = stressCoefficient(dr, taw, p);
    const etc = kc * et0[i];
    const eta = ks * etc;
    const cover = active.length ? 'crop' : (residueMask?.[i] ? 'residue' : 'bare');
    const runoff = scsRunoff(rain[i], curveNumber(texture, cover, slopeClass));
    const step = stepDepletion({ drPrev: dr, rain: rain[i], runoff, irr: 0, etcAdj: eta, taw });
    dr = step.dr;
    const refill = Math.min(step.deepPerc, ds);
    ds -= refill;
    const drainOut = step.deepPerc - refill;

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
    out.ds.push(ds); out.zr.push(zr); out.drainOut.push(drainOut);
  }
  return out;
}
