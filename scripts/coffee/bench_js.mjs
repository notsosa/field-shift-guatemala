// Medida de velocidad de la versión en JS (web/js/model/recommender.js: forward, esNext, initParams) de la misma evolución del café, para compararla con la de GPU.
// Corre unas pocas generaciones del mismo diseño (población 32, 512 escenarios, 2 prioridades, 2 acciones) y proyecta las 150; escribe scripts/coffee/cache/bench_js.json.
// Uso: node scripts/coffee/bench_js.mjs [generaciones=5] [semilla=17]
import fs from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import { mulberry32 } from '../../web/js/model/emulator.js';
import { initParams, forward, standardize, esNext } from '../../web/js/model/recommender.js';
import { priceOf } from './eval_lib.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const gens = Number(process.argv[2] ?? 5), seed = Number(process.argv[3] ?? 17);
const T = JSON.parse(fs.readFileSync(path.join(root, 'scripts/coffee/cache/coffee_table.json'), 'utf8'));
const train = T.scenarios.filter((s) => s.split === 'train');
const sizes = [T.meta.stateNames.length + 2, 64, 32, 16, 1];
const n = sizes[0];
const rowsOf = (s, p, a) => [...s.state, p, a];
// estandarización con filas de entrenamiento (escenario x prioridad x acción)
const mean = new Array(n).fill(0), std = new Array(n).fill(0), cnt = train.length * 4;
for (const s of train) for (const p of [0, 1]) for (const a of [0, 1]) rowsOf(s, p, a).forEach((v, j) => { mean[j] += v / cnt; });
for (const s of train) for (const p of [0, 1]) for (const a of [0, 1]) rowsOf(s, p, a).forEach((v, j) => { std[j] += (v - mean[j]) ** 2 / cnt; });
const sd = std.map(Math.sqrt);
for (const s of train) s.xs = [0, 1].map((p) => [0, 1].map((a) => standardize(rowsOf(s, p, a), mean, sd)));
const fit = (params, list) => {
  let tot = 0;
  for (const p of [0, 1]) {
    let m = 0;
    for (const s of list) {
      const sNot = (1 - s.rule) + Math.tanh(forward(params, s.xs[p][0], sizes)), sIrr = s.rule + Math.tanh(forward(params, s.xs[p][1], sizes));
      const diff = sIrr - sNot;
      const irr = Math.abs(diff) <= 1e-12 ? s.rule : diff > 0 ? 1 : 0;
      m += irr * (s.avoided - priceOf(p));
    }
    tot += m / list.length;
  }
  return tot / 2;
};
const rng = mulberry32(seed);
const init = initParams(seed, sizes);
let pop = esNext(Array(32).fill(init), Array(32).fill(0), rng, {}).next;
const t0 = performance.now();
for (let g = 0; g < gens; g++) {
  const idx = Array.from({ length: train.length }, (_, i) => i), r2 = mulberry32(seed * 100003 + g);
  for (let i = 0; i < 512; i++) { const j = i + Math.floor(r2() * (train.length - i)); [idx[i], idx[j]] = [idx[j], idx[i]]; }
  const batch = idx.slice(0, 512).map((i) => train[i]);
  const f = pop.map((ind) => fit(ind, batch));
  pop = esNext(pop, f, rng, {}).next;
}
const seconds = (performance.now() - t0) / 1000;
const evals = gens * 32 * 512 * 2;
const out = { generationsMeasured: gens, seconds, scenarioEvals: evals, scenarioEvalsPerSecond: evals / seconds, projected150GenerationsSeconds: (seconds / gens) * 150, note: 'JS, one thread; validation scoring of the champion not included (adds ~1 % of the work)' };
fs.writeFileSync(path.join(root, 'scripts/coffee/cache/bench_js.json'), JSON.stringify(out, null, 1));
console.log(JSON.stringify(out));
