// Mapa del Corredor Seco: mediana 2001–2024 de (alternativa − rotación actual) según el emulador,
// con paleta divergente apta para daltonismo centrada en 0 (azul = mejor, rojo = peor, gris = igual).
import { encodeFeatures } from '../model/emulator.js';
import { median, clamp01 } from './bestSowing.js';
import { t, fmtDiff, fmtError, fmtNumber, locale, TARGET_META } from './emulatorStrings.js';

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

/** Cultivos de comida de la secuencia (ky ≠ null): los que promedia waterIndex (targetsOf). Sin repetir, en orden. */
export function foodCropIds(sequence, crops) {
  return [...new Set(sequence.phases.map((ph) => ph.cropId))].filter((id) => crops.get(id)?.ky != null);
}

/** ¿waterIndex de la alternativa promedia los mismos cultivos que el de la rotación actual? */
export function compareFoodCrops(alternative, current, crops) {
  const alt = foodCropIds(alternative, crops), cur = foodCropIds(current, crops);
  const missing = cur.filter((id) => !alt.includes(id));
  const added = alt.filter((id) => !cur.includes(id));
  return { same: missing.length === 0 && added.length === 0, alt, current: cur, missing, added };
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
export function scaleLimit(values, targetId, band = TARGET_META[targetId].same) {
  const m = TARGET_META[targetId];
  const maxAbs = Math.max(0, ...values.map((v) => Math.abs(v.median ?? 0)));
  return niceLimit(Math.max(maxAbs, 2 * band) * m.scale) / m.scale;
}

/**
 * Banda de "casi igual" del mapa = RMSE medido de la diferencia alternativa − actual (emulator_eval.json → diffError)
 * para ese modelo, alternativa y objetivo. Si falta, se usa la banda fija del objetivo (measured: false).
 */
export function diffBand(evalJson, modelKey, alternative, targetId) {
  const d = evalJson.diffError?.[modelKey]?.[alternative]?.[targetId];
  if (d && Number.isFinite(d.rmse)) return { band: d.rmse, signAgreement: d.signAgreement ?? null, measured: true };
  return { band: TARGET_META[targetId].same, signAgreement: null, measured: false };
}

/**
 * Municipios que comparten celda de temperatura de NASA POWER (weatherMates de grid_features.json):
 * grupos en orden de aparición (con la elevación de la celda), los municipios a más de 1,500 m (elevación del pueblo, la de la
 * temperatura corregida) y los de lluvia, radiación y viento idénticos (identicalMates).
 */
export function cellGroups(points, highM = 1500) {
  const ids = new Set(points.map((p) => p.id));
  const groupOf = (p, key) => [p.id, ...(p[key] ?? []).filter((id) => ids.has(id))];
  const collect = (key) => {
    const seen = new Set();
    const out = [];
    for (const p of points) {
      if (seen.has(p.id) || !(p[key] ?? []).some((id) => ids.has(id))) continue;
      const g = groupOf(p, key);
      g.forEach((id) => seen.add(id));
      out.push({ ids: g, elevation: p.cellElevation ?? p.elevation });
    }
    return { out, seen };
  };
  const w = collect('weatherMates');
  return {
    nShared: w.seen.size,
    groups: w.out,
    high: points.filter((p) => p.elevation > highM).map((p) => ({ ids: [p.id], elevation: p.elevation })),
    identical: collect('identicalMates').out.map((g) => g.ids),
  };
}

const listNames = (lang, names) => new Intl.ListFormat(locale(lang), { type: 'conjunction' }).format(names);

/** Líneas del tooltip sobre la celda de clima del punto. byId: Map id → punto (para los nombres). */
export function cellLines(lang, point, byId) {
  const names = (list) => listNames(lang, (list ?? []).filter((id) => byId.has(id)).map((id) => byId.get(id).name));
  const elev = fmtNumber(lang, point.cellElevation ?? point.elevation, 0);
  const site = fmtNumber(lang, point.elevation, 0);
  const lines = [];
  if ((point.weatherMates ?? []).some((id) => byId.has(id))) lines.push(t(lang, 'tipSharedCell', { mates: names(point.weatherMates), elev, site }));
  else lines.push(t(lang, 'tipOwnCell', { elev, site }));
  if ((point.identicalMates ?? []).some((id) => byId.has(id))) lines.push(t(lang, 'tipIdentical', { mates: names(point.identicalMates) }));
  return lines;
}

/** Signo de "mejor": +1 si un valor mayor es mejor, −1 si menor es mejor (suelo desnudo). */
export const betterSign = (targetId) => (TARGET_META[targetId].higherIsBetter ? 1 : -1);

/** Cuenta mejor / casi igual / peor y los extremos (en sentido de "mejor"); band = mitad del ancho de "casi igual". */
export function summarize(values, targetId, band = TARGET_META[targetId].same) {
  const sg = betterSign(targetId);
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

/**
 * Dirección y desplazamiento del tooltip de un círculo en (x, y) dentro de un mapa w×h, para que no lo recorte la caja.
 * El tooltip mide hasta ~TIP_H de alto y ~2·TIP_HALF_W de ancho: cerca del borde de arriba o de abajo se abre hacia
 * el otro lado y se corre en horizontal lo justo para caber; en medio se abre hacia el lado con más espacio.
 */
const TIP_H = 170, TIP_HALF_W = 130;
export function tooltipAim(x, y, w, h) {
  const vertical = y < TIP_H ? 'bottom' : y > h - TIP_H ? 'top' : null;
  if (vertical || (x >= TIP_HALF_W && x <= w - TIP_HALF_W)) {
    const direction = vertical ?? 'top';
    const dx = x < TIP_HALF_W ? TIP_HALF_W - x : x > w - TIP_HALF_W ? w - TIP_HALF_W - x : 0;
    return { direction, offset: [Math.round(dx), direction === 'bottom' ? 10 : -10] };
  }
  return x < TIP_HALF_W ? { direction: 'right', offset: [12, 0] } : { direction: 'left', offset: [-12, 0] };
}

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
  const aimTooltips = () => {
    const { x: w, y: h } = map.getSize();
    for (const dot of dots.values()) {
      const { x, y } = map.latLngToContainerPoint(dot.getLatLng());
      Object.assign(dot.getTooltip().options, tooltipAim(x, y, w, h));
    }
  };
  aimTooltips();
  map.on('zoomend moveend resize', aimTooltips);
  return { map, dots };
}

/** Pinta los círculos y sus tooltips. values = null → sin dato (gris), p. ej. alternativa que exige riego. */
export function paintMap(ctrl, points, values, { lang, targetId, limit }) {
  const byId = new Map((values ?? []).map((v) => [v.point.id, v]));
  const pointsById = new Map(points.map((p) => [p.id, p]));
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
      + `<span class="tip-train">${esc(t(lang, p.heldOut ? 'tipHeldOut' : 'tipTrained'))}</span>`
      + cellLines(lang, p, pointsById).map((s) => `<span class="tip-cell">${esc(s)}</span>`).join(''),
    );
  }
}

