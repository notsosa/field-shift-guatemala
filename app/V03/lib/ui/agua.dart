import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import 'ajustes.dart' show confirmar;
import 'bitacora.dart' show PieGuardar, elegirDiaOpcional, numeroLimpio;
import 'emergentes.dart' as emergentes;
import 'tema.dart';

/// Saldo compartido de la finca y aplicación del lote son observaciones distintas.
class PantallaAgua extends StatefulWidget {
  const PantallaAgua({super.key, this.fechaInicial, this.campaniaId});
  final DateTime? fechaInicial;
  final String? campaniaId;
  @override
  State<PantallaAgua> createState() => _EstadoAgua();
}

class _EstadoAgua extends State<PantallaAgua> {
  DateTime? _fecha;
  String? _campania;
  DisponibilidadAgua _disponibilidad = DisponibilidadAgua.desconocida;
  int _necesito = -1, _rego = -1;
  final _volumen = TextEditingController(), _lamina = TextEditingController();
  String? _error;
  bool _guardando = false;

  // Lo que se cargó al abrir el formulario: sirve para saber si hay cambios
  // sin guardar antes de descartarlos.
  int _necesito0 = -1, _rego0 = -1;
  String _lamina0 = '', _volumen0 = '';
  DisponibilidadAgua _disponibilidad0 = DisponibilidadAgua.desconocida;

