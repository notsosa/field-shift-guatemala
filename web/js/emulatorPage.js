// Página del emulador: comparación MLP vs ELM, mapa del Corredor Seco y mejor fecha de siembra.
import { mlpPredict, elmPredict, trainELM, TARGET_NAMES } from './model/emulator.js';
import { loadCrops } from './model/crops.js';
import { computeEt0Series, agriculturalYears } from './model/simulate.js';
import { t, fmtNumber, fmtDiff, fmtError, locale } from './ui/emulatorStrings.js';
import {
  computeMapValues, createEmulatorMap, paintMap, renderLegend, accuracyText, bandText, renderMapTable, scaleLimit, summarize,
  foodCropIds, compareFoodCrops, diffBand, cellGroups,
} from './ui/emulatorMap.js';
import { SOW_OFFSETS, yearSlices, findBestSowing, renderSowingResult, renderSowingChart } from './ui/bestSowing.js';

const PILOTS = ['chiquimula', 'jutiapa', 'sanmartin'];
const HIGH_M = 1500; // arriba de esta elevación aparece el aviso de altitud (spec §6, paso 3)
/** Clave de emulator_eval.json con los puntajes del modelo que usa la página ('elm' = la ELM entrenada aquí). */
const evalKey = (model) => (model === 'elm' ? 'elmBrowser' : 'mlp');
const ALTERNATIVES = ['proteger', 'extra_secano', 'extra_riego'];
const SEQUENCE_IDS = ['actual', ...ALTERNATIVES];

const $ = (id) => document.getElementById(id);
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

const state = {
  lang: new URLSearchParams(location.search).get('lang') === 'es' ? 'es' : 'en',
  data: null,
  elm: { status: 'idle', model: null, seconds: null, error: null, startedAt: 0, promise: null, timer: 0 },
  map: { ctrl: null, last: null, token: 0 },
  sow: { sites: new Map(), last: null, token: 0 },
};
const tr = (key, vars) => t(state.lang, key, vars);
const num = (x, d = 0) => fmtNumber(state.lang, x, d);

/** Deja pintar el estado "calculando…" antes de un cálculo síncrono (con respaldo si la pestaña está oculta). */
function nextPaint() {
  return new Promise((resolve) => {
    let done = false;
    const go = () => { if (!done) { done = true; setTimeout(resolve, 0); } };
    requestAnimationFrame(go);
    setTimeout(go, 60);
  });
}

async function fetchJson(path) {
  const res = await fetch(path);
  if (!res.ok) throw new Error(`${path}: HTTP ${res.status}`);
  return res.json();
}

function leafletReady() {
  if (window.L) return Promise.resolve();
  return new Promise((resolve, reject) => {
    window.addEventListener('load', () => (window.L ? resolve() : reject(new Error('Leaflet did not load'))), { once: true });
  });
}

// ------------------------------------------------------------------ idioma y textos

function applyStatic() {
  document.documentElement.lang = state.lang;
  document.title = tr('docTitle');
  for (const el of document.querySelectorAll('[data-i18n]')) el.textContent = tr(el.dataset.i18n);
  $('lang-toggle').setAttribute('aria-label', tr('langToggleAria'));
  $('map').setAttribute('aria-label', tr('navMap'));
}

const listOf = (names) => new Intl.ListFormat(locale(state.lang), { type: 'conjunction' }).format(names);

const pointById = (id) => state.data.grid.points.find((p) => p.id === id);
const cropName = (id) => state.data.crops.get(id).name[state.lang] ?? state.data.crops.get(id).name.en;
/** "maize and beans (ICTA Ligero)" / "maize only" (minúscula inicial, lista del idioma). */
function cropList(ids) {
  const names = ids.map((id) => { const n = cropName(id); return n.charAt(0).toLocaleLowerCase(locale(state.lang)) + n.slice(1); });
  if (names.length === 1) return tr('cropsOnly', { crop: names[0] });
  return new Intl.ListFormat(locale(state.lang), { type: 'conjunction' }).format(names);
}
const seqName = (id) => state.data.sequences[id].name[state.lang] ?? state.data.sequences[id].name.en;