/** Leyenda: barra divergente con extremos "peor/mejor", ticks con signo y la precisión del modelo elegido. */
export function renderLegend(el, { lang, targetId, limit, accuracyText, bandText = '', caveatText, likeForLike = true }) {
  const sg = betterSign(targetId);
  const left = -sg * limit, right = sg * limit;
  const disp = limit * TARGET_META[targetId].scale;
  const tickDigits = Number.isInteger(Number(disp.toPrecision(12))) ? 0 : Math.min(TARGET_META[targetId].digits, 3);
  const tick = (v) => fmtDiff(lang, targetId, v, tickDigits);
  el.innerHTML = `
    <div class="legend-title">${esc(t(lang, `target_${targetId}`))} <span class="legend-desc">${esc(t(lang, `targetDesc_${targetId}`))}</span></div>
    <div class="legend-bar" style="background:linear-gradient(to right, ${DIVERGING_STOPS.join(', ')})" aria-hidden="true"></div>
    <div class="legend-ticks"><span>${esc(tick(left))}</span><span>0 · ${esc(t(lang, 'legendSame'))}</span><span>${esc(tick(right))}</span></div>
    <div class="legend-ends"><span>◀ ${esc(t(lang, likeForLike ? 'legendWorse' : 'legendLower'))}</span><span>${esc(t(lang, likeForLike ? 'legendBetter' : 'legendHigher'))} ▶</span></div>
    <div class="legend-held"><svg width="22" height="22" aria-hidden="true"><circle cx="11" cy="11" r="9" fill="none" stroke="${INK}" stroke-width="2" stroke-dasharray="3 4"/><circle cx="11" cy="11" r="5" fill="${DIVERGING_STOPS[3]}" stroke="${INK}" stroke-width="1.5"/></svg>${esc(t(lang, 'legendHeldOut'))}</div>
    ${accuracyText ? `<p class="legend-acc">${esc(accuracyText)}</p>` : ''}
    ${bandText ? `<p class="legend-acc legend-band">${esc(bandText)}</p>` : ''}
    ${caveatText ? `<p class="legend-acc caveat">${esc(caveatText)}</p>` : ''}`;
}

/** R² del modelo (todas las pruebas y años nuevos). modelKey: 'mlp', 'elm' o 'elmBrowser' (la ELM de la página). */
export function accuracyText(lang, evalJson, modelKey, targetIdx) {
  const m = evalJson[modelKey];
  const y = m?.bySplit?.testYears ?? evalJson.bySplit?.testYears?.[modelKey];
  return t(lang, 'legendAccuracy', {
    model: t(lang, modelKey === 'mlp' ? 'modelShortMlp' : 'modelShortElm'),
    r2: m ? fmtNumber(lang, m.r2[targetIdx], 2) : '—',
    r2y: y ? fmtNumber(lang, y.r2[targetIdx], 2) : '—',
  });
}

/** Texto de la banda de "casi igual" (error medido de la diferencia) para la leyenda. */
export function bandText(lang, targetId, { band, signAgreement, measured }) {
  if (!measured) return '';
  const rmse = fmtError(lang, targetId, band).replace(/^±/, '');
  return signAgreement == null
    ? t(lang, 'legendDiffBandNoSign', { rmse })
    : t(lang, 'legendDiffBand', { rmse, sign: `${fmtNumber(lang, signAgreement * 100, 0)}%` });
}

/** Tabla accesible con todos los municipios (mejor primero). */
export function renderMapTable(el, summary, { lang, targetId }) {
  el.innerHTML = `
    <table class="map-table">
      <thead><tr><th scope="col">${esc(t(lang, 'thMunicipality'))}</th><th scope="col">${esc(t(lang, 'thDepartment'))}</th><th scope="col" class="num">${esc(t(lang, 'thValue'))}</th><th scope="col">${esc(t(lang, 'thTraining'))}</th></tr></thead>
      <tbody>${summary.sorted.map((v) => `<tr><th scope="row">${esc(v.point.name)}</th><td>${esc(v.point.department)}</td><td class="num">${esc(fmtDiff(lang, targetId, v.median))}</td><td>${esc(t(lang, v.point.heldOut ? 'no' : 'yes'))}</td></tr>`).join('')}</tbody>
    </table>`;
}
