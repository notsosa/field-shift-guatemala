import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import 'ajustes.dart' show confirmar;
import 'finca.dart';
import 'tema.dart';
import 'bitacora.dart' show elegirDiaOpcional, elegirOpcion;
import 'emergentes.dart' show Interruptor;

/// Registro de la plantación: siembra, plaga reciente, fertilizante, suelo y
/// riego. La plaga y el fertilizante son cajas que se despliegan al activarlas.
class PantallaPlantacion extends StatefulWidget {
  const PantallaPlantacion({
    super.key,
    this.primeraVez = false,
    this.id,
    this.loteId,
    this.contornoNuevo,
    this.fincaNueva,
  });

  final bool primeraVez;

  /// Plantación que se edita. Si es nulo, se crea una nueva.
  final String? id;
  final String? loteId;

  /// Perímetro recién dibujado para una plantación nueva.
  final List<Punto>? contornoNuevo;

  /// Contorno de la finca y ancho del plano dibujados en este mismo flujo.
  /// Se guardan junto con la plantación, al pulsar «Guardar».
  final Trazo? fincaNueva;

  @override
  State<PantallaPlantacion> createState() => _EstadoPlantacion();
}

class _EstadoPlantacion extends State<PantallaPlantacion> {
  final _nombre = TextEditingController();
  final _variedad = TextEditingController(),
      _anterior = TextEditingController(),
      _minima = TextEditingController();
  bool _mantener = false, _mezcla = false;
  List<Punto> _contorno = const [];
  String _cultivo = 'maiz';
  late DateTime _fecha;
  int _ciclo = 120;
  Suelo _suelo = Suelo.franco;
  TipoRiego _riego = TipoRiego.ninguno;
  TemporadaRiego _temporada = TemporadaRiego.auxilio;

  bool _plaga = false;
  final _notaPlaga = TextEditingController();
  DateTime? _inicioPlaga;
  NivelPlaga _nivelPlaga = NivelPlaga.leve;
  bool _plagaTratada = false;
  final _tratamiento = TextEditingController();

  bool _fertilizo = false;
  TipoFertilizante _tipoFertilizante = TipoFertilizante.quimico;
  final _notaFertilizante = TextEditingController();
  DateTime? _fechaFertilizante;

  bool _iniciado = false;
  String? _error;
  bool _guardando = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final estado = Alcance.leer(context);
    final hoy = soloFecha(estado.hoy);
    final p = estado.plantacionPorId(widget.id);
    _contorno = p?.contorno ?? widget.contornoNuevo ?? const [];
    _fecha = hoy;
    _inicioPlaga = hoy;
    _fechaFertilizante = hoy;
    if (p == null && widget.loteId != null) {
      final previas =
          estado.campanias.where((x) => x.loteId == widget.loteId).toList()
            ..sort((a, b) => b.fecha.compareTo(a.fecha));
      final previa = previas.isEmpty ? null : previas.first;
      _contorno = estado.parcela!.marco.aPlano(
        estado.lotePorId(widget.loteId!)!.geometria,
      );
      if (previa != null) {
        _nombre.text = previa.nombre;
        _suelo = previa.suelo;
        _riego = previa.riego;
        _temporada = previa.temporadaRiego;
        _anterior.text = estado.txt.nombreCultivo(previa.cultivoId);
      }
    }
    if (p != null) {
      _nombre.text = p.nombre;
      _variedad.text = p.variedad;
      _anterior.text = p.cultivoAnterior;
      _mantener = p.mantenerCultivo;
      _mezcla = p.permitirMezcla;
      _minima.text = p.proporcionMinima?.toString() ?? '';
      _cultivo = p.cultivoId;
      _fecha = p.fecha;
      _ciclo = p.ciclo;
      _suelo = p.suelo;
      _riego = p.riego;
      _temporada = p.temporadaRiego;
      _plaga = p.plagaReciente;
      _notaPlaga.text = p.notaPlaga;
      _inicioPlaga = p.inicioPlaga;
      _nivelPlaga = p.nivelPlaga == NivelPlaga.ninguna
          ? NivelPlaga.leve
          : p.nivelPlaga;
      _plagaTratada = p.plagaTratada;
      _tratamiento.text = p.tratamientoPlaga;
      _fertilizo = p.fertilizo;
      _tipoFertilizante = p.tipoFertilizante;
      _notaFertilizante.text = p.notaFertilizante;
      _fechaFertilizante = p.fechaFertilizante;
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _variedad.dispose();
    _anterior.dispose();
    _minima.dispose();
    _notaPlaga.dispose();
    _tratamiento.dispose();
    _notaFertilizante.dispose();
    super.dispose();
  }

