import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { scoreActions, loadScorerContext } from '../scripts/compare/score_actions.mjs';
import { loadSimulator, simulate } from '../scripts/referee/compare.mjs';
import { computeEt0Series, runSequence, resolveMainSowIdx, agriculturalYears } from '../web/js/model/simulate.js';
import { targetsOf } from '../web/js/model/emulator.js';

const here = (p) => fileURLToPath(new URL(p, import.meta.url));
const ctx = loadScorerContext();
const example = JSON.parse(readFileSync(here('../scripts/compare/example_actions.json'), 'utf8'));
const base = { id: 'a1', site: 'chiquimula', year: 2020, texture: 'loam', slopeClass: 'flat', irrigation: 'none', sequenceId: 'actual', sowOffsetDays: 0 };
const single = { id: 'a1', site: 'chiquimula', year: 2020, texture: 'loam', slopeClass: 'flat', irrigation: 'none', crop: 'maiz', sowDate: '06-01' };
const rejects = (action, pattern) => assert.throws(() => scoreActions({ actions: [action] }, ctx), (e) => /"a1"/.test(e.message) && pattern.test(e.message), `${JSON.stringify(action)} should be rejected with ${pattern}`);

test('the example file scores both actions with every field the protocol promises', () => {
  const { results } = scoreActions(example, ctx);
  assert.deepEqual(results.map((r) => r.id), ['ejemplo_rotacion', 'ejemplo_un_cultivo']);
  const [rot, one] = results;
  assert.equal(rot.kind, 'rotation');
  assert.deepEqual(rot.crops.map((c) => c.cropId), ['maiz', 'frijol']);
  for (const c of rot.crops) {
    assert.match(c.sowDate, /^\d{4}-\d\d-\d\d$/);
    assert.match(c.harvestDate, /^\d{4}-\d\d-\d\d$/);
    assert.equal(typeof c.relYield, 'number');
    assert.equal(typeof c.cycleIncomplete, 'boolean');
  }
  for (const k of ['waterIndex', 'ksFlowerMain', 'bareFrac']) assert.equal(typeof rot[k], 'number');
  assert.equal(typeof rot.overlapDays[0], 'number');
  assert.equal(one.kind, 'single-crop');
  assert.equal(one.crops.length, 1);
  assert.equal(one.crops[0].sowDate, '2020-06-05');
  assert.equal(one.soil, 'site');
});

test('a rotation action equals runSequence directly (rotation index = mean of the food crops, incomplete cycles count 0)', () => {
  const b = ctx.bundles.chiquimula;
  const res = runSequence({ sequence: ctx.sequences.actual, bundle: b, et0: computeEt0Series(b), crops: ctx.crops, texture: 'loam', slopeClass: 'flat', irrigation: 'none', sowOffsetDays: 10 })
    .find((r) => r.year === 2021);
  const t = targetsOf(res);
  const { results } = scoreActions({ actions: [{ ...base, year: 2021, sowOffsetDays: 10 }] }, ctx);
  assert.equal(results[0].waterIndex, t[0]);
  assert.equal(results[0].ksFlowerMain, t[1]);
  assert.equal(results[0].bareFrac, t[2]);
  assert.equal(results[0].crops[0].relYield, res.crops[0].relYield);
  assert.equal(results[0].crops[0].sowDate, res.crops[0].sowDate);
});

test('a single-crop action gives the same relYield as the referee single-crop path (compare.mjs simulate)', async () => {
  const sim = await loadSimulator(here('../'));
  const b = ctx.bundles.chiquimula;
  const ref = simulate(sim, b, computeEt0Series(b), { id: 'r', crop: 'Maize', sowDate: '05-25', soil: 'Loam' }).find((r) => r.year === 2022);
  const { results } = scoreActions({ actions: [{ ...single, year: 2022, sowDate: '05-25' }] }, ctx);
  assert.equal(results[0].crops[0].relYield, ref.relYield);
  assert.equal(results[0].crops[0].ksFlowerMean, ref.ks);
  assert.equal(results[0].crops[0].cycleIncomplete, ref.incomplete);
  assert.equal(results[0].waterIndex, ref.incomplete ? 0 : ref.relYield);
});

test('a cycle that does not finish is flagged and counts 0 in the water index', () => {
  const { results } = scoreActions({ actions: [{ ...single, sowDate: '03-20' }] }, ctx);
  assert.equal(results[0].crops[0].cycleIncomplete, true);
  assert.equal(results[0].crops[0].effectiveRelYield, 0);
  assert.equal(results[0].waterIndex, 0);
  assert.equal(results[0].cycleIncomplete, true);
});

