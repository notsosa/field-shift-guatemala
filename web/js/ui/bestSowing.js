// Mejor fecha de siembra: el emulador prueba desfases de −20 a +30 días (cada 2) sobre el inicio de lluvias
// y el simulador (runSequence) confirma el desfase 0 y el propuesto. Cálculo puro + dibujo de resultados.
import { climateFeatures, phenoFeatures, encodeFeatures, targetsOf } from '../model/emulator.js';
import { runSequence } from '../model/simulate.js';
import { t, fmtAbs, fmtDiff, fmtNumber, locale } from './emulatorStrings.js';

export const SOW_OFFSETS = Array.from({ length: 26 }, (_, i) => -20 + 2 * i);

export const clamp01 = (v) => Math.min(1, Math.max(0, v));

/** Mediana sin mutar la entrada; null si está vacía. */
export function median(values) {
  if (values.length === 0) return null;
  const s = [...values].sort((a, b) => a - b);
  const h = s.length >> 1;
  return s.length % 2 ? s[h] : (s[h - 1] + s[h]) / 2;
}

/** Fila con la mayor mediana; en empate gana el desfase más cercano a 0 (y luego el más temprano). */
export function pickBestOffset(rows) {
  const EPS = 1e-12;
  let best = null;
  for (const r of rows) {
    if (r.median == null || !Number.isFinite(r.median)) continue;
    if (!best || r.median > best.median + EPS) { best = r; continue; }
    if (Math.abs(r.median - best.median) <= EPS) {
      const a = Math.abs(r.offset), b = Math.abs(best.offset);
      if (a < b || (a === b && r.offset < best.offset)) best = r;
    }
  }
  return best;
}

/** ¿El simulador mantiene el orden del emulador (propuesto > desfase 0)? tol en unidades de waterIndex. */
export function compareRanking(simZero, simBest, tol = 0.001) {
  const d = simBest - simZero;
  if (Math.abs(d) <= tol) return 'tie';
  return d > 0 ? 'agree' : 'disagree';
}

/**
 * Recorta el bundle a cada año agrícola (1 abr → 31 mar). Las features del emulador solo miran dentro
 * del año, y en el recorte buscan fechas en ~365 días en vez de ~9,000: la búsqueda es ~25× más rápida.
 */
export function yearSlices(bundle, et0, years) {
  const n = bundle.dates.length;
  return years.map((year) => {
    const s = bundle.dates.indexOf(`${year}-04-01`);
    const e = bundle.dates.indexOf(`${year + 1}-03-31`) + 1;
    if (s < 0 || e <= s) throw new Error(`yearSlices: agricultural year ${year} is not complete`);
    const sub = { ...bundle };
    for (const [k, v] of Object.entries(bundle)) if (Array.isArray(v) && v.length === n) sub[k] = v.slice(s, e);
    return { year, bundle: sub, et0: et0.slice(s, e) };
  });
}

/** Mediana (entre años) del waterIndex del emulador para cada desfase. predict(x) → [waterIndex, ks, bare]. */
export function emulateOffsets({ slices, crops, predict, management, offsets = SOW_OFFSETS }) {
  const t0 = performance.now();
  const clim = slices.map((s) => climateFeatures(s.bundle, s.year, s.et0));
  const rows = offsets.map((off) => {
    const w = [], doys = [];
    slices.forEach((s, k) => {
      const ph = phenoFeatures(s.bundle, s.year, s.et0, crops, off);
      doys.push(ph[0]);
      w.push(clamp01(predict(encodeFeatures(clim[k], ph, { ...management, sowOffsetDays: off }))[0]));
    });
    return { offset: off, median: median(w), sowDoy: median(doys) };
  });
  return { rows, predictions: offsets.length * slices.length, ms: performance.now() - t0 };
}

/** Mediana del waterIndex del simulador real para un desfase, en los años pedidos. */
export function simulateOffset({ sequence, bundle, et0, crops, years, texture, slopeClass, irrigation, offset }) {
  const t0 = performance.now();
  const res = runSequence({ sequence, bundle, et0, crops, texture, slopeClass, irrigation, sowOffsetDays: offset });
  const ms = performance.now() - t0;
  const want = new Set(years);
  const w = res.filter((r) => want.has(r.year)).map(targetsOf).filter(Boolean).map((x) => x[0]);
  return { median: median(w), n: w.length, ms };
}

