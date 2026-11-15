import test from 'node:test';
import assert from 'node:assert/strict';
import {
  DECISION_OFFSETS, TOLERANCE, mean, median, quantile, summarize, chooseOffset, pastYears, truncateBundle,
  decideOffset, overlapDays, winTieLoss, aggregateMetrics, aquacropMetrics,
} from '../web/js/model/decision.js';

const close = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) <= eps, `${a} != ${b}`);

test('the fixed design: feasible delays 0..30 every 5 days, tolerance 0.001', () => {
  assert.deepEqual(DECISION_OFFSETS, [0, 5, 10, 15, 20, 25, 30]);
  assert.equal(TOLERANCE, 0.001);
});

test('median / mean / quantile by hand (linear interpolation between order statistics)', () => {
  assert.equal(median([5, 1, 3]), 3);
  assert.equal(median([4, 1, 3, 2]), 2.5);
  assert.equal(median([]), null);
  close(mean([1, 2, 6]), 3);
  close(quantile([5, 4, 3, 2, 1], 0.2), 1.8); // position 4*0.2 = 0.8 -> 1 + 0.8*(2-1)
  close(quantile([10, 20], 0.2), 12);
  close(quantile([7], 0.2), 7);
  assert.equal(quantile([], 0.2), null);
});

test('summarize: typical = median, cautious = 20th percentile; unknown priority throws', () => {
  assert.equal(summarize([0.5, 0.6, 0.7], 'typical'), 0.6);
  close(summarize([0.5, 0.6, 0.7], 'cautious'), 0.54);
  assert.throws(() => summarize([1], 'greedy'), /priority/);
});

test('chooseOffset: highest summary wins', () => {
  assert.equal(chooseOffset([{ offset: 0, value: 0.5 }, { offset: 5, value: 0.7 }, { offset: 10, value: 0.6 }]), 5);
});

test('chooseOffset: a tie goes to the offset closest to 0 (also under float noise)', () => {
  assert.equal(chooseOffset([{ offset: 0, value: 0.5 }, { offset: 10, value: 0.7 }, { offset: 5, value: 0.7 }, { offset: 15, value: 0.6 }]), 5);
  assert.equal(chooseOffset([{ offset: 20, value: 0.8 }, { offset: 10, value: 0.8 }]), 10);
  assert.equal(chooseOffset([{ offset: 25, value: 0.1 + 0.2 }, { offset: 15, value: 0.3 }]), 15);
  assert.equal(chooseOffset([{ offset: 5, value: 0.4 }, { offset: -5, value: 0.4 }]), -5); // equally close: the earlier one
  assert.throws(() => chooseOffset([]), /no offset/);
  assert.throws(() => chooseOffset([{ offset: 0, value: Number.NaN }]), /no offset/);
});

test('pastYears keeps only years before the target', () => {
  assert.deepEqual(pastYears([2001, 2002, 2003, 2004], 2003), [2001, 2002]);
  assert.deepEqual(pastYears([2001, 2002], 2001), []);
});

test('truncateBundle: dates and daily arrays stop on 31 March of the target year; scalars stay; rainAlt is dropped', () => {
  const dates = [];
  for (let t = Date.UTC(2001, 0, 1); t <= Date.UTC(2004, 11, 31); t += 864e5) dates.push(new Date(t).toISOString().slice(0, 10));
  const rain = dates.map((_, i) => i);
  const b = { dates, rain, tmax: dates.map(() => 30), elevation: 1500, rainSource: 'ERA5', rainAlt: { IMERG: rain }, sources: ['a', 'b'] };
  const t = truncateBundle(b, 2003);
  assert.equal(t.dates.at(-1), '2003-03-31');
  assert.equal(t.dates.length, dates.indexOf('2003-04-01'));
  assert.equal(t.rain.length, t.dates.length);
  assert.equal(t.tmax.length, t.dates.length);
  assert.equal(t.elevation, 1500);
  assert.equal(t.rainSource, 'ERA5');
  assert.equal('rainAlt' in t, false);
  assert.equal(b.dates.length, dates.length); // the input is not mutated
  assert.throws(() => truncateBundle(b, 1999), /before/);
});

// Past years 2001..2003, target 2004. Offset 10: values .1, 1.0, .9 -> median .9, p20 .42;
// offset 5: .4, .9, .8 -> median .8, p20 .56; offset 0: .5, .6, .7 -> median .6, p20 .54.
const past = [
  [0, 2001, 0.5], [0, 2002, 0.6], [0, 2003, 0.7],
  [5, 2001, 0.4], [5, 2002, 0.9], [5, 2003, 0.8],
  [10, 2001, 0.1], [10, 2002, 1.0], [10, 2003, 0.9],
];
const rows = (extra = []) => [...past, ...extra].map(([offset, year, value]) => ({ offset, year, value }));

test('decideOffset: typical picks the best median, cautious the best 20th percentile', () => {
  assert.equal(decideOffset({ outcomes: rows(), targetYear: 2004, priority: 'typical' }), 10);
  assert.equal(decideOffset({ outcomes: rows(), targetYear: 2004, priority: 'cautious' }), 5);
});

