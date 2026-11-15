// Descarga de clima (NASA POWER + lluvia ERA5 vía Open-Meteo, o IMERG/CHIRPS vía ClimateSERV) y armado del ClimateBundle.
// Sin dependencias externas; corre en Node 20+ y navegadores (fetch global).
import { satVaporPressure, pressureFromElevation } from '../model/et0.js';

const POWER_URL = 'https://power.larc.nasa.gov/api/temporal/daily/point';
const ERA5_URL = 'https://archive-api.open-meteo.com/v1/archive';
const POWER_PARAMS = 'T2M_MAX,T2M_MIN,T2MDEW,ALLSKY_SFC_SW_DWN,WS2M,PS,PRECTOTCORR';
const MAX_GAP_DAYS = 3;
const SERIES = ['tmax', 'tmin', 'tdew', 'rs', 'u2', 'pressure', 'rain'];

const POWER_SOURCE = 'NASA POWER Daily API (MERRA-2, CERES SYN1deg), community AG — https://power.larc.nasa.gov/docs/services/api/temporal/daily/';
export const RAIN_SOURCES = {
  ERA5: 'Copernicus ERA5 reanalysis via Open-Meteo archive API — https://open-meteo.com/en/docs/historical-weather-api',
  IMERG: 'NASA GPM IMERG daily rainfall via ClimateSERV (NASA-USAID SERVIR) — https://climateserv.servirglobal.net/',
  CHIRPS: 'CHIRPS v2.0 daily rainfall (UCSB Climate Hazards Center) via ClimateSERV (NASA-USAID SERVIR) — https://climateserv.servirglobal.net/',
};
export const CLIMATE_SOURCES = [POWER_SOURCE, RAIN_SOURCES.ERA5];

// Corrección de la temperatura de la celda de POWER (elevación media de la celda) a la elevación de la parcela.
// Gradiente fijo del manual FAO-56 / atmósfera estándar; no es un parámetro de calibración.
export const LAPSE_RATE = -0.0065; // °C por metro
export const TEMPERATURE_CORRECTION_METHOD = 'Tmax and Tmin of the NASA POWER cell shifted by -0.0065 °C/m x (site elevation - cell elevation); relative humidity (actual vapour pressure over saturation at the cell mean temperature) held constant to get the site dew point; pressure scaled with the FAO-56 barometric formula; radiation, wind and rain unchanged';

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
  const out = {
    dates: keys.map(isoFromCompact),
    tmax: pick('T2M_MAX'), tmin: pick('T2M_MIN'), tdew: pick('T2MDEW'),
    rs: pick('ALLSKY_SFC_SW_DWN'), u2: pick('WS2M'), pressure: pick('PS'),
    elevation: json.geometry.coordinates[2],
  };
  // POWER rain (PRECTOTCORR) is only for comparing sources; the water balance never uses it.
  if (p.PRECTOTCORR) out.rainPower = pick('PRECTOTCORR');
  return out;
}

export async function fetchEra5Rain(lat, lon, fetchFn = fetch, { start = '2001-01-01', end = '2025-12-31' } = {}) {
  const url = `${ERA5_URL}?latitude=${lat}&longitude=${lon}&start_date=${start}&end_date=${end}&daily=precipitation_sum&timezone=America%2FGuatemala&models=era5`;
  const json = await getJson(fetchFn, url);
  return { dates: json.daily.time.slice(), rain: json.daily.precipitation_sum.map((v) => (v == null ? null : v)) };
}

/**
 * Alinea la lluvia diaria de un caché de ClimateSERV ({days: {fecha: mm|null}}) con una lista de fechas.
 * Lo que ClimateSERV no devolvió (o devolvió vacío) queda null: nunca se inventa.
 */
export function climateservRain(doc, dates, source, sourceDetail) {
  const out = { dates: dates.slice(), rain: dates.map((d) => (doc.days[d] == null ? null : doc.days[d])), source };
  if (sourceDetail) out.sourceDetail = sourceDetail;
  return out;
}

/**
 * Cobertura real de una serie de lluvia ya alineada con las fechas de POWER: días null (ausentes o vacíos) y
 * primer/último día con dato. No confía en el conteo que traiga el caché.
 */
