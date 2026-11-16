// Tabla de paridad algoritmo-simulador (Tarea 38, parte C) -> web/data/parity.json.
// Para cada red que el equipo conserva (predictor de siete cultivos v3, café predecir-y-elegir v2, red alineada con la app) se lista cada entrada y se clasifica leyendo el código:
//   1 = mueve el simulador directamente (clima, suelo, cultivo, fechas, sombra...)
//   2 = resumen derivado de cosas que sí mueven el simulador (o salida del propio simulador hasta hoy)
//   3 = no tiene efecto en el simulador
// Los nombres salen de los archivos (inputNames) o de la lista de nombres del código que generó los datos; si falta o sobra alguno, el guion falla.
// Uso: node scripts/parity/build_parity.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { FEATURE_NAMES_V3 } from '../../web/js/model/emulatorV3.js';
import { STATE_NAMES_V2 } from '../../web/js/model/coffee.js';
import { APP_INPUT_NAMES } from '../../web/js/model/appInputs.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(path.join(root, f), 'utf8'));

const C1 = 1, C2 = 2, C3 = 3;
const e = (cls, how) => ({ class: cls, how });

// --- predictor de siete cultivos v3: entradas = featuresV3 (emulatorV2.js, emulatorV3.js); se calculan SOLO de lo que se le da a simulateSuccessionYear ---
const WEATHER_DERIVED = 'resumen de la lluvia o la ET0 (del clima diario) del año agrícola; el simulador recibe esa lluvia y esa ET0 día por día';
const v3 = {
  rainMJJ: e(C2, WEATHER_DERIVED), rainASO: e(C2, WEATHER_DERIVED), rainYear: e(C2, WEATHER_DERIVED), caniculaDays: e(C2, 'racha seca de julio-agosto, resumen de la lluvia diaria'),
  et0MeanMO: e(C2, 'ET0 media mayo-octubre, resumen de la ET0 diaria'), tmeanMO: e(C2, 'temperatura media mayo-octubre; la temperatura mueve el simulador por la ET0 y los grados-día de la fenología'),
  elevation: e(C1, 'entra a la ET0 (radiación de cielo despejado, Rso = (0.75 + 2e-5 z)·Ra); efecto pequeño: +900 m = +0.7 % de ET0 en Jutiapa. Con la ET0 ya calculada, cambiar solo la elevación no mueve nada'),
  sowDoyA: e(C1, 'día de siembra del cultivo A (regla de inicio de lluvias + desfase): el simulador siembra ese día'),
  rain0to60: e(C2, 'lluvia en los 60 días tras la siembra de A'), et0_0to60: e(C2, 'ET0 en los 60 días tras la siembra de A'), rain61to150: e(C2, 'lluvia, días 61-150 tras la siembra'), et0_61to150: e(C2, 'ET0, días 61-150 tras la siembra'),
  offset30: e(C1, 'desfase de la siembra en días (0, 15, 30) / 30: el simulador siembra ese día'),
};
for (const c of ['maiz', 'frijol', 'ajonjoli', 'papa', 'cebolla', 'brocoli', 'lechuga']) v3[`A_${c}`] = e(C1, 'cultivo A elegido: parámetros FAO-56 del cultivo en el simulador');
for (const c of ['maiz', 'frijol', 'ajonjoli', 'papa', 'cebolla', 'brocoli', 'lechuga', 'none']) v3[`B_${c}`] = e(C1, c === 'none' ? 'sin cultivo B: el simulador no siembra un segundo cultivo' : 'cultivo B (sucesor) elegido: parámetros FAO-56 en el simulador');
for (const s of ['sand', 'loam', 'clay']) v3[`soil_${s}`] = e(C1, 'textura del suelo: θFC, θWP y número de curva del simulador');
const PER_CROP = {
  rainPre30: 'lluvia de los 30 días antes de la floración del cultivo', et0Pre30: 'ET0 de los 30 días antes de la floración', apiFlower: 'índice de lluvia antecedente hasta la floración',
  storeProxy: 'balance corrido acotado a 150 mm hasta la floración (lógica simple, no el simulador)', rainFlower: 'lluvia en la ventana de floración', deficitFlower: 'déficit climático en la ventana de floración',
  cycleDays: 'días del ciclo de la siembra a la cosecha, por grados-día (lo calcula la fenología del simulador)', daysLeft: 'días que quedan en el año agrícola al sembrar',
};
for (const who of ['A', 'B']) for (const [k, how] of Object.entries(PER_CROP)) v3[`${who}_${k}`] = e(C2, `${how} (cultivo ${who}); derivada de clima, fenología y fecha de siembra, que sí mueven el simulador`);

