// Genera test/casos_cafe.json: los casos de referencia ("golden") con que las pruebas de Dart comprueban que las 19 entradas
// de la red del café, su predicción, la decisión y los avisos dan lo mismo que la referencia en JavaScript del repositorio.
//
//   node tool/generar_casos_cafe.mjs
//
// Corre desde app/V01-red/ dentro del repositorio (usa web/js/model/coffee.js y emulator.js, y web/data/coffee_ptc_mlp_v3.json).
// Las series diarias de lluvia, ET0 y temperaturas son sintéticas y con semilla fija: no hay datos reales en los casos.
// El caso guarda la serie hasta hoy, la plantación, el Ks y el balance de la app que usan los avisos, y lo que da la referencia.
import { readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';

const aqui = dirname(fileURLToPath(import.meta.url));
const repo = resolve(aqui, '../../..');
const modelo = (f) => import(new URL(`file:///${resolve(repo, 'web/js/model', f).replaceAll('\\', '/')}`).href);
const { isoToDay, dayToIso } = await modelo('appEngine.js');
const cafe = await modelo('coffee.js');
const { mlpPredict } = await modelo('emulator.js');

const rutaRed = resolve(repo, 'web/data/coffee_ptc_mlp_v3.json');
const red = JSON.parse(readFileSync(rutaRed, 'utf8'));
if (JSON.stringify(red.inputNames) !== JSON.stringify(cafe.STATE_NAMES_V3)) throw new Error('inputNames no coincide con coffee.js');
let commit = 'desconocido';
try { commit = execFileSync('git', ['log', '-1', '--format=%H', '--', rutaRed], { cwd: repo, encoding: 'utf8' }).trim(); } catch { /* sin git */ }

function aleatorio(semilla) {
  let s = semilla >>> 0;
  return () => { s = (Math.imul(s, 1664525) + 1013904223) >>> 0; return s / 4294967296; };
}
const r3 = (v) => Math.round(v * 1000) / 1000;

// Los avisos del modelo comparan con medianas del sitio; la app no las tiene. Con medianas nulas, la roya «favorable» nunca
// se activa, que es lo que calcula la app (solo «possible»), y la antracnosis queda activa solo por estrés.
const history = { dtrMedian: Array(13).fill(null), tmaxMedian: Array(13).fill(null) };

// nombre, hoy, días desde la floración, lluvia (0 seco … 1 muy lluvioso), temperaturas, sombra, suelo entre los surcos (limpio por omisión), prioridad (0 ahorrar / 1 proteger),
// suelo (mm de agua disponible por metro), elevación, fracción de días con estrés en el balance de la app, agotamiento de la app (0–1 de TAW)
const definiciones = [
  { nombre: 'sin_sombra_seco_ahorrar_60d', semilla: 101, hoy: '2026-04-10', dias: 60, lluvioso: 0.0, tx: 29, tn: 17, sombra: 'ninguna', prioridad: 0, aw: 150, elev: 903, estres: 0.1, agot: 0.30 },
  { nombre: 'perenne_humedo_proteger_30d_abono_ahora', semilla: 102, hoy: '2025-06-05', dias: 30, lluvioso: 0.9, tx: 28, tn: 18, sombra: 'arbolesPerennes', prioridad: 1, aw: 180, elev: 1200, estres: 0.0, agot: 0.15 },
  { nombre: 'caduca_seco_ahorrar_90d_antracnosis', semilla: 103, hoy: '2026-05-20', dias: 90, lluvioso: 0.05, tx: 31, tn: 18, sombra: 'arbolesCaducos', prioridad: 0, aw: 100, elev: 760, estres: 0.8, agot: 0.85 },
  { nombre: 'banano_regulado_ahorrar_45d', semilla: 104, hoy: '2024-04-02', dias: 45, lluvioso: 0.2, tx: 30, tn: 19, sombra: 'bananoRegulado', prioridad: 0, aw: 150, elev: 1000, estres: 0.2, agot: 0.40 },
  { nombre: 'banano_denso_proteger_seco_75d_roya_posible', semilla: 105, hoy: '2025-06-18', dias: 75, lluvioso: 0.1, tx: 27, tn: 17, sombra: 'bananoDenso', prioridad: 1, aw: 100, elev: 1150, estres: 0.35, agot: 0.55 },
  { nombre: 'sin_sombra_humedo_proteger_100d_calor_sin_roya', semilla: 106, hoy: '2026-07-10', dias: 100, lluvioso: 0.7, tx: 36, tn: 25, sombra: 'ninguna', prioridad: 1, aw: 150, elev: 450, estres: 0.0, agot: 0.20 },
  { nombre: 'caduca_proteger_20d_noviembre', semilla: 107, hoy: '2025-11-24', dias: 20, lluvioso: 0.4, tx: 26, tn: 15, sombra: 'arbolesCaducos', prioridad: 1, aw: 180, elev: 1350, estres: 0.15, agot: 0.35 },
  { nombre: 'banano_regulado_ahorrar_estres_55d_antracnosis', semilla: 108, hoy: '2026-03-30', dias: 55, lluvioso: 0.0, tx: 32, tn: 20, sombra: 'bananoRegulado', prioridad: 0, aw: 150, elev: 880, estres: 0.9, agot: 0.9 },
  { nombre: 'malezas_seco_ahorrar_70d', semilla: 109, hoy: '2026-05-05', dias: 70, lluvioso: 0.05, tx: 30, tn: 18, sombra: 'ninguna', suelo: 'malezas', prioridad: 0, aw: 130, elev: 1050, estres: 0.4, agot: 0.5 },
  { nombre: 'malezas_humedo_proteger_35d', semilla: 110, hoy: '2025-04-12', dias: 35, lluvioso: 0.6, tx: 28, tn: 18, sombra: 'ninguna', suelo: 'malezas', prioridad: 1, aw: 170, elev: 1300, estres: 0.05, agot: 0.2 },
  { nombre: 'perenne_con_malezas_las_ignora_50d', semilla: 111, hoy: '2026-04-20', dias: 50, lluvioso: 0.1, tx: 29, tn: 17, sombra: 'arbolesPerennes', suelo: 'malezas', prioridad: 0, aw: 140, elev: 980, estres: 0.3, agot: 0.45 },
  { nombre: 'banano_denso_ahorrar_humedo_95d', semilla: 112, hoy: '2025-07-02', dias: 95, lluvioso: 0.8, tx: 27, tn: 18, sombra: 'bananoDenso', suelo: 'malezas', prioridad: 0, aw: 160, elev: 1100, estres: 0.0, agot: 0.15 },
];

// Serie diaria desde `primero` hasta `ultimo` (índices de día); lluvia, ET0 y temperaturas.
function serie(d, primero, ultimo) {
  const rnd = aleatorio(d.semilla);
  const n = ultimo - primero + 1;
  const col = (g) => Array.from({ length: n }, (_, i) => g(i));
  const lluvia = col(() => (rnd() < 0.05 + 0.55 * d.lluvioso ? r3((3 + 28 * d.lluvioso + 6 * rnd()) * rnd()) : 0));
  return {
    lluvia,
    et0: col((i) => r3(3.2 + 1.2 * Math.sin(i / 37) + 1.4 * rnd() - 0.8 * d.lluvioso)),
    tmax: col((i) => r3(d.tx + 2.5 * Math.sin(i / 23) + 2.5 * rnd())),
    tmin: col((i) => r3(d.tn + 1.5 * Math.cos(i / 31) + 2 * rnd())),
  };
}

const casos = [];
for (const d of definiciones) {
  const hoyDia = isoToDay(d.hoy);
  const floracionDia = hoyDia - d.dias;
  const [anio, mes] = d.hoy.split('-').map(Number);
  const anioCafetalero = mes >= 11 ? anio : anio - 1;
  const nov1 = isoToDay(`${anioCafetalero}-11-01`);
  const primero = nov1 - 30; // la serie empieza un mes antes del 1 de noviembre: el índice de noviembre no es 0
  const s = serie(d, primero, hoyDia);
  const t = hoyDia - primero;
  const fechas = Array.from({ length: t + 1 }, (_, i) => dayToIso(primero + i));

  const suelo = { thetaFC: 0.3, thetaWP: 0.3 - d.aw / 1000 };
  const cultivo = { zrMax: 1.2, kc: { mid: 0.95 } };
  // Árboles de sombra: shade 'trees' y sin sistema (no se combinan con malezas ni banano, y `suelo` se ignora). Banano: sistema 'regulado' o 'denso' (el suelo se ignora).
  // Sin sombra: suelo limpio = el café de siempre (sin sistema); con malezas = sistema 'malezas'.
  const arbol = d.sombra === 'arbolesPerennes' || d.sombra === 'arbolesCaducos' ? 'trees' : 'none';
  const tipoArbol = d.sombra === 'arbolesCaducos' ? 'deciduous' : 'evergreen';
  const sistema = d.sombra === 'bananoRegulado' ? 'regulado' : d.sombra === 'bananoDenso' ? 'denso' : d.sombra === 'ninguna' && d.suelo === 'malezas' ? 'malezas' : undefined;
  const { state, depletion, taw } = cafe.coffeeDecisionStateV3({
    dates: fechas, rain: s.lluvia, et0: s.et0, tmax: s.tmax, tmin: s.tmin, t, year: anioCafetalero,
    floweringIdx: t - d.dias, soil: suelo, crop: cultivo, elevation: d.elev, shade: arbol, treeType: tipoArbol, system: sistema,
  });
  const prediccion = mlpPredict(red, state)[0];

  // Lo que usan los avisos: el Ks y el balance de la propia app (sin sombra, raíz de 1.0 m).
  const rnd = aleatorio(d.semilla + 1000);
  const ks = Array.from({ length: t + 1 }, () => (rnd() < d.estres ? r3(0.3 + 0.69 * rnd()) : 1));
  const tawApp = d.aw * 1.0;
  const agotamientoApp = r3(d.agot * tawApp);
  const p = 0.4;

  const antracnosis = cafe.antracnosisNotice({ dates: fechas, tmax: s.tmax, tmin: s.tmin, ks, t, history });
  const roya = cafe.royaNotice({ dates: fechas, tmax: s.tmax, tmin: s.tmin, t, history });
  const abono = cafe.abonoNotice({ dates: fechas, rain: s.lluvia, t, dr: agotamientoApp, taw: tawApp, p });
  const prioridadEfectiva = cafe.effectivePriority(d.prioridad, antracnosis);
  const precio = cafe.PRICE[prioridadEfectiva];

  casos.push({
    nombre: d.nombre,
    hoy: d.hoy,
    primerDia: dayToIso(primero),
    floracion: dayToIso(floracionDia),
    diasDesdeFloracion: d.dias,
    parcela: { elevacion: d.elev },
    plantacion: { sombra: d.sombra, sueloSurcos: d.suelo ?? 'limpio', prioridad: d.prioridad === 0 ? 'ahorrarAgua' : 'protegerCultivo', aguaDisponible: d.aw },
    serie: { lluvia: s.lluvia, et0: s.et0, tmax: s.tmax, tmin: s.tmin },
    app: { ks: ks.slice(-40), agotamiento: agotamientoApp, aguaTotal: tawApp, p },
    esperado: {
      entradas: state,
      agotamiento: depletion,
      taw,
      prediccion,
      precioElegido: cafe.PRICE[d.prioridad],
      precio,
      antracnosisCambioPrioridad: prioridadEfectiva !== d.prioridad,
      regar: prediccion > precio,
      reglaRiega: cafe.ruleIrrigates(depletion, taw, 0.4),
      abono: { nivel: abono.level, fuente: abono.sourceKey, rain7: abono.triggers.rain7, enVentana: abono.triggers.inWindow, humedo: abono.triggers.moist },
      antracnosis: { nivel: antracnosis.level, porEstres: antracnosis.triggers.byStress, diasEstres28: antracnosis.triggers.stressDays28, fraccion28: antracnosis.triggers.stressShare28 },
      roya: { nivel: roya.level, tempMedia14: roya.triggers.meanTemp14 },
    },
  });
}

// Los casos de comprobación del archivo de pesos (calculados con PyTorch en 32 bits): tolerancia 1e-5.
const comprobacion = red.checkInputs.map((x, i) => ({ entradas: x, prediccion: red.checkPredictions[i].pred[0] }));

const salida = {
  generadoPor: 'tool/generar_casos_cafe.mjs',
  pesosCommit: commit,
  nombresEntradas: cafe.STATE_NAMES_V3,
  casos,
  comprobacionPesos: comprobacion,
};
writeFileSync(resolve(aqui, '../test/casos_cafe.json'), `${JSON.stringify(salida)}\n`);
for (const c of casos) {
  const e = c.esperado;
  console.log(
    c.nombre.padEnd(52), 'pred', e.prediccion.toFixed(3).padStart(7), 'precio', e.precio, e.regar ? 'REGAR' : 'no   ', 'regla', e.reglaRiega ? 'si' : 'no',
    'cambio', e.antracnosisCambioPrioridad ? 'si' : 'no', '|', e.abono.nivel.padEnd(9), e.antracnosis.nivel.padEnd(7), e.roya.nivel.padEnd(8), e.roya.tempMedia14.toFixed(1),
  );
}
