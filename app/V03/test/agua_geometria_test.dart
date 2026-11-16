import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/motor/recomendador.dart';

final fecha = DateTime(2026, 7, 20);
const finca = Parcela(
  nombre: 'Prueba',
  latitud: 14.825,
  longitud: -89.5312,
  elevacion: 373,
);
const cuadrado = [
  Punto(.05, .05),
  Punto(.95, .05),
  Punto(.95, .95),
  Punto(.05, .95),
];
List<Punto> rect(double x, double y, double ancho, double alto) => [
  Punto(x, y),
  Punto(x + ancho, y),
  Punto(x + ancho, y + alto),
  Punto(x, y + alto),
];
Plantacion siembra({
  List<Punto> contorno = const [],
  TipoRiego tipo = TipoRiego.goteo,
}) => Plantacion(
  contorno: contorno,
  cultivoId: 'maiz',
  fecha: DateTime(2026, 6, 1),
  ciclo: 120,
  suelo: Suelo.franco,
  riego: tipo,
  temporadaRiego: TemporadaRiego.auxilio,
  plagaReciente: false,
  fertilizo: false,
);
List<DiaClima> clima() => [
  for (var i = 0; i < 50; i++)
    DiaClima(
      fecha: DateTime(2026, 6, 1 + i),
      tmax: 32,
      tmin: 21,
      humedad: 60,
      viento: 2,
      radiacion: 22,
      lluvia: 0,
    ),
];
Future<AppEstado> abrir({
  Map<String, Object> guardado = const {},
  DateTime Function()? reloj,
}) async {
  SharedPreferences.setMockInitialValues(guardado);
  final e = AppEstado(await Almacen.abrir(), reloj: reloj ?? () => fecha);
  await e.preparada;
  return e;
}

