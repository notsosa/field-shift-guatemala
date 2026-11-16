// Tarea 36, parte C (café): la regla "antracnosis activa por estrés hídrico -> prioridad proteger el cultivo (precio 1)" medida en los 1620 escenarios de prueba (2019-2024).
// Para la red exportada de "predecir y luego elegir" (web/data/coffee_ptc_mlp.json) y para la regla FAO-56 (riega si el balance corrido pasa de p = 0.40 del agua disponible):
// días con aviso de antracnosis por estrés en los 30 días siguientes, con y sin el riego recomendado; utilidad con las dos prioridades; número de riegos.
// Roya y minador se reportan al lado: no cambian la decisión (ninguna fuente los enlaza con el riego).
// Uso: node scripts/factors/coffee_notices.mjs  -> escribe la sección coffee de web/data/factors_eval.json (vía factors_eval.mjs lo junta); aquí escribe scripts/factors/out/factors_coffee.json
import fs from 'node:fs';
import path from 'node:path';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series } from '../../web/js/model/simulate.js';
import { mlpPredict } from '../../web/js/model/emulator.js';
import {
  COFFEE_ID, PRICE, DECISION_DAYS, floweringFor, simulateCoffee, counterfactual, siteHistory, royaNotice, minadorNotice, antracnosisNotice, effectivePriority, ANTRACNOSIS,
} from '../../web/js/model/coffee.js';
import { RESERVED, SHADES, SOILS } from '../coffee/scenarios.mjs';

