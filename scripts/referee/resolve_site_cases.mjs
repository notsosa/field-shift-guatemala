// Turns cases with `soil: "site"` into AquaCrop-ready cases: the soil becomes {thetaFC, thetaWP} of the pilot named in
// `site` (from scripts/emulator/points.json); the `site` field stays so compare.mjs runs the simulator with the same soil.
// Usage: node scripts/referee/resolve_site_cases.mjs --cases scripts/referee/cases_chiquimula.json --out scripts/referee/out/cases_resolved.json
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

export function resolveSiteCases(cases, points) {
  return cases.map((c) => {
    if (c.soil !== 'site') return c;
    if (!c.site) throw new Error(`case ${c.id}: soil "site" needs a "site" field with the pilot id`);
    const soil = points.find((p) => p.id === c.site)?.soil;
    if (!soil) throw new Error(`case ${c.id}: pilot ${c.site} has no soil in points.json`);
    return { ...c, soil: { thetaFC: soil.thetaFC, thetaWP: soil.thetaWP } };
  });
}

function arg(name, argv) {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 ? argv[i + 1] : undefined;
}

function main(argv) {
  const casesPath = arg('cases', argv);
  const out = arg('out', argv);
  if (!casesPath || !out) throw new Error('Usage: resolve_site_cases.mjs --cases <cases.json> --out <resolved.json> [--points scripts/emulator/points.json]');
  const pointsPath = arg('points', argv) ?? new URL('../emulator/points.json', import.meta.url);
  const raw = JSON.parse(fs.readFileSync(casesPath, 'utf8'));
  const cases = Array.isArray(raw) ? raw : raw.cases;
  const resolved = resolveSiteCases(cases, JSON.parse(fs.readFileSync(pointsPath, 'utf8')));
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, JSON.stringify({ ...(Array.isArray(raw) ? {} : raw), cases: resolved }, null, 1) + '\n');
  console.log(`Wrote ${resolved.length} cases (${resolved.filter((c) => c.site).length} with site soil) to ${out}`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) main(process.argv.slice(2));
