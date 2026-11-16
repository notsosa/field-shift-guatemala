// Pruebas de los componentes emergentes. Guardan capturas en
// test/capturas/emergentes/:
//
//   flutter test test/emergentes_test.dart --update-goldens
import 'dart:io';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/ui/emergentes.dart';
import 'package:field_shift/ui/tema.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _hoy = DateTime(2026, 11, 14);

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

/// Resultados de la última interacción con la pantalla de muestra.
class _Res {
  Object? opcion = 'sin tocar';
  Object? confirmar = 'sin tocar';
  Object? fecha = 'sin tocar';
  bool avisoCerrado = false;
  bool interruptor = true;
  DateTime inicial = DateTime(2026, 11, 10);
  DateTime minimo = DateTime(2026, 9, 20);
  DateTime maximo = _hoy;
}

class _Muestra extends StatefulWidget {
  const _Muestra(this.res);
  final _Res res;
  @override
  State<_Muestra> createState() => _EstadoMuestra();
}

class _EstadoMuestra extends State<_Muestra> {
  _Res get r => widget.res;

  Widget _b(String t, VoidCallback f) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: CupertinoButton.filled(onPressed: f, child: Text(t)),
  );

  @override
  Widget build(BuildContext context) => CupertinoPageScaffold(
    child: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _b('abrir opciones', () async {
            final v = await elegirOpcion<String>(
              context,
              titulo: '¿Qué plantación?',
              ayuda: 'Solo las que tienen riego.',
              seleccionada: 'b',
              opciones: const [
                OpcionHoja(
                  valor: 'a',
                  texto: 'Maíz · 3 may',
                  detalle: 'Lote 1',
                  icono: CupertinoIcons.leaf_arrow_circlepath,
                ),
                OpcionHoja(
                  valor: 'b',
                  texto: 'Frijol · 20 jun',
                  detalle: 'Lote 2',
                  icono: CupertinoIcons.drop,
                ),
                OpcionHoja(valor: 'c', texto: 'Tomate · 2 ago'),
                OpcionHoja(
                  valor: 'x',
                  texto: 'Borrar plantación',
                  icono: CupertinoIcons.trash,
                  destructiva: true,
                ),
              ],
            );
            setState(() => r.opcion = v);
          }),
          _b('abrir confirmar', () async {
            final v = await confirmarAccion(
              context,
              titulo: '¿Borrar esta plantación?',
              mensaje: 'Se perderán sus riegos y notas. No se puede deshacer.',
              accion: 'Borrar',
              destructiva: true,
            );
            setState(() => r.confirmar = v);
          }),
          _b('abrir aviso', () async {
            await mostrarAviso(
              context,
              titulo: 'Sin wifi',
              mensaje: 'El clima no se actualizó. Se usarán los últimos datos.',
              icono: CupertinoIcons.wifi_slash,
            );
            setState(() => r.avisoCerrado = true);
          }),
          _b('abrir fecha', () async {
            final v = await elegirFecha(
              context,
              inicial: r.inicial,
              minimo: r.minimo,
              maximo: r.maximo,
              titulo: 'Fecha de siembra',
            );
            setState(() => r.fecha = v);
          }),
          Interruptor(
            valor: r.interruptor,
            alCambiar: (v) => setState(() => r.interruptor = v),
            etiqueta: 'Riego automático',
          ),
        ],
      ),
    ),
  );
}

