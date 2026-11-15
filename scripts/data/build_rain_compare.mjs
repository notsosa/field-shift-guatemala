// Builds web/data/rain_compare.json from the 3 pilot snapshots (web/data/snapshots/*.json, which carry `rainAlt`):
// per pilot and rain source, annual rain by agricultural year 2001–2024, May–Oct rain and canícula days
// (longest run of days < 1 mm between 1 Jul and 31 Aug). A year with any missing day has null figures.
// Uso: node scripts/data/build_rain_compare.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { compareSources } from '../../web/js/data/rainCompare.js';

const here = (p) => new URL(p, import.meta.url);
const PILOTS = ['chiquimula', 'jutiapa', 'sanmartin'];
const YEARS = Array.from({ length: 24 }, (_, i) => 2001 + i);
const points = JSON.parse(readFileSync(here('../emulator/points.json'), 'utf8'));

const SOURCE_LABELS = {
  POWER: 'NASA POWER PRECTOTCORR (MERRA-2 corrected; comparison only, never used by the model)',
  ERA5: 'Copernicus ERA5 via Open-Meteo',
  IMERG: 'ClimateSERV dataset 26, "NASA-IMERG-V06-Late 1 Day" per the ClimateSERV documentation (box ±0.03°)',
  IMERG_LATE: 'ClimateSERV dataset 226, "NASA-IMERG-V07-Late 1 Day" per the ClimateSERV documentation (box ±0.03°)',
  CHIRPS: 'CHIRPS v2.0 via ClimateSERV (box ±0.03°)',
};

const out = { generated: new Date().toISOString().slice(0, 10), years: YEARS, units: { annualMm: 'mm per agricultural year (1 Apr Y .. 31 Mar Y+1)', mayOctMm: 'mm, 1 May – 31 Oct of Y', caniculaDays: 'longest run of days < 1 mm between 1 Jul and 31 Aug of Y (days)' }, pilots: {} };
for (const id of PILOTS) {
  const b = JSON.parse(readFileSync(here(`../../web/data/snapshots/${id}.json`), 'utf8'));
  const meta = points.find((p) => p.id === id);
  // `common` = means over the years where every source has all its days (fair comparison; a year with a gap is never filled).
  // `commonSets` keeps the earlier four-product means (without IMERG_LATE) and gives the pair set without IMERG (dataset 26).
  const { sources, common, commonSets } = compareSources(b.dates, b.rainAlt ?? {}, YEARS, SOURCE_LABELS, {
    withoutImergLate: ['ERA5', 'IMERG', 'CHIRPS', 'POWER'],
    withoutImerg: ['ERA5', 'CHIRPS', 'POWER', 'IMERG_LATE'],
  });
  out.pilots[id] = { name: meta.name, lat: meta.lat, lon: meta.lon, modelRainSource: b.rainSource, sources, common, commonSets };
}
writeFileSync(here('../../web/data/rain_compare.json'), JSON.stringify(out, null, 1) + '\n');
for (const [id, p] of Object.entries(out.pilots)) {
  console.log(`${id} (model: ${p.modelRainSource})`);
  console.log(`  common years, all sources (${p.common.years.length}): annual ${JSON.stringify(p.common.meanAnnualMm)}`);
  for (const [k, c] of Object.entries(p.commonSets)) console.log(`  common ${k} (${c.years.length} years): annual ${JSON.stringify(c.meanAnnualMm)}`);
  for (const [n, s] of Object.entries(p.sources)) console.log(`  ${n.padEnd(7)} annual ${s.meanAnnualMm} mm, May–Oct ${s.meanMayOctMm} mm, canícula ${s.meanCaniculaDays} d, valid years ${s.validYears}/24`);
}
