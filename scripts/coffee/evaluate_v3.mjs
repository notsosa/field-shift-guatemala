// Evaluación del café v3 con los sistemas de la auditoría del asesor (Tarea 41) -> web/data/coffee_eval_v3.json. Los parámetros de las clases son valores de referencia de FAO-56 (no medidas de campo); ver coffee.js, SYSTEMS.
// Lee scripts/coffee/cache/coffee_table_v3.json y ptc_v3_seed{S}.json (ptc_mlp_v3.py); compara con web/data/coffee_eval.json (v1), que no se toca.
// Por sistema (sin sombra, árboles de hoja perenne, árboles de hoja caduca, café con malezas, banano regulado, banano denso): utilidad media de predecir-y-elegir v3 y de la regla FAO-56, riegos y estrés de la simulación.
// La regla FAO-56 es la misma para todos los sistemas (balance corrido del café, Kc 0.95, p 0.40): es lo que el agricultor puede observar; no usa el Kc ni la p del sistema.
// Uso: node scripts/coffee/evaluate_v3.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { summarizeObjects } from '../compare/aligned_lib.mjs';
import { PRICE, IRRIGATION_MM, HORIZON_DAYS, DECISION_DAYS, SYSTEMS, SYSTEMS_SOURCE } from '../../web/js/model/coffee.js';
import { metrics, oracleIrrigates } from './eval_lib.mjs';
import { RESERVED, SPLITS } from './scenarios.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const cache = (f) => path.join(root, 'scripts/coffee/cache', f);
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
const SEEDS = [17, 29, 43];
const T = readJson(cache('coffee_table_v3.json'));
const V1 = readJson(path.join(root, 'web/data/coffee_eval.json'));
const S = T.scenarios;
const PRI = [0, 1], PRI_NAME = { 0: 'saveWater', 1: 'protectCrop' };
const FIELDS = ['meanUtility', 'ruleMeanUtility', 'oracleMeanUtility', 'gainVsRule', 'irrigations', 'stressDaysLeft', 'stressDaysNoIrrigation', 'departsFromRule'];
const ORIGINAL = ['none', 'evergreen', 'deciduous'];
const SYSTEM_LABELS = ['weedy', 'regulated', 'dense'];
const SHADE_LABELS = [...ORIGINAL, ...SYSTEM_LABELS];
const GROUPS = { original: (s) => ORIGINAL.includes(s.shade), ...Object.fromEntries(SHADE_LABELS.map((l) => [l, (s) => s.shade === l])) };

const preds = SEEDS.map((s) => readJson(cache(`ptc_v3_seed${s}.json`)));
for (const p of preds) if (p.pred.length !== S.length) throw new Error('ptc_v3_seed no coincide con la tabla');
const best = readJson(path.join(root, 'web/data/coffee_ptc_mlp_v3.json'));

const idxOf = (list, pred) => list.map((s, i) => (pred(s) ? i : -1)).filter((i) => i >= 0);
const SETS = { test2019_2024: (s) => s.split === 'test', reserved2022_2024: (s) => s.split === 'test' && RESERVED.includes(s.year) };
const ptcDec = (pred) => pred.map((v) => PRI.map((p) => (v > PRICE[p] ? 1 : 0)));
const ruleDec = (list) => list.map((s) => [s.rule, s.rule]);
const oracleDec = (list) => list.map((s) => PRI.map((p) => (oracleIrrigates(s, p) ? 1 : 0)));

