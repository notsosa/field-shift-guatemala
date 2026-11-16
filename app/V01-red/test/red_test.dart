// Pruebas de la red del equipo dentro de la app.
//
// La "referencia fija" son los casos de test/casos_red.json, generados con la referencia en JavaScript del
// repositorio (tool/generar_casos.mjs): clima, plantación, las 40 entradas esperadas y las 3 salidas esperadas.
// Dart tiene que dar las mismas entradas (1e-9) y las mismas salidas (1e-5) con el mismo clima.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:field_shift/modelos.dart';
import 'package:field_shift/motor/entradas_red.dart';
import 'package:field_shift/motor/fao56.dart';
import 'package:field_shift/motor/pesos_app.dart';
import 'package:field_shift/motor/recomendador.dart';
import 'package:field_shift/motor/red.dart';
import 'package:flutter_test/flutter_test.dart';

class _Caso {
  _Caso(this.j)
      : nombre = j['nombre'] as String,
        hoy = DateTime.parse(j['hoy'] as String),
        clima = [for (final d in j['clima'] as List<dynamic>) DiaClima.deJson(d as Map<String, dynamic>)],
        entradas = _lista(j['entradas']),
        salidasCrudas = _lista(j['salidasCrudas']),
        salidas = _lista(j['salidas']);

  final Map<String, dynamic> j;
  final String nombre;
  final DateTime hoy;
  final List<DiaClima> clima;
  final List<double> entradas;
  final List<double> salidasCrudas;
  final List<double> salidas;

  Parcela get parcela {
    final p = j['parcela'] as Map<String, dynamic>;
    return Parcela(
      nombre: 'Prueba',
      latitud: (p['latitud'] as num).toDouble(),
      longitud: (p['longitud'] as num).toDouble(),
      elevacion: (p['elevacion'] as num).toDouble(),
    );
  }

  Plantacion plantacion({
    String? cultivo,
    DateTime? fecha,
    TipoRiego riego = TipoRiego.ninguno,
  }) {
    final p = j['plantacion'] as Map<String, dynamic>;
    return Plantacion(
      cultivoId: cultivo ?? p['cultivo'] as String,
      fecha: fecha ?? DateTime.parse(p['siembra'] as String),
      ciclo: (p['ciclo'] as num).toInt(),
      suelo: Suelo.values.byName(p['suelo'] as String),
      riego: riego,
      temporadaRiego: TemporadaRiego.auxilio,
      plagaReciente: false,
      fertilizo: false,
    );
  }
}

List<double> _lista(dynamic v) => [for (final n in v as List<dynamic>) (n as num).toDouble()];

double _maxDif(List<double> a, List<double> b) {
  expect(a.length, b.length);
  var m = 0.0;
  for (var i = 0; i < a.length; i++) {
    m = math.max(m, (a[i] - b[i]).abs());
  }
  return m;
}

