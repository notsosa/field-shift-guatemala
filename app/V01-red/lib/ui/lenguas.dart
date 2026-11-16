import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../lenguas.dart';
import '../textos.dart';
import 'tema.dart';

/// Aviso de que la traducción maya es un borrador. Una línea compacta en Hoy;
/// completo en Ajustes y en el glosario.
class AvisoBorrador extends StatelessWidget {
  const AvisoBorrador(this.texto, {super.key, this.compacto = false});

  final String texto;
  final bool compacto;

  @override
  Widget build(BuildContext context) {
    final ambar = Paleta.de(context, Paleta.ambar);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(CupertinoIcons.info, size: compacto ? 14 : 16, color: ambar),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            texto,
            key: const Key('aviso_borrador'),
            style: compacto ? letra(12, color: Paleta.de(context, Paleta.secundario), alto: 1.3) : Texto.nota(context),
          ),
        ),
      ],
    );
  }
}

/// Todas las palabras del glosario en la lengua activa, con el español al
/// lado y el resultado del cotejo.
class PantallaPalabras extends StatelessWidget {
  const PantallaPalabras({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final lengua = estado.idioma;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(middle: Text(t.palabrasEn), previousPageTitle: t.atras, border: null),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(Espacio.m, Espacio.m, Espacio.m, Espacio.xl),
          children: [
            if (t.esMaya) ...[
              AvisoBorrador(t.avisoBorrador),
              const SizedBox(height: Espacio.s),
              Text(t.avisoRevision, style: Texto.nota(context)),
              const SizedBox(height: Espacio.m),
              for (final termino in glosario)
                Padding(
                  padding: const EdgeInsets.only(bottom: Espacio.s),
                  child: Tarjeta(
                    padding: const EdgeInsets.symmetric(horizontal: Espacio.borde, vertical: 12),
                    child: _fila(context, t, termino, lengua),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fila(BuildContext context, Txt t, Termino termino, String lengua) {
    final palabra = termino.palabras[lengua];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(palabra?.texto ?? termino.es, style: Texto.fuerte(context)),
              Text(termino.es, style: Texto.nota(context)),
            ],
          ),
        ),
        const SizedBox(width: Espacio.s),
        Expanded(
          flex: 5,
          child: Text(
            palabra == null ? t.sinBorrador : t.estadoCotejo(palabra.cotejo),
            style: Texto.nota(context),
          ),
        ),
      ],
    );
  }
}
