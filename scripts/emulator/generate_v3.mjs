// Genera TODOS los candidatos del emulador v2 (211 680 sucesiones de siete cultivos, Tarea 33) con la misma simulación de succession_lib.mjs, con las entradas v3 (v2 + 16 nuevas).
// Uso: node scripts/emulator/generate_v3.mjs  (requiere las cachés de fetch_points.mjs). Escribe samples_v3_all.json (ignorado por git):
//   X con 47 columnas (las 31 primeras son las de v2, idénticas a samples_v2.json), Y, meta, y `reservoir` = índices de fila del reservorio de 60 000 (mismo algoritmo y semilla que generate_v2.mjs,
//   en el orden de samples_v2.json). Con ese índice se recuperan exactamente las filas de v2 (la prueba de igualdad la hace screen_v2_data_inputs.py).
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series, agriculturalYears, resolveMainSowIdx } from '../../web/js/model/simulate.js';
import { climateFeatures, mulberry32 } from '../../web/js/model/emulator.js';
import { FEATURE_NAMES_V3, featuresV3 } from '../../web/js/model/emulatorV3.js';
import { CROPS_V2, B_OPTIONS, SOILS_V2, OFFSETS_V2, TARGET_NAMES_V2, FEATURE_NAMES_V2, targetsV2 } from '../../web/js/model/emulatorV2.js';
import { simulateSuccessionYear } from '../compare/succession_lib.mjs';

const here = (p) => new URL(p, import.meta.url);
const readJson = (u) => JSON.parse(readFileSync(u, 'utf8'));
const points = readJson(here('./points.json'));
const crops = loadCrops(readJson(here('../../web/data/crops.json')));
const K = 60000;
const r4 = (v) => Math.round(v * 1e4) / 1e4;
const r5 = (v) => Math.round(v * 1e5) / 1e5;

// Paso 1: lista de candidatos y reservorio (algoritmo R, mulberry32(42)) sin simular; solo se simulan los conservados.
const bundles = {}; const ctx = {};
const cands = [];
for (const p of points) {
  const file = here(`./cache/${p.id}.json`);
  if (!existsSync(file)) { console.log(`${p.id}: sin caché, se omite`); continue; }
  const bundle = readJson(file);
  bundles[p.id] = bundle;
  const invalid = new Set(bundle.invalidYears ?? []);
  const ags = agriculturalYears(bundle.dates).filter((y) => !invalid.has(y.year));
  ctx[p.id] = { et0: computeEt0Series(bundle), ags };
  for (const ag of ags) for (const A of CROPS_V2) for (const B of B_OPTIONS) {
    if (B === A) continue;
    for (const soil of SOILS_V2) for (const off of OFFSETS_V2) cands.push([p.id, ag.year, A, B, soil, off]);
  }
}
const rng = mulberry32(42);
const slots = [];
let seen = 0;
for (let i = 0; i < cands.length; i++) {
  const slot = seen < K ? seen : Math.floor(rng() * (seen + 1));
  seen++;
  if (slot >= K) continue;
  if (slot === slots.length) slots.push(i); else slots[slot] = i;
}
console.log(`candidatos ${cands.length}; en el reservorio ${slots.length}`);
const reservoir = slots.slice(); // índices de candidato en el orden de samples_v2.json

// Paso 2: simular todos los candidatos.
const climCache = new Map();
const X = []; const Y = []; const meta = [];
let simMs = 0;
for (let idx = 0; idx < cands.length; idx++) {
  const [pid, year, A, B, soil, off] = cands[idx];
  const bundle = bundles[pid]; const { et0, ags } = ctx[pid];
  const ag = ags.find((a) => a.year === year);
  const ck = `${pid}|${year}`;
  if (!climCache.has(ck)) climCache.set(ck, climateFeatures(bundle, year, et0).map(r4));
  const t0 = performance.now();
  const res = simulateSuccessionYear({ idA: A, idB: B === 'none' ? null : B, bundle, et0, crops, texture: soil, year, startIdx: ag.startIdx, endIdx: ag.endIdx, offsetDays: off });
  simMs += performance.now() - t0;
  const y = targetsV2(res, B !== 'none').map(r5);
  const sowLocal = resolveMainSowIdx(bundle, year, off).idx;
  const x = featuresV3({ bundle, et0, year, climFeats: climCache.get(ck), sowLocal, offsetDays: off, idA: A, idB: B === 'none' ? null : B, soil, crops }).map(r4);
  if (![...x, ...y].every(Number.isFinite)) throw new Error(`valor no finito ${ck} ${A} ${B}`);
  X.push(x); Y.push(y); meta.push({ pointId: pid, year, A, B, soil, offset: off });
}
const git = (...a) => execFileSync('git', ['-C', fileURLToPath(here('../..')), ...a], { encoding: 'utf8' }).trim();
const provenance = {
  simulatorCommit: git('rev-parse', '--short', 'HEAD'),
  simulatorDirty: git('status', '--porcelain', '--', 'web/js/model/emulator.js', 'web/js/model/simulate.js', 'web/js/model/waterBalance.js', 'web/js/model/phenology.js', 'web/data/crops.json') !== '',
  rainSource: [...new Set(Object.values(bundles).map((b) => b.rainSource))].join(', '),
  generated: new Date().toISOString().slice(0, 10),
  candidates: cands.length, kept: X.length, reservoirSize: reservoir.length, simulatorMicrosPerSample: (simMs * 1000) / X.length,
};
writeFileSync(here('./samples_v3_all.json'), JSON.stringify({ provenance, featureNames: FEATURE_NAMES_V3, targetNames: TARGET_NAMES_V2, X, Y, meta, reservoir }));
console.log(`filas ${X.length} x ${X[0].length} entradas, ${Y[0].length} salidas; simulador ${provenance.simulatorMicrosPerSample.toFixed(0)} us/muestra`);
