import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import '../lenguas.dart';
import 'lenguas.dart';
import 'parcela.dart';
import 'plantacion.dart';
import 'tema.dart';

/// Ajustes: parcela, plantación, idioma, clima y fuentes.
class PestanaAjustes extends StatelessWidget {
  const PestanaAjustes({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final parcela = estado.parcela!;
    final raiz = Navigator.of(context, rootNavigator: true);

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(largeTitle: Text(t.ajustes), border: null),
          SliverList.list(children: [
            const SizedBox(height: Espacio.s),
            Grupo(children: [
              Fila(
                titulo: parcela.nombre,
                detalle: '${parcela.latitud.toStringAsFixed(4)}, ${parcela.longitud.toStringAsFixed(4)}'
                    '${parcela.elevacion == null ? '' : ' · ${parcela.elevacion!.round()} m'}',
                icono: CupertinoIcons.location,
                alPulsar: () => raiz.push(CupertinoPageRoute<void>(builder: (_) => const PantallaParcela())),
              ),
            ]),
            Rotulo(t.plantaciones),
            Grupo(children: [
              for (final p in estado.plantaciones)
                Fila(
                  titulo: t.nombrePlantacion(p),
                  detalle: '${t.fechaLarga(p.fecha)} · ${t.nombreRiego(p.riego)}',
                  icono: CupertinoIcons.tree,
                  alPulsar: () => raiz.push(CupertinoPageRoute<void>(builder: (_) => PantallaPlantacion(id: p.id))),
                ),
            ]),
            Rotulo(t.idioma),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
              child: Selector<String>(
                opciones: const {'es': 'Español', 'en': 'English'},
                valor: t.esMaya ? null : estado.idioma,
                alCambiar: (v) => Alcance.leer(context).cambiarIdioma(v),
              ),
            ),
            Rotulo(t.lenguasMayasRotulo),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
              child: Selector<String>(
                opciones: {for (final l in lenguasMayas) l.codigo: l.nombre},
                valor: t.esMaya ? estado.idioma : null,
                alCambiar: (v) => Alcance.leer(context).cambiarIdioma(v),
              ),
            ),
            if (t.esMaya) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(Espacio.m, Espacio.s, Espacio.m, Espacio.s),
                child: AvisoBorrador(t.avisoBorrador),
              ),
              Grupo(children: [
                Fila(
                  titulo: t.palabrasEn,
                  icono: CupertinoIcons.textformat,
                  alPulsar: () => raiz.push(CupertinoPageRoute<void>(builder: (_) => const PantallaPalabras())),
                ),
              ]),
            ],
            Rotulo(t.unidades),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
              child: Selector<Unidad>(
                opciones: {for (final u in Unidad.values) u: t.nombreUnidad(u)},
                valor: estado.unidad,
                alCambiar: (v) => Alcance.leer(context).cambiarUnidad(v),
              ),
            ),
            Rotulo(t.datos),
            Grupo(children: [
              Fila(
                titulo: estado.sincronizando ? t.sincronizando : t.sincronizar,
                detalle: t.soloWifi,
                icono: CupertinoIcons.arrow_clockwise,
                final_: estado.sincronizando ? const CupertinoActivityIndicator() : null,
                alPulsar: estado.sincronizando ? null : () => Alcance.leer(context).sincronizar(),
              ),
              Fila(
                titulo: t.metodos,
                icono: CupertinoIcons.book,
                alPulsar: () => raiz.push(CupertinoPageRoute<void>(builder: (_) => const PantallaMetodos())),
              ),
            ]),
            const SizedBox(height: Espacio.l),
            Grupo(children: [
              Fila(
                titulo: t.borrarDatos,
                icono: CupertinoIcons.trash,
                colorIcono: Paleta.de(context, Paleta.rojo),
                alPulsar: () => confirmar(
                  context,
                  titulo: t.borrarDatos,
                  mensaje: t.borrarPregunta,
                  accion: t.borrar,
                  cancelar: t.cancelar,
                  alConfirmar: () => Alcance.leer(context).borrarTodo(),
                ),
              ),
            ]),
            const SizedBox(height: Espacio.xl),
          ]),
        ],
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
      navigationBar: CupertinoNavigationBar(middle: Text(t.metodos), previousPageTitle: t.atras, border: null),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espacio.m, Espacio.m, Espacio.m, Espacio.xl),
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
                      Text(cuerpo, style: Texto.nota(context).copyWith(fontSize: 15, height: 1.45)),
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
}) =>
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(titulo),
        content: Text(mensaje),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(cancelar)),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.of(ctx).pop();
              alConfirmar();
            },
            child: Text(accion),
          ),
        ],
      ),
    );
