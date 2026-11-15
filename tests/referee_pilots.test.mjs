import test from 'node:test';
import assert from 'node:assert/strict';
import { validYearsOf, rainVariant } from '../scripts/referee/pilots.mjs';

const dates = [];
for (let t = Date.UTC(2001, 0, 1); t <= Date.UTC(2003, 11, 31); t += 864e5) dates.push(new Date(t).toISOString().slice(0, 10));

test('validYearsOf: complete agricultural years (1 Apr Y .. 31 Mar Y+1) without a missing rain day', () => {
  const ok = dates.map(() => 1);
  assert.deepEqual(validYearsOf(dates, ok), [2001, 2002]); // 2003 has no 31 Mar 2004
  const gap = [...ok];
  gap[dates.indexOf('2002-06-30')] = null; // inside the agricultural year 2002
  assert.deepEqual(validYearsOf(dates, gap), [2001]);
  const early = [...ok];
  early[dates.indexOf('2002-02-10')] = null; // Feb 2002 belongs to the agricultural year 2001
  assert.deepEqual(validYearsOf(dates, early), [2002]);
  const outside = [...ok];
  outside[dates.indexOf('2001-02-01')] = null; // before 1 Apr 2001: in no complete year
  assert.deepEqual(validYearsOf(dates, outside), [2001, 2002]);
});

test('rainVariant: swaps only the rain series, gap days become 0 and nothing else changes', () => {
  const bundle = { dates: ['a', 'b', 'c'], rain: [1, 2, 3], tmax: [30, 30, 30], rainSource: 'ERA5' };
  const v = rainVariant(bundle, [0.5, null, 4]);
  assert.deepEqual(v.rain, [0.5, 0, 4]);
  assert.deepEqual(v.tmax, bundle.tmax);
  assert.deepEqual(bundle.rain, [1, 2, 3]);
});

import { readFileSync } from 'node:fs';
const artifact = JSON.parse(readFileSync(new URL('../web/data/referee_aquacrop.json', import.meta.url), 'utf8'));

test('referee_aquacrop.json: four stages in order, same AquaCrop numbers, the old before/after keys are gone', () => {
  assert.deepEqual(artifact.stages.map((s) => s.label), ['pre-subsoil', 'subsoil', 'stage-ky', 'final']);
  assert.equal(artifact.before, undefined);
  assert.equal(artifact.after, undefined);
  for (const s of artifact.stages) {
    assert.ok(s.cases.maiz_0520 && s.cases.frijol_0901 && s.sowingCurve.points.length > 0, s.label);
    // AquaCrop is the same run for every stage
    assert.equal(s.cases.maiz_0520.cv.aquacrop, artifact.stages[0].cases.maiz_0520.cv.aquacrop);
  }
  assert.ok(artifact.stages[3].cases.maiz_0520_site);
  assert.ok(artifact.stages[0].skipped.maiz_0520_site); // old revisions cannot take a soil object
});

test('referee_aquacrop.json: pilots carry soilClassError for sand, loam and clay and name the closest class', () => {
  for (const id of ['chiquimula', 'jutiapa', 'sanmartin']) {
    const e = artifact.pilots[id].soilClassError;
    for (const k of ['sand', 'loam', 'clay']) assert.ok(e[k] >= 0, `${id}.${k}`);
    assert.equal(e.closest, ['sand', 'loam', 'clay'].sort((a, b) => e[a] - e[b])[0]);
    assert.equal(e.nearestTextureIsClosest, e.closest === artifact.pilots[id].soil.nearestTexture);
  }
});

test('referee_aquacrop.json: rain sensitivity uses only years complete in every product and never POWER', () => {
  const s = artifact.rainSensitivity;
  assert.deepEqual(Object.keys(s.vsAquacrop), ['ERA5', 'IMERG', 'CHIRPS']);
  for (const p of Object.values(s.excludedYears)) for (const y of p) assert.ok(!s.years.includes(y));
  assert.ok(s.excludedYears.IMERG.includes(2019) && s.excludedYears.IMERG.includes(2024));
  assert.equal(s.nYears, s.years.length);
});