function fillOptions(select, items) {
  const keep = select.value;
  select.innerHTML = items.map(([v, label]) => `<option value="${esc(v)}">${esc(label)}</option>`).join('');
  if (items.some(([v]) => v === keep)) select.value = keep;
}

function renderDataTexts() {
  const { grid, eval: E } = state.data;
  fillOptions($('map-alternative'), ALTERNATIVES.map((id) => [id, seqName(id)]));
  fillOptions($('sow-sequence'), SEQUENCE_IDS.map((id) => [id, seqName(id)]));
  fillOptions($('sow-pilot'), PILOTS.map((id) => [id, pointById(id).name]));
  const heldOut = grid.points.filter((p) => p.heldOut).map((p) => p.name).join(', ');
  $('compare-intro').textContent = tr('cmpIntro', { nIn: num(state.data.mlp.architecture[0]), nTrain: num(E.nTrain), nTest: num(E.nTest) });
  const currentChain = state.data.sequences.actual.phases.map((ph) => cropName(ph.cropId)).join(' → ');
  $('map-intro').textContent = tr('mapIntro', { current: currentChain });
  const e2e = E.endToEnd?.speedupVsSimulator;
  $('hero-stats').innerHTML = [
    [`${num(E.mlp.speedupVsSimulator)}×`, tr('statSpeed'), e2e?.mlp ? tr('statSpeedSub', { x: num(e2e.mlp, e2e.mlp < 10 ? 1 : 0) }) : ''],
    [num(E.bySplit.testYears.mlp.r2[0], 2), tr('statR2'), tr('statR2Sub', { v: num(E.mlp.r2[0], 2) })],
    [num(E.nTrain + E.nTest), tr('statRuns')],
  ].map(([v, label, sub]) => `<div class="stat"><span class="stat-value">${esc(v)}</span><span class="stat-label">${esc(label)}</span>${sub ? `<span class="stat-sub">${esc(sub)}</span>` : ''}</div>`).join('');
  $('sow-intro').textContent = tr('sowIntro', { n: SOW_OFFSETS.length });
  $('foot-simulator').textContent = tr('footSimulator', { n: grid.years.length, first: grid.years[0], last: grid.years.at(-1) });
  // Municipios de prueba que comparten celda de temperatura con alguno de entrenamiento.
  const held = grid.points.filter((p) => p.heldOut);
  const trainIds = new Set(grid.points.filter((p) => !p.heldOut).map((p) => p.id));
  const kShared = held.filter((p) => (p.weatherMates ?? []).some((id) => trainIds.has(id))).length;
  const shared = kShared === 0 ? '' : tr(kShared === held.length ? 'footSharedAll' : 'footSharedSome', { k: kShared, n: held.length });
  $('foot-training').textContent = tr('footTraining', {
    nAll: num(E.nTrain + E.nTest), nPoints: grid.points.length, nYears: grid.years.length, nOffsets: grid.offsets.length, heldOut, nHeld: held.length, shared,
  });
  // Nota del mapa: celdas de clima compartidas, celdas altas e insumos idénticos.
  const cg = cellGroups(grid.points, HIGH_M);
  const nameOf = (id) => pointById(id).name;
  $('map-cells').textContent = cg.nShared === 0 ? '' : [
    tr('mapCellsNote', { k: cg.nShared, n: grid.points.length }),
    ...cg.high.map((g) => tr('mapCellsHigh', { names: listOf(g.ids.map(nameOf)), elev: num(g.elevation) })),
    ...cg.identical.map((ids) => tr('mapCellsIdentical', { names: listOf(ids.map(nameOf)) })),
  ].join(' ');
  $('map-cells').hidden = cg.nShared === 0;
}

function setLang(lang) {
  state.lang = lang;
  const url = new URL(location.href);
  if (lang === 'es') url.searchParams.set('lang', 'es'); else url.searchParams.delete('lang');
  history.replaceState(null, '', url);
  applyStatic();
  if (!state.data) return;
  renderDataTexts();
  renderCompare();
  repaintMap();
  rerenderSowing();
}

