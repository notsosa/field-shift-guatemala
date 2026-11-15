// Evaluación alineada a las condiciones de Alex: semillas 17, 29 y 43; años reservados 2022-2025 (medibles 2022-2024).
// Uso: C:/Users/velas/venv_lab4/Scripts/python.exe scripts/gpu/elm_gpu.py v2 ; node scripts/compare/aligned_eval.mjs
// (requiere samples_v2.json, web/data/emulator_v2_mlp_seed{17,29,43}.json y los ELM de la GPU scripts/compare/out/elm_v2_seed{S}.json; desde la Tarea 33 el ELM se ajusta en GPU, antes en JS ~50 s por semilla)
// No reajusta las redes con 2019-2021: siguen entrenadas sin 2019-2024. No compara con ningún otro modelo.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { elmPredict, mlpPredict, r2, rmse } from '../../web/js/model/emulator.js';
import { summarizeSeeds, summarizeObjects, outcomeCounts } from './aligned_lib.mjs';
import {
  root, readJson, loadContext, buildRows, addNetworkPolicy, filterYears, metricsFor, ELM_CFG, PRIORITIES, TARGET_YEARS,
} from './loss_decision_core.mjs';

const TAG = 'v2';
const SEEDS = [17, 29, 43];
const elmSeconds = {};
const YEAR_SETS = { years2019_2024: TARGET_YEARS, reserved2022_2024: [2022, 2023, 2024] };
const ctx = loadContext();
const { featureNames, targetNames, X, Y, meta } = ctx.samples;
const T = targetNames.length, FIT = 2;
const inYears = (m) => m.year >= 2019 && m.year <= 2024;
const SPLITS = { newYears: (m) => inYears(m) && !ctx.held.has(m.pointId), newPoints: (m) => ctx.held.has(m.pointId) && !inYears(m) };
const teIdx = meta.map((m, i) => i).filter((i) => inYears(meta[i]) || ctx.held.has(meta[i].pointId));

const f1Of = (rows, P) => {
  let tp = 0, fp = 0, fn = 0;
  for (const i of rows) { const t = Y[i][FIT] >= 0.5, p = P.get(i)[FIT] >= 0.5; if (t && p) tp++; else if (p) fp++; else if (t) fn++; }
  const pr = tp + fp ? tp / (tp + fp) : null, rc = tp + fn ? tp / (tp + fn) : null;
  return pr != null && rc != null && pr + rc > 0 ? (2 * pr * rc) / (pr + rc) : null;
};
const accuracy = (predict) => {
  const P = new Map(teIdx.map((i) => [i, predict(X[i])]));
  return Object.fromEntries(Object.entries(SPLITS).map(([name, f]) => {
    const rows = teIdx.filter((i) => f(meta[i]));
    return [name, {
      n: rows.length,
      r2: Array.from({ length: T }, (_, o) => r2(rows.map((i) => Y[i][o]), rows.map((i) => P.get(i)[o]))),
      rmse: Array.from({ length: T }, (_, o) => rmse(rows.map((i) => Y[i][o]), rows.map((i) => P.get(i)[o]))),
      f1: f1Of(rows, P),
    }];
  }));
};

const rows = buildRows(ctx); // verdad, oráculo, regla y simulador: sin semilla, una sola vez
const emulator = { perSeed: {}, summary: {} };
for (const seed of SEEDS) {
  const net = readJson(path.join(root, `web/data/emulator_v2_mlp_seed${seed}.json`));
  if (net.seed !== seed) throw new Error(`seed del archivo ${net.seed} != ${seed}`);
  const elmFile = readJson(path.join(root, `scripts/compare/out/elm_${TAG}_seed${seed}.json`));
  const elm = elmFile.model;
  elmSeconds[seed] = elmFile.trainSeconds;
  console.log(`seed ${seed}: ELM (GPU) ajustada en ${elmFile.trainSeconds.toFixed(2)} s`);
  const mlpP = (x) => mlpPredict(net, x), elmP = (x) => elmPredict(elm, x);
  emulator.perSeed[seed] = { mlp: accuracy(mlpP), elm: accuracy(elmP), mlpEpochs: net.epochs, mlpBestValLoss: net.bestValLoss };
  addNetworkPolicy(rows, ctx, `mlp${seed}`, mlpP);
  addNetworkPolicy(rows, ctx, `elm${seed}`, elmP);
}

