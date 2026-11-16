// Tarea 36, parte C (pérdida del maíz): "predecir y luego elegir" con la red v3 de embudo (semillas 17/29/43) en los 54 casos (3 pilotos x 2019-2024 x pérdida a 30/45/60 días)
// y los 27 reservados (2022-2024), con (a) canResow verdadero y falso y (b) como qué-pasaría, cada clase de fertilidad de AquaCrop (tabla 2.13a).
// canResow = falso es una restricción declarada: solo queda dejar el campo (valor 0), no es una predicción. La fertilidad multiplica por igual a todos los cultivos resembrados;
// aquí no se supone que no cambia la elección: se vuelve a decidir con las predicciones multiplicadas y se compara.
// Como no se reentrenó nada (el calor casi no actúa), se usa la red v3 existente. Uso: node scripts/factors/loss_constraints.mjs -> scripts/factors/out/factors_loss.json
import fs from 'node:fs';
import path from 'node:path';
import { mlpPredict } from '../../web/js/model/emulator.js';
import { FERTILITY_CLASSES } from '../../web/js/model/factors.js';
import { decideAction, networkOutcomes, lossMetrics, FALLOW } from '../compare/loss_decision_lib.mjs';
import { summarizeObjects, outcomeCounts } from '../compare/aligned_lib.mjs';
import { root, readJson, loadContext, buildRows, filterYears, PRIORITIES } from '../compare/loss_decision_core.mjs';

const SEEDS = [17, 29, 43];
const YEAR_SETS = { years2019_2024: [2019, 2020, 2021, 2022, 2023, 2024], reserved2022_2024: [2022, 2023, 2024] };
const ctx = loadContext();
const rows = buildRows(ctx); // verdad del simulador en el año Y, oráculo, regla y simulador (sin semilla)
const nets = Object.fromEntries(SEEDS.map((s) => [s, readJson(path.join(root, `web/data/emulator_v3_mlp_seed${s}.json`))]));

/** Decisión de cada caso con la red de la semilla, multiplicando las predicciones por m (1 = fertilidad no declarada) y la restricción canResow. */
const decisionsFor = (seed, m, canResow) => {
  const predict = (x) => { const y = mlpPredict(nets[seed], x); return [y[0] * m, y[1] * m, y[2]]; }; // el multiplicador va a ambos cultivos; el tercer valor (cabe) no es un rendimiento
  return rows.map((r) => {
    const outcomes = networkOutcomes({ emuTexture: ctx.siteSoil[r.site].nearestTexture, predict, crops: ctx.crops }, r._past, r._offsetDays);
    return Object.fromEntries(PRIORITIES.map((p) => [p, decideAction({ outcomes, targetYear: r.year, priority: p, canResow })]));
  });
};

const FIELDS = ['chosenMean', 'meanGainVsRule', 'win', 'tie', 'loss', 'meanRegret', 'p10', 'worst', 'executable', 'below05', 'departsFromRule'];
const evalSet = (idxs, decs, m, canResow) => {
  const sub = idxs.map((i) => rows[i]);
  const items = sub.map((r, k) => {
    const action = decs[idxs[k]];
    const base = r._truthOf(action);
    const v = canResow || action === FALLOW ? base.relYield * (action === FALLOW ? 1 : m) : 0;
    return { r, action, value: v, executable: base.executable };
  });
  const ruleVal = (r) => (canResow ? r._truthOf(r.decisions.rule.none).relYield * (r.decisions.rule.none === FALLOW ? 1 : m) : 0);
  const mm = lossMetrics(items.map(({ r, action, value, executable }) => ({
    action, value, executable, ruleValue: ruleVal(r), oracleValue: r._truthOf(r.oracle).relYield * (r.oracle === FALLOW ? 1 : m), simAction: r.decisions.simulator.typical,
  })));
  const c = outcomeCounts(items.map((x) => ({ value: x.value, action: x.action, ruleAction: x.r.decisions.rule.none })));
  return { n: mm.n, chosenMean: mm.chosenMean, meanGainVsRule: mm.meanGainVsRule, win: mm.win, tie: mm.tie, loss: mm.loss, meanRegret: mm.meanRegret, p10: mm.p10, worst: mm.worst, executable: mm.executable, below05: c.below05, departsFromRule: c.departsFromRule, actions: mm.actions };
};

