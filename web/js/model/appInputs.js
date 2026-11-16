// Entradas, referencias y verdad de la red alineada con la app (Tarea 34, parte D). Todo sale del motor de la app (appEngine.js) y SOLO de lo que
// la app tiene el día de hoy: finca (latitud, longitud, elevación de la celda de POWER), clima de NASA POWER desde min(siembra, hoy-60) hasta hoy
// (como máximo 240 días atrás), plantación (cultivo, siembra, ciclo elegido, suelo) y el estado que la app ya calcula. Nada de clima posterior a
// hoy, ni de más de 240 días atrás, ni climatología, ni pronóstico.
import { prepararClima, simularBalance, factorRendimiento, diasConEstres, diaDelAnio, CATALOGO, SUELOS } from './appEngine.js';

export const CROPS = ['maiz', 'frijol', 'tomate']; // el café no entra: la app no le da Ky
export const SOILS = ['arenoso', 'franco', 'arcilloso'];
export const STAGES = ['inicial', 'desarrollo', 'media', 'finalCiclo']; // el 80 % del ciclo todavía no es 'cosechado'
export const TARGET_NAMES = ['factorFinal', 'estres7', 'estres14'];
export const APP_INPUT_NAMES = [
  'lat', 'lon', 'cellElevation',
  'sowSin', 'sowCos', 'todaySin', 'todayCos',
  ...CROPS.map((c) => `crop_${c}`),
  'cycleDays', 'fractionElapsed', 'daysToHarvest', 'soilAvailableWater',
  'kcMid', 'rootDepth', 'p', 'ky',
  'reserve', 'depletionOverTaw', 'ks',
  ...STAGES.map((s) => `stage_${s}`),
  'factorSoFar', 'stressDays7', 'stressDaysSinceSowing',
  'rain7', 'rain14', 'rain28', 'rainSinceSowing',
  'et0Sum7', 'et0Sum14', 'et0Sum28', 'et0SumSinceSowing',
  'longestDrySpell28', 'tmaxMean14', 'tminMean14', 'cropNeed7',
];
export const N_INPUTS = APP_INPUT_NAMES.length;
export const DRY_MM = 1; // día seco: lluvia < 1 mm (el mismo umbral de maxDry en emulator.js)

/** Primer día del clima que la app descarga: desde la siembra, con mínimo 60 y máximo 240 días atrás (estado.dart, sincronizar). */
export function windowStart(siembra, hoy) {
  let desde = hoy - 60;
  if (siembra < desde) desde = siembra;
  if (desde < hoy - 240) desde = hoy - 240;
  return desde;
}

/**
 * Serie de clima de POWER de un punto: {first: dayNum del primer índice, tmax, tmin, humedad, viento, radiacion, lluvia, et0?}. `et0` (opcional)
 * es la ET0 ya calculada con la misma fórmula; si falta, prepararClima la calcula.
 */
export function withEt0(series, latitud, elevacion, et0DeDia) {
  const et0 = series.tmax.map((_, i) => (series.tmax[i] == null || series.tmin[i] == null || series.humedad[i] == null || series.viento[i] == null || series.radiacion[i] == null
    ? null
    : et0DeDia({ dia: series.first + i, tmax: series.tmax[i], tmin: series.tmin[i], humedad: series.humedad[i], viento: series.viento[i], radiacion: series.radiacion[i] }, latitud, elevacion)));
  return { ...series, et0 };
}

/** Días de clima de la serie entre dos días (inclusive), con la ET0 ya calculada si la serie la trae. */
export function climaEntre(series, desde, hasta) {
  const out = [];
  for (let d = Math.max(desde, series.first); d <= hasta; d++) {
    const i = d - series.first;
    if (i >= series.tmax.length) break;
    out.push({ dia: d, tmax: series.tmax[i], tmin: series.tmin[i], humedad: series.humedad[i], viento: series.viento[i], radiacion: series.radiacion[i], lluvia: series.lluvia[i], et0: series.et0 ? series.et0[i] : null });
  }
  return out;
}

/** Los días de clima que la app tendría el día `hoy`: lo posterior a hoy y lo anterior a la ventana no se toca. */
export const climaDeLaApp = (series, siembra, hoy) => climaEntre(series, windowStart(siembra, hoy), hoy);

const sumLast = (a, n, key) => { let s = 0; for (let i = Math.max(0, a.length - n); i < a.length; i++) s += a[i][key]; return s; };
const meanObserved = (a, n, key, fallback) => {
  let s = 0, c = 0;
  for (let i = Math.max(0, a.length - n); i < a.length; i++) if (a[i][key] != null) { s += a[i][key]; c++; }
  return c ? s / c : fallback;
};

