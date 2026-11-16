import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/eventos.dart';
import 'package:field_shift/motor/recomendador.dart';

import 'agua_geometria_test.dart' as base;

Future<AppEstado> finca() async {
  final e = await base.abrir();
  await e.guardarParcela(base.finca);
  await e.guardarPlantacion(base.siembra(contorno: base.rect(.1, .1, .3, .3)));
  return e;
}

Evento evento(
  Plantacion p,
  TipoEvento tipo, {
  String id = 'e1',
  double? cantidad,
  String? unidad,
  String? referencia,
  Observacion? observacion,
  DateTime? fecha,
}) => Evento(
  id: id,
  campaniaId: p.id,
  loteId: p.loteId,
  tipo: tipo,
  fecha: fecha ?? base.fecha,
  cantidad: cantidad,
  unidad: unidad,
  referencia: referencia,
  observacion: observacion,
);

void main() {
  test(
    'cierre y nueva campaña conservan lote, eventos y riego aislado',
    () async {
      final e = await finca();
      final anterior = e.plantacion!;
      await e.guardarAgua(
        SuministroAgua(
          fecha: base.fecha,
          disponibilidad: DisponibilidadAgua.si,
        ),
        RegistroRiego(
          loteId: anterior.loteId,
          campaniaId: anterior.id,
          fecha: base.fecha,
          rego: true,
          laminaMm: 10,
        ),
      );
      await e.guardarEvento(
        evento(anterior, TipoEvento.cosecha, cantidad: 12, unidad: 'kg'),
      );
      await e.cerrarCampania(anterior.id, base.fecha);
      expect(e.plantacion, isNull);
      expect(e.configurada, isTrue);
      await e.guardarPlantacion(
        Plantacion.deJson({
          ...anterior.aJson(),
          'id': '',
          'cultivo': 'frijol',
          'fecha': fechaIso(base.fecha),
          'plagaReciente': false,
        }),
      );
      final actual = e.plantacion!;
      expect(actual.id, isNot(anterior.id));
      expect(actual.loteId, anterior.loteId);
      expect(e.lotes.length, 1);
      expect(e.campanias.length, 2);
      expect(e.eventosDe(actual.id), isEmpty);
      expect(e.kilosCosechados(anterior.id), 12);
      expect(
        e.riegoDe(actual.loteId, base.fecha, campaniaId: actual.id),
        isNull,
      );
      await e.guardarAgua(
        SuministroAgua(
          fecha: base.fecha,
          disponibilidad: DisponibilidadAgua.si,
        ),
        RegistroRiego(
          loteId: actual.loteId,
          campaniaId: actual.id,
          fecha: base.fecha,
          rego: false,
        ),
      );
      expect(e.riegosDiarios.length, 2);
      final otra = AppEstado(await Almacen.abrir(), reloj: () => base.fecha);
      await otra.preparada;
      expect(otra.campanias.length, 2);
      expect(otra.plantaciones.length, 1);
      expect(otra.kilosCosechados(anterior.id), 12);
    },
  );
  test(
    'rechaza dos campañas activas en el mismo lote y cierre antes de evento',
    () async {
      final e = await finca();
      final actual = e.plantacion!;
      await expectLater(
        e.guardarPlantacion(actual.conId('')),
        throwsFormatException,
      );
      await e.guardarEvento(
        evento(actual, TipoEvento.cosecha, cantidad: 4, unidad: 'kg'),
      );
      await expectLater(
        e.cerrarCampania(
          actual.id,
          base.fecha.subtract(const Duration(days: 1)),
        ),
        throwsFormatException,
      );
      expect(e.plantacion!.activa, isTrue);
    },
  );
  test(
    'variedad, antecedente y mínimo del lote sobreviven reapertura',
    () async {
      final e = await finca();
      await e.guardarPlantacion(
        Plantacion.deJson({
          ...e.plantacion!.aJson(),
          'variedad': 'ICTA B-5',
          'cultivoAnterior': 'Frijol',
          'mantenerCultivo': true,
          'permitirMezcla': true,
          'proporcionMinima': 60,
        }),
      );
      final otra = AppEstado(await Almacen.abrir(), reloj: () => base.fecha);
      await otra.preparada;
      expect(otra.plantacion!.variedad, 'ICTA B-5');
      expect(otra.plantacion!.proporcionMinima, 60);
      expect(otra.plantacion!.cultivoAnterior, 'Frijol');
      expect(otra.plantacion!.mantenerCultivo, isTrue);
      for (final min in [-1, 101, double.nan]) {
        await expectLater(
          e.guardarPlantacion(
            Plantacion.deJson({
              ...e.plantacion!.aJson(),
              'proporcionMinima': min,
            }),
          ),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'cosechas suman kg convertibles; pérdidas no se descuentan dos veces',
    () async {
      final e = await finca();
      final c = e.plantacion!;
      await e.guardarEvento(
        evento(c, TipoEvento.cosecha, cantidad: 12, unidad: 'kg'),
      );
      await e.guardarEvento(
        evento(c, TipoEvento.cosecha, id: 'e2', cantidad: 500, unidad: 'g'),
      );
      await e.guardarEvento(
        evento(c, TipoEvento.cosecha, id: 'e3', cantidad: .01, unidad: 't'),
      );
      await e.guardarEvento(
        evento(c, TipoEvento.cosecha, id: 'e4', cantidad: 2, unidad: 'otra'),
      );
      await e.guardarEvento(
        evento(
          c,
          TipoEvento.perdida,
          id: 'e5',
          cantidad: 3,
          unidad: 'kg',
          referencia: 'yaCosechado',
        ),
      );
      expect(e.kilosCosechados(c.id), 22.5);
      expect(e.eventosDe(c.id).where((x) => x.kilos == null).length, 2);
    },
  );
  test('eventos validan fecha, referencia, unidad y porcentajes', () async {
    final e = await finca();
    final p = e.plantacion!;
    final invalidos = [
      evento(p, TipoEvento.cosecha, cantidad: -1, unidad: 'kg'),
      evento(p, TipoEvento.perdida, cantidad: 10, unidad: '%'),
      evento(
        p,
        TipoEvento.perdida,
        cantidad: 110,
        unidad: '%',
        referencia: 'superficie',
      ),
      evento(
        p,
        TipoEvento.perdida,
        cantidad: 3,
        unidad: 'kg',
        referencia: 'superficie',
      ),
      evento(
        p,
        TipoEvento.observacion,
        cantidad: 3,
        unidad: 'kg',
        observacion: Observacion.sombra,
      ),
      evento(p, TipoEvento.fertilizacion, cantidad: 3, unidad: 'kg'),
      evento(p, TipoEvento.plaga, fecha: DateTime(2026, 5, 31)),
      evento(
        p,
        TipoEvento.plaga,
        fecha: base.fecha.add(const Duration(days: 1)),
      ),
    ];
    for (final x in invalidos) {
      await expectLater(e.guardarEvento(x), throwsFormatException);
    }
    expect(e.eventosDe(p.id), isEmpty);
  });
  test(
    'sombra, humedad y vecinos conservan profundidad, método y desconocidos',
    () async {
      final e = await finca();
      final p = e.plantacion!;
      await e.guardarEvento(
        Evento(
          id: '',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: TipoEvento.observacion,
          fecha: base.fecha,
          observacion: Observacion.humedadSuelo,
          cantidad: .25,
          unidad: 'm³/m³',
          profundidadCm: 20,
          metodo: 'Sensor',
        ),
      );
      await e.guardarEvento(
        evento(
          p,
          TipoEvento.observacion,
          id: 'vecinos',
          observacion: Observacion.vecinos,
        ),
      );
      final otra = AppEstado(await Almacen.abrir(), reloj: () => base.fecha);
      await otra.preparada;
      final suelo = otra.eventos.firstWhere(
        (x) => x.observacion == Observacion.humedadSuelo,
      );
      expect(suelo.profundidadCm, 20);
      expect(suelo.metodo, 'Sensor');
      expect(
        otra.eventos.firstWhere((x) => x.id == 'vecinos').cantidad,
        isNull,
      );
    },
  );
  test('fichas y semanas producen vistas con fecha desconocida o intervalo sin duplicar', () async {
    final e = await finca();
    await e.guardarPlantacion(
      Plantacion.deJson({
        ...e.plantacion!.aJson(),
        'plagaReciente': true,
        'plagaTratada': true,
        'inicioPlaga': null,
        'fertilizo': true,
        'fechaFertilizante': null,
      }),
    );
    final p = e.plantacion!;
    await e.guardarRegistro(
      RegistroSemanal(
        plantacionId: p.id,
        fecha: base.fecha,
        riegos: 2,
        plaga: NivelPlaga.moderada,
        fertilizo: true,
      ),
    );
    expect(e.eventos.length, 5);
    expect(
      e.eventos
          .where((x) => x.origen == 'ficha-inicial')
          .every((x) => x.fecha == null),
      isTrue,
    );
    final semanal = e.eventos.firstWhere((x) => x.origen == 'resumen-semanal');
    expect(semanal.fecha, isNull);
    expect(semanal.hasta!.difference(semanal.desde!).inDays, 6);
    final otra = AppEstado(await Almacen.abrir(), reloj: () => base.fecha);
    await otra.preparada;
    expect(otra.eventos.map((x) => x.id).toSet().length, 5);
    await otra.borrarRegistro(otra.todosLosRegistros.single);
    expect(otra.eventos.length, 3);
  });
  test(
    'bitácora fechada alimenta alertas sin inventar efectos en rendimiento',
    () async {
      final e = await finca();
      e.clima = base.clima();
      final p = e.plantacion!;
      final antes = e.recomendacion;
      await e.guardarEvento(
        Evento(
          id: 'p1',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: TipoEvento.plaga,
          fecha: base.fecha,
          severidad: 'fuerte',
        ),
      );
      expect(e.recomendacion.avisos, contains(Aviso.plaga));
      expect(e.recomendacion.factorRendimiento, antes.factorRendimiento);
      await e.guardarEvento(
        Evento(
          id: 'p1',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: TipoEvento.plaga,
          fecha: base.fecha,
          severidad: 'ninguna',
        ),
      );
      expect(e.recomendacion.avisos, isNot(contains(Aviso.plaga)));
    },
  );
  test('paquete se importa dos veces sin duplicar cosechas, riegos ni aplicaciones', () async {
    final e = await finca();
    final p = e.plantacion!;
    await e.guardarEvento(
      evento(p, TipoEvento.cosecha, cantidad: 10, unidad: 'kg'),
    );
    await e.guardarEvento(
      evento(
        p,
        TipoEvento.fertilizacion,
        id: 'f1',
        cantidad: 3,
        unidad: 'kg',
        referencia: 'ha',
      ),
    );
    await e.guardarAgua(
      SuministroAgua(fecha: base.fecha, disponibilidad: DisponibilidadAgua.si),
      RegistroRiego(
        loteId: p.loteId,
        campaniaId: p.id,
        fecha: base.fecha,
        rego: true,
        laminaMm: 3,
      ),
    );
    e.clima = [
      DiaClima(
        fecha: base.fecha,
        tmax: 30,
        tmin: 20,
        humedad: 50,
        viento: 2,
        radiacion: 20,
        lluvia: null,
      ),
    ];
    final paquete = jsonEncode(e.exportarPaquete());
    final destino = await base.abrir();
    await destino.importarPaquete(paquete);
    await destino.importarPaquete(paquete);
    expect(destino.campanias.length, 1);
    expect(destino.eventos.length, 2);
    expect(destino.riegosDiarios.length, 1);
    expect(destino.kilosCosechados(p.id), 10);
    expect(destino.clima.single.lluvia, isNull);
    final otra = AppEstado(await Almacen.abrir(), reloj: () => base.fecha);
    await otra.preparada;
    expect(otra.clima.single.lluvia, isNull);
    expect(otra.eventos.length, 2);
  });
  test(
    'conflictos e ID huérfano rechazan importación completa sin cambiar datos',
    () async {
      final e = await finca();
      final p = e.plantacion!;
      await e.guardarEvento(
        evento(p, TipoEvento.cosecha, cantidad: 10, unidad: 'kg'),
      );
      final paquete = e.exportarPaquete();
      final dato = (paquete['datos'] as Map)['eventos'] as List;
      (dato.single as Map)['cantidad'] = 99;
      await expectLater(
        e.importarPaquete(jsonEncode(paquete)),
        throwsFormatException,
      );
      expect(e.kilosCosechados(p.id), 10);
      (dato.single as Map)['campania'] = 'inexistente';
      await expectLater(
        e.importarPaquete(jsonEncode(paquete)),
        throwsFormatException,
      );
      expect(e.kilosCosechados(p.id), 10);
    },
  );
  test(
    'V2 se respalda y migra el riego a la campaña correcta una sola vez',
    () async {
      final e = await finca();
      final j = e.exportarPaquete()['datos'] as Map<String, dynamic>;
      j['version'] = 2;
      j.remove('eventos');
      j['riegosDiarios'] = [
        RegistroRiego(
          loteId: e.plantacion!.loteId,
          fecha: base.fecha,
          rego: true,
        ).aJson()..remove('campania'),
      ];
      final texto = jsonEncode(j);
      final migrada = await base.abrir(guardado: {'fincaV2': texto});
      expect(migrada.riegosDiarios.single.campaniaId, migrada.plantacion!.id);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('fincaV2'), texto);
      expect(jsonDecode(prefs.getString('fincaV3')!)['version'], 3);
    },
  );
  test(
    'tomate y variedad desconocida se exportan sin asignar perfil de maíz',
    () async {
      final e = await finca();
      await e.guardarPlantacion(
        Plantacion.deJson({...e.plantacion!.aJson(), 'cultivo': 'tomate'}),
      );
      final revision =
          (e.exportarPaquete()['revision'] as Map)['campanias'] as List;
      expect((revision.single as Map)['perfil'], isNull);
      expect(
        ((e.exportarPaquete()['datos'] as Map)['plantaciones'] as List)
            .single['cultivo'],
        'tomate',
      );
    },
  );

  test('exportar historia emite una sola geometría por lote físico', () async {
    final e = await finca();
    final anterior = e.plantacion!;
    await e.cerrarCampania(anterior.id, base.fecha);
    await e.guardarPlantacion(
      Plantacion.deJson({
        ...anterior.aJson(),
        'id': '',
        'fecha': fechaIso(base.fecha),
      }),
    );
    final features = e.exportarGeoJson()['features'] as List;
    expect(features.length, 1); // Finca de prueba sin contorno, un único lote.
    expect((features.single['properties']['campanias'] as List).length, 2);
    expect(e.lotes.length, 1);
  });
  test(
    'paquete rechaza fechas imposibles, severidad inválida e historia solapada',
    () async {
      final e = await finca();
      Map<String, dynamic> paquete() =>
          jsonDecode(jsonEncode(e.exportarPaquete())) as Map<String, dynamic>;
      var j = paquete();
      j['datos']['plantaciones'][0]['fecha'] = '2026-02-31';
      await expectLater(
        e.importarPaquete(jsonEncode(j)),
        throwsFormatException,
      );
      j = paquete();
      j['datos']['eventos'] = [
        evento(e.plantacion!, TipoEvento.plaga).aJson()..['severidad'] = 'mala',
      ];
      await expectLater(
        e.importarPaquete(jsonEncode(j)),
        throwsFormatException,
      );
      j = paquete();
      j['datos']['plantaciones'].add({
        ...e.plantacion!.aJson(),
        'id': 'otra',
        'fin': '2026-07-19',
      });
      await expectLater(
        e.importarPaquete(jsonEncode(j)),
        throwsFormatException,
      );
      expect(e.campanias.length, 1);
    },
  );
}
