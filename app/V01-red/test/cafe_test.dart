// Pruebas del café: la red de riego (versión 3, con las clases de la auditoría del asesor), los avisos con fuente y la ventana de clima.
//
// La "referencia fija" son los casos de test/casos_cafe.json, generados con la referencia en JavaScript del repositorio
// (tool/generar_casos_cafe.mjs): series diarias sintéticas, las 19 entradas, la predicción, la decisión y los avisos.
// Dart tiene que dar las mismas entradas (1e-9), la misma predicción (1e-5), la misma decisión y los mismos niveles de aviso.
//
// La paridad prueba que Dart calcula lo mismo que JavaScript con la misma serie. No prueba que la red acierte con el clima
// de la app (lluvia de POWER, temperatura de la celda, ET0 con humedad relativa).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/datos/clima.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/motor/cafe.dart';
import 'package:field_shift/motor/fao56.dart';
import 'package:field_shift/motor/fuentes_cafe.dart';
import 'package:field_shift/motor/pesos_cafe.dart';
import 'package:field_shift/motor/recomendador.dart';
import 'package:field_shift/motor/red.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

List<double> _lista(dynamic v) => [for (final n in v as List<dynamic>) (n as num).toDouble()];

DateTime _fecha(String s) => DateTime.parse(s);

DateTime _dia(DateTime f, int n) => DateTime(f.year, f.month, f.day + n);

class _Caso {
  _Caso(this.j)
      : nombre = j['nombre'] as String,
        hoy = _fecha(j['hoy'] as String),
        esperado = j['esperado'] as Map<String, dynamic>;

  final Map<String, dynamic> j;
  final String nombre;
  final DateTime hoy;
  final Map<String, dynamic> esperado;

  Map<String, dynamic> get _serie => j['serie'] as Map<String, dynamic>;
  Map<String, dynamic> get _plantacion => j['plantacion'] as Map<String, dynamic>;
  Map<String, dynamic> get app => j['app'] as Map<String, dynamic>;

  SerieCafe get serie {
    final lluvia = _lista(_serie['lluvia']);
    final primero = _fecha(j['primerDia'] as String);
    return SerieCafe(
      fechas: [for (var i = 0; i < lluvia.length; i++) _dia(primero, i)],
      lluvia: lluvia,
      et0: _lista(_serie['et0']),
      tmax: _lista(_serie['tmax']),
      tmin: _lista(_serie['tmin']),
    );
  }

  DateTime get floracion => _fecha(j['floracion'] as String);
  Sombra get sombra => Sombra.values.byName(_plantacion['sombra'] as String);
  SueloSurcos get sueloSurcos => SueloSurcos.values.byName(_plantacion['sueloSurcos'] as String);
  PrioridadRiego get prioridad => PrioridadRiego.values.byName(_plantacion['prioridad'] as String);
  double get aguaDisponible => (_plantacion['aguaDisponible'] as num).toDouble();
  double get elevacion => ((j['parcela'] as Map<String, dynamic>)['elevacion'] as num).toDouble();
  List<double> get ks => _lista(app['ks']);

  EntradasCafe? get entradas => entradasCafe(
        serie: serie,
        floracion: floracion,
        aguaDisponible: aguaDisponible,
        kc: 0.95,
        elevacion: elevacion,
        sombra: sombra,
        sueloSurcos: sueloSurcos,
      );
}

double _maxDif(List<double> a, List<double> b) {
  expect(a.length, b.length);
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    m = math.max(m, (a[i] - b[i]).abs());
  }
  return m;
}

// ---- Clima sintético para probar `recomendar` ----

/// Clima diario de [desde] a [hasta], con humedad, viento y radiación (lo que pide la app para la ET₀).
List<DiaClima> _clima(DateTime desde, DateTime hasta, {bool seco = false, double tmax = 29, double tmin = 17}) {
  final dias = <DiaClima>[];
  final n = _dia(hasta, 0).difference(_dia(desde, 0)).inDays;
  for (var i = 0; i <= n; i++) {
    dias.add(DiaClima(
      fecha: _dia(desde, i),
      tmax: tmax + 2 * math.sin(i / 5),
      tmin: tmin + math.cos(i / 7),
      humedad: 70,
      viento: 1.8,
      radiacion: 19,
      lluvia: seco ? 0 : (i % 4 == 0 ? 14 : 0),
    ));
  }
  return dias;
}

const _parcela = Parcela(nombre: 'Prueba', latitud: 14.6, longitud: -90.5, elevacion: 1100);

Plantacion _cafe({
  required DateTime floracion,
  Sombra sombra = Sombra.ninguna,
  SueloSurcos suelo = SueloSurcos.limpio,
  PrioridadRiego prioridad = PrioridadRiego.ahorrarAgua,
  String cultivo = 'cafe',
  int? ciclo,
}) =>
    Plantacion(
      cultivoId: cultivo,
      fecha: floracion,
      ciclo: ciclo ?? (cultivo == 'cafe' ? 365 : 120),
      suelo: Suelo.franco,
      riego: TipoRiego.ninguno,
      temporadaRiego: TemporadaRiego.auxilio,
      plagaReciente: false,
      fertilizo: false,
      sombra: sombra,
      sueloSurcos: suelo,
      prioridadRiego: prioridad,
    );

