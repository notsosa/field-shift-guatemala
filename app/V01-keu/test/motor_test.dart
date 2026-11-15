import 'package:field_shift/datos/clima.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/motor/fao56.dart';
import 'package:field_shift/motor/recomendador.dart';
import 'package:flutter_test/flutter_test.dart';

List<DiaAgua> _dias(int n, {double et0 = 5, double lluvia = 0}) => [
      for (var i = 0; i < n; i++) DiaAgua(fecha: DateTime(2026, 6, 1 + i), et0: et0, lluvia: lluvia),
    ];

List<DiaClima> _clima(int n, DateTime inicio, {double lluvia = 0}) => [
      for (var i = 0; i < n; i++)
        DiaClima(
          fecha: DateTime(inicio.year, inicio.month, inicio.day + i),
          tmax: 32,
          tmin: 21,
          humedad: 60,
          viento: 2,
          radiacion: 22,
          lluvia: lluvia,
        ),
    ];

void main() {
  final maiz = cultivoPorId('maiz').parametros;

  group('ET0', () {
    test('reproduce el ejemplo 18 de FAO-56 (Bruselas, 6 de julio): 3,9 mm/día', () {
      final et0 = et0PenmanMonteith(
        tmax: 21.5, tmin: 12.3, ea: 1.409, u2: 2.078, rs: 22.07,
        diaDelAnio: 187, latitud: 50.8, elevacion: 100,
      );
      expect(et0, closeTo(3.9, 0.05));
    });

    test('día del año', () {
      expect(diaDelAnio(DateTime(2026, 1, 1)), 1);
      expect(diaDelAnio(DateTime(2026, 7, 6)), 187);
    });
  });

  group('balance de agua', () {
    test('sin lluvia el suelo se agota y aparece estrés', () {
      final r = simularBalance(
        dias: _dias(60), siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150,
      );
      expect(r.length, 60);
      expect(r.last.ks, lessThan(1));
      expect(r.last.eta, lessThan(r.last.etc));
      expect(r.last.agotamiento, lessThanOrEqualTo(r.last.aguaTotal));
    });

    test('con lluvia diaria suficiente no hay estrés', () {
      final r = simularBalance(
        dias: _dias(60, lluvia: 8), siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150,
      );
      expect(r.every((d) => d.ks == 1), isTrue);
      expect(r.last.agotamiento, greaterThanOrEqualTo(0));
    });

    test('un riego reduce el agotamiento frente a no regar', () {
      final sin = simularBalance(
        dias: _dias(40), siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150,
      );
      final con = simularBalance(
        dias: _dias(40), siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150,
        riegos: {DateTime(2026, 7, 9): 30},
      );
      expect(con.last.agotamiento, lessThan(sin.last.agotamiento));
    });

    test('las etapas avanzan en orden y terminan en cosecha', () {
      final r = simularBalance(
        dias: _dias(130, lluvia: 6), siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150,
      );
      expect(r.first.etapa, Etapa.inicial);
      expect(r[60].etapa, Etapa.media);
      expect(r.last.etapa, Etapa.cosechado);
      expect(r.last.eta, 0);
    });

    test('el factor de rendimiento baja con estrés y es 1 sin estrés', () {
      final seco = simularBalance(
        dias: _dias(120), siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150,
      );
      final humedo = simularBalance(
        dias: _dias(120, lluvia: 8), siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150,
      );
      expect(factorRendimiento(humedo, maiz.ky), closeTo(1, 1e-9));
      expect(factorRendimiento(seco, maiz.ky)!, lessThan(0.6));
    });
  });

  group('agua del subsuelo al crecer las raíces', () {
    List<DiaAgua> lluvias(int n, double Function(int) f) => [
          for (var i = 0; i < n; i++) DiaAgua(fecha: DateTime(2026, 6, 1 + i), et0: 5, lluvia: f(i)),
        ];
    List<EstadoDia> correr(List<DiaAgua> dias, {Map<DateTime, double> riegos = const {}}) => simularBalance(
          dias: dias, siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150, riegos: riegos,
        );

    test('se conserva el agua en una temporada completa con raíces que crecen', () {
      final dias = lluvias(130, (i) => i % 7 == 0 ? 35 : (i % 3 == 0 ? 4 : 0));
      final riegos = {for (var i = 10; i < 120; i += 9) DateTime(2026, 6, 1 + i): 30.0};
      final r = correr(dias, riegos: riegos);
      // Agotamiento total (raíces + subsuelo) al inicio: la mitad del perfil de 1 m.
      final inicial = 0.5 * 150 * maiz.raizMaxima;
      var entra = 0.0;
      for (final d in r) {
        entra += d.lluvia - d.escorrentia - d.drenaje - d.eta + d.riego;
      }
      final final_ = r.last.agotamiento + r.last.agotamientoSubsuelo;
      expect(entra, closeTo(inicial - final_, 1e-6));
      expect(r.any((d) => d.drenaje > 0), isTrue);
      expect(r.any((d) => d.escorrentia > 0), isTrue);
    });

    test('un periodo seco antes de que crezca la raíz no cambia el agua del suelo nuevo', () {
      final r = correr(lluvias(70, (_) => 0));
      expect(r[40].agotamiento, closeTo(105.36011358, 1e-6)); // valor del motor anterior
      expect(r.last.agotamiento, closeTo(147.06532121, 1e-6));
    });

    test('un periodo húmedo antes de que crezca la raíz deja el suelo nuevo con menos agotamiento', () {
      final r = correr(lluvias(70, (i) => i < 20 ? 25 : 0));
      expect(r[40].agotamiento, lessThan(83.12956699 - 5)); // el motor anterior daba 83.13
      expect(r[19].drenaje, greaterThan(0));
      expect(r[19].agotamientoSubsuelo, lessThan(0.5 * 150 * (1.0 - r[19].aguaTotal / 150)));
    });

    test('el factor de rendimiento no cambia cuando pasan los días después de la cosecha', () {
      final dias = _dias(160, lluvia: 3.5); // el ciclo de 120 días termina el 28 de septiembre
      final alCosechar = simularBalance(
        dias: dias.sublist(0, 120), siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150,
      );
      final despues = simularBalance(
        dias: dias, siembra: DateTime(2026, 6, 1), cultivo: maiz, ciclo: 120, aguaDisponible: 150,
      );
      expect(despues.last.etapa, Etapa.cosechado);
      expect(factorRendimiento(alCosechar, maiz.ky)!, inExclusiveRange(0.05, 0.95));
      expect(factorRendimiento(despues, maiz.ky), closeTo(factorRendimiento(alCosechar, maiz.ky)!, 1e-12));
    });
  });

  group('recomendador', () {
    const parcela = Parcela(nombre: 'Prueba', latitud: 14.8, longitud: -89.54, elevacion: 407);
    Plantacion plantacion({TipoRiego riego = TipoRiego.goteo}) => Plantacion(
          cultivoId: 'maiz', fecha: DateTime(2026, 6, 1), ciclo: 120, suelo: Suelo.franco,
          riego: riego, temporadaRiego: TemporadaRiego.auxilio, plagaReciente: false, fertilizo: false,
        );
    final hoy = DateTime(2026, 7, 20);

    test('sin clima guardado pide sincronizar', () {
      final r = recomendar(parcela: parcela, plantacion: plantacion(), clima: [], registros: [], hoy: hoy);
      expect(r.nivel, NivelAgua.sinDatos);
      expect(r.avisos, contains(Aviso.climaViejo));
    });

    test('temporada seca: estrés y riego sugerido', () {
      final r = recomendar(
        parcela: parcela, plantacion: plantacion(), clima: _clima(50, DateTime(2026, 6, 1)), registros: [], hoy: hoy,
      );
      expect(r.nivel, NivelAgua.estres);
      expect(r.riegoSugerido, greaterThan(0));
      expect(r.riegosSugeridos, greaterThan(0));
      expect(r.diasDesdeSiembra, 49);
      expect(r.diasACosecha, 71);
      expect(r.avisos, contains(Aviso.registroPendiente));
    });

    test('sin riego disponible no sugiere regar', () {
      final r = recomendar(
        parcela: parcela, plantacion: plantacion(riego: TipoRiego.ninguno),
        clima: _clima(50, DateTime(2026, 6, 1)), registros: [], hoy: hoy,
      );
      expect(r.nivel, NivelAgua.estres);
      expect(r.riegoSugerido, 0);
    });

    test('con lluvia frecuente el cultivo está bien', () {
      final r = recomendar(
        parcela: parcela, plantacion: plantacion(),
        clima: _clima(50, DateTime(2026, 6, 1), lluvia: 9), registros: [], hoy: hoy,
      );
      expect(r.nivel, NivelAgua.bien);
      expect(r.riegoSugerido, 0);
    });

    test('registrar riegos mejora la reserva y la precisión', () {
      final clima = _clima(50, DateTime(2026, 6, 1));
      final sin = recomendar(parcela: parcela, plantacion: plantacion(), clima: clima, registros: [], hoy: hoy);
      final registros = [
        RegistroSemanal(fecha: DateTime(2026, 7, 13), riegos: 5, plaga: NivelPlaga.ninguna, fertilizo: true),
        RegistroSemanal(fecha: DateTime(2026, 7, 20), riegos: 5, plaga: NivelPlaga.moderada, fertilizo: false),
      ];
      final con = recomendar(parcela: parcela, plantacion: plantacion(), clima: clima, registros: registros, hoy: hoy);
      expect(con.reserva, greaterThan(sin.reserva));
      expect(con.precision.index, greaterThan(sin.precision.index));
      expect(con.avisos, contains(Aviso.plaga));
      expect(con.avisos, isNot(contains(Aviso.registroPendiente)));
    });

    test('los días sin dato observado se completan y se cuentan', () {
      final r = recomendar(
        parcela: parcela, plantacion: plantacion(), clima: _clima(40, DateTime(2026, 6, 1)), registros: [], hoy: hoy,
      );
      expect(r.diasEstimados, 10);
      expect(r.ultimoClima, DateTime(2026, 7, 10));
    });

    test('el factor de rendimiento de la recomendación no depende de cuánto pasó después de la cosecha', () {
      Recomendacion en(DateTime dia) => recomendar(
            parcela: parcela, plantacion: plantacion(riego: TipoRiego.ninguno),
            clima: _clima(dia.difference(DateTime(2026, 6, 1)).inDays + 1, DateTime(2026, 6, 1), lluvia: 3.5),
            registros: [], hoy: dia,
          );
      final enCosecha = en(DateTime(2026, 9, 28));
      final despues = en(DateTime(2026, 10, 25));
      expect(enCosecha.factorRendimiento!, inExclusiveRange(0.05, 0.95));
      expect(despues.factorRendimiento, closeTo(enCosecha.factorRendimiento!, 1e-12));
    });

    group('recordatorio de fertilizar atado al agua', () {
      final dia = DateTime(2026, 7, 5); // 34 días después de la siembra: etapa de desarrollo
      List<DiaClima> clima({required bool llovio}) => [
            for (final d in _clima(35, DateTime(2026, 6, 1)))
              DiaClima(
                fecha: d.fecha, tmax: d.tmax, tmin: d.tmin, humedad: d.humedad, viento: d.viento,
                radiacion: d.radiacion,
                lluvia: llovio && !d.fecha.isBefore(DateTime(2026, 6, 30)) && d.fecha.day % 2 == 1 ? 6 : 0,
              ),
          ];
      Recomendacion en(TipoRiego riego, {required bool llovio}) => recomendar(
            parcela: parcela, plantacion: plantacion(riego: riego), clima: clima(llovio: llovio),
            registros: [], hoy: dia,
          );

      test('sin lluvia en la semana y sin riego no se recomienda fertilizar: queda en espera', () {
        final r = en(TipoRiego.ninguno, llovio: false);
        expect(r.etapa, Etapa.desarrollo);
        expect(r.lluviaSemana, 0);
        expect(r.avisos, isNot(contains(Aviso.fertilizar)));
        expect(r.avisos, contains(Aviso.fertilizarEnEspera));
      });

      test('si llovió en los últimos siete días se recomienda fertilizar', () {
        final r = en(TipoRiego.ninguno, llovio: true);
        expect(r.lluviaSemana, greaterThan(0));
        expect(r.avisos, contains(Aviso.fertilizar));
        expect(r.avisos, isNot(contains(Aviso.fertilizarEnEspera)));
      });

      test('con riego se recomienda fertilizar aunque no llueva', () {
        final r = en(TipoRiego.goteo, llovio: false);
        expect(r.avisos, contains(Aviso.fertilizar));
        expect(r.avisos, isNot(contains(Aviso.fertilizarEnEspera)));
      });

      test('si ya fertilizó no aparece ninguno de los dos', () {
        final r = recomendar(
          parcela: parcela, plantacion: plantacion(riego: TipoRiego.ninguno), clima: clima(llovio: false),
          registros: [RegistroSemanal(fecha: dia, riegos: 0, plaga: NivelPlaga.ninguna, fertilizo: true)], hoy: dia,
        );
        expect(r.avisos, isNot(contains(Aviso.fertilizar)));
        expect(r.avisos, isNot(contains(Aviso.fertilizarEnEspera)));
      });
    });

    group('lluvia sin dato', () {
      final registros = [
        RegistroSemanal(fecha: DateTime(2026, 7, 13), riegos: 2, plaga: NivelPlaga.ninguna, fertilizo: true),
        RegistroSemanal(fecha: DateTime(2026, 7, 20), riegos: 2, plaga: NivelPlaga.ninguna, fertilizo: true),
      ];
      Recomendacion con(List<DiaClima> clima) =>
          recomendar(parcela: parcela, plantacion: plantacion(), clima: clima, registros: registros, hoy: hoy);

      test('un día con lluvia faltante queda marcado como estimado, sin inventar lluvia, y baja la precisión', () {
        final completo = _clima(50, DateTime(2026, 6, 1), lluvia: 3);
        final base = con(completo);
        expect(base.precision, Precision.alta);
        expect(base.diasEstimados, 0);

        final sinLluvia = [
          for (final d in completo)
            d.fecha == DateTime(2026, 7, 18)
                ? DiaClima(
                    fecha: d.fecha, tmax: d.tmax, tmin: d.tmin, humedad: d.humedad,
                    viento: d.viento, radiacion: d.radiacion, lluvia: null)
                : d,
        ];
        final r = con(sinLluvia);
        expect(r.diasEstimados, 1);
        final dia = r.ultimos.firstWhere((d) => d.fecha == DateTime(2026, 7, 18));
        expect(dia.estimado, isTrue);
        expect(dia.lluvia, 0);
        expect(r.precision, Precision.media);
      });

      test('un día incompleto antes de la última semana se cuenta pero no baja la precisión', () {
        final completo = _clima(50, DateTime(2026, 6, 1), lluvia: 3);
        final r = con([
          for (final d in completo)
            d.fecha == DateTime(2026, 7, 10)
                ? DiaClima(
                    fecha: d.fecha, tmax: d.tmax, tmin: d.tmin, humedad: d.humedad,
                    viento: d.viento, radiacion: d.radiacion, lluvia: null)
                : d,
        ]);
        expect(r.diasEstimados, 1);
        expect(r.precision, Precision.alta);
      });

      test('el retraso normal de publicación (3 a 4 días) no baja la precisión: sigue alta', () {
        final r = con(_clima(46, DateTime(2026, 6, 1), lluvia: 3)); // el dato llega hasta el 16 de julio
        expect(r.diasEstimados, 4);
        expect(r.precision, Precision.alta);
      });

      test('un retraso de siete días sí baja la precisión', () {
        final r = con(_clima(43, DateTime(2026, 6, 1), lluvia: 3)); // el dato llega hasta el 13 de julio
        expect(r.diasEstimados, 7);
        expect(r.precision.index, lessThan(Precision.alta.index));
      });

      test('un hueco dentro del rango observado en la última semana baja la precisión', () {
        final completo = _clima(50, DateTime(2026, 6, 1), lluvia: 3);
        final r = con([for (final d in completo) if (d.fecha != DateTime(2026, 7, 16)) d]);
        expect(r.diasEstimados, 1);
        expect(r.precision, Precision.media);
      });
    });
  });

  test('interpreta la respuesta de NASA POWER y descarta los -999', () {
    final r = ServicioClima.interpretar({
      'geometry': {
        'coordinates': [-89.54, 14.8, 762.46],
      },
      'properties': {
        'parameter': {
          'T2M_MAX': {'20260601': 31.2, '20260602': -999.0},
          'T2M_MIN': {'20260601': 20.1, '20260602': 19.5},
          'RH2M': {'20260601': 70.0, '20260602': 72.0},
          'WS2M': {'20260601': 1.9, '20260602': 2.1},
          'ALLSKY_SFC_SW_DWN': {'20260601': 21.0, '20260602': 20.0},
          'PRECTOTCORR': {'20260601': 4.2, '20260602': 0.0},
        },
      },
    });
    expect(r.elevacion, closeTo(762.46, 1e-6));
    expect(r.dias.length, 2);
    expect(r.dias.first.fecha, DateTime(2026, 6, 1));
    expect(r.dias.first.completo, isTrue);
    expect(r.dias.last.tmax, isNull);
    expect(r.dias.last.completo, isFalse);
  });
}