// --- café predecir-y-elegir v2: coffeeDecisionStateV2 (coffee.js) ---
const coffee = {
  daysSinceFlowering: e(C2, 'días desde la floración, que sale de la regla de lluvia (≥ 10 mm entre el 15 de febrero y el 30 de abril, más 9 días): derivada de la lluvia y la fecha'),
  doy: e(C1, 'fecha del día de la decisión: la fecha decide la estación lluviosa o seca, de la que depende el efecto de la sombra, y el día del año de la ET0'),
  rain7: e(C2, 'lluvia de los últimos 7 días'), et0_7: e(C2, 'ET0 de los últimos 7 días'), rain28: e(C2, 'lluvia de los últimos 28 días'), et0_28: e(C2, 'ET0 de los últimos 28 días'),
  rainSinceNov1: e(C2, 'lluvia desde el 1 de noviembre'), et0SinceNov1: e(C2, 'ET0 desde el 1 de noviembre'), dryspell28: e(C2, 'racha seca más larga de 28 días'),
  tmean28: e(C2, 'temperatura media de 28 días; la temperatura mueve el simulador por la ET0'), tmaxMax28: e(C2, 'máxima de Tmax en 28 días; ídem'),
  runningDepletion: e(C2, 'balance corrido acotado desde el 1 de noviembre (Kc 0.95, sin sombra ni escorrentía): una cuenta simple de lluvia y ET0, no el Dr del simulador'),
  soilAWmm: e(C2, 'agua disponible TAW = 1000·(θFC − θWP)·Zr: derivada del suelo y la raíz que el simulador usa'),
  elevation: e(C1, 'solo por la ET0 (radiación de cielo despejado): +900 m = +0.7 % de ET0 en Jutiapa. simulateCoffee recibe la ET0 ya calculada, así que la elevación sola no mueve el balance'),
  shadeTrees: e(C1, 'sombra de árboles sí/no: recorta 0.52 mm/día de evaporación en lluvias y suma el uso de agua del árbol (plotAdjust)'),
  deciduous: e(C1, 'tipo de árbol (deciduo o siempreverde): cambia el uso de agua del árbol por estación'),
  banana: e(C1, 'banano sí/no como sombra: SUPUESTO PROVISIONAL (evaporación −0.52 mm/día en lluvias y gasto de agua del banano)'),
  bananaCover: e(C1, 'fracción del suelo cubierta por copa de banano: multiplica el gasto de agua del banano, SUPUESTO PROVISIONAL (0.15 y 0.30 son convenciones)'),
};

