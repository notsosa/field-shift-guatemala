// Matriz de las 42 sucesiones A→B entre siete cultivos con nuestro simulador (cribado de agua y calendario).
// Uso:  node scripts/compare/succession_matrix.mjs [--teammate <carpeta auditorias/ del repo field-shift-guatemala>] [--out web/data/succession_matrix.json]
// Sin red y sin AquaCrop. Lee los resultados del equipo (commit a0d0690) solo para la comparación de Chiquimula.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { computeEt0Series, agriculturalYears } from '../../web/js/model/simulate.js';
import { loadCrops } from '../../web/js/model/crops.js';
import {
  GAP_DAYS, MIN_FIT_YEARS, simulateSuccessionYear, summarizePair, compareOrders, majority, teammateDirection, screen,
} from './succession_lib.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
export const CROP_IDS = ['maiz', 'frijol', 'ajonjoli', 'papa', 'cebolla', 'brocoli', 'lechuga'];
export const PILOTS = ['chiquimula', 'jutiapa', 'sanmartin'];
const TEAMMATE_COMMIT = 'a0d0690';
const DEFAULT_TEAMMATE = path.resolve(root, '../field-shift-guatemala/auditorias');
const NEW = 'combinaciones pendientes 7 cultivos 2025';

// Dónde está, para cada pareja, la corrida de referencia del equipo (ambos órdenes, IMERG, secano, perfil de referencia, escorrentía 15%).
function teammateSource(a, b) {
  const has = (x, y) => (a === x && b === y) || (a === y && b === x);
  if (has('papa', 'cebolla')) return { file: 'prueba papa cebolla 2025/resultados/comparacion_referencia.csv', calendars: { 'papa>cebolla': 'papa115_cebolla150_gap14_2025-03-01', 'cebolla>papa': 'cebolla150_papa115_gap14_2025-03-01' } };
  if (has('brocoli', 'lechuga')) return { file: 'prueba brocoli lechuga 2025/resultados/comparacion_referencia.csv', calendars: { 'brocoli>lechuga': 'brocoli90_lechuga75_gap14_2025-03-01', 'lechuga>brocoli': 'lechuga75_brocoli90_gap14_2025-03-01' } };
  if (has('maiz', 'ajonjoli')) return { file: 'prueba ajonjoli maiz 2025/resultados/comparacion_referencia.json', calendars: { 'ajonjoli>maiz': 'ajonjoli110_maiz90_gap14_2025-05-15', 'maiz>ajonjoli': 'maiz90_ajonjoli110_gap14_2025-05-15' } };
  if (has('maiz', 'frijol')) return { file: 'prueba frijol maiz 2025/investigacion/escenarios-chiquimula-2025/comparacion_referencia.csv', calendars: { 'maiz>frijol': 'corto_90_70_junio01', 'frijol>maiz': 'corto_90_70_junio01' } };
  const dir = ['maiz_papa', 'maiz_cebolla', 'maiz_brocoli', 'maiz_lechuga', 'frijol_ajonjoli', 'frijol_papa', 'frijol_cebolla', 'frijol_brocoli', 'frijol_lechuga',
    'ajonjoli_papa', 'ajonjoli_cebolla', 'ajonjoli_brocoli', 'ajonjoli_lechuga', 'papa_brocoli', 'papa_lechuga', 'cebolla_brocoli', 'cebolla_lechuga'].find((d) => d === `${a}_${b}` || d === `${b}_${a}`);
  return { file: `${NEW}/parejas/${dir}/referencia.json`, calendars: null };
}

function parseCsv(text) {
  const [head, ...lines] = text.replace(/\r/g, '').trim().split('\n');
  const keys = head.split(',');
  return lines.map((l) => Object.fromEntries(l.split(',').map((v, i) => [keys[i], v])));
}