const withCounts = (sub, policy, priority) => {
  const m = metricsFor(sub, policy, priority);
  const items = sub.map((r) => { const action = policy === 'rule' ? r.decisions.rule.none : r.decisions[policy][priority]; return { value: r._truthOf(action).relYield, action, ruleAction: r.decisions.rule.none }; });
  const c = outcomeCounts(items);
  return { n: m.n, chosenMean: m.chosenMean, meanGainVsRule: m.meanGainVsRule, win: m.win, tie: m.tie, loss: m.loss, meanRegret: m.meanRegret, p10: m.p10, worst: m.worst, executable: m.executable, below05: c.below05, departsFromRule: c.departsFromRule, actions: m.actions };
};
const FIELDS = ['chosenMean', 'meanGainVsRule', 'win', 'tie', 'loss', 'meanRegret', 'p10', 'worst', 'executable', 'below05', 'departsFromRule'];
const decision = { noSeed: {}, perSeed: {}, summary: {} };
for (const [setName, years] of Object.entries(YEAR_SETS)) {
  const sub = filterYears(rows, years);
  const oracleItems = sub.map((r) => ({ value: r._truthOf(r.oracle).relYield, action: r.oracle, ruleAction: r.decisions.rule.none }));
  decision.noSeed[setName] = {
    n: sub.length, years,
    rule: withCounts(sub, 'rule', null),
    simulator: Object.fromEntries(PRIORITIES.map((p) => [p, withCounts(sub, 'simulator', p)])),
    oracle: { chosenMean: metricsFor(sub, 'rule', null).oracleMean, executableShare: sub.filter((r) => r._truthOf(r.oracle).executable).length / sub.length, ...outcomeCounts(oracleItems) },
  };
  decision.perSeed[setName] = {}; decision.summary[setName] = {};
  for (const pol of ['mlp', 'elm']) {
    decision.summary[setName][pol] = {};
    for (const p of PRIORITIES) {
      const list = SEEDS.map((s) => withCounts(sub, `${pol}${s}`, p));
      SEEDS.forEach((s, k) => { ((decision.perSeed[setName][s] ??= {})[pol] ??= {})[p] = list[k]; });
      decision.summary[setName][pol][p] = summarizeObjects(list, FIELDS);
    }
  }
}
for (const pol of ['mlp', 'elm']) {
  emulator.summary[pol] = {};
  for (const split of Object.keys(SPLITS)) {
    const per = SEEDS.map((s) => emulator.perSeed[s][pol][split]);
    emulator.summary[pol][split] = { r2: targetNames.map((_, o) => summarizeSeeds(per.map((e) => e.r2[o]))), rmse: targetNames.map((_, o) => summarizeSeeds(per.map((e) => e.rmse[o]))), f1: summarizeSeeds(per.map((e) => e.f1)) };
  }
}

const git = (...a) => execFileSync('git', ['-C', root, ...a], { encoding: 'utf8' }).trim();
const out = {
  meta: {
    simulatorCommit: git('rev-parse', '--short', 'HEAD'), simulatorDirty: git('status', '--porcelain', '--', 'web/js/model', 'web/data/crops.json') !== '',
    generated: new Date().toISOString().slice(0, 10), seeds: SEEDS, targets: targetNames, features: featureNames.length,
    networks: { mlp: SEEDS.map((s) => `web/data/emulator_v2_mlp_seed${s}.json`), mlpRecipe: 'base, same data and splits as the seed-42 model', elm: { ...ELM_CFG, seed: 'per seed (random hidden layer)', fit: 'GPU, torch.linalg Cholesky ridge (scripts/gpu/elm_gpu.py); same hidden weights as trainELM', trainSecondsGpu: elmSeconds } },
    yearSets: { years2019_2024: '54 cases: 3 pilots x agricultural years 2019-2024 x loss day 30/45/60', reserved2022_2024: '27 cases: 3 pilots x agricultural years 2022-2024 x loss day 30/45/60' },
    reservedYearsRequested: '2022-2025 (years reserved by the teammate)',
    note2025: 'Agricultural year 2025 (April 2025 - March 2026) cannot be scored: the weather series ends on 2025-12-31. No data was invented; 2022-2024 is what can be measured.',
    refit: 'The networks were NOT refitted with 2019-2021 added: they were fitted with years 2019-2024 held out, so 2022-2024 is a subset of years they never saw.',
    ruleSimulatorOracle: 'rule, simulator-policy and oracle have no seed and are computed once.',
    emulatorSplits: 'newYears = years 2019-2024 at non-held-out points; newPoints = held-out points at other years (same as emulator_v2_eval.json). Emulator accuracy is on the test years 2019-2024 as trained; it is not recomputed for 2022-2024 only.',
  },
  emulator, decision,
};
fs.writeFileSync(path.join(root, 'web/data/aligned_eval.json'), JSON.stringify(out, null, 1));
const f = (v) => (v == null ? '-' : v.toFixed(3));
for (const pol of ['mlp', 'elm']) console.log(pol, 'R2 newYears per seed', SEEDS.map((s) => emulator.perSeed[s][pol].newYears.r2.map(f).join('/')).join(' | '));