// --- red alineada con la app: appInputs.js sobre el motor de la app (appEngine.js) ---
const app = {
  lat: e(C1, 'latitud: entra a la radiación extraterrestre de la ET0 en el motor de la app'),
  lon: e(C3, 'longitud: el motor de la app no la usa (ET0 solo usa latitud y elevación; el clima ya viene descargado). Solo identifica el punto de donde se bajó el clima'),
  cellElevation: e(C1, 'elevación de la celda: entra a la presión y a Rso de la ET0 (efecto pequeño)'),
  sowSin: e(C1, 'día de siembra (seno del día del año): el motor siembra ese día'), sowCos: e(C1, 'día de siembra (coseno)'),
  todaySin: e(C1, 'fecha de hoy (seno): hasta dónde corre el motor y qué clima conoce'), todayCos: e(C1, 'fecha de hoy (coseno)'),
  crop_maiz: e(C1, 'cultivo elegido: parámetros del catálogo de la app'), crop_frijol: e(C1, 'cultivo elegido'), crop_tomate: e(C1, 'cultivo elegido'),
  cycleDays: e(C1, 'ciclo elegido: define la duración de las etapas en el motor'),
  fractionElapsed: e(C2, 'fracción del ciclo transcurrida: (hoy − siembra) / ciclo'), daysToHarvest: e(C2, 'días que faltan a la cosecha: ciclo − (hoy − siembra)'),
  soilAvailableWater: e(C1, 'agua disponible del suelo elegido (aguaDisponible en simularBalance)'),
  kcMid: e(C1, 'Kc medio del catálogo del cultivo'), rootDepth: e(C1, 'raíz máxima del catálogo'), p: e(C1, 'fracción de agotamiento p del catálogo'), ky: e(C1, 'Ky del catálogo (entra al factor de rendimiento)'),
  reserve: e(C2, 'salida del motor de la app hasta hoy: agua en reserva'), depletionOverTaw: e(C2, 'salida del motor hasta hoy: agotamiento / TAW'), ks: e(C2, 'salida del motor hasta hoy: Ks del día'),
  stage_inicial: e(C2, 'etapa de hoy, derivada de siembra, ciclo y hoy'), stage_desarrollo: e(C2, 'etapa de hoy'), stage_media: e(C2, 'etapa de hoy'), stage_finalCiclo: e(C2, 'etapa de hoy'),
  factorSoFar: e(C2, 'salida del motor hasta hoy: factor de rendimiento acumulado'), stressDays7: e(C2, 'salida del motor hasta hoy: días con estrés en los últimos 7'), stressDaysSinceSowing: e(C2, 'salida del motor hasta hoy: días con estrés desde la siembra'),
  rain7: e(C2, 'lluvia, 7 días'), rain14: e(C2, 'lluvia, 14 días'), rain28: e(C2, 'lluvia, 28 días'), rainSinceSowing: e(C2, 'lluvia desde la siembra'),
  et0Sum7: e(C2, 'ET0, 7 días'), et0Sum14: e(C2, 'ET0, 14 días'), et0Sum28: e(C2, 'ET0, 28 días'), et0SumSinceSowing: e(C2, 'ET0 desde la siembra'),
  longestDrySpell28: e(C2, 'racha seca más larga de 28 días'), tmaxMean14: e(C2, 'Tmax media de 14 días (la temperatura mueve la ET0)'), tminMean14: e(C2, 'Tmin media de 14 días'),
  cropNeed7: e(C2, 'salida del motor hasta hoy: ETc de los últimos 7 días'),
};

function table(names, classes, what) {
  const missing = names.filter((n) => !classes[n]), extra = Object.keys(classes).filter((n) => !names.includes(n));
  if (missing.length || extra.length) throw new Error(`${what}: sin clasificar ${JSON.stringify(missing)}, de más ${JSON.stringify(extra)}`);
  return names.map((n) => ({ name: n, ...classes[n] }));
}
const count = (rows) => ({ drivesSimulator: rows.filter((r) => r.class === 1).length, derivedSummary: rows.filter((r) => r.class === 2).length, noEffect: rows.filter((r) => r.class === 3).length, total: rows.length });

const v3net = readJson('web/data/emulator_v3_mlp.json');
if (v3net.architecture[0] !== FEATURE_NAMES_V3.length) throw new Error('emulator_v3_mlp.json no tiene 47 entradas');
const coffeeNet = readJson('web/data/coffee_ptc_mlp_v2.json');
const appNet = readJson('web/data/app_mlp.json');
if (JSON.stringify(coffeeNet.inputNames) !== JSON.stringify(STATE_NAMES_V2)) throw new Error('coffee_ptc_mlp_v2.json: nombres de entrada distintos');
if (JSON.stringify(appNet.inputNames) !== JSON.stringify(APP_INPUT_NAMES)) throw new Error('app_mlp.json: nombres de entrada distintos');

const networks = {
  sevenCropPredictorV3: { file: 'web/data/emulator_v3_mlp.json', note: 'el archivo no trae inputNames; los nombres son FEATURE_NAMES_V3 (emulatorV3.js), el orden con que se generaron las muestras', inputs: table(FEATURE_NAMES_V3, v3, 'v3') },
  coffeePredictThenChooseV2: { file: 'web/data/coffee_ptc_mlp_v2.json', note: 'banana y bananaCover: supuesto provisional', inputs: table(coffeeNet.inputNames, coffee, 'café') },
  appAlignedNetwork: { file: 'web/data/app_mlp.json', note: 'las entradas salen del motor de la app (appEngine.js), no de simulate.js', inputs: table(appNet.inputNames, app, 'app') },
};
for (const n of Object.values(networks)) n.counts = count(n.inputs);

