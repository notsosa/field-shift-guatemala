/// Café: la red de riego del equipo (versión 3, con las clases de la auditoría del asesor) y los
/// avisos con fuente, en Dart puro (sin Flutter, sin red ni disco).
///
/// La referencia es `web/js/model/coffee.js` (`coffeeDecisionState`,
/// `coffeeDecisionStateV3`, `runningDepletion`, `ruleIrrigates`,
/// `effectivePriority` y los avisos). Las pruebas de `test/cafe_test.dart`
/// comparan este código con esa referencia, caso por caso.
///
/// La paridad prueba que Dart calcula lo mismo que JavaScript con la misma
/// serie de lluvia, ET₀ y temperaturas. No prueba que la red acierte con el
/// clima de la app: la red se entrenó con lluvia de ERA5 y temperaturas llevadas
/// a la altura de la parcela, y la app usa lluvia de NASA POWER, la temperatura
/// de la celda y una ET₀ calculada con la humedad relativa.
library;

import 'dart:math' as math;

import '../modelos.dart';
import 'fao56.dart';
import 'pesos_cafe.dart';
import 'red_cafe.dart';

/// Identificador del café en el catálogo.
const cultivoCafe = 'cafe';

/// La red se entrenó con decisiones a los 30, 60 y 90 días de la floración. Se
/// usa entre los 20 y los 100 días (ambos incluidos): el mismo tramo, con un
/// margen de 10 días a cada lado.
const diasMinimosDeFloracion = 20;
const diasMaximosDeFloracion = 100;

/// Temporada de floración con que se entrenó la red: la floración es 9 días después de la primera lluvia de 10 mm o más entre el
/// 15 de febrero y el 30 de abril (o el 9 de mayo si no hubo), o sea del 24 de febrero al 9 de mayo, y las decisiones fueron a los 30, 60 y 90 días
/// de ella (día del año 85 a 219 aprox.). Una decisión fuera de ahí, por ejemplo en noviembre, no se parece a nada de lo que vio. Se acepta una
/// última floración del 15 de febrero al 15 de mayo (mes*100 + día), ambos incluidos.
const floracionDesde = 215;
const floracionHasta = 515;

/// Lámina de riego que evalúa la red, mm (única con ensayo centroamericano).
const laminaRiegoCafeMm = 20.0;

/// Profundidad de raíces del café con que se entrenó la red, m (FAO-56: 0.9 a
/// 1.5). OJO: la app usa 1.0 m en su propio balance; aquí va 1.2 m porque es lo
/// que la red vio. Solo `soilAWmm`, el agotamiento corrido y la regla usan 1.2.
const raizCafeDeLaRedM = 1.2;

/// La regla FAO-56: regar si el suelo gastó más de esta fracción de su agua
/// disponible (p del café).
const fraccionRegla = 0.40;

/// Un día es seco si llovió menos de 1 mm (el mismo umbral de la referencia).
const _umbralDiaSeco = 1.0;

/// Días de clima que piden las entradas de la red (ventana de 28 días).
const _ventana = 28;

/// Días de clima que pide la roya (media de 14 días) y mínimo con dato.
const _diasRoya = 14;
const _minimoDatosRoya = 7;

/// Sin riego anotado en los últimos siete días.
const diasSinRiegoRegistrado = 7;

// Constantes de los avisos: las de `coffee.js` (ROYA, ANTRACNOSIS, ABONO).
const _royaPosibleC = [16.0, 28.0];
const _royaMeses = [6, 12];
const _antracnosisDias = 28;
const _antracnosisFraccion = 0.5;
const _abonoMeses = [5, 6, 8, 9, 10, 11];
const _abonoDiasLluvia = 7;
const _abonoLluviaMm = 10.0;

/// Nombres de las 19 entradas en el orden en que esta app las arma.
const nombresEntradasCafe = <String>[
  'daysSinceFlowering',
  'doy',
  'rain7',
  'et0_7',
  'rain28',
  'et0_28',
  'rainSinceNov1',
  'et0SinceNov1',
  'dryspell28',
  'tmean28',
  'tmaxMax28',
  'runningDepletion',
  'soilAWmm',
  'elevation',
  'shadeTrees',
  'deciduous',
  'weeds',
  'bananaRegulated',
  'bananaDense',
];

var _entradasComprobadas = false;