// ------------------------------------------------------------------ ELM en el navegador

/** La ELM de la página: la recomendación del barrido de validación (hidden <= 600), igual que elmBrowser en evaluate.mjs. */
function elmOptions() {
  const { browserElmRecommendation: rec } = state.data.eval;
  return { hidden: rec.hidden, inputScale: rec.inputScale ?? 1, lambda: rec.lambda, seed: rec.seed ?? 42 };
}

function trainInWorker(X, Y, options) {
  return new Promise((resolve, reject) => {
    let worker;
    try {
      worker = new Worker(new URL('./elmWorker.js', import.meta.url), { type: 'module' });
    } catch (err) {
      reject(Object.assign(new Error(String(err?.message ?? err)), { fallback: true }));
      return;
    }
    worker.onmessage = ({ data }) => {
      worker.terminate();
      if (data.ok) resolve(data); else reject(new Error(data.error));
    };
    worker.onerror = (ev) => {
      ev.preventDefault();
      worker.terminate();
      reject(Object.assign(new Error(ev.message || 'worker error'), { fallback: true }));
    };
    worker.postMessage({ X, Y, options });
  });
}

async function trainOnMainThread(X, Y, options) {
  await nextPaint();
  const t0 = performance.now();
  const model = trainELM(X, Y, options);
  return { model, seconds: (performance.now() - t0) / 1000 };
}

/** Entrena la ELM una sola vez (bajo pedido) y devuelve la misma promesa a quien la pida después. */
function ensureElm() {
  const elm = state.elm;
  if (elm.status === 'ready') return Promise.resolve(elm.model);
  if (elm.promise) return elm.promise;
  const { X, Y } = state.data.subset;
  const options = elmOptions();
  elm.status = 'training';
  elm.error = null;
  elm.startedAt = performance.now();
  elm.timer = setInterval(renderElmCell, 100);
  renderElmCell();
  elm.promise = trainInWorker(X, Y, options)
    .catch((err) => (err.fallback ? trainOnMainThread(X, Y, options) : Promise.reject(err)))
    .then(({ model, seconds }) => {
      Object.assign(elm, { status: 'ready', model, seconds });
      return model;
    }, (err) => {
      Object.assign(elm, { status: 'error', error: String(err?.message ?? err), promise: null });
      throw err;
    })
    .finally(() => {
      clearInterval(elm.timer);
      renderElmCell();
    });
  return elm.promise;
}

function renderElmCell() {
  const cell = $('elm-cell');
  if (!cell) return;
  const elm = state.elm;
  cell.dataset.state = elm.status;
  if (elm.status === 'idle' || elm.status === 'error') {
    cell.innerHTML = `${elm.status === 'error' ? `<span class="error">${esc(tr('elmFailed', { msg: elm.error }))}</span>` : ''}
      <button type="button" class="btn" id="elm-train">${esc(tr('elmTrainBtn'))}</button>`;
    $('elm-train').addEventListener('click', () => ensureElm().catch(() => {}));
  } else if (elm.status === 'training') {
    const s = (performance.now() - elm.startedAt) / 1000;
    cell.innerHTML = `<span class="training"><span class="spinner" aria-hidden="true"></span><span>${esc(tr('elmTraining', { s: num(s, 1) }))}</span></span>`;
  } else {
    const { hidden } = elmOptions();
    cell.innerHTML = `<span id="elm-time" class="elm-time" data-seconds="${elm.seconds.toFixed(3)}">${esc(tr('elmTrained', { s: num(elm.seconds, 2) }))}</span>
      <span class="sub">${esc(tr('elmTrainedDetail', { hidden: num(hidden), rows: num(state.data.subset.X.length) }))}</span>`;
  }
}

// ------------------------------------------------------------------ comparación MLP vs ELM