const decisionTime = [
  { item: 'priority (ahorrar agua / proteger el cultivo; café)', acts: 'choice criterion', how: 'fija el precio de regar (3 o 1 días de estrés); la elección es predicción > precio. El simulador no tiene prioridad: solo da los días de estrés evitados', simulatorResponds: false },
  { item: 'regla de antracnosis por estrés', acts: 'choice criterion', how: 'si el aviso está activo por estrés hídrico la prioridad pasa a proteger (effectivePriority); cambia la elección, no el simulador', simulatorResponds: false },
  { item: 'canResow (puedo resembrar)', acts: 'stated constraint', how: 'con falso solo queda dejar el campo (valor 0); se aplica al elegir, no cambia ninguna simulación', simulatorResponds: false },
  { item: 'hasIrrigation / irrigationType', acts: 'stated constraint', how: 'se declara y se aplica al elegir; el simulador tiene modos de riego (ninguno, limitado, completo) pero esta bandera declarada no los cambia', simulatorResponds: false },
  { item: 'clase de fertilidad', acts: 'stated multiplier', how: 'multiplica el rendimiento (AquaCrop tabla 2.13a); el simulador lo aplica con la opción factors.fertilityClass (apagada por defecto), la red no lo ve y no se reentrenó: la decisión multiplica las predicciones', simulatorResponds: true },
  { item: 'calor en floración (maíz, tomate)', acts: 'simulator option, not a network input', how: 'el simulador lo aplica con la opción factors.heat (apagada por defecto); ninguna red lo toma como entrada', simulatorResponds: true },
  { item: 'nivel de plaga declarado (pestLevel) y avisos de roya, minador y antracnosis', acts: 'notice only', how: 'se muestran y se llevan; no cambian el rendimiento ni el estrés (no hay función de daño con fuente)', simulatorResponds: false },
  { item: 'momento del abono (aviso de abono)', acts: 'notice only', how: 'aviso por ventanas de Anacafe y suelo húmedo; no entra al simulador', simulatorResponds: false },
  { item: 'precios (MAGA)', acts: 'notice only', how: 'solo registrados (prices.json); no se calcula margen', simulatorResponds: false },
  { item: 'pendiente (slopeClass), modo de riego y tipo de sucesión', acts: 'simulator inputs the v3 predictor does not take', how: 'el simulador responde (número de curva, riego) pero el predictor v3 se entrenó con pendiente plana y sin riego; la red no los ve', simulatorResponds: true },
];
const showsButSimulatorIgnores = [
  'lon de la red alineada con la app: el motor de la app no la usa (clase 3).',
  'priority: el simulador no responde; solo cambia el precio con que se juzga.',
  'canResow y hasIrrigation declarados: restricciones aplicadas al elegir, ninguna simulación cambia.',
  'pestLevel y avisos de plagas, aviso de abono, precios: solo avisos o registro; no mueven rendimiento ni estrés.',
  'elevation (café y v3) y lat / cellElevation (app) mueven el simulador solo por la ET0, y con efecto pequeño (+900 m = +0.7 % de ET0).',
  'banana y bananaCover: el simulador responde, pero solo por un supuesto provisional, no por una medida.',
];

const out = {
  meta: { task: 38, classes: { 1: 'mueve el simulador directamente', 2: 'resumen derivado de cosas que mueven el simulador, o salida del propio simulador hasta hoy', 3: 'sin efecto en el simulador' }, generatedFrom: 'lectura del código (emulatorV3.js, emulatorV2.js, coffee.js, appInputs.js, appEngine.js, factors.js, succession_lib.mjs)', provisional: 'banana y bananaCover (café v2) son un supuesto provisional, no una medida' },
  networks, decisionTimeInformationNotNetworkInput: decisionTime, algorithmShowsButSimulatorDoesNotRespond: showsButSimulatorIgnores,
};
fs.writeFileSync(path.join(root, 'web/data/parity.json'), JSON.stringify(out, null, 1));
for (const [k, n] of Object.entries(networks)) console.log(k.padEnd(28), JSON.stringify(n.counts));
