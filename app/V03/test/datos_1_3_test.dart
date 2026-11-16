import 'dart:convert';

import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/datos/clima.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/eventos.dart';
import 'package:field_shift/main.dart' as app;
import 'package:field_shift/modelos.dart';
import 'package:field_shift/motor/fao56.dart' show Etapa;
import 'package:field_shift/motor/recomendador.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _hoy = DateTime(2026, 7, 20);
const _finca = Parcela(
  nombre: 'Prueba',
  latitud: 14.825,
  longitud: -89.5312,
  elevacion: 373,
);
const _cuadrado = [
  Punto(.05, .05),
  Punto(.95, .05),
  Punto(.95, .95),
  Punto(.05, .95),
];

List<Punto> _rect(double x, double y, double ancho, double alto) => [
  Punto(x, y),
  Punto(x + ancho, y),
  Punto(x + ancho, y + alto),
  Punto(x, y + alto),
];

Plantacion _siembra({
  DateTime? fecha,
  List<Punto> contorno = const [],
  TipoRiego tipo = TipoRiego.goteo,
  String cultivo = 'maiz',
  bool fertilizo = false,
}) => Plantacion(
  contorno: contorno,
  cultivoId: cultivo,
  fecha: fecha ?? DateTime(2026, 6, 1),
  ciclo: 120,
  suelo: Suelo.franco,
  riego: tipo,
  temporadaRiego: TemporadaRiego.auxilio,
  plagaReciente: false,
  fertilizo: fertilizo,
);

List<DiaClima> _climaHasta(DateTime inicio, DateTime ultimo) => [
  for (
    var f = inicio;
    !f.isAfter(ultimo);
    f = DateTime(f.year, f.month, f.day + 1)
  )
    DiaClima(
      fecha: f,
      tmax: 32,
      tmin: 21,
      humedad: 60,
      viento: 2,
      radiacion: 22,
      lluvia: 1,
    ),
];

DateTime _antes(int dias) => DateTime(_hoy.year, _hoy.month, _hoy.day - dias);

class _ClimaFalso extends ServicioClima {
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
    return ClimaDescargado(dias: _climaHasta(desde, hasta), elevacion: 300);
  }
}

/// Almacén cuya escritura de la finca falla las primeras [fallos] veces.
class _AlmacenFalla extends Almacen {
  _AlmacenFalla(super.prefs, this.fallos);
  int fallos;
  int intentos = 0;
  @override
  Future<void> guardarEstadoFinca(Map<String, dynamic> estado) async {
    intentos++;
    if (fallos > 0) {
      fallos--;
      throw StateError('disco lleno');
    }
    return super.guardarEstadoFinca(estado);
  }
}

Future<AppEstado> _abrir({
  Map<String, Object> guardado = const {},
  DateTime Function()? reloj,
}) async {
  SharedPreferences.setMockInitialValues(guardado);
  final e = AppEstado(await Almacen.abrir(), reloj: reloj ?? () => _hoy);
  await e.preparada;
  return e;
}

/// Una finca con una campaña de maíz y su lote.
Future<AppEstado> _conCampania({
  List<Punto>? contorno,
  Plantacion? siembra,
}) async {
  final e = await _abrir();
  await e.guardarParcela(_finca.con(contorno: _cuadrado));
  await e.guardarPlantacion(
    siembra ?? _siembra(contorno: contorno ?? _rect(.1, .1, .3, .3)),
  );
  return e;
}

Map<String, dynamic> _datosV3() => {
  'version': 3,
  'parcela': _finca.con(id: 'finca-x').aJson(),
  'plantaciones': <dynamic>[],
  'lotes': <dynamic>[],
  'registros': <dynamic>[],
  'suministros': <dynamic>[],
  'riegosDiarios': <dynamic>[],
  'clima': <dynamic>[],
  'ultimaSync': null,
  'eventos': <dynamic>[],
  'seleccionada': null,
};

