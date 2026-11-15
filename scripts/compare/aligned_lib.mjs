// Funciones puras de la evaluación alineada (semillas 17/29/43, años reservados): resumen entre semillas y conteos de resultados.

// Resumen de un valor por semilla: media, mínimo y máximo (null si falta algún valor).
export function summarizeSeeds(values) {
  if (!values.length || values.some((v) => v == null || Number.isNaN(v))) return { mean: null, min: null, max: null, n: values.length };
  return { mean: values.reduce((a, b) => a + b, 0) / values.length, min: Math.min(...values), max: Math.max(...values), n: values.length };
}

// Conteos de una política: resultados por debajo de 0.5 y casos en que se aparta de la regla. items: [{ value, action, ruleAction }].
export function outcomeCounts(items, threshold = 0.5) {
  return { n: items.length, below05: items.filter((i) => i.value < threshold).length, departsFromRule: items.filter((i) => i.action !== i.ruleAction).length };
}

// Resume una lista de objetos (uno por semilla) campo por campo con summarizeSeeds.
export function summarizeObjects(list, fields) {
  return Object.fromEntries(fields.map((k) => [k, summarizeSeeds(list.map((o) => o[k]))]));
}
