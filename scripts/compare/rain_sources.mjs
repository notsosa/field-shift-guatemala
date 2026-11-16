// Tarea 35, parte 1: lluvia diaria de los 20 puntos con tres fuentes (ERA5, NASA POWER PRECTOTCORR, CHIRPS) y sus estadísticas por año.
// Uso: node scripts/compare/rain_sources.mjs   -> escribe web/data/rain_sources.json
// Requiere scripts/emulator/cache (ERA5), cache_power_app (POWER) y, para CHIRPS, scripts/emulator/cache_rain/{id}_chirps.json
// (los baja scripts/data/fetch_chirps_node.mjs). Un punto sin caché de CHIRPS queda con CHIRPS = null; no se inventa nada.
import fs from 'node:fs';
import path from 'node:path';
import { root, SOURCES, YEARS, loadPoints, loadSite, rainStatsByYear, coverage } from './rain_sources_lib.mjs';

const out = {
  meta: {
    generated: new Date().toISOString().slice(0, 10),
    years: YEARS,
    sources: {
      ERA5: 'Copernicus ERA5 reanalysis via Open-Meteo archive API (scripts/emulator/cache/{id}.json)',
      POWER: 'NASA POWER Daily API, community AG, PRECTOTCORR (scripts/emulator/cache_power_app/{id}.json)',
      CHIRPS: 'CHIRPS v2.0 daily rainfall (UCSB CHC) via ClimateSERV dataset 0, mean of a +-0.03 deg box (scripts/emulator/cache_rain/{id}_chirps.json)',
    },
    definitions: {
      annualMm: 'agricultural year Y: 1 April Y to 31 March Y+1',
      mayOctMm: '1 May to 31 October of year Y',
      julAugMm: '1 July to 31 August of year Y (the canicula)',
      longestDrySpellJunSep: 'longest run of consecutive days with rain < 1 mm between 1 June and 30 September of year Y',
      missing: 'a statistic is null when any day of its period has no value; no day is filled. Agricultural years with any missing day are listed in yearsExcluded and are not simulated for that source and site.',
    },
  },
  points: [],
};
for (const p of loadPoints()) {
  const s = loadSite(p.id);
  const entry = { id: p.id, name: p.name, department: p.department, lat: p.lat, lon: p.lon, sources: {} };
  for (const src of SOURCES) {
    if (!s.rain[src]) { entry.sources[src] = null; continue; }
    entry.sources[src] = { coverage: coverage(s.dates, s.rain[src]), ...rainStatsByYear(s.dates, s.rain[src]) };
  }
  out.points.push(entry);
}
fs.writeFileSync(path.join(root, 'web/data/rain_sources.json'), JSON.stringify(out, null, 1));
for (const e of out.points) console.log(e.id.padEnd(18), SOURCES.map((k) => (e.sources[k] ? `${k}: missing ${e.sources[k].coverage.missingDaysAll}, excluded yrs ${e.sources[k].coverage.yearsExcluded.length}` : `${k}: none`)).join(' | '));