/** Déficit de ET (mm) de la corrida de referencia del equipo para A→B y B→A en Chiquimula; null si el archivo no da alguna. */
function teammateRows(dir, a, b) {
  const src = teammateSource(a, b);
  const file = path.join(dir, src.file);
  if (!fs.existsSync(file)) return { file: src.file, ab: null, ba: null };
  const rows = file.endsWith('.csv') ? parseCsv(fs.readFileSync(file, 'utf8')) : readJson(file);
  const isRef = (r) => r.fuente_lluvia === 'imerg' && String(r.riego_hipotetico).toLowerCase() === 'false' && r.suelo_escenario === 'perfil_referencia'
    && Math.abs(Number(r.fraccion_escorrentia_supuesta) - 0.15) < 1e-9;
  const pick = (seq) => {
    const cal = src.calendars?.[seq.replace('_', '>')] ?? null;
    const hit = rows.filter((r) => r.secuencia === seq && isRef(r) && (cal == null || r.calendario === cal));
    return hit.length === 1 ? { deficit: Number(hit[0].deficit_ET_mm), calendar: hit[0].calendario } : null;
  };
  return { file: src.file, ab: pick(`${a}_${b}`), ba: pick(`${b}_${a}`) };
}

export function buildMatrix({ teammateDir = DEFAULT_TEAMMATE } = {}) {
  const data = (rel) => readJson(path.join(root, 'web/data', rel));
  const crops = loadCrops(data('crops.json'));
  const points = readJson(path.join(root, 'scripts/emulator/points.json'));
  const bundles = Object.fromEntries(PILOTS.map((s) => [s, data(`snapshots/${s}.json`)]));
  const et0 = Object.fromEntries(PILOTS.map((s) => [s, computeEt0Series(bundles[s])]));
  const soils = (pilot) => ({ site: points.find((p) => p.id === pilot).soil, loam: 'loam' });

  const pairs = [];
  const rowsByKey = {}; // `${pilot}|${soil}|${a}>${b}` → filas por año
  for (const a of CROP_IDS) for (const b of CROP_IDS) {
    if (a === b) continue;
    const out = { a, b, pilots: {} };
    for (const pilot of PILOTS) {
      out.pilots[pilot] = {};
      for (const [soilKey, texture] of Object.entries(soils(pilot))) {
        const rows = agriculturalYears(bundles[pilot].dates).map((y) => simulateSuccessionYear({
          idA: a, idB: b, bundle: bundles[pilot], et0: et0[pilot], crops, texture, year: y.year, startIdx: y.startIdx, endIdx: y.endIdx,
        }));
        rowsByKey[`${pilot}|${soilKey}|${a}>${b}`] = rows;
        out.pilots[pilot][soilKey] = summarizePair(rows);
      }
    }
    pairs.push(out);
  }

  // Comparación con el equipo: Chiquimula, suelo SoilGrids del piloto.
  const comparison = [];
  for (let i = 0; i < CROP_IDS.length; i++) for (let j = i + 1; j < CROP_IDS.length; j++) {
    const a = CROP_IDS[i];
    const b = CROP_IDS[j];
    const ours = compareOrders(rowsByKey[`chiquimula|site|${a}>${b}`], rowsByKey[`chiquimula|site|${b}>${a}`]);
    const t = teammateRows(teammateDir, a, b);
    const tDir = teammateDirection(t.ab, t.ba);
    const dDir = majority(ours.abLowerDeficit, ours.baLowerDeficit);
    const yDir = majority(ours.abHigherRelYield, ours.baHigherRelYield);
    const name = (d) => (d == null ? null : d === 'AB' ? `${a}>${b}` : d === 'BA' ? `${b}>${a}` : 'tie');
    comparison.push({
      pair: [a, b],
      teammate: { file: t.file, deficitMm: { [`${a}>${b}`]: t.ab?.deficit ?? null, [`${b}>${a}`]: t.ba?.deficit ?? null }, calendars: { [`${a}>${b}`]: t.ab?.calendar ?? null, [`${b}>${a}`]: t.ba?.calendar ?? null }, lowerDeficit: name(tDir) },
      ours: { ...ours, lowerDeficitByYears: name(dDir), higherRelYieldByYears: name(yDir) },
      agreeDeficit: tDir == null ? null : tDir === dDir,
      agreeDeficitNote: tDir === 'tie' || dDir === 'tie' ? 'empate' : null,
      agreeRelYield: tDir == null ? null : tDir === yDir,
    });
  }

  const summary = {};
  for (const pilot of PILOTS) {
    summary[pilot] = {};
    for (const soilKey of ['site', 'loam']) {
      const entries = pairs.map((p) => ({ pair: `${p.a}>${p.b}`, ...p.pilots[pilot][soilKey] }));
      summary[pilot][soilKey] = { ...screen(entries), fitCount: entries.filter((e) => e.fitYears >= MIN_FIT_YEARS).length, totalPairs: entries.length };
    }
  }

  const cropTable = Object.fromEntries(CROP_IDS.map((id) => {
    const c = crops.get(id);
    return [id, { tbase: c.tbase, days: c.days, kc: c.kc, zrMax: c.zrMax, p: c.p, ky: c.ky, proxy: c.proxy, family: c.family }];
  }));
  const agree = comparison.filter((c) => c.agreeDeficit != null);
  return {
    meta: {
      what: 'Cribado de agua y calendario de las 42 sucesiones A>B entre siete cultivos con el simulador FAO-56 del proyecto. No es una recomendación: sin precios, plagas, adaptación al calor ni mercado.',
      method: {
        years: 'años agrícolas completos de cada snapshot (1 abr Y a 31 mar Y+1)',
        management: 'secano, pendiente plana, suelo = SoilGrids del piloto (soil "site") y franco (soil "loam")',
        sowing: `A en la regla de inicio de lluvias; B el día siguiente a la cosecha de A más ${GAP_DAYS} días (intervalo de referencia del equipo); sin relevo ni traslape`,
        cycles: 'ciclos por grados-día del propio simulador (TREF = 26 °C y tbase del cultivo); no se fuerzan días fijos',
        fit: `la sucesión "cabe" en un año si las dos etapas terminan dentro del año agrícola; el resumen exige ≥ ${MIN_FIT_YEARS} años`,
        relYield: 'mediana, percentil 10 (interpolación lineal) y peor año sobre todos los años; un ciclo incompleto, o un B que no se puede sembrar, cuenta 0',
        cycleDatesDeficitTmax: 'mediana de ciclo, fechas, déficit de ET (ETc − ETa) y tmax media del ciclo: solo años en que cabe',
        tmax: 'media de la temperatura máxima diaria durante el ciclo; descriptiva: el modelo no tiene respuesta al calor ni al fotoperíodo',
        orderComparison: 'por pareja, años en que caben los dos órdenes: cuenta cuál orden tiene el menor déficit total de ET (suma de los dos cultivos) y cuál el mayor relYield medio de la pareja',
      },
      teammate: {
        repository: 'field-shift-guatemala (main)', commit: TEAMMATE_COMMIT, folder: 'auditorias/',
        reference: 'Chiquimula 2025, lluvia IMERG, secano, perfil de referencia, escorrentía supuesta 15%, reserva inicial 25%, intervalo 14 días; duraciones fijas de él (maíz 90, frijol 70, ajonjolí 110, papa 115, cebolla 150, brócoli 90, lechuga 75). Las parejas anteriores usan su propio calendario (ver calendars). Un solo año (2025).',
        note: 'Su brócoli de referencia es de 90 días (variante prorrateada); el nuestro es el ciclo FAO de 135 días por grados-día.',
      },
      cropTable,
      emulator: 'El emulador no se reentrenó: sus cuatro rotaciones no cambian y no conoce estos cultivos.',
    },
    pairs,
    comparison: { items: comparison, agreeDeficit: agree.filter((c) => c.agreeDeficit).length, withDirection: agree.length, agreeRelYield: agree.filter((c) => c.agreeRelYield).length, total: comparison.length },
    summary,
  };
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const args = process.argv.slice(2);
  const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
  const out = path.resolve(opt('--out', path.join(root, 'web/data/succession_matrix.json')));
  const m = buildMatrix({ teammateDir: path.resolve(opt('--teammate', DEFAULT_TEAMMATE)) });
  fs.writeFileSync(out, JSON.stringify(m, null, 1) + '\n');
  console.log(`wrote ${out}`);
}