/// Falla con un mensaje claro si el orden o el número de entradas que arma la
/// app no coincide con el de los pesos. Se llama antes de la primera predicción.
void comprobarEntradasDeCafe() {
  if (_entradasComprobadas) return;
  comprobarEntradas(pesosCafeEntradas, nombresEntradasCafe);
  _entradasComprobadas = true;
}

/// Serie diaria, sin huecos, hasta hoy (el último elemento es hoy).
///
/// Usa ET₀ de la app y conserva una máscara de lluvia observada. La red
/// admite el rezago al final de la serie como en la referencia de Keu.
/// Los huecos anteriores al último día observado invalidan la decisión.
class SerieCafe {
  const SerieCafe({
    required this.fechas,
    required this.lluvia,
    required this.et0,
    required this.tmax,
    required this.tmin,
    this.lluviaObservada,
  });

  /// Une los días de agua con las temperaturas del clima guardado, por fecha.
  factory SerieCafe.deClima(List<DiaAgua> dias, List<DiaClima> clima) {
    final porFecha = {for (final d in clima) _clave(d.fecha): d};
    return SerieCafe(
      fechas: [for (final d in dias) soloFecha(d.fecha)],
      lluvia: [for (final d in dias) d.lluvia ?? 0],
      lluviaObservada: [for (final d in dias) d.lluvia != null],
      et0: [for (final d in dias) d.et0],
      tmax: [
        for (final d in dias)
          d.et0Estimada ? null : porFecha[_clave(d.fecha)]?.tmax,
      ],
      tmin: [
        for (final d in dias)
          d.et0Estimada ? null : porFecha[_clave(d.fecha)]?.tmin,
      ],
    );
  }

  final List<DateTime> fechas;
  final List<double> lluvia;
  final List<bool>? lluviaObservada;
  final List<double> et0;
  final List<double?> tmax;
  final List<double?> tmin;

  int get largo => fechas.length;

  /// Índice de hoy.
  int get t => fechas.length - 1;

  DateTime get hoy => fechas.last;

  bool faltanLluviasDesde(int inicio) {
    final observadas = lluviaObservada;
    if (observadas == null) return false;
    final ultima = observadas.lastIndexOf(true);
    if (ultima < inicio) return true;
    for (var i = inicio; i <= ultima; i++) {
      if (!observadas[i]) return true;
    }
    return false;
  }
}

int _clave(DateTime f) => f.year * 10000 + f.month * 100 + f.day;

/// Días enteros de [a] a [b] sin que cuente el cambio de hora.
int _diasEntre(DateTime a, DateTime b) => DateTime.utc(
  b.year,
  b.month,
  b.day,
).difference(DateTime.utc(a.year, a.month, a.day)).inDays;

/// Día del año de 1 a 366, igual que `dayOfYear` de la referencia.
int _diaDelAnio(DateTime f) => _diasEntre(DateTime.utc(f.year), f) + 1;

/// El 1 de noviembre más reciente que no pasa de [hoy]: desde ahí empieza el
/// año cafetalero.
DateTime primeroDeNoviembre(DateTime hoy) =>
    DateTime(hoy.month >= 11 ? hoy.year : hoy.year - 1, 11, 1);

double _suma(List<double> a, int desde, int hasta) {
  var s = 0.0;
  for (var i = desde; i <= hasta; i++) {
    s += a[i];
  }
  return s;
}

int _rachaSeca(List<double> lluvia, int desde, int hasta) {
  var mejor = 0, actual = 0;
  for (var i = desde; i <= hasta; i++) {
    actual = lluvia[i] < _umbralDiaSeco ? actual + 1 : 0;
    if (actual > mejor) mejor = actual;
  }
  return mejor;
}

/// Balance corrido acotado desde el 1 de noviembre: D = 0 ese día y, cada día,
/// D ← min(TAW, max(0, D + Kc·ET₀ − lluvia)). Sin escorrentía, sin sombra y sin
/// riego pasado (solo datos observables). Devuelve D al final del día [t].
double agotamientoCorrido({
  required List<double> lluvia,
  required List<double> et0,
  required int nov1,
  required int t,
  required double taw,
  required double kc,
}) {
  var d = 0.0;
  for (var i = nov1; i <= t; i++) {
    d = math.min(taw, math.max(0.0, d + kc * et0[i] - lluvia[i]));
  }
  return d;
}

