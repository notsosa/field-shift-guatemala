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
      dias.add(DiaClima(
        fecha: f,
        tmax: 31 + 2 * math.sin(i / 5),
        tmin: 20 + math.cos(i / 7),
        humedad: 62,
        viento: 2.1,
        radiacion: 21,
        lluvia: llueve ? (lluvioso ? 12 : 14) : 0,
      ));
    }
    return ClimaDescargado(dias: dias, elevacion: 373);
  }
}

/// Mapa de mentira: no hay imágenes guardadas ni descarga, así que el plano se
/// ve como croquis y las pruebas no usan internet.
class MapaFalso extends ServicioMapa {
  MapaFalso() : super(null);

  @override
  Future<Uint8List?> tesela(CapaMapa capa, int z, int x, int y) async => null;
}

Future<void> _cargarFuentes() async {
  final inter = FontLoader('Inter')..addFont(_bytes('assets/fuentes/Inter.ttf'));
  await inter.load();
  final cache = Platform.environment['PUB_CACHE'] ??
      '${Platform.environment['LOCALAPPDATA']}/Pub/Cache';
  final carpeta = Directory('$cache/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .where((d) => d.path.replaceAll('\\', '/').split('/').last.startsWith('cupertino_icons-'))
      .last;
  final iconos = FontLoader('packages/cupertino_icons/CupertinoIcons')
    ..addFont(_bytes('${carpeta.path}/assets/CupertinoIcons.ttf'));
  await iconos.load();
}

Future<ByteData> _bytes(String ruta) async => ByteData.sublistView(await File(ruta).readAsBytes());

Future<AppEstado> _abrir(
  WidgetTester tester, {
  Brightness brillo = Brightness.light,
  ServicioClima? clima,
  Map<String, Object> guardado = const {},
}) async {
  SharedPreferences.setMockInitialValues(guardado);
  tester.view.physicalSize = const Size(1170, 2532); // teléfono de 390 × 844 a 3x
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.platformBrightnessTestValue = brillo;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final estado = AppEstado(
    await Almacen.abrir(),
    servicioClima: clima ?? ClimaFalso(),
    servicioMapa: MapaFalso(),
    reloj: () => _hoy,
  );
  await tester.pumpWidget(FieldShift(estado: estado));
  await tester.pumpAndSettle();
  return estado;
}

Future<void> _captura(WidgetTester tester, String nombre) =>
    expectLater(find.byType(CupertinoApp), matchesGoldenFile('capturas/$nombre.png'));

/// Toca el lienzo del croquis en las fracciones dadas para marcar esquinas.
Future<void> _marcar(WidgetTester tester, Key lienzo, List<Offset> fracciones) async {
  final caja = tester.getRect(find.byKey(lienzo));
  for (final f in fracciones) {
    await tester.tapAt(caja.topLeft + Offset(f.dx * caja.width, f.dy * caja.height));
    await tester.pump();
  }
}

void main() {
  setUpAll(_cargarFuentes);

  testWidgets('bienvenida en claro y cambio de idioma', (tester) async {
    await _abrir(tester);
    expect(find.text('Empezar'), findsOneWidget);
    await _captura(tester, '01_bienvenida');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(find.text('Get started'), findsOneWidget);
  });

  testWidgets('configuración inicial: parcela y plantación', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    expect(find.text('Tu parcela'), findsWidgets);

    final campos = find.byType(CupertinoTextField);
    await tester.enterText(campos.at(0), 'La Vega');
    await tester.enterText(campos.at(1), '14.8250');
    await tester.enterText(campos.at(2), '-89.5312');
    await tester.pumpAndSettle();
    await _captura(tester, '02_parcela');

    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Contorno de la finca: se dibuja tocando las esquinas.
    expect(find.text('Contorno de la finca'), findsOneWidget);
    await _marcar(tester, const Key('lienzo'), const [
      Offset(0.12, 0.15), Offset(0.78, 0.10), Offset(0.90, 0.85), Offset(0.15, 0.88),
    ]);
    await _captura(tester, '02b_contorno_finca');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(estado.parcela!.contorno.length, 4);

    // Perímetro de la plantación dentro de la finca.
    expect(find.text('Perímetro'), findsOneWidget);
    await _marcar(tester, const Key('lienzo'), const [
      Offset(0.50, 0.50), Offset(0.80, 0.50), Offset(0.80, 0.78), Offset(0.50, 0.78),
    ]);
    await _captura(tester, '02c_perimetro');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Plantación'), findsWidgets);
    await tester.tap(find.text('Frijol'));
    await tester.pumpAndSettle();
    await _captura(tester, '03_plantacion');

    // Caja de plaga: se despliega al activarla.
    expect(find.text('Desde cuándo'), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('plaga')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('plaga')));
    await tester.pumpAndSettle();
    expect(find.text('Desde cuándo'), findsOneWidget);
    await tester.enterText(find.widgetWithText(CupertinoTextField, 'Gusano cogollero'), 'Mosca blanca');
    await tester.tap(find.text('Fuerte'));
    await tester.tap(find.byKey(const Key('plagaTratada')));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(find.text('Plaga reciente')), alignment: 0.04);
    await tester.pumpAndSettle();
    await _captura(tester, '03b_plantacion_plaga');

    // Caja de fertilizante.
    await tester.ensureVisible(find.byKey(const Key('fertilizo')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fertilizo')));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(CupertinoTextField, 'Urea, 15-15-15…'), 'Urea');
    await tester.tap(find.text('Orgánico'));
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(find.text('Ya fertilizaste')), alignment: 0.04);
    await tester.pumpAndSettle();
    await _captura(tester, '03c_plantacion_fertilizante');

    await tester.ensureVisible(find.text('Goteo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goteo'));
    await tester.pumpAndSettle();
    await _captura(tester, '03d_plantacion_riego');

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(estado.configurada, isTrue);
    expect(estado.plantaciones.length, 1);
    expect(estado.plantacion!.contorno.length, 4);
    expect(estado.plantacion!.cultivoId, 'frijol');
    expect(estado.plantacion!.plagaReciente, isTrue);
    expect(estado.plantacion!.notaPlaga, 'Mosca blanca');
    expect(estado.plantacion!.nivelPlaga, NivelPlaga.fuerte);
    expect(estado.plantacion!.plagaTratada, isTrue);
    expect(estado.plantacion!.inicioPlaga, _hoy);
    expect(estado.plantacion!.fertilizo, isTrue);
    expect(estado.plantacion!.tipoFertilizante, TipoFertilizante.organico);
    expect(estado.plantacion!.notaFertilizante, 'Urea');
    expect(estado.plantacion!.fechaFertilizante, _hoy);
    expect(estado.plantacion!.riego, TipoRiego.goteo);
    expect(estado.plantacion!.ciclo, 67);
    expect(estado.parcela!.elevacion, 373); // llegó con la sincronización
    expect(find.text('Hoy'), findsWidgets);
  });

  testWidgets('ejemplo, pantalla de hoy y registro semanal', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    expect(estado.configurada, isTrue);
    expect(estado.clima, isNotEmpty);
    expect(find.text('agua disponible'), findsOneWidget);
    await _captura(tester, '04_hoy');

    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -620));
    await tester.pumpAndSettle();
    await _captura(tester, '05_hoy_abajo');

    await tester.tap(find.text('Registro semanal pendiente'));
    await tester.pumpAndSettle();
    expect(find.text('Veces que regaste'), findsOneWidget);
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    await _captura(tester, '06_registro');

    final antes = estado.registros.length;
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(estado.registros.length, antes + 1);
    expect(estado.registros.first.riegos, 2);
    expect(estado.registros.first.plaga, NivelPlaga.moderada);

    await tester.tap(find.text('Registros'));
    await tester.pumpAndSettle();
    await _captura(tester, '07_registros');

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    await _captura(tester, '08_ajustes');

    // Mapa de la finca: dos plantaciones; al tocar una en el mapa se elige.
    await tester.tap(find.text('Finca'));
    await tester.pumpAndSettle();
    expect(estado.plantaciones.length, 2);
    expect(estado.plantacion!.cultivoId, 'frijol');
    await _captura(tester, '11_finca');
    await _marcar(tester, const Key('lienzo-finca'), const [Offset(0.30, 0.33)]);
    await tester.pumpAndSettle();
    expect(estado.plantacion!.cultivoId, 'maiz');
    expect(estado.registros, isEmpty); // los registros son de cada plantación

    // Ingresar una plantación nueva desde el mapa.
    await tester.scrollUntilVisible(
      find.text('Nueva plantación'),
      200,
      scrollable: find.descendant(of: find.byType(PestanaFinca), matching: find.byType(Scrollable)).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nueva plantación'));
    await tester.pumpAndSettle();
    expect(find.text('Perímetro'), findsOneWidget); // la finca ya tiene contorno
    await _marcar(tester, const Key('lienzo'), const [
      Offset(0.20, 0.58), Offset(0.46, 0.58), Offset(0.46, 0.80), Offset(0.20, 0.80),
    ]);
    await _captura(tester, '12_nueva_plantacion');
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(estado.plantaciones.length, 3);
    expect(estado.plantacion!.cultivoId, 'tomate');
    expect(estado.plantacion!.contorno.length, 4);
    await _captura(tester, '13_finca_tres');

    // Al elegirla en la lista se pasa a Hoy con esa plantación.
    await Scrollable.ensureVisible(tester.element(find.text('Maíz')), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Maíz'));
    await tester.pumpAndSettle();
    expect(estado.plantacion!.cultivoId, 'maiz');
    // Hoy había quedado desplazada hacia abajo en un paso anterior.
    await tester.drag(find.byType(CustomScrollView).first, const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(find.text('agua disponible'), findsOneWidget);
    await _captura(tester, '14_hoy_maiz');
  });

  testWidgets('modo oscuro y cultivo sin estrés', (tester) async {
    final estado = await _abrir(tester, brillo: Brightness.dark, clima: ClimaFalso(lluvioso: true));
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    expect(find.text('Tu cultivo tiene agua'), findsOneWidget);
    expect(estado.recomendacion.riegoSugerido, 0);
    await _captura(tester, '09_hoy_oscuro');
  });

  testWidgets('sin wifi no se descarga el clima y se explica por qué', (tester) async {
    final estado = await _abrir(tester, clima: ClimaFalso(wifi: false));
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    expect(estado.clima, isEmpty);
    expect(find.text('Falta el clima'), findsOneWidget);
    await _captura(tester, '10_sin_clima');

    await tester.tap(find.text('Actualizar clima'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Sin wifi'), findsOneWidget);
  });

  testWidgets('los datos guardados se recuperan al volver a abrir', (tester) async {
    final primero = await _abrir(tester);
    await primero.cargarEjemplo();
    await primero.sincronizar();
    final prefs = await SharedPreferences.getInstance();
    final guardado = {for (final k in prefs.getKeys()) k: prefs.get(k)!};

    final segundo = await _abrir(tester, guardado: guardado, clima: ClimaFalso(wifi: false));
    expect(segundo.configurada, isTrue);
    expect(segundo.parcela!.nombre, 'Chiquimula');
    expect(segundo.plantaciones.length, 2);
    expect(segundo.plantacion!.cultivoId, 'frijol');
    expect(segundo.parcela!.contorno.length, 6);
    expect(segundo.registros.length, 1);
    expect(segundo.clima.length, primero.clima.length);
    expect(find.text('agua disponible'), findsOneWidget);
  });

  testWidgets('los datos de la versión con una sola plantación se conservan', (tester) async {
    final vieja = Plantacion(
      cultivoId: 'maiz',
      fecha: DateTime(2026, 9, 20),
      ciclo: 120,
      suelo: Suelo.franco,
      riego: TipoRiego.goteo,
      temporadaRiego: TemporadaRiego.auxilio,
      plagaReciente: false,
      fertilizo: false,
    ).aJson()
      ..remove('id')
      ..remove('nombre')
      ..remove('contorno');
    final registro = RegistroSemanal(fecha: DateTime(2026, 11, 10), riegos: 1, plaga: NivelPlaga.ninguna, fertilizo: false)
        .aJson()
      ..remove('plantacion');
    final estado = await _abrir(tester, guardado: {
      'parcela': jsonEncode({'nombre': 'La Vega', 'latitud': 14.8, 'longitud': -89.5, 'elevacion': 400}),
      'plantacion': jsonEncode(vieja),
      'registros': jsonEncode([registro]),
    });
    expect(estado.configurada, isTrue);
    expect(estado.plantaciones.length, 1);
    expect(estado.plantacion!.id, isNotEmpty);
    expect(estado.plantacion!.cultivoId, 'maiz');
    expect(estado.registros.length, 1);
    expect(estado.parcela!.contorno, isEmpty);
    expect(find.text('Falta el clima'), findsOneWidget);
  });
}