/**
 * Entradas de la red el día `hoy` y la información de referencia que se calcula en la app.
 * farm = {lat, lon, cellElevation}; plan = {crop, cycle, soil, siembra (dayNum)}; series = serie de POWER (puede traer días posteriores: se ignoran).
 * Devuelve {x (40 valores), refApp: [factorFinal, estres7, estres14] de "lo que muestra la app hoy", refDry: [...] del adelanto en seco, estados}.
 */
export function appInputs(series, farm, plan, hoy) {
  const cultivo = CATALOGO[plan.crop];
  const aw = SUELOS[plan.soil];
  const clima = climaDeLaApp(series, plan.siembra, hoy);
  const dias = prepararClima(clima, { latitud: farm.lat, elevacion: farm.cellElevation }, hoy);
  const estados = simularBalance({ dias, siembra: plan.siembra, cultivo, ciclo: plan.cycle, aguaDisponible: aw });
  if (!estados.length) throw new Error('appInputs: la app no tiene estados ese día');
  const act = estados.at(-1);
  const t = hoy - plan.siembra;
  const stress7 = diasConEstres(estados.slice(-7));
  const stressAll = diasConEstres(estados);
  const factorSoFar = factorRendimiento(estados, cultivo.ky);
  const sinceSow = dias.filter((d) => d.dia >= plan.siembra);
  let dry = 0, best = 0;
  for (const d of dias.slice(-28)) { dry = d.lluvia < DRY_MM ? dry + 1 : 0; if (dry > best) best = dry; }
  const doyS = diaDelAnio(plan.siembra), doyT = diaDelAnio(hoy);
  const x = [
    farm.lat, farm.lon, farm.cellElevation,
    Math.sin((2 * Math.PI * doyS) / 365), Math.cos((2 * Math.PI * doyS) / 365), Math.sin((2 * Math.PI * doyT) / 365), Math.cos((2 * Math.PI * doyT) / 365),
    ...CROPS.map((c) => (c === plan.crop ? 1 : 0)),
    plan.cycle, t / plan.cycle, plan.cycle - t, aw,
    cultivo.kcMedio, cultivo.raizMaxima, cultivo.p, cultivo.ky,
    act.reserva, act.agotamiento / act.aguaTotal, act.ks,
    ...STAGES.map((s) => (s === act.etapa ? 1 : 0)),
    factorSoFar, stress7, stressAll,
    sumLast(dias, 7, 'lluvia'), sumLast(dias, 14, 'lluvia'), sumLast(dias, 28, 'lluvia'), sinceSow.reduce((a, d) => a + d.lluvia, 0),
    sumLast(dias, 7, 'et0'), sumLast(dias, 14, 'et0'), sumLast(dias, 28, 'et0'), sinceSow.reduce((a, d) => a + d.et0, 0),
    best, meanObserved(clima, 14, 'tmax', meanObserved(clima, 1e9, 'tmax', 0)), meanObserved(clima, 14, 'tmin', meanObserved(clima, 1e9, 'tmin', 0)),
    estados.slice(-7).reduce((a, e) => a + e.etc, 0),
  ];
  return { x, refApp: [factorSoFar, stress7, Math.min(2 * stress7, 14)], refDry: dryForward(dias, plan, cultivo, aw, hoy), estados, estimatedDays: dias.filter((d) => d.estimado).length };
}

/**
 * Cota "adelanto en seco": el motor de la app seguido desde hoy hasta la cosecha sin lluvia y con la ET0 media de los últimos 7 días
 * (el mismo promedio de la regla de huecos de la app). Se puede calcular en la app sin red. Devuelve [factorFinal, estres7, estres14].
 */
export function dryForward(dias, plan, cultivo, aw, hoy) {
  const fin = plan.siembra + plan.cycle - 1;
  const last7 = dias.slice(-7);
  const et0 = last7.reduce((a, d) => a + d.et0, 0) / last7.length;
  const ext = dias.slice();
  for (let d = hoy + 1; d <= fin + 14; d++) ext.push({ dia: d, et0, lluvia: 0, estimado: true });
  const est = simularBalance({ dias: ext, siembra: plan.siembra, cultivo, ciclo: plan.cycle, aguaDisponible: aw });
  return truthFrom(est, plan, cultivo, hoy);
}

/** [factorFinal, estres7, estres14] de una corrida del motor de la app que cubre el ciclo: factor hasta el último día del ciclo y días con Ks < 1 después de hoy. */
export function truthFrom(estados, plan, cultivo, hoy) {
  const fin = plan.siembra + plan.cycle - 1;
  const cyc = estados.filter((e) => e.dia <= fin);
  const after = (n) => diasConEstres(estados.filter((e) => e.dia > hoy && e.dia <= hoy + n));
  return [factorRendimiento(cyc, cultivo.ky), after(7), after(14)];
}
