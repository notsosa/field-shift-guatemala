import test from 'node:test'; import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import {
  ACTION_IDS, INPUT_NAMES, N_INPUTS, LAYER_SIZES, paramCount, initParams, forward, scoreActions, pickAction, recommend, esNext,
  decisionState, storeProxyAt, maizeKcAt, actionFeatures, outcomeValue, inputRows,
} from '../web/js/model/recommender.js';
import { loadCrops } from '../web/js/model/crops.js';
import { computeEt0Series } from '../web/js/model/simulate.js';
import { mulberry32 } from '../web/js/model/emulator.js';

const rj = (p) => JSON.parse(readFileSync(new URL(p, import.meta.url), 'utf8'));
const crops = loadCrops(rj('../web/data/crops.json'));
const near = (a, b, eps = 1e-9) => assert.ok(Math.abs(a - b) < eps, `${a} != ${b}`);

// Año sintético 2001: lluvia 0 salvo 30 mm el 3 de mayo (inicio de lluvias = 3 de mayo), 10 mm el 1 de junio y 5 mm el 2 de junio; ET0 = 4; Tmax 30, Tmin 20.
function synth() {
  const dates = [];
  for (let t = Date.UTC(2001, 0, 1); t <= Date.UTC(2002, 11, 31); t += 864e5) dates.push(new Date(t).toISOString().slice(0, 10));
  const n = dates.length;
  const rain = new Array(n).fill(0);
  rain[dates.indexOf('2001-05-03')] = 30; rain[dates.indexOf('2001-06-01')] = 10; rain[dates.indexOf('2001-06-02')] = 5;
  return { dates, rain, tmax: new Array(n).fill(30), tmin: new Array(n).fill(20), tdew: new Array(n).fill(15), rs: new Array(n).fill(20), u2: new Array(n).fill(2), pressure: new Array(n).fill(95), elevation: 500, lat: 14.5 };
}
const LOAM = 'loam';

test('el vector de entrada tiene 32 nombres (17 de estado, prioridad, 14 de acción) y la red 4737 parámetros', () => {
  assert.equal(N_INPUTS, 32);
  assert.equal(INPUT_NAMES.length, 32);
  assert.deepEqual(LAYER_SIZES, [32, 64, 32, 16, 1]);
  assert.equal(paramCount(), 32 * 64 + 64 + 64 * 32 + 32 + 32 * 16 + 16 + 16 + 1);
});

test('estado el día de la decisión, calculado a mano (siembra 3 mayo, pérdida a los 30 días = 2 junio)', () => {
  const b = synth();
  const et0 = new Array(b.dates.length).fill(4);
  const { state, sowLocal, decisionLocal } = decisionState({ bundle: b, et0, year: 2001, lossDay: 30, crops, soil: LOAM });
  assert.equal(sowLocal, 32); // 1 abr = 0, 3 mayo = 30 + 2
  assert.equal(decisionLocal, 62); // 2 junio
  const S = Object.fromEntries(INPUT_NAMES.slice(0, 17).map((k, i) => [k, state[i]]));
  assert.equal(S.doy, 153); // 31+28+31+30+31 = 151, + 2
  assert.equal(S.daysSinceOnset, 30);
  assert.equal(S.daysToNov15, 166); // 2 jun a 15 nov: 28 + 31 + 31 + 30 + 31 + 15 = 166
  assert.equal(S.daysToYearEnd, 302); // 2 jun 2001 a 31 mar 2002 = 365 - 63
  assert.equal(S.lossDay, 30);
  near(S.rain7, 15); near(S.rain28, 15); near(S.rainSinceApr1, 45); // 30 mm del 3 mayo quedan fuera de las últimas 28 (desde el 6 mayo)
  near(S.et0_7, 28); near(S.et0_28, 112); near(S.et0SinceApr1, 252); // 63 días desde el 1 abril
  assert.equal(S.dryspell28, 26); // 6 al 31 de mayo
  near(S.tmean28, 25);
  // balance antecedente (kc.ini .3 hasta el fin de ini; ini = 20 d x 16 GDD = 320 GDD; 15 GDD/d → ini termina el día 22 desde la siembra)
  // 1 abr–2 mayo: 0; 3 mayo: 30 − .3·4 = 28.8; 21 días de kc .3: −25.2 → 3.6; luego Kc sube y llega a 0 hasta el 1 junio.
  // dev dura 35 d x 16 = 560 GDD: 1 junio (siembra+29): gdd 450, f = (450-320)/560, kc = .3 + .9 f = .508929, 10 - 2.035714 = 7.964286; 2 junio (+30): gdd 465, kc .533036, 5 - 2.132143 -> 10.832143
  near(S.storeProxy, 10.832143, 1e-6);
  near(S.soilAWmmPerM, 130); // (0.25 − 0.12)·1000
  assert.equal(S.cnCrop, 78);
  assert.equal(S.elevation, 500);
});