// Hoy y la floración están en temporada: la red solo se usa con floración del 15 de febrero al 15 de mayo.
final _hoy = DateTime(2027, 6, 1);

Recomendacion _recomendar(
  Plantacion p, {
  DateTime? hoy,
  List<DiaClima>? clima,
  List<RegistroSemanal> registros = const [],
}) {
  final h = hoy ?? _hoy;
  return recomendar(
    parcela: _parcela,
    plantacion: p,
    clima: clima ?? _clima(DateTime(2026, 10, 1), h),
    registros: registros,
    hoy: h,
  );
}

/// Servicio de clima que anota la ventana pedida.
class _ClimaQueAnota extends ServicioClima {
  DateTime? desde;

  @override
  Future<bool> hayWifi() async => true;

  @override
  Future<ClimaDescargado> descargar({
    required double latitud,
    required double longitud,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    this.desde = desde;
    return ClimaDescargado(dias: _clima(desde, hasta), elevacion: 1100);
  }
}

void main() {
  final fixture = jsonDecode(File('test/casos_cafe.json').readAsStringSync()) as Map<String, dynamic>;
  final casos = [for (final c in fixture['casos'] as List<dynamic>) _Caso(c as Map<String, dynamic>)];

  group('pesos y entradas', () {
    test('los nombres de las entradas de la app son los de los pesos y los de la referencia', () {
      expect(pesosCafeEntradas.length, 19);
      expect(nombresEntradasCafe, pesosCafeEntradas);
      expect([for (final n in fixture['nombresEntradas'] as List<dynamic>) n as String], pesosCafeEntradas);
      expect(pesosCafeEntradas.sublist(16), ['weeds', 'bananaRegulated', 'bananaDense']);
      expect(() => comprobarEntradasDeCafe(), returnsNormally);
    });

    test('la red tiene 3 905 parámetros y la forma 19 → 64 → 32 → 16 → 1', () {
      final capas = pesosCafe['layers'] as List<dynamic>;
      var n = 0;
      final formas = <int>[19];
      for (final c in capas) {
        final w = (c as Map<String, dynamic>)['W'] as List<dynamic>;
        n += w.length * (w.first as List<dynamic>).length + (c['b'] as List<dynamic>).length;
        formas.add(w.length);
      }
      expect(n, 3905);
      expect(formas, [19, 64, 32, 16, 1]);
      expect(pesosCafeCommit, matches(RegExp(r'^[0-9a-f]{40}$')));
      expect(pesosCafeSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(fuentesCafeCommit, matches(RegExp(r'^[0-9a-f]{40}$')));
    });

    test('los casos de comprobación de los pesos (PyTorch, 32 bits) dan lo mismo con tolerancia 1e-5', () {
      final comprobacion = fixture['comprobacionPesos'] as List<dynamic>;
      expect(comprobacion.length, 50);
      var m = 0.0;
      for (final c in comprobacion) {
        final y = predecirCapas(pesosCafe, _lista((c as Map<String, dynamic>)['entradas']))[0];
        final esperado = (c['prediccion'] as num).toDouble();
        expect(y, closeTo(esperado, 1e-5));
        m = math.max(m, (y - esperado).abs());
      }
      // ignore: avoid_print
      print('Casos de comprobación de los pesos: diferencia máxima ${m.toStringAsExponential(2)}');
    });

    test('comprobarEntradas falla con un mensaje claro si cambia el orden o el número', () {
      final cambiado = [...pesosCafeEntradas];
      final tmp = cambiado[16];
      cambiado[16] = cambiado[17];
      cambiado[17] = tmp;
      expect(() => comprobarEntradas(pesosCafeEntradas, cambiado), throwsA(isA<StateError>()));
      expect(() => comprobarEntradas(pesosCafeEntradas, pesosCafeEntradas.sublist(1)), throwsA(isA<StateError>()));
    });

    test('las fuentes de los avisos traen texto, fuente y confianza', () {
      for (final k in ['abono_ventanas', 'abono_suelo_seco', 'antracnosis', 'roya_posible']) {
        final f = fuentesCafe[k]!;
        expect(f.texto, isNotEmpty, reason: k);
        expect(f.fuente, isNotEmpty, reason: k);
        expect(f.fuenteCorta, isNotEmpty, reason: k);
        expect(f.confianza, isNotEmpty, reason: k);
        expect(f.nivelConfianza, isNotEmpty, reason: k);
      }
      expect(fuentesCafe['abono_ventanas']!.nivelConfianza, 'alta');
      expect(fuentesCafe['roya_posible']!.nivelConfianza, 'orientativa');
    });
  });

  group('paridad con la referencia en JavaScript', () {
    test('hay al menos 6 casos: cada sombra, las dos prioridades, seco y húmedo, y antracnosis activa', () {
      expect(casos.length, greaterThanOrEqualTo(6));
      expect({for (final c in casos) c.sombra}, Sombra.values.toSet());
      expect({for (final c in casos) c.prioridad}, PrioridadRiego.values.toSet());
      expect(casos.any((c) => c.esperado['antracnosis']['nivel'] == 'notice'), isTrue);
      expect(casos.any((c) => c.esperado['antracnosis']['nivel'] == 'none'), isTrue);
      expect(casos.any((c) => c.esperado['antracnosis']['porEstres'] == true && c.esperado['antracnosisCambioPrioridad'] == true), isTrue);
      expect(casos.any((c) => c.esperado['regar'] == true), isTrue);
      expect(casos.any((c) => c.esperado['regar'] == false), isTrue);
      expect(casos.any((c) => c.esperado['abono']['nivel'] == 'apply_now'), isTrue);
      expect(casos.any((c) => c.esperado['roya']['nivel'] == 'possible'), isTrue);
      expect(casos.any((c) => c.esperado['roya']['nivel'] == 'none'), isTrue);
      final lluvia7 = [for (final c in casos) (c.esperado['abono']['rain7'] as num).toDouble()];
      expect(lluvia7.reduce(math.min), lessThan(10), reason: 'algún caso seco');
      expect(lluvia7.reduce(math.max), greaterThan(40), reason: 'algún caso húmedo');
    });

    var maxEntradas = 0.0;
    var maxPrediccion = 0.0;
    for (final c in casos) {
      test(c.nombre, () {
        final e = c.entradas!;
        final esperadas = _lista(c.esperado['entradas']);
        expect(e.x.length, 19);
        for (var i = 0; i < 19; i++) {
          expect(e.x[i], closeTo(esperadas[i], 1e-9), reason: 'entrada $i (${pesosCafeEntradas[i]})');
        }
        maxEntradas = math.max(maxEntradas, _maxDif(e.x, esperadas));
        expect(e.agotamiento, closeTo((c.esperado['agotamiento'] as num).toDouble(), 1e-9));
        expect(e.taw, closeTo((c.esperado['taw'] as num).toDouble(), 1e-9));

        // La decisión: con y sin la regla de la antracnosis.
        final avisos = avisosCafe(
          serie: c.serie,
          ks: c.ks,
          agotamiento: (c.app['agotamiento'] as num).toDouble(),
          aguaTotal: (c.app['aguaTotal'] as num).toDouble(),
          p: (c.app['p'] as num).toDouble(),
        );
        final antracnosis = avisos.firstWhere((a) => a.tipo == TipoAvisoCafe.antracnosis);
        final d = decidirRiegoCafe(
          entradas: e,
          prioridad: c.prioridad,
          antracnosisPorEstres: antracnosis.nivel == NivelAvisoCafe.aviso,
        );
        final prediccion = (c.esperado['prediccion'] as num).toDouble();
        expect(d.diasEvitados, closeTo(prediccion, 1e-5));
        maxPrediccion = math.max(maxPrediccion, (d.diasEvitados - prediccion).abs());
        expect(d.precio, c.esperado['precio']);
        expect(d.precioElegido, c.esperado['precioElegido']);
        expect(d.antracnosisCambioPrioridad, c.esperado['antracnosisCambioPrioridad']);
        expect(d.regar, c.esperado['regar']);
        expect(d.reglaRiega, c.esperado['reglaRiega']);

        // Los avisos: nivel exacto, fuente y los números que los activaron.
        final abono = avisos.firstWhere((a) => a.tipo == TipoAvisoCafe.abono);
        final eAbono = c.esperado['abono'] as Map<String, dynamic>;
        expect(abono.nivel.clave, eAbono['nivel']);
        expect(abono.claveFuente, eAbono['fuente']);
        expect(abono.numeros['lluvia7'], closeTo((eAbono['rain7'] as num).toDouble(), 1e-9));
        expect(abono.numeros['enVentana'] == 1, eAbono['enVentana']);
        expect(abono.numeros['humedo'] == 1, eAbono['humedo']);

        final eAntr = c.esperado['antracnosis'] as Map<String, dynamic>;
        expect(antracnosis.nivel.clave, eAntr['nivel']);
        expect(antracnosis.nivel == NivelAvisoCafe.aviso, eAntr['porEstres']);
        expect(antracnosis.numeros['diasEstres28'], (eAntr['diasEstres28'] as num).toDouble());
        expect(antracnosis.numeros['fraccionEstres28'], closeTo((eAntr['fraccion28'] as num).toDouble(), 1e-12));

        final roya = avisos.firstWhere((a) => a.tipo == TipoAvisoCafe.roya);
        final eRoya = c.esperado['roya'] as Map<String, dynamic>;
        expect(roya.nivel.clave, eRoya['nivel']);
        expect(roya.numeros['tempMedia14'], closeTo((eRoya['tempMedia14'] as num).toDouble(), 1e-9));
      });
    }

    test('diferencias máximas contra la referencia', () {
      // Se ejecuta después de los casos (las pruebas de un grupo corren en orden).
      // ignore: avoid_print
      print('Diferencia máxima de las 19 entradas: ${maxEntradas.toStringAsExponential(2)}; de la predicción: ${maxPrediccion.toStringAsExponential(2)}');
      expect(maxEntradas, lessThan(1e-9));
      expect(maxPrediccion, lessThan(1e-5));
    });

    test('la regla de la antracnosis cambia el precio solo si el productor eligió ahorrar agua', () {
      // Un caso cuya predicción cae entre 1 y 3 días (1.26 con la red v3): ahí el precio decide. La bandera de antracnosis se pasa a mano; aquí solo se prueba la regla.
      final c = casos.firstWhere((c) => c.nombre.contains('sin_sombra_seco_ahorrar_60d'));
      final e = c.entradas!;
      final ahorrar = decidirRiegoCafe(entradas: e, prioridad: PrioridadRiego.ahorrarAgua, antracnosisPorEstres: true);
      expect(ahorrar.precio, 1);
      expect(ahorrar.precioElegido, 3);
      expect(ahorrar.antracnosisCambioPrioridad, isTrue);
      final proteger = decidirRiegoCafe(entradas: e, prioridad: PrioridadRiego.protegerCultivo, antracnosisPorEstres: true);
      expect(proteger.precio, 1);
      expect(proteger.antracnosisCambioPrioridad, isFalse);
      final sin = decidirRiegoCafe(entradas: e, prioridad: PrioridadRiego.ahorrarAgua, antracnosisPorEstres: false);
      expect(sin.precio, 3);
      expect(sin.antracnosisCambioPrioridad, isFalse);
      // Aquí la red predice entre 1 y 3 días: con precio 3 no riega, con precio 1 sí.
      expect(sin.regar, isFalse);
      expect(ahorrar.regar, isTrue);
    });

    test('recomendar arma las mismas entradas con la serie de la propia app', () {
      // Clima de la app → balance de la app → entradas: lo mismo que armar las entradas con la serie.
      final floracion = DateTime(2027, 4, 2);
      final p = _cafe(floracion: floracion, sombra: Sombra.bananoRegulado);
      final clima = _clima(DateTime(2026, 10, 1), _hoy);
      final r = _recomendar(p, clima: clima);
      final serie = SerieCafe.deClima(prepararClima(clima, _parcela, _hoy), clima);
      final e = entradasCafe(
        serie: serie,
        floracion: floracion,
        aguaDisponible: Suelo.franco.aguaDisponible,
        kc: 0.95,
        elevacion: 1100,
        sombra: Sombra.bananoRegulado,
        sueloSurcos: SueloSurcos.limpio,
      )!;
      expect(r.riegoCafe, isNotNull);
      expect(r.riegoCafe!.entradas, e.x);
      expect(r.riegoCafe!.entradas[0], 60); // días desde la floración
      expect(r.riegoCafe!.entradas.sublist(14), [0, 0, 0, 1, 0]); // árboles, caduca, malezas, banano regulado, banano denso
    });
  });

  group('dónde la red aplica y dónde no', () {
    final base = _cafe(floracion: DateTime(2027, 4, 2)); // 60 días antes de hoy

    test('entre 20 y 100 días después de la floración, ambos extremos incluidos', () {
      Recomendacion enDia(int n) => _recomendar(_cafe(floracion: _dia(_hoy, -n)));
      expect(enDia(19).riegoCafe, isNull);
      expect(enDia(20).riegoCafe, isNotNull);
      expect(enDia(60).riegoCafe, isNotNull);
      expect(enDia(100).riegoCafe, isNotNull);
      expect(enDia(101).riegoCafe, isNull);
      expect(enDia(150).riegoCafe, isNull);
      expect(enDia(-5).riegoCafe, isNull); // floración en el futuro
      // Fuera del tramo los avisos siguen saliendo.
      expect(enDia(19).avisosCafe, isNotEmpty);
      expect(enDia(150).avisosCafe, isNotEmpty);
    });

    test('temporada de floración: del 15 de febrero al 15 de mayo', () {
      Recomendacion con(DateTime f, {DateTime? hoy}) => _recomendar(_cafe(floracion: f), hoy: hoy ?? _dia(f, 60), clima: _clima(DateTime(2026, 10, 1), hoy ?? _dia(f, 60)));
      expect(con(DateTime(2027, 2, 14)).riegoCafe, isNull);
      expect(con(DateTime(2027, 2, 15)).riegoCafe, isNotNull);
      expect(con(DateTime(2027, 5, 15)).riegoCafe, isNotNull);
      expect(con(DateTime(2027, 5, 16)).riegoCafe, isNull);
      // Septiembre (20 días y 60 días después) y noviembre: fuera de lo que vio la red.
      expect(con(DateTime(2026, 9, 20)).riegoCafe, isNull);
      expect(_recomendar(_cafe(floracion: DateTime(2026, 9, 20)), hoy: DateTime(2026, 11, 15), clima: _clima(DateTime(2025, 11, 1), DateTime(2026, 11, 15))).riegoCafe, isNull);
      // Los avisos siguen saliendo.
      expect(con(DateTime(2026, 9, 20)).avisosCafe, isNotEmpty);
      expect(con(DateTime(2027, 2, 14)).avisosCafe, isNotEmpty);
      expect(redCafeAplica(plantacion: _cafe(floracion: DateTime(2027, 5, 15)), registros: const [], hoy: DateTime(2027, 7, 14), climaViejo: false), isTrue);
    });

    test('con clima viejo (más de 10 días sin dato) no hay red, y con 10 días todavía sí', () {
      final viejo = _clima(DateTime(2026, 10, 1), _dia(_hoy, -11));
      final r = _recomendar(base, clima: viejo);
      expect(r.riegoCafe, isNull);
      expect(r.avisos, contains(Aviso.climaViejo));
      expect(r.avisosCafe, isNotEmpty); // los avisos salen mientras haya clima
      final justo = _clima(DateTime(2026, 10, 1), _dia(_hoy, -10));
      expect(_recomendar(base, clima: justo).riegoCafe, isNotNull);
    });

    test('con la serie corta (no llega al 1 de noviembre anterior) no hay red; con el 1 de noviembre sí', () {
      expect(_recomendar(base, clima: _clima(DateTime(2026, 12, 1), _hoy)).riegoCafe, isNull);
      expect(_recomendar(base, clima: _clima(DateTime(2026, 11, 2), _hoy)).riegoCafe, isNull);
      expect(_recomendar(base, clima: _clima(DateTime(2026, 11, 1), _hoy)).riegoCafe, isNotNull);
      // Los avisos salen con la serie corta, siempre que haya 28 días.
      final corta = _recomendar(base, clima: _clima(DateTime(2026, 12, 1), _hoy));
      expect(corta.avisosCafe.map((a) => a.tipo), containsAll([TipoAvisoCafe.abono, TipoAvisoCafe.antracnosis, TipoAvisoCafe.roya]));
      // Con menos de 28 días no hay antracnosis (ni red).
      final muyCorta = _recomendar(base, clima: _clima(_dia(_hoy, -20), _hoy));
      expect(muyCorta.riegoCafe, isNull);
      expect(muyCorta.avisosCafe.any((a) => a.tipo == TipoAvisoCafe.antracnosis), isFalse);
    });

    test('para el 1 de noviembre anterior cuenta el del mismo año desde noviembre', () {
      expect(primeroDeNoviembre(DateTime(2027, 6, 1)), DateTime(2026, 11, 1));
      expect(primeroDeNoviembre(DateTime(2026, 11, 14)), DateTime(2026, 11, 1));
      expect(primeroDeNoviembre(DateTime(2026, 11, 1)), DateTime(2026, 11, 1));
      expect(primeroDeNoviembre(DateTime(2026, 10, 31)), DateTime(2025, 11, 1));
    });

    test('con riego anotado en los últimos siete días no hay red', () {
      RegistroSemanal registro(int atras, {int riegos = 2}) =>
          RegistroSemanal(fecha: _dia(_hoy, -atras), riegos: riegos, plaga: NivelPlaga.ninguna, fertilizo: false);
      expect(_recomendar(base, registros: [registro(3)]).riegoCafe, isNull);
      expect(_recomendar(base, registros: [registro(0)]).riegoCafe, isNull);
      expect(_recomendar(base, registros: [registro(7)]).riegoCafe, isNull);
      expect(_recomendar(base, registros: [registro(8)]).riegoCafe, isNotNull);
      expect(_recomendar(base, registros: [registro(3, riegos: 0)]).riegoCafe, isNotNull); // un registro sin riegos no cuenta
      expect(hayRiegoReciente([registro(3)], _hoy), isTrue);
      expect(hayRiegoReciente([registro(9)], _hoy), isFalse);
    });

    test('otros cultivos no tienen nada de café', () {
      for (final cultivo in ['maiz', 'frijol', 'tomate']) {
        final r = _recomendar(_cafe(floracion: _dia(_hoy, -60), cultivo: cultivo));
        expect(r.riegoCafe, isNull, reason: cultivo);
        expect(r.avisosCafe, isEmpty, reason: cultivo);
      }
    });

    test('sin clima no hay nada', () {
      final r = recomendar(parcela: _parcela, plantacion: base, clima: const [], registros: const [], hoy: _hoy);
      expect(r.riegoCafe, isNull);
      expect(r.avisosCafe, isEmpty);
    });

    test('los campos de siempre no cambian por llamar a la red del café', () {
      final r = _recomendar(base);
      final dias = prepararClima(_clima(DateTime(2026, 10, 1), _hoy), _parcela, _hoy);
      final estados = simularBalance(
        dias: dias,
        siembra: base.fecha,
        cultivo: base.cultivo.parametros,
        ciclo: base.ciclo,
        aguaDisponible: base.suelo.aguaDisponible,
      );
      expect(r.reserva, estados.last.reserva);
      expect(r.agotamiento, estados.last.agotamiento);
      expect(r.desdeRed, isFalse); // la otra red (Próximos 7 días) no se toca
    });

    test('en seco la red recomienda regar y la regla de la antracnosis pasa el precio a 1', () {
      final seco = _clima(DateTime(2026, 10, 1), _hoy, seco: true);
      final r = _recomendar(base, clima: seco);
      final riego = r.riegoCafe!;
      expect(riego.reglaRiega, isTrue); // sin lluvia el agotamiento corrido supera el 40 %
      final antracnosis = r.avisosCafe.firstWhere((a) => a.tipo == TipoAvisoCafe.antracnosis);
      expect(antracnosis.nivel, NivelAvisoCafe.aviso);
      expect(riego.precio, 1);
      expect(riego.precioElegido, 3);
      expect(riego.antracnosisCambioPrioridad, isTrue);
      // Si ya eligió proteger el cultivo, la regla no cambia nada.
      final protegido = _recomendar(_cafe(floracion: base.fecha, prioridad: PrioridadRiego.protegerCultivo), clima: seco).riegoCafe!;
      expect(protegido.precio, 1);
      expect(protegido.antracnosisCambioPrioridad, isFalse);
    });

    test('con lluvia no hay aviso de antracnosis y se usa el precio elegido', () {
      final r = _recomendar(base, clima: _clima(DateTime(2026, 10, 1), _hoy).map((d) => DiaClima(
            fecha: d.fecha, tmax: d.tmax, tmin: d.tmin, humedad: d.humedad, viento: d.viento, radiacion: d.radiacion, lluvia: 25)).toList());
      expect(r.avisosCafe.firstWhere((a) => a.tipo == TipoAvisoCafe.antracnosis).nivel, NivelAvisoCafe.ninguno);
      expect(r.riegoCafe!.precio, 3);
      expect(r.riegoCafe!.antracnosisCambioPrioridad, isFalse);
    });
  });

  group('avisos', () {
    SerieCafe serie(DateTime hoy, {int dias = 40, double lluvia = 0, double tmax = 29, double tmin = 17, bool sinTemp = false}) => SerieCafe(
          fechas: [for (var i = 0; i < dias; i++) _dia(hoy, i - dias + 1)],
          lluvia: List.filled(dias, lluvia),
          et0: List.filled(dias, 4),
          tmax: List.filled(dias, sinTemp ? null : tmax),
          tmin: List.filled(dias, sinTemp ? null : tmin),
        );

    test('roya posible: de junio a diciembre con la media de 14 días entre 16 y 28 °C', () {
      AvisoCafe? roya(DateTime h, {double tx = 29, double tn = 17}) => avisoRoya(serie(h, tmax: tx, tmin: tn));
      expect(roya(DateTime(2026, 6, 15))!.nivel, NivelAvisoCafe.posible); // 23 °C
      expect(roya(DateTime(2026, 12, 31))!.nivel, NivelAvisoCafe.posible);
      expect(roya(DateTime(2026, 5, 31))!.nivel, NivelAvisoCafe.ninguno); // fuera de temporada
      expect(roya(DateTime(2027, 1, 1))!.nivel, NivelAvisoCafe.ninguno);
      expect(roya(DateTime(2026, 8, 1), tx: 24, tn: 8)!.nivel, NivelAvisoCafe.posible); // 16 °C justo
      expect(roya(DateTime(2026, 8, 1), tx: 24, tn: 7.8)!.nivel, NivelAvisoCafe.ninguno); // 15.9
      expect(roya(DateTime(2026, 8, 1), tx: 34, tn: 22)!.nivel, NivelAvisoCafe.posible); // 28 °C justo
      expect(roya(DateTime(2026, 8, 1), tx: 34, tn: 22.2)!.nivel, NivelAvisoCafe.ninguno); // 28.1
      expect(roya(DateTime(2026, 8, 1))!.claveFuente, 'roya_posible');
      // El nivel «favorable» no existe en la app: nunca sale otro nivel.
      for (final h in [DateTime(2026, 7, 1), DateTime(2026, 9, 1), DateTime(2026, 11, 1)]) {
        expect({NivelAvisoCafe.posible, NivelAvisoCafe.ninguno}, contains(roya(h, tx: 26, tn: 18)!.nivel));
      }
    });

    test('roya: con menos de 14 días de serie o menos de 7 con temperatura no se calcula', () {
      expect(avisoRoya(serie(DateTime(2026, 7, 1), dias: 13)), isNull);
      expect(avisoRoya(serie(DateTime(2026, 7, 1), dias: 14)), isNotNull);
      expect(avisoRoya(serie(DateTime(2026, 7, 1), sinTemp: true)), isNull);
      // Con retraso de POWER, los últimos días no traen temperatura: se promedian los que sí.
      final s = serie(DateTime(2026, 7, 1));
      final tmax = [...s.tmax];
      final tmin = [...s.tmin];
      for (var i = s.largo - 5; i < s.largo; i++) {
        tmax[i] = null;
        tmin[i] = null;
      }
      final r = avisoRoya(SerieCafe(fechas: s.fechas, lluvia: s.lluvia, et0: s.et0, tmax: tmax, tmin: tmin))!;
      expect(r.numeros['diasConDato'], 9);
      expect(r.numeros['tempMedia14'], closeTo(23, 1e-12));
      for (var i = s.largo - 8; i < s.largo; i++) {
        tmax[i] = null;
        tmin[i] = null;
      }
      expect(avisoRoya(SerieCafe(fechas: s.fechas, lluvia: s.lluvia, et0: s.et0, tmax: tmax, tmin: tmin)), isNull);
    });

    test('antracnosis: más de la mitad de los últimos 28 días con Ks < 1', () {
      List<double> ultimos28(int conEstres) => [...List.filled(28 - conEstres, 1.0), ...List.filled(conEstres, 0.9)];
      expect(avisoAntracnosis(ultimos28(14))!.nivel, NivelAvisoCafe.ninguno); // justo la mitad
      expect(avisoAntracnosis(ultimos28(15))!.nivel, NivelAvisoCafe.aviso);
      expect(avisoAntracnosis(ultimos28(28))!.numeros['diasEstres28'], 28);
      expect(avisoAntracnosis(ultimos28(0))!.nivel, NivelAvisoCafe.ninguno);
      expect(avisoAntracnosis(List.filled(27, 0.5)), isNull); // menos de 28 días
      // Los días anteriores a los últimos 28 no cuentan.
      expect(avisoAntracnosis([...List.filled(30, 0.2), ...List.filled(28, 1.0)])!.nivel, NivelAvisoCafe.ninguno);
      expect(avisoAntracnosis(ultimos28(15))!.claveFuente, 'antracnosis');
    });

    test('abono: ventanas de mayo–junio, agosto–septiembre y octubre–noviembre con suelo húmedo', () {
      AvisoCafe abono(DateTime h, {double lluvia = 5, double agot = 10}) =>
          avisoAbono(serie: serie(h, lluvia: lluvia), agotamiento: agot, aguaTotal: 150, p: 0.4);
      // Lluvia de 7 días: 7 × 5 = 35 mm; RAW = 60 mm.
      for (final m in [5, 6, 8, 9, 10, 11]) {
        expect(abono(DateTime(2026, m, 15)).nivel, NivelAvisoCafe.abonarYa, reason: 'mes $m');
      }
      for (final m in [1, 2, 3, 4, 7, 12]) {
        final a = abono(DateTime(2026, m, 15));
        expect(a.nivel, NivelAvisoCafe.esperar, reason: 'mes $m');
        expect(a.seMuestra, isFalse, reason: 'fuera de las ventanas no se muestra: mes $m');
      }
      // Suelo seco: agotamiento sobre el agua fácil, o poca lluvia.
      final seco = abono(DateTime(2026, 6, 15), agot: 60);
      expect(seco.nivel, NivelAvisoCafe.esperar);
      expect(seco.seMuestra, isTrue);
      expect(seco.claveFuente, 'abono_suelo_seco');
      expect(abono(DateTime(2026, 6, 15), agot: 59.9).nivel, NivelAvisoCafe.abonarYa);
      expect(abono(DateTime(2026, 6, 15), lluvia: 1.4).nivel, NivelAvisoCafe.esperar); // 9.8 mm
      expect(abono(DateTime(2026, 6, 15), lluvia: 1.5).nivel, NivelAvisoCafe.abonarYa); // 10.5 mm
      expect(abono(DateTime(2026, 6, 15)).claveFuente, 'abono_ventanas');
    });
  });

  group('plantación: campos nuevos', () {
    Map<String, dynamic> viejo() => {
          'id': 'p1',
          'nombre': 'Lote',
          'contorno': <dynamic>[],
          'cultivo': 'cafe',
          'fecha': '2027-04-02',
          'ciclo': 365,
          'suelo': 'franco',
          'riego': 'ninguno',
          'temporadaRiego': 'auxilio',
          'plagaReciente': false,
          'notaPlaga': '',
          'inicioPlaga': null,
          'nivelPlaga': 'leve',
          'plagaTratada': false,
          'tratamientoPlaga': '',
          'fertilizo': false,
          'tipoFertilizante': 'quimico',
          'notaFertilizante': '',
          'fechaFertilizante': null,
        };

    test('datos guardados antes de estos campos cargan con los valores por omisión', () {
      final p = Plantacion.deJson(viejo());
      expect(p.sombra, Sombra.ninguna);
      expect(p.sueloSurcos, SueloSurcos.limpio);
      expect(p.prioridadRiego, PrioridadRiego.ahorrarAgua);
      expect(p.cultivoId, 'cafe');
    });

    test('valores desconocidos también caen en los de omisión', () {
      final p = Plantacion.deJson({...viejo(), 'sombra': 'otra', 'prioridadRiego': 'otra', 'sueloSurcos': 'otro'});
      expect(p.sombra, Sombra.ninguna);
      expect(p.prioridadRiego, PrioridadRiego.ahorrarAgua);
      expect(p.sueloSurcos, SueloSurcos.limpio);
    });

    test('ida y vuelta por JSON', () {
      final p = _cafe(floracion: DateTime(2027, 4, 2), sombra: Sombra.bananoDenso, suelo: SueloSurcos.malezas, prioridad: PrioridadRiego.protegerCultivo);
      final j = jsonDecode(jsonEncode(p.aJson())) as Map<String, dynamic>;
      expect(j['sombra'], 'bananoDenso');
      expect(j['sueloSurcos'], 'malezas');
      expect(j.containsKey('coberturaBanano'), isFalse); // ya no hay cobertura
      expect(j['prioridadRiego'], 'protegerCultivo');
      final q = Plantacion.deJson(j);
      expect(q.sombra, Sombra.bananoDenso);
      expect(q.sueloSurcos, SueloSurcos.malezas);
      expect(q.prioridadRiego, PrioridadRiego.protegerCultivo);
      // Los métodos que reconstruyen la plantación conservan los campos.
      expect(p.conId('p9').sombra, Sombra.bananoDenso);
      expect(p.conId('p9').sueloSurcos, SueloSurcos.malezas);
      expect(p.conContorno(const []).prioridadRiego, PrioridadRiego.protegerCultivo);
    });

    test('plantaciones guardadas con banano y cobertura (0.15 o 0.30) cargan como banano regulado', () {
      // La versión anterior guardaba sombra «banano» y coberturaBanano 0.15 o 0.30. Las dos pasan a la clase regulada de la auditoría; ver modelos.dart.
      for (final cobertura in [0.15, 0.30]) {
        final p = Plantacion.deJson({...viejo(), 'sombra': 'banano', 'coberturaBanano': cobertura, 'prioridadRiego': 'protegerCultivo'});
        expect(p.sombra, Sombra.bananoRegulado, reason: '$cobertura');
        expect(p.sueloSurcos, SueloSurcos.limpio);
        expect(p.prioridadRiego, PrioridadRiego.protegerCultivo);
        // y al guardarse de nuevo ya no llevan cobertura
        expect(p.aJson()['sombra'], 'bananoRegulado');
        expect(p.aJson().containsKey('coberturaBanano'), isFalse);
      }
      // Los demás valores antiguos no cambian.
      expect(Plantacion.deJson({...viejo(), 'sombra': 'arbolesCaducos', 'coberturaBanano': 0.15}).sombra, Sombra.arbolesCaducos);
    });

    test('el precio de cada prioridad es el de la red: 3 y 1', () {
      expect(PrioridadRiego.ahorrarAgua.precio, 3);
      expect(PrioridadRiego.protegerCultivo.precio, 1);
    });
  });

  group('ventana de clima', () {
    final hoy = DateTime(2026, 11, 14);
    Plantacion de(String cultivo, int diasAtras) => _cafe(floracion: _dia(hoy, -diasAtras), cultivo: cultivo);

    test('sin café no cambia: mínimo 60 días, desde la siembra más antigua, máximo 240', () {
      expect(inicioDeClima(hoy, [de('maiz', 20)]), _dia(hoy, -60));
      expect(inicioDeClima(hoy, [de('maiz', 100)]), _dia(hoy, -100));
      expect(inicioDeClima(hoy, [de('maiz', 100), de('frijol', 70)]), _dia(hoy, -100));
      expect(inicioDeClima(hoy, [de('tomate', 400)]), _dia(hoy, -240));
      expect(inicioDeClima(hoy, const []), _dia(hoy, -60));
    });

    test('con alguna plantación de café son 365 días', () {
      expect(diasDeClimaConCafe, 365);
      expect(inicioDeClima(hoy, [de('cafe', 60)]), _dia(hoy, -365));
      expect(inicioDeClima(hoy, [de('maiz', 20), de('cafe', 60)]), _dia(hoy, -365));
      expect(inicioDeClima(hoy, [de('cafe', 300)]), _dia(hoy, -365));
      // 365 días atrás siempre alcanza el 1 de noviembre anterior (a 364 días como máximo).
      for (var d = 0; d < 365; d += 7) {
        final h = _dia(DateTime(2026, 11, 1), d);
        expect(!inicioDeClima(h, [de('cafe', 60)]).isAfter(primeroDeNoviembre(h)), isTrue, reason: '$h');
      }
    });

    test('sincronizar pide 365 días con café y 60 sin café', () async {
      for (final caso in [('cafe', 365), ('maiz', 60)]) {
        SharedPreferences.setMockInitialValues({
          'parcela': jsonEncode({'nombre': 'Finca', 'latitud': 14.6, 'longitud': -90.5, 'elevacion': 1100}),
          'plantaciones': jsonEncode([
            _cafe(floracion: _dia(hoy, -30), cultivo: caso.$1).conId('p1').aJson(),
          ]),
        });
        final servicio = _ClimaQueAnota();
        final estado = AppEstado(await Almacen.abrir(), servicioClima: servicio, reloj: () => hoy);
        expect(await estado.sincronizar(), ResultadoSync.ok);
        expect(hoy.difference(servicio.desde!).inDays, caso.$2, reason: caso.$1);
        expect(estado.clima.first.fecha, servicio.desde);
      }
    });
  });
}
