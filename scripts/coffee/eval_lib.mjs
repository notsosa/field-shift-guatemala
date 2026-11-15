// Medidas de una política de riego del café (Tarea 32). Puro. Cada caso: { rule (0/1), avoided, stressNo, stressYes }; irr = decisión (0/1); priority = 0 | 1.
import { PRICE } from '../../web/js/model/coffee.js';

export const priceOf = (p) => PRICE[p];
export const TOL = 1e-9;
const mean = (a) => (a.length ? a.reduce((x, y) => x + y, 0) / a.length : null);
const rate = (num, den) => ({ count: num, of: den, rate: den ? num / den : null });

/** Utilidad de una decisión: regar = evitados − precio; no regar = 0. */
export const utilityOf = (irr, s, p) => (irr ? s.avoided - PRICE[p] : 0);
export const oracleIrrigates = (s, p) => s.avoided - PRICE[p] > 0; // empate (utilidad 0) → no regar

/** list = escenarios; irrs = decisiones (0/1) en el mismo orden. */
export function metrics(list, irrs, p) {
  const n = list.length;
  if (n === 0) return null;
  const u = list.map((s, i) => utilityOf(irrs[i], s, p));
  const ur = list.map((s) => utilityOf(s.rule, s, p));
  const uo = list.map((s) => Math.max(0, s.avoided - PRICE[p]));
  const d = u.map((x, i) => x - ur[i]);
  const irrigated = list.filter((_, i) => irrs[i] === 1);
  const neededIdx = list.map((s, i) => i).filter((i) => oracleIrrigates(list[i], p));
  return {
    n,
    meanUtility: mean(u), ruleMeanUtility: mean(ur), oracleMeanUtility: mean(uo),
    gainVsRule: mean(d), win: d.filter((x) => x > TOL).length, tie: d.filter((x) => Math.abs(x) <= TOL).length, loss: d.filter((x) => x < -TOL).length,
    regretVsOracle: mean(uo.map((x, i) => x - u[i])),
    irrigations: irrigated.length,
    wasted: rate(irrigated.filter((s) => s.avoided <= PRICE[p]).length, irrigated.length),
    missed: rate(neededIdx.filter((i) => irrs[i] === 0).length, neededIdx.length),
    stressDaysLeft: mean(list.map((s, i) => (irrs[i] ? s.stressYes : s.stressNo))),
    stressDaysNoIrrigation: mean(list.map((s) => s.stressNo)),
    departsFromRule: irrs.filter((x, i) => x !== list[i].rule).length,
  };
}
