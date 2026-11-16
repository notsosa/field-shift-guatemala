import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import 'finca.dart';
import 'tema.dart';
import 'bitacora.dart';
import 'emergentes.dart' show Interruptor;
import 'flujo.dart';

/// Formulario del registro semanal: riego, plaga y fertilizante.
class PantallaRegistro extends StatefulWidget {
  const PantallaRegistro({super.key, this.plantacionId});
  final String? plantacionId;

  @override
  State<PantallaRegistro> createState() => _EstadoRegistro();
}

class _EstadoRegistro extends State<PantallaRegistro> {
  /// Plantación a la que pertenece el registro. Arranca en la que se estaba
  /// viendo y se puede cambiar en el formulario.
  String? _plantacionId;

  /// Veces que regó en la semana. Nulo = todavía sin responder.
  int? _riegos;
  NivelPlaga _plaga = NivelPlaga.ninguna;
  bool _fertilizo = false;
  final _notaPlaga = TextEditingController();
  final _notaFertilizante = TextEditingController();

  /// Resumen de los últimos 6 días que se está corrigiendo, si ya existía.
  RegistroSemanal? _editando;
  bool _iniciado = false;
  bool _guardando = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final estado = Alcance.leer(context);
    _cargarDe(estado, _plantacion(estado), limpiar: false);
  }

  @override
  void dispose() {
    _notaPlaga.dispose();
    _notaFertilizante.dispose();
    super.dispose();
  }

  Plantacion _plantacion(AppEstado estado) =>
      estado.plantacionPorId(_plantacionId ?? widget.plantacionId) ??
      estado.plantacion!;

  /// El resumen más reciente de los últimos 6 días, si lo hay.
  RegistroSemanal? _reciente(AppEstado estado, Plantacion p) {
    final hoy = soloFecha(estado.hoy);
    RegistroSemanal? mejor;
    for (final r in estado.registrosDe(p.id)) {
      final f = soloFecha(r.fecha);
      if (f.isAfter(hoy) || hoy.difference(f).inDays > 6) continue;
      if (mejor == null || f.isAfter(soloFecha(mejor.fecha))) mejor = r;
    }
    return mejor;
  }

  /// Prepara el formulario para [p]: abre su resumen reciente para editarlo o
  /// lo deja vacío. Con [limpiar] se borra lo escrito si no hay resumen.
  void _cargarDe(AppEstado estado, Plantacion p, {required bool limpiar}) {
    final r = _reciente(estado, p);
    _editando = r;
    _riegos = null;
    if (r != null) {
      _riegos = p.tieneRiego ? r.riegos : null;
      _plaga = r.plaga;
      _notaPlaga.text = r.notaPlaga;
      _fertilizo = r.fertilizo;
      _notaFertilizante.text = r.notaFertilizante;
    } else if (limpiar) {
      _plaga = NivelPlaga.ninguna;
      _notaPlaga.clear();
      _fertilizo = false;
      _notaFertilizante.clear();
    }
  }

  Future<void> _guardar() async {
    final estado = Alcance.leer(context);
    final navegador = Navigator.of(context);
    final plantacion = _plantacion(estado);
    if (plantacion.tieneRiego && _riegos == null) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await estado.guardarRegistro(
        RegistroSemanal(
          plantacionId: plantacion.id,
          fecha: _editando?.fecha ?? soloFecha(estado.hoy),
          riegos: plantacion.tieneRiego ? _riegos! : (_editando?.riegos ?? 0),
          plaga: _plaga,
          notaPlaga: _plaga == NivelPlaga.ninguna ? '' : _notaPlaga.text.trim(),
          fertilizo: _fertilizo,
          notaFertilizante: _fertilizo ? _notaFertilizante.text.trim() : '',
        ),
      );
      // Al volver se muestra la plantación a la que se le acaba de registrar.
      await estado.seleccionar(plantacion.id);
      navegador.pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormatException
              ? error.message
              : estado.txt.noSeGuardo;
          _guardando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final verde = Paleta.de(context, Paleta.verde);
    final plantacion = _plantacion(estado);
    final tieneRiego = plantacion.riego != TipoRiego.ninguno;
    final sinResponder = tieneRiego && _riegos == null;

    Widget paso(IconData icono, VoidCallback? alPulsar) => CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(48, 48),
      onPressed: alPulsar,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Paleta.de(context, Paleta.tenue),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icono,
          size: 18,
          color: alPulsar == null
              ? Paleta.de(context, Paleta.secundario)
              : verde,
        ),
      ),
    );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.registroSemanal),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancelar),
        ),
        border: null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  if (widget.plantacionId == null &&
                      estado.plantaciones.length > 1) ...[
                    Rotulo(t.paraCualPlantacion),
                    Grupo(
                      children: [
                        for (final p in estado.plantaciones)
                          Fila(
                            key: Key('registro-${p.id}'),
                            titulo: t.nombrePlantacion(p),
                            detalle: t.fechaLarga(p.fecha),
                            final_: Icon(
                              p.id == plantacion.id
                                  ? CupertinoIcons.checkmark_circle_fill
                                  : CupertinoIcons.circle,
                              size: 24,
                              color: p.id == plantacion.id
                                  ? verde
                                  : Paleta.de(context, Paleta.tenue),
                            ),
                            alPulsar: () => setState(() {
                              if (p.id == plantacion.id) return;
                              final habiaEdicion = _editando != null;
                              _plantacionId = p.id;
                              _error = null;
                              _cargarDe(estado, p, limpiar: habiaEdicion);
                            }),
                          ),
                      ],
                    ),
                  ],
                  Rotulo(
                    '${identificarPlantacion(estado, plantacion)} · ${t.ultimaSemana}',
                  ),
                  if (_editando != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Espacio.l,
                        0,
                        Espacio.l,
                        Espacio.m,
                      ),
                      child: Text(
                        t.bilingue(
                          'Estás editando el resumen del ${t.fechaLarga(_editando!.fecha)}',
                          'You are editing the summary of ${t.fechaLarga(_editando!.fecha)}',
                        ),
                        key: const Key('editando-resumen'),
                        style: Texto.fuerte(context),
                      ),
                    ),
                  if (tieneRiego) ...[
                    Grupo(
                      children: [
                        Fila(
                          titulo: t.vecesRiego,
                          icono: CupertinoIcons.drop,
                          final_: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              paso(
                                CupertinoIcons.minus,
                                _riegos != null && _riegos! > 0
                                    ? () =>
                                          setState(() => _riegos = _riegos! - 1)
                                    : null,
                              ),
                              SizedBox(
                                width: 40,
                                child: Text(
                                  _riegos == null ? '—' : '$_riegos',
                                  key: const Key('veces-riego'),
                                  textAlign: TextAlign.center,
                                  style: letra(
                                    20,
                                    peso: 600,
                                    color: Paleta.de(context, Paleta.texto),
                                  ),
                                ),
                              ),
                              paso(
                                CupertinoIcons.plus,
                                (_riegos ?? 0) < 14
                                    ? () => setState(
                                        () => _riegos = (_riegos ?? 0) + 1,
                                      )
                                    : null,
                              ),
                            ],
                          ),
                        ),
                        Fila(
                          key: const Key('no-regue'),
                          titulo: t.bilingue('No regué', 'I did not irrigate'),
                          final_: Icon(
                            _riegos == 0
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            size: 24,
                            color: _riegos == 0
                                ? verde
                                : Paleta.de(context, Paleta.secundario),
                          ),
                          alPulsar: () => setState(() => _riegos = 0),
                        ),
                      ],
                    ),
                    const SizedBox(height: Espacio.m),
                  ],
                  Grupo(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Espacio.borde,
                          vertical: 14,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  CupertinoIcons.ant,
                                  size: 22,
                                  color: verde,
                                ),
                                const SizedBox(width: 14),
                                Text(t.plaga, style: Texto.cuerpo(context)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Selector<NivelPlaga>(
                              opciones: {
                                for (final n in NivelPlaga.values)
                                  n: t.nombrePlaga(n),
                              },
                              valor: _plaga,
                              alCambiar: (v) => setState(() => _plaga = v),
                            ),
                          ],
                        ),
                      ),
                      if (_plaga != NivelPlaga.ninguna)
                        Campo(
                          titulo: t.cualPlaga,
                          controlador: _notaPlaga,
                          ejemplo: t.notaOpcional,
                        ),
                    ],
                  ),
                  const SizedBox(height: Espacio.m),
                  Grupo(
                    children: [
                      Fila(
                        titulo: t.fertilizaste,
                        icono: CupertinoIcons.leaf_arrow_circlepath,
                        final_: Interruptor(
                          valor: _fertilizo,
                          alCambiar: (v) => setState(() => _fertilizo = v),
                          etiqueta: t.fertilizaste,
                        ),
                      ),
                      if (_fertilizo)
                        Campo(
                          titulo: t.nota,
                          controlador: _notaFertilizante,
                          ejemplo: t.queAplicaste,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PieGuardar(
              texto: t.guardar,
              alPulsar: _guardando || sinResponder ? null : _guardar,
              error: _error,
              motivo: sinResponder
                  ? t.bilingue(
                      'Dinos cuántas veces regaste, o toca «No regué»',
                      'Tell us how many times you irrigated, or tap “I did not irrigate”',
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

/// Consulta y captura de actividades; la configuración vive en Finca.
class PestanaRegistros extends StatelessWidget {
  const PestanaRegistros({super.key});
  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    final p = e.plantacion;
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(t.registros),
            border: null,
          ),
          SliverList.list(
            children: [
              if (p == null)
                Padding(
                  padding: const EdgeInsets.all(Espacio.l),
                  child: Text(
                    t.bilingue(
                      'Tus registros anteriores están en Finca. Elige un lote para consultarlos o iniciar otro cultivo.',
                      'Your previous records are in Farm. Choose a plot to view them or start another crop.',
                    ),
                    style: Texto.cuerpo(context),
                  ),
                )
              else ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: Espacio.m),
                  child: CambioPlantacion(),
                ),
                Padding(
                  padding: const EdgeInsets.all(Espacio.m),
                  child: BotonPrincipal(
                    texto: t.bilingue('Registrar actividad', 'Record activity'),
                    alPulsar: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute<void>(
                            builder: (_) =>
                                PantallaActividad(plantacionId: p.id),
                          ),
                        ),
                  ),
                ),
                Rotulo(t.bilingue('Lo que has registrado', 'Your records')),
                HistorialPlantacion(plantacion: p),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