function evalDec(list, dec, groups) {
  const out = {};
  for (const [setName, sf] of Object.entries(SETS)) {
    out[setName] = {};
    for (const [g, gf] of Object.entries(groups)) {
      const ids = idxOf(list, (s) => sf(s) && gf(s));
      out[setName][g] = Object.fromEntries(PRI.map((p) => [PRI_NAME[p], metrics(ids.map((i) => list[i]), ids.map((i) => dec[i][p]), p)]));
    }
  }
  return out;
}
function summarize(perSeed) {
  const out = {};
  for (const setName of Object.keys(perSeed[0])) {
    out[setName] = {};
    for (const g of Object.keys(perSeed[0][setName])) {
      out[setName][g] = {};
      for (const p of Object.values(PRI_NAME)) out[setName][g][p] = { n: perSeed[0][setName][g][p].n, ...summarizeObjects(perSeed.map((e) => e[setName][g][p]), FIELDS) };
    }
  }
  return out;
}

// --- utilidad por sistema: red v3 por semilla, regla, oráculo ---
const ptcPerSeed = preds.map((p) => evalDec(S, ptcDec(p.pred), GROUPS));
const ptc = summarize(ptcPerSeed);
const rule = evalDec(S, ruleDec(S), GROUPS), oracle = evalDec(S, oracleDec(S), GROUPS);

// --- estrés de la simulación por sistema (sin riego): días con Ks < 1 en cuajado, llenado de grano y estación seca; ETa/ETc ---
const meanOf = (a) => a.reduce((x, y) => x + y, 0) / a.length;
function stressRows(rows, label, yearFilter) {
  const r = rows.filter((y) => y.shade === label && yearFilter(y.year));
  const f = (k, q) => meanOf(r.map((y) => y[k][q]));
  return { n: r.length, fruitSetStressDays: f('fruitSet', 'stressDays'), grainFillStressDays: f('grainFill', 'stressDays'), drySeasonStressDays: f('drySeason', 'stressDays'),
    fruitSetEtaOverEtc: f('fruitSet', 'etaOverEtc'), grainFillEtaOverEtc: f('grainFill', 'etaOverEtc'), drySeasonEtaOverEtc: f('drySeason', 'etaOverEtc') };
}
const YEARS = { years2001_2024: () => true, test2019_2024: (y) => y >= 2019 && y <= 2024 };
const stress = Object.fromEntries(Object.entries(YEARS).map(([k, yf]) => [k, Object.fromEntries(SHADE_LABELS.map((l) => [l, stressRows(T.yearMeasures, l, yf)]))]));
// días de estrés evitables en los escenarios de decisión (sin riego, a 30 días): media por sistema, prueba
const stressNo = Object.fromEntries(SHADE_LABELS.map((l) => [l, S.filter((s) => s.shade === l && s.split === 'test')])
  .map(([l, rows]) => [l, { n: rows.length, stressDaysNoIrrigation30: meanOf(rows.map((s) => s.stressNo)), stressDaysAvoidedBy20mm: meanOf(rows.map((s) => s.avoided)), ruleSaysIrrigate: rows.filter((s) => s.rule === 1).length }]));

// --- v1 contra v3 en los escenarios originales (la misma muestra: 6480 filas, prueba 2700 / reservado 1350) ---
const v1Group = { original: 'all', none: 'noShade', evergreen: 'evergreen', deciduous: 'deciduous' };
const v1v3 = {};
for (const setName of Object.keys(SETS)) {
  const k1 = setName === 'test2019_2024' ? 'test' : 'reserved2022_2024';
  v1v3[setName] = {};
  for (const g of ['original', ...ORIGINAL]) {
    v1v3[setName][g] = {};
    for (const p of Object.values(PRI_NAME)) {
      const a = V1.policies.summary.predictThenChooseMlp[k1][v1Group[g] ?? g][p], b = ptc[setName][g][p];
      const r = V1.policies.noSeed.rule[k1][v1Group[g] ?? g][p];
      v1v3[setName][g][p] = { n: b.n, v1MeanUtility: a.meanUtility.mean, v3MeanUtility: b.meanUtility.mean, diff: b.meanUtility.mean - a.meanUtility.mean, v1Irrigations: a.irrigations.mean, v3Irrigations: b.irrigations.mean, ruleMeanUtility: r.meanUtility };
    }
  }
}

