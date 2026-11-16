import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import 'tema.dart';
import 'bitacora.dart';
import 'emergentes.dart' show confirmarAccion;
import 'finca.dart' show PantallaMapaFinca;

/// Preferencias de la aplicación; los cultivos se manejan desde Finca.
class PestanaAjustes extends StatelessWidget {
  const PestanaAjustes({super.key});
  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    final raiz = Navigator.of(context, rootNavigator: true);
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(t.ajustes),
            border: null,
          ),
          SliverList.list(
            children: [
              Grupo(
                children: [
                  Fila(
                    titulo: t.idioma,
                    detalle: e.idioma == 'es' ? 'Español' : 'English',
                    icono: CupertinoIcons.globe,
                    alPulsar: () async {
                      final v = await elegirOpcion(
                        context,
                        t.idioma,
                        const {'es': 'Español', 'en': 'English'},
                        seleccionada: e.idioma,
                      );
                      if (v != null) await e.cambiarIdioma(v);
                    },
                  ),
                  Fila(
                    titulo: t.unidades,
                    detalle: t.nombreUnidad(e.unidad),
                    icono: CupertinoIcons.square_grid_2x2,
                    alPulsar: () async {
                      final v = await elegirOpcion(
                        context,
                        t.unidades,
                        {
                          for (final u in Unidad.values) u: t.nombreUnidad(u),
                        },
                        seleccionada: e.unidad,
                      );
                      if (v != null) await e.cambiarUnidad(v);
                    },
                  ),
                ],
              ),
              const SizedBox(height: Espacio.m),
              Grupo(
                children: [
                  Fila(
                    titulo: t.bilingue(
                      'Ayuda y significado de los datos',
                      'Help and meaning of the data',
                    ),
                    icono: CupertinoIcons.question_circle,
                    alPulsar: () => raiz.push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const PantallaMetodos(),
                      ),
                    ),
                  ),
                  Fila(
                    titulo: t.bilingue(
                      'Opciones avanzadas',
                      'Advanced options',
                    ),
                    detalle: t.bilingue(
                      'Clima, copias y herramientas',
                      'Weather, copies and tools',
                    ),
                    icono: CupertinoIcons.slider_horizontal_3,
                    alPulsar: () => raiz.push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const PantallaOpcionesAvanzadas(),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PantallaOpcionesAvanzadas extends StatefulWidget {
  const PantallaOpcionesAvanzadas({super.key});
  @override
  State<PantallaOpcionesAvanzadas> createState() => _OpcionesAvanzadas();
}

class _OpcionesAvanzadas extends State<PantallaOpcionesAvanzadas> {
  String? _mensaje;
  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.bilingue('Opciones avanzadas', 'Advanced options')),
        previousPageTitle: t.atras,
      ),
      child: SafeArea(
        child: ListView(
          children: [
            Rotulo(t.clima),
            Grupo(
              children: [
                Fila(
                  titulo: e.sincronizando ? t.sincronizando : t.sincronizar,
                  detalle: t.soloWifi,
                  icono: CupertinoIcons.arrow_clockwise,
                  alPulsar: e.sincronizando
                      ? null
                      : () async {
                          final r = await e.sincronizar();
                          if (mounted) {
                            setState(
                              () => _mensaje = switch (r) {
                                ResultadoSync.ok => t.bilingue(
                                  'Clima actualizado.',
                                  'Weather updated.',
                                ),
                                ResultadoSync.sinWifi => t.sinWifi,
                                ResultadoSync.error => t.errorSync,
                              },
                            );
                          }
                        },
                ),
              ],
            ),
            Rotulo(t.bilingue('Copias y datos', 'Copies and data')),
            Grupo(
              children: [
                Fila(
                  titulo: t.bilingue('Paquete de datos', 'Data package'),
                  icono: CupertinoIcons.doc_text,
                  alPulsar: () => Navigator.of(context).push(
                    CupertinoPageRoute<void>(
                      builder: (_) => const PantallaPaquete(),
                    ),
                  ),
                ),
                Fila(
                  titulo: t.copiarGeoJson,
                  icono: CupertinoIcons.map,
                  alPulsar: () => PantallaMapaFinca.copiarGeoJson(context),
                ),
              ],
            ),
            if (_mensaje != null)
              Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Text(_mensaje!, style: Texto.nota(context)),
              ),
            Rotulo(t.bilingue('Borrar', 'Delete')),
            Grupo(
              children: [
                Fila(
                  titulo: t.borrarDatos,
                  detalle: t.bilingue(
                    'Quita la información de este teléfono.',
                    'Removes the information from this phone.',
                  ),
                  icono: CupertinoIcons.trash,
                  colorIcono: Paleta.de(context, Paleta.rojo),
                  alPulsar: () => confirmar(
                    context,
                    titulo: t.borrarDatos,
                    mensaje: t.borrarPregunta,
                    accion: t.borrar,
                    cancelar: t.cancelar,
                    alConfirmar: () async {
                      final nav = Navigator.of(context);
                      await e.borrarTodo();
                      if (nav.mounted) nav.popUntil((r) => r.isFirst);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: Espacio.xl),
          ],
        ),
      ),
    );
  }
}

/// Explica en lenguaje llano de dónde salen los números y sus límites.
class PantallaMetodos extends StatelessWidget {
  const PantallaMetodos({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.metodos),
        previousPageTitle: t.atras,
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            Espacio.m,
            Espacio.m,
            Espacio.m,
            Espacio.xl,
          ),
          children: [
            for (final (titulo, cuerpo) in t.metodosTexto)
              Padding(
                padding: const EdgeInsets.only(bottom: Espacio.m),
                child: Tarjeta(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titulo, style: Texto.fuerte(context)),
                      const SizedBox(height: 6),
                      Text(
                        cuerpo,
                        style: Texto.nota(context).copyWith(height: 1.45),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Pide confirmación antes de una acción que borra datos.
Future<void> confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String accion,
  required String cancelar,
  required VoidCallback alConfirmar,
}) async {
  final ok = await confirmarAccion(
    context,
    titulo: titulo,
    mensaje: mensaje,
    accion: accion,
    cancelar: cancelar,
    destructiva: true,
  );
  if (ok) alConfirmar();
}
