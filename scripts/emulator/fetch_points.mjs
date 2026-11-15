// Descarga POWER + ERA5 para los puntos del Corredor Seco y arma un ClimateBundle por punto.
// Lluvia del entrenamiento: UNA sola fuente para todo el conjunto. Si IMERG (caché de
// scripts/data/fetch_rain_climateserv.py) está completo —sin años inválidos 2001–2024— en los 20 puntos, los bundles
// usan IMERG; si no, ERA5. En ambos casos los 3 pilotos guardan las series alternas en `rainAlt`.
// Uso: node scripts/emulator/fetch_points.mjs [--refresh]   (secuencial, con caché y reintentos)
//   --refresh vuelve a descargar POWER/ERA5 aunque exista scripts/emulator/cache_raw/{id}.json
import { readFileSync, writeFileSync, mkdirSync, existsSync, copyFileSync } from 'node:fs';
import { fetchPowerDaily, fetchEra5Rain, buildBundle, climateservRain, isInsideGuatemala } from '../../web/js/data/climate.js';

const here = (p) => new URL(p, import.meta.url);
const points = JSON.parse(readFileSync(here('./points.json'), 'utf8'));
const RAW = here('./cache_raw/');
const CACHE = here('./cache/');
const RAIN_CACHE = here('./cache_rain/');
const SNAP = here('../../web/data/snapshots/');
const PILOTS = ['chiquimula', 'jutiapa', 'sanmartin'];
const REFRESH = process.argv.includes('--refresh');
const SERIES = ['tmax', 'tmin', 'tdew', 'rs', 'u2', 'pressure', 'rain'];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function withRetry(label, fn, tries = 3, backoffMs = 5000) {
  for (let a = 1; ; a++) {
    try { return await fn(); } catch (e) {
      if (a >= tries) throw new Error(`${label}: ${e.message}`);
      console.log(`  retry ${a}/${tries - 1} ${label}: ${e.message}`);
      await sleep(backoffMs);
    }
  }
}

const round = (a, d) => a.map((v) => (v == null ? v : Math.round(v * 10 ** d) / 10 ** d));
const rainDoc = (id, ds) => {
  const f = new URL(`${id}_${ds}.json`, RAIN_CACHE);
  return existsSync(f) ? JSON.parse(readFileSync(f, 'utf8')) : null;
};
const inTrainYears = (years) => years.filter((y) => y >= 2001 && y <= 2024);

for (const p of points) {
  if (!isInsideGuatemala(p.lat, p.lon)) throw new Error(`${p.id} fuera de Guatemala`);
}
mkdirSync(RAW, { recursive: true });
mkdirSync(CACHE, { recursive: true });
mkdirSync(SNAP, { recursive: true });

// 1) POWER + ERA5 crudos por punto (con caché).
const raw = new Map(); const failed = [];
for (const [n, p] of points.entries()) {
  const file = new URL(`${p.id}.json`, RAW);
  if (REFRESH || !existsSync(file)) {
    try {
      const power = await withRetry(`${p.id} POWER`, () => fetchPowerDaily(p.lat, p.lon));
      const era5 = await withRetry(`${p.id} ERA5`, () => fetchEra5Rain(p.lat, p.lon));
      writeFileSync(file, JSON.stringify({ power, era5 }));
      console.log(`[${n + 1}/${points.length}] ${p.id}: descargado`);
      await sleep(1000);
    } catch (e) {
      console.log(`[${n + 1}/${points.length}] ${p.id}: FALLÓ ${e.message}`);
      failed.push(p.id);
      continue;
    }
  }
  raw.set(p.id, JSON.parse(readFileSync(file, 'utf8')));
}

// 2) ¿IMERG completo en todos los puntos? (el conjunto de entrenamiento usa una sola fuente de lluvia)
const imergRain = (p) => {
  const doc = rainDoc(p.id, 'imerg');
  if (!doc) return null;
  const detail = `caja ±0.03°, ${doc.obtained?.[0]}..${doc.obtained?.[1]}, ${doc.missingDays} días sin dato`;
  return climateservRain(doc, raw.get(p.id).power.dates, 'IMERG', detail);
};
const imergReport = [];
for (const p of points) {
  if (!raw.has(p.id)) { imergReport.push(`${p.id}: sin POWER/ERA5`); continue; }
  const rain = imergRain(p);
  if (!rain) { imergReport.push(`${p.id}: sin caché IMERG`); continue; }
  const b = buildBundle(raw.get(p.id).power, rain, { lat: p.lat, lon: p.lon });
  const bad = inTrainYears(b.invalidYears);
  imergReport.push(`${p.id}: ${bad.length ? `años inválidos ${bad.join(',')}` : 'completo'}`);
}
const useImerg = failed.length === 0 && imergReport.every((l) => l.endsWith('completo'));
console.log(`\nIMERG por punto:\n  ${imergReport.join('\n  ')}`);
console.log(`Fuente de lluvia del conjunto: ${useImerg ? 'IMERG (completo en los 20 puntos)' : 'ERA5 (IMERG no está completo en todos los puntos)'}\n`);

// 3) Bundles finales + series alternas en los pilotos.
const ok = [];
for (const [n, p] of points.entries()) {
  if (!raw.has(p.id)) continue;
  const { power, era5 } = raw.get(p.id);
  const rain = useImerg ? imergRain(p) : { ...era5, source: 'ERA5' };
  const b = buildBundle(power, rain, { lat: p.lat, lon: p.lon });
  for (const k of SERIES) b[k] = round(b[k], 2);
  if (PILOTS.includes(p.id)) {
    const align = (dates, vals) => { const m = new Map(dates.map((d, i) => [d, vals[i]])); return round(b.dates.map((d) => (m.get(d) ?? null)), 1); };
    b.rainAlt = { ERA5: align(era5.dates, era5.rain) };
    const im = imergRain(p); if (im) b.rainAlt.IMERG = align(im.dates, im.rain);
    const cdoc = rainDoc(p.id, 'chirps');
    if (cdoc) { const c = climateservRain(cdoc, power.dates, 'CHIRPS'); b.rainAlt.CHIRPS = align(c.dates, c.rain); }
    if (power.rainPower) b.rainAlt.POWER = align(power.dates, power.rainPower); // solo para comparar; el modelo no la usa
  }
  const file = new URL(`${p.id}.json`, CACHE);
  writeFileSync(file, JSON.stringify(b));
  console.log(`[${n + 1}/${points.length}] ${p.id}: rain=${b.rainSource}, days=${b.dates.length}, elev=${b.elevation}, invalidYears=${JSON.stringify(b.invalidYears)}${b.rainAlt ? `, rainAlt=${Object.keys(b.rainAlt).join('+')}` : ''}`);
  if (PILOTS.includes(p.id)) copyFileSync(file, new URL(`${p.id}.json`, SNAP));
  ok.push(p.id);
}
console.log(`\nResumen: ${ok.length}/${points.length} puntos listos; fallidos: ${failed.length ? failed.join(', ') : 'ninguno'}`);
console.log(`Snapshots: ${PILOTS.filter((id) => ok.includes(id)).join(', ')}`);
if (failed.length) process.exitCode = 1;
