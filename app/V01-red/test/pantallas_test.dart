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
  Future<Uint8List?> tesela(CapaMapa capa, int z, int x, int y, {bool guardar = true}) async => null;
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
    expect(estado.parcela!.contorno, isEmpty); // aún no se guarda: falta terminar

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
    expect(estado.parcela!.contorno.length, 4); // el contorno se guardó junto con la plantación
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

  testWidgets('al abandonar la configuración inicial no queda nada dibujado', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    final campos = find.byType(CupertinoTextField);
    await tester.enterText(campos.at(1), '14.8250');
    await tester.enterText(campos.at(2), '-89.5312');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // Dibuja el contorno, cambia el ancho del plano y sigue al perímetro.
    await _marcar(tester, const Key('lienzo'), const [Offset(0.2, 0.2), Offset(0.8, 0.2), Offset(0.5, 0.8)]);
    await tester.tap(find.byIcon(CupertinoIcons.plus)); // agranda el plano
    await tester.pumpAndSettle();
    expect(find.text('50 mz'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Perímetro'), findsOneWidget);
    await _marcar(tester, const Key('lienzo'), const [Offset(0.4, 0.4), Offset(0.6, 0.4), Offset(0.5, 0.6)]);

    // «Atrás» vuelve al contorno con sus tres puntos, sin haber guardado nada.
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    expect(find.text('Contorno de la finca'), findsOneWidget);
    expect(find.textContaining('3 puntos ·'), findsOneWidget);
    expect(estado.parcela!.contorno, isEmpty);
    expect(estado.parcela!.lado, 500);

    // Se sale del todo: ni contorno, ni ancho, ni plantación.
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    expect(find.text('Empezar'), findsOneWidget);
    expect(estado.parcela!.contorno, isEmpty);
    expect(estado.parcela!.lado, 500);
    expect(estado.plantaciones, isEmpty);
    expect(estado.configurada, isFalse);

    // Al volver a entrar se ofrece otra vez dibujar el contorno, vacío.
    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Contorno de la finca'), findsOneWidget);
    expect(find.text('Marca 3 puntos o más'), findsOneWidget);
  });

  testWidgets('cancelar una plantación nueva o un cambio de contorno no altera la finca', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finca'));
    await tester.pumpAndSettle();
    final contorno = estado.parcela!.contorno;
    final perimetros = [for (final p in estado.plantaciones) p.contorno];
    final lista = find.descendant(of: find.byType(PestanaFinca), matching: find.byType(Scrollable)).first;

    // Plantación nueva: se marca el perímetro, se llega al formulario y se abandona.
    await tester.scrollUntilVisible(find.text('Nueva plantación'), 200, scrollable: lista);
    await tester.tap(find.text('Nueva plantación'));
    await tester.pumpAndSettle();
    await _marcar(tester, const Key('lienzo'), const [Offset(0.2, 0.6), Offset(0.4, 0.6), Offset(0.3, 0.8)]);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atrás')); // del formulario al perímetro
    await tester.pumpAndSettle();
    expect(find.textContaining('3 puntos ·'), findsOneWidget); // el trazo sigue ahí para corregirlo
    await tester.tap(find.text('Atrás')); // del perímetro a la finca
    await tester.pumpAndSettle();
    expect(estado.plantaciones.length, 2);

    // Cambio de contorno: se añaden puntos, se cambia el ancho y se sale con «Atrás».
    await tester.scrollUntilVisible(find.text('Cambiar el contorno de la finca'), -200, scrollable: lista);
    await tester.tap(find.text('Cambiar el contorno de la finca'));
    await tester.pumpAndSettle();
    await _marcar(tester, const Key('lienzo'), const [Offset(0.5, 0.5)]);
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.pumpAndSettle();
    expect(find.textContaining('7 puntos ·'), findsOneWidget);
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    expect(estado.parcela!.contorno, same(contorno));
    expect(estado.parcela!.lado, 500);
    expect([for (final p in estado.plantaciones) p.contorno], perimetros);

    // El mismo cambio, confirmado con «Continuar», sí se guarda y conserva las áreas.
    final areaAntes = areaDe(estado.plantaciones.first.contorno, 500);
    await tester.tap(find.text('Cambiar el contorno de la finca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(estado.parcela!.lado, ladosDe(Unidad.manzanas)[1]); // de 500 m al plano de 50 mz
    expect(estado.parcela!.contorno.length, 6);
    expect(areaDe(estado.plantaciones.first.contorno, estado.parcela!.lado), closeTo(areaAntes, 1e-6));
  });

  testWidgets('finca sin contorno: abandonar una plantación nueva no guarda el contorno', (tester) async {
    final vieja = Plantacion(
      cultivoId: 'maiz',
      fecha: DateTime(2026, 9, 20),
      ciclo: 120,
      suelo: Suelo.franco,
      riego: TipoRiego.goteo,
      temporadaRiego: TemporadaRiego.auxilio,
      plagaReciente: false,
      fertilizo: false,
    ).aJson();
    final estado = await _abrir(tester, guardado: {
      'parcela': jsonEncode({'nombre': 'La Vega', 'latitud': 14.8, 'longitud': -89.5}),
      'plantaciones': jsonEncode([vieja]),
    });
    await tester.tap(find.text('Finca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('Contorno de la finca'), findsOneWidget);
    await _marcar(tester, const Key('lienzo'), const [Offset(0.2, 0.2), Offset(0.8, 0.2), Offset(0.5, 0.8)]);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Perímetro'), findsOneWidget);
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    expect(estado.parcela!.contorno, isEmpty);
    expect(estado.plantaciones.length, 1);

    // Omitiendo el contorno y guardando, la plantación entra y la finca sigue sin contorno.
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Omitir'));
    await tester.pumpAndSettle();
    await _marcar(tester, const Key('lienzo'), const [Offset(0.4, 0.4), Offset(0.6, 0.4), Offset(0.5, 0.6)]);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(estado.plantaciones.length, 2);
    expect(estado.parcela!.contorno, isEmpty);
    expect(estado.plantacion!.contorno.length, 3);
    expect(find.text('Finca'), findsWidgets); // volvió a la pestaña, no quedó en el flujo
  });

  testWidgets('el registro semanal se guarda en la plantación que se elige', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    final maiz = estado.plantaciones.firstWhere((p) => p.cultivoId == 'maiz');
    final frijol = estado.plantaciones.firstWhere((p) => p.cultivoId == 'frijol');
    expect(estado.plantacion!.id, frijol.id);

    await tester.tap(find.text('Registros'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('¿PARA CUÁL PLANTACIÓN?'), findsOneWidget); // los rótulos van en mayúsculas
    expect(find.text('Veces que regaste'), findsOneWidget); // el frijol tiene goteo

    // Se cambia al maíz, que no tiene riego: desaparece la pregunta de riegos.
    await tester.tap(find.byKey(Key('registro-${maiz.id}')));
    await tester.pumpAndSettle();
    expect(find.text('Veces que regaste'), findsNothing);
    await tester.ensureVisible(find.text('Fuerte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fuerte'));
    await tester.pumpAndSettle();
    await _captura(tester, '06b_registro_plantacion');
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(estado.registrosDe(maiz.id).single.plaga, NivelPlaga.fuerte);
    expect(estado.registrosDe(frijol.id).length, 1); // el del frijol no cambió
    expect(estado.plantacion!.id, maiz.id); // se queda viendo la plantación registrada
  });

  testWidgets('unidades: manzanas por omisión y métrico al cambiar en Ajustes', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    expect(estado.unidad, Unidad.manzanas);
    await tester.tap(find.text('Finca'));
    await tester.pumpAndSettle();
    expect(find.textContaining(' mz'), findsWidgets);
    expect(find.textContaining(' ha'), findsNothing);

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hectáreas y km'));
    await tester.pumpAndSettle();
    expect(estado.unidad, Unidad.metrico);
    await tester.tap(find.text('Finca'));
    await tester.pumpAndSettle();
    expect(find.textContaining(' ha'), findsWidgets);
    expect(find.textContaining(' mz'), findsNothing);

    // En métrico el plano se agranda por anchos: de 500 m a 1 km y hasta 10 km.
    await tester.tap(find.text('Cambiar el contorno de la finca'));
    await tester.pumpAndSettle();
    expect(find.text('500 m'), findsOneWidget);
    for (final esperado in ['1 km', '2 km', '5 km', '10 km']) {
      await tester.tap(find.byIcon(CupertinoIcons.plus));
      await tester.pumpAndSettle();
      expect(find.text(esperado), findsOneWidget);
    }
    await _captura(tester, '15_contorno_10km');
    await tester.tap(find.text('Atrás'));
    await tester.pumpAndSettle();
    expect(estado.parcela!.lado, 500); // se salió sin continuar: no cambia
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

  // La tarjeta «Próximos 7 días» sale de la red del equipo y solo se muestra donde
  // la red se midió: maíz, frijol o tomate a secano, entre el 20 % y el 80 % del
  // ciclo y con clima reciente.
  Finder listaHoy() => find.descendant(of: find.byType(PestanaHoy), matching: find.byType(Scrollable)).first;

  Future<AppEstado> abrirConPlantacion(
    WidgetTester tester, {
    required String cultivo,
    required int dias,
    TipoRiego riego = TipoRiego.ninguno,
    int ciclo = 120,
    Brightness brillo = Brightness.light,
  }) async {
    final siembra = DateTime(_hoy.year, _hoy.month, _hoy.day - dias);
    final plantacion = Plantacion(
      id: 'p1',
      cultivoId: cultivo,
      fecha: siembra,
      ciclo: ciclo,
      suelo: Suelo.franco,
      riego: riego,
      temporadaRiego: TemporadaRiego.auxilio,
      plagaReciente: false,
      fertilizo: true,
    );
    final estado = await _abrir(tester, brillo: brillo, guardado: {
      'parcela': jsonEncode({'nombre': 'Chiquimula', 'latitud': 14.825, 'longitud': -89.5312, 'elevacion': 373}),
      'plantaciones': jsonEncode([plantacion.aJson()]),
    });
    await estado.sincronizar();
    await tester.pumpAndSettle();
    return estado;
  }

  testWidgets('Próximos 7 días: aparece donde la red se midió y desaparece donde no', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    // Queda seleccionado el frijol, que tiene riego por goteo: la red no se midió así.
    expect(estado.plantacion!.cultivoId, 'frijol');
    expect(estado.recomendacion.desdeRed, isFalse);
    expect(estado.recomendacion.estresProx7, isNull);
    expect(find.text('Próximos 7 días'), findsNothing);

    // El maíz del ejemplo es de secano y va por el 46 % del ciclo.
    await estado.seleccionar(estado.plantaciones.firstWhere((p) => p.cultivoId == 'maiz').id);
    await tester.pumpAndSettle();
    expect(estado.recomendacion.desdeRed, isTrue);
    await tester.scrollUntilVisible(find.text('Próximos 7 días'), 200, scrollable: listaHoy());
    expect(find.text('Próximos 7 días'), findsOneWidget);
    final habraEstres = estado.recomendacion.estresProx7! >= 0.5;
    expect(find.text('Se espera estrés por falta de agua en la próxima semana'), habraEstres ? findsOneWidget : findsNothing);
    expect(find.text('No se espera estrés por falta de agua en la próxima semana'), habraEstres ? findsNothing : findsOneWidget);
    expect(find.textContaining('En 14 días'), findsOneWidget);
    expect(find.textContaining('No es un pronóstico del tiempo'), findsOneWidget);
    expect(find.textContaining('Rendimiento esperado'), findsNothing); // el maíz no muestra el factor final

    await estado.cambiarIdioma('en');
    await tester.pumpAndSettle();
    expect(find.text('Next 7 days'), findsOneWidget);
    expect(find.textContaining('not a weather forecast'), findsOneWidget);
    await estado.cambiarIdioma('es');
    await tester.pumpAndSettle();

    // Con riego anotado en un registro semanal, la tarjeta desaparece.
    await estado.guardarRegistro(RegistroSemanal(
      plantacionId: estado.plantacion!.id,
      fecha: DateTime(_hoy.year, _hoy.month, _hoy.day - 2),
      riegos: 1,
      plaga: NivelPlaga.ninguna,
      fertilizo: false,
    ));
    await tester.pumpAndSettle();
    expect(estado.recomendacion.desdeRed, isFalse);
    expect(find.text('Próximos 7 días'), findsNothing);
  });

  testWidgets('Próximos 7 días: el factor final solo se muestra en tomate', (tester) async {
    final estado = await abrirConPlantacion(tester, cultivo: 'tomate', dias: 60);
    expect(estado.recomendacion.desdeRed, isTrue);
    await tester.scrollUntilVisible(find.text('Próximos 7 días'), 200, scrollable: listaHoy());
    expect(find.textContaining('Rendimiento esperado al final del ciclo'), findsOneWidget);
  });

  testWidgets('Próximos 7 días: no aparece con clima viejo, fuera del 20 al 80 % ni con café', (tester) async {
    final estado = await abrirConPlantacion(tester, cultivo: 'frijol', dias: 30, ciclo: 80);
    expect(estado.recomendacion.desdeRed, isTrue);
    await tester.scrollUntilVisible(find.text('Próximos 7 días'), 200, scrollable: listaHoy());

    // Clima viejo: el último dato es de hace 12 días.
    estado.clima = [for (final d in estado.clima) if (d.fecha.isBefore(DateTime(_hoy.year, _hoy.month, _hoy.day - 11))) d];
    await estado.cambiarIdioma('es'); // fuerza el recálculo
    await tester.pumpAndSettle();
    expect(estado.recomendacion.desdeRed, isFalse);
    expect(find.text('Próximos 7 días'), findsNothing);
  });

  testWidgets('Próximos 7 días: sin tarjeta al 10 % del ciclo, al 90 % y con café', (tester) async {
    for (final caso in [('maiz', 12), ('maiz', 108), ('cafe', 60)]) {
      final estado = await abrirConPlantacion(tester, cultivo: caso.$1, dias: caso.$2, ciclo: caso.$1 == 'cafe' ? 365 : 120);
      expect(estado.recomendacion.desdeRed, isFalse, reason: '${caso.$1} ${caso.$2}');
      expect(find.text('Próximos 7 días'), findsNothing, reason: '${caso.$1} ${caso.$2}');
    }
  });

  testWidgets('Próximos 7 días en claro y en oscuro', (tester) async {
    for (final oscuro in [false, true]) {
      final estado = await abrirConPlantacion(
        tester,
        cultivo: 'tomate',
        dias: 60,
        brillo: oscuro ? Brightness.dark : Brightness.light,
      );
      expect(estado.recomendacion.desdeRed, isTrue);
      await tester.scrollUntilVisible(find.text('Próximos 7 días'), 200, scrollable: listaHoy());
      await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -150));
      await tester.pumpAndSettle();
      await _captura(tester, oscuro ? '17_proximos_7_dias_oscuro' : '16_proximos_7_dias');
    }
  });
}
