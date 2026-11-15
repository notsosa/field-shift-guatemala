// Catálogo de cultivos: validación de fuentes. Los datos viven en web/data/crops.json.

/** Devuelve Map<id, Crop>. Rechaza cultivos sin fuente agronómica, con econ y sin fuente econ, o con kyStages y sin fuente kyStages. */
export function loadCrops(json) {
  const map = new Map();
  for (const crop of json) {
    if (!crop.sources || !crop.sources.agro) throw new Error(`Cultivo '${crop.id}': falta sources.agro`);
    if (crop.econ != null && !crop.sources.econ) throw new Error(`Cultivo '${crop.id}': econ sin sources.econ`);
    if (crop.kyStages != null && !crop.sources.kyStages) throw new Error(`Cultivo '${crop.id}': kyStages sin sources.kyStages`);
    map.set(crop.id, crop);
  }
  return map;
}
