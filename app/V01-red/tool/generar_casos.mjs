// Genera test/casos_red.json: los casos de referencia ("golden") con que las pruebas de Dart comprueban que la red
// y sus 40 entradas dan lo mismo que la referencia en JavaScript del repositorio del equipo.
//
//   node tool/generar_casos.mjs
//
// Corre desde app/V01-red/ dentro del repositorio (usa web/js/model/appInputs.js, appEngine.js y emulator.js, y web/data/app_mlp.json).
// El clima es sintético y con semilla fija: no hay datos reales en los casos. Cada caso guarda el clima tal como la app lo
// guardaría (formato de DiaClima.aJson), la plantación, las 40 entradas esperadas y las 3 salidas esperadas.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const aqui = dirname(fileURLToPath(import.meta.url));
const repo = resolve(aqui, '../../..');
const modelo = (f) => import(new URL(`file:///${resolve(repo, 'web/js/model', f).replaceAll('\\', '/')}`).href);
const { isoToDay, dayToIso, et0DeDia } = await modelo('appEngine.js');
const { appInputs, climaDeLaApp, withEt0, APP_INPUT_NAMES } = await modelo('appInputs.js');
const { mlpPredict } = await modelo('emulator.js');

const rutaRed = resolve(repo, 'web/data/app_mlp.json');
const red = JSON.parse(readFileSync(rutaRed, 'utf8'));
if (JSON.stringify(red.inputNames) !== JSON.stringify(APP_INPUT_NAMES)) throw new Error('inputNames no coincide con appInputs.js');
let commit = 'desconocido';
try { commit = execFileSync('git', ['log', '-1', '--format=%H', '--', rutaRed], { cwd: repo, encoding: 'utf8' }).trim(); } catch { /* sin git */ }

// Generador pseudoaleatorio con semilla (el mismo de los tests del repositorio).
function aleatorio(semilla) {
  let s = semilla >>> 0;
  return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
}

// Serie diaria de 420 días desde `primero`; `lluvioso` entre 0 (seco) y 1 (muy lluvioso).
function serie(semilla, primero, lluvioso, n = 420) {
  const rnd = aleatorio(semilla);
  const col = (g) => Array.from({ length: n }, (_, i) => g(i));
  const lluvia = col(() => (rnd() < 0.06 + 0.5 * lluvioso ? (4 + 22 * lluvioso) * rnd() : 0));
  return {
    first: primero,
    tmax: col((i) => 29 + 3 * Math.sin(i / 23) + 3 * rnd() - 2 * lluvioso),
    tmin: col((i) => 18 + 2 * Math.cos(i / 31) + 3 * rnd()),
    humedad: col(() => 48 + 25 * lluvioso + 25 * rnd()),
    viento: col(() => 0.8 + 2.4 * rnd()),
    radiacion: col((i) => (lluvia[i] > 5 ? 11 : 15) + 8 * rnd()),
    lluvia,
  };
}

const FINCA = { lat: 14.8, lon: -89.54, cellElevation: 762.46 };

// nombre, serie (semilla, primer día, lluvia), plantación, y qué día es hoy (días desde la siembra)
const definiciones = [
  { nombre: 'maiz_120_franco_humedo_25pct', semilla: 11, lluvioso: 0.85, plan: { crop: 'maiz', cycle: 120, soil: 'franco', siembra: '2024-05-20' }, t: 30 },
  { nombre: 'maiz_90_arenoso_seco_75pct', semilla: 12, lluvioso: 0.0, plan: { crop: 'maiz', cycle: 90, soil: 'arenoso', siembra: '2025-06-02' }, t: 68 },
  { nombre: 'frijol_80_franco_seco_35pct', semilla: 13, lluvioso: 0.1, plan: { crop: 'frijol', cycle: 80, soil: 'franco', siembra: '2025-09-10' }, t: 28 },
  { nombre: 'frijol_67_arcilloso_humedo_60pct', semilla: 14, lluvioso: 0.7, plan: { crop: 'frijol', cycle: 67, soil: 'arcilloso', siembra: '2024-08-05' }, t: 40 },
  { nombre: 'tomate_120_arenoso_seco_50pct', semilla: 15, lluvioso: 0.05, plan: { crop: 'tomate', cycle: 120, soil: 'arenoso', siembra: '2025-04-15' }, t: 60 },
  { nombre: 'tomate_145_franco_humedo_78pct', semilla: 16, lluvioso: 0.95, plan: { crop: 'tomate', cycle: 145, soil: 'franco', siembra: '2024-07-01' }, t: 113 },
  { nombre: 'maiz_120_franco_con_huecos_y_retraso', semilla: 17, lluvioso: 0.7, plan: { crop: 'maiz', cycle: 120, soil: 'franco', siembra: '2025-07-12' }, t: 55, huecos: [30, 31, 44, 45, 46], retraso: 3 },
  { nombre: 'frijol_90_franco_20pct_con_clima_posterior_a_hoy', semilla: 18, lluvioso: 0.55, plan: { crop: 'frijol', cycle: 90, soil: 'franco', siembra: '2025-10-01' }, t: 18, posterior: 5 },
];

