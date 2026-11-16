// Muestras de la red alineada con la app (Tarea 34, parte D): punto x año de siembra x fecha (cada 10 días desde el 1 de mayo hasta el 28 de septiembre,
// el último múltiplo de 10 días antes del 30) x cultivo y ciclo x suelo x "hoy" = 20, 35, 50, 65, 80 % del ciclo, a secano. Solo escenarios cuyo ciclo
// termina el 2025-12-31 o antes. La verdad sale del motor de la app con el clima real de TODO el ciclo; las entradas, solo de lo que la app tiene ese día
// (appInputs). Escribe binarios en scripts/app/cache/ (ignorado por git). Uso: node scripts/app/generate_samples.mjs
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { isoToDay, et0DeDia, simularBalance, prepararClima, CATALOGO, SUELOS } from '../../web/js/model/appEngine.js';
import { appInputs, withEt0, climaEntre, truthFrom, CROPS, SOILS, APP_INPUT_NAMES, TARGET_NAMES, N_INPUTS } from '../../web/js/model/appInputs.js';

const here = (p) => new URL(p, import.meta.url);
const points = JSON.parse(readFileSync(here('../emulator/points.json'), 'utf8'));
const OUT = here('./cache/');
mkdirSync(OUT, { recursive: true });
const FRACS = [0.2, 0.35, 0.5, 0.65, 0.8];
const SOW_OFFSETS = Array.from({ length: 16 }, (_, k) => k * 10);
const LAST_DAY = isoToDay('2025-12-31');
const YEARS = Array.from({ length: 25 }, (_, i) => 2001 + i);

const t0 = Date.now();
const X = [], Y = [], RA = [], RB = [], META = [];
let estimatedRows = 0, maxStateGap = 0, skipped = 0, groups = 0;
for (const [pi, p] of points.entries()) {
  const c = JSON.parse(readFileSync(here(`../emulator/cache_power_app/${p.id}.json`), 'utf8'));
  const raw = { first: isoToDay(c.dates[0]), tmax: c.tmax, tmin: c.tmin, humedad: c.humedad, viento: c.viento, radiacion: c.radiacion, lluvia: c.lluvia };
  const series = withEt0(raw, p.lat, c.elevation, et0DeDia);
  const farm = { lat: p.lat, lon: p.lon, cellElevation: c.elevation };
  for (const year of YEARS) {
    for (const [sk, off] of SOW_OFFSETS.entries()) {
      const siembra = isoToDay(`${year}-05-01`) + off;
      for (const [ci, crop] of CROPS.entries()) {
        for (const cycle of CATALOGO[crop].ciclos) {
          if (siembra + cycle - 1 > LAST_DAY) { skipped++; continue; }
          // Verdad: el motor de la app sobre el clima real de todo el ciclo (ventana desde 60 días antes de la siembra).
          const full = prepararClima(climaEntre(series, siembra - 60, siembra + cycle - 1), { latitud: farm.lat, elevacion: farm.cellElevation }, siembra + cycle - 1);
          for (const [si, soil] of SOILS.entries()) {
            groups++;
            const plan = { crop, cycle, soil, siembra };
            const states = simularBalance({ dias: full, siembra, cultivo: CATALOGO[crop], ciclo: cycle, aguaDisponible: SUELOS[soil] });
            for (const [fi, f] of FRACS.entries()) {
              const hoy = siembra + Math.round(f * cycle);
              const r = appInputs(series, farm, plan, hoy);
              const y = truthFrom(states, plan, CATALOGO[crop], hoy);
              if (r.estimatedDays) estimatedRows++;
              const st = states.find((s) => s.dia === hoy);
              const mine = r.estados.at(-1);
              maxStateGap = Math.max(maxStateGap, Math.abs(st.ks - mine.ks), Math.abs(st.agotamiento - mine.agotamiento));
              X.push(r.x); Y.push(y); RA.push(r.refApp); RB.push(r.refDry);
              META.push([pi, year, ci, cycle, si, fi, sk]);
            }
          }
        }
      }
    }
  }
  console.log(`${p.id}: ${X.length} filas acumuladas, ${((Date.now() - t0) / 1000).toFixed(0)} s`);
}
const n = X.length;
const flat = (rows, w) => { const a = new Float32Array(n * w); rows.forEach((r, i) => r.forEach((v, j) => { a[i * w + j] = v; })); return a; };
const meta = new Int16Array(n * 7);
META.forEach((r, i) => r.forEach((v, j) => { meta[i * 7 + j] = v; }));
for (const [name, arr] of [['X', flat(X, N_INPUTS)], ['Y', flat(Y, 3)], ['RA', flat(RA, 3)], ['RB', flat(RB, 3)]]) writeFileSync(new URL(`${name}.f32`, OUT), Buffer.from(arr.buffer));
writeFileSync(new URL('meta.i16', OUT), Buffer.from(meta.buffer));
const info = { n, nInputs: N_INPUTS, inputNames: APP_INPUT_NAMES, targetNames: TARGET_NAMES, metaColumns: ['pointIdx', 'year', 'cropIdx', 'cycle', 'soilIdx', 'fracIdx', 'sowIdx'],
  points: points.map((p) => p.id), crops: CROPS, soils: SOILS, fracs: FRACS, sowOffsetsDays: SOW_OFFSETS, groups, skippedByCycleEnd: skipped, rowsWithEstimatedDays: estimatedRows,
  maxAbsStateGapVsFullRun: maxStateGap, seconds: (Date.now() - t0) / 1000 };
writeFileSync(new URL('samples_info.json', OUT), JSON.stringify(info, null, 1));
console.log(`n=${n} grupos=${groups} omitidos por fin de ciclo=${skipped} filas con días estimados=${estimatedRows} dif. máx. de estado=${maxStateGap} (${info.seconds.toFixed(0)} s)`);
