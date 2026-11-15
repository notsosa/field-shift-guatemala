import test from 'node:test'; import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { loadCrops } from '../web/js/model/crops.js';

const json = JSON.parse(readFileSync(new URL('../web/data/crops.json', import.meta.url), 'utf8'));
const seqs = JSON.parse(readFileSync(new URL('../web/data/sequences.json', import.meta.url), 'utf8'));
const base = { id: 'x', name: { en: 'X', es: 'X' }, sources: { agro: 'x' }, econ: null };

test('catálogo: 12 cultivos con fuente agronómica', () => {
  const m = loadCrops(json);
  assert.equal(m.size, 12);
  for (const c of m.values()) assert.ok(c.sources.agro);
  assert.equal(m.get('maiz').kc.mid, 1.2);
  assert.equal(m.get('mucuna').ky, null);
  assert.equal(m.get('sandia').needsIrrigation, true);
});
test('cultivo con econ sin fuente es rechazado', () =>
  assert.throws(() => loadCrops([{ ...base, econ: { yieldRef: 1 }, sources: { agro: 'x' } }]), /x/));
test('cultivo sin fuente agronómica es rechazado, nombrando el id', () =>
  assert.throws(() => loadCrops([{ ...base, id: 'sinfuente', sources: {} }]), /sinfuente/));
test('econ null no exige fuente econ', () => assert.equal(loadCrops([base]).size, 1));
test('secuencias referencian cultivos existentes', () => {
  const m = loadCrops(json);
  assert.deepEqual(Object.keys(seqs), ['actual', 'proteger', 'extra_secano', 'extra_riego']);
  for (const s of Object.values(seqs)) for (const p of s.phases) assert.ok(m.has(p.cropId));
  assert.equal(seqs.extra_riego.requiresIrrigation, true);
  assert.deepEqual(seqs.proteger.phases[1], { cropId: 'mucuna', sow: { relayOf: 0, daysAfterSow: 60 } });
});
test('kyStages sin sources.kyStages es rechazado, nombrando el id', () =>
  assert.throws(() => loadCrops([{ ...base, id: 'kysin', kyStages: { veg: 0.4, flower: 1.5, yieldForm: 0.5, ripen: 0.2 } }]), /kysin/));
test('kyStages con fuente es aceptado; null no exige fuente', () => {
  const ok = { ...base, kyStages: { veg: 0.4, flower: 1.5, yieldForm: 0.5, ripen: 0.2 }, sources: { agro: 'x', kyStages: 'FAO-33' } };
  assert.equal(loadCrops([ok, { ...base, id: 'y', kyStages: null }]).size, 2);
});
test('catálogo: maíz y frijol con Ky por etapa verificado; el resto null', () => {
  const m = loadCrops(json);
  assert.deepEqual(m.get('maiz').kyStages, { veg: 0.4, flower: 1.5, yieldForm: 0.5, ripen: 0.2 });
  assert.deepEqual(m.get('frijol').kyStages, { veg: 0.2, flower: 1.1, yieldForm: 0.75, ripen: 0.2 });
  for (const id of ['sorgo', 'ajonjoli', 'sandia', 'melon', 'tomate', 'mucuna', 'papa', 'cebolla', 'brocoli', 'lechuga']) assert.equal(m.get(id).kyStages, null);
});

test('papa, cebolla, brócoli y lechuga: valores de las auditorías, fuentes y proxies rotulados', () => {
  const m = loadCrops(json);
  const days = (c) => Object.values(c.days).reduce((a, b) => a + b, 0);
  assert.deepEqual(['papa', 'cebolla', 'brocoli', 'lechuga'].map((id) => days(m.get(id))), [115, 150, 135, 75]);
  assert.deepEqual(m.get('cebolla').kc, { ini: 0.7, mid: 1.05, end: 0.75 });
  assert.equal(m.get('lechuga').zrMax, 0.4);
  for (const id of ['papa', 'cebolla', 'brocoli', 'lechuga']) {
    const c = m.get(id);
    assert.ok(c.sources.agro.includes('a0d0690') && c.sources.days.includes('a0d0690'), id);
    assert.ok(c.proxy.includes('tbase') && c.sources.tbase.startsWith('PROXY'), id);
    assert.equal(c.proxy.includes('ky'), c.sources.ky.startsWith('PROXY'), id);
    assert.equal(c.econ, null);
  }
  assert.deepEqual([m.get('papa').ky, m.get('cebolla').ky, m.get('brocoli').proxy, m.get('lechuga').proxy], [1.1, 1.1, ['ky', 'tbase'], ['ky', 'tbase']]);
});