void main() {
  final fixture = jsonDecode(File('test/casos_red.json').readAsStringSync()) as Map<String, dynamic>;
  final casos = [for (final c in fixture['casos'] as List<dynamic>) _Caso(c as Map<String, dynamic>)];

  group('pesos y entradas', () {
    test('los nombres de las entradas de la app son los de los pesos y los de la referencia', () {
      expect(pesosAppEntradas.length, 40);
      expect(nombresEntradasRed, pesosAppEntradas);
      expect([for (final n in fixture['nombresEntradas'] as List<dynamic>) n as String], pesosAppEntradas);
      expect(pesosAppSalidas, ['factorFinal', 'estres7', 'estres14']);
      expect(() => comprobarEntradasDeLaApp(), returnsNormally);
    });

    test('comprobarEntradas falla con un mensaje claro si cambia el orden o el número', () {
      final cambiado = [...pesosAppEntradas];
      final tmp = cambiado[3];
      cambiado[3] = cambiado[4];
      cambiado[4] = tmp;
      expect(() => comprobarEntradas(pesosAppEntradas, cambiado), throwsA(isA<StateError>()));
      expect(() => comprobarEntradas(pesosAppEntradas, pesosAppEntradas.sublist(1)), throwsA(isA<StateError>()));
    });

    test('la red tiene 5 283 parámetros y la forma 40 → 64 → 32 → 16 → 3', () {
      final capas = pesosApp['layers'] as List<dynamic>;
      expect(capas.length, 4);
      var n = 0;
      final formas = <int>[40];
      for (final c in capas) {
        final w = (c as Map<String, dynamic>)['W'] as List<dynamic>;
        n += w.length * (w.first as List<dynamic>).length + (c['b'] as List<dynamic>).length;
        formas.add(w.length);
      }
      expect(n, 5283);
      expect(formas, [40, 64, 32, 16, 3]);
      expect(pesosAppCommit, matches(RegExp(r'^[0-9a-f]{40}$')));
    });
  });

  group('paridad con la referencia en JavaScript', () {
    test('hay al menos 6 casos de los tres cultivos, temprano y tarde en el ciclo, secos y húmedos', () {
      expect(casos.length, greaterThanOrEqualTo(6));
      final cultivos = {for (final c in casos) c.plantacion().cultivoId};
      expect(cultivos, {'maiz', 'frijol', 'tomate'});
      final fracciones = [for (final c in casos) c.j['fraccionDelCiclo'] as double];
      expect(fracciones.reduce(math.min), lessThanOrEqualTo(0.25));
      expect(fracciones.reduce(math.max), greaterThanOrEqualTo(0.75));
      expect(casos.any((c) => c.salidas[1] > 6), isTrue, reason: 'algún caso con estrés');
      expect(casos.any((c) => c.salidas[1] < 0.5), isTrue, reason: 'algún caso sin estrés');
    });

    var maxEntradas = 0.0;
    var maxSalidas = 0.0;
    for (final c in casos) {
      test(c.nombre, () {
        final dias = prepararClima(c.clima, c.parcela, c.hoy);
        final estados = simularBalance(
          dias: dias,
          siembra: c.plantacion().fecha,
          cultivo: c.plantacion().cultivo.parametros,
          ciclo: c.plantacion().ciclo,
          aguaDisponible: c.plantacion().suelo.aguaDisponible,
        );
        final x = entradasRed(
          parcela: c.parcela,
          plantacion: c.plantacion(),
          clima: c.clima,
          dias: dias,
          estados: estados,
          hoy: c.hoy,
        );
        expect(x.length, 40);
        for (var i = 0; i < 40; i++) {
          expect(x[i], closeTo(c.entradas[i], 1e-9), reason: 'entrada $i (${pesosAppEntradas[i]})');
        }
        maxEntradas = math.max(maxEntradas, _maxDif(x, c.entradas));

        final crudo = predecirCapas(pesosApp, x);
        for (var o = 0; o < 3; o++) {
          expect(crudo[o], closeTo(c.salidasCrudas[o], 1e-5), reason: 'salida $o (${pesosAppSalidas[o]})');
        }
        final p = predecirRed(x);
        final salida = [p.factorFinal, p.estres7, p.estres14];
        maxSalidas = math.max(maxSalidas, math.max(_maxDif(crudo, c.salidasCrudas), _maxDif(salida, c.salidas)));
        for (var o = 0; o < 3; o++) {
          expect(salida[o], closeTo(c.salidas[o], 1e-5));
        }
      });
    }

    test('diferencias máximas contra la referencia', () {
      // Se ejecuta después de los casos (las pruebas de un grupo corren en orden).
      // ignore: avoid_print
      print('Diferencia máxima de las entradas: $maxEntradas; de las salidas: $maxSalidas');
      expect(maxEntradas, lessThan(1e-9));
      expect(maxSalidas, lessThan(1e-5));
    });

    test('recomendar llena los campos de la red con las mismas salidas', () {
      for (final c in casos) {
        final r = recomendar(
          parcela: c.parcela,
          plantacion: c.plantacion(),
          clima: c.clima,
          registros: const [],
          hoy: c.hoy,
        );
        expect(r.desdeRed, isTrue, reason: c.nombre);
        expect(r.factorFinalRed, closeTo(c.salidas[0], 1e-5), reason: c.nombre);
        expect(r.estresProx7, closeTo(c.salidas[1], 1e-5), reason: c.nombre);
        expect(r.estresProx14, closeTo(c.salidas[2], 1e-5), reason: c.nombre);
        expect(r.factorFinalRed!, inInclusiveRange(0, 1));
        expect(r.estresProx7!, inInclusiveRange(0, 7));
        expect(r.estresProx14!, inInclusiveRange(0, 14));
      }
    });

    test('los campos de siempre no cambian por llamar a la red', () {
      final c = casos.first;
      final r = recomendar(parcela: c.parcela, plantacion: c.plantacion(), clima: c.clima, registros: const [], hoy: c.hoy);
      final dias = prepararClima(c.clima, c.parcela, c.hoy);
      final estados = simularBalance(
        dias: dias,
        siembra: c.plantacion().fecha,
        cultivo: c.plantacion().cultivo.parametros,
        ciclo: c.plantacion().ciclo,
        aguaDisponible: c.plantacion().suelo.aguaDisponible,
      );
      expect(r.factorRendimiento, factorRendimiento(estados, 1.25));
      expect(r.reserva, estados.last.reserva);
      expect(r.etapa, estados.last.etapa);
    });
  });

  group('donde la red no se midió, los campos quedan en nulo', () {
    final base = casos.firstWhere((c) => c.nombre.startsWith('maiz_120_franco_humedo'));

    void sinRed(Recomendacion r) {
      expect(r.desdeRed, isFalse);
      expect(r.factorFinalRed, isNull);
      expect(r.estresProx7, isNull);
      expect(r.estresProx14, isNull);
    }

    test('el caso base sí usa la red', () {
      final r = recomendar(parcela: base.parcela, plantacion: base.plantacion(), clima: base.clima, registros: const [], hoy: base.hoy);
      expect(r.desdeRed, isTrue);
    });

    test('café', () {
      final r = recomendar(
        parcela: base.parcela,
        plantacion: base.plantacion(cultivo: 'cafe'),
        clima: base.clima,
        registros: const [],
        hoy: base.hoy,
      );
      sinRed(r);
      expect(r.nivel, isNot(NivelAgua.sinDatos)); // la recomendación de siempre sigue ahí
    });

    test('con riego declarado en la plantación', () {
      for (final riego in [TipoRiego.manual, TipoRiego.goteo, TipoRiego.aspersion, TipoRiego.gravedad]) {
        final r = recomendar(
          parcela: base.parcela,
          plantacion: base.plantacion(riego: riego),
          clima: base.clima,
          registros: const [],
          hoy: base.hoy,
        );
        sinRed(r);
      }
    });

    test('con riegos anotados en un registro semanal aunque el tipo sea ninguno', () {
      final r = recomendar(
        parcela: base.parcela,
        plantacion: base.plantacion(),
        clima: base.clima,
        registros: [
          RegistroSemanal(fecha: base.hoy.subtract(const Duration(days: 3)), riegos: 1, plaga: NivelPlaga.ninguna, fertilizo: false),
        ],
        hoy: base.hoy,
      );
      sinRed(r);
      // Un registro sin riegos no quita la red.
      final sinRiegos = recomendar(
        parcela: base.parcela,
        plantacion: base.plantacion(),
        clima: base.clima,
        registros: [
          RegistroSemanal(fecha: base.hoy.subtract(const Duration(days: 3)), riegos: 0, plaga: NivelPlaga.ninguna, fertilizo: false),
        ],
        hoy: base.hoy,
      );
      expect(sinRiegos.desdeRed, isTrue);
    });

    test('fuera del 20 % al 80 % del ciclo', () {
      // El caso base tiene el 25 % del ciclo (30 de 120 días).
      Recomendacion enDia(int t) => recomendar(
            parcela: base.parcela,
            plantacion: base.plantacion(fecha: DateTime(base.hoy.year, base.hoy.month, base.hoy.day - t)),
            clima: base.clima,
            registros: const [],
            hoy: base.hoy,
          );
      sinRed(enDia(10)); // 8 %
      sinRed(enDia(23)); // 19 %
      expect(enDia(24).desdeRed, isTrue); // 20 % justo
      expect(enDia(96).desdeRed, isTrue); // 80 % justo
      sinRed(enDia(97)); // 81 %
      sinRed(enDia(110)); // 92 %
      sinRed(enDia(125)); // pasado el ciclo
      sinRed(enDia(-5)); // siembra en el futuro
    });

    test('con clima viejo (más de 10 días sin dato)', () {
      final hasta = base.hoy.subtract(const Duration(days: 11));
      final viejo = [for (final d in base.clima) if (!d.fecha.isAfter(hasta)) d];
      final r = recomendar(parcela: base.parcela, plantacion: base.plantacion(), clima: viejo, registros: const [], hoy: base.hoy);
      sinRed(r);
      expect(r.avisos, contains(Aviso.climaViejo));
      // Con 10 días de retraso todavía se considera reciente.
      final limite = base.hoy.subtract(const Duration(days: 10));
      final justo = [for (final d in base.clima) if (!d.fecha.isAfter(limite)) d];
      expect(recomendar(parcela: base.parcela, plantacion: base.plantacion(), clima: justo, registros: const [], hoy: base.hoy).desdeRed, isTrue);
    });

    test('sin clima', () {
      sinRed(recomendar(parcela: base.parcela, plantacion: base.plantacion(), clima: const [], registros: const [], hoy: base.hoy));
    });

    test('redAplica: las condiciones una por una', () {
      bool aplica({String cultivo = 'maiz', TipoRiego riego = TipoRiego.ninguno, bool viejo = false, bool estados = true}) => redAplica(
            plantacion: base.plantacion(cultivo: cultivo, riego: riego),
            registros: const [],
            hoy: base.hoy,
            climaViejo: viejo,
            hayEstados: estados,
          );
      expect(aplica(), isTrue);
      expect(aplica(cultivo: 'frijol'), isTrue);
      expect(aplica(cultivo: 'tomate'), isTrue);
      expect(aplica(cultivo: 'cafe'), isFalse);
      expect(aplica(riego: TipoRiego.goteo), isFalse);
      expect(aplica(viejo: true), isFalse);
      expect(aplica(estados: false), isFalse);
    });
  });
}