test('el balance antecedente usa suelo desnudo (kc.ini del maíz) después de la pérdida y tiene tope de 150 mm', () => {
  const maize = crops.get('maiz');
  const kc = maizeKcAt(maize, { }, 10, 20);
  assert.equal(kc(5), maize.kc.ini); // antes de sembrar
  assert.equal(kc(25), maize.kc.ini); // después de la pérdida: desnudo
  // tope: 200 mm de lluvia un día con ET0 0 → 150
  assert.equal(storeProxyAt({ rain: [200, 0], et0: [0, 0], kcAt: () => 1, upto: 1 }), 150);
  // un día seco no baja de 0
  assert.equal(storeProxyAt({ rain: [0, 0], et0: [5, 5], kcAt: () => 1, upto: 1 }), 0);
  // upto corta: el día 1 no cuenta
  assert.equal(storeProxyAt({ rain: [10, 10], et0: [0, 0], kcAt: () => 1, upto: 0 }), 10);
});

test('sin datos futuros: alterar lo posterior al día de la decisión no cambia ninguna entrada (piloto real y año sintético)', () => {
  const corrupt = (b, from) => {
    const c = { ...b };
    for (const k of ['rain', 'tmax', 'tmin', 'tdew', 'rs', 'u2', 'pressure']) c[k] = b[k].map((v, i) => (i > from ? v * 7 + 50 : v));
    return c;
  };
  const pilot = rj('../web/data/snapshots/chiquimula.json');
  for (const [b, year, soil] of [[pilot, 2021, 'loam'], [pilot, 2003, 'clay']]) {
    const startIdx = b.dates.indexOf(`${year}-04-01`);
    for (const lossDay of [30, 45, 60]) {
      const base = decisionState({ bundle: b, et0: computeEt0Series(b), year, lossDay, crops, soil });
      const dAbs = base.startIdx + base.decisionLocal;
      assert.equal(startIdx, base.startIdx);
      const bad = corrupt(b, dAbs); // todo lo posterior al día de la decisión, incluidos otros años
      const alt = decisionState({ bundle: bad, et0: computeEt0Series(bad), year, lossDay, crops, soil });
      assert.deepEqual(alt.state, base.state);
      // las entradas de acción dependen solo del calendario y de los cultivos
      assert.deepEqual(ACTION_IDS.map((a) => actionFeatures(crops, a, base.sowLocal + lossDay + 15, base.endLocal)), ACTION_IDS.map((a) => actionFeatures(crops, a, alt.sowLocal + lossDay + 15, alt.endLocal)));
    }
  }
  const s = synth(), e = new Array(s.dates.length).fill(4);
  const a = decisionState({ bundle: s, et0: e, year: 2001, lossDay: 30, crops, soil: LOAM });
  const bad = corrupt(s, s.dates.indexOf('2001-06-02'));
  const b2 = decisionState({ bundle: bad, et0: e.map((v, i) => (i > s.dates.indexOf('2001-06-02') ? 99 : v)), year: 2001, lossDay: 30, crops, soil: LOAM });
  assert.deepEqual(b2.state, a.state);
});

test('entradas de acción a mano: maíz y dejar el campo', () => {
  const m = actionFeatures(crops, 'maiz', 100, 364);
  assert.deepEqual(m, [1, 0, 0, 0, 0, 0, 0, 0, 120, 1.2, 1.2, 0.55, 1.25, 1]); // días 20+35+40+25, kc mid 1.2, zr 1.2, p .55, ky 1.25
  assert.equal(actionFeatures(crops, 'maiz', 245, 364)[13], 0); // 245 + 120 > 364: no cabe
  assert.deepEqual(actionFeatures(crops, 'fallow', 100, 364), [0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1]);
  assert.throws(() => actionFeatures(crops, 'trigo', 1, 2));
});

test('forward a mano: red [2,2,1] con tanh en la oculta y salida lineal', () => {
  // capa 1: W = [[1,0],[0,2]], b = [0, -1]; capa 2: W = [[0.5, -1]], b = [0.25]
  const p = Float64Array.from([1, 0, 0, 2, 0, -1, 0.5, -1, 0.25]);
  const x = [0.5, 1];
  const h0 = Math.tanh(0.5), h1 = Math.tanh(2 * 1 - 1);
  near(forward(p, x, [2, 2, 1]), 0.5 * h0 - h1 + 0.25);
});

