import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import 'tema.dart';

/// Abre el detalle de una plaga (fuente, lugar, fecha y límite del registro).
void abrirDetallePlaga(BuildContext context, String cultivoId, String tipoId) {
  Navigator.of(context).push(
    CupertinoPageRoute<void>(
      builder: (_) => PantallaPlaga(cultivoId: cultivoId, tipoId: tipoId),
    ),
  );
}

/// Botón de información que abre el detalle; no aparece si la plaga no tiene detalle.
class BotonDetallePlaga extends StatelessWidget {
  const BotonDetallePlaga({
    super.key,
    required this.cultivoId,
    required this.tipoId,
  });

  final String cultivoId;
  final String tipoId;

  @override
  Widget build(BuildContext context) {
    if (detallePlaga(cultivoId, tipoId) == null) return const SizedBox.shrink();
    final t = Alcance.de(context).txt;
    return Semantics(
      button: true,
      label: t.verFuente,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 44),
        onPressed: () => abrirDetallePlaga(context, cultivoId, tipoId),
        child: Icon(
          CupertinoIcons.info_circle,
          size: 24,
          color: Paleta.de(context, Paleta.verde),
        ),
      ),
    );
  }
}

/// Lista de plagas del cultivo para elegir cuál se reporta, con el botón de
/// detalle en cada una y la nota fija de que un registro documentado no es
/// presencia en la parcela. Va dentro de un [Grupo].
class ListaPlagas extends StatelessWidget {
  const ListaPlagas({
    super.key,
    required this.cultivoId,
    required this.valor,
    required this.alCambiar,
  });

  final String cultivoId;
  final String valor;
  final ValueChanged<String> alCambiar;

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    final verde = Paleta.de(context, Paleta.verde);
    final tipos = tiposPlagaDe(cultivoId);
    final hayRegistros = tipos.any(
      (x) => x.origen == OrigenPlaga.investigacion,
    );