const root = path.resolve(path.dirname(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1')), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
const T = readJson(path.join(root, 'scripts/coffee/cache/coffee_table.json'));
const net = readJson(path.join(root, 'web/data/coffee_ptc_mlp.json'));
const crops = loadCrops(readJson(path.join(root, 'web/data/crops.json')));
const key = (s) => `${s.site}|${s.soil}|${s.shade}|${s.year}|${s.dayAfter}`;
const byKey = new Map(T.scenarios.map((s, i) => [key(s), i]));
const points = readJson(path.join(root, 'scripts/emulator/points.json')).filter((p) => T.sites.some((s) => s.id === p.id));
const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null);
const r3 = (x) => (x == null ? null : Math.round(x * 1000) / 1000);
const POL = ['rule', 'ptc']; // FAO-56 y la red exportada
const MODES = ['saveWater', 'protectCrop', 'saveWaterWithNoticeRule']; // prioridad declarada; con la regla del aviso, el agricultor pide ahorrar y el aviso la sube

const rows = [];
for (const pt of points) {
  const bundle = readJson(path.join(root, `scripts/emulator/cache/${pt.id}.json`));
  const et0 = computeEt0Series(bundle);
  const { dates, rain, tmax, tmin } = bundle;
  for (const soilLabel of SOILS) for (const sh of SHADES) {
    const sim = simulateCoffee({ dates, rain, et0, crops, texture: soilLabel, shade: sh.shade, treeType: sh.treeType });
    for (let year = 2019; year <= 2024; year++) {
      const fl = floweringFor(dates, rain, year + 1);
      for (const dayAfter of DECISION_DAYS) {
        const t = fl.idx + dayAfter;
        const idx = byKey.get(`${pt.id}|${soilLabel}|${sh.label}|${year}|${dayAfter}`);
        const sc = T.scenarios[idx];
        if (!sc || sc.split !== 'test') throw new Error(`scenario not found/test: ${pt.id} ${soilLabel} ${sh.label} ${year} ${dayAfter}`);
        const cf = counterfactual({ dates, rain, et0, crops, texture: soilLabel, shade: sh.shade, treeType: sh.treeType, sim, t, returnKs: true });
        if (cf.stressDaysAvoided !== sc.avoided) throw new Error('counterfactual differs from the table');
        const history = siteHistory(dates, tmax, tmin, Number(dates[t].slice(0, 4)));
        const ksFull = (w) => sim.ks.slice(0, t + 1).concat(w);
        const ksNo = ksFull(cf.ksNo), ksYes = ksFull(cf.ksYes);
        const noticeAt = (ks) => antracnosisNotice({ dates, tmax, tmin, ks, t, history });
        const ant = noticeAt(ksNo); // el día de la decisión t no depende del riego de hoy
        // días con aviso en los 30 días siguientes (t+1..t+30)
        const days = (ks) => { let byStress = 0, any = 0; for (let u = t + 1; u <= t + 30; u++) { const a = antracnosisNotice({ dates, tmax, tmin, ks, t: u, history }); if (a.triggers.byStress) byStress++; if (a.level === 'notice') any++; } return { byStress, any }; };
        const dNo = days(ksNo), dYes = days(ksYes);
        let roya = 0, minador = 0;
        for (let u = t + 1; u <= t + 30; u++) { if (royaNotice({ dates, tmax, tmin, t: u, history }).level === 'favorable') roya++; if (minadorNotice({ dates, tmax, rain, t: u, history }).level === 'probable') minador++; }
        rows.push({
          site: pt.id, soil: soilLabel, shade: sh.label, year, dayAfter, reserved: RESERVED.includes(year), avoided: sc.avoided, rule: sc.rule,
          ptcPred: mlpPredict(net, sc.state)[0], antActiveAtDecision: ant.triggers.byStress, antAnyAtDecision: ant.level === 'notice',
          antStressDaysNo: dNo.byStress, antStressDaysYes: dYes.byStress, antAnyDaysNo: dNo.any, antAnyDaysYes: dYes.any, royaDays: roya, minadorDays: minador,
        });
      }
    }
  }
}

const decide = (r, pol, mode) => {
  const priority = mode === 'protectCrop' ? 1 : 0;
  const eff = mode === 'saveWaterWithNoticeRule' ? effectivePriority(priority, { triggers: { byStress: r.antActiveAtDecision } }) : priority;
  if (pol === 'rule') return r.rule; // la regla FAO-56 no usa la prioridad
  return r.ptcPred > PRICE[eff] ? 1 : 0;
};
const summarize = (list) => {
  const out = { scenarios: list.length, antStressActiveAtDecision: list.filter((r) => r.antActiveAtDecision).length };
  out.noticeDays = {
    antracnosisByStress: { neverIrrigate: r3(mean(list.map((r) => r.antStressDaysNo))), alwaysIrrigate: r3(mean(list.map((r) => r.antStressDaysYes))) },
    royaFavorable: r3(mean(list.map((r) => r.royaDays))), minadorProbable: r3(mean(list.map((r) => r.minadorDays))),
  };
  out.policies = {};
  for (const pol of POL) {
    out.policies[pol] = {};
    for (const mode of MODES) {
      const dec = list.map((r) => decide(r, pol, mode));
      const util = (p) => mean(list.map((r, i) => (dec[i] ? r.avoided - PRICE[p] : 0)));
      const after = list.map((r, i) => (dec[i] ? r.antStressDaysYes : r.antStressDaysNo));
      const withoutIrr = list.map((r) => r.antStressDaysNo);
      out.policies[pol][mode] = {
        irrigations: dec.reduce((a, b) => a + b, 0), irrigationShare: r3(mean(dec)),
        utilityUnderSaveWater: r3(util(0)), utilityUnderProtectCrop: r3(util(1)),
        antracnosisStressDays30: { withoutIrrigation: r3(mean(withoutIrr)), withRecommendedIrrigation: r3(mean(after)), scenariosWithAnyDayWithout: withoutIrr.filter((x) => x > 0).length, scenariosWithAnyDayWith: after.filter((x) => x > 0).length },
        stressDaysLeft30: r3(mean(list.map((r, i) => (dec[i] ? r.avoided : 0)) .map((v, i) => 0 + v * 0))) ?? null,
      };
      delete out.policies[pol][mode].stressDaysLeft30;
    }
  }
  // dónde la regla del aviso cambia la decisión de la red
  const changed = list.filter((r) => decide(r, 'ptc', 'saveWater') !== decide(r, 'ptc', 'saveWaterWithNoticeRule'));
  out.noticeRuleChangesPtcDecision = { scenarios: changed.length, ofWhichAddedIrrigation: changed.filter((r) => decide(r, 'ptc', 'saveWaterWithNoticeRule') === 1).length };
  return out;
};
const result = { all2019_2024: summarize(rows), reserved2022_2024: summarize(rows.filter((r) => r.reserved)) };
const out = {
  meta: {
    generated: new Date().toISOString().slice(0, 10), scenarios: rows.length,
    rule: 'If the anthracnosis notice is active because of water stress (Ks < 1 on more than half of the last 28 days) the irrigation priority becomes "protect the crop" (price 1 day of stress avoided) whatever the grower stated; roya-only or no notice leaves the priority as stated. Approved in principle by the owner.',
    decision: `irrigate 20 mm today if the predicted stress days avoided (exported network web/data/coffee_ptc_mlp.json, seed ${net.seed}) exceed the price (3 days = save water, 1 day = protect the crop); the FAO-56 rule irrigates when the capped running depletion exceeds p = 0.40 of the available water and does not use the priority, so the notice rule cannot change it`,
    noticeDays: `days in t+1..t+30 with the anthracnosis notice active by stress (share of Ks<1 days over the last ${ANTRACNOSIS.days} days > ${ANTRACNOSIS.stressShare}), recomputed day by day from the soil water balance with and without the 20 mm irrigation at the end of day t (neverIrrigate/alwaysIrrigate are the two counterfactual series; the policy rows pick the one its decision leads to, per scenario)`,
    rainAndMinador: 'Roya "favorable" and minador "probable" days in t+1..t+30 depend only on the weather, not on irrigation; they are reported next to the anthracnosis days and do not change any decision.',
    modes: { saveWater: 'priority stated = save water, price 3', protectCrop: 'priority stated = protect the crop, price 1', saveWaterWithNoticeRule: 'priority stated = save water, raised to protect the crop when anthracnosis-by-stress is active at the decision day' },
    caveat: 'Notices are information with a source, not damage predictions; the number of notice days is a measure of water stress, not of disease. Scenarios of different shade/soil at one site-year share the weather.',
  },
  ...result,
};
fs.writeFileSync(path.join(root, 'scripts/factors/out/factors_coffee.json'), JSON.stringify(out, null, 1));
console.log(JSON.stringify(result.all2019_2024, null, 1));