/// Las 19 entradas de la red y los dos números que salen del mismo cálculo.
class EntradasCafe {
  const EntradasCafe({
    required this.x,
    required this.agotamiento,
    required this.taw,
  });

  /// Las entradas en el orden de [nombresEntradasCafe].
  final List<double> x;

  /// Agotamiento corrido desde el 1 de noviembre, mm.
  final double agotamiento;

  /// Agua disponible total de la zona de raíces de 1.2 m, mm.
  final double taw;
}

/// Las 19 entradas de la red el día de hoy (el último de la serie), o nulo si
/// la serie no llega al 1 de noviembre anterior ni tiene 28 días.
///
/// [floracion] es la fecha de la última floración (`Plantacion.fecha` del café).
EntradasCafe? entradasCafe({
  required SerieCafe serie,
  required DateTime floracion,
  required double aguaDisponible,
  required double kc,
  required double elevacion,
  required Sombra sombra,
  required SueloSurcos sueloSurcos,
}) {
  final t = serie.t;
  if (serie.largo < _ventana) return null;
  final nov1 = _diasEntre(serie.fechas.first, primeroDeNoviembre(serie.hoy));
  if (nov1 < 0 || serie.faltanLluviasDesde(math.min(nov1, t - 27))) return null;

  // Agua disponible del suelo (mm por metro) por la profundidad de raíces con que se entrenó la red.
  final taw = aguaDisponible * raizCafeDeLaRedM;
  final agotamiento = agotamientoCorrido(
    lluvia: serie.lluvia,
    et0: serie.et0,
    nov1: nov1,
    t: t,
    taw: taw,
    kc: kc,
  );

  var tm = 0.0, tmx = double.negativeInfinity;
  var n = 0;
  for (var i = t - (_ventana - 1); i <= t; i++) {
    final a = serie.tmax[i], b = serie.tmin[i];
    if (a == null || b == null) {
      continue;
    }
    tm += (a + b) / 2;
    n++;
    if (a > tmx) tmx = a;
  }
  if (n == 0) return null;

  // Árboles (perenne o caduca): shadeTrees 1; con banano, shadeTrees 0 (no se combinan). Malezas solo sin sombra: con árboles la red no tiene esa clase.
  final arboles =
      sombra == Sombra.arbolesPerennes || sombra == Sombra.arbolesCaducos;
  final malezas =
      sombra == Sombra.ninguna && sueloSurcos == SueloSurcos.malezas;
  final x = <double>[
    _diasEntre(floracion, serie.hoy).toDouble(),
    _diaDelAnio(serie.hoy).toDouble(),
    _suma(serie.lluvia, t - 6, t),
    _suma(serie.et0, t - 6, t),
    _suma(serie.lluvia, t - 27, t),
    _suma(serie.et0, t - 27, t),
    _suma(serie.lluvia, nov1, t),
    _suma(serie.et0, nov1, t),
    _rachaSeca(serie.lluvia, t - 27, t).toDouble(),
    tm / n,
    tmx,
    agotamiento,
    taw,
    elevacion,
    arboles ? 1.0 : 0.0,
    sombra == Sombra.arbolesCaducos ? 1.0 : 0.0,
    malezas ? 1.0 : 0.0,
    sombra == Sombra.bananoRegulado ? 1.0 : 0.0,
    sombra == Sombra.bananoDenso ? 1.0 : 0.0,
  ];
  assert(x.length == nombresEntradasCafe.length);
  return EntradasCafe(x: x, agotamiento: agotamiento, taw: taw);
}

// ---------------------------------------------------------------------------
// Avisos
// ---------------------------------------------------------------------------

enum TipoAvisoCafe { abono, antracnosis, roya }

/// Niveles de los avisos; [clave] es el `level` de la referencia en JavaScript.
enum NivelAvisoCafe {
  ninguno('none'),
  posible('possible'),
  aviso('notice'),
  abonarYa('apply_now'),
  esperar('wait');

  const NivelAvisoCafe(this.clave);
  final String clave;
}

/// Un aviso de condiciones (no una predicción de daño) con su fuente.
class AvisoCafe {
  const AvisoCafe({
    required this.tipo,
    required this.nivel,
    required this.claveFuente,
    required this.numeros,
  });

  final TipoAvisoCafe tipo;
  final NivelAvisoCafe nivel;

