// Tabla de escenarios de la red que recomienda (Tarea 31): entradas del día de la decisión y resultado de cada acción por el simulador.
// Entrenamiento = 20 puntos x años agrícolas 2001-2016 x pérdida 30/45/60 (arena/franco/arcilla en los no pilotos, el suelo del sitio en los pilotos);
// validación = lo mismo con 2017-2018; prueba = los 3 pilotos x 2019-2024 con el suelo del sitio (54 casos).
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series, resolveMainSowIdx } from '../../web/js/model/simulate.js';
import { ACTION_IDS, FALLOW_ID, decisionState, actionFeatures } from '../../web/js/model/recommender.js';
import { RESOW_CROPS, LOSS_DAYS, resowOffset, ruleAction, simulateResow } from './loss_decision_lib.mjs';
import { root, readJson } from './loss_decision_core.mjs';

export const PILOTS = ['chiquimula', 'jutiapa', 'sanmartin'];
export const SPLIT_YEARS = { train: [2001, 2016], val: [2017, 2018], test: [2019, 2024] };
const range = ([a, b]) => Array.from({ length: b - a + 1 }, (_, i) => a + i);

export function loadPointData() {
  const crops = loadCrops(readJson(path.join(root, 'web/data/crops.json')));
  const points = readJson(path.join(root, 'scripts/emulator/points.json'));
  const data = points.map((p) => {
    const isPilot = PILOTS.includes(p.id);
    const bundle = readJson(path.join(root, isPilot ? `web/data/snapshots/${p.id}.json` : `scripts/emulator/cache/${p.id}.json`));
    return { id: p.id, name: p.name, isPilot, bundle, et0: computeEt0Series(bundle), soils: isPilot ? [['site', p.soil]] : ['sand', 'loam', 'clay'].map((s) => [s, s]) };
  });
  return { crops, points, data };
}

/** Un escenario: punto, suelo, año agrícola y día de pérdida → entradas (estado y acciones) y resultado de cada acción en el simulador. */
export function buildScenario({ crops, pt, soilLabel, soil, year, lossDay }) {
  const offsetDays = resowOffset(lossDay);
  const { bundle, et0 } = pt;
  const { state, sowLocal, startIdx, endLocal } = decisionState({ bundle, et0, year, lossDay, crops, soil });
  const resowLocal = resolveMainSowIdx(bundle, year, offsetDays).idx;
  const resowDate = bundle.dates[startIdx + resowLocal];
  const truth = ACTION_IDS.map((a) => (a === FALLOW_ID ? { relYield: 0, executable: true } : simulateResow({ bundle, et0, crops, texture: soil, year, cropId: a, offsetDays })));
  const rule = ruleAction(resowDate);
  const y = truth.map((t) => t.relYield);
  return {
    point: pt.id, soilLabel, year, lossDay, resowDate, state, sowLocal,
    actionRows: ACTION_IDS.map((a) => actionFeatures(crops, a, resowLocal, endLocal)),
    y, executable: truth.map((t) => t.executable), rule, ruleIdx: ACTION_IDS.indexOf(rule), oracleIdx: y.indexOf(Math.max(...y)),
  };
}

// Mismo desempate del oráculo que loss_decision_lib.chooseAction: empate → dejar el campo, luego el orden de ACTIONS.
export function oracleAction(y) {
  const best = Math.max(...y);
  const tied = ACTION_IDS.filter((a, i) => y[i] >= best - 1e-12);
  return tied.includes(FALLOW_ID) ? FALLOW_ID : tied[0];
}

export function buildTable() {
  const t0 = performance.now();
  const { crops, data } = loadPointData();
  const table = { train: [], val: [], test: [] };
  for (const [split, yrs] of Object.entries(SPLIT_YEARS)) {
    for (const pt of data) {
      if (split === 'test' && !pt.isPilot) continue;
      for (const [soilLabel, soil] of pt.soils) for (const year of range(yrs)) for (const lossDay of LOSS_DAYS) table[split].push(buildScenario({ crops, pt, soilLabel, soil, year, lossDay }));
    }
  }
  for (const s of Object.values(table).flat()) s.oracle = oracleAction(s.y);
  return { table, crops, data, seconds: (performance.now() - t0) / 1000 };
}