void main() {
  group('1. arranque robusto', () {
    Future<Map<String, dynamic>> datosConCampania() async {
      final e = await _conCampania();
      return Map<String, dynamic>.from(e.exportarPaquete()['datos'] as Map);
    }

    test('V3 con JSON inválido se respalda y cae a V2', () async {
      final datos = await datosConCampania();
      final e = await _abrir(
        guardado: {
          'fincaV3': '{esto no es json',
          'fincaV2': jsonEncode({...datos, 'version': 2}),
        },
      );
      expect(e.configurada, isTrue);
      expect(e.campanias.length, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fincaV3_danada'), '{esto no es json');
      // V3 se reescribe sana; V2 queda intacta como respaldo.
      expect(jsonDecode(prefs.getString('fincaV3')!)['version'], 3);
      expect(prefs.getString('fincaV2'), isNotNull);
    });

    test('V3 con versión desconocida se respalda y cae a las claves '
        'antiguas', () async {
      final bruto = jsonEncode({..._datosV3(), 'version': 99});
      final e = await _abrir(
        guardado: {
          'fincaV3': bruto,
          'parcela': jsonEncode(_finca.con(contorno: _cuadrado).aJson()),
          'plantaciones': jsonEncode([
            _siembra(contorno: _rect(.1, .1, .3, .3)).aJson(),
          ]),
        },
      );
      expect(e.parcela, isNotNull);
      expect(e.campanias.length, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fincaV3_danada'), bruto);
      expect(jsonDecode(prefs.getString('fincaV3')!)['version'], 3);
    });

    test('V3 con estructura rota (no es una lista) también cae a V2', () async {
      final datos = await datosConCampania();
      final roto = jsonEncode({..._datosV3(), 'plantaciones': 'no-lista'});
      final e = await _abrir(
        guardado: {
          'fincaV3': roto,
          'fincaV2': jsonEncode({...datos, 'version': 2}),
        },
      );
      expect(e.campanias.length, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fincaV3_danada'), roto);
    });

    test('todo ilegible: abre vacío y conserva los textos', () async {
      final e = await _abrir(
        guardado: {
          'fincaV3': '[1,2',
          'fincaV2': 'nada',
          'plantaciones': '}{',
          'registros': '???',
          'clima': '!!',
        },
      );
      expect(e.configurada, isFalse);
      expect(e.parcela, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fincaV3_danada'), '[1,2');
      expect(prefs.getString('fincaV2_danada'), 'nada');
      expect(prefs.getString('fincaV2'), 'nada');
    });

    test('no reescribe el respaldo con el mismo texto dañado', () async {
      await _abrir(guardado: {'fincaV3': 'roto'});
      final prefs = await SharedPreferences.getInstance();
      // Vuelve a dañarse con el mismo contenido: no se crea un segundo respaldo.
      await prefs.setString('fincaV3', 'roto');
      final e = AppEstado(await Almacen.abrir(), reloj: () => _hoy);
      await e.preparada;
      expect(prefs.getString('fincaV3_danada2'), isNull);
      // Con otro contenido sí se conserva aparte.
      await prefs.setString('fincaV3', 'otro');
      final f = AppEstado(await Almacen.abrir(), reloj: () => _hoy);
      await f.preparada;
      expect(prefs.getString('fincaV3_danada'), 'roto');
      expect(prefs.getString('fincaV3_danada2'), 'otro');
    });

    test('si la escritura de arranque falla, abre y reintenta en la '
        'siguiente', () async {
      final datos = await datosConCampania();
      SharedPreferences.setMockInitialValues({
        'fincaV2': jsonEncode({...datos, 'version': 2}),
      });
      final almacen = _AlmacenFalla(await SharedPreferences.getInstance(), 1);
      final e = AppEstado(almacen, reloj: () => _hoy);
      await e.preparada; // no lanza
      expect(e.configurada, isTrue);
      expect(e.sinGuardar, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fincaV3'), isNull);
      await e.guardarRegistro(
        RegistroSemanal(
          plantacionId: e.campanias.first.id,
          fecha: _antes(1),
          riegos: 1,
          plaga: NivelPlaga.ninguna,
          fertilizo: false,
        ),
      );
      expect(e.sinGuardar, isFalse);
      expect(almacen.intentos, 2);
      final guardado =
          jsonDecode(prefs.getString('fincaV3')!) as Map<String, dynamic>;
      expect((guardado['registros'] as List).length, 1);
      expect((guardado['plantaciones'] as List).length, 1);
    });

    test('una escritura posterior que falla no pierde el estado en '
        'memoria', () async {
      SharedPreferences.setMockInitialValues({});
      final almacen = _AlmacenFalla(await SharedPreferences.getInstance(), 0);
      final e = AppEstado(almacen, reloj: () => _hoy);
      await e.preparada;
      almacen.fallos = 1;
      await expectLater(e.guardarParcela(_finca), throwsStateError);
      expect(e.parcela, isNotNull);
      expect(e.sinGuardar, isTrue);
      await e.cambiarLado(1000);
      expect(e.sinGuardar, isFalse);
    });

    testWidgets('main() llama a runApp con la finca V3 dañada', (tester) async {
      SharedPreferences.setMockInitialValues({'fincaV3': '{dañado'});
      await tester.runAsync(app.main);
      await tester.pump();
      expect(find.byType(app.FieldShift), findsOneWidget);
    });
  });

  group('2. retraso de NASA POWER', () {
    final registros = [
      RegistroSemanal(
        fecha: DateTime(2026, 7, 13),
        riegos: 2,
        plaga: NivelPlaga.ninguna,
        fertilizo: false,
      ),
      RegistroSemanal(
        fecha: DateTime(2026, 7, 19),
        riegos: 1,
        plaga: NivelPlaga.ninguna,
        fertilizo: false,
      ),
    ];
    Recomendacion calcular({
      List<RegistroSemanal>? r,
      int retraso = 4,
      List<DiaClima>? clima,
      DateTime? ahora,
    }) => recomendar(
      parcela: _finca,
      plantacion: _siembra(),
      clima: clima ?? _climaHasta(DateTime(2026, 6, 1), _antes(retraso)),
      registros: r ?? registros,
      hoy: ahora ?? _hoy,
    );

    test('clima completo que termina 4 días antes de hoy', () {
      final r = calcular();
      expect(r.ultimoClima, DateTime(2026, 7, 16));
      expect(r.diasEstimados, 4);
      expect(r.precision, Precision.alta);
      expect(r.factorRendimiento, isNotNull);
      expect(r.lluviaSemana, 3); // tres días observados de 1 mm
      expect(r.diasSinLluvia, 4);
      expect(r.diasLluviaFaltante, 4);
    });

    test(
      'el rendimiento coincide con el calculado al último día observado',
      () {
        final con = calcular();
        final enSuDia = calcular(ahora: _antes(4));
        expect(enSuDia.diasEstimados, 0);
        expect(con.factorRendimiento, enSuDia.factorRendimiento);
      },
    );

    test('sin registros semanales la precisión no sube', () {
      expect(calcular(r: []).precision, Precision.media);
      expect(
        calcular(r: [registros.last]).precision,
        Precision.media,
        reason: 'un solo registro reciente no basta para «alta»',
      );
    });

    test('el retraso normal (3 a 7 días) no baja la precisión', () {
      for (final retraso in [3, 5, 7]) {
        final r = calcular(retraso: retraso);
        expect(r.diasEstimados, retraso, reason: 'retraso $retraso');
        expect(r.precision, Precision.alta, reason: 'retraso $retraso');
        expect(r.factorRendimiento, isNotNull, reason: 'retraso $retraso');
      }
      final siete = calcular(retraso: 7);
      // Ningún día de la semana tiene lluvia observada: se informa como nulo.
      expect(siete.lluviaSemana, isNull);
      expect(siete.diasSinLluvia, 7);
    });

    test('un último clima de más de 10 días baja la precisión', () {
      final r = calcular(retraso: 11);
      expect(r.precision, Precision.baja);
      expect(r.avisos, contains(Aviso.climaViejo));
      expect(r.diasEstimados, 11);
      expect(calcular(retraso: 10).precision, Precision.alta);
    });

    test('un hueco dentro de la temporada observada sigue ocultando el '
        'rendimiento y baja la precisión', () {
      final c = _climaHasta(DateTime(2026, 6, 1), _antes(4))
        ..removeWhere((d) => d.fecha == DateTime(2026, 7, 14));
      final r = calcular(clima: c);
      expect(r.factorRendimiento, isNull);
      expect(r.precision, Precision.baja);
      // El hueco interior no es parte del retraso final.
      expect(r.diasEstimados, 4);
      expect(r.diasSinLluvia, 5);
      expect(r.lluviaSemana, 2);
    });

    test('lluvia observada con cero y sin dato no es lo mismo', () {
      final c = _climaHasta(DateTime(2026, 6, 1), _antes(4));
      final r = calcular(clima: c);
      expect(r.lluviaSemana, 3);
      final seca = [
        for (final d in c)
          DiaClima(
            fecha: d.fecha,
            tmax: d.tmax,
            tmin: d.tmin,
            humedad: d.humedad,
            viento: d.viento,
            radiacion: d.radiacion,
            lluvia: 0,
          ),
      ];
      final s = calcular(clima: seca);
      expect(s.lluviaSemana, 0);
      expect(s.diasSinLluvia, 4);
    });

    test('sin ningún clima observado la recomendación sigue vacía', () {
      final r = calcular(clima: []);
      expect(r.lluviaSemana, isNull);
      expect(r.factorRendimiento, isNull);
      expect(r.precision, Precision.baja);
    });
  });

  group('3. riegos sugeridos', () {
    Recomendacion base(double sugerido) => Recomendacion(
      nivel: NivelAgua.atencion,
      reserva: .4,
      agotamiento: 20,
      riegoSugerido: sugerido,
      riegosSugeridos: 0,
      etapa: Etapa.media,
      diasDesdeSiembra: 30,
      diasACosecha: 90,
      factorRendimiento: null,
      diasEstres: 0,
      lluviaSemana: null,
      necesidadSemana: 10,
      ultimos: const [],
      avisos: const [],
      precision: Precision.media,
      ultimoClima: null,
      diasEstimados: 0,
    );

    test('5,9 mm con goteo de 6 mm: sin límite, 1 riego (hacia arriba)', () {
      final r = base(5.9);
      expect(riegosPara(5.9, TipoRiego.goteo), 1);
      expect(limitarRiego(r, 5.9, TipoRiego.goteo).riegosSugeridos, 1);
    });

    test('con límite se redondea hacia abajo para no pasarse del saldo', () {
      final r = base(20);
      expect(limitarRiego(r, 5.9, TipoRiego.goteo).riegosSugeridos, 0);
      expect(limitarRiego(r, 11.9, TipoRiego.goteo).riegosSugeridos, 1);
      expect(limitarRiego(r, 12, TipoRiego.goteo).riegosSugeridos, 2);
      expect(limitarRiego(r, 0, TipoRiego.goteo).riegosSugeridos, 0);
    });

    test('limitarRiego y recomendar coinciden cuando el saldo alcanza', () {
      for (final mm in <double>[0.5, 5.9, 6, 6.1, 17.9, 18]) {
        expect(
          limitarRiego(base(mm), mm, TipoRiego.goteo).riegosSugeridos,
          riegosPara(mm, TipoRiego.goteo),
        );
      }
      expect(
        limitarRiego(base(5.9), 5.9, TipoRiego.ninguno).riegosSugeridos,
        0,
      );
    });

    test('limitarRiego conserva diasSinLluvia', () {
      final r = calcularConHueco();
      expect(r.diasSinLluvia, greaterThan(0));
      expect(
        limitarRiego(r, 1, TipoRiego.goteo).diasSinLluvia,
        r.diasSinLluvia,
      );
    });
  });

  group('4. guardarAgua', () {
    test('el volumen solo se guarda con disponibilidad «sí»', () async {
      final e = await _conCampania();
      final lote = e.plantacion!.loteId;
      for (final d in [DisponibilidadAgua.no, DisponibilidadAgua.desconocida]) {
        await e.guardarAgua(
          SuministroAgua(fecha: _hoy, disponibilidad: d, volumenM3: 30),
          RegistroRiego(loteId: lote, fecha: _hoy, necesito: true),
        );
        final s = e.suministroDe(_hoy);
        if (d == DisponibilidadAgua.no) {
          expect(s!.volumenM3, isNull);
        } else {
          expect(s, isNull);
        }
      }
      await e.guardarAgua(
        SuministroAgua(
          fecha: _hoy,
          disponibilidad: DisponibilidadAgua.si,
          volumenM3: 30,
        ),
        RegistroRiego(loteId: lote, fecha: _hoy, necesito: true),
      );
      expect(e.suministroDe(_hoy)!.volumenM3, 30);
    });

    test(
      'un volumen inválido con disponibilidad «no» no lanza error',
      () async {
        final e = await _conCampania();
        await e.guardarAgua(
          SuministroAgua(
            fecha: _hoy,
            disponibilidad: DisponibilidadAgua.no,
            volumenM3: -4,
          ),
          RegistroRiego(loteId: e.plantacion!.loteId, fecha: _hoy, rego: false),
        );
        expect(e.suministroDe(_hoy)!.volumenM3, isNull);
      },
    );

    test('un riego sin ningún dato no se guarda y borra el del día', () async {
      final e = await _conCampania();
      final lote = e.plantacion!.loteId;
      final otra = _antes(1);
      await e.guardarAgua(
        SuministroAgua(fecha: _hoy, disponibilidad: DisponibilidadAgua.si),
        RegistroRiego(loteId: lote, fecha: _hoy, necesito: true, rego: false),
      );
      await e.guardarAgua(
        SuministroAgua(fecha: otra, disponibilidad: DisponibilidadAgua.si),
        RegistroRiego(loteId: lote, fecha: otra, rego: true),
      );
      expect(e.riegosDiarios.length, 2);
      await e.guardarAgua(
        SuministroAgua(fecha: _hoy, disponibilidad: DisponibilidadAgua.si),
        RegistroRiego(loteId: lote, fecha: _hoy),
      );
      expect(e.riegoDe(lote, _hoy), isNull);
      expect(e.riegoDe(lote, otra), isNotNull);
      expect(e.suministroDe(_hoy), isNotNull);
    });

    test('un suministro desconocido y sin volumen no se guarda y borra el '
        'del día', () async {
      final e = await _conCampania();
      final lote = e.plantacion!.loteId;
      await e.guardarAgua(
        SuministroAgua(
          fecha: _hoy,
          disponibilidad: DisponibilidadAgua.si,
          volumenM3: 5,
        ),
        RegistroRiego(loteId: lote, fecha: _hoy, rego: false),
      );
      expect(e.suministroDe(_hoy), isNotNull);
      await e.guardarAgua(
        SuministroAgua(
          fecha: _hoy,
          disponibilidad: DisponibilidadAgua.desconocida,
        ),
        RegistroRiego(loteId: lote, fecha: _hoy, rego: false),
      );
      expect(e.suministroDe(_hoy), isNull);
      expect(e.riegoDe(lote, _hoy), isNotNull);
    });

    test('todo lo que guarda se puede exportar y volver a importar', () async {
      final e = await _conCampania();
      final lote = e.plantacion!.loteId;
      final combinaciones = <(SuministroAgua, RegistroRiego)>[
        (
          SuministroAgua(
            fecha: _hoy,
            disponibilidad: DisponibilidadAgua.no,
            volumenM3: 9,
          ),
          RegistroRiego(loteId: lote, fecha: _hoy, necesito: true),
        ),
        (
          SuministroAgua(
            fecha: _antes(1),
            disponibilidad: DisponibilidadAgua.desconocida,
          ),
          RegistroRiego(loteId: lote, fecha: _antes(1)),
        ),
        (
          SuministroAgua(
            fecha: _antes(2),
            disponibilidad: DisponibilidadAgua.si,
            volumenM3: 0,
          ),
          RegistroRiego(
            loteId: lote,
            fecha: _antes(2),
            rego: true,
            laminaMm: 3,
          ),
        ),
      ];
      for (final (s, r) in combinaciones) {
        await e.guardarAgua(s, r);
      }
      final paquete = jsonEncode(e.exportarPaquete());
      final otra = await _abrir();
      await otra.importarPaquete(paquete);
      expect(otra.suministros.length, 2);
      expect(otra.riegosDiarios.length, 2);
      // También sobre la misma finca (combinación idempotente).
      await e.importarPaquete(paquete);
      expect(e.suministros.length, 2);
    });

    test('una segunda llamada mientras otra está en curso se ignora', () async {
      final e = await _conCampania();
      final lote = e.plantacion!.loteId;
      final s = SuministroAgua(
        fecha: _hoy,
        disponibilidad: DisponibilidadAgua.si,
      );
      final r = RegistroRiego(loteId: lote, fecha: _hoy, rego: true);
      final a = e.guardarAgua(s, r);
      final b = e.guardarAgua(
        s,
        RegistroRiego(loteId: lote, fecha: _hoy, rego: false),
      );
      await Future.wait([a, b]);
      expect(e.riegosDiarios.length, 1);
      expect(e.riegoDe(lote, _hoy)!.rego, isTrue);
      // Terminada la primera, se acepta de nuevo.
      await e.guardarAgua(
        s,
        RegistroRiego(loteId: lote, fecha: _hoy, rego: false),
      );
      expect(e.riegoDe(lote, _hoy)!.rego, isFalse);
    });
  });

  group('5. campañas editadas', () {
    Future<AppEstado> conHistorial() async {
      final e = await _abrir();
      await e.guardarParcela(_finca.con(contorno: _cuadrado));
      await e.guardarPlantacion(
        _siembra(fecha: DateTime(2026, 3, 1), contorno: _rect(.1, .1, .3, .3)),
      );
      final primera = e.plantacion!;
      await e.cerrarCampania(primera.id, DateTime(2026, 5, 10));
      await e.guardarPlantacion(
        _siembra(
          fecha: DateTime(2026, 6, 1),
          contorno: _rect(.1, .1, .3, .3),
        ).conLote(primera.loteId),
      );
      return e;
    }

    test(
      'la siembra editada no puede ser anterior al cierre de la previa',
      () async {
        final e = await conHistorial();
        final segunda = e.plantacion!;
        expect(segunda.fecha, DateTime(2026, 6, 1));
        final adelantada = Plantacion.deJson({
          ...segunda.aJson(),
          'fecha': '2026-05-01',
        });
        await expectLater(
          e.guardarPlantacion(adelantada),
          throwsFormatException,
        );
        expect(e.plantacionPorId(segunda.id)!.fecha, DateTime(2026, 6, 1));
        // El mismo día del cierre sí vale (igual que en una campaña nueva).
        final justa = Plantacion.deJson({
          ...segunda.aJson(),
          'fecha': '2026-05-10',
        });
        await e.guardarPlantacion(justa);
        expect(e.plantacionPorId(segunda.id)!.fecha, DateTime(2026, 5, 10));
      },
    );

    test('el mensaje sale en el idioma elegido', () async {
      final e = await conHistorial();
      final segunda = e.plantacion!;
      final mala = Plantacion.deJson({
        ...segunda.aJson(),
        'fecha': '2026-05-01',
      });
      Future<String> mensaje() async {
        try {
          await e.guardarPlantacion(mala);
        } on FormatException catch (x) {
          return x.message;
        }
        return '';
      }

      expect(await mensaje(), contains('posterior al cierre'));
      e.idioma = 'en';
      expect(await mensaje(), contains('previous campaign'));
    });

    test('una campaña con cierre no termina después de la siembra de la '
        'siguiente', () async {
      final e = await _conCampania();
      final a = e.plantacion!;
      // Estado heredado con una campaña posterior en el mismo lote.
      e.campanias = [
        ...e.campanias,
        Plantacion.deJson({
          ...a.aJson(),
          'id': 'siguiente',
          'fecha': '2026-07-01',
        }),
      ];
      final tarde = Plantacion.deJson({...a.aJson(), 'fin': '2026-07-10'});
      await expectLater(e.guardarPlantacion(tarde), throwsFormatException);
      expect(e.plantacionPorId(a.id)!.fin, isNull);
      e.idioma = 'en';
      await expectLater(
        e.guardarPlantacion(tarde),
        throwsA(
          isA<FormatException>().having(
            (x) => x.message,
            'message',
            contains('next campaign'),
          ),
        ),
      );
      final aTiempo = Plantacion.deJson({...a.aJson(), 'fin': '2026-07-01'});
      await e.guardarPlantacion(aTiempo);
      expect(e.plantacionPorId(a.id)!.fin, DateTime(2026, 7, 1));
    });
  });

  group('6. lotes que bloquean', () {
    test('(a) borrar la última campaña de un lote borra el lote', () async {
      final e = await _conCampania();
      final lote = e.plantacion!.loteId;
      final id = e.plantacion!.id;
      await e.guardarAgua(
        SuministroAgua(fecha: _hoy, disponibilidad: DisponibilidadAgua.si),
        RegistroRiego(loteId: lote, fecha: _hoy, rego: true),
      );
      await e.borrarPlantacion(id);
      expect(e.lotes.where((l) => l.id == lote), isEmpty);
      expect(e.riegosDiarios, isEmpty);
      // Lo que queda sigue siendo un paquete válido.
      final paquete = jsonEncode(e.exportarPaquete());
      await (await _abrir()).importarPaquete(paquete);
    });

    test('(a) un lote con otra campaña (historial) se conserva', () async {
      final e = await _conCampania();
      final primera = e.plantacion!;
      await e.cerrarCampania(primera.id, DateTime(2026, 6, 20));
      await e.guardarPlantacion(
        _siembra(
          fecha: DateTime(2026, 7, 1),
          contorno: _rect(.1, .1, .3, .3),
        ).conLote(primera.loteId),
      );
      final segunda = e.plantacion!;
      await e.borrarPlantacion(segunda.id);
      expect(e.lotePorId(primera.loteId), isNotNull);
      await e.borrarPlantacion(primera.id);
      expect(e.lotePorId(primera.loteId), isNull);
      expect(e.lotes, isEmpty);
    });

    test('(a) el terreno borrado se puede volver a dibujar', () async {
      final e = await _conCampania(contorno: _rect(.1, .1, .3, .3));
      await e.borrarPlantacion(e.plantacion!.id);
      await e.guardarPlantacion(_siembra(contorno: _rect(.12, .12, .3, .3)));
      expect(e.plantaciones.length, 1);
    });

    test('(b) un lote sin campañas no bloquea un trazo nuevo', () async {
      final e = await _conCampania(contorno: _rect(.1, .1, .3, .3));
      e.lotes.add(
        Lote(
          id: 'huerfano',
          geometria: e.parcela!.marco.aGeografico(_rect(.5, .5, .3, .3)),
        ),
      );
      expect(e.validarTrazo(_rect(.55, .55, .2, .2)), isNull);
      await e.guardarPlantacion(_siembra(contorno: _rect(.55, .55, .2, .2)));
      expect(e.plantaciones.length, 2);
    });

    test('(b) un lote ya inválido (con cruces) no bloquea', () async {
      final e = await _conCampania(contorno: _rect(.1, .1, .3, .3));
      final lote = e.plantacion!.loteId;
      final corbata = [
        const Punto(.5, .5),
        const Punto(.8, .8),
        const Punto(.8, .5),
        const Punto(.5, .8),
      ];
      expect(validarPoligono(corbata), ErrorGeometria.cruce);
      e.lotes[e.lotes.indexWhere((l) => l.id == lote)] = Lote(
        id: lote,
        geometria: e.parcela!.marco.aGeografico(corbata),
      );
      expect(e.validarTrazo(_rect(.55, .55, .2, .2)), isNull);
      // Y sigue detectando el solape con lotes sanos.
      await e.guardarPlantacion(_siembra(contorno: _rect(.55, .55, .2, .2)));
      expect(
        e.validarTrazo(_rect(.6, .6, .1, .1)),
        ErrorGeometria.solapamiento,
      );
    });

    test('(b) validarPoligono ignora un vecino ya inválido', () {
      final corbata = [
        const Punto(.5, .5),
        const Punto(.8, .8),
        const Punto(.8, .5),
        const Punto(.5, .8),
      ];
      expect(
        validarPoligono(_rect(.55, .55, .2, .2), otros: [corbata]),
        isNull,
      );
    });

    test('(c) cambiar solo el ancho del plano no revalida los lotes', () async {
      final e = await _conCampania(contorno: _rect(.1, .1, .3, .3));
      final lote = e.plantacion!.loteId;
      // Un lote que ya quedó fuera de la finca (p. ej. por un paquete viejo).
      e.lotes[e.lotes.indexWhere((l) => l.id == lote)] = Lote(
        id: lote,
        geometria: e.parcela!.marco.aGeografico(_rect(1.2, 1.2, .2, .2)),
      );
      final p = e.parcela!;
      final nuevo = MarcoPlano(p.latitud, p.longitud, 1000);
      await e.guardarFinca(contorno: nuevo.aPlano(p.geometria), lado: 1000);
      expect(e.parcela!.lado, 1000);
      // Si cambia el contorno, sí se revalida.
      await expectLater(
        e.guardarFinca(contorno: _rect(.1, .1, .2, .2), lado: 1000),
        throwsFormatException,
      );
    });

    group('(d) fallo de la triangulación', () {
      final original = triangulador;
      tearDown(() => triangulador = original);

      test('validarPoligono devuelve un ErrorGeometria', () {
        triangulador = (_) => throw const FormatException('no triangula');
        expect(
          validarPoligono(_rect(.2, .2, .2, .2), finca: _cuadrado),
          isNotNull,
        );
        expect(
          validarPoligono(
            _rect(.2, .2, .2, .2),
            otros: [_rect(.3, .3, .2, .2)],
          ),
          ErrorGeometria.degenerado,
        );
      });

      test('guardarPlantacion lo informa sin romper', () async {
        final e = await _abrir();
        await e.guardarParcela(_finca.con(contorno: _cuadrado));
        triangulador = (_) => throw const FormatException('no triangula');
        await expectLater(
          e.guardarPlantacion(_siembra(contorno: _rect(.2, .2, .2, .2))),
          throwsA(
            isA<FormatException>().having(
              (x) => x.message,
              'message',
              isNotEmpty,
            ),
          ),
        );
        expect(e.lotes, isEmpty);
      });
    });
  });

  group('7. mensajes de error en dos idiomas', () {
    Future<String> mensaje(Future<void> Function() f) async {
      try {
        await f();
      } on FormatException catch (e) {
        return e.message;
      }
      return '';
    }

    test('guardarAgua', () async {
      final e = await _conCampania();
      final r = RegistroRiego(loteId: 'no-existe', fecha: _hoy, rego: true);
      final s = SuministroAgua(
        fecha: _hoy,
        disponibilidad: DisponibilidadAgua.si,
      );
      expect(await mensaje(() => e.guardarAgua(s, r)), 'Elige la plantación');
      e.idioma = 'en';
      expect(await mensaje(() => e.guardarAgua(s, r)), 'Choose the planting');
      final fuera = RegistroRiego(
        loteId: e.plantacion!.loteId,
        campaniaId: e.plantacion!.id,
        fecha: DateTime(2026, 5, 1),
        rego: true,
      );
      expect(
        await mensaje(
          () => e.guardarAgua(
            SuministroAgua(
              fecha: DateTime(2026, 5, 1),
              disponibilidad: DisponibilidadAgua.si,
            ),
            fuera,
          ),
        ),
        'Date outside the campaign',
      );
      e.idioma = 'es';
      expect(
        await mensaje(
          () => e.guardarAgua(
            SuministroAgua(
              fecha: DateTime(2026, 5, 1),
              disponibilidad: DisponibilidadAgua.si,
            ),
            fuera,
          ),
        ),
        'Fecha fuera de la campaña',
      );
    });

    test('validarEvento, validarCampania y cerrarCampania', () async {
      final e = await _conCampania();
      final p = e.plantacion!;
      final mal = Evento(
        id: 'x1',
        campaniaId: p.id,
        loteId: p.loteId,
        tipo: TipoEvento.cosecha,
        fecha: _hoy,
      );
      expect(
        await mensaje(() => e.guardarEvento(mal)),
        'Indica la cosecha y su unidad.',
      );
      e.idioma = 'en';
      expect(
        await mensaje(() => e.guardarEvento(mal)),
        'Give the harvest and its unit.',
      );
      expect(
        await mensaje(
          () => e.guardarPlantacion(
            Plantacion.deJson({...p.aJson(), 'ciclo': 0}),
          ),
        ),
        contains('Check the date'),
      );
      expect(
        await mensaje(() => e.cerrarCampania('no-existe', _hoy)),
        'The campaign is not active',
      );
    });

    test('importar un paquete inválido', () async {
      final e = await _abrir();
      e.idioma = 'en';
      final m = await mensaje(
        () => e.importarPaquete(
          jsonEncode({'esquema': 'otro', 'version': 1, 'datos': {}}),
        ),
      );
      expect(m, 'Package schema not supported');
    });
  });

  group('8. menores', () {
    test('cambiar de cultivo con solo eventos derivados de la ficha', () async {
      final e = await _conCampania(
        siembra: _siembra(contorno: _rect(.1, .1, .3, .3), fertilizo: true),
      );
      final p = e.plantacion!;
      expect(e.eventosDe(p.id), isNotEmpty); // el «fertilizó» inicial
      await e.guardarPlantacion(
        Plantacion.deJson({...p.aJson(), 'cultivo': 'frijol', 'ciclo': 67}),
      );
      expect(e.plantacion!.cultivoId, 'frijol');
    });

    test(
      'cambiar de cultivo con un evento detallado sigue bloqueado',
      () async {
        final e = await _conCampania();
        final p = e.plantacion!;
        await e.guardarEvento(
          Evento(
            id: 'ev-1',
            campaniaId: p.id,
            loteId: p.loteId,
            tipo: TipoEvento.observacion,
            observacion: Observacion.sombra,
            fecha: _antes(3),
          ),
        );
        await expectLater(
          e.guardarPlantacion(
            Plantacion.deJson({...p.aJson(), 'cultivo': 'frijol', 'ciclo': 67}),
          ),
          throwsFormatException,
        );
        expect(e.plantacion!.cultivoId, 'maiz');
      },
    );

    test(
      'cambiar de cultivo con un registro semanal sigue bloqueado',
      () async {
        final e = await _conCampania();
        final p = e.plantacion!;
        await e.guardarRegistro(
          RegistroSemanal(
            plantacionId: p.id,
            fecha: _antes(2),
            riegos: 1,
            plaga: NivelPlaga.ninguna,
            fertilizo: false,
          ),
        );
        await expectLater(
          e.guardarPlantacion(
            Plantacion.deJson({...p.aJson(), 'cultivo': 'frijol', 'ciclo': 67}),
          ),
          throwsFormatException,
        );
      },
    );

    test('guardarPlantacion y guardarEvento ignoran el doble toque', () async {
      final e = await _abrir();
      await e.guardarParcela(_finca.con(contorno: _cuadrado));
      final a = e.guardarPlantacion(_siembra(contorno: _rect(.1, .1, .3, .3)));
      final b = e.guardarPlantacion(_siembra(contorno: _rect(.5, .5, .3, .3)));
      await Future.wait([a, b]);
      expect(e.campanias.length, 1);
      final p = e.plantacion!;
      Evento ev(String nota) => Evento(
        id: '',
        campaniaId: p.id,
        loteId: p.loteId,
        tipo: TipoEvento.observacion,
        observacion: Observacion.sombra,
        fecha: _antes(1),
        nota: nota,
      );
      await Future.wait([e.guardarEvento(ev('1')), e.guardarEvento(ev('2'))]);
      expect(e.eventos.where((x) => !x.derivado).length, 1);
      await e.guardarEvento(ev('3'));
      expect(e.eventos.where((x) => !x.derivado).length, 2);
    });

    test(
      'sincronizar no mira las campañas cerradas para la fecha inicial',
      () async {
        SharedPreferences.setMockInitialValues({});
        final servicio = _ClimaFalso();
        final e = AppEstado(
          await Almacen.abrir(),
          servicioClima: servicio,
          reloj: () => _hoy,
        );
        await e.preparada;
        await e.guardarParcela(_finca.con(contorno: _cuadrado));
        await e.guardarPlantacion(
          _siembra(
            fecha: DateTime(2026, 1, 10),
            contorno: _rect(.1, .1, .3, .3),
          ),
        );
        await e.cerrarCampania(e.plantacion!.id, DateTime(2026, 2, 1));
        await e.guardarPlantacion(
          _siembra(
            fecha: DateTime(2026, 6, 20),
            contorno: _rect(.5, .5, .3, .3),
          ),
        );
        expect(await e.sincronizar(), ResultadoSync.ok);
        // Sin la campaña cerrada, el mínimo son los 60 días por omisión.
        expect(servicio.desde, _antes(60));
        e.campanias = [
          for (final p in e.campanias)
            if (p.activa)
              Plantacion.deJson({...p.aJson(), 'fecha': '2026-04-01'})
            else
              p,
        ];
        await e.sincronizar();
        expect(servicio.desde, DateTime(2026, 4, 1));
      },
    );

    test('un error no deja trabado el guardado siguiente', () async {
      final e = await _conCampania();
      await expectLater(
        e.guardarPlantacion(
          Plantacion.deJson({...e.plantacion!.aJson(), 'ciclo': 0}),
        ),
        throwsFormatException,
      );
      await e.guardarPlantacion(e.plantacion!);
    });
  });
}

Recomendacion calcularConHueco() => recomendar(
  parcela: _finca,
  plantacion: _siembra(),
  clima: _climaHasta(DateTime(2026, 6, 1), _antes(4)),
  registros: const [],
  hoy: _hoy,
);
