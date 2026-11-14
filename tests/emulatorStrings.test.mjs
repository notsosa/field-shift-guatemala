import { test } from 'node:test';
import assert from 'node:assert/strict';
import { STRINGS, t } from '../web/js/ui/emulatorStrings.js';

test('EN y ES tienen exactamente las mismas claves', () => {
  const en = Object.keys(STRINGS.en).sort();
  const es = Object.keys(STRINGS.es).sort();
  assert.deepEqual(es.filter((k) => !en.includes(k)), []);
  assert.deepEqual(en.filter((k) => !es.includes(k)), []);
});

test('texto fijo de honestidad en ambos idiomas', () => {
  assert.equal(t('en', 'honesty'), 'AI learns our physical model; it does not predict real harvests');
  assert.equal(t('es', 'honesty'), 'La IA aprende nuestro modelo físico; no predice cosechas reales');
});

test('t: reemplaza variables y cae al inglés si falta la clave', () => {
  assert.equal(t('es', 'mapTiming', { n: 960, ms: 4 }), STRINGS.es.mapTiming.replace('{n}', '960').replace('{ms}', '4'));
  assert.equal(t('fr', 'honesty'), STRINGS.en.honesty);
  assert.equal(t('en', 'noSuchKey'), 'noSuchKey');
});
