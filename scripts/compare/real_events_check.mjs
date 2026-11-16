// Tarea 35, parte 3: ¿el simulador coincide con los eventos de sequía documentados en el Corredor Seco de Guatemala 2001-2024?
// Uso: node scripts/compare/real_events_check.mjs [ruta/eventos-sequia-documentados.json]   -> escribe web/data/real_events_check.json
// La tabla de eventos la compiló otro agente SIN ver salidas del simulador (research_notes/eventos-sequia-documentados.json); aquí no se edita.
//
// REGLAS FIJADAS ANTES DE VER NINGÚN RESULTADO DE ESTA PARTE (no se cambian después):
//  * Unidad = un sitio-año: punto de points.json cuyo departamento nombra el evento × año agrícola × calendario × cultivo.
//    Calendario: primera = siembra en la fecha de la regla de inicio de lluvias; postrera = siembra el 15 de agosto. Evento "ambas" = las dos;
//    cultivo "ambos" = maíz y frijol, cada uno una unidad. Un evento sin departamentos (no se puede ubicar en puntos) no se puntúa y su año queda
//    fuera de los controles de ese calendario. Unidades repetidas por varios eventos se cuentan una vez.
//  * Valor del simulador = relYield de ese cultivo y calendario con la lluvia de la fuente (secano; suelo del sitio en pilotos, franco en los demás);
//    percentil = rango medio entre los años usables de ese sitio, calendario, cultivo y fuente (años con días de lluvia faltantes quedan fuera, no se rellenan).
//  * Acierto = percentil <= 1/3 (peor tercio). Puntaje = 1 - percentil.
//  * Controles: (a) "noEventYears" = los años del archivo, en los mismos puntos, cultivos y calendarios que usan los eventos; (b) "otros años" = todos los demás
//    años 2001-2024 de esos puntos sin ningún evento listado de ese calendario y cultivo (incluidos los sin departamentos).
//  * AUC = Mann-Whitney (empates 1/2) de los puntajes de las unidades de evento contra los de los controles, mezclando calendarios y cultivos.
//  * Regla de elección de fuente: con los eventos 2001-2016 solamente, gana la fuente de mayor AUC; reemplaza a ERA5 solo si lo supera por >= 0.05.
//    Como en 2001-2016 el archivo trae un solo año sin evento (2015 postrera), el AUC de la regla es el que usa los "otros años" como controles (no los noEventYears),
//    y se calcula sobre el soporte común (las unidades evaluables con las tres fuentes), para que las fuentes se comparen sobre las mismas unidades.
//    Después se reportan todas las fuentes en 2017-2024 como comprobación fuera de muestra. No se cambia la fuente por defecto ni se reentrena nada.
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {
  root, SOURCES, YEARS, loadAllCrops, loadPoints, loadSite, soilOfPoint, completeYears, simulateSowing, sowLocalIndex,
  percentile, isHit, auc, chooseRainSource, round, WORST_THIRD, SWITCH_MARGIN,
} from './rain_sources_lib.mjs';

export const DEFAULT_EVENTS = 'C:/Users/velas/OneDrive/Documents/spaceapps_challenge/research_notes/eventos-sequia-documentados.json';
export const CALENDARS = { primera: { when: 'onset', label: 'first cycle, sown at the onset-rule date' }, postrera: { when: '08-15', label: 'second cycle (postrera), sown 15 August' } };
const CROP_ID = { maiz: 'maiz', frijol: 'frijol' };
export const PERIODS = { A: [2001, 2016], B: [2017, 2024] };
export const periodOf = (year) => (year <= PERIODS.A[1] ? 'A' : 'B');

export const normDept = (s) => s.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim();
const calendarsOf = (season) => (season === 'ambas' ? ['primera', 'postrera'] : CALENDARS[season] ? [season] : []);
const cropsOf = (crop) => (crop === 'ambos' ? ['maiz', 'frijol'] : CROP_ID[crop] ? [CROP_ID[crop]] : []);
const unitKey = (u) => `${u.point}|${u.year}|${u.calendar}|${u.crop}`;

