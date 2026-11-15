// Duración de los ciclos de los cultivos en los 3 pilotos (franco, secano, siembra al inicio de lluvias, 2001–2024) con el clima de
// los snapshots de una raíz de repositorio: la actual ("después") y, opcionalmente, una revisión anterior exportada ("antes").
// Uso: node scripts/data/cycle_lengths.mjs [--before <raíz con web/ de la revisión anterior>] [--before-label e5a3d49] [--out web/data/cycle_lengths.json]
//   git archive e5a3d49 web | tar -x -C <raíz>      # raíz de la revisión "antes"
// Sin --before solo se escribe el bloque "after". Rotaciones: `actual` (maíz y frijol el 1 de septiembre) y `extra_secano` (maíz y ajonjolí el 1 de septiembre).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

export const PILOTS = ['chiquimula', 'jutiapa', 'sanmartin'];
const here = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const DAY = 864e5;
const days = (a, b) => Math.round((Date.parse(b) - Date.parse(a)) / DAY) + 1;
const median = (a) => { const s = [...a].sort((x, y) => x - y); const h = s.length >> 1; return s.length % 2 ? s[h] : (s[h - 1] + s[h]) / 2; };
const agriYear = (iso) => (Number(iso.slice(5, 7)) >= 4 ? Number(iso.slice(0, 4)) : Number(iso.slice(0, 4)) - 1);
const dayOfAgriYear = (iso) => days(`${agriYear(iso)}-04-01`, iso);

/** Estadísticas de ciclo de una raíz (debe contener web/js/model, web/data/crops.json, sequences.json y snapshots/). */
export async function cycleStats(root) {
  const imp = (p) => import(pathToFileURL(path.join(root, p)).href);
  const { runSequence, computeEt0Series } = await imp('web/js/model/simulate.js');
  const { loadCrops } = await imp('web/js/model/crops.js');
  const crops = loadCrops(JSON.parse(fs.readFileSync(path.join(root, 'web/data/crops.json'), 'utf8')));
  const seqs = JSON.parse(fs.readFileSync(path.join(root, 'web/data/sequences.json'), 'utf8'));
  const out = {};
  for (const site of PILOTS) {
    const b = JSON.parse(fs.readFileSync(path.join(root, `web/data/snapshots/${site}.json`), 'utf8'));
    const et0 = computeEt0Series(b);
    const tm = (months) => { const v = b.tmax.map((t, i) => ((t + b.tmin[i]) / 2)).filter((_, i) => months.includes(Number(b.dates[i].slice(5, 7)))); return v.reduce((x, y) => x + y, 0) / v.length; };
    const o = out[site] = {
      elevation: b.elevation, cellElevation: b.cellElevation ?? b.elevation, deltaT: b.temperatureCorrection?.deltaT ?? 0,
      meanTempMayAug: Number(tm([5, 6, 7, 8]).toFixed(2)), meanTempSepDec: Number(tm([9, 10, 11, 12]).toFixed(2)),
    };
    for (const id of ['actual', 'extra_secano']) {
      const res = runSequence({ sequence: seqs[id], bundle: b, et0, crops, texture: 'loam', slopeClass: 'flat', irrigation: 'none', sowOffsetDays: 0 });
      const c0 = res.map((r) => days(r.crops[0].sowDate, r.crops[0].harvestDate));
      const c1 = res.map((r) => days(r.crops[1].sowDate, r.crops[1].harvestDate));
      const ov = res.map((r) => Math.max(0, days(r.crops[1].sowDate, r.crops[0].harvestDate)));
      const h1 = res.map((r) => r.crops[1].harvestDate).sort((x, y) => dayOfAgriYear(x) - dayOfAgriYear(y)); // fechas reales, ordenadas por día del año agrícola
      const stat = (a) => ({ median: median(a), min: Math.min(...a), max: Math.max(...a) });
      o[id] = {
        n: res.length,
        maize: stat(c0),
        second: { crop: seqs[id].phases[1].cropId, ...stat(c1) },
        maizeStandingAtSecondSowing: res.filter((r) => r.crops[0].harvestDate >= r.crops[1].sowDate).length,
        overlapMedianDays: median(ov),
        secondHarvestWindow: { first: h1[0].slice(5), upperMedian: h1[h1.length >> 1].slice(5), last: h1[h1.length - 1].slice(5) },
        incompleteCycleYears: res.filter((r) => r.crops.some((c) => c.cycleIncomplete)).length,
      };
    }
  }
  return out;
}

async function main(argv) {
  const arg = (n) => { const i = argv.indexOf(`--${n}`); return i >= 0 ? argv[i + 1] : undefined; };
  const outFile = arg('out') ?? path.join(here, 'web/data/cycle_lengths.json');
  const result = {
    meta: {
      description: 'Crop cycle lengths in calendar days at the 3 pilots (loam, rainfed, sowing at the rain onset, 2001-2024); second crop sown on 1 September. Cited: maize ~120 d (ICTA), beans 64-70 d (ICTA, Manual de produccion de frijol 2022, cuadro 1 p. 8), sesame 110 d (FAO-56 cuadro 11), as in web/data/crops.json.',
      cited: { maiz: 120, frijol: '64-70', ajonjoli: 110 },
      secondHarvestWindowNote: 'Dates (MM-DD) are the real harvest dates ordered by day of the agricultural year (1 April = day 1), so the window crosses the new year correctly; upperMedian is the element at index n/2 of that order.',
    },
  };
  if (arg('before')) { result.meta.beforeLabel = arg('before-label') ?? 'before'; result.before = await cycleStats(path.resolve(arg('before'))); }
  result.after = await cycleStats(here);
  fs.writeFileSync(outFile, JSON.stringify(result, null, 1) + '\n');
  console.log(`Escrito ${outFile}`);
  for (const [k, X] of Object.entries({ before: result.before, after: result.after })) {
    if (!X) continue;
    for (const s of PILOTS) console.log(k, s, `maiz ${X[s].actual.maize.median} d, frijol ${X[s].actual.second.median} d, ajonjolí ${X[s].extra_secano.second.median} d, maíz en pie ${X[s].actual.maizeStandingAtSecondSowing}/${X[s].actual.n}, ciclos incompletos (ajonjolí) ${X[s].extra_secano.incompleteCycleYears}`);
  }
}
if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) await main(process.argv.slice(2));
