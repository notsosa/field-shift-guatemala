// Writes the AquaCrop weather file (tab-separated) and a CSV copy from a bundle (snapshot or cache JSON).
// Usage: node scripts/referee/export_weather.mjs --bundle web/data/snapshots/chiquimula.json --out scripts/referee/out/weather_chiquimula
//   -> <out>.txt (Day Month Year MinTemp MaxTemp Precipitation ReferenceET) and <out>.csv (same columns, comma-separated)
// The whole bundle is exported; the Python side only simulates complete agricultural years (1 Apr Y .. 31 Mar Y+1).
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { computeEt0Series } from '../../web/js/model/simulate.js';

export const WEATHER_COLUMNS = ['Day', 'Month', 'Year', 'MinTemp', 'MaxTemp', 'Precipitation', 'ReferenceET'];

export function weatherRows(bundle, et0) {
  return bundle.dates.map((date, i) => {
    const [y, m, d] = date.split('-').map(Number);
    return [d, m, y, bundle.tmin[i], bundle.tmax[i], bundle.rain[i], Number(et0[i].toFixed(4))];
  });
}

function arg(name, argv) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
}

function main(argv) {
  const bundlePath = arg('bundle', argv);
  const out = arg('out', argv);
  if (!bundlePath || !out) throw new Error('Usage: export_weather.mjs --bundle <bundle.json> --out <path-without-extension>');
  const bundle = JSON.parse(fs.readFileSync(bundlePath, 'utf8'));
  const rows = weatherRows(bundle, computeEt0Series(bundle));
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(`${out}.txt`, [WEATHER_COLUMNS.join('\t'), ...rows.map((r) => r.join('\t'))].join('\n') + '\n');
  fs.writeFileSync(`${out}.csv`, [WEATHER_COLUMNS.join(','), ...rows.map((r) => r.join(','))].join('\n') + '\n');
  console.log(`Wrote ${rows.length} days (${bundle.dates[0]} .. ${bundle.dates.at(-1)}; rainSource ${bundle.rainSource}) to ${out}.txt / .csv`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) main(process.argv.slice(2));
