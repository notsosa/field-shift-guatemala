// Elevación del terreno de cada punto de scripts/emulator/points.json (modelo digital Copernicus DEM GLO-90) vía la API de
// elevación de Open-Meteo, un agregador de datos de Copernicus. Es la ÚNICA llamada de red de la corrección térmica
// (solo se envían coordenadas): el resultado queda en scripts/data/site_elevation.json y en `siteElevation` de cada punto.
// Uso: node scripts/data/fetch_site_elevation.mjs [--refresh]   (sin --refresh usa el caché si existe)
import { readFileSync, writeFileSync, existsSync } from 'node:fs';

export const SITE_ELEVATION_SOURCE = 'Open-Meteo Elevation API (agregador de Copernicus DEM GLO-90, ~90 m) — https://open-meteo.com/en/docs/elevation-api';
const URL_BASE = 'https://api.open-meteo.com/v1/elevation';
const here = (p) => new URL(p, import.meta.url);
const POINTS = here('../emulator/points.json');
const CACHE = here('./site_elevation.json');

const points = JSON.parse(readFileSync(POINTS, 'utf8'));
let cache;
if (!process.argv.includes('--refresh') && existsSync(CACHE)) {
  cache = JSON.parse(readFileSync(CACHE, 'utf8'));
} else {
  const url = `${URL_BASE}?latitude=${points.map((p) => p.lat).join(',')}&longitude=${points.map((p) => p.lon).join(',')}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} de la API de elevación`);
  const { elevation } = await res.json();
  if (!Array.isArray(elevation) || elevation.length !== points.length || elevation.some((v) => typeof v !== 'number' || !Number.isFinite(v))) {
    throw new Error('Respuesta de elevación incompleta o no numérica; no se escribió nada');
  }
  cache = {
    source: SITE_ELEVATION_SOURCE,
    fetched: new Date().toISOString().slice(0, 10),
    points: Object.fromEntries(points.map((p, i) => [p.id, { lat: p.lat, lon: p.lon, elevation: elevation[i] }])),
  };
  writeFileSync(CACHE, JSON.stringify(cache, null, 1) + '\n');
}

// Inserta (o reemplaza) siteElevation/siteElevationSource en cada línea de points.json sin reformatear el resto.
const lines = readFileSync(POINTS, 'utf8').split('\n');
let n = 0;
const out = lines.map((line) => {
  const m = line.match(/"id": "([^"]+)"/);
  if (!m) return line;
  const c = cache.points[m[1]];
  if (!c) throw new Error(`Sin elevación para ${m[1]}`);
  n++;
  const clean = line.replace(/"siteElevation": [^,]+, "siteElevationSource": "[^"]*", /, '');
  return clean.replace('"heldOut":', `"siteElevation": ${c.elevation}, "siteElevationSource": ${JSON.stringify(cache.source)}, "heldOut":`);
});
if (n !== points.length) throw new Error('No coinciden las líneas de points.json con los puntos');
writeFileSync(POINTS, out.join('\n'));
console.log(`siteElevation escrito en ${n} puntos`);
for (const p of points) console.log(`${p.id}: ${cache.points[p.id].elevation} m`);
