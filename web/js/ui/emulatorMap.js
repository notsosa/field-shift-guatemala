// Mapa del Corredor Seco: mediana 2001–2024 de (alternativa − rotación actual) según el emulador,
// con paleta divergente apta para daltonismo centrada en 0 (azul = mejor, rojo = peor, gris = igual).
import { encodeFeatures } from '../model/emulator.js';
import { median, clamp01 } from './bestSowing.js';
import { t, fmtDiff, fmtError, fmtNumber, TARGET_META } from './emulatorStrings.js';

/** De "peor" a "mejor": rojo → gris neutro → azul (dos tonos opuestos, mismo número de pasos por brazo). */
export const DIVERGING_STOPS = ['#a3262a', '#e34948', '#f2aca7', '#f0efec', '#9ec5f4', '#3987e5', '#184f95'];
const INK = '#1b1d1a';
const NA_FILL = '#c9c7bf';

/** Diferencias por punto (mediana entre años) del objetivo targetIdx; predicciones recortadas a [0, 1]. */
export function computeMapValues({ grid, predict, alternative, targetIdx, texture, slopeClass, irrigation, offset = 0 }) {
  const t0 = performance.now();
  let predictions = 0;
  const base = { texture, slopeClass, irrigation, sowOffsetDays: offset };
  const values = grid.points.map((point) => {
    const diffs = [];
    for (const year of grid.years) {
      const clim = grid.climate[point.id]?.[year];
      const ph = grid.pheno[point.id]?.[year]?.[String(offset)];
      if (!clim || !ph) continue;
      const a = clamp01(predict(encodeFeatures(clim, ph, { ...base, sequenceId: alternative }))[targetIdx]);
      const c = clamp01(predict(encodeFeatures(clim, ph, { ...base, sequenceId: 'actual' }))[targetIdx]);
      predictions += 2;
      diffs.push(a - c);
    }
    return { point, median: median(diffs), n: diffs.length };
  });
  return { values, predictions, ms: performance.now() - t0 };
}

const hex2rgb = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
const rgb2hex = (c) => `#${c.map((v) => Math.round(v).toString(16).padStart(2, '0')).join('')}`;

/** tv ∈ [−1, 1]: −1 = mucho peor, 0 = igual, +1 = mucho mejor (se recorta fuera del rango). */
export function divergingColor(tv) {
  const n = DIVERGING_STOPS.length;
  const pos = ((Math.min(1, Math.max(-1, tv)) + 1) / 2) * (n - 1);
  const i = Math.min(Math.floor(pos), n - 2);
  const f = pos - i;
  const a = hex2rgb(DIVERGING_STOPS[i]), b = hex2rgb(DIVERGING_STOPS[i + 1]);
  return rgb2hex(a.map((v, k) => v + (b[k] - v) * f));
}

const NICE_STEPS = [1, 1.5, 2, 2.5, 3, 4, 5, 6, 8, 10];

/** Techo "bonito" (1, 1.5, 2, 2.5, 3, 4, 5, 6, 8 o 10 × 10^k; 1 si x ≤ 0): la escala usa casi todo el color. */
export function niceLimit(x) {
  if (!(x > 0)) return 1;
  const e = 10 ** Math.floor(Math.log10(x));
  const f = Number((x / e).toPrecision(12));
  return Number((NICE_STEPS.find((s) => f <= s) * e).toPrecision(12));
}

/** Límite simétrico de la escala en unidades del objetivo (al menos 2× la banda de "casi igual"). */
export function scaleLimit(values, targetId) {
  const m = TARGET_META[targetId];
  const maxAbs = Math.max(0, ...values.map((v) => Math.abs(v.median ?? 0)));
  return niceLimit(Math.max(maxAbs, 2 * m.same) * m.scale) / m.scale;
}

/** Signo de "mejor": +1 si un valor mayor es mejor, −1 si menor es mejor (suelo desnudo). */
export const betterSign = (targetId) => (TARGET_META[targetId].higherIsBetter ? 1 : -1);

/** Cuenta mejor / casi igual / peor y los extremos (en sentido de "mejor"). */
export function summarize(values, targetId) {
  const sg = betterSign(targetId), band = TARGET_META[targetId].same;
  const ok = values.filter((v) => v.median != null);
  const sorted = [...ok].sort((a, b) => sg * b.median - sg * a.median);
  return {
    n: ok.length,
    better: ok.filter((v) => sg * v.median > band).length,
    worse: ok.filter((v) => sg * v.median < -band).length,
    same: ok.filter((v) => Math.abs(v.median) <= band).length,
    top: sorted[0] && sg * sorted[0].median > band ? sorted[0] : null,
    bottom: sorted.at(-1) && sg * sorted.at(-1).median < -band ? sorted.at(-1) : null,
    sorted,
  };
}

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

