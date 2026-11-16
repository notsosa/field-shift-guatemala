// Pruebas de los formularios simplificados: bitácora, agua, resumen semanal,
// selectores de fecha y plantación. No usan internet ni capturas de referencia.
import 'dart:io';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/datos/clima.dart';
import 'package:field_shift/datos/mapa.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/eventos.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/ui/agua.dart';
import 'package:field_shift/ui/bitacora.dart';
import 'package:field_shift/ui/plantacion.dart';
import 'package:field_shift/ui/registro.dart';
import 'package:field_shift/ui/tema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _hoy = DateTime(2026, 11, 14);

class ClimaFalso extends ServicioClima {
  @override
  Future<bool> hayWifi() async => true;

  @override
  Future<ClimaDescargado> descargar({
    required double latitud,
    required double longitud,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final dias = <DiaClima>[];
    final n = hasta.difference(desde).inDays - 3;
    for (var i = 0; i < n; i++) {
      dias.add(
        DiaClima(
          fecha: DateTime(desde.year, desde.month, desde.day + i),
          tmax: 31 + 2 * math.sin(i / 5),
          tmin: 20 + math.cos(i / 7),
          humedad: 62,
          viento: 2.1,
          radiacion: 21,
          lluvia: i % 9 == 0 ? 14 : 0,
        ),
      );
    }
    return ClimaDescargado(dias: dias, elevacion: 373);
  }
}

class MapaFalso extends ServicioMapa {
  MapaFalso() : super(null);

  @override
  Future<Uint8List?> tesela(
    CapaMapa capa,
    int z,
    int x,
    int y, {
    bool guardar = true,
  }) async => null;
}

Future<ByteData> _bytes(String ruta) async =>
    ByteData.sublistView(await File(ruta).readAsBytes());

Future<void> _cargarFuentes() async {
  final inter = FontLoader('Inter')
    ..addFont(_bytes('assets/fuentes/Inter.ttf'));
  await inter.load();
  final cache =
      Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['LOCALAPPDATA']}/Pub/Cache';
  final carpeta = Directory('$cache/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .where(
        (d) => d.path
            .replaceAll('\\', '/')
            .split('/')
            .last
            .startsWith('cupertino_icons-'),
      )
      .last;
  final iconos = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(_bytes('${carpeta.path}/assets/CupertinoIcons.ttf'));
  await iconos.load();
}

/// Finca de ejemplo: maíz sin riego y frijol con goteo (la seleccionada).
Future<AppEstado> _estado() async {
  SharedPreferences.setMockInitialValues({});
  final e = AppEstado(
    await Almacen.abrir(),
    servicioClima: ClimaFalso(),
    servicioMapa: MapaFalso(),
    reloj: () => _hoy,
  );
  await e.preparada;
  await e.cargarEjemplo();
  return e;
}

/// Abre [pantalla] sobre una app mínima, con el texto al tamaño [escala].
Future<void> _abrir(
  WidgetTester t,
  AppEstado e,
  Widget pantalla, {
  double escala = 1,
}) async {
  t.view.physicalSize = const Size(390, 844) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    Alcance(
      estado: e,
      child: CupertinoApp(
        theme: temaApp(null),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es'), Locale('en')],
        localizationsDelegates: [
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(escala)),
          child: child!,
        ),
        home: const SizedBox(),
      ),
    ),
  );
  t
      .state<NavigatorState>(find.byType(Navigator))
      .push(CupertinoPageRoute<void>(builder: (_) => pantalla));
  await t.pumpAndSettle();
}

Future<void> _visible(WidgetTester t, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await t.scrollUntilVisible(
      finder,
      220,
      scrollable: find.byType(Scrollable).first,
      maxScrolls: 30,
    );
  }
  await t.ensureVisible(finder.last);
  await t.pumpAndSettle();
}

Future<void> _pulsa(WidgetTester t, String texto) async {
  final f = find.text(texto);
  await _visible(t, f);
  await t.tap(f.hitTestable().last);
  await t.pumpAndSettle();
}