  /// Clave del texto y la fuente en `fuentesCafe` (`sourceKey` de la referencia).
  final String claveFuente;

  /// Los números que activaron el aviso, para mostrarlos.
  final Map<String, double> numeros;

  /// Si se muestra al productor. El abono solo dentro de sus ventanas (fuera de
  /// ellas no hay nada que avisar); antracnosis y roya solo si están activos.
  bool get seMuestra => switch (tipo) {
    TipoAvisoCafe.abono => (numeros['enVentana'] ?? 0) == 1,
    TipoAvisoCafe.antracnosis => nivel == NivelAvisoCafe.aviso,
    TipoAvisoCafe.roya => nivel == NivelAvisoCafe.posible,
  };
}

/// Abono: «abonar ahora» solo en las ventanas de Anacafé (mayo–junio,
/// agosto–septiembre y octubre–noviembre) con el suelo húmedo (agotamiento menor
/// que el agua fácil y al menos 10 mm de lluvia en 7 días); si no, «en espera».
///
/// [agotamiento], [aguaTotal] y [p] son los del balance de la propia app el día
/// de hoy (raíz de 1.0 m, sin sombra), no los de la red.
AvisoCafe avisoAbono({
  required SerieCafe serie,
  required double agotamiento,
  required double aguaTotal,
  required double p,
}) {
  final t = serie.t;
  final mes = serie.hoy.month;
  final enVentana = _abonoMeses.contains(mes);
  final lluvia7 = _suma(serie.lluvia, math.max(0, t - _abonoDiasLluvia + 1), t);
  final raw = p * aguaTotal;
  final humedo = agotamiento < raw && lluvia7 >= _abonoLluviaMm;
  final activo = enVentana && humedo;
  return AvisoCafe(
    tipo: TipoAvisoCafe.abono,
    nivel: activo ? NivelAvisoCafe.abonarYa : NivelAvisoCafe.esperar,
    claveFuente: activo ? 'abono_ventanas' : 'abono_suelo_seco',
    numeros: {
      'mes': mes.toDouble(),
      'enVentana': enVentana ? 1 : 0,
      'agotamiento': agotamiento,
      'raw': raw,
      'lluvia7': lluvia7,
      'humedo': humedo ? 1 : 0,
    },
  );
}

/// Antracnosis por estrés: Ks < 1 en más de la mitad de los últimos 28 días,
/// con el Ks del balance de la propia app. [ks] va en orden, el último es hoy.
/// Nulo si hay menos de 28 días.
///
/// La referencia también activa el aviso con un aviso de roya «favorable» en
/// los 60 días previos; eso necesita medianas de varios años del sitio que la
/// app no tiene, así que aquí solo cuenta el estrés.
AvisoCafe? avisoAntracnosis(List<double> ks) {
  if (ks.length < _antracnosisDias) return null;
  var estres = 0;
  for (var i = ks.length - _antracnosisDias; i < ks.length; i++) {
    if (ks[i] < 1) estres++;
  }
  final fraccion = estres / _antracnosisDias;
  return AvisoCafe(
    tipo: TipoAvisoCafe.antracnosis,
    nivel: fraccion > _antracnosisFraccion
        ? NivelAvisoCafe.aviso
        : NivelAvisoCafe.ninguno,
    claveFuente: 'antracnosis',
    numeros: {'fraccionEstres28': fraccion, 'diasEstres28': estres.toDouble()},
  );
}

/// Roya, nivel «posible»: de junio a diciembre, con la temperatura media de los
/// últimos 14 días entre 16 y 28 °C. El nivel «favorable» compara el rango diurno
/// con la mediana del mes en el sitio, que la app no tiene, y no se calcula.
/// Nulo si de los últimos 14 días hay menos de 7 con temperaturas.
AvisoCafe? avisoRoya(SerieCafe serie) {
  final t = serie.t;
  if (t < _diasRoya - 1) return null;
  var sx = 0.0, sn = 0.0;
  var n = 0;
  for (var i = t - (_diasRoya - 1); i <= t; i++) {
    final a = serie.tmax[i], b = serie.tmin[i];
    if (a == null || b == null) continue;
    sx += a;
    sn += b;
    n++;
  }
  if (n < _minimoDatosRoya) return null;
  final media = (sx + sn) / (2 * n);
  final mes = serie.hoy.month;
  final enTemporada = mes >= _royaMeses[0] && mes <= _royaMeses[1];
  final posible =
      enTemporada && media >= _royaPosibleC[0] && media <= _royaPosibleC[1];
  return AvisoCafe(
    tipo: TipoAvisoCafe.roya,
    nivel: posible ? NivelAvisoCafe.posible : NivelAvisoCafe.ninguno,
    claveFuente: 'roya_posible',
    numeros: {
      'tempMedia14': media,
      'mes': mes.toDouble(),
      'diasConDato': n.toDouble(),
    },
  );
}

