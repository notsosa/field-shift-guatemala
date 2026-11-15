// Piezas reutilizables de la decisión tras perder el maíz: contexto, casos (verdad, regla, simulador), red como política y métricas.
// Las usan loss_decision.mjs (semilla 42, 2019-2024) y aligned_eval.mjs (semillas 17/29/43, subconjunto de años). Sin efectos de escritura.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series, resolveMainSowIdx } from '../../web/js/model/simulate.js';
import { trainELM } from '../../web/js/model/emulator.js';
import { PRIORITIES } from '../../web/js/model/decision.js';
import {
  RESOW_CROPS, FALLOW, LOSS_DAYS, resowOffset, ruleAction, daysBeforeNov15, chooseAction, decideAction, lossMetrics, pastData,
  simulatorOutcomes, networkOutcomes, simulateResow,
} from './loss_decision_lib.mjs';

export const SITES = ['chiquimula', 'jutiapa', 'sanmartin'];
export const TARGET_YEARS = [2019, 2020, 2021, 2022, 2023, 2024];
export const ELM_CFG = { hidden: 1500, inputScale: 0.1, lambda: 0.1, seed: 42 };
export const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
export const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));

export function loadContext() {
  const crops = loadCrops(readJson(path.join(root, 'web/data/crops.json')));
  const points = readJson(path.join(root, 'scripts/emulator/points.json'));
  const bundles = Object.fromEntries(SITES.map((s) => [s, readJson(path.join(root, `web/data/snapshots/${s}.json`))]));
  const siteSoil = Object.fromEntries(SITES.map((s) => [s, points.find((p) => p.id === s).soil]));
  const samples = readJson(path.join(root, 'scripts/emulator/samples_v2.json'));
  const held = new Set(points.filter((p) => p.heldOut).map((p) => p.id));
  const fitIdx = samples.meta.map((m, i) => i).filter((i) => { const m = samples.meta[i]; return !((m.year >= 2019 && m.year <= 2024) || held.has(m.pointId)) && ![2017, 2018].includes(m.year); });
  return { crops, points, bundles, siteSoil, samples, held, fitIdx };
}

export const trainElmV2 = (ctx, seed) => trainELM(ctx.fitIdx.map((i) => ctx.samples.X[i]), ctx.fitIdx.map((i) => ctx.samples.Y[i]), { ...ELM_CFG, seed });

// Casos con verdad, oráculo, regla y simulador (sin redes).
export function buildRows(ctx) {
  const { crops, bundles, siteSoil } = ctx;
  const rows = [];
  for (const site of SITES) {
    const bundle = bundles[site];
    const et0Full = computeEt0Series(bundle);
    for (const year of TARGET_YEARS) {
      const past = pastData(bundle, year); // lo único que ve la decisión: hasta el 31 de marzo de `year`
      const s0 = resolveMainSowIdx(bundle, year, 0).idx;
      for (const lossDay of LOSS_DAYS) {
        const offsetDays = resowOffset(lossDay);
        const truth = Object.fromEntries(RESOW_CROPS.map((c) => [c, simulateResow({ bundle, et0: et0Full, crops, texture: siteSoil[site], year, cropId: c, offsetDays })]));
        const truthOf = (a) => (a === FALLOW ? { relYield: 0, executable: true } : truth[a]);
        const resowDate = bundle.dates[bundle.dates.indexOf(`${year}-04-01`) + s0 + offsetDays];
        const oracle = chooseAction([...RESOW_CROPS.map((c) => ({ action: c, value: truth[c].relYield })), { action: FALLOW, value: 0 }]);
        const decisions = { rule: { none: ruleAction(resowDate) } };
        decisions.simulator = Object.fromEntries(PRIORITIES.map((p) => [p, decideAction({ outcomes: simulatorOutcomes({ crops, simSoil: siteSoil[site] }, past, offsetDays), targetYear: year, priority: p })]));
        rows.push({ site, year, lossDay, resowDate, daysBeforeNov15: daysBeforeNov15(resowDate), oracle, truth: Object.fromEntries(RESOW_CROPS.map((c) => [c, { relYield: truth[c].relYield, executable: truth[c].executable }])), decisions, _truthOf: truthOf, _past: past, _offsetDays: offsetDays });
      }
    }
  }
  return rows;
}

// Agrega la política de una red (predict) a todos los casos: decisiones por prioridad.
export function addNetworkPolicy(rows, ctx, name, predict, { v3 = false } = {}) {
  for (const r of rows) {
    const outcomes = networkOutcomes({ emuTexture: ctx.siteSoil[r.site].nearestTexture, predict, crops: v3 ? ctx.crops : null }, r._past, r._offsetDays);
    r.decisions[name] = Object.fromEntries(PRIORITIES.map((p) => [p, decideAction({ outcomes, targetYear: r.year, priority: p })]));
  }
}

export const strip = (rows) => rows.map(({ _truthOf, _past, _offsetDays, ...r }) => r);

// Subconjunto por años agrícolas (el año de un caso es el año en que empieza el año agrícola).
export const filterYears = (rows, years) => rows.filter((r) => years.includes(r.year));

export function metricsFor(rows, policy, priority) {
  return lossMetrics(rows.map((r) => {
    const action = policy === 'rule' ? r.decisions.rule.none : r.decisions[policy][priority];
    const t = r._truthOf(action);
    return { action, value: t.relYield, executable: t.executable, ruleValue: r._truthOf(r.decisions.rule.none).relYield, oracleValue: r._truthOf(r.oracle).relYield, simAction: r.decisions.simulator[priority ?? 'typical'] };
  }));
}

export { PRIORITIES, LOSS_DAYS, FALLOW };
