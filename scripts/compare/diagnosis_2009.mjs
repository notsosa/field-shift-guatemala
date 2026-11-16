// Tarea 35, parte 2: por qué el simulador no reproduce 2009 en el oriente (Chiquimula, Jutiapa, Zacapa).
// Uso: node scripts/compare/diagnosis_2009.mjs   -> escribe web/data/diagnosis_2009.json
// Para cada fuente de lluvia (ERA5, POWER, CHIRPS si hay caché y el año está completo) simula, secano, con el suelo del sitio (pilotos) o franco:
//  (a) lo que hizo historical_check: maíz resembrado 14 días después de una pérdida a los 30/45/60 días (desfase = pérdida + 1 + 14 sobre la regla de inicio);
//  (b) el calendario documentado: maíz de primera sembrado en la fecha de la regla de inicio, y maíz y frijol de segunda sembrados el 1 ago, 15 ago, 1 sep y 15 sep.
// Cada celda lleva relYield, días de estrés (ks < 0.7), si el ciclo termina en el año agrícola, y el puesto y percentil de 2009 entre 2001-2024 para ese sitio, fuente y calendario.
// No se ajusta ningún parámetro.
import fs from 'node:fs';
import path from 'node:path';
import {
  root, SOURCES, YEARS, loadAllCrops, loadPoints, loadSite, soilOfPoint, completeYears, simulateSowing, sowLocalIndex,
  percentile, rankWorst, isHit, rainStatsByYear, round,
} from './rain_sources_lib.mjs';
import { resowOffset, LOSS_DAYS } from './loss_decision_lib.mjs';
import { onsetSowIdx } from '../../web/js/model/phenology.js';

export const DIAG_SITES = ['chiquimula', 'jutiapa', 'zacapa'];
export const DIAG_YEAR = 2009;
const SECOND_DATES = ['08-01', '08-15', '09-01', '09-15'];

const crops = loadAllCrops();
const points = Object.fromEntries(loadPoints().map((p) => [p.id, p]));

/** Calendarios: id, cultivo, cuándo se siembra (onset | MM-DD) y el desfase sobre la regla de inicio. */
export function calendars() {
  const cal = [];
  for (const d of LOSS_DAYS) cal.push({ id: `historical_check_maize_loss${d}`, group: 'a', label: `maize resown 14 days after a loss at day ${d} (historical_check)`, cropId: 'maiz', when: 'onset', offset: resowOffset(d) });
  cal.push({ id: 'first_cycle_maize_onset', group: 'b', label: 'first-cycle maize sown at the onset rule date', cropId: 'maiz', when: 'onset', offset: 0 });
  for (const d of SECOND_DATES) cal.push({ id: `second_cycle_maize_${d}`, group: 'b', label: `second-cycle maize sown ${d}`, cropId: 'maiz', when: d, offset: 0 });
  for (const d of SECOND_DATES) cal.push({ id: `second_cycle_beans_${d}`, group: 'b', label: `second-cycle beans sown ${d}`, cropId: 'frijol', when: d, offset: 0 });
  return cal;
}

/** Serie por año (YEARS) de un calendario para un sitio y fuente; null en los años con lluvia incompleta. */
export function seriesFor(site, rainSeries, cal, soil, usable) {
  return YEARS.map((year) => {
    if (!usable.has(year)) return null;
    const sowLocal = sowLocalIndex(site.bundle, rainSeries, year, cal.when, cal.offset);
    return simulateSowing({ bundle: site.bundle, et0: site.et0, rain: rainSeries, crops, soil, year, cropId: cal.cropId, sowLocal });
  });
}

