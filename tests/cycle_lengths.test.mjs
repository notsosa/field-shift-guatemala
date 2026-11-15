import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';
import { cycleStats, PILOTS } from '../scripts/data/cycle_lengths.mjs';

const root = fileURLToPath(new URL('..', import.meta.url));
const artifact = JSON.parse(fs.readFileSync(new URL('../web/data/cycle_lengths.json', import.meta.url), 'utf8'));

test('cycle_lengths.json: el bloque "after" es el que da hoy el simulador con los snapshots actuales', async () => {
  const now = await cycleStats(root);
  assert.deepEqual(now, artifact.after);
});

test('cycle_lengths.json: la temperatura a la elevación de la parcela acorta el ciclo donde la parcela es más baja que su celda y lo alarga donde es más alta', () => {
  for (const id of PILOTS) {
    const b = artifact.before[id]; const a = artifact.after[id];
    assert.equal(b.deltaT, 0); // "antes" = temperatura de la celda sin corregir
    const sign = Math.sign(a.deltaT);
    const d = a.actual.maize.median - b.actual.maize.median;
    assert.ok(sign !== 0 && Math.sign(d) === -sign, `${id}: deltaT ${a.deltaT}, maize ${b.actual.maize.median} -> ${a.actual.maize.median}`);
  }
  assert.ok(artifact.after.chiquimula.deltaT > 0 && artifact.after.sanmartin.deltaT < 0);
});