/// Pulsa un botón de un diálogo de confirmación.
Future<void> _dialogo(WidgetTester t, String texto) async {
  await t.tap(find.text(texto).hitTestable().last);
  await t.pumpAndSettle();
}

Future<void> _campo(WidgetTester t, String titulo, String valor) async {
  final f = find.byWidgetPredicate((w) => w is Campo && w.titulo == titulo);
  await _visible(t, f);
  await t.enterText(
    find.descendant(of: f, matching: find.byType(CupertinoTextField)),
    valor,
  );
  await t.pumpAndSettle();
}

Evento _declarado(AppEstado e, TipoEvento tipo) => e
    .eventosDe(e.plantacion!.id)
    .firstWhere((x) => !x.derivado && x.tipo == tipo);

BotonPrincipal _guardar(WidgetTester t) =>
    t.widget<BotonPrincipal>(find.widgetWithText(BotonPrincipal, 'Guardar'));

void main() {
  setUpAll(_cargarFuentes);

  group('1. bitácora: eventos', () {
    testWidgets('1a. sin cantidad no se guardan unidad ni referencia', (
      t,
    ) async {
      final e = await _estado();
      await _abrir(
        t,
        e,
        PantallaEvento(
          campaniaId: e.plantacion!.id,
          tipoInicial: TipoEvento.tratamiento,
        ),
      );
      await _campo(t, 'Producto', 'Caldo bordelés');
      await _pulsa(t, 'Guardar');
      final x = _declarado(e, TipoEvento.tratamiento);
      expect(x.producto, 'Caldo bordelés');
      expect(x.cantidad, isNull);
      expect(x.unidad, isNull);
      expect(x.referencia, isNull);
    });

    testWidgets('1a. con cantidad (con espacios y coma) sí se guardan', (
      t,
    ) async {
      final e = await _estado();
      await _abrir(
        t,
        e,
        PantallaEvento(
          campaniaId: e.plantacion!.id,
          tipoInicial: TipoEvento.fertilizacion,
        ),
      );
      await _campo(t, 'Producto', 'Urea');
      await _campo(t, 'Cantidad aplicada', '  2,5 ');
      await _pulsa(t, 'Guardar');
      final x = _declarado(e, TipoEvento.fertilizacion);
      expect(x.cantidad, 2.5);
      expect(x.unidad, 'kg');
      expect(x.referencia, 'desconocida');
    });

    testWidgets('1a. una pérdida sin cantidad conserva qué se perdió', (
      t,
    ) async {
      final e = await _estado();
      await _abrir(
        t,
        e,
        PantallaEvento(
          campaniaId: e.plantacion!.id,
          tipoInicial: TipoEvento.perdida,
        ),
      );
      await _pulsa(t, 'Guardar');
      final x = _declarado(e, TipoEvento.perdida);
      expect(x.cantidad, isNull);
      expect(x.unidad, isNull);
      expect(x.referencia, 'produccionEsperada');
    });

    test('1b. el detalle nunca muestra textos crudos ni .0', () async {
      final e = await _estado();
      final p = e.plantacion!;
      Evento ev({
        TipoEvento tipo = TipoEvento.tratamiento,
        double? cantidad,
        String? unidad,
        String? referencia,
        String? severidad,
        double? profundidad,
      }) => Evento(
        id: 'x',
        campaniaId: p.id,
        loteId: p.loteId,
        tipo: tipo,
        fecha: _hoy,
        cantidad: cantidad,
        unidad: unidad,
        referencia: referencia,
        severidad: severidad,
        profundidadCm: profundidad,
      );
      final d = detalleEvento(
        e,
        ev(cantidad: 5.0, unidad: 'otra', referencia: 'L de mezcla'),
      );
      expect(d, contains('5 otra unidad'));
      expect(d, contains('cada litro de mezcla'));
      expect(d, isNot(contains('5.0')));
      expect(d, isNot(contains('L de mezcla')));
      final desconocida = detalleEvento(
        e,
        ev(cantidad: 2.5, unidad: 'L', referencia: 'desconocida'),
      );
      expect(desconocida, contains('2.5 L'));
      expect(desconocida, isNot(contains('desconocida')));
      expect(
        detalleEvento(
          e,
          ev(
            tipo: TipoEvento.perdida,
            cantidad: 30.0,
            unidad: '%',
            referencia: 'produccionEsperada',
          ),
        ),
        allOf(contains('30 %'), contains('producción esperada')),
      );
      expect(
        detalleEvento(e, ev(tipo: TipoEvento.plaga, severidad: 'moderada')),
        contains('Media'),
      );
      expect(numeroLimpio(5.0), '5');
      expect(numeroLimpio(0.125), '0.125');
      // La ficha inicial guarda el tipo de abono como nombre de enum.
      final inicial = e
          .eventosDe(p.id)
          .firstWhere((x) => x.origen == 'ficha-inicial');
      expect(detalleEvento(e, inicial), isNot(contains('quimico')));
    });

    testWidgets('1c. primero lo básico; el resto detrás de «Más detalles»', (
      t,
    ) async {
      final e = await _estado();
      await _abrir(
        t,
        e,
        PantallaEvento(
          campaniaId: e.plantacion!.id,
          tipoInicial: TipoEvento.tratamiento,
        ),
      );
      expect(find.text('Producto'), findsOneWidget);
      expect(find.text('Cantidad aplicada'), findsOneWidget);
      expect(find.text('Más detalles (opcional)'), findsOneWidget);
      expect(find.text('¿La cantidad es para…?'), findsNothing);
      expect(find.text('Nota'), findsNothing);
      await _pulsa(t, 'Más detalles (opcional)');
      expect(find.text('¿La cantidad es para…?'), findsOneWidget);
      expect(find.text('Nota'), findsOneWidget);
      expect(find.text('Dosis por'), findsNothing);
    });
  });

  group('2. historial', () {
    testWidgets(
      'aviso de otras unidades, pérdidas distintas y filas rotuladas',
      (t) async {
        final e = await _estado();
        final p = e.plantacion!;
        Evento ev(
          String id,
          TipoEvento tipo, {
          double? c,
          String? u,
          String? r,
        }) => Evento(
          id: id,
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: tipo,
          fecha: _hoy,
          cantidad: c,
          unidad: u,
          referencia: r,
        );
        await e.guardarEvento(ev('c1', TipoEvento.cosecha, c: 10, u: 'kg'));
        await e.guardarEvento(ev('c2', TipoEvento.cosecha, c: 3, u: 'otra'));
        await e.guardarEvento(
          ev('p1', TipoEvento.perdida, c: 20, u: '%', r: 'produccionEsperada'),
        );
        await e.guardarAgua(
          SuministroAgua(fecha: _hoy, disponibilidad: DisponibilidadAgua.si),
          RegistroRiego(
            loteId: p.loteId,
            campaniaId: p.id,
            fecha: _hoy,
            rego: true,
            laminaMm: 5,
          ),
        );
        await _abrir(t, e, PantallaBitacora(campaniaId: p.id));
        expect(
          find.text('Hay cosechas en otras unidades que no se suman a los kg.'),
          findsOneWidget,
        );
        expect(find.textContaining('Actividad · Pérdida'), findsOneWidget);
        expect(
          find.textContaining('Actividad · Cosecha parcial'),
          findsWidgets,
        );
        expect(find.textContaining('Riego · '), findsOneWidget);
        expect(find.textContaining('Resumen de la semana · '), findsOneWidget);
        expect(find.textContaining('Resumen: editar'), findsNothing);
        expect(t.takeException(), isNull);
      },
    );
  });

  group('3. errores visibles', () {
    testWidgets('en la bitácora el error queda fijo sobre Guardar, en rojo', (
      t,
    ) async {
      final e = await _estado();
      await _abrir(
        t,
        e,
        PantallaEvento(
          campaniaId: e.plantacion!.id,
          tipoInicial: TipoEvento.cosecha,
        ),
      );
      await _campo(t, 'Cantidad cosechada', 'abc');
      await _pulsa(t, 'Guardar');
      final error = find.byKey(const Key('error-guardar'));
      expect(error, findsOneWidget);
      final texto = t.widget<Text>(error);
      final contexto = t.element(error);
      expect(texto.style!.color, Paleta.de(contexto, Paleta.rojo));
      expect(
        t.getBottomLeft(error).dy,
        lessThanOrEqualTo(
          t.getTopLeft(find.widgetWithText(BotonPrincipal, 'Guardar')).dy,
        ),
      );
    });
  });

  group('4. agua y riego', () {
    testWidgets('4a. el selector de fecha se limita a la campaña', (t) async {
      final h = t.ensureSemantics();
      final e = await _estado();
      final frijol = e.plantacion!;
      await _abrir(t, e, PantallaAgua(campaniaId: frijol.id));
      await t.tap(find.text('Fecha'));
      await t.pumpAndSettle();
      expect(find.text('Noviembre 2026'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('15 nov 2026.*no disponible')),
        findsOneWidget,
      );
      await t.tap(find.byIcon(CupertinoIcons.chevron_left));
      await t.pumpAndSettle();
      expect(find.text('Octubre 2026'), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('6 oct 2026.*no disponible')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^7 oct 2026$')), findsOneWidget);
      await _pulsa(t, 'Cancelar');
      // Campaña cerrada: el máximo es su fin.
      final maiz = e.plantaciones.first;
      final fin = DateTime(2026, 11, 11);
      await e.cerrarCampania(maiz.id, fin);
      await t.pumpWidget(const SizedBox());
      await _abrir(t, e, PantallaAgua(campaniaId: maiz.id));
      await t.tap(find.text('Fecha'));
      await t.pumpAndSettle();
      expect(
        find.bySemanticsLabel(RegExp('12 nov 2026.*no disponible')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp(r'^11 nov 2026$')), findsOneWidget);
      h.dispose();
    });

    testWidgets('4b y 4e. el botón desactivado explica el motivo', (t) async {
      final e = await _estado();
      await e.guardarPlantacion(
        Plantacion.deJson({...e.plantaciones.first.aJson(), 'riego': 'goteo'}),
      );
      await _abrir(t, e, const PantallaAgua());
      expect(_guardar(t).alPulsar, isNull);
      expect(
        find.text('Elige la plantación que recibió el riego'),
        findsOneWidget,
      );
      await t.tap(find.byKey(const Key('elegir-plantacion-riego')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Frijol ·').last);
      await t.pumpAndSettle();
      // Todo en «sin dato» y nada guardado.
      expect(_guardar(t).alPulsar, isNull);
      expect(find.text('No hay nada que guardar'), findsOneWidget);
      await _pulsa(t, 'Hay agua');
      expect(_guardar(t).alPulsar, isNotNull);
      expect(find.text('No hay nada que guardar'), findsNothing);
    });

    testWidgets('4c. cambiar de plantación con datos pide confirmación', (
      t,
    ) async {
      final e = await _estado();
      await e.guardarPlantacion(
        Plantacion.deJson({...e.plantaciones.first.aJson(), 'riego': 'goteo'}),
      );
      await _abrir(t, e, const PantallaAgua());
      final elegir = find.byKey(const Key('elegir-plantacion-riego'));
      await t.tap(elegir);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Maíz ·').last);
      await t.pumpAndSettle();
      // Sin datos escritos no pregunta nada.
      expect(find.text('¿Cambiar de plantación?'), findsNothing);
      final rego = find.byKey(const ValueKey('¿Regaste en esta fecha?'));
      await _visible(t, rego);
      await t.tap(find.descendant(of: rego, matching: find.text('Sí')));
      await t.pumpAndSettle();
      await t.ensureVisible(elegir);
      await t.pumpAndSettle();
      await t.tap(elegir);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Frijol ·').last);
      await t.pumpAndSettle();
      expect(find.text('¿Cambiar de plantación?'), findsOneWidget);
      await _dialogo(t, 'Seguir aquí');
      expect(
        find.descendant(of: elegir, matching: find.text('Maíz')),
        findsOneWidget,
      );
      await t.tap(elegir);
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Frijol ·').last);
      await t.pumpAndSettle();
      await _dialogo(t, 'Cambiar');
      expect(
        find.descendant(of: elegir, matching: find.text('Frijol')),
        findsOneWidget,
      );
      // El formulario nuevo está vacío.
      expect(find.text('No hay nada que guardar'), findsOneWidget);
    });

    testWidgets('4d. borrar un riego guardado pide confirmación', (t) async {
      final e = await _estado();
      final p = e.plantacion!;
      await e.guardarAgua(
        SuministroAgua(fecha: _hoy, disponibilidad: DisponibilidadAgua.si),
        RegistroRiego(
          loteId: p.loteId,
          campaniaId: p.id,
          fecha: _hoy,
          rego: true,
          laminaMm: 5,
        ),
      );
      await _abrir(t, e, PantallaAgua(campaniaId: p.id));
      await _pulsa(t, 'Borrar este registro');
      expect(find.text('Cancelar'), findsOneWidget);
      await _dialogo(t, 'Cancelar');
      expect(e.riegoDe(p.loteId, _hoy, campaniaId: p.id), isNotNull);
      await _pulsa(t, 'Borrar este registro');
      await _dialogo(t, 'Borrar');
      expect(e.riegoDe(p.loteId, _hoy, campaniaId: p.id), isNull);
      expect(find.byKey(const Key('borrar-riego')), findsNothing);
    });

    testWidgets('4d. sin riego guardado no aparece «Borrar este registro»', (
      t,
    ) async {
      final e = await _estado();
      await _abrir(t, e, PantallaAgua(campaniaId: e.plantacion!.id));
      expect(find.text('Borrar este registro'), findsNothing);
    });

    testWidgets('4f. explica la diferencia entre necesitar y regar', (t) async {
      final e = await _estado();
      await _abrir(t, e, PantallaAgua(campaniaId: e.plantacion!.id));
      expect(find.byKey(const Key('explica-riego')), findsOneWidget);
      expect(find.text('¿Necesitabas regar?'), findsOneWidget);
      expect(find.text('¿Regaste?'), findsOneWidget);
    });
  });

  group('5. selectores de fecha', () {
    testWidgets('Cancelar y tocar fuera dejan la fecha; Listo la cambia', (
      t,
    ) async {
      final e = await _estado();
      final p = e.plantacion!;
      final txt = e.txt;
      await _abrir(t, e, PantallaAgua(campaniaId: p.id));
      final nueva = DateTime(2026, 11, 5);
      Future<void> mover() async {
        await t.tap(find.text('Fecha'));
        await t.pumpAndSettle();
        await t.tap(find.text('5').hitTestable().last);
        await t.pumpAndSettle();
      }

      await mover();
      await _pulsa(t, 'Cancelar');
      expect(find.text(txt.fechaLarga(_hoy)), findsOneWidget);
      await mover();
      await t.tapAt(const Offset(195, 20)); // fuera del selector
      await t.pumpAndSettle();
      expect(find.text('Noviembre 2026'), findsNothing);
      expect(find.text(txt.fechaLarga(_hoy)), findsOneWidget);
      await mover();
      await _pulsa(t, 'Listo');
      expect(find.text(txt.fechaLarga(nueva)), findsOneWidget);
    });

    testWidgets('Cancelar en la bitácora deja la fecha del evento', (t) async {
      final e = await _estado();
      await _abrir(
        t,
        e,
        PantallaEvento(
          campaniaId: e.plantacion!.id,
          tipoInicial: TipoEvento.cosecha,
        ),
      );
      await t.tap(find.text('Fecha'));
      await t.pumpAndSettle();
      await t.tap(find.byIcon(CupertinoIcons.chevron_left));
      await t.pumpAndSettle();
      await t.tap(find.text('30').hitTestable().last);
      await t.pumpAndSettle();
      await _pulsa(t, 'Cancelar');
      expect(find.text(e.txt.fechaLarga(_hoy)), findsOneWidget);
    });

    testWidgets('una siembra de hace más de 3 años no se recorta', (t) async {
      final e = await _estado();
      final frijol = e.plantacion!;
      final antigua = DateTime(2021, 3, 1);
      await e.guardarPlantacion(
        Plantacion.deJson({...frijol.aJson(), 'fecha': '2021-03-01'}),
      );
      await _abrir(t, e, PantallaPlantacion(id: frijol.id));
      await t.tap(find.text('Fecha de siembra'));
      await t.pumpAndSettle();
      expect(find.text('Marzo 2021'), findsOneWidget);
      expect(find.textContaining('fuera del rango'), findsNothing);
      await _pulsa(t, 'Listo');
      await _pulsa(t, 'Guardar');
      expect(e.plantacionPorId(frijol.id)!.fecha, antigua);
    });
  });

  group('6. resumen de la semana', () {
    testWidgets('6a. el riego empieza sin respuesta y Guardar la exige', (
      t,
    ) async {
      final e = await _estado();
      final p = e.plantacion!;
      await _abrir(t, e, PantallaRegistro(plantacionId: p.id));
      expect(t.widget<Text>(find.byKey(const Key('veces-riego'))).data, '—');
      expect(find.text('No regué'), findsOneWidget);
      expect(_guardar(t).alPulsar, isNull);
      expect(find.byKey(const Key('motivo-guardar')), findsOneWidget);
      await _pulsa(t, 'No regué');
      expect(t.widget<Text>(find.byKey(const Key('veces-riego'))).data, '0');
      expect(_guardar(t).alPulsar, isNotNull);
      await _pulsa(t, 'Guardar');
      final nuevo = e
          .registrosDe(p.id)
          .firstWhere((r) => soloFecha(r.fecha) == soloFecha(_hoy));
      expect(nuevo.riegos, 0);
    });

    testWidgets('6a. el más (+) también cuenta como respuesta', (t) async {
      final e = await _estado();
      final p = e.plantacion!;
      await _abrir(t, e, PantallaRegistro(plantacionId: p.id));
      await t.tap(find.byIcon(CupertinoIcons.plus));
      await t.pumpAndSettle();
      expect(t.widget<Text>(find.byKey(const Key('veces-riego'))).data, '1');
      expect(_guardar(t).alPulsar, isNotNull);
    });

    testWidgets('6a. sin riego no se pregunta ni se exige', (t) async {
      final e = await _estado();
      final maiz = e.plantaciones.first;
      await _abrir(t, e, PantallaRegistro(plantacionId: maiz.id));
      expect(find.byKey(const Key('veces-riego')), findsNothing);
      expect(_guardar(t).alPulsar, isNotNull);
    });

    testWidgets('6b. si hay un resumen de los últimos 6 días, lo edita', (
      t,
    ) async {
      final e = await _estado();
      final p = e.plantacion!;
      final fecha = DateTime(2026, 11, 11);
      await e.guardarRegistro(
        RegistroSemanal(
          plantacionId: p.id,
          fecha: fecha,
          riegos: 3,
          plaga: NivelPlaga.moderada,
          notaPlaga: 'Gusano',
          fertilizo: false,
        ),
      );
      final antes = e.registrosDe(p.id).length;
      await _abrir(t, e, PantallaRegistro(plantacionId: p.id));
      expect(
        find.text('Estás editando el resumen del ${e.txt.fechaLarga(fecha)}'),
        findsOneWidget,
      );
      expect(t.widget<Text>(find.byKey(const Key('veces-riego'))).data, '3');
      await t.tap(find.byIcon(CupertinoIcons.plus));
      await t.pumpAndSettle();
      await _pulsa(t, 'Guardar');
      expect(e.registrosDe(p.id).length, antes);
      final editado = e
          .registrosDe(p.id)
          .firstWhere((r) => soloFecha(r.fecha) == fecha);
      expect(editado.riegos, 4);
      expect(editado.notaPlaga, 'Gusano');
    });

    testWidgets('6b. un resumen de hace 9 días no se reabre', (t) async {
      final e = await _estado();
      await _abrir(t, e, PantallaRegistro(plantacionId: e.plantacion!.id));
      expect(find.byKey(const Key('editando-resumen')), findsNothing);
    });
  });

  group('7. plantación', () {
    testWidgets(
      '7a y 7b. títulos llanos y el borrado cuenta lo que se pierde',
      (t) async {
        final e = await _estado();
        final p = e.plantacion!;
        await e.guardarEvento(
          Evento(
            id: 'c1',
            campaniaId: p.id,
            loteId: p.loteId,
            tipo: TipoEvento.cosecha,
            fecha: _hoy,
            cantidad: 4,
            unidad: 'kg',
          ),
        );
        await e.guardarAgua(
          SuministroAgua(fecha: _hoy, disponibilidad: DisponibilidadAgua.si),
          RegistroRiego(
            loteId: p.loteId,
            campaniaId: p.id,
            fecha: _hoy,
            rego: true,
          ),
        );
        await _abrir(t, e, PantallaPlantacion(id: p.id));
        for (final titulo in [
          'Variedad y próximas siembras (opcional)',
          '¿Tuvo plaga o abono al sembrar? (opcional)',
        ]) {
          await _visible(t, find.text(titulo));
          expect(find.text(titulo), findsOneWidget);
        }
        await _pulsa(t, 'Contorno del lote y borrar (opcional)');
        await _pulsa(t, 'Borrar plantación');
        expect(find.textContaining('1 actividad'), findsOneWidget);
        expect(find.textContaining('1 riego'), findsOneWidget);
        expect(find.textContaining('1 resumen de la semana'), findsOneWidget);
        await _dialogo(t, 'Cancelar');
        expect(e.plantacionPorId(p.id), isNotNull);
      },
    );
  });

  group('8. campañas', () {
    testWidgets('ya no ofrece iniciar otra campaña', (t) async {
      final e = await _estado();
      await e.cerrarCampania(e.plantacion!.id, _hoy);
      await _abrir(t, e, const PantallaCampanias());
      expect(find.textContaining('Iniciar otra'), findsNothing);
      expect(find.textContaining('Start another'), findsNothing);
      expect(find.text('Frijol'), findsOneWidget);
    });
  });

  group('letra grande (2.0) sin desbordes', () {
    for (final (tipo, escala) in [
      for (final tipo in TipoEvento.values) (tipo, 2.0),
      (TipoEvento.tratamiento, 3.2),
      (TipoEvento.observacion, 3.2),
    ]) {
      testWidgets('PantallaEvento ${tipo.name} x$escala', (t) async {
        final e = await _estado();
        await _abrir(
          t,
          e,
          PantallaEvento(campaniaId: e.plantacion!.id, tipoInicial: tipo),
          escala: escala,
        );
        expect(t.takeException(), isNull);
        await _pulsa(t, 'Más detalles (opcional)');
        expect(t.takeException(), isNull);
      });
    }

    testWidgets('PantallaEvento observación de vecinos con error', (t) async {
      final e = await _estado();
      await _abrir(
        t,
        e,
        PantallaEvento(
          campaniaId: e.plantacion!.id,
          tipoInicial: TipoEvento.observacion,
        ),
        escala: 2,
      );
      await _campo(t, 'Valor medido', 'x');
      await _pulsa(t, 'Guardar');
      expect(find.byKey(const Key('error-guardar')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('PantallaAgua', (t) async {
      final e = await _estado();
      await _abrir(t, e, PantallaAgua(campaniaId: e.plantacion!.id), escala: 2);
      expect(t.takeException(), isNull);
      await _pulsa(t, 'Hay agua');
      await _visible(t, find.byKey(const Key('agua-volumen')));
      await _campo(t, 'Saldo (m³)', 'abc');
      await _pulsa(t, 'Guardar');
      expect(find.byKey(const Key('error-guardar')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('PantallaAgua sin plantación elegida', (t) async {
      final e = await _estado();
      await e.guardarPlantacion(
        Plantacion.deJson({...e.plantaciones.first.aJson(), 'riego': 'goteo'}),
      );
      await _abrir(t, e, const PantallaAgua(), escala: 2);
      expect(find.byKey(const Key('motivo-guardar')), findsOneWidget);
      expect(t.takeException(), isNull);
    });

    testWidgets('PantallaRegistro', (t) async {
      final e = await _estado();
      await _abrir(
        t,
        e,
        PantallaRegistro(plantacionId: e.plantacion!.id),
        escala: 2,
      );
      expect(t.takeException(), isNull);
    });
  });
}
