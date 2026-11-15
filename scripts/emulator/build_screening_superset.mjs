// Tarea 19, paso 1 del cribado: arma el "superconjunto" de entradas (las 25 actuales + las 7 candidatas de agua antecedente)
// SOLO para las filas de entrenamiento de samples.json. Las filas de prueba (años 2019-2024 o puntos heldOut) se descartan
// antes de calcular nada: ni sus entradas candidatas ni sus objetivos llegan al archivo de salida, así que el cribado
// (screen_features.py) no puede ni calcular una métrica sobre ellas.
// Uso: node scripts/emulator/build_screening_superset.mjs   (requiere samples.json y las cachés de fetch_points.mjs)
// Salida: scripts/emulator/screening_superset.json (ignorado por git; se regenera).
import { readFileSync, writeFileSync } from 'node:fs';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series } from '../../web/js/model/simulate.js';
import { antecedentFeatures, phenoFeatures, ANTECEDENT_CANDIDATES, PHENO_FEATURE_NAMES } from '../../web/js/model/emulator.js';

const here = (p) => new URL(p, import.meta.url);
const readJson = (u) => JSON.parse(readFileSync(u, 'utf8'));
const r4 = (v) => Math.round(v * 1e4) / 1e4;
const samples = readJson(here('./samples.json'));
const points = readJson(here('./points.json'));
const crops = loadCrops(readJson(here('../../web/data/crops.json')));
const held = new Set(points.filter((p) => p.heldOut).map((p) => p.id));
const isTest = (m) => (m.year >= 2019 && m.year <= 2024) || held.has(m.pointId);

const baseNames = ['sowDoy', 'rainFlower', 'drySpellFlower', 'deficitFlower'];
const at = (name) => samples.featureNames.indexOf(name);
if (baseNames.some((n) => at(n) < 0)) throw new Error('samples.json no trae las cuatro entradas de floración');

const keep = [];
samples.meta.forEach((m, i) => { if (!isTest(m)) keep.push(i); }); // <- único lugar donde se decide qué filas se usan
const bundles = {}; const et0s = {}; const cache = new Map();
const X = [], E = [], Y = [], year = [], pointId = [];
for (const i of keep) {
  const m = samples.meta[i];
  if (isTest(m)) throw new Error('fila de prueba en el cribado'); // defensa en profundidad
  bundles[m.pointId] ??= readJson(here(`./cache/${m.pointId}.json`));
  et0s[m.pointId] ??= computeEt0Series(bundles[m.pointId]);
  const k = `${m.pointId}|${m.year}|${m.sowOffsetDays}`;
  let c = cache.get(k);
  if (!c) {
    const b = bundles[m.pointId], et0 = et0s[m.pointId];
    const base = phenoFeatures(b, m.year, et0, crops, m.sowOffsetDays).map(r4);
    const a = antecedentFeatures(b, m.year, et0, crops, m.sowOffsetDays);
    c = { base, extra: ANTECEDENT_CANDIDATES.map((n) => r4(a[n])) };
    cache.set(k, c);
  }
  // Comprobación de alineación: las cuatro entradas de floración recalculadas coinciden con las de samples.json.
  baseNames.forEach((n, j) => { if (samples.X[i][at(n)] !== c.base[j]) throw new Error(`desalineado ${k} ${n}: ${samples.X[i][at(n)]} vs ${c.base[j]}`); });
  X.push(samples.X[i]); E.push(c.extra); Y.push(samples.Y[i]); year.push(m.year); pointId.push(m.pointId);
}
if (PHENO_FEATURE_NAMES.length !== 4) console.log(`aviso: PHENO_FEATURE_NAMES ya trae ${PHENO_FEATURE_NAMES.length} entradas`);
writeFileSync(here('./screening_superset.json'), JSON.stringify({
  note: 'Solo filas de entrenamiento (sin años 2019-2024 ni puntos heldOut). X = entradas actuales de samples.json; E = las siete candidatas, en el orden de candidateNames.',
  provenance: samples.provenance, featureNames: samples.featureNames, candidateNames: ANTECEDENT_CANDIDATES, targetNames: samples.targetNames,
  nTestDropped: samples.meta.length - keep.length, X, E, Y, year, pointId,
}));
console.log(`filas de entrenamiento ${keep.length} de ${samples.meta.length} (descartadas ${samples.meta.length - keep.length} de prueba); combinaciones únicas ${cache.size}`);
