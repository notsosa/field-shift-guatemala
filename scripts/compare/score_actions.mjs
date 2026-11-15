// Puntúa con nuestro simulador las acciones recomendadas por CUALQUIER modelo (ver proyecto/comparacion-modelos.md).
// Uso:  node scripts/compare/score_actions.mjs --in actions.json [--out scored.json]   (sin --out, imprime el JSON)
// Entrada {"actions": [...]}. Una acción: {id, site, year, texture | "soil": "site", slopeClass, irrigation} más
//   {sequenceId: "actual"|"proteger"|"extra_secano"|"extra_riego", sowOffsetDays: n}   (rotación; el desfase mueve al cultivo principal)
//   o {crop: "maiz"|"frijol"|"sorgo", sowDate: "MM-DD"}                                 (un cultivo con fecha fija, como scripts/referee/compare.mjs).
// Las acciones inválidas se rechazan todas juntas con un mensaje que nombra el id de cada una.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { computeEt0Series, runSequence, agriculturalYears } from '../../web/js/model/simulate.js';
import { loadCrops } from '../../web/js/model/crops.js';
import { targetsOf } from '../../web/js/model/emulator.js';
import { overlapDays } from '../../web/js/model/decision.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));

export const SITES = ['chiquimula', 'jutiapa', 'sanmartin'];
export const TEXTURES = ['sand', 'loam', 'clay'];
export const SLOPES = ['flat', 'moderate', 'steep'];
export const IRRIGATIONS = ['none', 'limited', 'full'];
export const SINGLE_CROPS = ['maiz', 'frijol', 'sorgo'];
const KEYS = new Set(['id', 'site', 'year', 'texture', 'soil', 'slopeClass', 'irrigation', 'sequenceId', 'sowOffsetDays', 'crop', 'sowDate', 'note']);

/** Bundles de los pilotos, su ET0, los cultivos, las rotaciones y el suelo SoilGrids de cada piloto. */
export function loadScorerContext() {
  const data = (rel) => readJson(path.join(root, 'web/data', rel));
  const points = readJson(path.join(root, 'scripts/emulator/points.json'));
  const bundles = Object.fromEntries(SITES.map((s) => [s, data(`snapshots/${s}.json`)]));
  return {
    bundles,
    et0: Object.fromEntries(SITES.map((s) => [s, computeEt0Series(bundles[s])])),
    years: Object.fromEntries(SITES.map((s) => [s, agriculturalYears(bundles[s].dates).map((a) => a.year)])),
    crops: loadCrops(data('crops.json')),
    sequences: data('sequences.json'),
    siteSoil: Object.fromEntries(SITES.map((s) => [s, points.find((p) => p.id === s).soil])),
  };
}

const isMmDd = (s) => {
  if (typeof s !== 'string' || !/^\d{2}-\d{2}$/.test(s)) return false;
  const [m, d] = s.split('-').map(Number);
  const t = new Date(Date.UTC(2000, m - 1, d)); // 2000 es bisiesto: 02-29 vale
  return t.getUTCMonth() === m - 1 && t.getUTCDate() === d;
};

/** Lista de problemas de una acción (vacía si es válida). */
function problems(a, ctx) {
  if (a === null || typeof a !== 'object' || Array.isArray(a)) return ['it is not an object'];
  const bad = [];
  const has = (k) => a[k] !== undefined;
  for (const k of Object.keys(a)) if (a[k] !== undefined && !KEYS.has(k)) bad.push(`unknown field "${k}" (allowed: ${[...KEYS].join(', ')})`);
  const siteOk = SITES.includes(a.site);
  if (!siteOk) bad.push(`unknown site "${a.site}" (sites: ${SITES.join(', ')})`);
  if (!Number.isInteger(a.year) || (siteOk && !ctx.years[a.site].includes(a.year))) {
    bad.push(`year ${JSON.stringify(a.year)} is not an agricultural year in the bundle${siteOk ? ` of ${a.site} (${ctx.years[a.site][0]}..${ctx.years[a.site].at(-1)})` : ''}`);
  }
  if (has('texture') && has('soil')) bad.push('give texture or soil "site", not both');
  else if (has('soil')) { if (a.soil !== 'site') bad.push(`soil must be "site" (the pilot SoilGrids soil), got ${JSON.stringify(a.soil)}`); }
  else if (!TEXTURES.includes(a.texture)) bad.push(`texture must be ${TEXTURES.join('|')} (or soil "site"), got ${JSON.stringify(a.texture)}`);
  if (!SLOPES.includes(a.slopeClass)) bad.push(`slopeClass must be ${SLOPES.join('|')}, got ${JSON.stringify(a.slopeClass)}`);
  if (!IRRIGATIONS.includes(a.irrigation)) bad.push(`irrigation must be ${IRRIGATIONS.join('|')}, got ${JSON.stringify(a.irrigation)}`);
  const rot = has('sequenceId') || has('sowOffsetDays');
  const one = has('crop') || has('sowDate');
  if (rot === one) bad.push('give either a rotation (sequenceId + sowOffsetDays) or a single crop (crop + sowDate), not both and not neither');
  else if (rot) {
    if (!has('sequenceId') || !Object.hasOwn(ctx.sequences, a.sequenceId)) bad.push(`sequenceId must be ${Object.keys(ctx.sequences).join('|')}, got ${JSON.stringify(a.sequenceId)}`);
    else if (ctx.sequences[a.sequenceId].requiresIrrigation && a.irrigation === 'none') bad.push(`sequenceId "${a.sequenceId}" needs irrigation (limited or full), but irrigation is "none"`);
    if (!Number.isInteger(a.sowOffsetDays)) bad.push(`sowOffsetDays must be an integer (days after the rain-onset rule; negative = before), got ${JSON.stringify(a.sowOffsetDays)}`);
  } else {
    if (!SINGLE_CROPS.includes(a.crop)) bad.push(`crop must be ${SINGLE_CROPS.join('|')}, got ${JSON.stringify(a.crop)}`);
    if (!isMmDd(a.sowDate)) bad.push(`sowDate must be a real calendar date "MM-DD", got ${JSON.stringify(a.sowDate)}`);
  }
  return bad;
}