/** Crea el mapa Leaflet (base OSM) con un círculo por punto; anillo punteado si el punto quedó fuera del entrenamiento. */
export function createEmulatorMap(el, points) {
  const L = globalThis.L;
  const map = L.map(el, { scrollWheelZoom: false, dragging: !L.Browser.mobile, zoomSnap: 0.25 });
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
    maxZoom: 18,
    attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
  }).addTo(map);
  map.fitBounds(L.latLngBounds(points.map((p) => [p.lat, p.lon])), { padding: [40, 40] });
  const dots = new Map();
  for (const p of points) {
    if (p.heldOut) {
      L.circleMarker([p.lat, p.lon], { radius: 15, color: INK, weight: 2, dashArray: '3 4', fill: false, interactive: false, className: 'held-ring' }).addTo(map);
    }
    const dot = L.circleMarker([p.lat, p.lon], { radius: 10, color: INK, weight: 1.5, fillColor: NA_FILL, fillOpacity: 1, className: 'emu-dot' }).addTo(map);
    dot.bindTooltip('', { direction: 'top', offset: [0, -10], className: 'emu-tip' });
    dots.set(p.id, dot);
  }
  // El mapa recorta lo que sale de su caja: cerca de un borde el tooltip se abre hacia el lado contrario.
  const AIM = { top: [0, -10], bottom: [0, 10], left: [-12, 0], right: [12, 0] };
  const aimTooltips = () => {
    const { x: w } = map.getSize();
    for (const dot of dots.values()) {
      const { x, y } = map.latLngToContainerPoint(dot.getLatLng());
      const direction = x > w - 140 ? 'left' : x < 140 ? 'right' : y < 120 ? 'bottom' : 'top';
      Object.assign(dot.getTooltip().options, { direction, offset: AIM[direction] });
    }
  };
  aimTooltips();
  map.on('zoomend moveend resize', aimTooltips);
  return { map, dots };
}

/** Pinta los círculos y sus tooltips. values = null → sin dato (gris), p. ej. alternativa que exige riego. */
export function paintMap(ctrl, points, values, { lang, targetId, limit }) {
  const byId = new Map((values ?? []).map((v) => [v.point.id, v]));
  const sg = betterSign(targetId);
  for (const p of points) {
    const v = byId.get(p.id);
    const dot = ctrl.dots.get(p.id);
    const has = v && v.median != null;
    dot.setStyle({ fillColor: has ? divergingColor((sg * v.median) / limit) : NA_FILL });
    const valueLine = has
      ? `<span class="tip-value">${esc(t(lang, 'tipVsCurrent', { value: fmtDiff(lang, targetId, v.median) }))}</span>`
      : '';
    dot.setTooltipContent(
      `<strong>${esc(p.name)}</strong><span class="tip-dept">${esc(p.department)}</span>`
      + `<span class="tip-target">${esc(t(lang, `target_${targetId}`))}</span>${valueLine}`
      + `<span class="tip-train">${esc(t(lang, p.heldOut ? 'tipHeldOut' : 'tipTrained'))}</span>`,
    );
  }
}

/** Leyenda: barra divergente con extremos "peor/mejor", ticks con signo y la precisión del modelo elegido. */
export function renderLegend(el, { lang, targetId, limit, accuracyText, caveatText }) {
  const sg = betterSign(targetId);
  const left = -sg * limit, right = sg * limit;
  const disp = limit * TARGET_META[targetId].scale;
  const tickDigits = Number.isInteger(Number(disp.toPrecision(12))) ? 0 : Math.min(TARGET_META[targetId].digits, 3);
  const tick = (v) => fmtDiff(lang, targetId, v, tickDigits);
  el.innerHTML = `
    <div class="legend-title">${esc(t(lang, `target_${targetId}`))} <span class="legend-desc">${esc(t(lang, `targetDesc_${targetId}`))}</span></div>
    <div class="legend-bar" style="background:linear-gradient(to right, ${DIVERGING_STOPS.join(', ')})" aria-hidden="true"></div>
    <div class="legend-ticks"><span>${esc(tick(left))}</span><span>0 · ${esc(t(lang, 'legendSame'))}</span><span>${esc(tick(right))}</span></div>
    <div class="legend-ends"><span>◀ ${esc(t(lang, 'legendWorse'))}</span><span>${esc(t(lang, 'legendBetter'))} ▶</span></div>
    <div class="legend-held"><svg width="22" height="22" aria-hidden="true"><circle cx="11" cy="11" r="9" fill="none" stroke="${INK}" stroke-width="2" stroke-dasharray="3 4"/><circle cx="11" cy="11" r="5" fill="${DIVERGING_STOPS[3]}" stroke="${INK}" stroke-width="1.5"/></svg>${esc(t(lang, 'legendHeldOut'))}</div>
    ${accuracyText ? `<p class="legend-acc">${esc(accuracyText)}</p>` : ''}
    ${caveatText ? `<p class="legend-acc caveat">${esc(caveatText)}</p>` : ''}`;
}

/** Texto de precisión para la leyenda a partir de emulator_eval.json. */
export function accuracyText(lang, evalJson, modelKey, targetIdx, targetId) {
  const m = evalJson[modelKey];
  const y = evalJson.bySplit?.testYears?.[modelKey];
  return t(lang, 'legendAccuracy', {
    model: t(lang, modelKey === 'mlp' ? 'modelShortMlp' : 'modelShortElm'),
    r2: fmtNumber(lang, m.r2[targetIdx], 2),
    r2y: y ? fmtNumber(lang, y.r2[targetIdx], 2) : '—',
    rmse: fmtError(lang, targetId, m.rmse[targetIdx]).replace(/^±/, ''),
  });
}

/** Tabla accesible con todos los municipios (mejor primero). */
export function renderMapTable(el, summary, { lang, targetId }) {
  el.innerHTML = `
    <table class="map-table">
      <thead><tr><th scope="col">${esc(t(lang, 'thMunicipality'))}</th><th scope="col">${esc(t(lang, 'thDepartment'))}</th><th scope="col" class="num">${esc(t(lang, 'thValue'))}</th><th scope="col">${esc(t(lang, 'thTraining'))}</th></tr></thead>
      <tbody>${summary.sorted.map((v) => `<tr><th scope="row">${esc(v.point.name)}</th><td>${esc(v.point.department)}</td><td class="num">${esc(fmtDiff(lang, targetId, v.median))}</td><td>${esc(t(lang, v.point.heldOut ? 'no' : 'yes'))}</td></tr>`).join('')}</tbody>
    </table>`;
}
