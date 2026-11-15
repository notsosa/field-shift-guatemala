import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  SITES, TARGET_YEARS, POLICIES, ENGINES, loadContext, pastData, decideAll, maizeSowDate, aquacropCases, mergeAquacrop,
} from '../scripts/compare/sowing_policy.mjs';
import { DECISION_OFFSETS } from '../web/js/model/decision.js';
import { resolveMainSowIdx } from '../web/js/model/simulate.js';

const ctx = loadContext();

/** Copia del bundle con datos absurdos desde el 1 de abril de `year` en adelante. */
function corruptFrom(bundle, year, fill) {
  const cut = bundle.dates.indexOf(`${year}-04-01`);
  const b = { ...bundle };
  for (const k of ['rain', 'tmax', 'tmin', 'tdew', 'rs', 'u2']) b[k] = bundle[k].map((v, i) => (i < cut ? v : fill[k]));
  return b;
}
const DRY_HOT = { rain: 0, tmax: 45, tmin: 30, tdew: 5, rs: 30, u2: 4 };
const FLOOD = { rain: 300, tmax: 22, tmin: 18, tdew: 21, rs: 5, u2: 1 };

test('information rule (real engines): changing the data of year Y and later leaves the decision for Y unchanged', () => {
  for (const [site, year, soil] of [['chiquimula', 2021, 'loam'], ['jutiapa', 2019, 'site'], ['sanmartin', 2024, 'clay']]) {
    const base = decideAll(ctx, site, year, soil);
    for (const fill of [DRY_HOT, FLOOD]) {
      const ctx2 = { ...ctx, bundles: { ...ctx.bundles, [site]: corruptFrom(ctx.bundles[site], year, fill) } };
      assert.deepEqual(decideAll(ctx2, site, year, soil), base, `${site} ${year} ${soil}`);
    }
  }
});

test('information rule: the corruption is material (a LATER target year, which may use year Y, sees different outcomes)', () => {
  const site = 'chiquimula';
  const year = 2021;
  const ctx2 = { ...ctx, bundles: { ...ctx.bundles, [site]: corruptFrom(ctx.bundles[site], year, DRY_HOT) } };
  const soil = { simSoil: 'loam', emuTexture: 'loam' };
  for (const policy of POLICIES) {
    const a = ENGINES[policy](ctx, pastData(ctx.bundles[site], year + 1), soil).filter((o) => o.year === year);
    const b = ENGINES[policy](ctx2, pastData(ctx2.bundles[site], year + 1), soil).filter((o) => o.year === year);
    assert.equal(a.length, DECISION_OFFSETS.length);
    assert.notDeepEqual(a, b, policy);
  }
});

test('pastData: only complete agricultural years before the target, and the bundle ends on 31 March of the target year', () => {
  const p = pastData(ctx.bundles.chiquimula, 2019);
  assert.equal(p.bundle.dates.at(-1), '2019-03-31');
  assert.deepEqual(p.years, Array.from({ length: 18 }, (_, i) => 2001 + i));
  assert.equal(p.et0.length, p.bundle.dates.length);
  assert.equal('rainAlt' in p.bundle, false);
});

test('maizeSowDate follows resolveMainSowIdx; AquaCrop cases cover 3 sites x 6 years x 7 delays with the site soil resolved', () => {
  const b = ctx.bundles.jutiapa;
  const i = resolveMainSowIdx(b, 2020, 10).idx;
  assert.equal(maizeSowDate(b, 2020, 10), b.dates[b.dates.indexOf('2020-04-01') + i].slice(5));
  assert.equal(maizeSowDate(b, 2020, 10) > maizeSowDate(b, 2020, 0), true);
  const points = JSON.parse(readFileSync(new URL('../scripts/emulator/points.json', import.meta.url), 'utf8'));
  const cases = aquacropCases(ctx, 'jutiapa', points);
  assert.equal(cases.length, TARGET_YEARS.length * DECISION_OFFSETS.length);
  const soil = points.find((p) => p.id === 'jutiapa').soil;
  assert.deepEqual(cases[0].soil, { thetaFC: soil.thetaFC, thetaWP: soil.thetaWP });
  assert.equal(cases[0].site, 'jutiapa');
  assert.deepEqual(cases[0].years, [2019]);
});

test('mergeAquacrop fails loudly on a missing case, a missing yield or a different sowing date', () => {
  const site = 'chiquimula';
  const mk = () => ({ id: `${site}_2019_site`, site, year: 2019, soil: 'site', truth: Object.fromEntries(DECISION_OFFSETS.map((o) => [o, { maizeSowDate: `2019-${maizeSowDate(ctx.bundles[site], 2019, o)}` }])) });
  const aqCases = () => DECISION_OFFSETS.map((o) => ({ id: `${site}_2019_o${o}`, sowDate: maizeSowDate(ctx.bundles[site], 2019, o), results: [{ year: 2019, yieldTHa: 5 + o / 10 }] }));
  const good = mk();
  mergeAquacrop([good], { [site]: { cases: aqCases() } }, ctx);
  assert.equal(good.aquacrop[10], 6);
  assert.throws(() => mergeAquacrop([mk()], { [site]: { cases: aqCases().slice(1) } }, ctx), /is missing/);
  const noYield = aqCases(); noYield[2].results[0].yieldTHa = null;
  assert.throws(() => mergeAquacrop([mk()], { [site]: { cases: noYield } }, ctx), /no yield/);
  const wrongDate = aqCases(); wrongDate[3].sowDate = '01-01';
  assert.throws(() => mergeAquacrop([mk()], { [site]: { cases: wrongDate } }, ctx), /sowed on/);
  assert.throws(() => mergeAquacrop([mk()], {}, ctx), /missing/);
});

test('the sites and years are the fixed design', () => {
  assert.deepEqual(SITES, ['chiquimula', 'jutiapa', 'sanmartin']);
  assert.deepEqual(TARGET_YEARS, [2019, 2020, 2021, 2022, 2023, 2024]);
});
