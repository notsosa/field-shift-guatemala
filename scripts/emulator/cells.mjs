// Puntos que comparten celda de clima: NASA POWER da temperatura y humedad en celdas de ~0.5° con la
// elevación media de la celda, así que varios municipios reciben exactamente las mismas series.
const WEATHER_KEYS = ['elevation', 'tmax', 'tmin', 'tdew'];
const ALL_KEYS = [...WEATHER_KEYS, 'rs', 'u2', 'pressure', 'rain'];

const signature = (bundle, keys) => JSON.stringify(keys.map((k) => bundle[k]));

/**
 * bundles: {id: bundle}. Devuelve {id: {weatherMates, identicalMates}}:
 * weatherMates = otros puntos con la misma celda de temperatura (elevación + tmax/tmin/tdew idénticas);
 * identicalMates = otros puntos con todas las series de clima idénticas (además radiación, viento, presión y lluvia).
 */
export function sharedCells(bundles) {
  const ids = Object.keys(bundles);
  const w = Object.fromEntries(ids.map((id) => [id, signature(bundles[id], WEATHER_KEYS)]));
  const all = Object.fromEntries(ids.map((id) => [id, signature(bundles[id], ALL_KEYS)]));
  return Object.fromEntries(ids.map((id) => [id, {
    weatherMates: ids.filter((o) => o !== id && w[o] === w[id]),
    identicalMates: ids.filter((o) => o !== id && all[o] === all[id]),
  }]));
}