  bool get _riegoSucio =>
      _campania != null &&
      (_necesito != _necesito0 ||
          _rego != _rego0 ||
          _lamina.text.trim() != _lamina0);
  bool get _suministroSucio =>
      _disponibilidad != _disponibilidad0 || _volumen.text.trim() != _volumen0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fecha != null) return;
    final e = Alcance.leer(context);
    final candidatas = e.plantaciones.where((p) => p.tieneRiego).toList();
    _campania =
        widget.campaniaId ??
        (candidatas.length == 1 ? candidatas.single.id : null);
    _fecha = soloFecha(widget.fechaInicial ?? e.hoy);
    _cargar();
  }

  void _cargar({bool soloRiego = false}) {
    final e = Alcance.leer(context);
    final p = e.plantacionPorId(_campania);
    final r = p == null ? null : e.riegoDe(p.loteId, _fecha!, campaniaId: p.id);
    final s = e.suministroDe(_fecha!);
    if (!soloRiego) {
      _disponibilidad = s?.disponibilidad ?? DisponibilidadAgua.desconocida;
      _volumen.text = s?.volumenM3 == null ? '' : numeroLimpio(s!.volumenM3!);
      _disponibilidad0 = _disponibilidad;
      _volumen0 = _volumen.text.trim();
    }
    _necesito = r?.necesito == null
        ? -1
        : r!.necesito!
        ? 1
        : 0;
    _rego = r?.rego == null
        ? -1
        : r!.rego!
        ? 1
        : 0;
    _lamina.text = r?.laminaMm == null ? '' : numeroLimpio(r!.laminaMm!);
    _necesito0 = _necesito;
    _rego0 = _rego;
    _lamina0 = _lamina.text.trim();
    _error = null;
  }

  @override
  void dispose() {
    _volumen.dispose();
    _lamina.dispose();
    super.dispose();
  }

  /// Rango de fechas de la campaña elegida: de su inicio a su fin, o a hoy si
  /// sigue abierta.
  (DateTime, DateTime) _rango(AppEstado e) {
    final p = e.plantacionPorId(_campania);
    final hoy = soloFecha(e.hoy);
    if (p == null) return (DateTime(2000), hoy);
    return (soloFecha(p.fecha), soloFecha(p.fin ?? e.hoy));
  }

  bool _fueraDeRango(AppEstado e) {
    if (_campania == null) return false;
    final (min, max) = _rango(e);
    return _fecha!.isBefore(min) || _fecha!.isAfter(max);
  }

  Future<void> _elegirFecha() async {
    final e = Alcance.leer(context), t = e.txt;
    final (min, max) = _rango(e);
    final f = await elegirDiaOpcional(
      context,
      _fecha!,
      minimo: min,
      maximo: max,
      recortar: _fueraDeRango(e),
    );
    if (f == null || !mounted || f == _fecha) return;
    void aplicar() => setState(() {
      _fecha = f;
      _cargar();
    });
    if (_riegoSucio || _suministroSucio) {
      confirmar(
        context,
        titulo: t.bilingue('¿Cambiar de fecha?', 'Change the date?'),
        mensaje: t.bilingue(
          'Lo que escribiste y no guardaste se perderá.',
          'What you typed and did not save will be lost.',
        ),
        accion: t.bilingue('Cambiar', 'Change'),
        cancelar: t.bilingue('Seguir aquí', 'Stay here'),
        alConfirmar: aplicar,
      );
    } else {
      aplicar();
    }
  }

  void _cambiarPlantacion(String id) {
    final t = Alcance.leer(context).txt;
    if (id == _campania) return;
    void aplicar() => setState(() {
      _campania = id;
      _cargar(soloRiego: true);
    });
    if (_riegoSucio) {
      confirmar(
        context,
        titulo: t.bilingue('¿Cambiar de plantación?', 'Change planting?'),
        mensaje: t.bilingue(
          'Lo que escribiste del riego y no guardaste se perderá.',
          'What you typed about irrigation and did not save will be lost.',
        ),
        accion: t.bilingue('Cambiar', 'Change'),
        cancelar: t.bilingue('Seguir aquí', 'Stay here'),
        alConfirmar: aplicar,
      );
    } else {
      aplicar();
    }
  }

  Future<void> _guardar() async {
    final e = Alcance.leer(context);
    final destino = e.plantacionPorId(_campania);
    if (destino == null) return;
    double? numero(TextEditingController c) =>
        double.tryParse(c.text.trim().replaceAll(',', '.'));
    final volumen = _disponibilidad == DisponibilidadAgua.si
        ? numero(_volumen)
        : null;
    final lamina = _rego == 1 ? numero(_lamina) : null;
    if (_disponibilidad == DisponibilidadAgua.si &&
            _volumen.text.trim().isNotEmpty &&
            (volumen == null || !volumen.isFinite || volumen < 0) ||
        _rego == 1 &&
            _lamina.text.trim().isNotEmpty &&
            (lamina == null || !lamina.isFinite || lamina <= 0)) {
      setState(() => _error = e.txt.datosAguaInvalidos);
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await e.guardarAgua(
        SuministroAgua(
          fecha: _fecha!,
          disponibilidad: _disponibilidad,
          volumenM3: volumen,
        ),
        RegistroRiego(
          loteId: destino.loteId,
          campaniaId: destino.id,
          fecha: _fecha!,
          necesito: _necesito < 0 ? null : _necesito == 1,
          rego: _rego < 0 ? null : _rego == 1,
          laminaMm: lamina,
        ),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is FormatException ? error.message : e.txt.noSeGuardo;
          _guardando = false;
        });
      }
    }
  }

  void _borrar(RegistroRiego r) {
    final e = Alcance.leer(context), t = e.txt;
    confirmar(
      context,
      titulo: t.bilingue('Borrar este registro', 'Delete this record'),
      mensaje: t.bilingue(
        'Se borrará el riego de esta plantación en esta fecha. El dato de agua de la finca se queda. No se puede deshacer.',
        'The irrigation of this planting on this date will be deleted. The farm water entry stays. This cannot be undone.',
      ),
      accion: t.borrar,
      cancelar: t.cancelar,
      alConfirmar: () async {
        await e.borrarRiego(r);
        if (mounted) setState(() => _cargar(soloRiego: true));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    final opciones = {-1: t.sinDato, 1: t.si, 0: t.no};
    final destino = e.plantacionPorId(_campania);
    final guardado = destino == null
        ? null
        : e.riegoDe(destino.loteId, _fecha!, campaniaId: destino.id);
    final fueraDeRango = _fueraDeRango(e);
    final todoSinDato =
        _disponibilidad == DisponibilidadAgua.desconocida &&
        _necesito < 0 &&
        _rego < 0;
    final nadaGuardado = guardado == null && e.suministroDe(_fecha!) == null;
    final String? motivo = _campania == null
        ? t.bilingue(
            'Elige la plantación que recibió el riego',
            'Choose the planting that received the irrigation',
          )
        : fueraDeRango
        ? t.bilingue(
            'Esa fecha está fuera de la plantación. Elige otra fecha.',
            'That date is outside this planting. Choose another date.',
          )
        : todoSinDato && nadaGuardado
        ? t.bilingue('No hay nada que guardar', 'There is nothing to save')
        : null;
    Widget pregunta(
      String texto,
      String clave,
      int valor,
      ValueChanged<int> cambiar,
    ) => Padding(
      padding: const EdgeInsets.all(Espacio.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(texto, style: Texto.cuerpo(context)),
          const SizedBox(height: 10),
          Selector<int>(
            key: ValueKey(clave),
            opciones: opciones,
            valor: valor,
            alCambiar: cambiar,
          ),
        ],
      ),
    );
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.registroAgua),
        previousPageTitle: t.atras,
        border: null,
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
                        key: const Key('elegir-plantacion-riego'),
                        titulo: t.bilingue(
                          'Plantación que recibió el riego',
                          'Planting that received irrigation',
                        ),
                        detalle: destino == null
                            ? t.bilingue('Elegir plantación', 'Choose planting')
                            : t.nombrePlantacion(destino),
                        icono: CupertinoIcons.tree,
                        alPulsar: widget.campaniaId != null
                            ? null
                            : () async {
                                final id = await emergentes.elegirOpcion<String>(
                                  context,
                                  titulo: t.bilingue(
                                    '¿Qué plantación?',
                                    'Which planting?',
                                  ),
                                  seleccionada: _campania,
                                  opciones: [
                                    for (final p in e.plantaciones.where(
                                      (p) => p.tieneRiego,
                                    ))
                                      emergentes.OpcionHoja(
                                        valor: p.id,
                                        texto:
                                            '${t.nombrePlantacion(p)} · ${t.fechaCorta(p.fecha)} · ${t.bilingue('Lote', 'Plot')} ${e.lotes.indexWhere((l) => l.id == p.loteId) + 1}',
                                        icono: CupertinoIcons.tree,
                                      ),
                                  ],
                                );
                                if (id != null && context.mounted) {
                                  _cambiarPlantacion(id);
                                }
                              },
                      ),
                    ],
                  ),

                  Grupo(
                    children: [
                      Fila(
                        titulo: t.fechaObservacion,
                        detalle: t.fechaLarga(_fecha!),
                        icono: CupertinoIcons.calendar,
                        alPulsar: _elegirFecha,
                      ),
                    ],
                  ),
                  Rotulo(t.aguaFinca),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Espacio.l),
                    child: Text(
                      t.bilingue(
                        'La fuente de agua es compartida por la finca.',
                        'The water source is shared by the farm.',
                      ),
                      style: Texto.nota(context),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(Espacio.m),
                    child: Selector<DisponibilidadAgua>(
                      key: const Key('disponibilidad-agua'),
                      opciones: {
                        for (final d in DisponibilidadAgua.values)
                          d: t.nombreDisponibilidad(d),
                      },
                      valor: _disponibilidad,
                      alCambiar: (d) => setState(() => _disponibilidad = d),
                    ),
                  ),
                  if (_disponibilidad == DisponibilidadAgua.si)
                    Grupo(
                      children: [
                        Campo(
                          key: const Key('agua-volumen'),
                          titulo: t.saldoM3,
                          controlador: _volumen,
                          ejemplo: t.opcional,
                          teclado: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ],
                    ),
                  if (_campania != null) ...[
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Espacio.l,
                        Espacio.m,
                        Espacio.l,
                        Espacio.s,
                      ),
                      child: Text(
                        t.bilingue(
                          '«¿Necesitabas regar?» es si el cultivo pedía agua. «¿Regaste?» es si de verdad le echaste agua.',
                          '“Did you need to irrigate?” is whether the crop needed water. “Did you irrigate?” is whether you actually applied water.',
                        ),
                        key: const Key('explica-riego'),
                        style: Texto.nota(context),
                      ),
                    ),
                    Grupo(
                      children: [
                        pregunta(
                          t.bilingue(
                            '¿Necesitabas regar?',
                            'Did you need to irrigate?',
                          ),
                          t.necesitoRiego,
                          _necesito,
                          (v) => setState(() => _necesito = v),
                        ),
                        pregunta(
                          t.bilingue('¿Regaste?', 'Did you irrigate?'),
                          t.regasteFecha,
                          _rego,
                          (v) => setState(() => _rego = v),
                        ),
                        if (_rego == 1)
                          Campo(
                            key: const Key('agua-lamina'),
                            titulo: t.laminaMm,
                            controlador: _lamina,
                            ejemplo: t.opcional,
                            teclado: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                          ),
                      ],
                    ),
                  ],
                  if (guardado != null)
                    CupertinoButton(
                      key: const Key('borrar-riego'),
                      onPressed: () => _borrar(guardado),
                      child: Text(
                        t.bilingue(
                          'Borrar este registro',
                          'Delete this record',
                        ),
                        style: letra(
                          18,
                          peso: 600,
                          color: Paleta.de(context, Paleta.rojo),
                        ),
                      ),
                    ),
                  SeccionDesplegable(
                    titulo: t.bilingue(
                      'Ayuda sobre el agua',
                      'Help with water',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(Espacio.l),
                        child: Text(
                          '${t.aguaCompartidaAyuda}\n\n${t.riegoDiarioAyuda}',
                          style: Texto.nota(context),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PieGuardar(
              texto: t.guardar,
              alPulsar: _guardando || motivo != null ? null : _guardar,
              error: _error,
              motivo: _guardando ? null : motivo,
            ),
          ],
        ),
      ),
    );
  }
}
