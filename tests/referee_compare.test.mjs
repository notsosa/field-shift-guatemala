import test from 'node:test';
import assert from 'node:assert/strict';
import { averageRanks, spearman, worstK, overlap, cv, rankOf, countAtOne, quantile, caseMetrics } from '../scripts/referee/compare.mjs';

const near = (a, b, tol = 1e-9) => assert.ok(Math.abs(a - b) < tol, `${a} != ${b}`);

test('averageRanks: ties share the mean position', () => {
  assert.deepEqual(averageRanks([10, 20, 20, 30]), [1, 2.5, 2.5, 4]);
  assert.deepEqual(averageRanks([5, 5, 5]), [2, 2, 2]);
});

test('spearman: monotone, reversed, and with ties (hand-computed)', () => {
  near(spearman([1, 2, 3, 4], [10, 20, 30, 40]), 1);
  near(spearman([1, 2, 3, 4], [4, 3, 2, 1]), -1);
  // ranks a = 1,2,3,4 ; ranks b = 1,2.5,2.5,4 -> cov 4.5, var a 5, var b 4.5 -> 4.5/sqrt(22.5)
  near(spearman([1, 2, 3, 4], [1, 2, 2, 3]), 4.5 / Math.sqrt(22.5));
  assert.equal(spearman([1, 2, 3], [7, 7, 7]), null);
});

test('worstK / overlap: lowest k with tiebreak, then overlap count', () => {
  const years = [2001, 2002, 2003, 2004, 2005];
  assert.deepEqual(worstK([5, 1, 3, 2, 4], years, 2), [2002, 2004]);
  // all tied at 1: the tiebreak (smaller is worse) picks 2003 (1) and 2005 (2)
  assert.deepEqual(worstK([1, 1, 1, 1, 1], years, 2, [9, 8, 1, 7, 2]), [2003, 2005]);
  assert.equal(overlap([2002, 2004, 2005], [2004, 2005, 2001]), 2);
});

test('cv: sample standard deviation over mean', () => {
  // values 2,4,4,4,5,5,7,9: mean 5, sum of squared deviations 32, sample sd sqrt(32/7)
  near(cv([2, 4, 4, 4, 5, 5, 7, 9]), Math.sqrt(32 / 7) / 5);
});

test('rankOf (1 = worst, ties take the lowest rank), countAtOne, quantile', () => {
  const years = [1, 2, 3, 4];
  assert.equal(rankOf([0.5, 1, 1, 0.2], years, 2), 3);
  assert.equal(rankOf([0.5, 1, 1, 0.2], years, 4), 1);
  assert.equal(countAtOne([1, 0.99995, 0.9, 1]), 3);
  near(quantile([1, 2, 3, 4, 5], 0.5), 3);
  near(quantile([0, 10], 0.1), 1);
});

test('caseMetrics assembles the agreement numbers', () => {
  const years = [2013, 2014, 2015, 2016, 2017, 2018, 2019];
  const aq = [9, 2, 1, 8, 7, 5, 3];
  const sim = [1, 0.8, 0.7, 1, 1, 0.9, 0.85];
  const ks = [1, 0.6, 0.5, 1, 1, 0.8, 0.7];
  const m = caseMetrics(years.map((year, i) => ({ year, aq: aq[i], sim: sim[i], ks: ks[i] })));
  assert.equal(m.n, 7);
  assert.deepEqual(m.worst5.aquacrop, [2014, 2015, 2017, 2018, 2019]);
  // simulator: 2015 (.7), 2014 (.8), 2019 (.85), 2018 (.9), then the 1.0 tie broken by ks (all equal) -> first year, 2013
  assert.deepEqual(m.worst5.simulator, [2013, 2014, 2015, 2018, 2019]);
  assert.equal(m.worst5.overlap, 4);
  assert.equal(m.simYearsAtOne, 3);
  assert.deepEqual(m.droughtRanks[2015], { aquacrop: 1, simulator: 1 });
  assert.deepEqual(m.droughtRanks[2014], { aquacrop: 2, simulator: 2 });
  assert.deepEqual(m.droughtRanks[2018], { aquacrop: 4, simulator: 4 });
  assert.equal(m.droughtRanks[2013], undefined);
});

import { resolveSiteCases } from '../scripts/referee/resolve_site_cases.mjs';

test('resolveSiteCases: soil "site" becomes the pilot theta pair for AquaCrop and keeps the site id for the simulator', () => {
  const points = [{ id: 'chiquimula', soil: { thetaFC: 0.3296, thetaWP: 0.1795, label: 'x', source: 's', cn: { crop: 89, residue: 85, bare: 94 } } }, { id: 'zacapa' }];
  const cases = [
    { id: 'a', crop: 'Maize', sowDate: '05-20', years: '2001-2024', soil: 'Loam', initial: 'dry' },
    { id: 'a_site', crop: 'Maize', sowDate: '05-20', years: '2001-2024', soil: 'site', site: 'chiquimula', initial: 'dry' },
  ];
  const out = resolveSiteCases(cases, points);
  assert.deepEqual(out[0], cases[0]);
  assert.deepEqual(out[1].soil, { thetaFC: 0.3296, thetaWP: 0.1795 });
  assert.equal(out[1].site, 'chiquimula');
  assert.equal(cases[1].soil, 'site'); // the input is not mutated
});

test('resolveSiteCases: a pilot without soil, or a site case without site, throws', () => {
  const points = [{ id: 'zacapa' }];
  assert.throws(() => resolveSiteCases([{ id: 'b', soil: 'site', site: 'zacapa' }], points), /zacapa/);
  assert.throws(() => resolveSiteCases([{ id: 'c', soil: 'site' }], points), /site/);
});
