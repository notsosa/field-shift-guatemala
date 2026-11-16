import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import '../plan_v3.dart';
import '../textos.dart';
import 'finca.dart' show Trazo;
import 'plantacion.dart';
import 'tema.dart';

class PantallaSiembraV3 extends StatefulWidget {
  const PantallaSiembraV3({
    super.key,
    this.loteId,
    this.trazo,
    this.primeraVez = false,
  });

  final String? loteId;
  final Trazo? trazo;
  final bool primeraVez;

  @override
  State<PantallaSiembraV3> createState() => _SiembraV3();
}

class _SiembraV3 extends State<PantallaSiembraV3> {
  Future<PropuestaSiembraV3>? _calculo;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _calculo ??= _evaluarLote();
  }

  Future<PropuestaSiembraV3> _evaluarLote() => Alcance.leer(context)
      .proponerSiembraV3(
        loteId: widget.loteId,
        contorno: widget.trazo?.puntos,
        lado: widget.trazo?.lado,
      );

  void _abrirFormulario([PropuestaSiembraV3? sugerencia]) {
    final trazo = widget.trazo;
    final finca = Alcance.leer(context).parcela!;
    final puntos = trazo == null
        ? null
        : reescalar(trazo.puntos, trazo.lado, finca.lado);
    Navigator.of(context).push<void>(
      CupertinoPageRoute(
        builder: (_) => PantallaPlantacion(
          primeraVez: widget.primeraVez,
          loteId: widget.loteId,
          contornoNuevo: puntos,
          sugerencia: sugerencia,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.bilingue('Sugerencia de cultivo', 'Crop suggestion')),
        previousPageTitle: t.atras,
        border: null,
      ),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: FutureBuilder<PropuestaSiembraV3>(
              future: _calculo,
              builder: (context, snapshot) {
                final termino =
                    snapshot.connectionState == ConnectionState.done;
                final propuesta = termino ? snapshot.data : null;
                final error = termino ? snapshot.error : null;
                final falta = error is SiembraNoDisponible
                    ? error.motivo
                    : null;
                final fechaFutura =
                    propuesta != null &&
                    soloFecha(propuesta.fecha).isAfter(soloFecha(estado.hoy));
                final sePuedeRegistrar =
                    propuesta != null &&
                    !propuesta.convieneEsperar &&
                    soloFecha(propuesta.fecha) == soloFecha(estado.hoy) &&
                    catalogo.any((c) => c.id == propuesta.cultivoId);
                return ListView(
                  key: const Key('siembra-v3'),
                  padding: const EdgeInsets.only(bottom: Espacio.xl),
                  children: [
                    if (propuesta == null && error == null)
                      Padding(
                        padding: const EdgeInsets.all(Espacio.l),
                        child: Column(
                          children: [
                            const CupertinoActivityIndicator(),
                            const SizedBox(height: Espacio.s),
                            Text(
                              t.bilingue(
                                'Evaluando el lote…',
                                'Evaluating the plot…',
                              ),
                              style: Texto.cuerpo(context),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    if (error != null) ...[
                      Rotulo(
                        t.bilingue('Propuesta pendiente', 'Proposal pending'),
                      ),
                      Grupo(
                        children: [
                          Fila(
                            titulo: falta != null
                                ? _tituloFalta(t, falta)
                                : error is FormatException && !t.en
                                ? error.message
                                : t.bilingue(
                                    'No se pudo evaluar el lote. Revisa el clima y los datos guardados.',
                                    'Could not evaluate the plot. Check the saved weather and plot data.',
                                  ),
                            detalle: falta == null
                                ? null
                                : _detalleFalta(t, falta),
                            icono: CupertinoIcons.info_circle,
                          ),
                          if (falta == FaltaParaSiembra.clima)
                            Fila(
                              titulo: t.bilingue(
                                'Actualizar clima y reintentar',
                                'Refresh weather and retry',
                              ),
                              icono: CupertinoIcons.arrow_clockwise,
                              alPulsar: () =>
                                  setState(() => _calculo = _evaluarLote()),
                            ),
                        ],
                      ),
                    ],
                    if (propuesta != null) ...[
                      Rotulo(
                        t.bilingue(
                          'Sugerencia de la red neuronal',
                          'Neural network suggestion',
                        ),
                      ),
                      Grupo(
                        children: [
                          Fila(
                            titulo: t.nombreCultivo(propuesta.cultivoId),
                            detalle: [
                              if (propuesta.variedad.isNotEmpty)
                                propuesta.variedad,
                              t.dias(propuesta.ciclo),
                            ].join(' · '),
                            icono: CupertinoIcons.leaf_arrow_circlepath,
                          ),
                          Fila(
                            titulo: fechaFutura
                                ? t.bilingue(
                                    'Próxima fecha posible',
                                    'Next possible planting date',
                                  )
                                : t.bilingue(
                                    'Fecha evaluada',
                                    'Evaluated date',
                                  ),
                            detalle: t.fechaLarga(propuesta.fecha),
                            icono: CupertinoIcons.calendar,
                          ),
                          if (propuesta.convieneEsperar || !sePuedeRegistrar)
                            Fila(
                              titulo: fechaFutura
                                  ? t.bilingue(
                                      'Espera a la ventana de siembra',
                                      'Wait for the planting window',
                                    )
                                  : t.bilingue(
                                      'La red recomienda esperar',
                                      'The network recommends waiting',
                                    ),
                              detalle: fechaFutura
                                  ? t.bilingue(
                                      'La fecha viene del calendario del cultivo. Vuelve a evaluar cerca de ese día.',
                                      'The date comes from the crop calendar. Reassess as it approaches.',
                                    )
                                  : t.bilingue(
                                      'Con los datos de hoy, esperar obtuvo un puntaje igual o mayor que sembrar.',
                                      'With today’s data, waiting scored at least as high as planting.',
                                    ),
                              icono: CupertinoIcons.info_circle,
                              colorIcono: Paleta.de(context, Paleta.ambar),
                            ),
                        ],
                      ),
                    ],
                    Padding(
                      padding: const EdgeInsets.all(Espacio.m),
                      child: Column(
                        children: [
                          if (sePuedeRegistrar)
                            BotonPrincipal(
                              key: const Key('siembra-v3-revisar'),
                              texto: t.bilingue(
                                'Revisar y registrar',
                                'Review and record',
                              ),
                              alPulsar: () => _abrirFormulario(propuesta),
                            ),
                          BotonPrincipal(
                            key: const Key('siembra-v3-manual'),
                            texto: t.bilingue(
                              'Elegir manualmente',
                              'Choose manually',
                            ),
                            secundario: true,
                            alPulsar: _abrirFormulario,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

String _tituloFalta(Txt t, FaltaParaSiembra falta) => switch (falta) {
  FaltaParaSiembra.clima => t.bilingue(
    'Falta clima reciente',
    'Recent weather is missing',
  ),
  FaltaParaSiembra.presupuesto => t.bilingue(
    'El presupuesto no alcanza para este lote',
    'The budget is too low for this plot',
  ),
  FaltaParaSiembra.temperatura => t.bilingue(
    'Temperatura fuera de los rangos del catálogo',
    'Temperature outside catalog ranges',
  ),
  FaltaParaSiembra.agua => t.bilingue(
    'Falta confirmar el agua',
    'Water availability needs confirmation',
  ),
  FaltaParaSiembra.humedad => t.bilingue(
    'Humedad del suelo insuficiente',
    'Soil moisture is too low',
  ),
  FaltaParaSiembra.fecha => t.bilingue(
    'Sin ventana de siembra disponible',
    'No planting window is available',
  ),
};

String _detalleFalta(Txt t, FaltaParaSiembra falta) => switch (falta) {
  FaltaParaSiembra.clima => t.bilingue(
    'Se necesitan cuatro días de clima en el último mes y al menos uno en los últimos diez días. Conéctate a Wi-Fi para actualizar.',
    'Four usable days of weather are needed in the last month, including one in the last ten days. Connect to Wi-Fi to refresh.',
  ),
  FaltaParaSiembra.presupuesto => t.bilingue(
    'El costo estimado para el área del lote supera el presupuesto del plan. Si no indicaste un monto, se usan Q4,000 de referencia.',
    'Estimated costs for this area exceed the plan budget. If no amount was provided, Q4,000 is used as a reference.',
  ),
  FaltaParaSiembra.temperatura => t.bilingue(
    'Ningún cultivo que cabe en el presupuesto se ajusta a la temperatura reciente.',
    'None of the crops that fit the budget are suitable for recent temperatures.',
  ),
  FaltaParaSiembra.agua => t.bilingue(
    'Los cultivos disponibles requieren agua confirmada en la finca.',
    'The available crops require confirmed farm water.',
  ),
  FaltaParaSiembra.humedad => t.bilingue(
    'La humedad superficial estimada no alcanza el mínimo de los cultivos disponibles hoy.',
    'Estimated surface moisture is below the minimum for today’s eligible crops.',
  ),
  FaltaParaSiembra.fecha => t.bilingue(
    'El calendario de los cultivos y las condiciones registradas no ofrecen una fecha de siembra.',
    'The crop calendars and current records yield no planting date.',
  ),
};