/// Los tres avisos de hoy; los que no se pueden calcular (poca serie) se omiten.
/// [ks] es el Ks diario del balance de la app para la misma serie.
List<AvisoCafe> avisosCafe({
  required SerieCafe serie,
  required List<double> ks,
  required double agotamiento,
  required double aguaTotal,
  required double p,
}) => [
  avisoAbono(
    serie: serie,
    agotamiento: agotamiento,
    aguaTotal: aguaTotal,
    p: p,
  ),
  ?avisoAntracnosis(ks),
  ?avisoRoya(serie),
];

// ---------------------------------------------------------------------------
// Decisión de riego
// ---------------------------------------------------------------------------

/// Lo que dice la red sobre regar 20 mm hoy.
class DecisionRiegoCafe {
  const DecisionRiegoCafe({
    required this.regar,
    required this.diasEvitados,
    required this.precio,
    required this.precioElegido,
    required this.antracnosisCambioPrioridad,
    required this.reglaRiega,
    required this.agotamiento,
    required this.taw,
    required this.entradas,
  });

  /// Conviene regar [laminaRiegoCafeMm] hoy: los días de estrés evitados que
  /// predice la red superan el precio.
  final bool regar;

  /// Días con Ks < 1 en los 30 días siguientes que evitaría regar, según la red.
  final double diasEvitados;

  /// Precio de regar que se usó, en días de estrés (3 o 1).
  final int precio;

  /// Precio de la prioridad que eligió el productor.
  final int precioElegido;

  /// El aviso de antracnosis por estrés llevó la prioridad a «proteger el
  /// cultivo» aunque el productor eligió ahorrar agua.
  final bool antracnosisCambioPrioridad;

  /// Lo que dice la regla FAO-56: regar si el agotamiento corrido supera el 40 %
  /// del agua disponible.
  final bool reglaRiega;

  /// Agotamiento corrido desde el 1 de noviembre, mm.
  final double agotamiento;

  /// Agua disponible total de la zona de raíces de 1.2 m, mm.
  final double taw;

  /// Las 19 entradas con que se evaluó la red.
  final List<double> entradas;
}

/// ¿Hay un riego anotado en los últimos siete días? Cuenta cualquier registro
/// con riegos fechado entre hace siete días y hoy.
bool hayRiegoReciente(List<RegistroSemanal> registros, DateTime hoy) =>
    registros.any((r) {
      final atras = _diasEntre(soloFecha(r.fecha), soloFecha(hoy));
      return r.riegos > 0 && atras >= 0 && atras <= diasSinRiegoRegistrado;
    });

/// Días desde la última floración hasta hoy.
int diasDesdeFloracion(Plantacion p, DateTime hoy) =>
    _diasEntre(soloFecha(p.fecha), soloFecha(hoy));

/// La red evaluada sobre las entradas ya armadas. [antracnosisPorEstres] sube la
/// prioridad a «proteger el cultivo» (precio 1) sea cual sea la que eligió el
/// productor (`effectivePriority` de la referencia).
DecisionRiegoCafe decidirRiegoCafe({
  required EntradasCafe entradas,
  required PrioridadRiego prioridad,
  required bool antracnosisPorEstres,
}) {
  comprobarEntradasDeCafe();
  final evitados = predecirCapas(pesosCafe, entradas.x)[0];
  final efectiva = antracnosisPorEstres
      ? PrioridadRiego.protegerCultivo
      : prioridad;
  return DecisionRiegoCafe(
    regar: evitados > efectiva.precio,
    diasEvitados: evitados,
    precio: efectiva.precio,
    precioElegido: prioridad.precio,
    antracnosisCambioPrioridad:
        antracnosisPorEstres && prioridad != PrioridadRiego.protegerCultivo,
    reglaRiega: entradas.agotamiento > fraccionRegla * entradas.taw,
    agotamiento: entradas.agotamiento,
    taw: entradas.taw,
    entradas: entradas.x,
  );
}

