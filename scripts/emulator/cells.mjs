// Puntos que comparten celda de clima: NASA POWER da temperatura y humedad en celdas de ~0.5° con la elevación media de la
// celda, así que varios municipios parten de las mismas series (la temperatura se corrige luego a la elevación de cada
// parcela con un ΔT propio, ver correctToSiteElevation). La celda se reconoce por la elevación de la celda y por las series
// de tmax/tmin SIN la corrección (se resta el ΔT guardado en el bundle; tolerancia de 0.011 °C por el redondeo a 2 decimales).
const TOL = 0.011;
const SHARED_KEYS = ['rs', 'u2', 'rain']; // no dependen de la elevación de la parcela

function rawTemperature(id, bundle) {
  const dT = bundle.temperatureCorrection?.deltaT;
  if (!Number.isFinite(dT) || !Number.isFinite(bundle.cellElevation)) {
    throw new Error(`sharedCells: el bundle de ${id} no trae cellElevation y temperatureCorrection.deltaT (¿bundle anterior a la corrección térmica?)`);
  }
  return { cellElevation: bundle.cellElevation, tmax: bundle.tmax.map((v) => v - dT), tmin: bundle.tmin.map((v) => v - dT) };
}

function sameCell(a, b) {
  if (a.cellElevation !== b.cellElevation || a.tmax.length !== b.tmax.length) return false;
  for (let i = 0; i < a.tmax.length; i++) {
    if (!(Math.abs(a.tmax[i] - b.tmax[i]) < TOL) || !(Math.abs(a.tmin[i] - b.tmin[i]) < TOL)) return false;
  }
  return true;
}

const sameSeries = (x, y) => SHARED_KEYS.every((k) => JSON.stringify(x[k]) === JSON.stringify(y[k]));

/**
 * bundles: {id: bundle}. Devuelve {id: {weatherMates, identicalMates}}:
 * weatherMates = otros puntos con la misma celda de temperatura de POWER (misma elevación de celda y misma tmax/tmin de la celda);
 * identicalMates = weatherMates con además radiación, viento y lluvia idénticos (la presión y la temperatura ya corregidas
 * difieren por la elevación de cada parcela).
 */
export function sharedCells(bundles) {
  const ids = Object.keys(bundles);
  const raw = Object.fromEntries(ids.map((id) => [id, rawTemperature(id, bundles[id])]));
  const mates = Object.fromEntries(ids.map((id) => [id, ids.filter((o) => o !== id && sameCell(raw[id], raw[o]))]));
  return Object.fromEntries(ids.map((id) => [id, {
    weatherMates: mates[id],
    identicalMates: mates[id].filter((o) => sameSeries(bundles[id], bundles[o])),
  }]));
}
