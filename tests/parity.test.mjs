// Tabla de paridad (Tarea 38): cada entrada de las tres redes está clasificada y los nombres coinciden con los archivos de las redes.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { FEATURE_NAMES_V3 } from '../web/js/model/emulatorV3.js';

const load = (f) => JSON.parse(readFileSync(new URL(`../web/data/${f}`, import.meta.url)));
const par = load('parity.json');

test('paridad: los nombres de cada red coinciden con sus archivos y todas tienen clase 1, 2 o 3', () => {
  const names = (k) => par.networks[k].inputs.map((i) => i.name);
  assert.deepEqual(names('sevenCropPredictorV3'), FEATURE_NAMES_V3);
  assert.deepEqual(names('coffeePredictThenChooseV2'), load('coffee_ptc_mlp_v2.json').inputNames);
  assert.deepEqual(names('appAlignedNetwork'), load('app_mlp.json').inputNames);
  for (const n of Object.values(par.networks)) {
    for (const i of n.inputs) assert.ok([1, 2, 3].includes(i.class), i.name);
    assert.equal(n.counts.total, n.inputs.length);
    assert.equal(n.counts.drivesSimulator + n.counts.derivedSummary + n.counts.noEffect, n.inputs.length);
  }
});

test('paridad: la única entrada sin efecto en el simulador es lon de la red alineada con la app', () => {
  const none = Object.entries(par.networks).flatMap(([k, n]) => n.inputs.filter((i) => i.class === 3).map((i) => `${k}:${i.name}`));
  assert.deepEqual(none, ['appAlignedNetwork:lon']);
});