test('information rule: data of the target year and later cannot change the decision', () => {
  const future = [[10, 2004, 0], [10, 2005, 0], [0, 2004, 1], [0, 2005, 1], [0, 2006, 1], [5, 2004, 0.01], [30, 2004, 1], [30, 2005, 1], [30, 2006, 1]];
  for (const priority of ['typical', 'cautious']) {
    const a = decideOffset({ outcomes: rows(), targetYear: 2004, priority });
    const b = decideOffset({ outcomes: rows(future), targetYear: 2004, priority });
    assert.equal(a, b);
  }
  // control: the same rows DO change the answer for a later target year (they are used once they are past)
  assert.notEqual(decideOffset({ outcomes: rows(future), targetYear: 2007, priority: 'typical' }), 10);
});

test('decideOffset: restricts to the offsets given and needs at least one past year', () => {
  assert.equal(decideOffset({ outcomes: rows(), targetYear: 2004, priority: 'typical', offsets: [0, 5] }), 5);
  assert.throws(() => decideOffset({ outcomes: rows(), targetYear: 2001, priority: 'typical' }), /past year/);
});

test('overlapDays: from the later sowing to the earlier harvest, never negative', () => {
  assert.equal(overlapDays({ sowDate: '2020-05-20', harvestDate: '2020-09-10' }, { sowDate: '2020-09-01', harvestDate: '2020-12-01' }), 9);
  assert.equal(overlapDays({ sowDate: '2020-05-20', harvestDate: '2020-08-20' }, { sowDate: '2020-09-01', harvestDate: '2020-12-01' }), 0);
});

test('winTieLoss: gains beyond the tolerance win or lose, the rest tie', () => {
  assert.deepEqual(winTieLoss([0.1, 0.001, -0.001, 0, -0.05, 0.0011], 0.001), { win: 2, tie: 3, loss: 1, n: 6 });
});

const R = (o) => ({ offset: 0, simOffset: 0, wi: 0, wiBase: 0, wiOracle: 0, maize: 0, maizeBase: 0, overlap: 0, overlapBase: 0, wiSim: 0, maizeSim: 0, ...o });

test('aggregateMetrics by hand', () => {
  const m = aggregateMetrics([
    R({ offset: 10, simOffset: 10, wi: 0.80, wiBase: 0.70, wiOracle: 0.85, maize: 0.90, maizeBase: 0.80, overlap: 20, overlapBase: 10, wiSim: 0.80, maizeSim: 0.90 }),
    R({ offset: 0, simOffset: 5, wi: 0.60, wiBase: 0.60, wiOracle: 0.70, maize: 0.50, maizeBase: 0.50, overlap: 10, overlapBase: 10, wiSim: 0.65, maizeSim: 0.55 }),
    R({ offset: 5, simOffset: 5, wi: 0.50, wiBase: 0.55, wiOracle: 0.55, maize: 0.40, maizeBase: 0.45, overlap: 30, overlapBase: 10, wiSim: 0.50, maizeSim: 0.40 }),
  ]);
  assert.equal(m.n, 3);
  assert.deepEqual(m.offsets, { 0: 1, 5: 1, 10: 1 });
  const w = m.waterIndex;
  close(w.chosenMean, 0.6333333333); close(w.baselineMean, 0.6166666667); close(w.oracleMean, 0.7);
  close(w.meanGain, 0.0166666667); close(w.meanRegret, 0.0666666667);
  assert.deepEqual([w.win, w.tie, w.loss], [1, 1, 1]);
  close(w.chosenWorst, 0.5); close(w.baselineWorst, 0.55);
  close(w.chosenP10, 0.52); close(w.baselineP10, 0.56);
  assert.deepEqual([m.maize.win, m.maize.tie, m.maize.loss], [1, 1, 1]);
  close(m.maize.meanGain, 0.0166666667);
  assert.equal(m.overlapMedian.chosen, 20); assert.equal(m.overlapMedian.baseline, 10);
  assert.equal(m.agreement.sameOffset, 2);
  close(m.agreement.meanWaterIndexDiff, -0.0166666667);
  close(m.agreement.meanMaizeDiff, 0.0166666667 * 0 + (0 - 0.05 + 0) / 3);
  assert.equal(m.indexUpMaizeDown, 0);
});

test('aggregateMetrics counts cases where the rotation index improves while the maize gets worse', () => {
  const m = aggregateMetrics([
    R({ offset: 20, wi: 0.80, wiBase: 0.70, maize: 0.50, maizeBase: 0.60 }),
    R({ offset: 20, wi: 0.80, wiBase: 0.70, maize: 0.65, maizeBase: 0.60 }),
  ]);
  assert.equal(m.indexUpMaizeDown, 1);
});

test('aquacropMetrics by hand: gain, pooled percentage, win/tie/loss and simulator-only wins', () => {
  const m = aquacropMetrics([
    { id: 'a', aq: 6.0, aqBase: 5.0, simMaizeGain: 0.10 },
    { id: 'b', aq: 4.9, aqBase: 5.0, simMaizeGain: 0.05 },
    { id: 'c', aq: 5.0, aqBase: 5.0, simMaizeGain: 0 },
    { id: 'd', aq: 5.5, aqBase: 5.0, simMaizeGain: -0.02 },
  ]);
  assert.equal(m.n, 4);
  close(m.meanGainTHa, 0.35); close(m.meanGainPct, 7);
  assert.deepEqual([m.win, m.tie, m.loss], [2, 1, 1]);
  assert.equal(m.simulatorOnlyWins.count, 1);
  assert.deepEqual(m.simulatorOnlyWins.ids, ['b']);
});