/// Motivo por el cual la red de café se reserva para otra consulta.
enum MotivoCafe {
  climaViejo,
  floracionFueraDeTemporada,
  diasFueraDeRango,
  riegoReciente,
  historialClimaticoInsuficiente,
}

MotivoCafe? _motivoCafe({
  required Plantacion plantacion,
  required List<RegistroSemanal> registros,
  required List<RegistroRiego> riegosDiarios,
  required DateTime hoy,
  required bool climaViejo,
}) {
  if (climaViejo) return MotivoCafe.climaViejo;
  final md = plantacion.fecha.month * 100 + plantacion.fecha.day;
  if (md < floracionDesde || md > floracionHasta) {
    return MotivoCafe.floracionFueraDeTemporada;
  }
  final dias = diasDesdeFloracion(plantacion, hoy);
  if (dias < diasMinimosDeFloracion || dias > diasMaximosDeFloracion) {
    return MotivoCafe.diasFueraDeRango;
  }
  if (hayRiegoReciente(registros, hoy) ||
      riegosDiarios.any((r) {
        final atras = _diasEntre(r.fecha, hoy);
        return r.rego == true && atras >= 0 && atras <= diasSinRiegoRegistrado;
      })) {
    return MotivoCafe.riegoReciente;
  }
  return null;
}

/// La decisión corresponde a cafetales dentro de la ventana del modelo.
bool redCafeAplica({
  required Plantacion plantacion,
  required List<RegistroSemanal> registros,
  List<RegistroRiego> riegosDiarios = const [],
  required DateTime hoy,
  required bool climaViejo,
}) =>
    plantacion.cultivoId == cultivoCafe &&
    _motivoCafe(
          plantacion: plantacion,
          registros: registros,
          riegosDiarios: riegosDiarios,
          hoy: hoy,
          climaViejo: climaViejo,
        ) ==
        null;

class ResultadoCafe {
  const ResultadoCafe({required this.riego, required this.avisos, this.motivo});

  final DecisionRiegoCafe? riego;
  final List<AvisoCafe> avisos;
  final MotivoCafe? motivo;
}

/// Calcula los avisos y el beneficio estimado de evaluar un riego de 20 mm.
ResultadoCafe resultadoCafe({
  required Parcela parcela,
  required Plantacion plantacion,
  required SerieCafe serie,
  required List<EstadoDia> estados,
  required List<RegistroSemanal> registros,
  List<RegistroRiego> riegosDiarios = const [],
  required bool climaViejo,
}) {
  final actual = estados.last;
  final avisos = serie.faltanLluviasDesde(math.max(0, serie.t - 27))
      ? const <AvisoCafe>[]
      : avisosCafe(
          serie: serie,
          ks: [for (final e in estados) e.ks],
          agotamiento: actual.agotamiento,
          aguaTotal: actual.aguaTotal,
          p: plantacion.cultivo.parametros.p,
        );

  final motivo = _motivoCafe(
    plantacion: plantacion,
    registros: registros,
    riegosDiarios: riegosDiarios,
    hoy: serie.hoy,
    climaViejo: climaViejo,
  );
  if (motivo != null) {
    return ResultadoCafe(riego: null, avisos: avisos, motivo: motivo);
  }

  final entradas = entradasCafe(
    serie: serie,
    floracion: plantacion.fecha,
    aguaDisponible: plantacion.suelo.aguaDisponible,
    kc: plantacion.cultivo.parametros.kcMedio,
    elevacion: parcela.elevacion ?? 500,
    sombra: plantacion.sombra,
    sueloSurcos: plantacion.sueloSurcos,
  );
  if (entradas == null) {
    return ResultadoCafe(
      riego: null,
      avisos: avisos,
      motivo: MotivoCafe.historialClimaticoInsuficiente,
    );
  }
  final hayEstres = avisos.any(
    (aviso) =>
        aviso.tipo == TipoAvisoCafe.antracnosis &&
        aviso.nivel == NivelAvisoCafe.aviso,
  );
  return ResultadoCafe(
    riego: decidirRiegoCafe(
      entradas: entradas,
      prioridad: plantacion.prioridadRiego,
      antracnosisPorEstres: hayEstres,
    ),
    avisos: avisos,
  );
}