/** Dónde se entrenó la MLP: "PyTorch, <GPU> (CUDA) · same training on CPU: Y s" o "PyTorch (compiled), CPU". */
function mlpTrainLabel(m) {
  if (m.trainDevice !== 'cuda') return tr('cmpMlpTrain');
  const gpu = m.trainDeviceName ?? 'GPU';
  return m.trainSecondsCpu != null ? tr('cmpMlpTrainCuda', { gpu, cpu: num(m.trainSecondsCpu, 1) }) : tr('cmpMlpTrainCudaOnly', { gpu });
}

function renderCompare() {
  const { eval: E, mlp } = state.data;
  const ty = E.bySplit.testYears;
  const lowerWins = (a, b) => [a <= b, b <= a];
  const higherWins = (a, b) => [a >= b, b >= a];
  const pair = (a, b, fmt, wins) => {
    const [wa, wb] = wins(a, b);
    return `<td class="num${wa ? ' win' : ''}">${fmt(a, 'mlp')}</td><td class="num${wb ? ' win' : ''}">${fmt(b, 'elm')}</td>`;
  };
  const r2 = (k, i) => {
    const o = k === 'mlp' ? 'elm' : 'mlp';
    const a = E[k].r2[i], b = ty[k].r2[i];
    return `<td class="num r2"><span class="${a >= E[o].r2[i] ? 'win' : ''}">${num(a, 3)}</span><span class="sep" aria-hidden="true"> · </span><span class="${b >= ty[o].r2[i] ? 'win' : ''}">${num(b, 3)}</span></td>`;
  };
  const row = (labelKey, cells, cls = '', subKey = '') => `<tr${cls ? ` class="${cls}"` : ''}><th scope="row">${esc(tr(labelKey))}${subKey ? `<span class="sub">${esc(tr(subKey))}</span>` : ''}</th>${cells}</tr>`;
  $('cmp-table').innerHTML = `
    <thead><tr><td></td><th scope="col">MLP<span class="sub">${esc(tr('cmpColMlp'))}</span></th><th scope="col">ELM<span class="sub">${esc(tr('cmpColElm'))}</span></th></tr></thead>
    <tbody>
      ${row('cmpRowHow', `<td>${esc(tr('cmpMlpHow', { arch: mlp.architecture.join('→') }))}</td><td>${esc(tr('cmpElmHow', { hidden: num(E.elmConfig.hidden), scale: String(E.elmConfig.inputScale ?? 1), lambda: String(E.elmConfig.lambda) }))}</td>`)}
      ${row('cmpRowParams', `<td class="num">${num(E.mlp.params)}</td><td class="num">${num(E.elm.params)}</td>`)}
      <tr class="group"><th scope="rowgroup" colspan="3">${esc(tr('cmpRowR2'))} <span class="sub">${esc(tr('cmpR2Legend'))}</span></th></tr>
      ${TARGET_NAMES.map((id, i) => `<tr class="r2-row"><th scope="row">${esc(tr(`target_${id}`))}</th>${r2('mlp', i)}${r2('elm', i)}</tr>`).join('')}
      ${row('cmpRowTrain', ['mlp', 'elm'].map((k) => `<td class="num">${num(E[k].trainSeconds, 1)} s<span class="sub">${esc(k === 'mlp' ? mlpTrainLabel(E.mlp) : tr('cmpElmTrain'))}</span></td>`).join(''), 'sep-top', 'cmpRowTrainSub')}
      ${row('cmpRowBrowser', `<td class="muted">${esc(tr('cmpMlpBrowser'))}</td><td id="elm-cell" class="elm-cell"></td>`)}
      ${row('cmpRowMemory', pair(E.mlp.trainMemoryAnalyticMB, E.elm.trainMemoryAnalyticMB, (v) => `${num(v, v < 1 ? 2 : 1)} MB`, lowerWins))}
      ${row('cmpRowPredict', pair(E.mlp.predictMicros, E.elm.predictMicros, (v) => `${num(v, 1)} µs`, lowerWins))}
      ${row('cmpRowSpeedup', pair(E.mlp.speedupVsSimulator, E.elm.speedupVsSimulator, (v) => esc(tr('cmpSpeedup', { x: num(v, v < 10 ? 1 : 0) })), higherWins), '', 'cmpRowSpeedupSub')}
    </tbody>`;
  const { hidden: hb } = elmOptions();
  const B = E.elmBrowser;
  const r2s = (a) => a.map((v) => num(v, 2)).join(' · ');
  const b = E.baseline.r2;
  const e2e = E.endToEnd?.speedupVsSimulator;
  const sd = E.stressDetection;
  const f1 = (k) => (sd?.[k]?.f1 == null ? '—' : num(sd[k].f1, 2));
  $('cmp-notes').innerHTML = [
    tr('cmpNoteR2', { nTest: num(E.nTest) }),
    tr('cmpNoteBaseline', { a: num(b[0], 2), b: num(b[1], 2), c: num(b[2], 2) }),
    e2e ? tr('cmpNoteSpeed', { us: num(E.simulatorMicrosPerYear), e2eMlp: num(e2e.mlp, 0), e2eElm: num(e2e.elm, 0) }) : '',
    tr('cmpNoteTrain'),
    sd ? tr('cmpNoteStress', { base: `${num(sd.baseRate * 100, 1)}%`, mlp: f1('mlp'), elm: f1('elm'), elmB: f1('elmBrowser') }) : '',
    tr(B ? 'elmBrowserNote' : 'elmBrowserNoteShort', {
      hb: num(hb), hn: E.elmConfig?.hidden != null ? num(E.elmConfig.hidden) : '—', rb: num(state.data.subset.X.length),
      rn: E.elmConfig?.nFit != null ? num(E.elmConfig.nFit) : '—',
      r2: B ? r2s(B.r2) : '—', r2y: B ? r2s(B.bySplit.testYears.r2) : '—',
    }),
  ].filter(Boolean).map((s) => `<p>${esc(s)}</p>`).join('');
  renderElmCell();
}

