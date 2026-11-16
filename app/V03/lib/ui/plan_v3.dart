import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../plan_v3.dart';
import '../textos.dart';
import 'bitacora.dart' show PieGuardar, numeroLimpio;
import 'emergentes.dart' as emergentes;
import 'tema.dart';

String _nombrePrioridad(Txt t, PrioridadPlanV3 prioridad) =>
    switch (prioridad) {
      PrioridadPlanV3.produccion => t.bilingue('Producción', 'Production'),
      PrioridadPlanV3.margen => t.bilingue('Margen', 'Margin'),
    };

class PantallaPlanV3 extends StatefulWidget {
  const PantallaPlanV3({super.key});

  @override
  State<PantallaPlanV3> createState() => _PlanV3();
}

class _PlanV3 extends State<PantallaPlanV3> {
  final _presupuesto = TextEditingController();
  final _costoRiego = TextEditingController();
  final _lista = ScrollController();
  PrioridadPlanV3? _prioridad;
  String? _error;
  bool _calculando = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prioridad != null) return;
    final opciones = Alcance.leer(context).opcionesPlanV3;
    _prioridad = opciones.prioridad;
    final monto = opciones.presupuestoQ;
    _presupuesto.text = monto == null ? '' : numeroLimpio(monto);
    final costo = opciones.costoRiegoQ;
    _costoRiego.text = costo == null ? '' : numeroLimpio(costo);
  }

  @override
  void dispose() {
    _presupuesto.dispose();
    _costoRiego.dispose();
    _lista.dispose();
    super.dispose();
  }

  double? _monto(TextEditingController campo) =>
      double.tryParse(campo.text.trim().replaceAll(',', '.'));

  bool _montoInvalido(TextEditingController campo, double? monto) =>
      campo.text.trim().isNotEmpty &&
      (monto == null || !monto.isFinite || monto < 0);

  Future<void> _elegirPrioridad(Txt t) async {
    final elegida = await emergentes.elegirOpcion(
      context,
      titulo: t.bilingue('Objetivo del plan', 'Plan goal'),
      opciones: [
        for (final v in PrioridadPlanV3.values)
          emergentes.OpcionHoja(valor: v, texto: _nombrePrioridad(t, v)),
      ],
      seleccionada: _prioridad,
    );
    if (mounted && elegida != null) {
      setState(() {
        _prioridad = elegida;
        _error = null;
      });
    }
  }

  Future<void> _calcular({bool actualizarClima = false}) async {
    if (_calculando) return;
    final estado = Alcance.leer(context);
    final t = estado.txt;
    final presupuesto = _monto(_presupuesto);
    final costo = _monto(_costoRiego);
    if (_montoInvalido(_presupuesto, presupuesto) ||
        _montoInvalido(_costoRiego, costo)) {
      setState(() {
        _error = t.bilingue(
          'Escribe importes válidos en quetzales.',
          'Enter valid amounts in quetzals.',
        );
      });
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _calculando = true;
      _error = null;
    });
    final soloOpciones = estado.plantaciones.isEmpty;
    try {
      if (actualizarClima) {
        final sync = await estado.sincronizar();
        if (!mounted) return;
        if (sync != ResultadoSync.ok) {
          setState(() {
            _error = sync == ResultadoSync.sinWifi ? t.sinWifi : t.errorSync;
          });
          return;
        }
      }
      await estado.calcularPlanV3(
        OpcionesPlanV3(
          prioridad: _prioridad!,
          presupuestoQ: presupuesto,
          costoRiegoQ: costo,
        ),
      );
      if (!mounted) return;
      if (soloOpciones) {
        Navigator.of(context).pop();
      } else if (_lista.hasClients) {
        _lista.jumpTo(0);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormatException && !t.en
              ? error.message
              : t.bilingue(
                  'No se pudo calcular el plan. Revisa los datos de la finca.',
                  'Could not calculate the plan. Check the farm data.',
                );
        });
      }
    } finally {
      if (mounted) setState(() => _calculando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final opciones = estado.opcionesPlanV3;
    final resultado = estado.resultadoPlanV3;
    final hayCampanias = estado.plantaciones.isNotEmpty;
    final presupuesto = _monto(_presupuesto);
    final costo = _monto(_costoRiego);
    final cambiaronOpciones =
        _prioridad != opciones.prioridad ||
        presupuesto != opciones.presupuestoQ ||
        costo != opciones.costoRiegoQ ||
        _montoInvalido(_presupuesto, presupuesto) ||
        _montoInvalido(_costoRiego, costo);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.bilingue('Plan diario', 'Daily plan')),
        previousPageTitle: t.atras,
        border: null,
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: ListView(
                    controller: _lista,
                    padding: const EdgeInsets.only(bottom: Espacio.m),
                    children: [
                      if (resultado == null)
                        Padding(
                          padding: const EdgeInsets.all(Espacio.m),
                          child: Tarjeta(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  t.bilingue('Manejo de hoy', 'Today’s plan'),
                                  style: Texto.fuerte(context),
                                ),
                                const SizedBox(height: Espacio.xs),
                                Text(
                                  t.bilingue(
                                    hayCampanias
                                        ? 'Usa el clima y los registros guardados para calcular el plan en este dispositivo.'
                                        : 'Registra un cultivo en Finca para calcular el plan. Puedes guardar estas opciones para tu próxima siembra.',
                                    hayCampanias
                                        ? 'Use saved weather and records to calculate the plan on this device.'
                                        : 'Add a crop in Farm to calculate the plan. You can save these options for your next planting.',
                                  ),
                                  style: Texto.nota(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      if (resultado != null)
                        _ResumenPlanV3(
                          key: const Key('plan-v3-resultado'),
                          resultado: resultado,
                          presupuestoQ: opciones.presupuestoQ,
                          desactualizado:
                              estado.resultadoPlanV3Desactualizado ||
                              cambiaronOpciones,
                          actualizarClima: _calculando || estado.sincronizando
                              ? null
                              : () => _calcular(actualizarClima: true),
                        ),
                      Rotulo(t.bilingue('Opciones', 'Options')),
                      Grupo(
                        children: [
                          Fila(
                            key: const Key('plan-v3-prioridad'),
                            titulo: t.bilingue(
                              'Objetivo del plan',
                              'Plan goal',
                            ),
                            detalle: _nombrePrioridad(t, _prioridad!),
                            alPulsar: _calculando
                                ? null
                                : () => _elegirPrioridad(t),
                          ),
                          Campo(
                            key: const Key('plan-v3-presupuesto'),
                            titulo: t.bilingue(
                              'Presupuesto disponible (Q)',
                              'Available budget (Q)',
                            ),
                            controlador: _presupuesto,
                            ejemplo: t.bilingue(
                              'Q4,000 de referencia',
                              'Q4,000 reference',
                            ),
                            teclado: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            alCambiar: (_) => setState(() => _error = null),
                          ),
                          Campo(
                            key: const Key('plan-v3-costo-riego'),
                            titulo: t.bilingue(
                              'Costo por turno de riego (Q)',
                              'Cost per irrigation turn (Q)',
                            ),
                            controlador: _costoRiego,
                            ejemplo: t.bilingue(
                              'Q28 de referencia',
                              'Q28 reference',
                            ),
                            teclado: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            alCambiar: (_) => setState(() => _error = null),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PieGuardar(
                  key: const Key('plan-v3-calcular'),
                  texto: _calculando
                      ? t.bilingue('Calculando…', 'Calculating…')
                      : hayCampanias
                      ? t.bilingue('Calcular plan', 'Calculate plan')
                      : t.bilingue('Guardar opciones', 'Save options'),
                  alPulsar: _calculando ? null : _calcular,
                  error: _error,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResumenPlanV3 extends StatelessWidget {
  const _ResumenPlanV3({
    super.key,
    required this.resultado,
    required this.presupuestoQ,
    required this.desactualizado,
    required this.actualizarClima,
  });

  final ResultadoPlanV3 resultado;
  final double? presupuestoQ;
  final bool desactualizado;
  final VoidCallback? actualizarClima;

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    final evaluados = resultado.evaluados;
    final pendientes = {
      for (final lote in resultado.lotes)
        if (lote.accion == AccionPlanV3.pendiente) ...lote.avisos,
    };
    final totalAgua = _medida(resultado.aguaM3, 3);
    final totalCosto = resultado.costoQ;
    final lotesRiego = resultado.lotes
        .where((lote) => lote.accion == AccionPlanV3.regar)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Rotulo(t.bilingue('Resumen de la finca', 'Farm summary')),
        Grupo(
          children: [
            Fila(
              icono: evaluados == 0
                  ? CupertinoIcons.exclamationmark_triangle
                  : CupertinoIcons.check_mark_circled,
              titulo: evaluados == 0
                  ? t.bilingue('Plan pendiente', 'Plan pending')
                  : t.bilingue('Plan calculado', 'Plan calculated'),
              detalle: evaluados == 0
                  ? pendientes.map((aviso) => _aviso(t, aviso)).join('\n')
                  : t.bilingue(
                      'La red neuronal evaluó $evaluados de ${resultado.lotes.length} lotes.',
                      'The neural network evaluated $evaluados of ${resultado.lotes.length} plots.',
                    ),
            ),
            if (pendientes.contains('clima_insuficiente'))
              Fila(
                icono: CupertinoIcons.arrow_clockwise,
                titulo: t.bilingue(
                  'Actualizar clima y recalcular',
                  'Refresh weather and recalculate',
                ),
                alPulsar: actualizarClima,
              ),
            if (desactualizado)
              Fila(
                icono: CupertinoIcons.exclamationmark_triangle,
                colorIcono: Paleta.de(context, Paleta.ambar),
                titulo: t.bilingue('Plan desactualizado', 'Outdated plan'),
                detalle: t.bilingue(
                  'Vuelve a calcular con los datos y opciones actuales.',
                  'Calculate again with the current data and options.',
                ),
              ),
          ],
        ),
        if (evaluados > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Espacio.m,
              Espacio.s,
              Espacio.m,
              0,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final escala = MediaQuery.textScalerOf(context).scale(1);
                final doble = constraints.maxWidth >= 320 && escala <= 1.35;
                final ancho = doble
                    ? (constraints.maxWidth - Espacio.s) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: Espacio.s,
                  runSpacing: Espacio.s,
                  children: [
                    _IndicadorPlanV3(
                      ancho: ancho,
                      titulo: t.bilingue('Lotes en el plan', 'Plots in plan'),
                      valor: '${resultado.lotes.length}',
                    ),
                    _IndicadorPlanV3(
                      ancho: ancho,
                      titulo: t.bilingue(
                        'Lotes para regar',
                        'Plots to irrigate',
                      ),
                      valor: '$lotesRiego',
                    ),
                    _IndicadorPlanV3(
                      ancho: ancho,
                      titulo: t.bilingue('Agua propuesta', 'Proposed water'),
                      valor: '$totalAgua m³',
                    ),
                    if (presupuestoQ case final presupuesto?)
                      _IndicadorPlanV3(
                        ancho: ancho,
                        titulo: t.bilingue('Presupuesto', 'Budget'),
                        valor: 'Q ${numeroLimpio(presupuesto)}',
                      ),
                    if (totalCosto != null)
                      _IndicadorPlanV3(
                        ancho: ancho,
                        titulo: t.bilingue('Costo estimado', 'Estimated cost'),
                        valor: 'Q ${_medida(totalCosto)}',
                      ),
                  ],
                );
              },
            ),
          ),
        if (resultado.lotes.isNotEmpty) ...[
          Rotulo(t.bilingue('Acciones por lote', 'Actions by plot')),
          Grupo(
            children: [
              for (final lote in resultado.lotes) _FilaLotePlanV3(lote: lote),
            ],
          ),
        ],
        if (resultado.avisos.isNotEmpty) ...[
          Rotulo(t.bilingue('Avisos', 'Notes')),
          Grupo(
            children: [
              for (final aviso in resultado.avisos)
                Fila(
                  icono: CupertinoIcons.info_circle,
                  titulo: _aviso(t, aviso),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _IndicadorPlanV3 extends StatelessWidget {
  const _IndicadorPlanV3({
    required this.ancho,
    required this.titulo,
    required this.valor,
  });

  final double ancho;
  final String titulo, valor;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: ancho,
    child: Tarjeta(
      padding: const EdgeInsets.all(Espacio.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Texto.nota(context)),
          const SizedBox(height: Espacio.xs),
          Text(valor, style: Texto.fuerte(context)),
        ],
      ),
    ),
  );
}

class _FilaLotePlanV3 extends StatelessWidget {
  const _FilaLotePlanV3({required this.lote});

  final ResultadoLotePlanV3 lote;

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    final regar = lote.accion == AccionPlanV3.regar;
    final accion = switch (lote.accion) {
      AccionPlanV3.regar => t.bilingue('Regar', 'Irrigate'),
      AccionPlanV3.continuar => t.bilingue(
        'Continuar la campaña',
        'Continue the season',
      ),
      AccionPlanV3.esperar => t.bilingue('Esperar', 'Wait'),
      AccionPlanV3.pendiente => t.bilingue(
        'Revisar el lote',
        'Review the plot',
      ),
    };
    return Fila(
      titulo: lote.nombre,
      icono: regar ? CupertinoIcons.drop : CupertinoIcons.leaf_arrow_circlepath,
      colorIcono: Paleta.de(context, switch (lote.accion) {
        AccionPlanV3.regar => Paleta.azul,
        AccionPlanV3.pendiente => Paleta.ambar,
        _ => Paleta.verde,
      }),
      detalle: [
        '${_cultivo(t, lote.cultivoId)} · $accion',
        if (regar)
          '${_medida(lote.laminaMm)} mm · ${_medida(lote.aguaM3, 3)} m³',
        if (lote.reserva case final reserva?)
          t.bilingue(
            'Reserva de agua ${(reserva * 100).round()} %',
            'Soil water reserve ${(reserva * 100).round()}%',
          ),
        if (lote.costoQ case final costo?) 'Q ${_medida(costo)}',
        for (final aviso in lote.avisos) _aviso(t, aviso),
      ].join('\n'),
    );
  }
}

String _medida(double valor, [int decimales = 2]) =>
    numeroLimpio(double.parse(valor.toStringAsFixed(decimales)));

String _cultivo(Txt t, String id) => switch (id) {
  'maize' || 'maiz' => t.nombreCultivo('maiz'),
  'bean' || 'frijol' => t.nombreCultivo('frijol'),
  'bean_zam' => t.bilingue('Frijol ICTA Zam', 'ICTA Zam beans'),
  'tomato' || 'tomate' => t.nombreCultivo('tomate'),
  'coffee' || 'cafe' => t.nombreCultivo('cafe'),
  _ => t.nombreCultivo(id),
};

String _aviso(Txt t, String aviso) => switch (aviso) {
  'clima_insuficiente' => t.bilingue(
    'Hace falta clima reciente para calcular el plan.',
    'Recent weather is required to calculate the plan.',
  ),
  'cultivo_no_compatible' => t.bilingue(
    'Este cultivo conserva el balance de agua de Hoy.',
    'This crop keeps its water balance in Today.',
  ),
  'agua_sin_confirmar' => t.bilingue(
    'Confirma el suministro de agua de hoy.',
    'Confirm today’s water supply.',
  ),
  'volumen_insuficiente' => t.bilingue(
    'El agua compartida limita el riego.',
    'Shared water limits irrigation.',
  ),
  'presupuesto_insuficiente' => t.bilingue(
    'El presupuesto limita el riego.',
    'The budget limits irrigation.',
  ),
  'entradas_estimadas' => t.bilingue(
    'Parte del estado de los lotes se estimó con el balance de agua.',
    'Some plot conditions were estimated from the water balance.',
  ),
  'costo_referencial' => t.bilingue(
    'El cálculo usó Q28 como costo de referencia por turno.',
    'The calculation used a Q28 reference cost per irrigation turn.',
  ),
  'area_pendiente' => t.bilingue(
    'Define el área del lote para calcular el volumen de riego.',
    'Set the plot area to calculate irrigation volume.',
  ),
  'campania_fuera_de_ciclo' => t.bilingue(
    'Revisa las fechas de la campaña antes de calcular.',
    'Check the season dates before calculating.',
  ),
  'turno_compartido' => t.bilingue(
    'El turno de hoy se asignó a otro lote.',
    'Today’s turn was assigned to another plot.',
  ),
  'sin_campanias' => t.bilingue(
    'Agrega una campaña activa para calcular el plan.',
    'Add an active season to calculate the plan.',
  ),
  'riego_reciente' => t.bilingue(
    'El registro ya muestra riego aplicado hoy.',
    'The log already shows irrigation applied today.',
  ),
  _ => aviso,
};