test('a rotation that needs irrigation is scored when irrigation is allowed, and rejected with irrigation none', () => {
  const ok = scoreActions({ actions: [{ ...base, sequenceId: 'extra_riego', irrigation: 'full' }] }, ctx);
  assert.equal(ok.results[0].crops.length, 3);
  rejects({ ...base, sequenceId: 'extra_riego' }, /irrigation/);
});

test('rejections name the action id and say what is wrong', () => {
  rejects({ ...base, site: 'zacapa' }, /unknown site/);
  rejects({ ...base, year: 1999 }, /year/);
  rejects({ ...base, year: 2030 }, /year/);
  rejects({ ...base, year: 2020.5 }, /year/);
  rejects({ ...base, texture: 'silt' }, /texture/);
  rejects({ ...base, soil: 'site' }, /texture.*soil|soil.*texture/);
  rejects({ ...base, texture: undefined }, /texture|soil/);
  rejects({ ...base, slopeClass: 'cliff' }, /slopeClass/);
  rejects({ ...base, irrigation: 'rain' }, /irrigation/);
  rejects({ ...base, sequenceId: 'inventada' }, /sequenceId/);
  rejects({ ...base, sowOffsetDays: 2.5 }, /sowOffsetDays/);
  rejects({ ...base, sowOffsetDays: undefined }, /sowOffsetDays/);
  rejects({ ...base, crop: 'maiz', sowDate: '06-01' }, /either|both/);
  rejects({ ...single, crop: 'arroz' }, /crop/);
  rejects({ ...single, sowDate: '02-30' }, /sowDate/);
  rejects({ ...single, sowDate: '5/20' }, /sowDate/);
  rejects({ ...single, crop: undefined }, /crop/);
  rejects({ ...base, sowOfset: 3 }, /unknown field/);
  assert.throws(() => scoreActions({ actions: [{ ...base, id: undefined }] }, ctx), /action #1.*id/);
  assert.throws(() => scoreActions({ actions: [base, base] }, ctx), /duplicate id "a1"/);
  assert.throws(() => scoreActions({ actions: 'x' }, ctx), /"actions" must be a list/);
  assert.throws(() => scoreActions({ actions: [] }, ctx), /no actions/);
  assert.throws(() => scoreActions({ actions: [null] }, ctx), /action #1/);
});

test('all rejections are reported together, not just the first', () => {
  assert.throws(() => scoreActions({ actions: [{ ...base, id: 'x', site: 'nowhere' }, { ...base, id: 'y', year: 1990 }] }, ctx),
    (e) => /"x"/.test(e.message) && /"y"/.test(e.message));
});

test('the CLI scores the example file and prints JSON', () => {
  const out = execFileSync(process.execPath, [here('../scripts/compare/score_actions.mjs'), '--in', here('../scripts/compare/example_actions.json')], { encoding: 'utf8' });
  assert.deepEqual(JSON.parse(out).results, scoreActions(example, ctx).results);
});

test('the CLI fails with a message when the input file does not exist', () => {
  assert.throws(() => execFileSync(process.execPath, [here('../scripts/compare/score_actions.mjs'), '--in', here('./no_such_actions.json')], { encoding: 'utf8', stdio: 'pipe' }), /no_such_actions/);
});

test('an offset that would push the sowing outside the agricultural year is rejected (no silent clamping); the range edges are accepted', () => {
  const b = ctx.bundles.chiquimula;
  const onset = resolveMainSowIdx(b, 2021, 0).idx;
  const hi = agriculturalYears(b.dates).find((y) => y.year === 2021).endIdx - agriculturalYears(b.dates).find((y) => y.year === 2021).startIdx - onset;
  const at = (n) => ({ ...base, year: 2021, sowOffsetDays: n });
  rejects(at(400), /outside the agricultural year.*range is -\d+ to \d+/);
  rejects(at(hi + 1), /outside the agricultural year/);
  rejects(at(-onset - 1), /outside the agricultural year/);
  const edge = scoreActions({ actions: [at(hi), { ...at(-onset), id: 'a2' }] }, ctx).results;
  assert.equal(edge[0].crops[0].sowDate, '2022-03-31');
  assert.equal(edge[1].crops[0].sowDate, '2021-04-01');
});