    Widget fila(TipoPlaga tipo) {
      final elegido = tipo.id == valor;
      final taxones = tipo.registros.map((r) => r.taxon).join(', ');
      final subtitulo = switch (tipo.origen) {
        OrigenPlaga.investigacion => taxones,
        OrigenPlaga.caficultor => t.origenCaficultor,
        OrigenPlaga.otra => '',
      };
      return Row(
        children: [
          Expanded(
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              minimumSize: const Size(44, 52),
              alignment: Alignment.centerLeft,
              onPressed: () => alCambiar(tipo.id),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(Espacio.borde, 10, 0, 10),
                child: Row(
                  children: [
                    Icon(
                      elegido
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 24,
                      color: elegido ? verde : Paleta.de(context, Paleta.secundario),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t.nombreTipoPlaga(tipo.id),
                            style: Texto.cuerpo(context),
                          ),
                          if (subtitulo.isNotEmpty)
                            Text(
                              subtitulo,
                              style: Texto.nota(context).copyWith(
                                fontStyle:
                                    tipo.origen == OrigenPlaga.investigacion
                                    ? FontStyle.italic
                                    : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          BotonDetallePlaga(cultivoId: cultivoId, tipoId: tipo.id),
          if (detallePlaga(cultivoId, tipo.id) == null)
            const SizedBox(width: Espacio.borde),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Espacio.borde,
            14,
            Espacio.borde,
            4,
          ),
          child: Text(t.tipoPlaga, style: Texto.cuerpo(context)),
        ),
        for (final tipo in tipos) fila(tipo),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Espacio.borde,
            4,
            Espacio.borde,
            14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(
                  CupertinoIcons.info,
                  size: 16,
                  color: Paleta.de(context, Paleta.secundario),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hayRegistros
                      ? t.notaRegistroNoPresencia
                      : (sinRegistroConfirmado(cultivoId)
                            ? t.sinRegistroLocal
                            : t.notaListaCaficultor),
                  style: Texto.nota(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Detalle de una plaga: nombre, taxón, daño, dónde y cuándo se documentó, la
/// fuente y el límite del registro. Todo sale del archivo de la investigación.
class PantallaPlaga extends StatelessWidget {
  const PantallaPlaga({
    super.key,
    required this.cultivoId,
    required this.tipoId,
  });

  final String cultivoId;
  final String tipoId;

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    final verde = Paleta.de(context, Paleta.verde);
    final tipo = detallePlaga(cultivoId, tipoId);

    Widget dato(String etiqueta, String valor, {Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Espacio.borde,
        vertical: 10,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(etiqueta.toUpperCase(), style: Texto.etiqueta(context)),
          const SizedBox(height: 4),
          Text(valor, style: Texto.cuerpo(context).copyWith(color: color)),
        ],
      ),
    );

    Widget aviso(String texto, IconData icono) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
      child: Tarjeta(
        color: Paleta.de(context, Paleta.tenue),
        padding: const EdgeInsets.all(Espacio.m),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              CupertinoIcons.info,
              size: 20,
              color: Paleta.de(context, Paleta.secundario),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(texto, style: Texto.cuerpo(context))),
          ],
        ),
      ),
    );

    final cuerpo = <Widget>[];
    if (tipo == null) {
      cuerpo.add(
        Padding(
          padding: const EdgeInsets.all(Espacio.borde),
          child: Text(t.plagaSinInformacion, style: Texto.nota(context)),
        ),
      );
    } else {
      cuerpo.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Espacio.borde + Espacio.m,
            Espacio.s,
            Espacio.borde + Espacio.m,
            Espacio.m,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.nombreTipoPlaga(tipo.id), style: Texto.titulo(context)),
              const SizedBox(height: 4),
              Text(
                '${t.nombreCultivo(cultivoId)} · ${tipo.origen == OrigenPlaga.caficultor ? t.origenCaficultor : t.origenInvestigacion}',
                style: Texto.nota(context),
              ),
            ],
          ),
        ),
      );
      cuerpo.add(aviso(t.notaRegistroNoPresencia, CupertinoIcons.location));
      if (tipo.origen == OrigenPlaga.caficultor) {
        cuerpo.add(const SizedBox(height: Espacio.m));
        cuerpo.add(aviso(t.detalleCaficultor, CupertinoIcons.book));
      }
      if (tipo.registros.isNotEmpty) {
        cuerpo.add(Rotulo(t.registrosDocumentados(tipo.registros.length)));
      }
      for (final r in tipo.registros) {
        cuerpo.add(
          Padding(
            padding: const EdgeInsets.only(bottom: Espacio.m),
            child: Grupo(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: Espacio.borde,
                    vertical: 14,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.taxon,
                        style: Texto.fuerte(context)
                            .copyWith(fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        t.resolucionTaxon(r.resolucion),
                        style: Texto.nota(context),
                      ),
                    ],
                  ),
                ),
                dato(t.danio, r.danio.de(t.en)),
                dato(t.etiquetaEtapa(r.etapa.es), r.etapa.de(t.en)),
                dato(t.dondeDocumentado, r.lugar.de(t.en)),
                dato(t.cuandoDocumentado, r.periodo.de(t.en)),
                for (final ref in r.referencias)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: Espacio.borde,
                      vertical: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.fuente.toUpperCase(),
                          style: Texto.etiqueta(context),
                        ),
                        const SizedBox(height: 4),
                        Text(ref.fuente.cita, style: Texto.cuerpo(context)),
                        const SizedBox(height: 2),
                        Text(ref.localizador, style: Texto.nota(context)),
                        const SizedBox(height: 6),
                        Text(
                          ref.fuente.url,
                          style: letra(13, color: verde, alto: 1.35),
                        ),
                      ],
                    ),
                  ),
                dato(t.limiteRegistro, r.limite.de(t.en)),
              ],
            ),
          ),
        );
      }
    }

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.plaga),
        previousPageTitle: t.atras,
        border: null,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: Espacio.xl),
          children: cuerpo,
        ),
      ),
    );
  }
}
