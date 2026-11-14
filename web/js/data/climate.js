// Descarga de clima (NASA POWER + ERA5 vía Open-Meteo) y armado del ClimateBundle.
// Sin dependencias; corre en Node 20+ y navegadores (fetch global).

const POWER_URL = 'https://power.larc.nasa.gov/api/temporal/daily/point';
const ERA5_URL = 'https://archive-api.open-meteo.com/v1/archive';
const POWER_PARAMS = 'T2M_MAX,T2M_MIN,T2MDEW,ALLSKY_SFC_SW_DWN,WS2M,PS';
const MAX_GAP_DAYS = 3;
const SERIES = ['tmax', 'tmin', 'tdew', 'rs', 'u2', 'pressure', 'rain'];

export const CLIMATE_SOURCES = [
  'NASA POWER Daily API (MERRA-2, CERES SYN1deg), community AG — https://power.larc.nasa.gov/docs/services/api/temporal/daily/',
  'Copernicus ERA5 reanalysis via Open-Meteo archive API — https://open-meteo.com/en/docs/historical-weather-api',
];

export function isInsideGuatemala(lat, lon) {
  return lat >= 13.6 && lat <= 17.9 && lon >= -92.3 && lon <= -88.1;
}

async function getJson(fetchFn, url) {
  const res = await fetchFn(url);
  if (!res.ok) throw new Error(`HTTP ${res.status} from ${url.split('?')[0]}`);
  return res.json();
}

const isoFromCompact = (s) => `${s.slice(0, 4)}-${s.slice(4, 6)}-${s.slice(6, 8)}`;

export async function fetchPowerDaily(lat, lon, fetchFn = fetch, { start = '20010101', end = '20251231' } = {}) {
  const url = `${POWER_URL}?parameters=${POWER_PARAMS}&community=AG&longitude=${lon}&latitude=${lat}&start=${start}&end=${end}&format=JSON`;
  const json = await getJson(fetchFn, url);
  const p = json.properties.parameter;
  const keys = Object.keys(p.T2M_MAX).sort();
  const pick = (name) => keys.map((k) => {
    const v = p[name][k];
    return v === -999 || v == null ? null : v;
  });
  return {
    dates: keys.map(isoFromCompact),
    tmax: pick('T2M_MAX'), tmin: pick('T2M_MIN'), tdew: pick('T2MDEW'),
    rs: pick('ALLSKY_SFC_SW_DWN'), u2: pick('WS2M'), pressure: pick('PS'),
    elevation: json.geometry.coordinates[2],
  };
}

export async function fetchEra5Rain(lat, lon, fetchFn = fetch, { start = '2001-01-01', end = '2025-12-31' } = {}) {
  const url = `${ERA5_URL}?latitude=${lat}&longitude=${lon}&start_date=${start}&end_date=${end}&daily=precipitation_sum&timezone=America%2FGuatemala&models=era5`;
  const json = await getJson(fetchFn, url);
  return { dates: json.daily.time.slice(), rain: json.daily.precipitation_sum.map((v) => (v == null ? null : v)) };
}

// Interpola linealmente tramos de null de <= MAX_GAP_DAYS con valor a ambos lados. Modifica el arreglo.
function interpolateShortGaps(arr) {
  let i = 0;
  while (i < arr.length) {
    if (arr[i] !== null) { i++; continue; }
    let j = i;
    while (j < arr.length && arr[j] === null) j++;
    const len = j - i;
    if (i > 0 && j < arr.length && len <= MAX_GAP_DAYS) {
      const a = arr[i - 1]; const b = arr[j];
      for (let k = 0; k < len; k++) arr[i + k] = a + ((b - a) * (k + 1)) / (len + 1);
    }
    i = j;
  }
}

const agriYear = (iso) => (Number(iso.slice(5, 7)) >= 4 ? Number(iso.slice(0, 4)) : Number(iso.slice(0, 4)) - 1);

export function buildBundle(power, era5, { lat, lon }) {
  const rainByDate = new Map(era5.dates.map((d, i) => [d, era5.rain[i]]));
  const idx = [];
  power.dates.forEach((d, i) => { if (rainByDate.has(d)) idx.push(i); });
  const dates = idx.map((i) => power.dates[i]);
  const bundle = { dates };
  for (const k of ['tmax', 'tmin', 'tdew', 'rs', 'u2', 'pressure']) bundle[k] = idx.map((i) => power[k][i]);
  bundle.rain = dates.map((d) => rainByDate.get(d));
  for (const k of SERIES) interpolateShortGaps(bundle[k]);

  const invalid = new Set();
  dates.forEach((d, i) => { if (SERIES.some((k) => bundle[k][i] === null)) invalid.add(agriYear(d)); });

  return {
    ...bundle,
    rainSource: 'ERA5', elevation: power.elevation, lat, lon,
    sources: CLIMATE_SOURCES.slice(), fallback: false,
    invalidYears: [...invalid].sort((a, b) => a - b),
  };
}
