// Pruebas de las pantallas. Además de comprobar los flujos, guardan una imagen
// de cada pantalla en test/capturas/ para revisar el diseño:
//
//   flutter test test/pantallas_test.dart --update-goldens
import 'dart:io';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/datos/clima.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/main.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/ui/plagas.dart';
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
  final estado = AppEstado(await Almacen.abrir(), servicioClima: clima ?? ClimaFalso(), reloj: () => _hoy);
  await tester.pumpWidget(FieldShift(estado: estado));
  await tester.pumpAndSettle();
  return estado;
}

Future<void> _captura(WidgetTester tester, String nombre) =>
    expectLater(find.byType(CupertinoApp), matchesGoldenFile('capturas/$nombre.png'));

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
    expect(find.text('Plantación'), findsWidgets);
    await tester.tap(find.text('Frijol'));
    await tester.pumpAndSettle();
    await _captura(tester, '03_plantacion');
    await tester.scrollUntilVisible(find.text('Goteo'), 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Goteo'));
    await tester.pumpAndSettle();
    await _captura(tester, '03b_plantacion_riego');

    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(estado.configurada, isTrue);
    expect(estado.plantacion!.cultivoId, 'frijol');
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
  });

  testWidgets('café: el tipo de plaga se elige, se guarda y se ve en la lista de registros', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    await estado.guardarPlantacion(Plantacion(
      cultivoId: 'cafe', fecha: DateTime(2026, 5, 1), ciclo: 365, suelo: Suelo.franco,
      riego: TipoRiego.ninguno, temporadaRiego: TemporadaRiego.auxilio, plagaReciente: false, fertilizo: false,
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Registros'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('Roya'), findsNothing); // sin plaga no se pregunta el tipo
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    expect(find.text('Roya'), findsOneWidget);
    expect(find.text('Minador'), findsOneWidget);
    expect(find.text('Antracnosis'), findsOneWidget);
    expect(find.text('Otra'), findsOneWidget);
    await tester.tap(find.text('Roya'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();

    expect(estado.registros.first.tipoPlaga, 'roya');
    expect(find.textContaining('(roya)'), findsOneWidget);
  });

  testWidgets('frijol: elegir una plaga con fuente, guardarla y abrir su detalle desde el registro', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registros'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    expect(find.text('Trips de las flores'), findsNothing); // sin plaga no se pregunta el tipo
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    expect(find.text('Trips de las flores'), findsOneWidget);
    expect(find.text('Mosca minadora'), findsOneWidget);
    expect(find.text('Otra'), findsOneWidget);
    expect(find.textContaining('no significa que la plaga esté presente en esta parcela'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    await _captura(tester, '11_plagas_selector');
    await tester.tap(find.text('Trips de las flores'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(estado.registros.first.tipoPlaga, 'trips-de-las-flores');
    expect(find.textContaining('(trips de las flores)'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.info_circle));
    await tester.pumpAndSettle();
    expect(find.text('Megalurothrips usitatus'), findsOneWidget);
    expect(find.text('Flores y vainas'), findsOneWidget);
    expect(find.textContaining('Petén, El Progreso, Zacapa y Chimaltenango'), findsOneWidget);
    expect(find.text('2022'), findsOneWidget);
    expect(find.textContaining('ICTA · Una nueva plaga en el cultivo de frijol'), findsOneWidget);
    expect(find.text('https://icta.gob.gt/plagacultivofrijolGuatemala.html'), findsOneWidget);
    expect(find.textContaining('No se extrapolan sus porcentajes de daño'), findsOneWidget);
    expect(find.textContaining('no significa que la plaga esté presente en esta parcela'), findsOneWidget);
    await _captura(tester, '12_plaga_detalle');
  });

  testWidgets('brócoli en inglés y modo oscuro: selector con nombres largos y detalle sin desbordes', (tester) async {
    final estado = await _abrir(tester, brillo: Brightness.dark);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    await estado.guardarPlantacion(Plantacion(
      cultivoId: 'brocoli', fecha: DateTime(2026, 9, 20), ciclo: 135, suelo: Suelo.franco,
      riego: TipoRiego.goteo, temporadaRiego: TemporadaRiego.todoElAnio, plagaReciente: false, fertilizo: false,
    ));
    await estado.cambiarIdioma('en');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Logs'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();
    expect(find.text('Diamondback moth'), findsOneWidget);
    expect(find.text('White grub'), findsOneWidget);
    expect(find.text('Leaf miner fly'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -260));
    await tester.pumpAndSettle();
    await _captura(tester, '11b_plagas_selector_oscuro');
    await tester.tap(find.byIcon(CupertinoIcons.info_circle).first);
    await tester.pumpAndSettle();
    expect(find.text('Plutella xylostella'), findsOneWidget);
    expect(find.text('Leaves and inflorescence'), findsOneWidget);
    expect(find.textContaining('A documented record in Guatemala does not mean'), findsOneWidget);
    await _captura(tester, '12b_plaga_detalle_oscuro');
  });

  testWidgets('ajonjolí: sin registro confirmado solo se ofrece Otra y se dice por qué', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    await estado.guardarPlantacion(Plantacion(
      cultivoId: 'ajonjoli', fecha: DateTime(2026, 9, 20), ciclo: 110, suelo: Suelo.franco,
      riego: TipoRiego.ninguno, temporadaRiego: TemporadaRiego.auxilio, plagaReciente: false, fertilizo: false,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registros'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    expect(find.text('Otra'), findsOneWidget);
    // una sola fila (Otra) y sin botón de detalle
    expect(find.descendant(of: find.byType(ListaPlagas), matching: find.byType(CupertinoButton)), findsOneWidget);
    expect(find.textContaining('aún no tiene un registro local confirmado'), findsOneWidget);
    expect(find.textContaining('no significa que la plaga esté presente'), findsNothing);
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(estado.registros.first.tipoPlaga, 'otra');
  });

  testWidgets('café: el detalle dice que lo reportó un caficultor y no es un registro con fuente', (tester) async {
    final estado = await _abrir(tester);
    await tester.tap(find.text('Ver un ejemplo'));
    await tester.pumpAndSettle();
    await estado.guardarPlantacion(Plantacion(
      cultivoId: 'cafe', fecha: DateTime(2026, 5, 1), ciclo: 365, suelo: Suelo.franco,
      riego: TipoRiego.ninguno, temporadaRiego: TemporadaRiego.auxilio, plagaReciente: false, fertilizo: false,
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Registros'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.add));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Media'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(CupertinoIcons.info_circle).first);
    await tester.pumpAndSettle();
    expect(find.text('Roya'), findsOneWidget);
    expect(find.textContaining('Reportado por un caficultor'), findsWidgets);
    expect(find.textContaining('No es un registro con fuente'), findsOneWidget);
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
    expect(segundo.registros.length, 1);
    expect(segundo.clima.length, primero.clima.length);
    expect(find.text('agua disponible'), findsOneWidget);
  });
}