Future<_Res> _abrir(
  WidgetTester tester, {
  Brightness brillo = Brightness.light,
  double escala = 1,
  Size tamano = const Size(390, 844),
  bool ingles = false,
  _Res? res,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = tamano * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.platformBrightnessTestValue = brillo;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
  final estado = AppEstado(await Almacen.abrir(), reloj: () => _hoy);
  await estado.preparada;
  if (ingles) estado.idioma = 'en';
  final r = res ?? _Res();
  await tester.pumpWidget(
    Alcance(
      estado: estado,
      child: CupertinoApp(
        debugShowCheckedModeBanner: false,
        theme: temaApp(null),
        builder: (c, hijo) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: TextScaler.linear(escala)),
          child: hijo!,
        ),
        home: _Muestra(r),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return r;
}

Future<void> _toca(WidgetTester t, String texto) async {
  await t.tap(find.text(texto).hitTestable().last);
  await t.pumpAndSettle();
}

Future<void> _afuera(WidgetTester t) async {
  await t.tapAt(const Offset(195, 20));
  await t.pumpAndSettle();
}

Future<void> _captura(WidgetTester t, String nombre) => expectLater(
  find.byType(CupertinoApp),
  matchesGoldenFile('capturas/emergentes/$nombre.png'),
);

Finder _dia(int n) => find.text('$n');

void main() {
  setUpAll(_cargarFuentes);

  group('hoja de opciones', () {
    testWidgets('devuelve el valor elegido', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir opciones');
      await _toca(t, 'Tomate · 2 ago');
      expect(r.opcion, 'c');
      expect(find.text('¿Qué plantación?'), findsNothing);
    });

    testWidgets('la opción destructiva también devuelve su valor', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir opciones');
      await _toca(t, 'Borrar plantación');
      expect(r.opcion, 'x');
    });

    testWidgets('cancelar devuelve null', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir opciones');
      await _toca(t, 'Cancelar');
      expect(r.opcion, isNull);
    });

    testWidgets('tocar fuera devuelve null', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir opciones');
      await _afuera(t);
      expect(r.opcion, isNull);
      expect(find.text('¿Qué plantación?'), findsNothing);
    });

    testWidgets('marca la seleccionada en la semántica', (t) async {
      final h = t.ensureSemantics();
      await _abrir(t);
      await _toca(t, 'abrir opciones');
      expect(
        t.getSemantics(find.bySemanticsLabel('Frijol · 20 jun. Lote 2')),
        isSemantics(isSelected: true, isButton: true),
      );
      h.dispose();
    });
  });

  group('confirmación y aviso', () {
    testWidgets('confirmar devuelve true', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir confirmar');
      await _toca(t, 'Borrar');
      expect(r.confirmar, true);
    });

    testWidgets('cancelar devuelve false', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir confirmar');
      await _toca(t, 'Cancelar');
      expect(r.confirmar, false);
    });

    testWidgets('tocar fuera devuelve false', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir confirmar');
      await _afuera(t);
      expect(r.confirmar, false);
    });

    testWidgets('los botones van apilados, no lado a lado', (t) async {
      await _abrir(t);
      await _toca(t, 'abrir confirmar');
      final a = t.getRect(find.text('Borrar').last);
      final c = t.getRect(find.text('Cancelar'));
      expect(c.top, greaterThan(a.bottom));
      expect(
        t
            .getSize(
              find
                  .ancestor(
                    of: find.text('Borrar'),
                    matching: find.byType(AnimatedContainer),
                  )
                  .first,
            )
            .height,
        greaterThanOrEqualTo(56),
      );
    });

    testWidgets('el aviso se cierra con su botón y con un toque fuera', (
      t,
    ) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir aviso');
      expect(find.text('Sin wifi'), findsOneWidget);
      await _toca(t, 'Entendido');
      expect(find.text('Sin wifi'), findsNothing);
      expect(r.avisoCerrado, isTrue);
      r.avisoCerrado = false;
      await _toca(t, 'abrir aviso');
      await _afuera(t);
      expect(find.text('Sin wifi'), findsNothing);
      expect(r.avisoCerrado, isTrue);
    });

    testWidgets('textos por omisión en inglés', (t) async {
      await _abrir(t, ingles: true);
      await _toca(t, 'abrir aviso');
      expect(find.text('Got it'), findsOneWidget);
    });
  });

  group('selector de fecha', () {
    testWidgets('elegir un día y pulsar Listo devuelve esa fecha', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir fecha');
      await t.tap(_dia(5));
      await t.pumpAndSettle();
      await _toca(t, 'Listo');
      expect(r.fecha, DateTime(2026, 11, 5));
    });

    testWidgets('sin tocar nada, Listo devuelve la inicial', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir fecha');
      await _toca(t, 'Listo');
      expect(r.fecha, DateTime(2026, 11, 10));
    });

    testWidgets('cancelar y tocar fuera devuelven null', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir fecha');
      await _toca(t, 'Cancelar');
      expect(r.fecha, isNull);
      r.fecha = 'sin tocar';
      await _toca(t, 'abrir fecha');
      await _afuera(t);
      expect(r.fecha, isNull);
    });

    testWidgets('los días fuera del rango no se pueden elegir', (t) async {
      final h = t.ensureSemantics();
      final r = await _abrir(t);
      await _toca(t, 'abrir fecha');
      // 20 nov está después del máximo (14 nov).
      await t.tap(_dia(20), warnIfMissed: false);
      await t.pumpAndSettle();
      // Y el día queda anunciado como no disponible.
      expect(
        find.bySemanticsLabel(RegExp('20 nov 2026.*no disponible')),
        findsOneWidget,
      );
      await _toca(t, 'Listo');
      expect(r.fecha, DateTime(2026, 11, 10));
      h.dispose();
    });

    testWidgets('las flechas se limitan al rango', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir fecha');
      expect(find.text('Noviembre 2026'), findsOneWidget);
      // No hay mes siguiente (el máximo es noviembre).
      await t.tap(
        find.byIcon(CupertinoIcons.chevron_right),
        warnIfMissed: false,
      );
      await t.pumpAndSettle();
      expect(find.text('Noviembre 2026'), findsOneWidget);
      await t.tap(find.byIcon(CupertinoIcons.chevron_left));
      await t.pumpAndSettle();
      expect(find.text('Octubre 2026'), findsOneWidget);
      await t.tap(find.byIcon(CupertinoIcons.chevron_left));
      await t.pumpAndSettle();
      expect(find.text('Septiembre 2026'), findsOneWidget);
      // Septiembre es el primer mes del rango.
      await t.tap(
        find.byIcon(CupertinoIcons.chevron_left),
        warnIfMissed: false,
      );
      await t.pumpAndSettle();
      expect(find.text('Septiembre 2026'), findsOneWidget);
      // Los días de septiembre anteriores al mínimo están desactivados.
      await t.tap(_dia(10), warnIfMissed: false);
      await t.pumpAndSettle();
      await _toca(t, 'Listo');
      expect(r.fecha, DateTime(2026, 11, 10)); // el 10 de sep. no cuenta
    });

    testWidgets('Hoy, Ayer y Hace una semana eligen su día', (t) async {
      final r = await _abrir(t);
      await _toca(t, 'abrir fecha');
      await _toca(t, 'Hoy');
      await _toca(t, 'Listo');
      expect(r.fecha, DateTime(2026, 11, 14));
      await _toca(t, 'abrir fecha');
      await _toca(t, 'Ayer');
      await _toca(t, 'Listo');
      expect(r.fecha, DateTime(2026, 11, 13));
      await _toca(t, 'abrir fecha');
      await _toca(t, 'Hace una semana');
      await _toca(t, 'Listo');
      expect(r.fecha, DateTime(2026, 11, 7));
    });

    testWidgets('los accesos rápidos fuera del rango no aparecen', (t) async {
      final r = await _abrir(t);
      r.minimo = DateTime(2026, 11, 14);
      r.inicial = DateTime(2026, 11, 14);
      await _toca(t, 'abrir fecha');
      expect(find.text('Hoy'), findsOneWidget);
      expect(find.text('Ayer'), findsNothing);
      expect(find.text('Hace una semana'), findsNothing);
    });

    testWidgets('una inicial fuera de rango no se recorta en silencio', (
      t,
    ) async {
      final r = await _abrir(t);
      r.inicial = DateTime(2026, 12, 3);
      await _toca(t, 'abrir fecha');
      // Se muestra su mes, con un aviso.
      expect(find.text('Diciembre 2026'), findsOneWidget);
      expect(find.textContaining('fuera del rango permitido'), findsOneWidget);
      // «Listo» no hace nada hasta elegir otra fecha.
      await t.tap(find.text('Listo'));
      await t.pumpAndSettle();
      expect(find.text('Diciembre 2026'), findsOneWidget);
      expect(r.fecha, 'sin tocar');
      // Se puede volver al rango y elegir.
      await _toca(t, 'Hoy');
      await _toca(t, 'Listo');
      expect(r.fecha, DateTime(2026, 11, 14));
    });

    testWidgets('en inglés: meses, lunes primero y textos', (t) async {
      await _abrir(t, ingles: true);
      await _toca(t, 'abrir fecha');
      expect(find.text('November 2026'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      // 1 nov 2026 es domingo: la primera fila lleva seis huecos.
      final lunes = t.getTopLeft(find.text('M').first).dx;
      final uno = t.getTopLeft(find.text('1').first).dx;
      final domingo = t.getTopLeft(find.text('S').last).dx;
      expect(lunes, lessThan(domingo));
      expect((uno - domingo).abs(), lessThan(20));
    });
  });

  group('interruptor', () {
    testWidgets('muestra Sí y No y cambia al tocar', (t) async {
      final r = await _abrir(t);
      expect(find.text('Sí'), findsOneWidget);
      expect(find.text('No'), findsOneWidget);
      await t.tap(find.text('No'));
      await t.pumpAndSettle();
      expect(r.interruptor, isFalse);
      await t.tap(find.text('Sí'));
      await t.pumpAndSettle();
      expect(r.interruptor, isTrue);
    });

    testWidgets('es un control de dos estados para lectores de pantalla', (
      t,
    ) async {
      final h = t.ensureSemantics();
      await _abrir(t);
      expect(
        t.getSemantics(find.bySemanticsLabel('Riego automático')),
        isSemantics(hasToggledState: true, isToggled: true),
      );
      h.dispose();
    });

    testWidgets(
      'tocar la opción ya activa es idempotente; tocar el centro alterna',
      (t) async {
        final r = await _abrir(t);
        expect(r.interruptor, isTrue);
        await t.tap(find.text('Sí'));
        await t.pumpAndSettle();
        expect(r.interruptor, isTrue);
        await t.tap(find.byType(Interruptor));
        await t.pumpAndSettle();
        expect(r.interruptor, isFalse);
        await t.tap(find.text('No'));
        await t.pumpAndSettle();
        expect(r.interruptor, isFalse);
      },
    );
  });

  group('capturas', () {
    for (final oscuro in [false, true]) {
      for (final escala in [1.0, 2.0]) {
        final sufijo = '${oscuro ? 'oscuro' : 'claro'}_x${escala.toInt()}';
        final brillo = oscuro ? Brightness.dark : Brightness.light;

        testWidgets('muestra $sufijo', (t) async {
          await _abrir(t, brillo: brillo, escala: escala);
          await _captura(t, '00_muestra_$sufijo');
          expect(t.takeException(), isNull);
        });

        testWidgets('opciones $sufijo', (t) async {
          await _abrir(t, brillo: brillo, escala: escala);
          await _toca(t, 'abrir opciones');
          await _captura(t, '01_opciones_$sufijo');
          expect(t.takeException(), isNull);
        });

        testWidgets('confirmación $sufijo', (t) async {
          await _abrir(t, brillo: brillo, escala: escala);
          await _toca(t, 'abrir confirmar');
          await _captura(t, '02_confirmar_$sufijo');
          expect(t.takeException(), isNull);
        });

        testWidgets('aviso $sufijo', (t) async {
          await _abrir(t, brillo: brillo, escala: escala);
          await _toca(t, 'abrir aviso');
          await _captura(t, '03_aviso_$sufijo');
          expect(t.takeException(), isNull);
        });

        testWidgets('fecha $sufijo', (t) async {
          await _abrir(t, brillo: brillo, escala: escala);
          await _toca(t, 'abrir fecha');
          await _captura(t, '04_fecha_$sufijo');
          expect(t.takeException(), isNull);
        });

        testWidgets('fecha fuera de rango $sufijo', (t) async {
          final r = await _abrir(t, brillo: brillo, escala: escala);
          r.inicial = DateTime(2026, 12, 3);
          await _toca(t, 'abrir fecha');
          await _captura(t, '05_fecha_fuera_$sufijo');
          expect(t.takeException(), isNull);
        });
      }
    }

    testWidgets('horizontal con letra 2.0', (t) async {
      const h = Size(844, 390);
      await _abrir(t, escala: 2, tamano: h);
      for (final (boton, nombre) in [
        ('abrir opciones', '06_horizontal_opciones'),
        ('abrir confirmar', '06_horizontal_confirmar'),
        ('abrir aviso', '06_horizontal_aviso'),
        ('abrir fecha', '06_horizontal_fecha'),
      ]) {
        await t.dragUntilVisible(
          find.text(boton),
          find.byType(ListView),
          const Offset(0, -80),
        );
        await _toca(t, boton);
        await _captura(t, nombre);
        expect(t.takeException(), isNull);
        await t.tapAt(const Offset(10, 10));
        await t.pumpAndSettle();
      }
    });
  });
}
