import test from 'node:test'; import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  daysBeforeNov15, ruleAction, chooseAction, decideAction, lossMetrics, resowOffset, pastData, simulatorOutcomes, networkOutcomes, FALLOW,
} from '../scripts/compare/loss_decision_lib.mjs';
import { loadCrops } from '../web/js/model/crops.js';

const rj = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));

test('regla agronómica: 120 días para maíz, 70 para frijol, si no dejar el campo (a mano, año 2021)', () => {
  assert.equal(daysBeforeNov15('2021-07-18'), 120); // 18 jul a 15 nov = 13 + 31 + 30 + 31 + 15 = 120
  assert.equal(ruleAction('2021-07-18'), 'maiz');
  assert.equal(ruleAction('2021-07-19'), 'frijol'); // 119 días
  assert.equal(daysBeforeNov15('2021-09-06'), 70); // 6 sep a 15 nov = 24 + 31 + 15 = 70
  assert.equal(ruleAction('2021-09-06'), 'frijol');
  assert.equal(ruleAction('2021-09-07'), FALLOW); // 69 días
  assert.equal(ruleAction('2021-11-20'), FALLOW); // ya pasó
});

test('el desfase de la resiembra: pérdida + 1 día libre + 14', () => {
  assert.deepEqual([30, 45, 60].map(resowOffset), [45, 60, 75]);
});

test('chooseAction: el mayor valor; empate a dejar el campo, luego el orden de ACTIONS', () => {
  assert.equal(chooseAction([{ action: 'frijol', value: 0.5 }, { action: 'maiz', value: 0.4 }]), 'frijol');
  assert.equal(chooseAction([{ action: 'frijol', value: 0.5 }, { action: 'maiz', value: 0.5 }]), 'maiz');
  assert.equal(chooseAction([{ action: 'maiz', value: 0 }, { action: FALLOW, value: 0 }]), FALLOW);
});

test('decideAction: mediana vs percentil 20 sobre años pasados, calculados a mano', () => {
  // maiz 2001..2005: .9 .9 .9 .9 0 ; frijol .6 en los cinco. Mediana maiz .9; p20 maiz: orden 0 .9 .9 .9 .9, pos 0.8 → 0.72 > .6
  const o = [];
  for (const [y, m] of [[2001, 0.9], [2002, 0.9], [2003, 0.9], [2004, 0.9], [2005, 0]]) { o.push({ action: 'maiz', year: y, value: m }); o.push({ action: 'frijol', year: y, value: 0.6 }); }
  assert.equal(decideAction({ outcomes: o, targetYear: 2006, priority: 'typical' }), 'maiz');
  assert.equal(decideAction({ outcomes: o, targetYear: 2006, priority: 'cautious' }), 'maiz');
  // con dos ceros: orden 0 0 .9 .9 .9, pos 0.8 → 0 < .6; la mediana sigue en .9
  o.find((r) => r.action === 'maiz' && r.year === 2004).value = 0;
  assert.equal(decideAction({ outcomes: o, targetYear: 2006, priority: 'cautious' }), 'frijol');
  assert.equal(decideAction({ outcomes: o, targetYear: 2006, priority: 'typical' }), 'maiz');
  // un año futuro con valores enormes no entra
  const future = [...o, { action: 'lechuga', year: 2006, value: 1 }, { action: 'lechuga', year: 2007, value: 1 }];
  assert.equal(decideAction({ outcomes: future, targetYear: 2006, priority: 'typical' }), 'maiz');
  // todo 0 → dejar el campo
  assert.equal(decideAction({ outcomes: [{ action: 'maiz', year: 2001, value: 0 }], targetYear: 2002, priority: 'typical' }), FALLOW);
  assert.throws(() => decideAction({ outcomes: [{ action: 'maiz', year: 2006, value: 1 }], targetYear: 2006, priority: 'typical' }));
});

test('lossMetrics: media, ganancia contra la regla, W/T/L, arrepentimiento, p10, peor y ejecutables, a mano', () => {
  const rows = [
    { action: 'maiz', value: 0.8, ruleValue: 0.5, oracleValue: 0.9, executable: true, simAction: 'maiz' },
    { action: 'frijol', value: 0.5, ruleValue: 0.5, oracleValue: 0.5, executable: true, simAction: 'maiz' },
    { action: 'papa', value: 0.0, ruleValue: 0.4, oracleValue: 0.6, executable: false, simAction: 'papa' },
    { action: FALLOW, value: 0.0, ruleValue: 0.0, oracleValue: 0.2, executable: true, simAction: 'maiz' },
  ];
  const m = lossMetrics(rows);
  assert.equal(m.n, 4);
  assert.ok(Math.abs(m.chosenMean - 0.325) < 1e-12);
  assert.ok(Math.abs(m.ruleMean - 0.35) < 1e-12);
  assert.ok(Math.abs(m.meanGainVsRule - (0.3 + 0 - 0.4 + 0) / 4) < 1e-12);
  assert.deepEqual([m.win, m.tie, m.loss], [1, 2, 1]);
  assert.ok(Math.abs(m.meanRegret - (0.1 + 0 + 0.6 + 0.2) / 4) < 1e-12);
  assert.equal(m.worst, 0);
  assert.ok(Math.abs(m.p10 - 0) < 1e-12); // valores 0 0 .5 .8, pos 0.3 → 0
  assert.equal(m.executable, 3);
  assert.equal(m.executableShare, 0.75);
  assert.deepEqual(m.actions, { maiz: 1, frijol: 1, papa: 1, fallow: 1 });
  assert.equal(m.agreesWithSimulator, 2);
});

test('regla de información: corromper los datos desde el año Y en adelante no cambia la decisión (simulador y red)', () => {
  const bundle = rj('../web/data/snapshots/chiquimula.json');
  const crops = loadCrops(rj('../web/data/crops.json'));
  const Y = 2020;
  const corrupted = { ...bundle, rain: [...bundle.rain], tmax: [...bundle.tmax], tmin: [...bundle.tmin] };
  for (let i = bundle.dates.indexOf(`${Y}-04-01`); i < bundle.dates.length; i++) { corrupted.rain[i] = 900; corrupted.tmax[i] = 55; corrupted.tmin[i] = 40; }
  const decide = (b, prio) => {
    const past = pastData(b, Y);
    const sim = decideAction({ outcomes: simulatorOutcomes({ crops, simSoil: 'loam' }, past, 45), targetYear: Y, priority: prio });
    const dummy = (x) => [x[8] / 500, 0, 1]; // usa la lluvia de 0 a 60 días: cualquier fuga cambiaría el resultado
    const net = decideAction({ outcomes: networkOutcomes({ emuTexture: 'loam', predict: dummy }, past, 45), targetYear: Y, priority: prio });
    return [sim, net, past.years.at(-1), past.bundle.dates.at(-1)];
  };
  for (const prio of ['typical', 'cautious']) assert.deepEqual(decide(bundle, prio), decide(corrupted, prio));
  assert.equal(decide(bundle, 'typical')[2], Y - 1);
  assert.equal(decide(bundle, 'typical')[3], `${Y}-03-31`);
});
