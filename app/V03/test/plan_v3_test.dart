import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/main.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/plan_v3.dart';
import 'package:flutter_test/flutter_test.dart';

import 'agua_geometria_test.dart' as base;

Future<AppEstado> _fincaSinAgua() async {
  final estado = await base.abrir();
  await estado.guardarParcela(base.finca);
  estado.clima = base
      .clima()
      .where((dia) => dia.fecha.isBefore(base.fecha))
      .toList();
  await estado.guardarPlantacion(
    base.siembra(contorno: base.rect(.1, .1, .25, .25)),
  );
  final p = estado.plantacion!;
  await estado.guardarAgua(
    SuministroAgua(fecha: base.fecha, disponibilidad: DisponibilidadAgua.no),
    RegistroRiego(
      campaniaId: p.id,
      loteId: p.loteId,
      fecha: base.fecha,
      necesito: true,
      rego: false,
    ),
  );
  return estado;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'la V3 local evalúa con su asset, respeta el agua y guarda el plan',
    () async {
      final estado = await _fincaSinAgua();
      const opciones = OpcionesPlanV3(
        prioridad: PrioridadPlanV3.margen,
        presupuestoQ: 150,
        costoRiegoQ: 30,
      );

      await estado.calcularPlanV3(opciones);

      final plan = estado.resultadoPlanV3!;
      expect(plan.evaluados, 1);
      expect(plan.motor, 'Red neuronal');
      expect(plan.lotes.single.accion, isNot(AccionPlanV3.regar));
      expect(plan.lotes.single.laminaMm, 0);
      expect(plan.aguaM3, 0);
      expect(estado.resultadoPlanV3Desactualizado, isFalse);

      final reabierto = AppEstado(
        await Almacen.abrir(),
        reloj: () => base.fecha,
      );
      await reabierto.preparada;
      expect(reabierto.resultadoPlanV3?.aJson(), plan.aJson());
      expect(reabierto.opcionesPlanV3.aJson(), opciones.aJson());
      expect(reabierto.resultadoPlanV3Desactualizado, isFalse);
    },
  );

  test('la V3 elige un cultivo con solo el contorno del lote', () async {
    final estado = await _fincaSinAgua();
    estado.clima = [
      for (final dia in estado.clima)
        DiaClima.deJson({
          ...dia.aJson(),
          if (base.fecha.difference(dia.fecha).inDays <= 3) 'l': 22.0,
        }),
    ];
    final cantidad = estado.plantaciones.length;
    final propuesta = await estado.proponerSiembraV3(
      contorno: base.rect(.55, .55, .2, .2),
    );
    expect(
      catalogo.any((cultivo) => cultivo.id == propuesta.cultivoId),
      isTrue,
    );
    expect(propuesta.ciclo, greaterThan(0));
    expect(propuesta.fecha.isBefore(soloFecha(base.fecha)), isFalse);
    expect(estado.plantaciones.length, cantidad);
  });

  testWidgets('Finca abre el tablero local y ofrece alta manual o con V3', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final estado = await _fincaSinAgua();
    await tester.pumpWidget(FieldShift(estado: estado));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(CupertinoTabBar),
        matching: find.text('Finca'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nueva plantación'), findsOneWidget);
    expect(find.byKey(const ValueKey('finca-siembra-v3')), findsOneWidget);
    final enlace = find.byKey(const ValueKey('finca-plan-v3'));
    await tester.scrollUntilVisible(
      enlace,
      230,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(enlace);
    await tester.pumpAndSettle();

    final calcular = find.text('Calcular plan');
    expect(calcular.hitTestable(), findsOneWidget);
    expect(find.text('Copiar solicitud'), findsNothing);
    expect(find.text('Pegar resultado'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
