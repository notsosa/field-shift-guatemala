// Catálogo de cultivos: validación de fuentes. Los datos viven en web/data/crops.json.

/** Devuelve Map<id, Crop>. Rechaza cultivos sin fuente agronómica, o con econ y sin fuente econ. */
export function loadCrops(json) {
  const map = new Map();
  for (const crop of json) {
    if (!crop.sources || !crop.sources.agro) throw new Error(`Cultivo '${crop.id}': falta sources.agro`);
    if (crop.econ != null && !crop.sources.econ) throw new Error(`Cultivo '${crop.id}': econ sin sources.econ`);
    map.set(crop.id, crop);
  }
  return map;
}