// ------------------------------------------------------------------ mapa

const predictor = (model) => (model === 'elm'
  ? (x) => elmPredict(state.elm.model, x)
  : (x) => mlpPredict(state.data.mlp, x));

function mapState() {
  return {
    alternative: $('map-alternative').value, target: $('map-target').value, model: $('map-model').value,
    irrigation: $('map-irrigation').value, texture: $('map-texture').value, slopeClass: $('map-slope').value,
  };
}

async function updateMap() {
  const s = mapState();
  const token = ++state.map.token;
  const section = $('map-section');
  if (state.data.sequences[s.alternative].requiresIrrigation && s.irrigation === 'none') {
    state.map.last = { s, values: null };
    repaintMap();
    return;
  }
  if (s.model === 'elm' && state.elm.status !== 'ready') {
    section.dataset.state = 'training';
    $('map-status').textContent = tr('mapTrainingElm');
    try { await ensureElm(); } catch (err) {
      $('map-status').textContent = tr('elmFailed', { msg: err.message });
      section.dataset.state = 'error';
      return;
    }
    if (token !== state.map.token) return;
  }
  const targetIdx = TARGET_NAMES.indexOf(s.target);
  const r = computeMapValues({
    grid: state.data.grid, predict: predictor(s.model), alternative: s.alternative, targetIdx,
    texture: s.texture, slopeClass: s.slopeClass, irrigation: s.irrigation,
  });
  state.map.last = { s, targetIdx, ...r };
  repaintMap();
}