  void _elegirCultivo(String id) => setState(() {
    _cultivo = id;
    final c = cultivoPorId(id);
    if (!c.ciclos.contains(_ciclo)) _ciclo = c.ciclos.first;
  });

  /// Abre el selector de fecha y devuelve la elegida, o nulo si se cancela. No
  /// deja pasar de hoy, y el rango siempre incluye la fecha que ya había: una
  /// siembra antigua no se recorta en silencio.
  Future<DateTime?> _pedirFecha(DateTime actual, {int aniosAtras = 3}) {
    final estado = Alcance.leer(context);
    final hoy = soloFecha(estado.hoy);
    final anioMin = hoy.year - aniosAtras;
    final ultimoDiaMes = DateTime(anioMin, hoy.month + 1, 0).day;
    return elegirDiaOpcional(
      context,
      actual,
      minimo: DateTime(
        anioMin,
        hoy.month,
        hoy.day <= ultimoDiaMes ? hoy.day : ultimoDiaMes,
      ),
      maximo: hoy,
    );
  }

  Future<void> _guardar() async {
    final estado = Alcance.leer(context);
    final navegador = Navigator.of(context);
    final c = cultivoPorId(_cultivo);
    // Lo dibujado en los pasos anteriores se guarda aquí, no antes, para que
    // abandonar el flujo no deje nada a medias.
    final finca = widget.fincaNueva;
    if (_guardando) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final minima = _mezcla && _minima.text.trim().isNotEmpty
          ? double.tryParse(_minima.text.replaceAll(',', '.'))
          : null;
      if (_mezcla && _minima.text.trim().isNotEmpty && minima == null) {
        throw FormatException(
          estado.txt.bilingue('Porcentaje inválido', 'Invalid percentage'),
        );
      }
      await estado.guardarPlantacion(
        Plantacion(
          id: widget.id ?? '',
          loteId:
              estado.plantacionPorId(widget.id)?.loteId ?? widget.loteId ?? '',
          variedad: _variedad.text.trim(),
          cultivoAnterior: _anterior.text.trim(),
          mantenerCultivo: _mantener,
          permitirMezcla: _mezcla,
          proporcionMinima: minima,
          nombre: _nombre.text.trim(),
          contorno: _contorno,
          cultivoId: _cultivo,
          fecha: _fecha,
          ciclo: c.perenne ? c.ciclos.first : _ciclo,
          suelo: _suelo,
          riego: _riego,
          temporadaRiego: _temporada,
          plagaReciente: _plaga,
          notaPlaga: _plaga ? _notaPlaga.text.trim() : '',
          inicioPlaga: _plaga ? _inicioPlaga : null,
          nivelPlaga: _plaga ? _nivelPlaga : NivelPlaga.leve,
          plagaTratada: _plaga && _plagaTratada,
          tratamientoPlaga: _plaga && _plagaTratada
              ? _tratamiento.text.trim()
              : '',
          fertilizo: _fertilizo,
          tipoFertilizante: _tipoFertilizante,
          notaFertilizante: _fertilizo ? _notaFertilizante.text.trim() : '',
          fechaFertilizante: _fertilizo ? _fechaFertilizante : null,
        ),
        fincaNueva: finca?.puntos,
        lado: finca?.lado,
      );
    } on FormatException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _guardando = false;
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = estado.txt.noSeGuardo;
          _guardando = false;
        });
      }
      return;
    }
    if (!mounted) return;
    estado.sincronizar();
    if (widget.id == null) {
      // Plantación nueva: se cierran de una vez todos los pasos del flujo.
      navegador.popUntil((r) => r.isFirst);
    } else {
      navegador.pop();
    }
  }

  Future<void> _redibujar() async {
    final estado = Alcance.leer(context);
    final t = estado.txt;
    final nuevo = await Navigator.of(context).push<Trazo>(
      CupertinoPageRoute(
        builder: (_) => PantallaTrazo(
          titulo: t.perimetro,
          ayuda: t.ayudaTrazoPlantacion,
          excepto: widget.id,
          inicial: _contorno,
          lado: widget.fincaNueva?.lado,
          fincaPendiente: widget.fincaNueva?.puntos,
        ),
      ),
    );
    // Queda en el formulario; se guarda con el resto al pulsar «Guardar».
    if (nuevo != null && nuevo.puntos.length >= 3 && mounted) {
      setState(() => _contorno = nuevo.puntos);
    }
  }

  void _borrar() {
    final estado = Alcance.leer(context);
    final t = estado.txt;
    final navegador = Navigator.of(context);
    final id = widget.id!;
    final actividades = estado.eventosDe(id).where((x) => !x.derivado).length;
    final riegos = estado.riegosDiarios.where((r) => r.campaniaId == id).length;
    final resumenes = estado.registrosDe(id).length;
    final partes = [
      if (actividades > 0)
        t.bilingue(
          '$actividades ${actividades == 1 ? 'actividad' : 'actividades'}',
          '$actividades ${actividades == 1 ? 'activity' : 'activities'}',
        ),
      if (riegos > 0)
        t.bilingue(
          '$riegos ${riegos == 1 ? 'riego' : 'riegos'}',
          '$riegos ${riegos == 1 ? 'irrigation' : 'irrigations'}',
        ),
      if (resumenes > 0)
        t.bilingue(
          '$resumenes ${resumenes == 1 ? 'resumen de la semana' : 'resúmenes de la semana'}',
          '$resumenes weekly ${resumenes == 1 ? 'summary' : 'summaries'}',
        ),
    ];
    final perdera = partes.isEmpty
        ? t.bilingue(
            'Esta plantación no tiene registros.',
            'This planting has no records.',
          )
        : t.bilingue(
            'Se perderán: ${partes.join(', ')}.',
            'You will lose: ${partes.join(', ')}.',
          );
    confirmar(
      context,
      titulo: t.borrarPlantacion,
      mensaje: t.bilingue(
        'Se borrará esta plantación. $perdera No se puede deshacer.',
        'This planting will be deleted. $perdera This cannot be undone.',
      ),
      accion: t.borrar,
      cancelar: t.cancelar,
      alConfirmar: () async {
        final loteId = estado.plantacionPorId(id)?.loteId;
        await estado.borrarPlantacion(id);
        if (!mounted) return;
        if (loteId != null && estado.lotePorId(loteId) == null) {
          navegador.popUntil((r) => r.isFirst);
        } else {
          navegador.pop();
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final cultivo = cultivoPorId(_cultivo);

    Widget bloque(String titulo, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Espacio.borde,
        vertical: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Texto.cuerpo(context)),
          const SizedBox(height: 10),
          control,
        ],
      ),
    );

    Widget interruptor(
      Key clave,
      bool valor,
      ValueChanged<bool> alCambiar, {
      String? etiqueta,
    }) => Interruptor(
      key: clave,
      valor: valor,
      alCambiar: alCambiar,
      etiqueta: etiqueta,
    );

    Widget filaFecha(
      String titulo,
      DateTime? fecha,
      ValueChanged<DateTime> alElegir, {
      int aniosAtras = 3,
    }) => Fila(
      titulo: titulo,
      detalle: fecha == null ? t.sinDato : t.fechaLarga(fecha),
      alPulsar: () async {
        final f = await _pedirFecha(
          fecha ?? soloFecha(estado.hoy),
          aniosAtras: aniosAtras,
        );
        if (f != null && mounted) alElegir(f);
      },
    );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.plantacion),
        previousPageTitle: t.atras,
        border: null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                scrollCacheExtent: const ScrollCacheExtent.pixels(2400),
                padding: const EdgeInsets.only(bottom: Espacio.l),
                children: [
                  // Siembra: fecha y cultivo.
                  Rotulo(t.siembra),
                  Grupo(
                    children: [
                      filaFecha(
                        cultivo.perenne ? t.fechaReferencia : t.fechaSiembra,
                        _fecha,
                        (f) => setState(() => _fecha = f),
                      ),
                      Campo(
                        titulo: t.nombreLote,
                        controlador: _nombre,
                        ejemplo: t.ejemploLote,
                      ),
                    ],
                  ),
                  const SizedBox(height: Espacio.m),
                  Grupo(
                    children: [
                      Fila(
                        titulo: t.bilingue('Cultivo', 'Crop'),
                        detalle: t.nombreCultivo(_cultivo),
                        alPulsar: () async {
                          final v = await elegirOpcion(
                            context,
                            t.bilingue('¿Qué cultivo?', 'Which crop?'),
                            {
                              for (final c in catalogo)
                                c.id: t.nombreCultivo(c.id),
                            },
                            seleccionada: _cultivo,
                          );
                          if (v != null && mounted) _elegirCultivo(v);
                        },
                      ),
                      if (!cultivo.perenne && cultivo.ciclos.length > 1)
                        bloque(
                          t.ciclo,
                          Selector<int>(
                            opciones: {
                              for (final d in cultivo.ciclos) d: t.dias(d),
                            },
                            valor: _ciclo,
                            alCambiar: (v) => setState(() => _ciclo = v),
                          ),
                        ),
                    ],
                  ),

                  // Suelo y riego: lo que necesita el cálculo de agua.
                  Rotulo(t.sueloYRiego),
                  Grupo(
                    children: [
                      bloque(
                        t.suelo,
                        Selector<Suelo>(
                          opciones: {
                            for (final s in Suelo.values) s: t.nombreSuelo(s),
                          },
                          valor: _suelo,
                          alCambiar: (v) => setState(() => _suelo = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Espacio.m),
                  Grupo(
                    children: [
                      Fila(
                        titulo: t.bilingue('Tipo de riego', 'Irrigation type'),
                        detalle: t.nombreRiego(_riego),
                        alPulsar: () async {
                          final v = await elegirOpcion(
                            context,
                            t.bilingue('¿Cómo riegas?', 'How do you irrigate?'),
                            {
                              for (final r in TipoRiego.values)
                                r: t.nombreRiego(r),
                            },
                            seleccionada: _riego,
                          );
                          if (v != null && mounted) setState(() => _riego = v);
                        },
                      ),
                      if (_riego != TipoRiego.ninguno)
                        bloque(
                          t.temporadaRiego,
                          Selector<TemporadaRiego>(
                            opciones: {
                              for (final x in TemporadaRiego.values)
                                x: t.nombreTemporada(x),
                            },
                            valor: _temporada,
                            alCambiar: (v) => setState(() => _temporada = v),
                          ),
                        ),
                    ],
                  ),

                  SeccionDesplegable(
                    titulo: t.bilingue(
                      'Variedad y próximas siembras (opcional)',
                      'Variety and future plantings (optional)',
                    ),
                    children: [
                      Grupo(
                        children: [
                          Campo(
                            titulo: t.bilingue('Variedad', 'Variety'),
                            controlador: _variedad,
                            ejemplo: t.opcional,
                          ),
                          Campo(
                            titulo: t.bilingue(
                              'Cultivo anterior',
                              'Previous crop',
                            ),
                            controlador: _anterior,
                            ejemplo: t.opcional,
                          ),
                          Fila(
                            titulo: t.bilingue(
                              'Mantener este cultivo',
                              'Keep this crop',
                            ),
                            detalle: t.bilingue(
                              'Las alternativas deben conservarlo.',
                              'Alternatives must keep this crop.',
                            ),
                            final_: interruptor(
                              const Key('mantener-cultivo'),
                              _mantener,
                              (v) => setState(() => _mantener = v),
                              etiqueta: t.bilingue(
                                'Mantener este cultivo',
                                'Keep this crop',
                              ),
                            ),
                          ),
                          Fila(
                            titulo: t.bilingue(
                              'Permitir mezcla',
                              'Allow intercropping',
                            ),
                            final_: interruptor(
                              const Key('permitir-mezcla'),
                              _mezcla,
                              (v) => setState(() => _mezcla = v),
                              etiqueta: t.bilingue(
                                'Permitir mezcla',
                                'Allow intercropping',
                              ),
                            ),
                          ),
                          if (_mezcla)
                            Campo(
                              key: const Key('proporcion-minima'),
                              titulo: t.bilingue(
                                'Mínimo del lote (%)',
                                'Minimum plot area (%)',
                              ),
                              controlador: _minima,
                              ejemplo: t.opcional,
                              teclado: const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                            ),
                        ],
                      ),
                      if (_mezcla)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Espacio.l,
                          ),
                          child: Text(
                            t.bilingue(
                              'Porcentaje del área del lote que debe conservar este cultivo.',
                              'Percentage of this plot’s area that must retain this crop.',
                            ),
                            style: Texto.nota(context),
                          ),
                        ),
                    ],
                  ),
                  SeccionDesplegable(
                    titulo: t.bilingue(
                      '¿Tuvo plaga o abono al sembrar? (opcional)',
                      'Any pests or fertilizer at planting? (optional)',
                    ),
                    children: [
                      // Caja de plaga reciente.
                      Grupo(
                        children: [
                          Fila(
                            titulo: t.plagaReciente,
                            detalle: t.plagaAyuda,
                            icono: CupertinoIcons.ant,
                            final_: interruptor(
                              const Key('plaga'),
                              _plaga,
                              (v) => setState(() => _plaga = v),
                              etiqueta: t.plagaReciente,
                            ),
                          ),
                          if (_plaga) ...[
                            Campo(
                              titulo: t.cualPlaga,
                              controlador: _notaPlaga,
                              ejemplo: t.ejemploPlaga,
                            ),
                            filaFecha(
                              t.desdeCuando,
                              _inicioPlaga,
                              (f) => setState(() => _inicioPlaga = f),
                              aniosAtras: 1,
                            ),
                            bloque(
                              t.danio,
                              Selector<NivelPlaga>(
                                opciones: {
                                  for (final n in NivelPlaga.values)
                                    if (n != NivelPlaga.ninguna)
                                      n: t.nombrePlaga(n),
                                },
                                valor: _nivelPlaga,
                                alCambiar: (v) =>
                                    setState(() => _nivelPlaga = v),
                              ),
                            ),
                            Fila(
                              titulo: t.yaTratada,
                              final_: interruptor(
                                const Key('plagaTratada'),
                                _plagaTratada,
                                (v) => setState(() => _plagaTratada = v),
                                etiqueta: t.yaTratada,
                              ),
                            ),
                            if (_plagaTratada)
                              Campo(
                                titulo: t.conQue,
                                controlador: _tratamiento,
                                ejemplo: t.notaOpcional,
                              ),
                          ],
                        ],
                      ),
                      const SizedBox(height: Espacio.m),

                      // Caja de fertilizante.
                      Grupo(
                        children: [
                          Fila(
                            titulo: t.fertilizacion,
                            detalle: t.fertilizanteAyuda,
                            icono: CupertinoIcons.leaf_arrow_circlepath,
                            final_: interruptor(
                              const Key('fertilizo'),
                              _fertilizo,
                              (v) => setState(() => _fertilizo = v),
                              etiqueta: t.fertilizacion,
                            ),
                          ),
                          if (_fertilizo) ...[
                            bloque(
                              t.claseFertilizante,
                              Selector<TipoFertilizante>(
                                opciones: {
                                  for (final f in TipoFertilizante.values)
                                    f: t.nombreFertilizante(f),
                                },
                                valor: _tipoFertilizante,
                                alCambiar: (v) =>
                                    setState(() => _tipoFertilizante = v),
                              ),
                            ),
                            Campo(
                              titulo: t.producto,
                              controlador: _notaFertilizante,
                              ejemplo: t.ejemploFertilizante,
                            ),
                            filaFecha(
                              t.fechaAplicacion,
                              _fechaFertilizante,
                              (f) => setState(() => _fechaFertilizante = f),
                              aniosAtras: 1,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  // Perímetro en el croquis y borrado, solo al editar.
                  if (widget.id != null)
                    SeccionDesplegable(
                      titulo: t.bilingue(
                        'Contorno del lote y borrar (opcional)',
                        'Plot outline and delete (optional)',
                      ),
                      children: [
                        Grupo(
                          children: [
                            Fila(
                              titulo: t.perimetro,
                              detalle: _contorno.length >= 3
                                  ? t.area(
                                      areaDe(_contorno, estado.parcela!.lado),
                                    )
                                  : t.sinDibujar,
                              icono: CupertinoIcons.map,
                              alPulsar: widget.loteId == null
                                  ? _redibujar
                                  : null,
                            ),
                            if (estado.plantaciones.length > 1)
                              Fila(
                                titulo: t.borrarPlantacion,
                                icono: CupertinoIcons.trash,
                                colorIcono: Paleta.de(context, Paleta.rojo),
                                alPulsar: _borrar,
                              ),
                          ],
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Text(
                  _error!,
                  style: Texto.nota(context)
                      .copyWith(color: Paleta.de(context, Paleta.rojo)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Espacio.l,
                Espacio.s,
                Espacio.l,
                Espacio.m,
              ),
              child: BotonPrincipal(
                texto: t.guardar,
                alPulsar: _guardando ? null : _guardar,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