void main() {
  group('agua y lluvia', () {
    Recomendacion calcular(DisponibilidadAgua d) => recomendar(
      parcela: finca,
      plantacion: siembra(),
      clima: clima(),
      registros: [],
      hoy: fecha,
      disponibilidad: d,
    );
    test('sistema instalado con suministro desconocido no promete riego', () {
      final r = calcular(DisponibilidadAgua.desconocida);
      expect(r.necesidadRiego, greaterThan(0));
      expect(r.riegoSugerido, 0);
      expect(r.avisos, contains(Aviso.aguaSinConfirmar));
    });
    test('sin agua conserva déficit; con agua confirma una propuesta', () {
      final no = calcular(DisponibilidadAgua.no),
          si = calcular(DisponibilidadAgua.si);
      expect(no.necesidadRiego, si.necesidadRiego);
      expect(no.riegoSugerido, 0);
      expect(no.avisos, contains(Aviso.sinAgua));
      expect(si.riegoSugerido, greaterThan(0));
    });
    test(
      'lluvia nula no se convierte en cero observado ni se pierde ET0 válido',
      () {
        final c = clima();
        final d = c[20];
        c[20] = DiaClima(
          fecha: d.fecha,
          tmax: d.tmax,
          tmin: d.tmin,
          humedad: d.humedad,
          viento: d.viento,
          radiacion: d.radiacion,
          lluvia: null,
        );
        final dias = prepararClima(c, finca, fecha);
        expect(dias[20].lluvia, isNull);
        expect(dias[20].et0Estimada, isFalse);
        expect(dias[20].estimado, isTrue);
        expect(dias[19].lluvia, 0);
        expect(dias[19].estimado, isFalse);
        final r = recomendar(
          parcela: finca,
          plantacion: siembra(),
          clima: c,
          registros: [],
          hoy: fecha,
        );
        // Un hueco dentro de la temporada no es el retraso final de NASA.
        expect(r.diasEstimados, 0);
        expect(r.diasLluviaFaltante, 1);
        expect(r.factorRendimiento, isNull);
        expect(r.avisos, contains(Aviso.lluviaFaltante));
      },
    );
    test('lluvia semanal desconocida e imputación solo de ET0 se señalan', () {
      final c = clima()..removeAt(47);
      final r = recomendar(
        parcela: finca,
        plantacion: siembra(),
        clima: c,
        registros: [],
        hoy: fecha,
      );
      // La suma usa los seis días con lluvia conocida y cuenta el que falta.
      expect(r.lluviaSemana, 0);
      expect(r.diasSinLluvia, 1);
      expect(r.diasEstimados, 0);
      expect(
        r.ultimos.where((d) => d.lluvia == null).single.et0Estimada,
        isTrue,
      );
    });
    test('clima posterior a la decisión no entra al promedio', () {
      final c = clima()
        ..add(
          DiaClima(
            fecha: DateTime(2026, 7, 21),
            tmax: 50,
            tmin: 40,
            humedad: 5,
            viento: 10,
            radiacion: 40,
            lluvia: 300,
          ),
        );
      expect(prepararClima(c, finca, fecha).length, 50);
    });
    test(
      'aplicación diaria reemplaza reparto semanal y cero confirmado lo anula',
      () {
        final semanal = [
          RegistroSemanal(
            fecha: fecha,
            riegos: 7,
            plaga: NivelPlaga.ninguna,
            fertilizo: false,
          ),
        ];
        final diario = [
          RegistroRiego(
            loteId: 'l',
            fecha: DateTime(2026, 7, 19),
            rego: true,
            laminaMm: 3,
          ),
          RegistroRiego(loteId: 'l', fecha: DateTime(2026, 7, 18), rego: false),
        ];
        final r = prepararRiegos(semanal, diario, TipoRiego.goteo);
        expect(r.laminas[DateTime(2026, 7, 19)], 3);
        expect(r.laminas[DateTime(2026, 7, 18)], 0);
        expect(r.estimados.contains(DateTime(2026, 7, 19)), isFalse);
        expect(r.estimados.contains(DateTime(2026, 7, 17)), isTrue);
      },
    );
    test(
      'el saldo compartido no se multiplica por el número de lotes',
      () async {
        final e = await abrir();
        await e.guardarParcela(finca.con(contorno: cuadrado));
        await e.guardarPlantacion(siembra(contorno: rect(.1, .1, .3, .3)));
        await e.guardarPlantacion(siembra(contorno: rect(.6, .6, .3, .3)));
        e.clima = clima();
        await e.guardarAgua(
          SuministroAgua(
            fecha: fecha,
            disponibilidad: DisponibilidadAgua.si,
            volumenM3: 1,
          ),
          RegistroRiego(
            loteId: e.plantacion!.loteId,
            fecha: fecha,
            rego: false,
          ),
        );
        var total = 0.0;
        for (final p in e.plantaciones) {
          final r = e.recomendacionDe(p);
          expect(r.riegoSugerido, greaterThan(0));
          expect(r.avisos, contains(Aviso.capacidadLimitada));
          total += r.riegoSugerido * e.lotePorId(p.loteId)!.areaM2 / 1000;
        }
        expect(total, closeTo(1, 1e-9));
      },
    );
    test('el suministro vence al cambiar de fecha incluso con recomendaciones cacheadas', () async {
      var reloj = fecha;
      final e = await abrir(reloj: () => reloj);
      await e.guardarParcela(finca);
      await e.guardarPlantacion(siembra());
      e.clima = clima();
      await e.guardarAgua(
        SuministroAgua(fecha: fecha, disponibilidad: DisponibilidadAgua.si),
        RegistroRiego(loteId: e.plantacion!.loteId, fecha: fecha, rego: false),
      );
      expect(e.recomendacion.riegoSugerido, greaterThan(0));
      reloj = DateTime(2026, 7, 21);
      expect(e.recomendacion.riegoSugerido, 0);
      expect(e.recomendacion.disponibilidad, DisponibilidadAgua.desconocida);
    });
    test(
      'se guarda necesidad sin aplicación y se conserva al reabrir',
      () async {
        final e = await abrir();
        await e.guardarParcela(finca);
        await e.guardarPlantacion(siembra());
        await e.guardarAgua(
          SuministroAgua(
            fecha: fecha,
            disponibilidad: DisponibilidadAgua.si,
            volumenM3: 0,
          ),
          RegistroRiego(
            loteId: e.plantacion!.loteId,
            fecha: fecha,
            necesito: true,
            rego: false,
          ),
        );
        final otra = AppEstado(await Almacen.abrir(), reloj: () => fecha);
        await otra.preparada;
        final r = otra.riegoDe(e.plantacion!.loteId, fecha)!;
        expect(r.necesito, isTrue);
        expect(r.rego, isFalse);
        expect(r.laminaMm, isNull);
        expect(otra.suministroDe(fecha)!.disponibilidad, DisponibilidadAgua.si);
        expect(otra.suministroDe(fecha)!.volumenM3, 0);
      },
    );
  });

  group('geometría', () {
    test('rechaza cruces, superficie cero y puntos repetidos', () {
      expect(
        validarPoligono([
          const Punto(0, 0),
          const Punto(1, 1),
          const Punto(0, 1),
          const Punto(1, 0),
        ]),
        ErrorGeometria.cruce,
      );
      expect(
        validarPoligono([
          const Punto(0, 0),
          const Punto(.5, 0),
          const Punto(1, 0),
        ]),
        ErrorGeometria.degenerado,
      );
      expect(
        validarPoligono([
          const Punto(0, 0),
          const Punto(0, 0),
          const Punto(1, 1),
        ]),
        ErrorGeometria.degenerado,
      );
    });
    test(
      'solapamiento parcial, inclusión e igualdad; borde compartido permitido',
      () {
        final a = rect(0, 0, .5, 1);
        expect(
          validarPoligono(rect(.25, .25, .5, .5), otros: [a]),
          ErrorGeometria.solapamiento,
        );
        expect(
          validarPoligono(rect(.1, .1, .1, .1), otros: [a]),
          ErrorGeometria.solapamiento,
        );
        expect(validarPoligono(a, otros: [a]), ErrorGeometria.solapamiento);
        expect(validarPoligono(rect(.5, 0, .5, 1), otros: [a]), isNull);
      },
    );
    test(
      'finca cóncava: vértices dentro no bastan para contener los bordes',
      () {
        const f = [
          Punto(0, 0),
          Punto(1, 0),
          Punto(1, .4),
          Punto(.4, .4),
          Punto(.4, 1),
          Punto(0, 1),
        ];
        const lote = [Punto(.2, .8), Punto(.8, .2), Punto(.2, .2)];
        expect(lote.every((p) => dentroDe(f, p)), isTrue);
        expect(validarPoligono(lote, finca: f), ErrorGeometria.fueraFinca);
        expect(validarPoligono(rect(.1, .1, .2, .7), finca: f), isNull);
      },
    );
    test('conversión mantiene ubicación y área a distintas escalas', () {
      const marco = MarcoPlano(14.825, -89.5312, 500);
      final geo = marco.aGeografico(rect(.2, .2, .4, .4));
      final area = areaGeografica(geo);
      expect((area - 40000).abs() / 40000, lessThan(.005));
      for (final lado in [200.0, 1000.0, 10000.0]) {
        final otro = MarcoPlano(14.83, -89.54, lado);
        final vuelta = otro.aGeografico(otro.aPlano(geo));
        expect(areaGeografica(vuelta), closeTo(area, .001));
        for (var i = 0; i < geo.length; i++) {
          expect(vuelta[i].latitud, closeTo(geo[i].latitud, 1e-10));
          expect(vuelta[i].longitud, closeTo(geo[i].longitud, 1e-10));
        }
      }
      final json = poligonoGeoJson(geo)!;
      final anillo = (json['coordinates'] as List).single as List;
      expect(anillo.length, 5);
      expect(anillo.first, anillo.last);
      expect((anillo.first as List).first, closeTo(geo.first.longitud, .01));
    });
  });

  group('migración y lotes', () {
    test(
      'migra la finca antigua una vez sin inventar agua ni borrar sus claves',
      () async {
        final original = jsonEncode(
          finca.con(contorno: cuadrado).aJson()..remove('geometria'),
        );
        final cultivo = siembra(contorno: rect(.1, .1, .2, .2)).aJson()
          ..remove('loteId');
        final e = await abrir(
          guardado: {
            'parcela': original,
            'plantacion': jsonEncode(cultivo),
            'registros': jsonEncode([
              RegistroSemanal(
                fecha: fecha,
                riegos: 2,
                plaga: NivelPlaga.leve,
                fertilizo: false,
              ).aJson(),
            ]),
          },
        );
        expect(e.plantacion!.loteId, isNotEmpty);
        expect(e.lotes.single.geometria.length, 4);
        expect(e.suministroDe(fecha), isNull);
        expect(e.riegosDiarios, isEmpty);
        expect(e.todosLosRegistros.single.plantacionId, e.plantacion!.id);
        final otra = AppEstado(await Almacen.abrir(), reloj: () => fecha);
        await otra.preparada;
        expect(otra.plantacion!.loteId, e.plantacion!.loteId);
        expect(otra.lotes.single.aJson(), e.lotes.single.aJson());
        expect(
          (await SharedPreferences.getInstance()).getString('parcela'),
          original,
        );
      },
    );
    test('cambiar centro y ancho no mueve las geometrías exportadas', () async {
      final e = await abrir();
      await e.guardarParcela(finca.con(contorno: cuadrado));
      await e.guardarPlantacion(siembra(contorno: rect(.1, .1, .2, .2)));
      final antes = jsonEncode(e.exportarGeoJson());
      final loteId = e.plantacion!.loteId;
      await e.cambiarLado(10000);
      await e.guardarParcela(
        const Parcela(
          nombre: 'Prueba',
          latitud: 14.83,
          longitud: -89.54,
          lado: 10000,
        ),
      );
      expect(jsonEncode(e.exportarGeoJson()), antes);
      final otra = AppEstado(await Almacen.abrir(), reloj: () => fecha);
      await otra.preparada;
      expect(otra.plantacion!.loteId, loteId);
      expect(jsonEncode(otra.exportarGeoJson()), antes);
    });
    test(
      'un polígono inválido no guarda parcialmente la finca del flujo',
      () async {
        final e = await abrir();
        await e.guardarParcela(finca);
        final p = siembra(contorno: rect(.8, .8, .2, .2));
        await expectLater(
          e.guardarPlantacion(p, fincaNueva: rect(.1, .1, .5, .5), lado: 1000),
          throwsFormatException,
        );
        expect(e.parcela!.lado, 500);
        expect(e.parcela!.contorno, isEmpty);
        expect(e.lotes, isEmpty);
      },
    );
    test('el editor de finca no puede dejar un lote existente fuera', () async {
      final e = await abrir();
      await e.guardarParcela(finca.con(contorno: cuadrado));
      await e.guardarPlantacion(siembra(contorno: rect(.6, .6, .2, .2)));
      await expectLater(
        e.guardarFinca(contorno: rect(.1, .1, .2, .2), lado: 500),
        throwsFormatException,
      );
      expect(e.parcela!.geometria.length, 4);
    });
  });
  test('un hueco de ET0 conserva la lluvia observada por separado', () {
    final c = clima(), d = clima()[48];
    c[48] = DiaClima(
      fecha: d.fecha,
      tmax: d.tmax,
      tmin: d.tmin,
      humedad: d.humedad,
      viento: null,
      radiacion: d.radiacion,
      lluvia: 12,
    );
    final preparado = prepararClima(c, finca, fecha)[48];
    expect(preparado.lluvia, 12);
    expect(preparado.et0Estimada, isTrue);
    final r = recomendar(
      parcela: finca,
      plantacion: siembra(),
      clima: c,
      registros: [],
      hoy: fecha,
    );
    expect(r.lluviaSemana, 12);
    expect(r.diasLluviaFaltante, 0);
  });
  test(
    'capacidad conocida requiere área y el saldo cero no propone aplicación',
    () async {
      final e = await abrir();
      await e.guardarParcela(finca);
      await e.guardarPlantacion(siembra());
      e.clima = clima();
      await e.guardarAgua(
        SuministroAgua(
          fecha: fecha,
          disponibilidad: DisponibilidadAgua.si,
          volumenM3: 10,
        ),
        RegistroRiego(loteId: e.plantacion!.loteId, fecha: fecha),
      );
      expect(e.recomendacion.riegoSugerido, 0);
      expect(e.recomendacion.avisos, contains(Aviso.areaPendiente));
      await e.guardarPlantacion(
        e.plantacion!.conContorno(rect(.1, .1, .2, .2)),
      );
      await e.guardarAgua(
        SuministroAgua(
          fecha: fecha,
          disponibilidad: DisponibilidadAgua.si,
          volumenM3: 0,
        ),
        RegistroRiego(loteId: e.plantacion!.loteId, fecha: fecha),
      );
      expect(e.recomendacion.riegoSugerido, 0);
      expect(e.recomendacion.avisos, contains(Aviso.capacidadLimitada));
    },
  );
  test('cantidades inválidas o fechas futuras no se guardan', () async {
    final e = await abrir();
    await e.guardarParcela(finca);
    await e.guardarPlantacion(siembra());
    await expectLater(
      e.guardarAgua(
        SuministroAgua(
          fecha: fecha,
          disponibilidad: DisponibilidadAgua.si,
          volumenM3: -1,
        ),
        RegistroRiego(loteId: e.plantacion!.loteId, fecha: fecha),
      ),
      throwsFormatException,
    );
    final futuro = DateTime(2026, 7, 21);
    await expectLater(
      e.guardarAgua(
        SuministroAgua(fecha: futuro, disponibilidad: DisponibilidadAgua.si),
        RegistroRiego(loteId: e.plantacion!.loteId, fecha: futuro),
      ),
      throwsFormatException,
    );
    expect(e.suministros, isEmpty);
    expect(e.riegosDiarios, isEmpty);
  });
  test(
    'rechaza retroceso sobre un borde y permite contacto de una esquina',
    () {
      expect(
        validarPoligono([
          const Punto(0, 0),
          const Punto(1, 0),
          const Punto(.5, 0),
          const Punto(.5, 1),
          const Punto(0, 1),
        ]),
        ErrorGeometria.degenerado,
      );
      expect(
        validarPoligono(rect(.5, .5, .2, .2), otros: [rect(.1, .1, .4, .4)]),
        isNull,
      );
    },
  );
  test(
    'editar datos del cultivo conserva la identidad y procedencia del lote',
    () async {
      final e = await abrir();
      await e.guardarParcela(finca);
      await e.guardarPlantacion(siembra(contorno: rect(.1, .1, .2, .2)));
      final antes = e.lotes.single.aJson(), id = e.parcela!.id;
      await e.guardarPlantacion(
        Plantacion.deJson({...e.plantacion!.aJson(), 'nombre': 'Lote norte'}),
      );
      expect(e.lotes.single.aJson(), antes);
      expect(e.parcela!.id, id);
      expect(id, isNotEmpty);
    },
  );
  test('geometría antigua inválida se conserva y el error de exportación identifica el cultivo', () async {
    final e = await abrir(
      guardado: {
        'parcela': jsonEncode(
          finca.con(contorno: rect(.1, .1, .3, .3)).aJson(),
        ),
        'plantacion': jsonEncode(
          siembra(contorno: rect(.8, .8, .1, .1)).aJson(),
        ),
      },
    );
    expect(e.lotes.single.geometria.length, 4);
    expect(
      () => e.exportarGeoJson(),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'mensaje',
          contains('Maíz:'),
        ),
      ),
    );
    expect(e.plantaciones.length, 1);
  });
}