function repaintMap() {
  const last = state.map.last;
  if (!last) return;
  const { lang } = state;
  const { s } = last;
  const points = state.data.grid.points;
  const section = $('map-section');
  if (!last.values) {
    paintMap(state.map.ctrl, points, null, { lang, targetId: s.target, limit: 1 });
    renderLegend($('map-legend'), { lang, targetId: s.target, limit: scaleLimit([], s.target) });
    $('map-status').textContent = tr('mapNeedsIrrigation');
    $('map-summary').textContent = '';
    $('map-timing').textContent = '';
    $('map-table').innerHTML = '';
    $('map-note').hidden = true;
    section.dataset.state = 'na';
    return;
  }
  // waterIndex promedia los cultivos de comida de cada rotación: si no son los mismos, la comparación no es pareja.
  const { sequences, crops } = state.data;
  const food = compareFoodCrops(sequences[s.alternative], sequences.actual, crops);
  const likeForLike = s.target !== 'waterIndex' || food.same;
  const note = $('map-note');
  note.hidden = likeForLike;
  note.textContent = likeForLike ? '' : tr('noteNotLike', { alt: seqName(s.alternative), altCrops: cropList(food.alt), curCrops: cropList(food.current) });
  // "Casi igual" = error medido de la diferencia (alternativa − actual) de este modelo, alternativa y objetivo.
  const key = evalKey(s.model);
  const band = diffBand(state.data.eval, key, s.alternative, s.target);
  const limit = scaleLimit(last.values, s.target, band.band);
  paintMap(state.map.ctrl, points, last.values, { lang, targetId: s.target, limit });
  renderLegend($('map-legend'), {
    lang, targetId: s.target, limit, likeForLike,
    accuracyText: accuracyText(lang, state.data.eval, key, last.targetIdx),
    bandText: bandText(lang, s.target, band),
    caveatText: s.model === 'elm' ? tr('legendElmCaveat', { hb: num(elmOptions().hidden), rb: num(state.data.subset.X.length) }) : '',
  });
  const sm = summarize(last.values, s.target, band.band);
  $('map-summary').innerHTML = [
    esc(tr(likeForLike ? 'mapSummary' : 'mapSummaryIndex', { better: sm.better, same: sm.same, worse: sm.worse, n: sm.n })),
    sm.top ? esc(tr(likeForLike ? 'mapGain' : 'mapHighest', { name: sm.top.point.name, value: fmtDiff(lang, s.target, sm.top.median) })) : '',
    sm.bottom ? esc(tr(likeForLike ? 'mapLoss' : 'mapLowest', { name: sm.bottom.point.name, value: fmtDiff(lang, s.target, sm.bottom.median) })) : '',
  ].filter(Boolean).join(' ');
  $('map-timing').textContent = tr('mapTiming', { n: num(last.predictions), ms: num(last.ms, 1) });
  renderMapTable($('map-table'), sm, { lang, targetId: s.target });
  $('map-status').textContent = '';
  section.dataset.state = 'ready';
}

// ------------------------------------------------------------------ mejor fecha de siembra

function sowState() {
  return {
    pilot: $('sow-pilot').value, sequence: $('sow-sequence').value, model: $('sow-model').value,
    irrigation: $('sow-irrigation').value, texture: $('sow-texture').value, slopeClass: $('sow-slope').value,
  };
}

async function loadSite(id) {
  if (state.sow.sites.has(id)) return state.sow.sites.get(id);
  const bundle = await fetchJson(`data/snapshots/${id}.json`);
  const et0 = computeEt0Series(bundle);
  const invalid = new Set(bundle.invalidYears ?? []);
  const years = agriculturalYears(bundle.dates).map((a) => a.year).filter((y) => !invalid.has(y));
  const site = { bundle, et0, slices: yearSlices(bundle, et0, years) };
  state.sow.sites.set(id, site);
  return site;
}

async function runSowing() {
  const token = ++state.sow.token;
  const s = sowState();
  const section = $('sowing');
  const status = $('sow-status');
  const sequence = state.data.sequences[s.sequence];
  if (sequence.requiresIrrigation && s.irrigation === 'none') {
    state.sow.last = { s, result: { notApplicable: true } };
    rerenderSowing();
    return;
  }
  section.dataset.state = 'working';
  status.textContent = tr('sowLoadingSite', { site: pointById(s.pilot).name });
  let site;
  try { site = await loadSite(s.pilot); } catch (err) {
    status.textContent = tr('loadError', { msg: err.message });
    section.dataset.state = 'error';
    return;
  }
  if (token !== state.sow.token) return;
  if (s.model === 'elm' && state.elm.status !== 'ready') {
    status.textContent = tr('mapTrainingElm');
    try { await ensureElm(); } catch (err) {
      status.textContent = tr('elmFailed', { msg: err.message });
      section.dataset.state = 'error';
      return;
    }
    if (token !== state.sow.token) return;
  }
  status.textContent = tr('sowWorking', { n: SOW_OFFSETS.length });
  await nextPaint();
  if (token !== state.sow.token) return;
  const result = findBestSowing({
    bundle: site.bundle, et0: site.et0, slices: site.slices, crops: state.data.crops, sequence,
    predict: predictor(s.model),
    management: { texture: s.texture, slopeClass: s.slopeClass, irrigation: s.irrigation, sequenceId: s.sequence },
  });
  state.sow.last = { s, result };
  rerenderSowing();
}