test('al inicio la red recomienda exactamente la regla en todo escenario (corrección 0)', () => {
  const p = initParams(17);
  assert.equal(p.length, paramCount());
  assert.ok(p.some((v) => v !== 0)); // las capas ocultas no son cero
  const mean = new Array(N_INPUTS).fill(0), std = new Array(N_INPUTS).fill(1);
  const rng = mulberry32(5);
  for (let k = 0; k < 40; k++) {
    const rows = ACTION_IDS.map(() => Array.from({ length: N_INPUTS }, () => rng() * 10 - 5));
    const rule = ACTION_IDS[Math.floor(rng() * 8)];
    const r = recommend({ params: p, mean, std }, rows, rule);
    assert.equal(r.action, rule);
    assert.deepEqual(r.scores, ACTION_IDS.map((a) => (a === rule ? 1 : 0)));
  }
});

test('puntaje = regla + tanh(corrección) y desempate a la acción de la regla', () => {
  // red [1,1] de una sola capa lineal: corrección = w·x + b con w = 2, b = 0
  const sizes = [1, 1];
  const net = { params: Float64Array.from([2, 0]), mean: [0], std: [1] };
  const rows = ACTION_IDS.map((_, i) => [i === 1 ? 1 : 0]); // solo "frijol" recibe corrección tanh(2) = 0.964
  const sc = scoreActions(net, rows, 'maiz', sizes);
  near(sc[0], 1); near(sc[1], Math.tanh(2)); near(sc[2], 0);
  assert.equal(pickAction(sc, 'maiz'), 'maiz'); // 1 > 0.964
  // empate exacto entre maíz (regla) y frijol → regla; entre dos que no son la regla → dejar el campo primero, luego el orden
  assert.equal(pickAction([0.7, 0.7, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1], 'maiz'), 'maiz');
  assert.equal(pickAction([0.1, 0.7, 0.7, 0.1, 0.1, 0.1, 0.1, 0.1], 'maiz'), 'frijol');
  assert.equal(pickAction([0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.7, 0.7], 'maiz'), 'fallow');
  // una corrección grande en contra de la regla puede cambiarla: regla frijol con −tanh(-)→ maíz con puntaje 0.99 > 1 + tanh(−3)=0.005
  assert.equal(pickAction([0.99, 0.005, 0, 0, 0, 0, 0, 0], 'frijol'), 'maiz');
});

test('valor del resultado por prioridad, a mano', () => {
  near(outcomeValue(0.8, 0), 0.8); near(outcomeValue(0.8, 1), 0.8);
  near(outcomeValue(0.2, 0), 0.2); near(outcomeValue(0.2, 1), 0.2 - 0.3); // penaliza lo que falta para 0.5
  near(outcomeValue(0, 1), -0.5);
});

test('paso de la estrategia de evolución: conserva la élite y los hijos salen de los 8 mejores con σ pequeño', () => {
  const pop = Array.from({ length: 32 }, (_, i) => new Float64Array(10).fill(i * 100)); // individuos muy separados
  const fit = pop.map((_, i) => i); // el mejor es el 31, luego 30 … 24 son los padres
  const { next, order } = esNext(pop, fit, mulberry32(3), { parents: 8, sigma: 0.05, elite: 1 });
  assert.equal(next.length, 32);
  assert.deepEqual(order.slice(0, 3), [31, 30, 29]);
  assert.deepEqual(Array.from(next[0]), Array.from(pop[31])); // élite sin mutar
  for (const child of next.slice(1)) {
    const near8 = [31, 30, 29, 28, 27, 26, 25, 24].some((i) => child.every((v) => Math.abs(v - i * 100) < 1));
    assert.ok(near8, 'cada hijo viene de uno de los 8 mejores');
    assert.ok(child.some((v) => v % 100 !== 0), 'y fue mutado');
  }
  // σ: desviación típica de las diferencias ≈ 0.05 (muchas muestras)
  const big = esNext([new Float64Array(20000)], [0], mulberry32(9), { parents: 1, elite: 0, sigma: 0.05 }).next[0];
  const sd = Math.sqrt(big.reduce((s, v) => s + v * v, 0) / big.length);
  assert.ok(Math.abs(sd - 0.05) < 0.003, `sd ${sd}`);
});

test('inputRows arma 8 filas [estado, prioridad, acción]', () => {
  const rows = inputRows([1, 2], 1, ACTION_IDS.map((a, i) => [i]));
  assert.equal(rows.length, 8);
  assert.deepEqual(rows[3], [1, 2, 1, 3]);
});