if (import.meta.url === `file://${process.argv[1].replace(/\\/g, '/')}` || process.argv[1]?.endsWith('diagnosis_2009.mjs')) {
  const out = {
    meta: {
      generated: new Date().toISOString().slice(0, 10), year: DIAG_YEAR, yearsRanked: [YEARS[0], YEARS.at(-1)],
      soil: 'site soil (SoilGrids) at the pilots (Chiquimula, Jutiapa); loam at Zacapa. Rainfed, flat, no irrigation, one crop per run from 1 April (bare soil before sowing).',
      reading: 'rank 1 = the worst of the usable years; percentile = mid-rank share of usable years with a lower relYield (0 = worst, 1 = best); badYear = percentile <= 1/3 (the worst third, fixed beforehand). relYield is 0 when the cycle does not finish before 31 March.',
      usableYearRule: 'a source-year with any missing rain day in 1 April..31 March is excluded for that site and source (not filled)',
      sources: SOURCES,
    },
    sites: [],
  };
  for (const id of DIAG_SITES) {
    const p = points[id]; const soil = soilOfPoint(p); const site = loadSite(id);
    const entry = { id, name: p.name, soil: typeof soil === 'string' ? soil : 'site', sources: {} };
    for (const src of SOURCES) {
      const rain = site.rain[src];
      if (!rain) { entry.sources[src] = null; continue; }
      const usable = new Set(completeYears(site.dates, rain));
      const stats = rainStatsByYear(site.dates, rain);
      const iy = YEARS.indexOf(DIAG_YEAR);
      const pctOf = (arr, wetIsGood) => { const v = arr.filter((x) => x != null); return arr[iy] == null ? null : round(wetIsGood ? percentile(v, arr[iy]) : 1 - percentile(v, arr[iy])); };
      const rec = { usableYears: usable.size, year2009Usable: usable.has(DIAG_YEAR), rain2009: { annualMm: stats.annualMm[iy], mayOctMm: stats.mayOctMm[iy], julAugMm: stats.julAugMm[iy], longestDrySpellJunSep: stats.longestDrySpellJunSep[iy], rainPercentile: { note: '0 = driest of the years, 1 = wettest (for the dry spell, 0 = longest spell)', annual: pctOf(stats.annualMm, true), mayOct: pctOf(stats.mayOctMm, true), julAug: pctOf(stats.julAugMm, true), drySpell: pctOf(stats.longestDrySpellJunSep, false) }, siteMeanMm: { annual: round(stats.annualMm.filter((x) => x != null).reduce((a, b) => a + b, 0) / stats.annualMm.filter((x) => x != null).length, 1), julAug: round(stats.julAugMm.filter((x) => x != null).reduce((a, b) => a + b, 0) / stats.julAugMm.filter((x) => x != null).length, 1) }, onsetDate: usable.has(DIAG_YEAR) ? site.dates[onsetSowIdx(rain, site.dates, DIAG_YEAR).idx] : null }, calendars: [] };
      for (const cal of calendars()) {
        const series = seriesFor(site, rain, cal, soil, usable);
        const vals = series.filter(Boolean).map((r) => r.relYield);
        const r09 = series[YEARS.indexOf(DIAG_YEAR)];
        const cell = { id: cal.id, group: cal.group, label: cal.label, cropId: cal.cropId, when: cal.when, offsetDays: cal.offset, yearsInRanking: vals.length, cycleCompleteYears: series.filter((r) => r?.cycleCompletes).length };
        if (r09) {
          const pct = percentile(vals, r09.relYield);
          Object.assign(cell, { sowDate: r09.sowDate, harvestDate: r09.harvestDate, relYield: round(r09.relYield), stressDays: r09.stressDays, cycleCompletes: r09.cycleCompletes, cycleDays: r09.cycleDays, ...rankWorst(vals, r09.relYield), percentile: round(pct), badYear: isHit(pct), siteMedianRelYield: round([...vals].sort((a, b) => a - b)[vals.length >> 1]) });
        } else cell.note = 'excluded: missing rain days in the agricultural year 2009 for this source';
        rec.calendars.push(cell);
      }
      entry.sources[src] = rec;
    }
    out.sites.push(entry);
  }
  fs.writeFileSync(path.join(root, 'web/data/diagnosis_2009.json'), JSON.stringify(out, null, 1));
  for (const s of out.sites) for (const [src, r] of Object.entries(s.sources)) {
    if (!r) { console.log(s.id, src, 'no data'); continue; }
    console.log(`\n${s.id} ${src} usable ${r.usableYears} 2009: ${JSON.stringify(r.rain2009)}`);
    for (const c of r.calendars) console.log(' ', c.id.padEnd(34), c.relYield == null ? c.note : `sow ${c.sowDate} rel ${c.relYield} stress ${c.stressDays} done ${c.cycleCompletes} rank ${c.rank}/${c.of} (tied ${c.tied}) pct ${c.percentile} bad ${c.badYear} median ${c.siteMedianRelYield}`);
  }
}
