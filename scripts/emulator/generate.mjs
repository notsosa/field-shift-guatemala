// Genera los ejemplos de entrenamiento del emulador corriendo el simulador completo.
// Uso: node scripts/emulator/generate.mjs  (requiere las cachés de fetch_points.mjs)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series, agriculturalYears, runSequence } from '../../web/js/model/simulate.js';
import { climateFeatures, phenoFeatures, encodeFeatures, targetsOf, mulberry32, FEATURE_NAMES, CLIMATE_FEATURE_NAMES, PHENO_FEATURE_NAMES, TARGET_NAMES } from '../../web/js/model/emulator.js';
import { fileURLToPath } from 'node:url';
import { sharedCells } from './cells.mjs';

const here = (p) => new URL(p, import.meta.url);
const readJson = (u) => JSON.parse(readFileSync(u, 'utf8'));
const points = readJson(here('./points.json'));
const crops = loadCrops(readJson(here('../../web/data/crops.json')));
const sequences = readJson(here('../../web/data/sequences.json'));

const K = 50000;
const TEXTURES = ['sand', 'loam', 'clay'];
const SLOPES = ['flat', 'moderate', 'steep'];
const IRRIGATIONS = ['none', 'limited', 'full'];
const OFFSETS = Array.from({ length: 11 }, (_, i) => -20 + 5 * i);
const COMBOS = [];
for (const id of ['actual', 'proteger', 'extra_secano']) for (const irr of IRRIGATIONS) COMBOS.push([id, irr]);
for (const irr of ['limited', 'full']) COMBOS.push(['extra_riego', irr]);

const r4 = (v) => Math.round(v * 1e4) / 1e4;
const r5 = (v) => Math.round(v * 1e5) / 1e5;
const round2 = (v) => Math.round(v * 100) / 100;
const finite = (a, what) => { if (!a.every(Number.isFinite)) throw new Error(`Valor no finito en ${what}`); };

const t0 = Date.now();
const rng = mulberry32(42);
const X = []; const Y = []; const meta = [];
let seen = 0;
const gridPoints = []; const climate = {}; const pheno = {}; const yearSet = new Set(); const bundles = {};

for (const p of points) {
  const file = here(`./cache/${p.id}.json`);
  if (!existsSync(file)) { console.log(`${p.id}: sin caché, se omite`); continue; }
  const bundle = readJson(file);
  bundles[p.id] = bundle;
  const invalid = new Set(bundle.invalidYears ?? []);
  const years = agriculturalYears(bundle.dates).filter((y) => !invalid.has(y.year)).map((y) => y.year);
  const et0 = computeEt0Series(bundle);
  const climFeats = {}; const phenoFeats = {};
  for (const y of years) {
    climFeats[y] = climateFeatures(bundle, y, et0).map(r4);
    phenoFeats[y] = {};
    for (const o of OFFSETS) phenoFeats[y][o] = phenoFeatures(bundle, y, et0, crops, o).map(r4);
    yearSet.add(y);
  }
  climate[p.id] = climFeats;
  pheno[p.id] = phenoFeats;
  gridPoints.push({ id: p.id, name: p.name, department: p.department, lat: p.lat, lon: p.lon, elevation: bundle.elevation, cellElevation: bundle.cellElevation, deltaT: round2(bundle.temperatureCorrection.deltaT), heldOut: p.heldOut });

  for (const [seqId, irrigation] of COMBOS) for (const texture of TEXTURES) for (const slopeClass of SLOPES) for (const sowOffsetDays of OFFSETS) {
    const results = runSequence({ sequence: sequences[seqId], bundle, et0, crops, texture, slopeClass, irrigation, sowOffsetDays });
    for (const yr of results) {
      if (invalid.has(yr.year)) continue;
      const t = targetsOf(yr);
      if (t === null) continue;
      // Algoritmo R: reservorio de K ejemplos con selección uniforme determinista.
      const slot = seen < K ? seen : Math.floor(rng() * (seen + 1));
      seen++;
      if (slot >= K) continue;
      const x = encodeFeatures(climFeats[yr.year], phenoFeats[yr.year][sowOffsetDays], { texture, slopeClass, irrigation, sequenceId: seqId, sowOffsetDays }).map(r4);
      const y = t.map(r5);
      finite(x, `features ${p.id} ${yr.year}`); finite(y, `targets ${p.id} ${yr.year}`);
      const m = { pointId: p.id, year: yr.year, sequenceId: seqId, texture, slopeClass, irrigation, sowOffsetDays };
      if (slot === X.length) { X.push(x); Y.push(y); meta.push(m); } else { X[slot] = x; Y[slot] = y; meta[slot] = m; }
    }
  }
  console.log(`${p.id}: ${years.length} años, candidatos acumulados ${seen}`);
}

// Celda de clima compartida: `elevation` es la de la parcela (la temperatura se corrige a ella) y `cellElevation` la de la celda POWER.
const cells = sharedCells(bundles);
for (const gp of gridPoints) Object.assign(gp, cells[gp.id]);

const heldOut = new Set(points.filter((p) => p.heldOut).map((p) => p.id));
const isTest = (m) => (m.year >= 2019 && m.year <= 2024) || heldOut.has(m.pointId);
const nTest = meta.filter(isTest).length;
// Procedencia: commit del simulador al generar (y si el modelo tenía cambios sin confirmar), fuente de lluvia de los bundles, fecha.
const git = (...a) => execFileSync('git', ['-C', fileURLToPath(here('../..')), ...a], { encoding: 'utf8' }).trim();
const provenance = {
  simulatorCommit: git('rev-parse', '--short', 'HEAD'),
  simulatorDirty: git('status', '--porcelain', '--', 'web/js/model', 'web/data/crops.json', 'web/data/sequences.json') !== '',
  rainSource: [...new Set(Object.values(bundles).map((b) => b.rainSource))].join(', '),
  generated: new Date().toISOString().slice(0, 10),
};
writeFileSync(here('./samples.json'), JSON.stringify({ provenance, featureNames: FEATURE_NAMES, targetNames: TARGET_NAMES, X, Y, meta }));
writeFileSync(here('../../web/data/grid_features.json'), JSON.stringify({ points: gridPoints, years: [...yearSet].sort((a, b) => a - b), climateNames: CLIMATE_FEATURE_NAMES, phenoNames: PHENO_FEATURE_NAMES, offsets: OFFSETS, climate, pheno }));

console.log(`\nPuntos usados: ${gridPoints.length}; candidatos totales: ${seen}; conservados: ${X.length}; tiempo: ${((Date.now() - t0) / 1000).toFixed(1)} s`);
console.log(`Forma: ${X.length} filas x ${X[0].length} features, ${Y[0].length} objetivos; sin NaN/Infinity (verificado)`);
console.log(`División (prueba = año 2019-2024 O punto heldOut [${[...heldOut].join(', ')}]): entrenamiento ${X.length - nTest}, prueba ${nTest}`);
