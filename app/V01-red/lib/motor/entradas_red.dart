/// Entradas de la red del equipo y su salida, armadas con lo que `recomendar`
/// ya tiene: la parcela, la plantación, los días de clima preparados, los
/// estados del balance de agua y la fecha de hoy. Dart puro, sin red ni disco.
///
/// El orden y las definiciones de las 40 entradas son los de
/// `web/js/model/appInputs.js` (referencia en JavaScript) y los de la sección 4
/// de `proyecto/contrato-app-modelo.md`. Las pruebas de `test/red_test.dart`
/// comparan este código con esa referencia, caso por caso.
library;

import 'dart:math' as math;

import '../modelos.dart';
import 'fao56.dart';
import 'pesos_app.dart';
import 'red.dart';

/// Cultivos con que se midió la red, en el orden de las entradas `crop_*`.
const cultivosDeLaRed = ['maiz', 'frijol', 'tomate'];

/// Etapas en el orden de las entradas `stage_*`. El 80 % del ciclo todavía no
/// es «cosechado».
const _etapasDeLaRed = [Etapa.inicial, Etapa.desarrollo, Etapa.media, Etapa.finalCiclo];

/// Un día es seco si llovió menos de 1 mm (el mismo umbral de la referencia).
const _umbralDiaSeco = 1.0;

/// Tramo del ciclo en que se midió la red: de la quinta parte a los cuatro quintos.
const fraccionMinimaRed = 0.2;
const fraccionMaximaRed = 0.8;

/// Un día de estrés esperado por semana o más: el umbral con que se midió la
/// clase «hay estrés» (predicción ≥ 0,5 días).
const umbralEstresRed = 0.5;

/// Nombres de las 40 entradas en el orden en que esta app las arma.
const nombresEntradasRed = <String>[
  'lat', 'lon', 'cellElevation',
  'sowSin', 'sowCos', 'todaySin', 'todayCos',
  'crop_maiz', 'crop_frijol', 'crop_tomate',
  'cycleDays', 'fractionElapsed', 'daysToHarvest', 'soilAvailableWater',
  'kcMid', 'rootDepth', 'p', 'ky',
  'reserve', 'depletionOverTaw', 'ks',
  'stage_inicial', 'stage_desarrollo', 'stage_media', 'stage_finalCiclo',
  'factorSoFar', 'stressDays7', 'stressDaysSinceSowing',
  'rain7', 'rain14', 'rain28', 'rainSinceSowing',
  'et0Sum7', 'et0Sum14', 'et0Sum28', 'et0SumSinceSowing',
  'longestDrySpell28', 'tmaxMean14', 'tminMean14', 'cropNeed7',
];

var _entradasComprobadas = false;

/// Falla con un mensaje claro si el orden o el número de entradas que arma la
/// app no coincide con el de los pesos. Se llama antes de la primera predicción.
void comprobarEntradasDeLaApp() {
  if (_entradasComprobadas) return;
  comprobarEntradas(pesosAppEntradas, nombresEntradasRed);
  _entradasComprobadas = true;
}

/// Lo que la red dice de los próximos días, ya recortado a sus rangos.
class PrediccionRed {
  const PrediccionRed({required this.factorFinal, required this.estres7, required this.estres14});

  /// Factor de rendimiento esperado al final del ciclo (0 a 1).
  final double factorFinal;

  /// Días con estrés hídrico esperados en los próximos 7 (0 a 7).
  final double estres7;

  /// Días con estrés hídrico esperados en los próximos 14 (0 a 14).
  final double estres14;
}

double _suma(Iterable<double> v) => v.fold(0.0, (a, b) => a + b);

/// Promedio de los últimos [n] días de [clima] que traen el dato, igual que la
/// referencia: toma las últimas [n] entradas y salta las que no lo tienen.
double _promedioObservado(List<DiaClima> clima, int n, double? Function(DiaClima) dato, double respaldo) {
  var s = 0.0;
  var c = 0;
  for (var i = math.max(0, clima.length - n); i < clima.length; i++) {
    final v = dato(clima[i]);
    if (v != null) {
      s += v;
      c++;
    }
  }
  return c > 0 ? s / c : respaldo;
}