/**
 * Del archivo de eventos y los puntos a las unidades.
 * @returns {{eventUnits, noEventUnits, otherUnits, skippedEvents, siteSets}} cada unidad {point, year, calendar, crop, eventIds}
 */
export function buildUnits(file, points) {
  const byDept = new Map();
  for (const p of points) { const k = normDept(p.department); if (!byDept.has(k)) byDept.set(k, []); byDept.get(k).push(p.id); }
  const skippedEvents = [];
  const eventUnits = new Map();
  const eventYearsCal = new Map(); // `${calendar}|${crop}` -> Set de años con algún evento listado (aunque no se pueda ubicar)
  const markYear = (cal, crop, year) => { const k = `${cal}|${crop}`; if (!eventYearsCal.has(k)) eventYearsCal.set(k, new Set()); eventYearsCal.get(k).add(year); };
  file.events.forEach((e, idx) => {
    const id = `E${String(idx + 1).padStart(2, '0')}`;
    const cals = calendarsOf(e.season); const crops = cropsOf(e.crop);
    for (const c of cals) for (const k of crops) markYear(c, k, e.year);
    const pts = [...new Set((e.departments ?? []).flatMap((d) => byDept.get(normDept(d)) ?? []))];
    if (!cals.length || !crops.length) { skippedEvents.push({ id, year: e.year, season: e.season, crop: e.crop, reason: 'season or crop not simulated' }); return; }
    if (!pts.length) { skippedEvents.push({ id, year: e.year, season: e.season, crop: e.crop, reason: 'no department named: cannot be placed on points; its year is kept out of the "other years" controls' }); return; }
    for (const c of cals) for (const k of crops) for (const p of pts) {
      const u = { point: p, year: e.year, calendar: c, crop: k, eventIds: [id] };
      const key = unitKey(u);
      if (eventUnits.has(key)) eventUnits.get(key).eventIds.push(id); else eventUnits.set(key, u);
    }
  });
  // Conjunto de puntos por (calendario, cultivo): los de alguna unidad de evento.
  const siteSets = new Map();
  for (const u of eventUnits.values()) { const k = `${u.calendar}|${u.crop}`; if (!siteSets.has(k)) siteSets.set(k, new Set()); siteSets.get(k).add(u.point); }
  const noEventUnits = new Map();
  for (const n of file.noEventYears) {
    for (const c of calendarsOf(n.season)) for (const k of ['maiz', 'frijol']) for (const p of siteSets.get(`${c}|${k}`) ?? []) {
      const u = { point: p, year: n.year, calendar: c, crop: k, eventIds: [] };
      if (!eventUnits.has(unitKey(u))) noEventUnits.set(unitKey(u), u);
    }
  }
  const otherUnits = new Map();
  for (const [ck, set] of siteSets) {
    const [c, k] = ck.split('|');
    for (const p of set) for (const year of YEARS) {
      if (eventYearsCal.get(ck)?.has(year)) continue;
      const u = { point: p, year, calendar: c, crop: k, eventIds: [] };
      otherUnits.set(unitKey(u), u);
    }
  }
  return { eventUnits: [...eventUnits.values()], noEventUnits: [...noEventUnits.values()], otherUnits: [...otherUnits.values()], skippedEvents, siteSets: Object.fromEntries([...siteSets].map(([k, v]) => [k, [...v]])) };
}

/** Resume un conjunto de unidades evaluadas ({pct, hit, value}): n, aciertos, tasa. */
export function hitSummary(units) {
  const n = units.length; const hits = units.filter((u) => u.hit).length;
  return { n, hits, hitRate: n ? round(hits / n) : null };
}