const out = {
  meta: {
    task: 41, systemsSource: SYSTEMS_SOURCE,
    note: 'Los parámetros de las clases (Kc compuesto y p) son valores de referencia de FAO-56 de la auditoría del asesor del equipo, sin calibración local: la red aprende el simulador, no una medida de campo.',
    systems: { none: 'café de siempre: Kc 0.95 constante, p 0.40 (suelo limpio o con mulch)', weedy: { id: 'malezas', ...SYSTEMS.malezas }, regulated: { id: 'regulado', ...SYSTEMS.regulado }, dense: { id: 'denso', ...SYSTEMS.denso } },
    decision: { irrigationMm: IRRIGATION_MM, horizonDays: HORIZON_DAYS, decisionDaysAfterFlowering: DECISION_DAYS, price: { saveWater: PRICE[0], protectCrop: PRICE[1] } },
    splits: SPLITS, reserved: RESERVED, shades: SHADE_LABELS, seeds: SEEDS, selectedSeed: best.seed, inputNames: best.inputNames,
    scenarios: { total: S.length, test: idxOf(S, SETS.test2019_2024).length, reserved: idxOf(S, SETS.reserved2022_2024).length },
    originalRowsCheck: T.meta.originalRowsCheck,
    ruleNote: 'La regla FAO-56 usa el balance corrido del café (Kc 0.95, p 0.40) en todos los sistemas, porque es lo que el agricultor puede observar; no conoce el Kc ni la p del sistema.',
    stressNote: 'stress = días con Ks < 1 del lote (FAO-56 ec. 84 con la p del sistema: 0.40 sin sombra, árboles y malezas; 0.38 banano regulado; 0.35 banano denso) en la simulación continua sin riego; ETa/ETc con la ETc del lote. Media sobre sitios, suelos y años cafeteros.',
  },
  utility: { predictThenChooseV3: ptc, predictThenChooseV3PerSeed: ptcPerSeed, rule, oracle },
  stress, stressNoIrrigation30DayDecision: stressNo,
  v1VsV3OnOriginalScenarios: v1v3,
};
fs.writeFileSync(path.join(root, 'web/data/coffee_eval_v3.json'), JSON.stringify(out, null, 1));

const f = (x, d = 3) => (x == null ? 'NA' : x.toFixed(d));
for (const setName of Object.keys(SETS)) {
  console.log(`== ${setName}`);
  for (const g of Object.keys(GROUPS)) console.log(g.padEnd(12), Object.values(PRI_NAME).map((p) => { const m = ptc[setName][g][p]; return `${p}: ptc ${f(m.meanUtility.mean)} rule ${f(m.ruleMeanUtility.mean)} irr ${f(m.irrigations.mean, 0)}/${m.n}`; }).join(' | '));
}
for (const [yk, o] of Object.entries(stress)) { console.log(`== estres ${yk}`); for (const [l, v] of Object.entries(o)) console.log(l.padEnd(12), `fs ${f(v.fruitSetStressDays, 1)} gf ${f(v.grainFillStressDays, 1)} dry ${f(v.drySeasonStressDays, 1)} | ETa/ETc fs ${f(v.fruitSetEtaOverEtc)} gf ${f(v.grainFillEtaOverEtc)} dry ${f(v.drySeasonEtaOverEtc)}`); }
console.log('== v1 vs v3 originales (prueba)');
for (const g of ['original', ...ORIGINAL]) console.log(g.padEnd(10), Object.values(PRI_NAME).map((p) => { const c = v1v3.test2019_2024[g][p]; return `${p}: v1 ${f(c.v1MeanUtility)} v3 ${f(c.v3MeanUtility)}`; }).join(' | '));
console.log('== stressNo30 / evitados (prueba)'); for (const [l, v] of Object.entries(stressNo)) console.log(l.padEnd(12), f(v.stressDaysNoIrrigation30, 2), f(v.stressDaysAvoidedBy20mm, 2), v.ruleSaysIrrigate, '/', v.n);
