// Port a JS del motor de la app de Carlos (app/V01/lib/motor/fao56.dart y prepararClima de recomendador.dart, commit de origin/main
// que trae esos archivos). Puro, sin dependencias. Es el "juez" de la red alineada con la app: lo que la app calcularía con el clima real.
// Las fechas son días enteros desde 1970-01-01 UTC (dayNum); isoToDay/dayToIso convierten desde y hacia 'AAAA-MM-DD'.
// El port se probó contra la salida del código Dart real (tests/fixtures/app_engine_dart.json) a 1e-9.

const DAY_MS = 86400000;
export const isoToDay = (s) => Math.round(Date.UTC(+s.slice(0, 4), +s.slice(5, 7) - 1, +s.slice(8, 10)) / DAY_MS);
export const dayToIso = (n) => new Date(n * DAY_MS).toISOString().slice(0, 10);
/** Día del año, de 1 a 366 (diaDelAnio de fao56.dart). */
export function diaDelAnio(dayNum) {
  const y = new Date(dayNum * DAY_MS).getUTCFullYear();
  return dayNum - Math.round(Date.UTC(y, 0, 1) / DAY_MS) + 1;
}

const clamp = (x, lo, hi) => (x < lo ? lo : x > hi ? hi : x);

/** Presión de vapor de saturación en kPa (FAO-56 ec. 11). */
export const presionSaturacion = (t) => 0.6108 * Math.exp((17.27 * t) / (t + 237.3));

/** ET0 diaria en mm por Penman-Monteith (FAO-56 ec. 6); mismos pasos que et0PenmanMonteith de la app. */
export function et0PenmanMonteith({ tmax, tmin, ea, u2, rs, diaDelAnio: doy, latitud, elevacion }) {
  const tmed = (tmax + tmin) / 2;
  const es = (presionSaturacion(tmax) + presionSaturacion(tmin)) / 2;
  const delta = (4098 * presionSaturacion(tmed)) / Math.pow(tmed + 237.3, 2);
  const presion = 101.3 * Math.pow((293 - 0.0065 * elevacion) / 293, 5.26);
  const gamma = 0.000665 * presion;
  const phi = (latitud * Math.PI) / 180;
  const dr = 1 + 0.033 * Math.cos((2 * Math.PI * doy) / 365);
  const decl = 0.409 * Math.sin((2 * Math.PI * doy) / 365 - 1.39);
  const ws = Math.acos(clamp(-Math.tan(phi) * Math.tan(decl), -1, 1));
  const ra = ((24 * 60) / Math.PI) * 0.082 * dr * (ws * Math.sin(phi) * Math.sin(decl) + Math.cos(phi) * Math.cos(decl) * Math.sin(ws));
  const rso = (0.75 + 2e-5 * elevacion) * ra;
  const rns = 0.77 * rs;
  const relativa = rso > 0 ? clamp(rs / rso, 0.3, 1.0) : 0.3;
  const rnl = 4.903e-9 * ((Math.pow(tmax + 273.16, 4) + Math.pow(tmin + 273.16, 4)) / 2) * (0.34 - 0.14 * Math.sqrt(Math.max(ea, 0))) * (1.35 * relativa - 0.35);
  const rn = rns - rnl;
  const et0 = (0.408 * delta * rn + ((gamma * 900) / (tmed + 273)) * u2 * (es - ea)) / (delta + gamma * (1 + 0.34 * u2));
  return Math.max(et0, 0);
}

/**
 * Catálogo de la app (modelos.dart) para los cultivos con Ky. etapas = proporción de las cuatro etapas; ciclos = los que ofrece la app.
 * El café no está: la app no le da Ky.
 */
export const CATALOGO = {
  maiz: { id: 'maiz', ciclos: [90, 120], kcInicial: 0.30, kcMedio: 1.20, kcFinal: 0.35, etapas: [20, 35, 40, 30], raizMaxima: 1.0, p: 0.55, perenne: false, ky: 1.25 },
  frijol: { id: 'frijol', ciclos: [67, 80, 90], kcInicial: 0.40, kcMedio: 1.15, kcFinal: 0.35, etapas: [15, 25, 35, 20], raizMaxima: 0.6, p: 0.45, perenne: false, ky: 1.15 },
  tomate: { id: 'tomate', ciclos: [120, 145], kcInicial: 0.60, kcMedio: 1.15, kcFinal: 0.80, etapas: [30, 40, 45, 30], raizMaxima: 1.0, p: 0.40, perenne: false, ky: 1.05 },
};
/** Agua disponible en mm por metro de las tres clases de suelo de la app (enum Suelo). */
export const SUELOS = { arenoso: 100, franco: 150, arcilloso: 180 };

export const ETAPAS = ['inicial', 'desarrollo', 'media', 'finalCiclo', 'cosechado', 'establecido'];
const RAIZ_MINIMA = 0.20;

/** ¿Tiene el día los cinco datos que exige DiaClima.completo? (lluvia no cuenta: nula vale 0). */
export const diaCompleto = (d) => d.tmax != null && d.tmin != null && d.humedad != null && d.viento != null && d.radiacion != null;

/** ET0 de un día de clima con la humedad relativa (FAO-56 ec. 19), como prepararClima. */
export function et0DeDia(d, latitud, elevacion) {
  const hr = clamp(d.humedad, 1.0, 100.0);
  const ea = (hr / 100) * ((presionSaturacion(d.tmax) + presionSaturacion(d.tmin)) / 2);
  return et0PenmanMonteith({ tmax: d.tmax, tmin: d.tmin, ea, u2: d.viento, rs: d.radiacion, diaDelAnio: diaDelAnio(d.dia), latitud, elevacion });
}