/** Valida todas las acciones; lanza un solo error con todos los rechazos. Devuelve la lista de acciones. */
export function validateActions(input, ctx) {
  if (input === null || typeof input !== 'object' || !Array.isArray(input.actions)) throw new Error('the input must be {"actions": [...]}: "actions" must be a list');
  if (input.actions.length === 0) throw new Error('no actions to score');
  const seen = new Set();
  const errors = [];
  input.actions.forEach((a, i) => {
    const label = typeof a?.id === 'string' && a.id ? `action "${a.id}"` : `action #${i + 1}`;
    const bad = [];
    if (a !== null && typeof a === 'object' && !(typeof a.id === 'string' && a.id)) bad.push('id must be a non-empty string');
    else if (typeof a?.id === 'string') { if (seen.has(a.id)) bad.push(`duplicate id "${a.id}"`); seen.add(a.id); }
    bad.push(...problems(a, ctx));
    for (const b of bad) errors.push(`${label}: ${b}`);
  });
  if (errors.length) throw new Error(`${errors.length} problem(s) in the actions:\n- ${errors.join('\n- ')}`);
  return input.actions;
}

/** Secuencia de un solo cultivo con fecha fija: la misma que arma simulate() de scripts/referee/compare.mjs. */
const singleCropSequence = (id, cropId, sowDate) => ({ id, name: { en: id, es: id }, phases: [{ cropId, sow: sowDate }], requiresIrrigation: false });

/** Puntúa las acciones: {results: [...]}, un resultado por acción y en el mismo orden. */
export function scoreActions(input, ctx) {
  const actions = validateActions(input, ctx);
  return {
    results: actions.map((a) => {
      const bundle = ctx.bundles[a.site];
      const texture = a.soil === 'site' ? ctx.siteSoil[a.site] : a.texture;
      const single = a.crop !== undefined;
      const sequence = single ? singleCropSequence(a.id, a.crop, a.sowDate) : ctx.sequences[a.sequenceId];
      const yr = runSequence({
        sequence, bundle, et0: ctx.et0[a.site], crops: ctx.crops, texture, slopeClass: a.slopeClass, irrigation: a.irrigation,
        sowOffsetDays: single ? 0 : a.sowOffsetDays,
      }).find((r) => r.year === a.year);
      const t = targetsOf(yr);
      const crops = yr.crops.map((c) => ({
        cropId: c.cropId, sowDate: c.sowDate, harvestDate: c.harvestDate,
        relYield: c.relYield, effectiveRelYield: c.relYield === null ? null : (c.cycleIncomplete ? 0 : c.relYield),
        ksFlowerMean: c.ksFlowerMean, cycleIncomplete: c.cycleIncomplete,
      }));
      return {
        id: a.id, site: a.site, year: a.year, soil: a.soil === 'site' ? 'site' : a.texture, slopeClass: a.slopeClass, irrigation: a.irrigation,
        kind: single ? 'single-crop' : 'rotation',
        ...(single ? { crop: a.crop, sowDate: a.sowDate } : { sequenceId: a.sequenceId, sowOffsetDays: a.sowOffsetDays }),
        crops,
        overlapDays: yr.crops.slice(1).map((c, k) => overlapDays(yr.crops[k], c)),
        waterIndex: t ? t[0] : null, ksFlowerMain: t ? t[1] : null, bareFrac: t ? t[2] : null,
        onsetFallback: yr.onsetFallback, cycleIncomplete: yr.cycleIncomplete,
      };
    }),
  };
}

function arg(name, argv) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
}

function main(argv) {
  const inPath = arg('in', argv);
  if (!inPath) throw new Error('Usage: score_actions.mjs --in <actions.json> [--out <scored.json>]');
  const scored = scoreActions(readJson(inPath), loadScorerContext());
  const text = JSON.stringify(scored, null, 1) + '\n';
  const out = arg('out', argv);
  if (out) { fs.mkdirSync(path.dirname(path.resolve(out)), { recursive: true }); fs.writeFileSync(out, text); console.error(`Scored ${scored.results.length} actions -> ${out}`); } else process.stdout.write(text);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try { main(process.argv.slice(2)); } catch (e) { console.error(e.message); process.exit(1); }
}