/** Busca el mejor desfase con el emulador y lo confirma con el simulador (desfase 0 y propuesto). */
export function findBestSowing({ bundle, et0, slices, crops, sequence, predict, management, offsets = SOW_OFFSETS }) {
  if (sequence.requiresIrrigation && management.irrigation === 'none') return { notApplicable: true };
  const emu = emulateOffsets({ slices, crops, predict, management, offsets });
  const best = pickBestOffset(emu.rows);
  const zero = emu.rows.find((r) => r.offset === 0);
  const years = slices.map((s) => s.year);
  const simArgs = {
    sequence, bundle, et0, crops, years,
    texture: management.texture, slopeClass: management.slopeClass, irrigation: management.irrigation,
  };
  const sim0 = simulateOffset({ ...simArgs, offset: 0 });
  const same = best.offset === 0;
  const simB = same ? sim0 : simulateOffset({ ...simArgs, offset: best.offset });
  return {
    rows: emu.rows, best, zero, years,
    emulator: { zero: zero.median, best: best.median, ms: emu.ms, dates: offsets.length, predictions: emu.predictions },
    simulator: { zero: sim0.median, best: simB.median, ms: sim0.ms + (same ? 0 : simB.ms), dates: same ? 1 : 2, n: sim0.n },
    verdict: same ? 'same' : compareRanking(sim0.median, simB.median),
  };
}

// ---------------------------------------------------------------- dibujo (solo navegador)

const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

export function shiftLong(lang, off) {
  return off > 0 ? t(lang, 'sowShiftAfter', { d: off }) : t(lang, 'sowShiftBefore', { d: -off });
}
export function shiftShort(lang, off) {
  if (off === 0) return '0 d';
  return off > 0 ? t(lang, 'sowShiftShortAfter', { d: off }) : t(lang, 'sowShiftShortBefore', { d: -off });
}
function doyDate(lang, doy) {
  return new Intl.DateTimeFormat(locale(lang), { day: 'numeric', month: 'long', timeZone: 'UTC' })
    .format(new Date(Date.UTC(2001, 0, Math.round(doy))));
}
const ms = (lang, v) => fmtNumber(lang, v, v < 10 ? 1 : 0);

/** Propuesta + tabla lado a lado emulador/simulador con sus tiempos + veredicto. */
export function renderSowingResult(el, r, { lang, modelShort, indexNote = '' }) {
  const W = (v) => fmtAbs(lang, 'waterIndex', v);
  const same = r.best.offset === 0;
  const headline = same ? t(lang, 'sowKeep') : t(lang, 'sowProposal', { shift: `<strong>${esc(shiftLong(lang, r.best.offset))}</strong>` });
  const dates = same
    ? t(lang, 'sowDates0', { date0: doyDate(lang, r.zero.sowDoy) })
    : t(lang, 'sowDates', { date: doyDate(lang, r.best.sowDoy), date0: doyDate(lang, r.zero.sowDoy) });
  const emuDelta = same ? '' : ` <span class="delta">${esc(fmtDiff(lang, 'waterIndex', r.emulator.best - r.emulator.zero))}</span>`;
  const simDelta = same ? '' : ` <span class="delta">${esc(fmtDiff(lang, 'waterIndex', r.simulator.best - r.simulator.zero))}</span>`;
  const bestCol = same ? '' : `<th scope="col">${esc(t(lang, 'sowColBest', { shift: shiftShort(lang, r.best.offset) }))}</th>`;
  const time = (total, n) => `<span class="sub time">${esc(t(lang, 'sowTime', { ms: ms(lang, total), n, per: fmtNumber(lang, total / n, 2) }))}</span>`;
  const verdicts = {
    agree: ['ok', '✓', t(lang, 'sowAgree', { delta: fmtDiff(lang, 'waterIndex', r.simulator.best - r.simulator.zero) })],
    disagree: ['warn', '⚠', t(lang, 'sowDisagree', { zero: W(r.simulator.zero), best: W(r.simulator.best) })],
    tie: ['tie', '≈', t(lang, 'sowTie', { zero: W(r.simulator.zero), best: W(r.simulator.best) })],
    same: ['tie', '=', t(lang, 'sowSame', { zero: W(r.simulator.zero) })],
  };
  const [cls, icon, text] = verdicts[r.verdict];
  el.innerHTML = `
    <p class="sow-headline">${headline}</p>
    <p class="sow-dates">${esc(dates)}</p>
    <div class="table-scroll">
      <table class="sow-table" data-testid="sow-table">
        <caption>${esc(t(lang, 'sowCaption', { n: r.years.length, first: r.years[0], last: r.years.at(-1) }))}</caption>
        <thead><tr><td></td><th scope="col">${esc(t(lang, 'sowColZero'))}</th>${bestCol}</tr></thead>
        <tbody>
          <tr data-row="emulator"><th scope="row">${esc(t(lang, 'sowRowEmu', { model: modelShort }))}${time(r.emulator.ms, r.emulator.dates)}</th>
            <td class="num">${esc(W(r.emulator.zero))}</td>${same ? '' : `<td class="num">${esc(W(r.emulator.best))}${emuDelta}</td>`}</tr>
          <tr data-row="simulator"><th scope="row">${esc(t(lang, 'sowRowSim'))}${time(r.simulator.ms, r.simulator.dates)}</th>
            <td class="num">${esc(W(r.simulator.zero))}</td>${same ? '' : `<td class="num">${esc(W(r.simulator.best))}${simDelta}</td>`}</tr>
        </tbody>
      </table>
    </div>
    ${indexNote ? `<p class="sow-note">${esc(indexNote)}</p>` : ''}
    <p class="verdict verdict-${cls}" data-verdict="${r.verdict}"><span class="verdict-icon" aria-hidden="true">${icon}</span> ${esc(text)}</p>`;
}