export function rainCoverage(rain) {
  let missingDays = 0; let first = null; let last = null;
  rain.rain.forEach((v, i) => {
    if (v == null) { missingDays++; return; }
    if (first === null) first = rain.dates[i];
    last = rain.dates[i];
  });
  return { missingDays, first, last };
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

/**
 * Mueve la temperatura de la celda de POWER a la elevación de la parcela. Función pura: no modifica `power`.
 * tmax y tmin suman ΔT = LAPSE_RATE × (zParcela − zCelda); la humedad relativa se conserva (ea de la celda con su punto de
 * rocío, contra la saturación a la temperatura media de la celda; el punto de rocío de la parcela sale de esa misma
 * humedad relativa a la temperatura media de la parcela); la presión se escala con la fórmula barométrica de FAO-56
 * (cociente entre las dos elevaciones). Radiación, viento y lluvia no cambian. Los null pasan como null.
 * Sin elevación de la parcela (o de la celda) falla: no hay valor de respaldo.
 */
export function correctToSiteElevation(power, siteElevation, { siteElevationSource } = {}) {
  if (!Number.isFinite(siteElevation)) throw new Error('correctToSiteElevation: falta la elevación de la parcela (siteElevation); no se usa un valor de respaldo');
  const cellElevation = power.elevation;
  if (!Number.isFinite(cellElevation)) throw new Error('correctToSiteElevation: la celda de POWER no trae elevación');
  const deltaT = LAPSE_RATE * (siteElevation - cellElevation) + 0; // + 0: evita -0
  const pRatio = pressureFromElevation(siteElevation) / pressureFromElevation(cellElevation);
  const n = power.tmax.length;
  const tmax = new Array(n); const tmin = new Array(n); const tdew = new Array(n); const pressure = new Array(n);
  for (let i = 0; i < n; i++) {
    const a = power.tmax[i]; const b = power.tmin[i]; const d = power.tdew[i]; const p = power.pressure[i];
    tmax[i] = a === null ? null : a + deltaT;
    tmin[i] = b === null ? null : b + deltaT;
    pressure[i] = p === null ? null : p * pRatio;
    if (d === null || a === null || b === null) { tdew[i] = null; continue; }
    const tmeanCell = (a + b) / 2;
    const rh = satVaporPressure(d) / satVaporPressure(tmeanCell);
    const eaSite = rh * satVaporPressure(tmeanCell + deltaT);
    const x = Math.log(eaSite / 0.6108); // inversa de la ecuación 11 de FAO-56
    tdew[i] = (237.3 * x) / (17.27 - x);
  }
  return {
    tmax, tmin, tdew, pressure, elevation: siteElevation, cellElevation,
    temperatureCorrection: {
      lapseRate: LAPSE_RATE, deltaT, method: TEMPERATURE_CORRECTION_METHOD,
      source: siteElevationSource ?? 'site elevation supplied by the caller',
    },
  };
}

const agriYear = (iso) => (Number(iso.slice(5, 7)) >= 4 ? Number(iso.slice(0, 4)) : Number(iso.slice(0, 4)) - 1);

/**
 * Arma el ClimateBundle. `rain` = {dates, rain, source?: 'ERA5'|'IMERG'|'CHIRPS', sourceDetail?}.
 * La temperatura, el punto de rocío y la presión de POWER se llevan antes a `siteElevation` (ver correctToSiteElevation);
 * `elevation` del bundle es la de la parcela y `cellElevation` la de la celda.
 * Los huecos <= 3 días se interpolan solo en las series que no son lluvia; un día de lluvia null
 * se queda null y su año agrícola va a invalidYears (no se inventa lluvia).
 */
export function buildBundle(power, rain, { lat, lon, siteElevation, siteElevationSource }) {
  const site = correctToSiteElevation(power, siteElevation, { siteElevationSource });
  const source = rain.source ?? 'ERA5';
  if (!Object.hasOwn(RAIN_SOURCES, source)) throw new Error(`Fuente de lluvia desconocida: ${source}`);
  const rainByDate = new Map(rain.dates.map((d, i) => [d, rain.rain[i]]));
  const idx = [];
  power.dates.forEach((d, i) => { if (rainByDate.has(d)) idx.push(i); });
  const dates = idx.map((i) => power.dates[i]);
  const bundle = { dates };
  for (const k of ['tmax', 'tmin', 'tdew', 'pressure']) bundle[k] = idx.map((i) => site[k][i]);
  for (const k of ['rs', 'u2']) bundle[k] = idx.map((i) => power[k][i]);
  bundle.rain = dates.map((d) => rainByDate.get(d));
  for (const k of SERIES) if (k !== 'rain') interpolateShortGaps(bundle[k]);

  const invalid = new Set();
  dates.forEach((d, i) => { if (SERIES.some((k) => bundle[k][i] === null)) invalid.add(agriYear(d)); });

  const rainLine = rain.sourceDetail ? `${RAIN_SOURCES[source]} (${rain.sourceDetail})` : RAIN_SOURCES[source];
  return {
    ...bundle,
    rainSource: source, elevation: site.elevation, cellElevation: site.cellElevation, lat, lon,
    temperatureCorrection: site.temperatureCorrection,
    sources: [POWER_SOURCE, rainLine, ...(siteElevationSource ? [siteElevationSource] : [])], fallback: false,
    invalidYears: [...invalid].sort((a, b) => a - b),
  };
}
