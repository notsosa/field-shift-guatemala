import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import '../eventos.dart';
import 'tema.dart';
import 'bitacora.dart';
import 'registro.dart' show PantallaRegistro;
import 'agua.dart';
import 'plantacion.dart';
import 'siembra_v3.dart';
import 'cafe_red.dart';
import 'ajustes.dart' show confirmar;
import 'hoy.dart' show PantallaDetalleAgua, PestanaHoy;
import '../motor/recomendador.dart' show NivelAgua;

String identificarPlantacion(AppEstado e, Plantacion p) =>
    '${e.txt.nombrePlantacion(p)} · ${e.txt.bilingue('Lote', 'Plot')} ${e.lotes.indexWhere((l) => l.id == p.loteId) + 1}';

/// Única ficha de manejo de un lote, accesible desde Finca y desde el mapa.
/// Aquí, y solo aquí, se termina un cultivo o se inicia otro en el lote.
class PantallaMiPlantacion extends StatefulWidget {
  const PantallaMiPlantacion({super.key, required this.loteId});
  final String loteId;
  @override
  State<PantallaMiPlantacion> createState() => _MiPlantacion();
}

class _MiPlantacion extends State<PantallaMiPlantacion> {
  String? _error;
  Future<void> _terminar(Plantacion p) async {
    final e = Alcance.leer(context), t = Alcance.leer(context).txt;
    // Si se cancela el selector, no se sigue al paso de confirmar.
    final fecha = await elegirDiaOpcional(context, e.hoy, minimo: p.fecha);
    if (!mounted || fecha == null) return;
    confirmar(
      context,
      titulo: t.bilingue('Terminar este cultivo', 'Finish this crop'),
      mensaje:
          '${t.nombrePlantacion(p)} · ${t.fechaLarga(fecha)}\n${t.bilingue('Sus registros se conservarán. Después podrás iniciar otro cultivo en este mismo lote.', 'Its records will be kept. You can then start another crop in this plot.')}',
      accion: t.bilingue('Terminar cultivo', 'Finish crop'),
      cancelar: t.cancelar,
      alConfirmar: () async {
        try {
          await e.cerrarCampania(p.id, fecha);
        } catch (error) {
          if (mounted) {
            setState(
              () => _error = error is FormatException
                  ? error.message
                  : t.noSeGuardo,
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    final activas = e.plantaciones
        .where((p) => p.loteId == widget.loteId)
        .toList();
    final p = activas.isEmpty ? null : activas.single;
    final loteIdx = e.lotes.indexWhere((l) => l.id == widget.loteId);
    final numero = loteIdx + 1;
    if (p == null && (loteIdx < 0 || e.lotePorId(widget.loteId) == null)) {
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(t.bilingue('Lote no disponible', 'Plot unavailable')),
          previousPageTitle: t.atras,
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Espacio.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.bilingue('Lote no disponible', 'Plot unavailable'),
                  style: Texto.cuerpo(context),
                ),
                const SizedBox(height: Espacio.m),
                BotonPrincipal(
                  texto: t.atras,
                  alPulsar: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final r = p == null ? null : e.recomendacionDe(p);
    final hayAnteriores = e.campanias.any(
      (c) => c.loteId == widget.loteId && !c.activa,
    );
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(
          p == null
              ? '${t.bilingue('Lote', 'Plot')} $numero'
              : t.nombrePlantacion(p),
        ),
        previousPageTitle: t.atras,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Espacio.xl),
          children: [
            if (p != null && r != null) ...[
              const SizedBox(height: Espacio.s),
              Grupo(
                children: [
                  Fila(
                    key: const Key('ficha-resumen-agua'),
                    titulo: t.tituloNivel(r.nivel),
                    detalle: r.nivel == NivelAgua.sinDatos
                        ? t.sinDato
                        : t.porcentajeAgua((r.reserva * 100).round()),
                    icono: CupertinoIcons.circle_fill,
                    colorIcono: PestanaHoy.colorNivel(context, r.nivel),
                  ),
                  Fila(
                    titulo: t.bilingue(
                      'Ver detalle del agua',
                      'View water details',
                    ),
                    icono: CupertinoIcons.drop,
                    alPulsar: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => PantallaDetalleAgua(plantacionId: p.id),
                      ),
                    ),
                  ),
                ],
              ),
              TarjetaRedCafe(plantacion: p, recomendacion: r),
            ],
            Padding(
              padding: const EdgeInsets.all(Espacio.l),
              child: Text(
                '${t.bilingue('Lote', 'Plot')} $numero${p == null ? '' : ' · ${t.fechaLarga(p.fecha)}\n${t.nombreRiego(p.riego)}'}',
                style: Texto.cuerpo(context),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
              child: BotonPrincipal(
                texto: p == null
                    ? t.bilingue('Iniciar un cultivo aquí', 'Start a crop here')
                    : t.bilingue('Registrar actividad', 'Record activity'),
                alPulsar: () => Navigator.of(context).push(
                  CupertinoPageRoute<void>(
                    builder: (_) => p == null
                        ? PantallaPlantacion(loteId: widget.loteId)
                        : PantallaActividad(plantacionId: p.id),
                  ),
                ),
              ),
            ),
            const SizedBox(height: Espacio.m),
            Grupo(
              children: [
                if (p == null)
                  Fila(
                    key: const Key('lote-siembra-v3'),
                    titulo: t.bilingue(
                      'Sugerir cultivo con red neuronal',
                      'Suggest crop with neural network',
                    ),
                    icono: CupertinoIcons.leaf_arrow_circlepath,
                    alPulsar: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) =>
                            PantallaSiembraV3(loteId: widget.loteId),
                      ),
                    ),
                  ),
                if (p != null)
                  Fila(
                    titulo: t.bilingue('Ver registros', 'View records'),
                    icono: CupertinoIcons.square_list,
                    alPulsar: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => PantallaBitacora(campaniaId: p.id),
                      ),
                    ),
                  ),
                if (p != null)
                  Fila(
                    titulo: t.bilingue(
                      'Datos de la plantación',
                      'Planting details',
                    ),
                    detalle: t.bilingue(
                      'Cultivo, fecha, riego y suelo',
                      'Crop, date, irrigation and soil',
                    ),
                    icono: CupertinoIcons.pencil,
                    alPulsar: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => PantallaPlantacion(id: p.id),
                      ),
                    ),
                  ),
                if (hayAnteriores)
                  Fila(
                    titulo: t.bilingue(
                      'Cultivos anteriores de este lote',
                      'Previous crops in this plot',
                    ),
                    icono: CupertinoIcons.clock,
                    alPulsar: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) =>
                            PantallaCampanias(loteId: widget.loteId),
                      ),
                    ),
                  ),
              ],
            ),
            if (p != null)
              SeccionDesplegable(
                titulo: t.bilingue('Más opciones', 'More options'),
                children: [
                  Grupo(
                    children: [
                      Fila(
                        titulo: t.bilingue(
                          'Terminar este cultivo',
                          'Finish this crop',
                        ),
                        detalle: t.bilingue(
                          'Conserva los registros y libera el lote.',
                          'Keeps records and frees this plot.',
                        ),
                        icono: CupertinoIcons.check_mark,
                        alPulsar: () => _terminar(p),
                      ),
                    ],
                  ),
                ],
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Text(_error!, style: Texto.nota(context)),
              ),
          ],
        ),
      ),
    );
  }
}

