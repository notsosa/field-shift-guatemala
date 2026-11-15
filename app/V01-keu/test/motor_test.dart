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
