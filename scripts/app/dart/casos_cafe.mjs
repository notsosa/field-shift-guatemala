// Escribe casos de comprobación para la red de café: entradas crudas y la salida de la referencia en JS.
// Uso: node scripts/app/dart/casos_cafe.mjs <salida.json>
import { readFileSync, writeFileSync } from 'node:fs';
import { forward, standardize } from '../../../web/js/model/recommender.js';

const net = JSON.parse(readFileSync(new URL('../../../web/data/coffee_recommender.json', import.meta.url)));
let seed = 12345;
const rnd = () => ((seed = (seed * 1664525 + 1013904223) >>> 0) / 4294967296);
const cases = [];
for (let k = 0; k < 20; k++) {
  const x = net.mean.map((m, j) => m + (rnd() * 4 - 2) * net.std[j]); // valores dentro de ±2 desviaciones
  cases.push({ x, out: forward(net.params, standardize(x, net.mean, net.std), net.layerSizes) });
}
writeFileSync(process.argv[2], JSON.stringify(cases));
console.log(`${cases.length} casos`);
