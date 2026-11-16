// Descarga NASA POWER EXACTAMENTE como la app de Carlos (app/V01/lib/datos/clima.dart): mismos parámetros, comunidad AG, latitud y longitud con
// 4 decimales, time-standard LST; sin corrección de temperatura a la parcela y con la lluvia de POWER (PRECTOTCORR). Guarda también la elevación
// de la celda (geometry.coordinates[2]). Caché en scripts/emulator/cache_power_app/ (ignorado por git, igual que scripts/emulator/cache/).
// Reporta los días sin dato por variable y punto (-999 o ausentes) en web/data/app_power_coverage.json; aquí no se rellena nada: el hueco lo cubre
// prepararClima de la app (regla del promedio de la ET0 de los últimos siete días y lluvia 0).
// Uso: node scripts/app/fetch_power_app.mjs [--refresh]
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';

const here = (p) => new URL(p, import.meta.url);
const points = JSON.parse(readFileSync(here('../emulator/points.json'), 'utf8'));
const CACHE = here('../emulator/cache_power_app/');
const PARAMS = 'T2M_MAX,T2M_MIN,RH2M,WS2M,ALLSKY_SFC_SW_DWN,PRECTOTCORR';
const MAP = { tmax: 'T2M_MAX', tmin: 'T2M_MIN', humedad: 'RH2M', viento: 'WS2M', radiacion: 'ALLSKY_SFC_SW_DWN', lluvia: 'PRECTOTCORR' };
const START = '20010101', END = '20251231';
const REFRESH = process.argv.includes('--refresh');
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const iso = (k) => `${k.slice(0, 4)}-${k.slice(4, 6)}-${k.slice(6, 8)}`;

export function powerUrl(lat, lon, start = START, end = END) {
  const q = new URLSearchParams({ parameters: PARAMS, community: 'AG', latitude: lat.toFixed(4), longitude: lon.toFixed(4), start, end, format: 'JSON', 'time-standard': 'LST' });
  return `https://power.larc.nasa.gov/api/temporal/daily/point?${q}`;
}
// Igual que ServicioClima.interpretar: -999 (cualquier valor <= -900) o ausente = nulo.
export function interpret(json) {
  const p = json.properties.parameter;
  const keys = Object.keys(p.T2M_MAX).filter((k) => k.length === 8).sort();
  const val = (name, k) => { const v = p[name]?.[k]; return v == null || v <= -900 ? null : v; };
  const out = { dates: keys.map(iso), elevation: json.geometry?.coordinates?.[2] ?? null };
  for (const [name, pn] of Object.entries(MAP)) out[name] = keys.map((k) => val(pn, k));
  return out;
}

async function get(url) {
  for (let a = 1; ; a++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': 'field-shift-research-client' } });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.json();
    } catch (e) {
      if (a >= 4) throw e;
      console.log(`  reintento ${a}: ${e.message}`);
      await sleep(5000 * a);
    }
  }
}

if (import.meta.url === new URL(process.argv[1], 'file:///').href || process.argv[1]?.endsWith('fetch_power_app.mjs')) {
  mkdirSync(CACHE, { recursive: true });
  const report = [];
  for (const [n, p] of points.entries()) {
    const file = new URL(`${p.id}.json`, CACHE);
    if (REFRESH || !existsSync(file)) {
      const data = interpret(await get(powerUrl(p.lat, p.lon)));
      writeFileSync(file, JSON.stringify({ id: p.id, lat: p.lat, lon: p.lon, request: { parameters: PARAMS, community: 'AG', start: START, end: END, timeStandard: 'LST' }, ...data }));
      console.log(`[${n + 1}/${points.length}] ${p.id}: ${data.dates.length} días, celda ${data.elevation} m`);
      await sleep(1000);
    }
    const d = JSON.parse(readFileSync(file, 'utf8'));
    const missing = Object.fromEntries(Object.keys(MAP).map((v) => [v, d[v].filter((x) => x == null).length]));
    const incomplete = d.dates.filter((_, i) => ['tmax', 'tmin', 'humedad', 'viento', 'radiacion'].some((v) => d[v][i] == null)).length;
    report.push({ id: p.id, lat: p.lat, lon: p.lon, cellElevation: d.elevation, siteElevation: p.siteElevation, days: d.dates.length, first: d.dates[0], last: d.dates.at(-1), missing, daysWithoutAnyWeatherValue: incomplete });
  }
  const total = (v) => report.reduce((a, r) => a + r.missing[v], 0);
  const doc = { source: 'NASA POWER Daily API, community AG, parámetros y formato de la app (app/V01/lib/datos/clima.dart)', parameters: PARAMS, period: `${START}..${END}`, nPoints: report.length,
    gapRule: 'La app (prepararClima) descarta los días sin alguno de los cinco datos de ET0 (tmax, tmin, humedad, viento, radiación) y los completa con el promedio de la ET0 de los siete últimos días observados (4.0 si no hay) y lluvia 0; una lluvia nula con el resto completo cuenta 0 sin marcar el día. No se aplicó ninguna otra regla.',
    totalMissingByVariable: Object.fromEntries(Object.keys(MAP).map((v) => [v, total(v)])), points: report };
  writeFileSync(here('../../web/data/app_power_coverage.json'), JSON.stringify(doc, null, 1));
  console.log('faltantes totales por variable', JSON.stringify(doc.totalMissingByVariable));
}