if (process.argv[1]?.endsWith('real_events_check.mjs')) {
  // --heat (Tarea 36): mismo cálculo con el factor de calor en la floración (maíz); escribe web/data/factors_real_events_check.json y no toca real_events_check.json.
  const HEAT = process.argv.includes('--heat');
  const eventsPath = process.argv.slice(2).find((a) => !a.startsWith('--')) ?? DEFAULT_EVENTS;
  const raw = fs.readFileSync(eventsPath);
  const file = JSON.parse(raw);
  const points = loadPoints();
  const crops = loadAllCrops();
  const U = buildUnits(file, points);
  const pointById = Object.fromEntries(points.map((p) => [p.id, p]));
  const siteCache = {};
  const site = (id) => (siteCache[id] ??= loadSite(id));
  const seriesCache = new Map();
  /** relYield por año (YEARS) de (fuente, punto, cultivo, calendario); null si el año no es usable en esa fuente o no hay fuente para el punto. */
  const series = (src, pid, crop, cal) => {
    const key = `${src}|${pid}|${crop}|${cal}`;
    if (seriesCache.has(key)) return seriesCache.get(key);
    const s = site(pid); const rain = s.rain[src];
    let out = null;
    if (rain) {
      const usable = new Set(completeYears(s.dates, rain)); const soil = soilOfPoint(pointById[pid]);
      out = YEARS.map((y) => (usable.has(y) ? simulateSowing({ bundle: s.bundle, et0: s.et0, rain, crops, soil, year: y, cropId: crop, sowLocal: sowLocalIndex(s.bundle, rain, y, CALENDARS[cal].when), factors: HEAT ? { heat: true } : null }) : null));
    }
    seriesCache.set(key, out);
    return out;
  };
  /** Evalúa una unidad con una fuente: valor, percentil, acierto; null si la fuente no la puede evaluar. */
  const evalUnit = (u, src) => {
    const sr = series(src, u.point, u.crop, u.calendar);
    const r = sr?.[YEARS.indexOf(u.year)];
    if (!r) return null;
    const vals = sr.filter(Boolean).map((x) => x.relYield);
    const pct = percentile(vals, r.relYield);
    return { relYield: round(r.relYield), stressDays: r.stressDays, cycleCompletes: r.cycleCompletes, pct: round(pct, 4), score: 1 - pct, hit: isHit(pct), yearsInRanking: vals.length };
  };

  const groups = { event: U.eventUnits, noEvent: U.noEventUnits, other: U.otherUnits };
  const evald = {}; // group -> unit[] con .by[src]
  for (const [g, list] of Object.entries(groups)) evald[g] = list.map((u) => ({ ...u, by: Object.fromEntries(SOURCES.map((s) => [s, evalUnit(u, s)])) }));
  const common = (u) => SOURCES.every((s) => u.by[s]);

  const sel = (g, src, period, commonOnly) => evald[g].filter((u) => u.by[src] && (period === 'all' || periodOf(u.year) === period) && (!commonOnly || common(u)));
  const aucFor = (src, ctl, period, commonOnly) => {
    const ev = sel('event', src, period, commonOnly).map((u) => u.by[src].score);
    const cs = sel(ctl, src, period, commonOnly).map((u) => u.by[src].score);
    return { auc: auc(ev, cs) == null ? null : round(auc(ev, cs)), nEvents: ev.length, nControls: cs.length };
  };
  const summary = {};
  for (const src of SOURCES) {
    summary[src] = {};
    for (const period of ['A', 'B', 'all']) {
      summary[src][period] = {
        events: hitSummary(sel('event', src, period, false).map((u) => u.by[src])),
        eventsCommonSupport: hitSummary(sel('event', src, period, true).map((u) => u.by[src])),
        noEventYearsFlagged: hitSummary(sel('noEvent', src, period, false).map((u) => u.by[src])),
        otherYearsFlagged: hitSummary(sel('other', src, period, false).map((u) => u.by[src])),
        aucVsNoEventYears: aucFor(src, 'noEvent', period, false),
        aucVsOtherYears: aucFor(src, 'other', period, false),
        aucVsNoEventYearsCommonSupport: aucFor(src, 'noEvent', period, true),
        aucVsOtherYearsCommonSupport: aucFor(src, 'other', period, true),
      };
    }
  }
  const ruleInputA = Object.fromEntries(SOURCES.map((s) => [s, summary[s].A.aucVsOtherYearsCommonSupport.auc]));
  const decision = chooseRainSource(ruleInputA);
  const heldOutB = Object.fromEntries(SOURCES.map((s) => [s, { aucVsOtherYearsCommonSupport: summary[s].B.aucVsOtherYearsCommonSupport, aucVsNoEventYearsCommonSupport: summary[s].B.aucVsNoEventYearsCommonSupport, events: summary[s].B.events, eventsCommonSupport: summary[s].B.eventsCommonSupport }]));

  // Fallos y falsas alarmas por nombre
  const name = (u) => `${pointById[u.point].name} (${pointById[u.point].department}) ${u.year} ${u.calendar} ${u.crop}`;
  const misses = {}; const falseAlarms = {}; const notEvaluable = {};
  for (const src of SOURCES) {
    misses[src] = evald.event.filter((u) => u.by[src] && !u.by[src].hit).map((u) => ({ unit: name(u), events: u.eventIds, relYield: u.by[src].relYield, percentile: u.by[src].pct }));
    falseAlarms[src] = evald.noEvent.filter((u) => u.by[src]?.hit).map((u) => ({ unit: name(u), relYield: u.by[src].relYield, percentile: u.by[src].pct }));
    notEvaluable[src] = { events: evald.event.filter((u) => !u.by[src]).length, noEvent: evald.noEvent.filter((u) => !u.by[src]).length, other: evald.other.filter((u) => !u.by[src]).length };
  }
  // Resumen por evento (sitios evaluables y aciertos por fuente)
  const eventRows = file.events.map((e, idx) => {
    const id = `E${String(idx + 1).padStart(2, '0')}`;
    const us = evald.event.filter((u) => u.eventIds.includes(id));
    return {
      id, year: e.year, season: e.season, crop: e.crop, departments: e.departments, municipalities: e.municipalities ?? [], reported: e.reported, quote: e.quote, source: e.source, confidence: e.confidence,
      scored: us.length > 0, units: us.length,
      bySource: Object.fromEntries(SOURCES.map((s) => { const x = us.filter((u) => u.by[s]); return [s, { evaluable: x.length, hits: x.filter((u) => u.by[s].hit).length, meanRelYield: x.length ? round(x.reduce((a, u) => a + u.by[s].relYield, 0) / x.length) : null, meanPercentile: x.length ? round(x.reduce((a, u) => a + u.by[s].pct, 0) / x.length) : null }]; })),
    };
  });
  const noEventRows = file.noEventYears.map((n) => ({ year: n.year, season: n.season, scope: n.scope, quote: n.quote, source: n.source, confidence: n.confidence }));
  const pointCoverage = Object.fromEntries(SOURCES.map((s) => [s, points.filter((p) => site(p.id).rain[s]).map((p) => p.id)]));
  const out = {
    meta: {
      generated: new Date().toISOString().slice(0, 10),
      eventsFile: { path: 'research_notes/eventos-sequia-documentados.json (outside the repo; compiled by a separate agent without seeing simulator output)', sha256: crypto.createHash('sha256').update(raw).digest('hex'), generated: file.generated, nEvents: file.events.length, nNoEventYears: file.noEventYears.length },
      preRegistered: {
        worstThirdThreshold: WORST_THIRD, switchMargin: SWITCH_MARGIN,
        rule: 'Using only events in 2001-2016, the source with the highest AUC wins; it replaces ERA5 only if its AUC beats ERA5 by at least 0.05. The AUC used by the rule compares event site-years against all other years of the same sites (not the noEventYears, because 2001-2016 contains a single noEventYears entry), on the common support (site-years evaluable with all three sources). 2017-2024 is then reported as the held-out check.',
      },
      method: 'Rainfed FAO-56 water balance with the existing simulator; first cycle = sown at the onset-rule date, second cycle (postrera) = sown 15 August; maize and beans as documented; "ambas" events count both cycles, "ambos" crops count both crops; percentile among the usable years 2001-2024 of the same site, calendar, crop and source; hit = percentile <= 1/3.',
      periods: { A: 'events 2001-2016', B: 'held-out 2017-2024' },
      soil: 'site soil at Chiquimula, Jutiapa and San Martin Jilotepeque; loam at the other points',
      pointsPerSource: Object.fromEntries(SOURCES.map((s) => [s, pointCoverage[s].length])),
      pointsWithSource: pointCoverage,
      siteSets: U.siteSets,
      skippedEvents: U.skippedEvents,
      caveats: ['Events are regional reports (departments, households, area), not plots; every point of a named department counts as one site-year even if the loss was local.', 'The simulator sees only water: no pests, seed, money, heat or soil fertility.', 'Neighbouring points of one event share weather and are not independent; counts are given beside every rate and no significance is claimed.', 'The noEventYears list is short and partly regional (2017 entries do not mention Guatemala); "other years" are not verified as good years.'],
    },
    counts: { eventUnits: U.eventUnits.length, noEventUnits: U.noEventUnits.length, otherUnits: U.otherUnits.length, notEvaluable },
    summary, ruleInputA, decision, heldOutB, misses, falseAlarms, events: eventRows, noEventYears: noEventRows,
    units: { event: evald.event.map((u) => ({ unit: name(u), point: u.point, year: u.year, calendar: u.calendar, crop: u.crop, events: u.eventIds, by: u.by })), noEvent: evald.noEvent.map((u) => ({ unit: name(u), point: u.point, year: u.year, calendar: u.calendar, crop: u.crop, by: u.by })) },
  };
  if (HEAT) out.meta.factors = 'heat factor on (AquaCrop maize/tomato pollination thresholds, logistic over 5 C, mean over flowering window); beans have no threshold so are unchanged; fertility class not stated (multiplier 1); same fixed thresholds, nothing tuned';
  fs.writeFileSync(path.join(root, HEAT ? 'web/data/factors_real_events_check.json' : 'web/data/real_events_check.json'), JSON.stringify(out, null, 1));
  console.log('units', out.counts, 'skipped', U.skippedEvents.map((s) => `${s.id} ${s.year} ${s.season}`).join('; '));
  for (const s of SOURCES) for (const p of ['A', 'B', 'all']) { const x = summary[s][p]; console.log(s, p, 'hit', `${x.events.hits}/${x.events.n}`, 'common', `${x.eventsCommonSupport.hits}/${x.eventsCommonSupport.n}`, 'noEvFlag', `${x.noEventYearsFlagged.hits}/${x.noEventYearsFlagged.n}`, 'otherFlag', `${x.otherYearsFlagged.hits}/${x.otherYearsFlagged.n}`, 'AUCnoEv', x.aucVsNoEventYears.auc, `(${x.aucVsNoEventYears.nEvents}/${x.aucVsNoEventYears.nControls})`, 'AUCother', x.aucVsOtherYears.auc, `(${x.aucVsOtherYears.nEvents}/${x.aucVsOtherYears.nControls})`, 'commonOther', x.aucVsOtherYearsCommonSupport.auc, `(${x.aucVsOtherYearsCommonSupport.nEvents}/${x.aucVsOtherYearsCommonSupport.nControls})`, 'commonNoEv', x.aucVsNoEventYearsCommonSupport.auc, `(${x.aucVsNoEventYearsCommonSupport.nEvents}/${x.aucVsNoEventYearsCommonSupport.nControls})`); }
  console.log('rule input A', ruleInputA, decision);
}
