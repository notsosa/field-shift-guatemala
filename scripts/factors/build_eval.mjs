// Tarea 36: junta las partes en web/data/factors_eval.json (tabla de factores, conteo de calor, eventos reales antes/después, decisiones de pérdida del maíz y del café).
// Uso (en orden): node scripts/factors/heat_counts.mjs; node scripts/compare/real_events_check.mjs --heat; node scripts/factors/loss_constraints.mjs; node scripts/factors/coffee_notices.mjs; node scripts/factors/build_eval.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FERTILITY_CLASSES, HEAT_CROPS, HEAT_RANGE_C, LOGISTIC_STEEPNESS, LOBELL, PEST_NOTE, MONEY_NOTE } from '../../web/js/model/factors.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const rd = (f) => JSON.parse(fs.readFileSync(path.join(root, f), 'utf8'));
const heat = rd('scripts/factors/out/factors_heat_counts.json');
const loss = rd('scripts/factors/out/factors_loss.json');
const coffee = rd('scripts/factors/out/factors_coffee.json');
const evWater = rd('web/data/real_events_check.json');
const evHeat = rd('web/data/factors_real_events_check.json');
const prices = rd('web/data/prices.json');

const evPick = (e) => {
  const s = e.summary.ERA5;
  return Object.fromEntries(['A', 'B', 'all'].map((p) => [p, {
    events: s[p].events, noEventYearsFlagged: s[p].noEventYearsFlagged, otherYearsFlagged: s[p].otherYearsFlagged,
    aucVsNoEventYears: s[p].aucVsNoEventYears, aucVsOtherYears: s[p].aucVsOtherYears,
  }]));
};
const SRC = {
  heat: 'AquaCrop Reference Manual v7.3 (FAO), Annex I (I.2 Maize 4.2 p.11; I.9 Tomato 4.2; Table 15 beans p.59) and Chapter 3, 3.12.5, Fig. 3.12k p.3-147; read from the PDF',
  fertility: 'AquaCrop Reference Manual v7.3, Chapter 2, Table 2.13a, p.2-188; read from the PDF',
  lobell: 'Lobell et al. 2011, Nature Climate Change 1:42-45, abstract read; full text not read; maize in Africa',
  prices: 'MAGA, El Agro en Cifras 2023, Tablas 22 and 26; wholesale La Terminal zona 4',
  rust: 'Avelino et al. 2015, Food Security 7:303-321; regional aggregate, uncertain estimates',
};
const out = {
  meta: { generated: new Date().toISOString().slice(0, 10), task: 36, rule: 'A factor enters the yield only with a published number read from the source itself; anything else stays a notice or a stated input. Nothing is tuned to the documented drought events. Opt-in: with no `factors` option every existing result is reproduced unchanged.', researchFile: 'research_notes/factores-rendimiento.json (outside the repo)' },
  factorTable: [
    { factor: 'Heat at flowering, maize and tomato', publishedNumber: true, enters: 'yield (opt-in): mean daily pollination coefficient over the flowering window multiplies the water-limited relative yield', numbers: { crops: HEAT_CROPS, rangeC: HEAT_RANGE_C, shape: 'logistic, 1 -> 0 over 5 C beyond the threshold', logisticSteepnessK: LOGISTIC_STEEPNESS, steepnessNote: 'our choice: the source gives the shape and the ends, not the steepness' }, source: SRC.heat, simplification: 'AquaCrop applies the coefficient to the reference harvest index; here the window mean multiplies the relative yield' },
    { factor: 'Heat, beans, coffee and the other crops', publishedNumber: false, enters: 'nothing (no factor)', note: 'Table 15 (dry beans) gives no pollination thresholds; coffee arabica has an optimum annual mean of 18-21 C and quality loss above 23 C (DaMatta & Ramalho 2006) but no yield loss per degree', source: SRC.heat },
    { factor: 'Heat sensitivity, maize (Lobell et al. 2011)', publishedNumber: true, enters: 'sensitivity only: off by default, never used in decisions', numbers: LOBELL, source: SRC.lobell, caveat: 'Africa, not Central America; linear and unbounded here, which is far outside the trial range for long hot cycles' },
    { factor: 'Soil fertility class', publishedNumber: true, enters: 'stated input (opt-in): multiplies the relative yield; not stated = 1', numbers: FERTILITY_CLASSES, source: SRC.fertility, caveat: 'generic, not calibrated for Guatemala; no source maps "fertilised / not fertilised" to a class, so none is invented' },
    { factor: 'Pests', publishedNumber: false, enters: 'notice only plus the stated observed level carried through and shown; yield unchanged', note: PEST_NOTE, source: SRC.rust },
    { factor: 'Money', publishedNumber: true, enters: 'recorded in web/data/prices.json as information; no margin computed', numbers: { maizeQ_per_qq_2023: prices.prices.maiz.value2023, beanQ_per_qq_2023: prices.prices.frijol.value2023 }, note: MONEY_NOTE, source: SRC.prices },
    { factor: 'Ability to act: canResow, hasIrrigation (and type)', publishedNumber: null, enters: 'stated constraints applied when choosing (canResow = false leaves only "leave the field"); not predictions', note: 'no data needed' },
  ],
  heat: { rule: heat.meta.rule, total: heat.total, totalByCalendar: heat.totalByCalendar, retrainNeeded: heat.retrainNeeded, byPoint: heat.byPoint, affectedSiteYears: heat.affectedSiteYears, meta: heat.meta },
  retrained: { anything: false, reason: `${heat.total.changeOver001} of ${heat.total.siteYears} maize site-years (${(100 * heat.total.shareChangeOver001).toFixed(2)} %) change by more than 0.01, below the 1 % rule; ${heat.total.hotDays} days of flowering windows reach Tmax above 40 C in 20 points x 24 years x 2 cycles, and all ${heat.total.siteYearsWithColdDay} affected site-years are cold nights (Tmin below 10 C) at the highland points; the factor is implemented but inactive for heat in this region and these years.` },
  realEvents: {
    method: 'scripts/compare/real_events_check.mjs (ERA5), same fixed thresholds (hit = worst third), nothing tuned; --heat adds the maize heat factor; fertility not stated; beans unchanged (no threshold)',
    waterOnly: evPick(evWater), withHeat: evPick(evHeat), counts: { waterOnly: evWater.counts, withHeat: evHeat.counts },
  },
  cropLoss: { meta: loss.meta, decision: loss.decision, sameChoiceAsNotStated: loss.sameChoiceAsNotStated },
  coffee: { meta: coffee.meta, all2019_2024: coffee.all2019_2024, reserved2022_2024: coffee.reserved2022_2024 },
  notComputed: [
    'Pest damage: no source gives a damage function (the 16 % fall of Central American coffee production in 2013 is a regional aggregate); pests do not change the yield.',
    'Fertiliser response in Guatemala: no published fertilised vs unfertilised number; only the generic AquaCrop classes, stated by the user.',
    'Margin: no production costs, no seed cost, no usable attainable yields; prices are wholesale, not farm-gate.',
    'Heat for beans and coffee: no threshold or loss per degree in the sources.',
    'Cutworm (cogollero) and the other pests: only search snippets, not verified, not used.',
  ],
  decisionMethod: 'One method: predict then choose (the backprop funnel network predicts the outcome of each option; the choice applies the priority and the stated constraints). The evolutionary recommender is archived as is, not trained or extended.',
};
fs.writeFileSync(path.join(root, 'web/data/factors_eval.json'), JSON.stringify(out, null, 1));
console.log('factors_eval.json written', JSON.stringify(out.realEvents.waterOnly.all.events), JSON.stringify(out.realEvents.withHeat.all.events));