/// Las 40 entradas de la red el día [hoy].
///
/// [dias] y [estados] son los de `prepararClima` y `simularBalance` con la
/// plantación; [clima] es el clima guardado tal como llegó de NASA POWER.
List<double> entradasRed({
  required Parcela parcela,
  required Plantacion plantacion,
  required List<DiaClima> clima,
  required List<DiaAgua> dias,
  required List<EstadoDia> estados,
  required DateTime hoy,
}) {
  final cultivo = plantacion.cultivo.parametros;
  final actual = estados.last;
  final siembra = soloFecha(plantacion.fecha);
  final transcurridos = soloFecha(hoy).difference(siembra).inDays;
  final aw = plantacion.suelo.aguaDisponible;
  final ky = cultivo.ky!;

  bool conEstres(EstadoDia d) => d.ks < 1 && d.etapa != Etapa.cosechado;
  final semana = estados.length > 7 ? estados.sublist(estados.length - 7) : estados;
  final desdeSiembra = dias.where((d) => !d.fecha.isBefore(siembra)).toList();

  double ultimos(List<DiaAgua> v, int n, double Function(DiaAgua) f) =>
      _suma((v.length > n ? v.sublist(v.length - n) : v).map(f));

  var seco = 0, rachaSeca = 0;
  for (final d in dias.length > 28 ? dias.sublist(dias.length - 28) : dias) {
    seco = d.lluvia < _umbralDiaSeco ? seco + 1 : 0;
    if (seco > rachaSeca) rachaSeca = seco;
  }

  // Los días de clima que la app tiene hasta hoy, en orden.
  final observados = clima.where((d) => !soloFecha(d.fecha).isAfter(soloFecha(hoy))).toList()
    ..sort((a, b) => a.fecha.compareTo(b.fecha));
  double? tmax(DiaClima d) => d.tmax;
  double? tmin(DiaClima d) => d.tmin;
  final tmaxMedia = _promedioObservado(observados, 14, tmax, _promedioObservado(observados, 1 << 30, tmax, 0));
  final tminMedia = _promedioObservado(observados, 14, tmin, _promedioObservado(observados, 1 << 30, tmin, 0));

  final doyS = diaDelAnio(siembra), doyH = diaDelAnio(hoy);
  final x = <double>[
    parcela.latitud, parcela.longitud, parcela.elevacion ?? 500,
    math.sin(2 * math.pi * doyS / 365), math.cos(2 * math.pi * doyS / 365),
    math.sin(2 * math.pi * doyH / 365), math.cos(2 * math.pi * doyH / 365),
    for (final c in cultivosDeLaRed) c == plantacion.cultivoId ? 1.0 : 0.0,
    plantacion.ciclo.toDouble(), transcurridos / plantacion.ciclo, (plantacion.ciclo - transcurridos).toDouble(), aw,
    cultivo.kcMedio, cultivo.raizMaxima, cultivo.p, ky,
    actual.reserva, actual.agotamiento / actual.aguaTotal, actual.ks,
    for (final e in _etapasDeLaRed) e == actual.etapa ? 1.0 : 0.0,
    factorRendimiento(estados, ky)!, semana.where(conEstres).length.toDouble(), estados.where(conEstres).length.toDouble(),
    ultimos(dias, 7, (d) => d.lluvia), ultimos(dias, 14, (d) => d.lluvia), ultimos(dias, 28, (d) => d.lluvia),
    _suma(desdeSiembra.map((d) => d.lluvia)),
    ultimos(dias, 7, (d) => d.et0), ultimos(dias, 14, (d) => d.et0), ultimos(dias, 28, (d) => d.et0),
    _suma(desdeSiembra.map((d) => d.et0)),
    rachaSeca.toDouble(), tmaxMedia, tminMedia,
    _suma(semana.map((e) => e.etc)),
  ];
  assert(x.length == nombresEntradasRed.length);
  return x;
}

/// Pasa las entradas por la red y recorta las salidas a sus rangos.
PrediccionRed predecirRed(List<double> entradas) {
  comprobarEntradasDeLaApp();
  final y = predecirCapas(pesosApp, entradas);
  return PrediccionRed(
    factorFinal: y[0].clamp(0.0, 1.0),
    estres7: y[1].clamp(0.0, 7.0),
    estres14: y[2].clamp(0.0, 14.0),
  );
}

/// ¿Se midió la red en este caso? Solo entonces se usa; si no, la app muestra
/// lo que mostraba antes. Las condiciones son las de la sección 4 del contrato:
/// maíz, frijol o tomate; a secano (tipo de riego «ninguno» y ningún riego en
/// los registros); entre el 20 % y el 80 % del ciclo; con clima reciente.
bool redAplica({
  required Plantacion plantacion,
  required List<RegistroSemanal> registros,
  required DateTime hoy,
  required bool climaViejo,
  required bool hayEstados,
}) {
  if (!hayEstados || climaViejo) return false;
  if (!cultivosDeLaRed.contains(plantacion.cultivoId)) return false;
  final cultivo = plantacion.cultivo;
  if (cultivo.perenne || cultivo.parametros.ky == null) return false;
  if (plantacion.riego != TipoRiego.ninguno) return false;
  if (registros.any((r) => r.riegos > 0)) return false;
  final fraccion = soloFecha(hoy).difference(soloFecha(plantacion.fecha)).inDays / plantacion.ciclo;
  return fraccion >= fraccionMinimaRed && fraccion <= fraccionMaximaRed;
}