const casos = [];
for (const d of definiciones) {
  const siembra = isoToDay(d.plan.siembra);
  const hoy = siembra + d.t;
  const primero = siembra - 80;
  const s = withEt0(serie(d.semilla, primero, d.lluvioso), FINCA.lat, FINCA.cellElevation, et0DeDia);
  // Huecos: días enteros sin dato dentro de la ventana (POWER marca -999).
  for (const k of d.huecos ?? []) {
    const i = hoy - k - s.first;
    for (const campo of ['tmax', 'tmin', 'humedad', 'viento', 'radiacion', 'lluvia', 'et0']) s[campo][i] = null;
  }
  // Retraso de POWER: el último día con dato es anterior a hoy.
  const ultimoConDato = hoy - (d.retraso ?? 0);
  const recortada = { ...s };
  for (const campo of ['tmax', 'tmin', 'humedad', 'viento', 'radiacion', 'lluvia', 'et0']) recortada[campo] = s[campo].slice(0, ultimoConDato - s.first + 1);

  const r = appInputs(recortada, FINCA, { ...d.plan, siembra }, hoy);
  const crudo = mlpPredict(red, r.x);
  // Lo que la app guarda: la ventana de clima hasta hoy, más (en un caso) días posteriores que la app debe ignorar.
  const ventana = climaDeLaApp(recortada, siembra, hoy);
  const posteriores = [];
  for (let k = 1; k <= (d.posterior ?? 0); k++) {
    const i = hoy + k - s.first;
    posteriores.push({ dia: hoy + k, tmax: s.tmax[i] + 9, tmin: s.tmin[i], humedad: s.humedad[i], viento: s.viento[i], radiacion: s.radiacion[i], lluvia: s.lluvia[i] + 300 });
  }
  const clima = [...ventana, ...posteriores].map((c) => ({ f: dayToIso(c.dia), x: c.tmax, n: c.tmin, h: c.humedad, v: c.viento, r: c.radiacion, l: c.lluvia }));
  casos.push({
    nombre: d.nombre,
    parcela: { latitud: FINCA.lat, longitud: FINCA.lon, elevacion: FINCA.cellElevation },
    plantacion: { cultivo: d.plan.crop, siembra: d.plan.siembra, ciclo: d.plan.cycle, suelo: d.plan.soil },
    hoy: dayToIso(hoy),
    fraccionDelCiclo: d.t / d.plan.cycle,
    diasEstimados: r.estimatedDays,
    clima,
    entradas: r.x,
    salidasCrudas: crudo,
    salidas: [Math.min(Math.max(crudo[0], 0), 1), Math.min(Math.max(crudo[1], 0), 7), Math.min(Math.max(crudo[2], 0), 14)],
    // Lo que muestra la app hoy y lo que el motor de la app dice que pasó después (sin lluvia adelante), solo para leer los casos.
    referenciaApp: r.refApp,
  });
}

const salida = { generadoPor: 'tool/generar_casos.mjs', pesosCommit: commit, nombresEntradas: APP_INPUT_NAMES, nombresSalidas: red.targetNames, casos };
writeFileSync(resolve(aqui, '../test/casos_red.json'), `${JSON.stringify(salida, null, 1)}\n`);
for (const c of casos) {
  console.log(c.nombre.padEnd(52), 'frac', c.fraccionDelCiclo.toFixed(2), 'estimados', c.diasEstimados, 'salidas', c.salidas.map((v) => v.toFixed(3)).join(' '), 'estres7 app', c.referenciaApp[1]);
}
