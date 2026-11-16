// CHIRPS diario (ClimateSERV dataset 0) para los puntos de scripts/emulator/points.json que aún no tienen caché.
// Misma petición y mismo formato de caché que scripts/data/fetch_rain_climateserv.py (que necesita el paquete python climateserv):
// caja de +-0.03 grados, operación "Average" (5), un año calendario por petición, escrito en scripts/emulator/cache_rain/{id}_chirps.json.
// Un día que ClimateSERV no devuelve (o devuelve nulo/negativo) queda null y se cuenta como faltante: no se rellena nada.
// Solo el servicio oficial, sin cuenta ni clave, cliente genérico.
// Uso: node scripts/data/fetch_chirps_node.mjs [--workers 8] [--budget-minutes 15] [--points id1 id2 ...]
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const CACHE = path.join(root, 'scripts/emulator/cache_rain');
const BASE = 'https://climateserv.servirglobal.net/api';
const Y0 = 2001; const Y1 = 2025; const R = 0.03;
const args = process.argv.slice(2);
const opt = (k, d) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : d; };
const workers = Number(opt('--workers', 8));
const budgetMs = Number(opt('--budget-minutes', 15)) * 60000;
const pi = args.indexOf('--points');
const only = pi >= 0 ? args.slice(pi + 1).filter((a) => !a.startsWith('--')) : null;

const box = (lat, lon, r) => [[lon - r, lat - r], [lon + r, lat - r], [lon + r, lat + r], [lon - r, lat + r], [lon - r, lat - r]];
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const iso = (y, m, d) => `${String(y).padStart(4, '0')}-${String(m).padStart(2, '0')}-${String(d).padStart(2, '0')}`;

async function getText(url, tries = 4) {
  let last;
  for (let a = 1; a <= tries; a++) {
    try {
      const res = await fetch(url, { headers: { 'User-Agent': 'field-shift-rain-check/1.0' }, signal: AbortSignal.timeout(120000) });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return await res.text();
    } catch (e) { last = e; await sleep(5000 * a); }
  }
  throw last;
}

async function requestYear(polygon, year) {
  const q = new URLSearchParams({ datatype: '0', begintime: `01/01/${year}`, endtime: `12/31/${year}`, intervaltype: '0', operationtype: '5', geometry: polygon });
  const id = JSON.parse(await getText(`${BASE}/submitDataRequest/?${q}`))[0];
  if (!id) throw new Error('no request id');
  for (let i = 0; i < 120; i++) {
    const p = JSON.parse(await getText(`${BASE}/getDataRequestProgress/?id=${id}`));
    if (p[0] === 100) break;
    if (p[0] === -1) throw new Error('request failed on the server');
    await sleep(2000);
  }
  const data = JSON.parse(await getText(`${BASE}/getDataFromRequest/?id=${id}`)).data;
  if (!data || !data.length) throw new Error('empty response');
  return data;
}

function recomputeMeta(doc) {
  const [s, e] = doc.requested;
  const gaps = [];
  for (let t = Date.parse(s); t <= Date.parse(e); t += 864e5) { const d = new Date(t).toISOString().slice(0, 10); if (typeof doc.days[d] !== 'number') gaps.push(d); }
  const dates = Object.keys(doc.days).filter((d) => doc.days[d] !== null).sort();
  doc.obtained = dates.length ? [dates[0], dates.at(-1)] : null;
  doc.missingDays = gaps.length;
  doc.missingDates = gaps.length <= 400 ? gaps : [...gaps.slice(0, 200), '...', ...gaps.slice(-200)];
  const yrs = new Set(gaps.map((d) => Number(d.slice(0, 4))));
  doc.yearsIncomplete = [...yrs].sort();
  doc.complete = gaps.length === 0;
}

const points = JSON.parse(fs.readFileSync(path.join(root, 'scripts/emulator/points.json'), 'utf8')).filter((p) => !only || only.includes(p.id));
if (only) points.sort((a, b) => only.indexOf(a.id) - only.indexOf(b.id)); // con --points, se baja en el orden dado
const jobs = []; const docs = {};
for (const p of points) {
  const file = path.join(CACHE, `${p.id}_chirps.json`);
  const doc = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : {
    id: p.id, lat: p.lat, lon: p.lon, dataset: 'chirps', datasetId: 0, operation: 'Average', boxLonLat: box(p.lat, p.lon, R),
    requested: [`${Y0}-01-01`, `${Y1}-12-31`], service: 'https://climateserv.servirglobal.net/', clientPackage: 'direct REST (node fetch), same calls as climateserv 1.0.8',
    response: {}, days: {}, yearsDone: [], yearsFailed: {}, duplicates: 0, nonNumeric: 0,
  };
  docs[p.id] = { file, doc, p };
  for (let y = Y0; y <= Y1; y++) if (!doc.yearsDone.includes(y)) jobs.push([p.id, y]);
}
const t0 = Date.now();
console.log(`${jobs.length} requests pending, ${workers} workers, budget ${budgetMs / 60000} min`);
let next = 0;
function save(entry) {
  entry.doc.downloadedUtc = new Date().toISOString().slice(0, 19) + '+00:00';
  recomputeMeta(entry.doc);
  const tmp = `${entry.file}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(entry.doc));
  try { fs.renameSync(tmp, entry.file); } catch { fs.writeFileSync(entry.file, JSON.stringify(entry.doc)); }
}
async function worker() {
  while (next < jobs.length) {
    const [id, y] = jobs[next++];
    if (Date.now() - t0 > budgetMs) { console.log('skipped (time box)', id, y); continue; }
    const entry = docs[id];
    try {
      const rows = await requestYear(JSON.stringify({ type: 'Polygon', coordinates: [box(entry.p.lat, entry.p.lon, R)] }), y);
      for (const row of rows) {
        let v = row.value?.avg;
        if (v != null && typeof v !== 'number') { entry.doc.nonNumeric++; v = null; }
        const key = iso(row.year, row.month, row.day);
        if (key in entry.doc.days) entry.doc.duplicates++;
        entry.doc.days[key] = v == null || v < 0 ? null : Math.round(v * 1000) / 1000;
      }
      entry.doc.yearsDone.push(y); delete entry.doc.yearsFailed[String(y)];
      console.log('ok', id, y, rows.length, `t=${Math.round((Date.now() - t0) / 1000)}s`);
    } catch (e) {
      entry.doc.yearsFailed[String(y)] = String(e.message ?? e);
      console.log('FAILED', id, y, e.message ?? e);
    }
    save(entry);
  }
}
await Promise.all(Array.from({ length: workers }, worker));
console.log(`Elapsed ${((Date.now() - t0) / 60000).toFixed(1)} min`);
for (const [id, { doc }] of Object.entries(docs)) console.log(id, `years ${doc.yearsDone.length}/${Y1 - Y0 + 1}`, 'missing days', doc.missingDays, 'failed', Object.keys(doc.yearsFailed).join(','));
