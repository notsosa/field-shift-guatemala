// Pruebas de las pantallas. Además de comprobar los flujos, guardan una imagen
// de cada pantalla en test/capturas/ para revisar el diseño:
//
//   flutter test test/pantallas_test.dart --update-goldens
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/datos/clima.dart';
import 'package:field_shift/datos/mapa.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/main.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/ui/finca.dart';
import 'package:field_shift/ui/tema.dart';
import 'package:field_shift/ui/flujo.dart';
import 'package:field_shift/ui/hoy.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _hoy = DateTime(2026, 11, 14);

/// Clima de mentira: no usa internet y permite elegir si hay wifi.
class ClimaFalso extends ServicioClima {
  ClimaFalso({this.wifi = true, this.lluvioso = false});

  final bool wifi;
  final bool lluvioso;

  @override
  Future<bool> hayWifi() async => wifi;

  @override
  Future<ClimaDescargado> descargar({
    required double latitud,
    required double longitud,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final dias = <DiaClima>[];
    final n = hasta.difference(desde).inDays - 3; // POWER publica con retraso
    for (var i = 0; i < n; i++) {
      final f = DateTime(desde.year, desde.month, desde.day + i);
      final llueve = lluvioso ? i % 2 == 0 : (i % 9 == 0 && i < n - 16);
      dias.add(
        DiaClima(
          fecha: f,
          tmax: 31 + 2 * math.sin(i / 5),
          tmin: 20 + math.cos(i / 7),
          humedad: 62,
          viento: 2.1,
          radiacion: 21,
          lluvia: llueve ? (lluvioso ? 12 : 14) : 0,
        ),
      );
    }
    return ClimaDescargado(dias: dias, elevacion: 373);
  }
}

/// Mapa de mentira: no hay imágenes guardadas ni descarga, así que el plano se
/// ve como croquis y las pruebas no usan internet.
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

Future<ByteData> _bytes(String ruta) async =>
    ByteData.sublistView(await File(ruta).readAsBytes());

Future<AppEstado> _abrir(
  WidgetTester tester, {
  Brightness brillo = Brightness.light,
  ServicioClima? clima,
  Map<String, Object> guardado = const {},
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  SharedPreferences.setMockInitialValues(guardado);
  tester.view.physicalSize = tamano * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.platformBrightnessTestValue = brillo;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(
        disableAnimations: true,
        reduceMotion: true,
      );
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final estado = AppEstado(
    await Almacen.abrir(),
    servicioClima: clima ?? ClimaFalso(),
    servicioMapa: MapaFalso(),
    reloj: () => _hoy,
  );
  await estado.preparada;
  await tester.pumpWidget(FieldShift(estado: estado));
  await tester.pumpAndSettle();
  return estado;
}

Future<void> _captura(WidgetTester tester, String nombre) => expectLater(
  find.byType(CupertinoApp),
  matchesGoldenFile('capturas/ux/$nombre.png'),
);

/// Toca el lienzo del croquis en las fracciones dadas para marcar esquinas.
Future<void> _marcar(
  WidgetTester tester,
  Key lienzo,
  List<Offset> fracciones,
) async {
  final caja = tester.getRect(find.byKey(lienzo));
  for (final f in fracciones) {
    await tester.tapAt(
      caja.topLeft + Offset(f.dx * caja.width, f.dy * caja.height),
    );
    await tester.pump();
  }
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

Future<void> _tab(WidgetTester t, String texto) async {
  await t.tap(
    find.descendant(
      of: find.byType(CupertinoTabBar),
      matching: find.text(texto),
    ),
  );
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

Future<AppEstado> _ejemplo(
  WidgetTester t, {
  Brightness brillo = Brightness.light,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  final e = await _abrir(t, brillo: brillo, tamano: tamano, escala: escala);
  await _pulsa(t, 'Ver un ejemplo');
  return e;
}

Future<void> _ficha(WidgetTester t, Plantacion p) async {
  await _tab(t, 'Finca');
  final fila = find.byKey(Key('finca-lote-${p.loteId}'));
  await _visible(t, fila);
  await t.tap(fila);
  await t.pumpAndSettle();
  expect(find.byType(PantallaMiPlantacion), findsOneWidget);
}

void main() {
  setUpAll(_cargarFuentes);
  testWidgets('bienvenida y cambio de idioma siguen disponibles', (t) async {
    await _abrir(t);
    await _captura(t, '01_bienvenida');
    await _pulsa(t, 'English');
    expect(find.text('Get started'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'alta de finca y cultivo: datos básicos primero y opcionales desplegables',
    (t) async {
      final e = await _abrir(t);
      await _pulsa(t, 'Empezar');
      final campos = find.byType(CupertinoTextField);
      await t.enterText(campos.at(0), 'La Vega');
      await t.enterText(campos.at(1), '14.8250');
      await t.enterText(campos.at(2), '-89.5312');
      await t.pumpAndSettle();
      await _captura(t, '02_parcela');
      await _pulsa(t, 'Continuar');
      await _marcar(t, const Key('lienzo'), const [
        Offset(.1, .1),
        Offset(.9, .1),
        Offset(.9, .9),
        Offset(.1, .9),
      ]);
      await _pulsa(t, 'Continuar');
      expect(e.parcela!.contorno, isEmpty);
      await _marcar(t, const Key('lienzo'), const [
        Offset(.2, .2),
        Offset(.5, .2),
        Offset(.5, .5),
        Offset(.2, .5),
      ]);
      await _pulsa(t, 'Continuar');
      expect(find.text('Mantener este cultivo'), findsNothing);
      expect(find.byKey(const Key('plaga')), findsNothing);
      await _pulsa(t, 'Cultivo');
      await _pulsa(t, 'Frijol');
      await _pulsa(t, 'Tipo de riego');
      await _pulsa(t, 'Goteo');
      await _captura(t, '03_formulario_basico');
      await _pulsa(t, 'Variedad y próximas siembras (opcional)');
      await _campo(t, 'Variedad', 'ICTA Ligero');
      final mezcla = find.byKey(const Key('permitir-mezcla'));
      await _visible(t, mezcla);
      await t.tap(mezcla);
      await t.pumpAndSettle();
      await _campo(t, 'Mínimo del lote (%)', '60');
      await _pulsa(t, 'Guardar');
      expect(e.configurada, isTrue);
      expect(e.plantacion!.cultivoId, 'frijol');
      expect(e.plantacion!.riego, TipoRiego.goteo);
      expect(e.plantacion!.variedad, 'ICTA Ligero');
      expect(e.plantacion!.proporcionMinima, 60);
      expect(e.plantacion!.plagaReciente, isFalse);
      expect(e.plantacion!.contorno.length, 4);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('Finca es el único acceso de configuración de las plantaciones', (
    t,
  ) async {
    final e = await _ejemplo(t);
    await _tab(t, 'Ajustes');
    expect(find.text('Frijol'), findsNothing);
    expect(find.text('Maíz'), findsNothing);
    expect(find.text('Campañas e historial'), findsNothing);
    expect(find.text('Paquete de datos'), findsNothing);
    await _captura(t, '04_ajustes');
    await _ficha(t, e.plantacion!);
    expect(find.text('Datos de la plantación'), findsOneWidget);
    expect(find.text('Terminar este cultivo'), findsNothing);
    await _captura(t, '05_ficha_plantacion');
    await _pulsa(t, 'Datos de la plantación');
    expect(find.text('Variedad'), findsNothing);
    await _pulsa(t, 'Variedad y próximas siembras (opcional)');
    await _campo(t, 'Variedad', 'Cambio sin guardar');
    await _pulsa(t, 'Atrás');
    expect(e.plantacion!.variedad, isEmpty);
    expect(find.text('Datos de la plantación'), findsOneWidget);
  });

  testWidgets(
    'editar datos conserva fechas desconocidas y el riego de otros lotes',
    (t) async {
      final e = await _ejemplo(t);
      final frijol = e.plantacion!, maiz = e.plantaciones.first;
      await _ficha(t, frijol);
      await _pulsa(t, 'Datos de la plantación');
      await _pulsa(t, 'Variedad y próximas siembras (opcional)');
      await _campo(t, 'Variedad', 'ICTA Ligero');
      await _pulsa(t, 'Guardar');
      expect(e.plantacionPorId(frijol.id)!.variedad, 'ICTA Ligero');
      expect(e.plantacionPorId(frijol.id)!.fechaFertilizante, isNull);
      expect(e.plantacionPorId(maiz.id)!.riego, TipoRiego.ninguno);
    },
  );

  testWidgets(
    'Hoy ofrece resumen; gráficos y explicación del clima requieren abrir detalle',
    (t) async {
      await _ejemplo(t);
      expect(find.text('Agua estimada en el suelo'), findsOneWidget);
      expect(find.text('Últimos 14 días'), findsNothing);
      expect(
        find.textContaining('El balance muestra un escenario'),
        findsNothing,
      );
      await _captura(t, '06_hoy');
      await _pulsa(t, 'Ver detalle del agua y clima');
      expect(find.byType(PantallaDetalleAgua), findsOneWidget);
      expect(find.text('Últimos 14 días'), findsOneWidget);
      await _captura(t, '07_detalle_clima');
      await _pulsa(t, 'Atrás');
      expect(find.text('Últimos 14 días'), findsNothing);
    },
  );

  testWidgets('registro semanal conserva el destino elegido desde la ficha', (
    t,
  ) async {
    final e = await _ejemplo(t);
    final maiz = e.plantaciones.first, frijol = e.plantacion!;
    await _ficha(t, maiz);
    await _pulsa(t, 'Registrar actividad');
    expect(find.text('Riego'), findsNothing);
    expect(find.text('Registro semanal'), findsNothing);
    // «Resumen de la semana» está en el primer nivel del menú.
    await _pulsa(t, 'Resumen de la semana');
    expect(find.text('Veces que regaste'), findsNothing);
    await _pulsa(t, 'Fuerte');
    await _captura(t, '08_resumen_semanal');
    await _pulsa(t, 'Guardar');
    expect(e.registrosDe(maiz.id).single.plaga, NivelPlaga.fuerte);
    expect(e.registrosDe(frijol.id).length, 1);
    expect(e.plantacion!.id, maiz.id);
  });

  testWidgets(
    'registrar cosecha lleva directo al formulario y actualiza historial',
    (t) async {
      final e = await _ejemplo(t);
      final id = e.plantacion!.id;
      await _tab(t, 'Registros');
      expect(find.text('Datos de la plantación'), findsNothing);
      expect(find.text('Campañas e historial'), findsNothing);
      await _pulsa(t, 'Registrar actividad');
      await _captura(t, '09_elegir_actividad');
      await _pulsa(t, 'Cosecha'); // abre directo el formulario
      expect(find.text('Tipo de registro'), findsNothing);
      await _campo(t, 'Cantidad cosechada', '11.5');
      await _captura(t, '10_cosecha');
      await _pulsa(t, 'Guardar');
      expect(e.kilosCosechados(id), 11.5);
      await _pulsa(t, 'Atrás');
      expect(find.text('11.50 kg'), findsOneWidget);
      await _captura(t, '11_registros');
    },
  );

  testWidgets(
    'dos plantaciones con riego requieren destinatario y conservan la otra aplicación',
    (t) async {
      final e = await _ejemplo(t);
      final maiz = e.plantaciones.first, frijol = e.plantacion!;
      await e.guardarPlantacion(
        Plantacion.deJson({...maiz.aJson(), 'riego': 'goteo'}),
      );
      await e.guardarAgua(
        SuministroAgua(fecha: _hoy, disponibilidad: DisponibilidadAgua.si),
        RegistroRiego(
          loteId: maiz.loteId,
          campaniaId: maiz.id,
          fecha: _hoy,
          rego: true,
          laminaMm: 5,
        ),
      );
      await t.pumpAndSettle();
      await _pulsa(t, 'Suministro de agua hoy');
      expect(find.text('Elegir plantación'), findsOneWidget);
      expect(
        t
            .widget<BotonPrincipal>(
              find.widgetWithText(BotonPrincipal, 'Guardar'),
            )
            .alPulsar,
        isNull,
      );
      await t.tap(find.byKey(const Key('elegir-plantacion-riego')));
      await t.pumpAndSettle();
      await t.tap(find.textContaining('Frijol ·').last);
      await t.pumpAndSettle();
      final rego = find.byKey(const ValueKey('¿Regaste en esta fecha?'));
      await _visible(t, rego);
      await t.tap(find.descendant(of: rego, matching: find.text('No')));
      await t.pumpAndSettle();
      await _captura(t, '12_riego_destino');
      await _pulsa(t, 'Guardar');
      expect(
        e.riegoDe(frijol.loteId, _hoy, campaniaId: frijol.id)!.rego,
        isFalse,
      );
      expect(e.riegoDe(maiz.loteId, _hoy, campaniaId: maiz.id)!.laminaMm, 5);
    },
  );

  testWidgets(
    'alta cancelada y contorno inválido no crean plantaciones ni modifican finca',
    (t) async {
      final e = await _ejemplo(t);
      final finca = jsonEncode(e.parcela!.aJson()),
          lotes = jsonEncode(e.lotes.map((x) => x.aJson()).toList());
      await _tab(t, 'Finca');
      await _captura(t, '13_finca');
      await _pulsa(t, 'Nueva plantación');
      await _marcar(t, const Key('lienzo'), const [
        Offset(.22, .60),
        Offset(.40, .60),
        Offset(.40, .78),
        Offset(.22, .78),
      ]);
      await _pulsa(t, 'Continuar');
      await _campo(t, 'Nombre', 'Borrador');
      await _pulsa(t, 'Atrás');
      await _pulsa(t, 'Atrás');
      expect(e.plantaciones.length, 2);
      expect(jsonEncode(e.parcela!.aJson()), finca);
      expect(jsonEncode(e.lotes.map((x) => x.aJson()).toList()), lotes);
      await _pulsa(t, 'Nueva plantación');
      await _marcar(t, const Key('lienzo'), const [
        Offset(.2, .6),
        Offset(.4, .8),
        Offset(.2, .8),
        Offset(.4, .6),
      ]);
      expect(
        t
            .widget<BotonPrincipal>(
              find.widgetWithText(BotonPrincipal, 'Continuar'),
            )
            .alPulsar,
        isNull,
      );
      await _captura(t, '14_contorno_invalido');
    },
  );

  testWidgets('mapa separado mantiene zoom y ubicación del terreno', (t) async {
    final e = await _ejemplo(t);
    final geo = jsonEncode(e.exportarGeoJson());
    await _tab(t, 'Finca');
    await _pulsa(t, 'Ver mapa de la finca');
    expect(find.byType(PantallaMapaFinca), findsOneWidget);
    expect(find.text('Nueva plantación'), findsNothing);
    await _captura(t, '15_mapa');
    final caja = t.getRect(find.byKey(const Key('lienzo-finca')));
    final a = await t.startGesture(
      caja.center + const Offset(-35, 0),
      pointer: 1,
    );
    final b = await t.startGesture(
      caja.center + const Offset(35, 0),
      pointer: 2,
    );
    await a.moveBy(const Offset(-30, 0));
    await b.moveBy(const Offset(30, 0));
    await a.up();
    await b.up();
    await t.pumpAndSettle();
    expect(jsonEncode(e.exportarGeoJson()), geo);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'terminar cultivo y reutilizar lote conservan historial desde su ficha',
    (t) async {
      final e = await _ejemplo(t);
      final anterior = e.plantacion!;
      await _ficha(t, anterior);
      await _pulsa(t, 'Más opciones');
      await _pulsa(t, 'Terminar este cultivo');
      await _pulsa(t, 'Listo');
      await _pulsa(t, 'Terminar cultivo');
      expect(e.plantacionPorId(anterior.id)!.activa, isFalse);
      expect(find.text('Iniciar un cultivo aquí'), findsOneWidget);
      await _captura(t, '16_lote_disponible');
      await _pulsa(t, 'Iniciar un cultivo aquí');
      await _pulsa(t, 'Guardar');
      expect(e.campanias.length, 3);
      expect(e.plantacion!.loteId, anterior.loteId);
      expect(e.plantacion!.id, isNot(anterior.id));
      expect(e.registrosDe(anterior.id).length, 1);
      for (final p in [...e.plantaciones]) {
        await e.cerrarCampania(p.id, _hoy);
      }
      await t.pumpAndSettle();
      await _tab(t, 'Hoy');
      expect(find.textContaining('No hay cultivos en curso.'), findsOneWidget);
      await _tab(t, 'Finca');
      expect(find.text('Lote disponible'), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'idioma unidades y herramientas avanzadas se conservan en Ajustes',
    (t) async {
      final e = await _ejemplo(t);
      await _tab(t, 'Ajustes');
      await _pulsa(t, 'Unidades');
      await _pulsa(t, 'Hectáreas y km');
      expect(e.unidad, Unidad.metrico);
      await _pulsa(t, 'Idioma');
      await _pulsa(t, 'English');
      expect(e.idioma, 'en');
      await _pulsa(t, 'Language');
      await _pulsa(t, 'Español');
      await _pulsa(t, 'Opciones avanzadas');
      // Borrar queda a la vista dentro de Opciones avanzadas, con confirmación.
      expect(find.text('Borrar todos los datos'), findsOneWidget);
      await _captura(t, '17_opciones_avanzadas');
      await _pulsa(t, 'Paquete de datos');
      await t.enterText(find.byKey(const Key('paquete-json')), '{');
      await _pulsa(t, 'Revisar antes de importar');
      expect(find.text('Importar datos revisados'), findsNothing);
      await t.enterText(
        find.byKey(const Key('paquete-json')),
        jsonEncode(e.exportarPaquete()),
      );
      await _pulsa(t, 'Revisar antes de importar');
      await _captura(t, '18_paquete');
      await _pulsa(t, 'Importar datos revisados');
      expect(find.text('Datos importados.'), findsOneWidget);
      expect(e.campanias.length, 2);
    },
  );

  testWidgets(
    'sin wifi explica la falta de clima y no pierde finca al reabrir',
    (t) async {
      final e = await _abrir(t, clima: ClimaFalso(wifi: false));
      await _pulsa(t, 'Ver un ejemplo');
      await _pulsa(t, 'Actualizar clima');
      expect(find.textContaining('wifi'), findsWidgets);
      await _captura(t, '19_sin_clima');
      await _pulsa(t, 'Listo');
      final otra = AppEstado(
        await Almacen.abrir(),
        servicioClima: ClimaFalso(wifi: false),
        reloj: () => _hoy,
      );
      await otra.preparada;
      expect(otra.plantaciones.length, 2);
      expect(otra.plantacion!.id, e.plantacion!.id);
      expect(otra.registros.length, 1);
    },
  );

  for (final (nombre, tamano, escala, brillo) in [
    ('pequeno', const Size(375, 812), 2.0, Brightness.light),
    ('horizontal', const Size(844, 390), 1.6, Brightness.light),
    ('tableta_oscura', const Size(768, 1024), 2.0, Brightness.dark),
    ('letra_maxima', const Size(390, 844), 3.2, Brightness.light),
  ]) {
    testWidgets(
      'flujo accesible: $nombre, texto $escala, movimiento reducido',
      (t) async {
        await _ejemplo(t, tamano: tamano, escala: escala, brillo: brillo);
        for (final tab in ['Hoy', 'Finca', 'Registros', 'Ajustes']) {
          await _tab(t, tab);
          expect(t.takeException(), isNull, reason: '$nombre / $tab');
        }
        await _captura(t, '20_${nombre}_ajustes');
        await _tab(t, 'Registros');
        await _pulsa(t, 'Registrar actividad');
        await _pulsa(t, 'Cosecha');
        await _campo(t, 'Cantidad cosechada', '12');
        await _captura(t, '21_${nombre}_formulario');
        expect(t.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'controles principales tienen objetivos táctiles Android suficientes',
    (t) async {
      await _ejemplo(t);
      final semantics = t.ensureSemantics();
      try {
        for (final tab in ['Hoy', 'Finca', 'Registros', 'Ajustes']) {
          await _tab(t, tab);
          await expectLater(
            t,
            meetsGuideline(androidTapTargetGuideline),
            reason: tab,
          );
        }
      } finally {
        semantics.dispose();
      }
    },
  );

  testWidgets('contraste de texto y controles se verifica en claro y oscuro', (
    t,
  ) async {
    double contraste(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (math.max(x, y) + .05) / (math.min(x, y) + .05);
    }

    for (final brillo in [Brightness.light, Brightness.dark]) {
      await t.pumpWidget(
        CupertinoApp(
          theme: temaApp(brillo),
          home: Builder(
            builder: (context) {
              for (final texto in [
                Paleta.texto,
                Paleta.secundario,
                Paleta.verde,
              ]) {
                for (final fondo in [Paleta.tarjeta, Paleta.fondo]) {
                  expect(
                    contraste(
                      Paleta.de(context, texto),
                      Paleta.de(context, fondo),
                    ),
                    greaterThanOrEqualTo(4.5),
                  );
                }
              }
              return const SizedBox();
            },
          ),
        ),
      );
      await t.pumpAndSettle();
    }
  });
}