function rerenderSowing() {
  const last = state.sow.last;
  if (!last) return;
  const section = $('sowing');
  if (last.result.notApplicable) {
    $('sow-status').textContent = tr('sowNeedsIrrigation');
    $('sow-result').innerHTML = '';
    $('sow-chart').innerHTML = '';
    section.dataset.state = 'na';
    return;
  }
  $('sow-status').textContent = '';
  const E = state.data.eval;
  const key = evalKey(last.s.model);
  const modelShort = tr(last.s.model === 'elm' ? 'modelShortElm' : 'modelShortMlp');
  const ty = E[key]?.bySplit?.testYears ?? E.bySplit?.testYears?.[key];
  const elev = state.sow.sites.get(last.s.pilot)?.bundle.elevation;
  const sim = last.result.simulator;
  const ctx = {
    lang: state.lang, modelShort,
    cropName: (id) => cropName(id),
    indexNote: tr('sowIndexCrops', { crops: cropList(foodCropIds(state.data.sequences[last.s.sequence], state.data.crops)) }),
    accuracyNote: ty ? tr('sowAccuracy', { model: modelShort, r2: num(ty.r2[0], 2), rmse: fmtError(state.lang, 'waterIndex', ty.rmse[0]).replace(/^±/, '') }) : '',
    altitudeNote: elev > HIGH_M
      ? tr(sim.incompleteYears > 0 ? 'sowAltitude' : 'sowAltitude0', { elev: num(elev), k: sim.incompleteYears, n: sim.n })
      : '',
  };
  renderSowingResult($('sow-result'), last.result, ctx);
  renderSowingChart($('sow-chart'), last.result, ctx);
  section.dataset.state = 'done';
}

// ------------------------------------------------------------------ arranque

async function boot() {
  applyStatic();
  $('lang-toggle').addEventListener('click', () => setLang(state.lang === 'en' ? 'es' : 'en'));
  const boot = $('boot-status');
  boot.textContent = tr('loading');
  try {
    const [mlp, subset, grid, evalJson, cropsJson, sequences] = await Promise.all([
      'emulator_mlp.json', 'emulator_train_subset.json', 'grid_features.json', 'emulator_eval.json', 'crops.json', 'sequences.json',
    ].map((f) => fetchJson(`data/${f}`)));
    state.data = { mlp, subset, grid, eval: evalJson, crops: loadCrops(cropsJson), sequences };
    await leafletReady();
  } catch (err) {
    boot.textContent = tr('loadError', { msg: err.message });
    boot.classList.add('error');
    document.body.dataset.state = 'error';
    return;
  }
  boot.hidden = true;
  renderDataTexts();
  renderCompare();

  state.map.ctrl = createEmulatorMap($('map'), state.data.grid.points);
  for (const id of ['map-alternative', 'map-target', 'map-model', 'map-irrigation', 'map-texture', 'map-slope']) {
    $(id).addEventListener('change', updateMap);
  }
  await updateMap();

  for (const id of ['sow-pilot', 'sow-sequence', 'sow-model', 'sow-irrigation', 'sow-texture', 'sow-slope']) {
    $(id).addEventListener('change', runSowing);
  }
  let resizeTimer = 0;
  window.addEventListener('resize', () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => { if (state.sow.last && !state.sow.last.result.notApplicable) rerenderSowing(); }, 150);
  });
  document.body.dataset.state = 'ready';
  document.body.dataset.readyMs = String(Math.round(performance.now()));
  setTimeout(runSowing, 0);
}

boot();