/// Una tarea a la vez: contexto explícito, actividad y formulario específico.
class PantallaActividad extends StatefulWidget {
  const PantallaActividad({super.key, this.plantacionId});
  final String? plantacionId;
  @override
  State<PantallaActividad> createState() => _Actividad();
}

class _Actividad extends State<PantallaActividad> {
  String? _id;
  bool _iniciada = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_iniciada) {
      _id = widget.plantacionId;
      _iniciada = true;
    }
  }

  Future<void> _elegir() async {
    final e = Alcance.leer(context);
    final id = await elegirOpcion(
      context,
      e.txt.bilingue('¿En qué plantación?', 'Which planting?'),
      {for (final p in e.plantaciones) p.id: identificarPlantacion(e, p)},
      seleccionada: _id,
    );
    if (id != null && mounted) setState(() => _id = id);
  }

  Future<void> _evento(Plantacion p, Map<TipoEvento, String> tipos) async {
    final e = Alcance.leer(context);
    final tipo = tipos.length == 1
        ? tipos.keys.single
        : await elegirOpcion(
            context,
            e.txt.bilingue(
              '¿Qué quieres anotar?',
              'What would you like to record?',
            ),
            tipos,
          );
    if (!mounted || tipo == null) return;
    await Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PantallaEvento(campaniaId: p.id, tipoInicial: tipo),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    final p = e.plantacionPorId(_id);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.bilingue('Registrar actividad', 'Record activity')),
        previousPageTitle: t.atras,
      ),
      child: SafeArea(
        child: ListView(
          children: [
            Rotulo(t.bilingue('Plantación', 'Planting')),
            Grupo(
              children: [
                Fila(
                  key: const Key('actividad-plantacion'),
                  titulo: p == null
                      ? t.bilingue('Elegir plantación', 'Choose planting')
                      : identificarPlantacion(e, p),
                  detalle: p == null
                      ? t.bilingue(
                          'Primero elige dónde trabajaste.',
                          'First choose where you worked.',
                        )
                      : t.fechaLarga(p.fecha),
                  icono: CupertinoIcons.tree,
                  alPulsar: widget.plantacionId == null ? _elegir : null,
                ),
              ],
            ),
            if (p != null) ...[
              Rotulo(t.bilingue('¿Qué hiciste?', 'What did you do?')),
              Grupo(
                children: [
                  Fila(
                    key: const Key('actividad-resumen'),
                    titulo: t.bilingue(
                      'Resumen de la semana',
                      'Summary of the week',
                    ),
                    detalle: t.bilingue(
                      'Si no recuerdas el día exacto.',
                      'If you do not remember the exact day.',
                    ),
                    icono: CupertinoIcons.calendar,
                    alPulsar: () => Navigator.of(context).push(
                      CupertinoPageRoute<void>(
                        builder: (_) => PantallaRegistro(plantacionId: p.id),
                      ),
                    ),
                  ),
                  if (p.tieneRiego)
                    Fila(
                      titulo: t.bilingue('Riego', 'Irrigation'),
                      icono: CupertinoIcons.drop,
                      alPulsar: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => PantallaAgua(campaniaId: p.id),
                        ),
                      ),
                    ),
                  Fila(
                    titulo: t.bilingue('Cosecha', 'Harvest'),
                    icono: CupertinoIcons.bag,
                    alPulsar: () => _evento(p, {
                      TipoEvento.cosecha: t.bilingue('Cosecha', 'Harvest'),
                    }),
                  ),
                  Fila(
                    titulo: t.bilingue('Plaga', 'Pest'),
                    icono: CupertinoIcons.ant,
                    alPulsar: () => _evento(p, {
                      TipoEvento.plaga: t.bilingue(
                        'Vi una plaga',
                        'I saw a pest',
                      ),
                    }),
                  ),
                  Fila(
                    titulo: t.bilingue(
                      'Abono o tratamiento',
                      'Fertilizer or treatment',
                    ),
                    icono: CupertinoIcons.leaf_arrow_circlepath,
                    alPulsar: () => _evento(p, {
                      TipoEvento.fertilizacion: t.bilingue(
                        'Apliqué abono o fertilizante',
                        'I applied fertilizer',
                      ),
                      TipoEvento.tratamiento: t.bilingue(
                        'Apliqué un tratamiento',
                        'I applied a treatment',
                      ),
                    }),
                  ),
                ],
              ),
              SeccionDesplegable(
                titulo: t.bilingue('Otras', 'Other'),
                children: [
                  Grupo(
                    children: [
                      Fila(
                        titulo: t.bilingue('Pérdida', 'Loss'),
                        icono: CupertinoIcons.exclamationmark_triangle,
                        alPulsar: () => _evento(p, {
                          TipoEvento.perdida: t.bilingue('Pérdida', 'Loss'),
                        }),
                      ),
                      Fila(
                        titulo: t.bilingue('Observación', 'Observation'),
                        icono: CupertinoIcons.eye,
                        alPulsar: () => _evento(p, {
                          TipoEvento.observacion: nombreEvento(
                            e,
                            TipoEvento.observacion,
                          ),
                        }),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