/**
 * prepararClima de recomendador.dart. clima = [{dia, tmax, tmin, humedad, viento, radiacion, lluvia}] (null = sin dato), parcela = {latitud, elevacion}.
 * Devuelve [{dia, et0, lluvia, estimado}] sin huecos desde el primer día completo hasta `hoy`; los días sin dato llevan el promedio de la ET0 de los
 * últimos siete observados (4.0 si no hay) y lluvia 0. Si un día trae `et0` ya calculada (misma fórmula), se usa en vez de recalcularla.
 */
export function prepararClima(clima, parcela, hoy) {
  const validos = clima.filter(diaCompleto).sort((a, b) => a.dia - b.dia);
  if (validos.length === 0) return [];
  const elev = parcela.elevacion ?? 500;
  const porFecha = new Map();
  for (const d of validos) {
    const et0 = d.et0 != null ? d.et0 : et0DeDia(d, parcela.latitud, elev);
    porFecha.set(d.dia, { dia: d.dia, et0, lluvia: d.lluvia ?? 0, estimado: false });
  }
  const salida = [];
  const recientes = [];
  for (let f = validos[0].dia; f <= hoy; f++) {
    const obs = porFecha.get(f);
    if (obs) {
      salida.push(obs);
      recientes.push(obs.et0);
      if (recientes.length > 7) recientes.shift();
    } else {
      let prom = 4.0;
      if (recientes.length) { let s = recientes[0]; for (let i = 1; i < recientes.length; i++) s += recientes[i]; prom = s / recientes.length; }
      salida.push({ dia: f, et0: prom, lluvia: 0, estimado: true });
    }
  }
  return salida;
}

/**
 * simularBalance de fao56.dart. dias = salida de prepararClima; cultivo = entrada del CATALOGO; riegos = Map(dia -> mm).
 * Devuelve [{dia, etapa, kc, etc, eta, ks, agotamiento, aguaTotal, aguaFacil, lluvia, riego, estimado, reserva}].
 */
export function simularBalance({ dias, siembra, cultivo, ciclo, aguaDisponible, riegos = new Map(), numeroCurva = 78, agotamientoInicial = 0.5 }) {
  const total = cultivo.etapas.reduce((a, b) => a + b, 0);
  const f1 = (cultivo.etapas[0] / total) * ciclo;
  const f2 = f1 + (cultivo.etapas[1] / total) * ciclo;
  const f3 = f2 + (cultivo.etapas[2] / total) * ciclo;
  const s = 25400 / numeroCurva - 254;
  const salida = [];
  let agotado = null;
  let tawPrevio = 0;
  for (const d of dias) {
    const t = d.dia - siembra;
    if (!cultivo.perenne && t < 0) continue;
    let etapa, kc, zr;
    if (cultivo.perenne) {
      etapa = 'establecido'; kc = cultivo.kcMedio; zr = cultivo.raizMaxima;
    } else if (t >= ciclo) {
      etapa = 'cosechado'; kc = cultivo.kcFinal; zr = cultivo.raizMaxima;
    } else {
      zr = RAIZ_MINIMA + (cultivo.raizMaxima - RAIZ_MINIMA) * clamp(t / f2, 0, 1);
      if (t < f1) { etapa = 'inicial'; kc = cultivo.kcInicial; }
      else if (t < f2) { etapa = 'desarrollo'; kc = cultivo.kcInicial + ((cultivo.kcMedio - cultivo.kcInicial) * (t - f1)) / (f2 - f1); }
      else if (t < f3) { etapa = 'media'; kc = cultivo.kcMedio; }
      else { etapa = 'finalCiclo'; kc = cultivo.kcMedio + ((cultivo.kcFinal - cultivo.kcMedio) * (t - f3)) / Math.max(ciclo - f3, 1); }
    }
    const taw = aguaDisponible * zr;
    agotado = agotado === null ? agotamientoInicial * taw : agotado + (taw - tawPrevio) * agotamientoInicial;
    tawPrevio = taw;
    const raw = cultivo.p * taw;
    const ks = agotado <= raw ? 1.0 : clamp((taw - agotado) / (taw - raw), 0, 1);
    const etc = kc * d.et0;
    const eta = etapa === 'cosechado' ? 0.0 : ks * etc;
    const escorrentia = d.lluvia > 0.2 * s ? Math.pow(d.lluvia - 0.2 * s, 2) / (d.lluvia + 0.8 * s) : 0.0;
    const riego = riegos.get(d.dia) ?? 0.0;
    agotado = clamp(agotado - (d.lluvia - escorrentia) - riego + eta, 0, taw);
    salida.push({ dia: d.dia, etapa, kc, etc, eta, ks, agotamiento: agotado, aguaTotal: taw, aguaFacil: raw, lluvia: d.lluvia, riego, estimado: d.estimado, reserva: taw <= 0 ? 0 : clamp(1 - agotado / taw, 0, 1) });
  }
  return salida;
}

/** Factor de rendimiento por agua de FAO-33: 1 − Ky · (1 − ETa/ETc) sobre los días dados; null si no hay Ky, días o ETc. */
export function factorRendimiento(estados, ky) {
  if (ky == null || estados.length === 0) return null;
  let etc = 0, eta = 0;
  for (const d of estados) { etc += d.etc; eta += d.eta; }
  if (etc <= 0) return null;
  return clamp(1 - ky * (1 - eta / etc), 0, 1);
}

/** Días con estrés (Ks < 1, fuera de la cosecha) en una lista de estados, como diasEstres de recomendar. */
export const diasConEstres = (estados) => estados.filter((d) => d.ks < 1 && d.etapa !== 'cosechado').length;
