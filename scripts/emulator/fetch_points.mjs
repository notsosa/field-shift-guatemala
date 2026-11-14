// Descarga POWER + ERA5 para los puntos del Corredor Seco y guarda un ClimateBundle por punto.
// Uso: node scripts/emulator/fetch_points.mjs   (secuencial, con caché y reintentos)
import { readFileSync, writeFileSync, mkdirSync, existsSync, copyFileSync } from 'node:fs';
import { fetchPowerDaily, fetchEra5Rain, buildBundle, isInsideGuatemala } from '../../web/js/data/climate.js';

const here = (p) => new URL(p, import.meta.url);
const points = JSON.parse(readFileSync(here('./points.json'), 'utf8'));
const CACHE = here('./cache/');
const SNAP = here('../../web/data/snapshots/');
const PILOTS = ['chiquimula', 'jutiapa', 'sanmartin'];
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

const round2 = (a) => a.map((v) => (v == null ? v : Math.round(v * 100) / 100));

for (const p of points) {
  if (!isInsideGuatemala(p.lat, p.lon)) throw new Error(`${p.id} fuera de Guatemala`);
}
mkdirSync(CACHE, { recursive: true });
mkdirSync(SNAP, { recursive: true });

const ok = []; const failed = [];
for (const [n, p] of points.entries()) {
  const file = new URL(`${p.id}.json`, CACHE);
  let fetched = false;
  if (!existsSync(file)) {
    try {
      const power = await withRetry(`${p.id} POWER`, () => fetchPowerDaily(p.lat, p.lon));
      const era5 = await withRetry(`${p.id} ERA5`, () => fetchEra5Rain(p.lat, p.lon));
      const b = buildBundle(power, era5, { lat: p.lat, lon: p.lon });
      for (const k of ['tmax', 'tmin', 'tdew', 'rs', 'u2', 'pressure', 'rain']) b[k] = round2(b[k]);
      writeFileSync(file, JSON.stringify(b));
      fetched = true;
    } catch (e) {
      console.log(`[${n + 1}/${points.length}] ${p.id}: FALLÓ ${e.message}`);
      failed.push(p.id);
      await sleep(1000);
      continue;
    }
  }
  const b = JSON.parse(readFileSync(file, 'utf8'));
  console.log(`[${n + 1}/${points.length}] ${p.id}: ${fetched ? 'descargado' : 'en caché'}, days=${b.dates.length}, elev=${b.elevation}, invalidYears=${JSON.stringify(b.invalidYears)}`);
  if (PILOTS.includes(p.id)) copyFileSync(file, new URL(`${p.id}.json`, SNAP));
  ok.push(p.id);
  if (fetched) await sleep(1000);
}
console.log(`\nResumen: ${ok.length}/${points.length} puntos listos; fallidos: ${failed.length ? failed.join(', ') : 'ninguno'}`);
console.log(`Snapshots: ${PILOTS.filter((id) => ok.includes(id)).join(', ')}`);
if (failed.length) process.exitCode = 1;
