import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import '../motor/cafe.dart';
import '../motor/recomendador.dart';
import '../textos.dart';
import 'bitacora.dart' show PieGuardar;
import 'emergentes.dart' as emergentes;
import 'tema.dart';

/// Resultado y configuración de la red de riego para el cafetal seleccionado.
class TarjetaRedCafe extends StatelessWidget {
  const TarjetaRedCafe({
    super.key,
    required this.plantacion,
    required this.recomendacion,
  });

  final Plantacion plantacion;
  final Recomendacion recomendacion;

  @override
  Widget build(BuildContext context) {
    if (plantacion.cultivoId != cultivoCafe) return const SizedBox.shrink();
    final e = Alcance.de(context), t = e.txt;
    final cafe = recomendacion.cafeRed;
    final decision = cafe?.riego;
    final disponible =
        plantacion.tieneRiego &&
        recomendacion.disponibilidad == DisponibilidadAgua.si;
    final admiteLamina =
        disponible && recomendacion.riegoSugerido >= laminaRiegoCafeMm;
    final puedeRegar = decision?.regar == true && admiteLamina;
    final avisos = cafe?.avisos.where((aviso) => aviso.seMuestra) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Rotulo(t.bilingue('Riego del café', 'Coffee irrigation')),
        Grupo(
          key: const Key('tarjeta_cafe'),
          children: [
            if (decision == null)
              Fila(
                icono: CupertinoIcons.info_circle,
                titulo: t.bilingue(
                  'Cálculo de riego pendiente',
                  'Irrigation calculation pending',
                ),
                detalle: _motivo(t, cafe?.motivo),
              )
            else ...[
              Fila(
                icono: decision.regar
                    ? CupertinoIcons.drop
                    : CupertinoIcons.clock,
                colorIcono: Paleta.de(
                  context,
                  puedeRegar ? Paleta.azul : Paleta.ambar,
                ),
                titulo: puedeRegar
                    ? t.bilingue('Regar 20 mm hoy', 'Irrigate 20 mm today')
                    : decision.regar
                    ? t.bilingue(
                        'El riego podría reducir el estrés',
                        'Irrigation could reduce stress',
                      )
                    : t.bilingue(
                        'Conviene esperar antes de regar',
                        'Wait before irrigating',
                      ),
                detalle: _resumen(t, decision, disponible, admiteLamina),
              ),
              if (decision.antracnosisCambioPrioridad)
                Fila(
                  icono: CupertinoIcons.info_circle,
                  titulo: t.bilingue('Prioridad aplicada', 'Priority applied'),
                  detalle: t.bilingue(
                    'El aviso de estrés activó la prioridad de proteger el cultivo.',
                    'The stress notice activated crop protection priority.',
                  ),
                ),
            ],
            for (final aviso in avisos) _filaAviso(context, t, aviso),
            Fila(
              key: const Key('datos-cafetal'),
              titulo: t.bilingue('Datos del cafetal', 'Coffee plot details'),
              detalle: t.bilingue(
                'Floración, sombra, suelo y prioridad',
                'Flowering, shade, soil and priority',
              ),
              icono: CupertinoIcons.slider_horizontal_3,
              alPulsar: () => Navigator.of(context, rootNavigator: true).push(
                CupertinoPageRoute<void>(
                  builder: (_) => _DatosCafetal(plantacion: plantacion),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _motivo(Txt t, MotivoCafe? motivo) => switch (motivo) {
  MotivoCafe.riegoReciente => t.bilingue(
    'Hay un riego registrado en los últimos 7 días.',
    'An irrigation event was recorded in the last 7 days.',
  ),
  MotivoCafe.floracionFueraDeTemporada => t.bilingue(
    'La red cubre floraciones del 15 de febrero al 15 de mayo. Verifica la fecha del cafetal.',
    'The network covers flowering from February 15 to May 15. Check the plot’s flowering date.',
  ),
  MotivoCafe.diasFueraDeRango => t.bilingue(
    'La red se aplica entre 20 y 100 días después de la última floración.',
    'The network applies between 20 and 100 days after the last flowering.',
  ),
  MotivoCafe.historialClimaticoInsuficiente => t.bilingue(
    'Se necesita el historial de lluvia y temperatura desde noviembre. Actualiza el clima en Hoy.',
    'Weather records from November are needed. Refresh the weather in Today.',
  ),
  MotivoCafe.climaViejo || null => t.bilingue(
    'Actualiza el clima en Hoy para volver a evaluar el cafetal.',
    'Refresh the weather in Today to reassess the coffee plot.',
  ),
};

String _resumen(
  Txt t,
  DecisionRiegoCafe decision,
  bool disponible,
  bool admiteLamina,
) {
  final dias = decision.diasEvitados.clamp(0.0, 30.0).toStringAsFixed(1);
  return [
    t.bilingue(
      'La red estima $dias días de estrés evitados en los próximos 30 días con 20 mm hoy.',
      'The network estimates $dias stress days avoided over the next 30 days with 20 mm today.',
    ),
    if (decision.regar && !disponible)
      t.bilingue(
        'Para aplicarlo, confirma que el lote puede recibir riego en Agua y riego.',
        'Before irrigating, confirm the plot can receive water in Water and irrigation.',
      )
    else if (decision.regar && !admiteLamina)
      t.bilingue(
        'Consulta la lámina admitida por el balance de agua en Hoy.',
        'Check the irrigation depth allowed by the water balance in Today.',
      ),
  ].join('\n');
}

Widget _filaAviso(BuildContext context, Txt t, AvisoCafe aviso) {
  final titulo = switch (aviso.tipo) {
    TipoAvisoCafe.abono =>
      aviso.nivel == NivelAvisoCafe.abonarYa
          ? t.bilingue(
              'Abono: condiciones favorables',
              'Fertilizer: favorable conditions',
            )
          : t.bilingue(
              'Abono: espera a que el suelo tenga humedad',
              'Fertilizer: wait for moist soil',
            ),
    TipoAvisoCafe.antracnosis => t.bilingue(
      'Antracnosis: estrés hídrico en el cafetal',
      'Anthracnose: water stress in the coffee plot',
    ),
    TipoAvisoCafe.roya => t.bilingue(
      'Roya: temperatura en el rango de germinación',
      'Rust: temperature within the germination range',
    ),
  };
  return Fila(
    titulo: titulo,
    icono: CupertinoIcons.exclamationmark_circle,
    colorIcono: Paleta.de(context, Paleta.ambar),
  );
}

class _DatosCafetal extends StatefulWidget {
  const _DatosCafetal({required this.plantacion});
  final Plantacion plantacion;

  @override
  State<_DatosCafetal> createState() => _EstadoDatosCafetal();
}

class _EstadoDatosCafetal extends State<_DatosCafetal> {
  late Sombra _sombra = widget.plantacion.sombra;
  late SueloSurcos _surcos = widget.plantacion.sueloSurcos;
  late PrioridadRiego _prioridad = widget.plantacion.prioridadRiego;
  bool _guardando = false;
  String? _error;

  Future<void> _elegir<T>(
    String titulo,
    T actual,
    List<T> opciones,
    String Function(T) nombre,
    ValueChanged<T> asignar,
  ) async {
    final elegido = await emergentes.elegirOpcion<T>(
      context,
      titulo: titulo,
      seleccionada: actual,
      opciones: [
        for (final opcion in opciones)
          emergentes.OpcionHoja(valor: opcion, texto: nombre(opcion)),
      ],
    );
    if (mounted && elegido != null) setState(() => asignar(elegido));
  }

  Future<void> _guardar() async {
    if (_guardando) return;
    final e = Alcance.leer(context), t = e.txt;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final p = e.plantacionPorId(widget.plantacion.id);
      if (p == null || !p.activa || p.cultivoId != cultivoCafe) {
        throw FormatException(
          t.bilingue(
            'El cafetal ya no está disponible.',
            'This coffee plot is no longer available.',
          ),
        );
      }
      await e.guardarPlantacion(
        Plantacion.deJson({
          ...p.aJson(),
          'sombra': _sombra.name,
          'sueloSurcos': _surcos.name,
          'prioridadRiego': _prioridad.name,
        }),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _guardando = false;
          _error = error is FormatException ? error.message : t.noSeGuardo;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    final sombra = t.bilingue('Sombra', 'Shade');
    final surcos = t.bilingue('Suelo entre los surcos', 'Ground between rows');
    final prioridad = t.bilingue('Prioridad de riego', 'Irrigation priority');
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.bilingue('Datos del cafetal', 'Coffee plot details')),
        previousPageTitle: t.atras,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Grupo(
                    children: [
                      Fila(
                        titulo: t.fechaReferencia,
                        detalle: t.fechaLarga(widget.plantacion.fecha),
                        icono: CupertinoIcons.calendar,
                      ),
                      Fila(
                        titulo: sombra,
                        detalle: _nombreSombra(t, _sombra),
                        alPulsar: _guardando
                            ? null
                            : () => _elegir(
                                sombra,
                                _sombra,
                                Sombra.values,
                                (value) => _nombreSombra(t, value),
                                (value) => _sombra = value,
                              ),
                      ),
                      if (_sombra == Sombra.ninguna)
                        Fila(
                          titulo: surcos,
                          detalle: _nombreSurcos(t, _surcos),
                          alPulsar: _guardando
                              ? null
                              : () => _elegir(
                                  surcos,
                                  _surcos,
                                  SueloSurcos.values,
                                  (value) => _nombreSurcos(t, value),
                                  (value) => _surcos = value,
                                ),
                        ),
                      Fila(
                        titulo: prioridad,
                        detalle: _nombrePrioridad(t, _prioridad),
                        alPulsar: _guardando
                            ? null
                            : () => _elegir(
                                prioridad,
                                _prioridad,
                                PrioridadRiego.values,
                                (value) => _nombrePrioridad(t, value),
                                (value) => _prioridad = value,
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PieGuardar(
              texto: t.guardar,
              alPulsar: _guardando ? null : _guardar,
              error: _error,
            ),
          ],
        ),
      ),
    );
  }
}

String _nombreSombra(Txt t, Sombra opcion) => switch (opcion) {
  Sombra.ninguna => t.bilingue('Sin sombra', 'No shade'),
  Sombra.arbolesPerennes => t.bilingue('Árboles perennes', 'Evergreen trees'),
  Sombra.arbolesCaducos => t.bilingue('Árboles caducos', 'Deciduous trees'),
  Sombra.bananoRegulado => t.bilingue('Banano regulado', 'Managed banana'),
  Sombra.bananoDenso => t.bilingue('Banano denso', 'Dense banana'),
};

String _nombreSurcos(Txt t, SueloSurcos opcion) => switch (opcion) {
  SueloSurcos.limpio => t.bilingue(
    'Limpio o con cobertura',
    'Clean or mulched',
  ),
  SueloSurcos.malezas => t.bilingue('Con malezas', 'With weeds'),
};

String _nombrePrioridad(Txt t, PrioridadRiego opcion) => switch (opcion) {
  PrioridadRiego.ahorrarAgua => t.bilingue('Ahorrar agua', 'Save water'),
  PrioridadRiego.protegerCultivo => t.bilingue(
    'Proteger el cultivo',
    'Protect the crop',
  ),
};