const SVG_NS = 'http://www.w3.org/2000/svg';

/** Curva del emulador (mediana por desfase) + las dos revisiones del simulador, con cursor y tooltip. */
export function renderSowingChart(el, r, { lang, modelShort }) {
  const width = Math.max(280, Math.round(el.clientWidth || 640));
  const height = width < 480 ? 220 : 260;
  const m = { l: 46, r: 14, t: 26, b: 42 };
  const iw = width - m.l - m.r, ih = height - m.t - m.b;
  const xs = r.rows.map((d) => d.offset);
  const pts = [...r.rows.map((d) => d.median), r.simulator.zero, r.simulator.best].map((v) => v * 100);
  let lo = Math.min(...pts), hi = Math.max(...pts);
  const pad = Math.max(0.5, (hi - lo) * 0.15);
  lo -= pad; hi += pad;
  const step = [0.5, 1, 2, 5, 10, 20].find((s) => (hi - lo) / s <= 5) ?? 20;
  lo = Math.max(0, Math.floor(lo / step) * step);
  hi = Math.min(100, Math.ceil(hi / step) * step);
  if (hi <= lo) hi = lo + step;
  const x = (o) => m.l + ((o - xs[0]) / (xs.at(-1) - xs[0])) * iw;
  const y = (v) => m.t + (1 - (v * 100 - lo) / (hi - lo)) * ih;
  const pct = (v) => `${fmtNumber(lang, v, step < 1 ? 1 : 0)}%`;

  const yTicks = [];
  for (let v = lo; v <= hi + 1e-9; v += step) yTicks.push(v);
  const xTicks = [-20, -10, 0, 10, 20, 30];
  const line = r.rows.map((d, i) => `${i ? 'L' : 'M'}${x(d.offset).toFixed(1)},${y(d.median).toFixed(1)}`).join('');
  const diamond = (cx, cy, s = 6) => `M${cx},${cy - s}L${cx + s},${cy}L${cx},${cy + s}L${cx - s},${cy}Z`;
  const same = r.best.offset === 0;

  el.innerHTML = `
    <div class="chart-legend">
      <span class="key"><span class="swatch-line" aria-hidden="true"></span>${esc(t(lang, 'chartEmu', { model: modelShort, n: r.years.length }))}</span>
      <span class="key"><svg width="14" height="14" aria-hidden="true"><path d="${diamond(7, 7, 5)}" class="sim-mark"/></svg>${esc(t(lang, 'chartSim'))}</span>
    </div>
    <div class="chart-wrap">
      <svg xmlns="${SVG_NS}" width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" role="img" aria-label="${esc(t(lang, 'chartAria'))}">
        <g class="grid">${yTicks.map((v) => `<line x1="${m.l}" x2="${m.l + iw}" y1="${y(v / 100)}" y2="${y(v / 100)}"/>`).join('')}</g>
        <g class="axis-labels">
          ${yTicks.map((v) => `<text x="${m.l - 8}" y="${y(v / 100) + 4}" text-anchor="end">${pct(v)}</text>`).join('')}
          ${xTicks.map((o) => `<text x="${x(o)}" y="${m.t + ih + 18}" text-anchor="middle">${o > 0 ? '+' : o < 0 ? '−' : ''}${Math.abs(o)}</text>`).join('')}
          <text x="${m.l + iw / 2}" y="${height - 4}" text-anchor="middle" class="axis-title">${esc(t(lang, 'chartXAxis'))}</text>
        </g>
        <line class="onset" x1="${x(0)}" x2="${x(0)}" y1="${m.t}" y2="${m.t + ih}"/>
        <text class="mark-label" x="${x(0) + 4}" y="${m.t - 8}" text-anchor="${x(0) > width - 110 ? 'end' : 'start'}">${esc(t(lang, 'chartOnset'))}</text>
        ${same ? '' : `<text class="mark-label strong" x="${x(r.best.offset)}" y="${m.t - 8}" text-anchor="${x(r.best.offset) > width - 70 ? 'end' : 'middle'}">${esc(t(lang, 'chartProposed'))}</text>`}
        <path class="emu-line" d="${line}"/>
        <circle class="emu-point" cx="${x(0)}" cy="${y(r.emulator.zero)}" r="5"/>
        ${same ? '' : `<circle class="emu-point" cx="${x(r.best.offset)}" cy="${y(r.emulator.best)}" r="5"/>`}
        <path class="sim-mark" d="${diamond(x(0), y(r.simulator.zero))}"/>
        ${same ? '' : `<path class="sim-mark" d="${diamond(x(r.best.offset), y(r.simulator.best))}"/>`}
        <g class="hover" visibility="hidden"><line class="crosshair" y1="${m.t}" y2="${m.t + ih}"/><circle class="hover-dot" r="5"/></g>
        <rect class="hit" x="${m.l}" y="${m.t}" width="${iw}" height="${ih}" fill="transparent"/>
      </svg>
      <div class="chart-tip" hidden></div>
    </div>`;

  const svg = el.querySelector('.chart-wrap svg');
  const hover = svg.querySelector('.hover');
  const tip = el.querySelector('.chart-tip');
  const onMove = (ev) => {
    const box = svg.getBoundingClientRect();
    const px = ((ev.clientX - box.left) / box.width) * width;
    let k = 0;
    xs.forEach((o, i) => { if (Math.abs(x(o) - px) < Math.abs(x(xs[k]) - px)) k = i; });
    const d = r.rows[k];
    hover.setAttribute('visibility', 'visible');
    hover.querySelector('line').setAttribute('x1', x(d.offset));
    hover.querySelector('line').setAttribute('x2', x(d.offset));
    hover.querySelector('circle').setAttribute('cx', x(d.offset));
    hover.querySelector('circle').setAttribute('cy', y(d.median));
    const simV = d.offset === 0 ? r.simulator.zero : d.offset === r.best.offset ? r.simulator.best : null;
    tip.innerHTML = `<strong>${esc(shiftShort(lang, d.offset))}</strong> · ${esc(modelShort)} ${esc(fmtAbs(lang, 'waterIndex', d.median))}`
      + (simV == null ? '' : `<br>${esc(t(lang, 'sowRowSim'))} ${esc(fmtAbs(lang, 'waterIndex', simV))}`);
    tip.hidden = false;
    const left = (x(d.offset) / width) * box.width;
    tip.style.left = `${Math.min(Math.max(left, 70), box.width - 70)}px`;
    tip.style.top = `${(y(d.median) / height) * box.height - 12}px`;
  };
  const onLeave = () => { hover.setAttribute('visibility', 'hidden'); tip.hidden = true; };
  const hit = svg.querySelector('.hit');
  hit.addEventListener('pointermove', onMove);
  hit.addEventListener('pointerdown', onMove);
  hit.addEventListener('pointerleave', onLeave);
}
