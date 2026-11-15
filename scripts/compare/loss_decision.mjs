// Decisión tras perder el maíz: qué hacer con el campo (resembrar uno de siete cultivos o dejarlo sin cultivo), con información previa.
// Uso: node scripts/compare/loss_decision.mjs  (requiere scripts/emulator/samples_v2.json y web/data/emulator_v2_mlp.json; la ELM v2 se entrena aquí, ~1 min)
// Casos: 3 pilotos x años 2019-2024 x pérdida a los 30, 45 o 60 días de la siembra = 54. Verdad = el simulador en el año Y.
// Todo está fijado en loss_decision_lib.mjs y aquí; no se ajusta tras ver resultados. NO se calcula margen: el modelo no tiene precios ni costos.
// Las piezas compartidas (casos, políticas de red, métricas) están en loss_decision_core.mjs.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { elmPredict, mlpPredict } from '../../web/js/model/emulator.js';
import { RESOW_CROPS, FALLOW, RULE } from './loss_decision_lib.mjs';
import {
  SITES, TARGET_YEARS, ELM_CFG, root, readJson, loadContext, trainElmV2, buildRows, addNetworkPolicy, strip, metricsFor as metricsOf, PRIORITIES, LOSS_DAYS,
} from './loss_decision_core.mjs';

const ctx = loadContext();
const bundles = ctx.bundles;
const mlp = readJson(path.join(root, 'web/data/emulator_v2_mlp.json'));
const t0 = performance.now();
const elm = trainElmV2(ctx, ELM_CFG.seed);
console.log(`ELM v2 entrenada (${ctx.fitIdx.length} filas) en ${((performance.now() - t0) / 1000).toFixed(1)} s`);
const predictors = { mlp: (x) => mlpPredict(mlp, x), elm: (x) => elmPredict(elm, x) };

const rows = buildRows(ctx);
for (const [name, predict] of Object.entries(predictors)) addNetworkPolicy(rows, ctx, name, predict);

const POLICY_LIST = ['simulator', 'mlp', 'elm'];
const metricsFor = (policy, priority, subset = rows) => metricsOf(subset, policy, priority);
const metrics = { rule: metricsFor('rule', null) };
for (const policy of POLICY_LIST) metrics[policy] = Object.fromEntries(PRIORITIES.map((p) => [p, metricsFor(policy, p)]));
const byLossDay = Object.fromEntries(LOSS_DAYS.map((L) => {
  const sub = rows.filter((r) => r.lossDay === L);
  return [L, { rule: metricsFor('rule', null, sub), ...Object.fromEntries(POLICY_LIST.map((pol) => [pol, Object.fromEntries(PRIORITIES.map((p) => [p, metricsFor(pol, p, sub)]))])) }];
}));
const ruleVsSimulator = Object.fromEntries(PRIORITIES.map((p) => [p, rows.filter((r) => r.decisions.rule.none === r.decisions.simulator[p]).length]));

const git = (...a) => execFileSync('git', ['-C', root, ...a], { encoding: 'utf8' }).trim();
const out = {
  meta: {
    simulatorCommit: git('rev-parse', '--short', 'HEAD'), simulatorDirty: git('status', '--porcelain', '--', 'web/js/model', 'web/data/crops.json') !== '',
    rainSource: [...new Set(Object.values(bundles).map((b) => b.rainSource))].join(', '), generated: new Date().toISOString().slice(0, 10),
    networks: { mlp: 'web/data/emulator_v2_mlp.json', elm: ELM_CFG, elmRows: 'samples_v2.json minus test (2019-2024 or held-out points) minus validation years 2017-2018' },
  },
  design: {
    cases: `${SITES.length} pilots (${SITES.join(', ')}) x target years ${TARGET_YEARS[0]}-${TARGET_YEARS.at(-1)} x main maize lost ${LOSS_DAYS.join(', ')} days after sowing = ${rows.length}`,
    soil: 'Simulator truth uses the pilot SoilGrids soil; the networks get its nearestTexture.',
    timing: 'Maize sown at the rain-onset rule; the field is free the day after the loss and the next sowing is 14 days later (offset = lossDay + 1 + 14 = 45, 60, 75 days after the onset rule).',
    actions: [...RESOW_CROPS, `${FALLOW} (leave the field without a crop / cover: relYield 0, always executable)`],
    objective: 'relYield of the resown crop in the simulator; 0 if its cycle does not complete inside the agricultural year. No margin: this model has no prices or costs.',
    priorities: 'typical = median of the past years, cautious = 20th percentile',
    informationRule: 'The decision for year Y uses only agricultural years before Y at that site (bundle truncated to 31 March of Y, then year filter).',
    policies: { simulator: 'simulator on past years', mlp: 'v2 funnel MLP on past years (resown crop as A at its actual sowing date, B = none)', elm: 'v2 ELM on past years (same encoding)', rule: `simple agronomic rule (Alex): resow maize if at least ${RULE.maizeMinDays} days remain before 15 November, else beans if at least ${RULE.beansMinDays}, else leave the field`, oracle: 'best action in year Y itself by the simulator' },
    tieBreak: 'higher summary wins; ties go to leaving the field, then to the order maiz, frijol, ajonjoli, papa, cebolla, brocoli, lechuga',
    tolerance: 0.001,
    extrapolationNote: 'The v2 networks were trained with sowing offsets 0, 15 and 30 days after the onset rule; these cases use 45, 60 and 75, so the networks extrapolate beyond their training range.',
    soilWaterNote: 'The resown crop is simulated alone from 1 April with a dry soil; water used by the lost maize is not carried over.',
  },
  metrics, byLossDay, ruleVsSimulatorSameAction: ruleVsSimulator,
  oracle: { chosenMean: metrics.rule.oracleMean, executableShare: rows.filter((r) => r._truthOf(r.oracle).executable).length / rows.length },
  cases: strip(rows),
};
fs.writeFileSync(path.join(root, 'web/data/decision_loss_eval.json'), JSON.stringify(out, null, 1));
const f = (v) => (v == null ? '-' : v.toFixed(3));
console.log('rule', f(metrics.rule.chosenMean), 'oracle', f(metrics.rule.oracleMean), 'exec', metrics.rule.executable, 'p10', f(metrics.rule.p10), 'worst', f(metrics.rule.worst));
for (const pol of POLICY_LIST) for (const p of PRIORITIES) { const m = metrics[pol][p]; console.log(pol, p, 'mean', f(m.chosenMean), 'gain', f(m.meanGainVsRule), `${m.win}/${m.tie}/${m.loss}`, 'regret', f(m.meanRegret), 'p10', f(m.p10), 'worst', f(m.worst), 'exec', `${m.executable}/${m.n}`, 'agree', m.agreesWithSimulator, JSON.stringify(m.actions)); }
