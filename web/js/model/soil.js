// Suelo, escorrentía SCS-CN y agua disponible. Unidades: mm, m, m3/m3.
const SRC_THETA = 'FAO-56 (Allen et al., 1998), cuadro 19, punto medio';
const SRC_CN = 'USDA-NRCS TR-55, cuadro 2-2b';

export const SOILS = {
  sand: { thetaFC: 0.12, thetaWP: 0.045, hydrologicGroup: 'A', cn: { crop: 67, residue: 64, bare: 77 }, source: `${SRC_THETA}; CN: ${SRC_CN}` },
  loam: { thetaFC: 0.25, thetaWP: 0.12, hydrologicGroup: 'B', cn: { crop: 78, residue: 75, bare: 86 }, source: `${SRC_THETA}; CN: ${SRC_CN}` },
  clay: { thetaFC: 0.36, thetaWP: 0.22, hydrologicGroup: 'D', cn: { crop: 89, residue: 85, bare: 94 }, source: `${SRC_THETA}; CN: ${SRC_CN}` },
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

const isNum = (v) => typeof v === 'number' && Number.isFinite(v);

/**
 * Suelo del simulador: una clave de SOILS ('sand'|'loam'|'clay') o un objeto
 * {thetaFC, thetaWP, cn: {crop, residue, bare}, source, label?} (p. ej. SoilGrids en un piloto).
 * Cualquier otra forma lanza error.
 */
export function resolveSoil(texture) {
  if (typeof texture === 'string') {
    const soil = SOILS[texture];
    if (!soil) throw new Error(`Textura desconocida: ${texture}`);
    return soil;
  }
  if (texture === null || typeof texture !== 'object') throw new Error(`Textura desconocida: ${String(texture)}`);
  const { thetaFC, thetaWP, cn, source } = texture;
  if (!isNum(thetaFC) || !isNum(thetaWP)) throw new Error('Suelo inválido: thetaFC y thetaWP deben ser números');
  if (!(thetaWP > 0 && thetaFC > thetaWP && thetaFC < 1)) throw new Error(`Suelo inválido: se exige 0 < thetaWP < thetaFC < 1 (${thetaWP}, ${thetaFC})`);
  if (!cn || !['crop', 'residue', 'bare'].every((k) => isNum(cn[k]))) throw new Error('Suelo inválido: cn debe tener crop, residue y bare numéricos');
  if (typeof source !== 'string' || !source) throw new Error('Suelo inválido: falta source (un parámetro sin fuente no se usa)');
  return texture;
}

/** Número de curva según suelo (clave u objeto), cobertura ('crop'|'residue'|'bare') y pendiente. */
export function curveNumber(texture, cover, slopeClass) {
  const soil = resolveSoil(texture);
  if (!(slopeClass in CN_SLOPE_ADJ)) throw new Error(`Clase de pendiente desconocida: ${slopeClass}`);
  const base = soil.cn[cover];
  if (base === undefined) throw new Error(`Cobertura desconocida: ${cover}`);
  return Math.max(30, Math.min(98, base + CN_SLOPE_ADJ[slopeClass]));
}

/**
 * Clase de textura USDA (triángulo de textura, USDA Soil Survey Manual, cap. 3) desde arcilla y arena en %.
 * limo = 100 − arcilla − arena. Los nombres van en inglés (clave técnica).
 */
export function usdaTextureClass(clayPct, sandPct) {
  if (!isNum(clayPct) || !isNum(sandPct) || clayPct < 0 || sandPct < 0) throw new Error(`clay y sand deben ser porcentajes >= 0 (${clayPct}, ${sandPct})`);
  const silt = 100 - clayPct - sandPct;
  if (silt < -0.5) throw new Error(`clay + sand no puede pasar de 100 (${clayPct} + ${sandPct})`);
  const c = clayPct; const sa = sandPct; const si = Math.max(0, silt);
  if (si + 1.5 * c < 15) return 'sand';
  if (si + 1.5 * c >= 15 && si + 2 * c < 30) return 'loamy sand';
  if ((c >= 7 && c < 20 && sa > 52 && si + 2 * c >= 30) || (c < 7 && si < 50 && si + 2 * c >= 30)) return 'sandy loam';
  if (c >= 7 && c < 27 && si >= 28 && si < 50 && sa <= 52) return 'loam';
  if ((si >= 50 && c >= 12 && c < 27) || (si >= 50 && si < 80 && c < 12)) return 'silt loam';
  if (si >= 80 && c < 12) return 'silt';
  if (c >= 20 && c < 35 && si < 28 && sa > 45) return 'sandy clay loam';
  if (c >= 27 && c < 40 && sa > 20 && sa <= 45) return 'clay loam';
  if (c >= 27 && c < 40 && sa <= 20) return 'silty clay loam';
  if (c >= 35 && sa > 45) return 'sandy clay';
  if (c >= 40 && si >= 40) return 'silty clay';
  if (c >= 40 && sa <= 45 && si < 40) return 'clay';
  throw new Error(`Sin clase USDA para clay ${clayPct}, sand ${sandPct}`);
}

// Grupo hidrológico desde la clase de textura (TR-55 apéndice A, Disturbed soil profiles). 'silt' no está en esa tabla: se asigna B por analogía con silt loam.
const HYDROLOGIC_GROUP = {
  sand: 'A', 'loamy sand': 'A', 'sandy loam': 'A',
  loam: 'B', 'silt loam': 'B', silt: 'B',
  'sandy clay loam': 'C',
  'clay loam': 'D', 'silty clay loam': 'D', 'sandy clay': 'D', 'silty clay': 'D', clay: 'D',
};
export const HYDROLOGIC_GROUP_SOURCE = 'Grupo hidrológico por la textura del suelo superficial: USDA-SCS TR-55 (1986), apéndice A, "Disturbed soil profiles" (Brakensiek y Rawls, 1983)';

export function hydrologicGroupOf(usdaClass) {
  const g = HYDROLOGIC_GROUP[usdaClass];
  if (!g) throw new Error(`Clase de textura sin grupo hidrológico: ${usdaClass}`);
  return g;
}

// USDA-NRCS TR-55, cuadro 2-2b (tierras cultivadas): crop = hileras rectas (SR) condición buena; residue = SR + residuo (CR) buena;
// bare = barbecho en suelo desnudo. A, B y D son las filas que ya usan las clases sand, loam y clay.
const CN_BY_GROUP = {
  A: { crop: 67, residue: 64, bare: 77 },
  B: { crop: 78, residue: 75, bare: 86 },
  C: { crop: 85, residue: 82, bare: 91 },
  D: { crop: 89, residue: 85, bare: 94 },
};
export const CN_TABLE_SOURCE = SRC_CN;

export function cnForGroup(group) {
  const row = CN_BY_GROUP[group];
  if (!row) throw new Error(`Grupo hidrológico desconocido: ${group}`);
  return { ...row };
}

/** Clase del simulador ('sand'|'loam'|'clay') con el agua disponible (θFC − θWP) más cercana. */
export function nearestTexture(thetaFC, thetaWP) {
  const aw = thetaFC - thetaWP;
  let best = null; let bestDiff = Infinity;
  for (const [key, soil] of Object.entries(SOILS)) {
    const diff = Math.abs(soil.thetaFC - soil.thetaWP - aw);
    if (diff < bestDiff) { best = key; bestDiff = diff; }
  }
  return best;
}
