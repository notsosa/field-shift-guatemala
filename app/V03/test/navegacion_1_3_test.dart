// Pruebas de la navegación simplificada (Finca, ficha, Hoy, Registrar
// actividad, mapa y Ajustes). No comparan capturas.
import 'dart:io';
import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/datos/clima.dart';
import 'package:field_shift/datos/mapa.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/eventos.dart';
import 'package:field_shift/main.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/motor/recomendador.dart';
import 'package:field_shift/ui/finca.dart';
import 'package:field_shift/ui/flujo.dart';
import 'package:field_shift/ui/hoy.dart';
import 'package:field_shift/ui/registro.dart';
import 'package:field_shift/ui/tema.dart';
import 'package:field_shift/ui/topo3d_view.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _hoy = DateTime(2026, 11, 14);

/// Clima de mentira que cuenta las descargas.
class ClimaFalso extends ServicioClima {
  ClimaFalso({this.wifi = true});

  final bool wifi;
  int descargas = 0;

  @override
  Future<bool> hayWifi() async => wifi;

  @override
  Future<ClimaDescargado> descargar({
    required double latitud,
    required double longitud,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    descargas++;
    final dias = <DiaClima>[];
    final n = hasta.difference(desde).inDays - 3;
    for (var i = 0; i < n; i++) {
      final f = DateTime(desde.year, desde.month, desde.day + i);
      dias.add(
        DiaClima(
          fecha: f,
          tmax: 31 + 2 * math.sin(i / 5),
          tmin: 20 + math.cos(i / 7),
          humedad: 62,
          viento: 2.1,
          radiacion: 21,
          lluvia: i % 9 == 0 && i < n - 16 ? 14 : 0,
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
  ClimaFalso? clima,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = tamano * 3;
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = escala;
  tester.platformDispatcher.accessibilityFeaturesTestValue =
      const FakeAccessibilityFeatures(
        disableAnimations: true,
        reduceMotion: true,
      );
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
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

Future<AppEstado> _ejemplo(
  WidgetTester t, {
  ClimaFalso? clima,
  Size tamano = const Size(390, 844),
  double escala = 1,
}) async {
  final e = await _abrir(t, clima: clima, tamano: tamano, escala: escala);
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

  testWidgets('1. Finca: cada fila muestra punto de color, agua y etapa', (
    t,
  ) async {
    final e = await _ejemplo(t);
    await _tab(t, 'Finca');
    for (final p in e.plantaciones) {
      final r = e.recomendacionDe(p);
      expect(r.nivel, isNot(NivelAgua.sinDatos));
      final fila = find.byKey(Key('finca-lote-${p.loteId}'));
      await _visible(t, fila);
      final punto = find.descendant(
        of: fila,
        matching: find.byIcon(CupertinoIcons.circle_fill),
      );
      expect(punto, findsOneWidget);
      expect(
        t.widget<Icon>(punto).color,
        PestanaHoy.colorNivel(t.element(fila), r.nivel),
      );
      expect(
        find.descendant(
          of: fila,
          matching: find.textContaining('${(r.reserva * 100).round()} %'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: fila,
          matching: find.textContaining(e.txt.nombreEtapa(r.etapa)),
        ),
        findsOneWidget,
      );
    }
    // Tocar la fila abre la ficha de esa plantación.
    final otra = e.plantaciones.first;
    await t.tap(find.byKey(Key('finca-lote-${otra.loteId}')));
    await t.pumpAndSettle();
    expect(
      t.widget<PantallaMiPlantacion>(find.byType(PantallaMiPlantacion)).loteId,
      otra.loteId,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets(
    '2a. Ficha: resumen del agua y acceso al detalle de esa plantación',
    (t) async {
      final e = await _ejemplo(t);
      final maiz = e.plantaciones.first;
      expect(e.plantacion!.id, isNot(maiz.id));
      await _ficha(t, maiz);
      final r = e.recomendacionDe(maiz);
      final resumen = find.byKey(const Key('ficha-resumen-agua'));
      expect(resumen, findsOneWidget);
      expect(
        find.descendant(
          of: resumen,
          matching: find.text(e.txt.tituloNivel(r.nivel)),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: resumen,
          matching: find.text('${(r.reserva * 100).round()} % de agua'),
        ),
        findsOneWidget,
      );
      expect(
        t
            .widget<Icon>(
              find.descendant(
                of: resumen,
                matching: find.byIcon(CupertinoIcons.circle_fill),
              ),
            )
            .color,
        PestanaHoy.colorNivel(t.element(resumen), r.nivel),
      );
      await _pulsa(t, 'Ver detalle del agua');
      final detalle = find.byType(PantallaDetalleAgua);
      expect(detalle, findsOneWidget);
      expect(t.widget<PantallaDetalleAgua>(detalle).plantacionId, maiz.id);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    '2c. «Cultivos anteriores» solo aparece si hay campañas previas',
    (t) async {
      final e = await _ejemplo(t);
      final p = e.plantacion!;
      await _ficha(t, p);
      expect(find.text('Cultivos anteriores de este lote'), findsNothing);
      await e.cerrarCampania(p.id, _hoy);
      await t.pumpAndSettle();
      expect(find.text('Cultivos anteriores de este lote'), findsOneWidget);
      expect(find.text('Iniciar un cultivo aquí'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('3a. Hoy: actualizar clima desde la barra y deslizando', (
    t,
  ) async {
    final clima = ClimaFalso();
    final e = await _ejemplo(t, clima: clima);
    expect(e.recomendacion.nivel, isNot(NivelAgua.sinDatos));
    final antes = clima.descargas;
    await t.tap(find.byKey(const Key('hoy-actualizar-clima')));
    await t.pumpAndSettle();
    expect(clima.descargas, antes + 1);

    await t.drag(find.byType(CustomScrollView).first, const Offset(0, 500));
    await t.pumpAndSettle();
    expect(clima.descargas, antes + 2);
    expect(t.takeException(), isNull);
  });

  testWidgets('3b. Hoy: Registrar actividad funciona aunque no haya clima', (
    t,
  ) async {
    final e = await _ejemplo(t, clima: ClimaFalso(wifi: false));
    expect(e.recomendacion.nivel, NivelAgua.sinDatos);
    final boton = find.widgetWithText(BotonPrincipal, 'Registrar actividad');
    expect(boton, findsOneWidget);
    expect(t.widget<BotonPrincipal>(boton).alPulsar, isNotNull);
    await t.tap(boton);
    await t.pumpAndSettle();
    expect(find.byType(PantallaActividad), findsOneWidget);
    expect(find.text('Resumen de la semana'), findsOneWidget);
  });

  testWidgets('4. Registrar actividad: orden por frecuencia y 2 toques', (
    t,
  ) async {
    final e = await _ejemplo(t);
    // Desde Hoy: Registrar actividad y Resumen de la semana son 2 toques.
    await _pulsa(t, 'Registrar actividad');
    await _pulsa(t, 'Resumen de la semana');
    expect(find.byType(PantallaRegistro), findsOneWidget);
    await _pulsa(t, 'Cancelar');

    // La plantación de ejemplo con riego muestra Riego en segundo lugar.
    final con = e.plantaciones.firstWhere((p) => p.tieneRiego);
    expect(e.plantacion!.id, con.id);
    double y(String texto) => t.getTopLeft(find.text(texto).first).dy;
    final orden = [
      y('Resumen de la semana'),
      y('Riego'),
      y('Cosecha'),
      y('Plaga'),
      y('Abono o tratamiento'),
    ];
    expect([...orden]..sort(), orden);
    expect(find.text('Pérdida'), findsNothing);
    expect(find.text('Observación'), findsNothing);
    await _pulsa(t, 'Otras');
    expect(find.text('Pérdida'), findsOneWidget);
    expect(find.text('Observación'), findsOneWidget);
    await _pulsa(t, 'Atrás');

    // Sin riego no aparece Riego.
    final sin = e.plantaciones.firstWhere((p) => !p.tieneRiego);
    await _ficha(t, sin);
    await _pulsa(t, 'Registrar actividad');
    expect(find.text('Riego'), findsNothing);
    expect(find.text('Resumen de la semana'), findsOneWidget);
    // Cosecha lleva directo al formulario.
    await _pulsa(t, 'Cosecha');
    expect(find.text('Cantidad cosechada'), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets('5. Mapa: tocar una zona abre su ficha y la nota lo dice', (
    t,
  ) async {
    final e = await _ejemplo(t);
    final p = e.plantaciones.first;
    expect(p.contorno.length, greaterThanOrEqualTo(3));
    await _tab(t, 'Finca');
    await _pulsa(t, 'Ver mapa de la finca');
    expect(find.byType(PantallaMapaFinca), findsOneWidget);
    expect(find.textContaining('para elegirla'), findsNothing);
    expect(
      find.text('Toca una plantación en el mapa para abrir su ficha.'),
      findsOneWidget,
    );
    final caja = t.getRect(find.byKey(const Key('lienzo-finca')));
    final c =
        p.contorno.fold(Offset.zero, (a, q) => a + Offset(q.x, q.y)) /
        p.contorno.length.toDouble();
    await t.tapAt(caja.topLeft + Offset(c.dx * caja.width, c.dy * caja.height));
    await t.pumpAndSettle();
    expect(
      t.widget<PantallaMiPlantacion>(find.byType(PantallaMiPlantacion)).loteId,
      p.loteId,
    );
    expect(t.takeException(), isNull);
  });

  testWidgets('5. Mapa en horizontal: los botones se ven sin desplazar', (
    t,
  ) async {
    const tamano = Size(844, 390);
    final e = await _ejemplo(t, tamano: tamano);
    await _tab(t, 'Finca');
    await _pulsa(t, 'Ver mapa de la finca');
    final lienzo = t.getRect(find.byKey(const Key('lienzo-finca')));
    expect(lienzo.height, lessThanOrEqualTo(tamano.height));
    final editar = find.text(
      e.parcela!.contorno.length >= 3
          ? e.txt.editarContorno
          : e.txt.dibujarContorno,
    );
    expect(editar, findsOneWidget);
    final r = t.getRect(editar);
    expect(r.bottom, lessThanOrEqualTo(tamano.height));
    expect(r.top, greaterThanOrEqualTo(0));
    expect(t.takeException(), isNull);
  });

  testWidgets(
    '6. Borrar todos los datos: Ajustes > Opciones avanzadas > Borrar',
    (t) async {
      final e = await _ejemplo(t);
      await _tab(t, 'Ajustes');
      await _pulsa(t, 'Opciones avanzadas');
      expect(find.text('Paquete de datos'), findsOneWidget);
      expect(find.text('Copiar GeoJSON'), findsWidgets);
      final borrar = find.text('Borrar todos los datos');
      await _visible(t, borrar);
      expect(borrar, findsOneWidget);
      await t.tap(borrar);
      await t.pumpAndSettle();
      // La confirmación aparece y cancelar no borra nada.
      expect(find.text(e.txt.borrarPregunta), findsOneWidget);
      await t.tap(find.text('Cancelar'));
      await t.pumpAndSettle();
      expect(e.campanias, isNotEmpty);
    },
  );

  testWidgets('7. Texto.fuerte no es menor que Texto.cuerpo', (t) async {
    await t.pumpWidget(
      CupertinoApp(
        theme: temaApp(Brightness.light),
        home: Builder(
          builder: (context) {
            expect(
              Texto.fuerte(context).fontSize,
              greaterThanOrEqualTo(Texto.cuerpo(context).fontSize!),
            );
            expect(Texto.cuerpo(context).fontSize, 18);
            return const SizedBox();
          },
        ),
      ),
    );
  });

  for (final (nombre, tamano) in [
    ('vertical', const Size(390, 844)),
    ('horizontal', const Size(844, 390)),
  ]) {
    testWidgets('7. letra al doble sin desbordes: $nombre', (t) async {
      final e = await _ejemplo(t, tamano: tamano, escala: 2.0);
      expect(
        MediaQuery.textScalerOf(t.element(find.byType(PestanaHoy))).scale(10),
        20,
      );
      for (final tab in ['Hoy', 'Finca', 'Registros', 'Ajustes']) {
        await _tab(t, tab);
        expect(t.takeException(), isNull, reason: '$nombre / $tab');
      }
      await _tab(t, 'Hoy');
      await _pulsa(t, 'Registrar actividad');
      expect(t.takeException(), isNull, reason: '$nombre / actividad');
      await _pulsa(t, 'Otras');
      expect(t.takeException(), isNull, reason: '$nombre / otras');
      await _pulsa(t, 'Atrás');
      await _ficha(t, e.plantaciones.first);
      expect(t.takeException(), isNull, reason: '$nombre / ficha');
      await _pulsa(t, 'Más opciones');
      expect(t.takeException(), isNull, reason: '$nombre / ficha abierta');
      await _pulsa(t, 'Atrás');
      await _pulsa(t, 'Ver mapa de la finca');
      expect(t.takeException(), isNull, reason: '$nombre / mapa');
      await _pulsa(t, 'Atrás');
      await _tab(t, 'Ajustes');
      await _pulsa(t, 'Opciones avanzadas');
      expect(t.takeException(), isNull, reason: '$nombre / avanzadas');
    });
  }

  testWidgets(
    '8a. Mapa 3D y telemetría: VistaTopo3D, PanelTelemetria3D y cambio de capas',
    (t) async {
      final e = await _ejemplo(t);
      await _tab(t, 'Finca');
      await _pulsa(t, 'Ver mapa de la finca');
      expect(find.byType(PantallaMapaFinca), findsOneWidget);
      expect(find.byType(PanelTelemetria3D), findsOneWidget);
      expect(find.byKey(const Key('telemetria-humedad-tierra')), findsOneWidget);
      expect(find.byKey(const Key('telemetria-temp-altitud')), findsOneWidget);
      expect(find.byKey(const Key('telemetria-cuerpo-agua')), findsOneWidget);
      expect(find.byKey(const Key('telemetria-pendiente')), findsOneWidget);
      expect(find.byKey(const Key('telemetria-icta')), findsOneWidget);

      await _pulsa(t, '3D');
      expect(e.capa, CapaMapa.relieve3d);
      expect(find.byType(VistaTopo3D), findsOneWidget);

      final ctrl = ControladorTopo3D.instancia;
      for (final capa in ['temp', 'rain', 'elev', 'slope', 'icta', 'moist']) {
        final chip = find.byKey(Key('capa-3d-$capa'));
        await _visible(t, chip);
        await t.tap(chip);
        await t.pumpAndSettle();
        expect(ctrl.capaActiva, capa);
        expect(t.takeException(), isNull);
      }

      final perspectivaInicial = ctrl.morph3D;
      final btnPerspectiva = find.byKey(const Key('toggle-3d-perspectiva'));
      await _visible(t, btnPerspectiva);
      await t.tap(btnPerspectiva);
      await t.pumpAndSettle();
      expect(ctrl.morph3D, isNot(perspectivaInicial));
      ctrl.restablecerVista();
      await t.pumpAndSettle();
      expect(ctrl.morph3D, 1.0);
    },
  );

  test(
    '8b. Telemetría real: humedadSueloPct, MallaTerreno.sintetica y cuerpo de agua',
    () async {
      final d = DiaClima(
        fecha: _hoy,
        tmedia: 23.5,
        tmax: 29.0,
        tmin: 18.0,
        humedad: 75.0,
        viento: 2.0,
        radiacion: 20.0,
        lluvia: 4.0,
        gwettop: 0.60,
        gwetroot: 0.80,
      );
      // 0.80 * 0.65 + 0.60 * 0.35 = 0.52 + 0.21 = 0.73 -> 73.0 %
      expect(d.humedadSueloPct, closeTo(73.0, 1e-6));

      final interpretado = ServicioClima.interpretar({
        'geometry': {
          'coordinates': [-89.5312, 14.8250, 412.0],
        },
        'properties': {
          'parameter': {
            'T2M': {'20261114': 22.4},
            'T2M_MAX': {'20261114': 28.5},
            'T2M_MIN': {'20261114': 17.2},
            'RH2M': {'20261114': 78.0},
            'WS2M': {'20261114': 1.9},
            'ALLSKY_SFC_SW_DWN': {'20261114': 19.5},
            'PRECTOTCORR': {'20261114': 6.0},
            'GWETTOP': {'20261114': 0.70},
            'GWETROOT': {'20261114': 0.75},
          },
        },
      });
      expect(interpretado.elevacion, 412.0);
      expect(interpretado.dias.single.gwettop, 0.70);
      expect(interpretado.dias.single.gwetroot, 0.75);
      expect(interpretado.dias.single.humedadSueloPct, closeTo(73.25, 1e-6));

      final malla = MallaTerreno.sintetica(
        latitud: 14.8250,
        longitud: -89.5312,
        elevacionBase: 420.0,
      );
      expect(malla.n, 56);
      expect(malla.cuerposAgua, isNotEmpty);
      final cw = malla.evaluarCuerpoAguaCercano(14.8250, -89.5312);
      expect(cw, isNotNull);
      expect(cw!.distanciaM, greaterThanOrEqualTo(0));
    },
  );

  test(
    '8c. QA: sincronizar fusiona clima nuevo con histórico y desempata plagas del mismo día',
    () async {
      SharedPreferences.setMockInitialValues({});
      final e = AppEstado(
        await Almacen.abrir(),
        servicioClima: ClimaFalso(),
        servicioMapa: MapaFalso(),
        reloj: () => _hoy,
      );
      await e.preparada;
      await e.cargarEjemplo();

      final historico = DateTime(2025, 12, 1);
      e.clima = [
        DiaClima(
          fecha: historico,
          tmax: 28,
          tmin: 17,
          humedad: 65,
          viento: 2,
          radiacion: 19,
          lluvia: 3,
        ),
      ];
      final res = await e.sincronizar();
      expect(res, ResultadoSync.ok);
      expect(
        e.clima.any((d) => soloFecha(d.fecha) == historico),
        isTrue,
        reason: 'El clima histórico previo a la ventana no debe perderse',
      );
      expect(e.humedadTierraDe(), isNotNull);
      expect(e.cuerpoAguaDe(), isNotNull);

      final p = e.plantacion!;
      await e.guardarEvento(
        Evento(
          id: 'plaga-1',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: TipoEvento.plaga,
          fecha: _hoy,
          severidad: 'leve',
        ),
      );
      expect(e.recomendacion.avisos, isNot(contains(Aviso.plaga)));

      await e.guardarEvento(
        Evento(
          id: 'plaga-2',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: TipoEvento.plaga,
          fecha: _hoy,
          severidad: 'fuerte',
        ),
      );
      expect(e.recomendacion.avisos, contains(Aviso.plaga));

      await e.guardarEvento(
        Evento(
          id: 'plaga-3',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: TipoEvento.plaga,
          fecha: _hoy,
          severidad: 'leve',
        ),
      );
      expect(e.recomendacion.avisos, isNot(contains(Aviso.plaga)));
    },
  );

  testWidgets(
    '8d. QA: borrar la única plantación de un lote desde su ficha vuelve a Finca sin Lote 0',
    (t) async {
      final e = await _ejemplo(t);
      final p = e.plantacion!;
      await _ficha(t, p);
      await _pulsa(t, 'Datos de la plantación');
      await _pulsa(t, 'Contorno del lote y borrar (opcional)');
      await _pulsa(t, 'Borrar plantación');
      await _pulsa(t, 'Borrar');
      expect(e.plantacionPorId(p.id), isNull);
      expect(find.byType(PantallaMiPlantacion), findsNothing);
      expect(find.textContaining('Lote 0'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