const scenarios = {
  canResowTrue: { m: 1, canResow: true },
  canResowFalse: { m: 1, canResow: false },
  ...Object.fromEntries(Object.entries(FERTILITY_CLASSES).map(([k, m]) => [`fertility_${k}`, { m, canResow: true }])),
};
const cache = {}; // `${seed}|${m}|${canResow}` -> decisiones
const decs = (seed, m, canResow) => (cache[`${seed}|${m}|${canResow}`] ??= decisionsFor(seed, m, canResow));
// decisiones sin restricción por prioridad, para comparar la elección bajo cada clase con la de "no declarada"
const base = Object.fromEntries(SEEDS.map((s) => [s, decs(s, 1, true)]));

const out = { meta: {}, decision: {}, sameChoiceAsNotStated: {} };
for (const [setName, years] of Object.entries(YEAR_SETS)) {
  const idxs = rows.map((r, i) => (years.includes(r.year) ? i : -1)).filter((i) => i >= 0);
  out.decision[setName] = { n: idxs.length };
  out.sameChoiceAsNotStated[setName] = {};
  for (const [name, { m, canResow }] of Object.entries(scenarios)) {
    out.decision[setName][name] = {};
    for (const p of PRIORITIES) {
      const list = SEEDS.map((s) => evalSet(idxs, decs(s, m, canResow).map((d) => d[p]), m, canResow));
      out.decision[setName][name][p] = summarizeObjects(list, FIELDS);
      out.decision[setName][name][p].actionsBySeed = Object.fromEntries(SEEDS.map((s, k) => [s, list[k].actions]));
    }
    if (canResow) {
      out.sameChoiceAsNotStated[setName][name] = Object.fromEntries(PRIORITIES.map((p) => [p, SEEDS.map((s) => idxs.filter((i) => decs(s, m, true)[i][p] === base[s][i][p]).length)]));
    }
  }
  // referencias sin semilla: regla agronómica y oráculo del simulador
  const sub = idxs.map((i) => rows[i]);
  out.decision[setName].reference = {
    ruleMeanRelYield: sub.reduce((a, r) => a + r._truthOf(r.decisions.rule.none).relYield, 0) / sub.length,
    oracleMeanRelYield: sub.reduce((a, r) => a + r._truthOf(r.oracle).relYield, 0) / sub.length,
    ruleActions: sub.reduce((a, r) => { const k = r.decisions.rule.none; a[k] = (a[k] ?? 0) + 1; return a; }, {}),
    oracleActions: sub.reduce((a, r) => { a[r.oracle] = (a[r.oracle] ?? 0) + 1; return a; }, {}),
  };
}
out.meta = {
  generated: new Date().toISOString().slice(0, 10), network: 'v3 funnel MLP (backprop), seeds 17/29/43, web/data/emulator_v3_mlp_seed{17,29,43}.json; not retrained (the heat factor is almost never active, see factors_eval.json heat)',
  method: 'predict then choose: the network predicts the relative yield of each of 7 crops (resown at the actual date) in the past years; the choice applies the priority (typical = median, cautious = 20th percentile) and the stated constraint. Truth = simulator in year Y (water only).',
  cases: { years2019_2024: '54 cases (3 pilots x years 2019-2024 x loss day 30/45/60)', reserved2022_2024: '27 cases (2022-2024)' },
  canResowFalse: 'Stated constraint, not a prediction: only "leave the field" remains (value 0). The rule baseline and every policy then also get 0 because nothing can be resown.',
  fertility: 'What-if: AquaCrop table 2.13a relative biomass (near-optimal 0.80, moderate 0.60, about half 0.50, poor 0.40, very poor 0.25) multiplies the predicted relative yield of every resown crop; the truth is multiplied the same way. Generic classes, not calibrated for Guatemala; there is no source that maps fertilised/not fertilised to a class.',
  utilityNote: 'Values are relative yield (0 to 1); no money and no margin.',
};
fs.writeFileSync(path.join(root, 'scripts/factors/out/factors_loss.json'), JSON.stringify(out, null, 1));
const f = (v) => (v == null ? '-' : v.mean.toFixed(3));
for (const [setName, d] of Object.entries(out.decision)) {
  console.log(setName, 'n', d.n, 'rule', d.reference.ruleMeanRelYield.toFixed(3), 'oracle', d.reference.oracleMeanRelYield.toFixed(3));
  for (const name of Object.keys(scenarios)) for (const p of PRIORITIES) { const x = d[name][p]; console.log(' ', name.padEnd(22), p.padEnd(8), 'mean', f(x.chosenMean), 'gain', f(x.meanGainVsRule), 'W/T/L', f(x.win), f(x.tie), f(x.loss), 'p10', f(x.p10), 'worst', f(x.worst), 'below.5', f(x.below05), 'departs', f(x.departsFromRule), JSON.stringify(x.actionsBySeed[17])); }
  console.log(' same choice vs not-stated', JSON.stringify(out.sameChoiceAsNotStated[setName]));
}
