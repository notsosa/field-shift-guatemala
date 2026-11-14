// Suelo, escorrentía SCS-CN y agua disponible. Unidades: mm, m, m3/m3.
const SRC_THETA = 'FAO-56 (Allen et al., 1998), cuadro 19, punto medio';
const SRC_CN = 'USDA-NRCS TR-55, cuadro 2-2b';

export const SOILS = {
  sand: { thetaFC: 0.12, thetaWP: 0.045, hydrologicGroup: 'A', cn: { crop: 67, residue: 64, bare: 77 }, source: `${SRC_THETA}; CN: ${SRC_CN}` },
  loam: { thetaFC: 0.25, thetaWP: 0.12, hydrologicGroup: 'B', cn: { crop: 78, residue: 75, bare: 86 }, source: `${SRC_THETA}; CN: ${SRC_CN}` },
  clay: { thetaFC: 0.36, thetaWP: 0.22, hydrologicGroup: 'D', cn: { crop: 89, residue: 87, bare: 94 }, source: `${SRC_THETA}; CN: ${SRC_CN}` },
};

export const SLOPE_CLASSES = {
  flat: { pct: 2, erosionFactor: 0.5 },
  moderate: { pct: 8, erosionFactor: 1 },
  steep: { pct: 20, erosionFactor: 2 },
};

const CN_SLOPE_ADJ = { flat: -3, moderate: 0, steep: 5 };

/** Agua total disponible en la zona radicular (mm): 1000(θFC−θWP)·Zr. */
export function totalAvailableWater(thetaFC, thetaWP, zrM) {
  return 1000 * (thetaFC - thetaWP) * zrM;
}

/** Escorrentía SCS (mm) con Ia = 0.2·S. */
export function scsRunoff(pMm, cn) {
  if (!(pMm > 0)) return 0;
  const s = 25400 / cn - 254;
  const ia = 0.2 * s;
  if (pMm <= ia) return 0;
  return ((pMm - ia) ** 2) / (pMm + 0.8 * s);
}

/** Número de curva según textura, cobertura ('crop'|'residue'|'bare') y pendiente. */
export function curveNumber(texture, cover, slopeClass) {
  const soil = SOILS[texture];
  if (!soil) throw new Error(`Textura desconocida: ${texture}`);
  if (!(slopeClass in CN_SLOPE_ADJ)) throw new Error(`Clase de pendiente desconocida: ${slopeClass}`);
  const base = soil.cn[cover];
  if (base === undefined) throw new Error(`Cobertura desconocida: ${cover}`);
  return Math.max(30, Math.min(98, base + CN_SLOPE_ADJ[slopeClass]));
}
