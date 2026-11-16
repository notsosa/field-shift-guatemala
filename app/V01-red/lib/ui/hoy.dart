import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart' show Sombra;
import '../motor/cafe.dart';
import '../motor/entradas_red.dart' show umbralEstresRed;
import '../motor/fuentes_cafe.dart';
import '../motor/fao56.dart';
import '../motor/recomendador.dart';
import 'finca.dart';
import 'graficos.dart';
import 'registro.dart';
import 'tema.dart';

/// Pantalla principal: cuánta agua le queda al cultivo y qué conviene hacer.
class PestanaHoy extends StatelessWidget {
  const PestanaHoy({super.key});

  static Color colorNivel(BuildContext c, NivelAgua n) => switch (n) {
        NivelAgua.sinDatos => Paleta.de(c, Paleta.secundario),
        NivelAgua.bien => Paleta.de(c, Paleta.verde),
        NivelAgua.atencion => Paleta.de(c, Paleta.ambar),
        NivelAgua.estres => Paleta.de(c, Paleta.rojo),
      };

  Future<void> _sincronizar(BuildContext context) async {
    final estado = Alcance.leer(context);
    final resultado = await estado.sincronizar();
    if (!context.mounted || resultado == ResultadoSync.ok) return;
    final t = estado.txt;
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(t.clima),
        content: Text(resultado == ResultadoSync.sinWifi ? t.sinWifi : t.errorSync),
        actions: [
          CupertinoDialogAction(onPressed: () => Navigator.of(ctx).pop(), child: Text(t.listo)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final r = estado.recomendacion;
    final plantacion = estado.plantacion!;
    final color = colorNivel(context, r.nivel);
    final sinDatos = r.nivel == NivelAgua.sinDatos;

    void abrirRegistro() => Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute<void>(fullscreenDialog: true, builder: (_) => const PantallaRegistro()),
        );

    Widget dato(String rotulo, String valor) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(rotulo.toUpperCase(), style: Texto.etiqueta(context)),
              const SizedBox(height: 6),
              Text(valor, style: letra(17, peso: 600, color: Paleta.de(context, Paleta.texto), espaciado: -0.2)),
            ],
          ),
        );

    final estadoClima = r.ultimoClima == null ? t.nuncaSincronizado : t.climaHasta(t.fechaCorta(r.ultimoClima!));
    final detalleClima = [if (r.diasEstimados > 0) t.estimados(r.diasEstimados), t.soloWifi].join(' · ');

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(t.hoy),
            border: null,
            trailing: estado.sincronizando
                ? const CupertinoActivityIndicator()
                : CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => _sincronizar(context),
                    child: const Icon(CupertinoIcons.arrow_clockwise, size: 22),
                  ),
          ),
          CupertinoSliverRefreshControl(onRefresh: () => _sincronizar(context)),
          SliverList.list(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.m, 0, Espacio.m, Espacio.m),
              child: const CambioPlantacion(),
            ),

            // Estado del agua y recomendación.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
              child: Tarjeta(
                padding: const EdgeInsets.fromLTRB(Espacio.borde, Espacio.xl, Espacio.borde, Espacio.l),
                child: Column(
                  children: [
                    AnilloAgua(fraccion: r.reserva, color: color, leyenda: t.aguaDisponible, vacio: sinDatos),
                    const SizedBox(height: Espacio.l),
                    Text(t.tituloNivel(r.nivel), style: Texto.titulo(context), textAlign: TextAlign.center),
                    const SizedBox(height: 6),
                    Text(
                      t.detalleNivel(r, plantacion.riego),
                      style: letra(16, color: Paleta.de(context, Paleta.secundario), alto: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    if (sinDatos) ...[
                      const SizedBox(height: Espacio.l),
                      BotonPrincipal(
                        texto: estado.sincronizando ? t.sincronizando : t.sincronizar,
                        alPulsar: estado.sincronizando ? null : () => _sincronizar(context),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            if (!sinDatos) ...[
              const SizedBox(height: Espacio.m),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
                child: Tarjeta(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      dato(t.etapa, t.nombreEtapa(r.etapa)),
                      if (r.diasACosecha != null && r.etapa != Etapa.cosechado) ...[
                        const SizedBox(width: Espacio.m),
                        dato(t.cosecha, t.enDias(r.diasACosecha!)),
                      ],
                      if (r.factorRendimiento != null) ...[
                        const SizedBox(width: Espacio.m),
                        dato(t.rendimiento, '${(r.factorRendimiento! * 100).round()} %'),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: Espacio.m),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
                child: Tarjeta(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.ultimosDias, style: Texto.fuerte(context)),
                      const SizedBox(height: 2),
                      Text(t.leyendaReserva, style: Texto.nota(context)),
                      const SizedBox(height: Espacio.m),
                      BarrasAgua(dias: r.ultimos),
                      const SizedBox(height: Espacio.m),
                      SizedBox(height: 0.5, child: ColoredBox(color: Paleta.de(context, Paleta.tenue))),
                      const SizedBox(height: Espacio.m),
                      Row(
                        children: [
                          dato('${t.lluvia} · 7 d', t.mm(r.lluviaSemana)),
                          const SizedBox(width: Espacio.m),
                          dato('${t.necesidad} · 7 d', t.mm(r.necesidadSemana)),
                        ],
                      ),
                      const SizedBox(height: Espacio.m),
                      Text(t.diasEstres(r.diasEstres), style: Texto.nota(context)),
                    ],
                  ),
                ),
              ),
              if (r.desdeRed && r.estresProx7 != null && r.estresProx14 != null) ...[
                const SizedBox(height: Espacio.m),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
                  child: _TarjetaProximosDias(r: r, cultivoId: plantacion.cultivoId),
                ),
              ],
              if (plantacion.cultivoId == cultivoCafe) ...[
                const SizedBox(height: Espacio.m),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
                  child: _TarjetaCafe(r: r, banano: plantacion.sombra == Sombra.bananoRegulado || plantacion.sombra == Sombra.bananoDenso),
                ),
              ],
            ],

            if (r.avisos.isNotEmpty) ...[
              Rotulo(t.porHacer),
              Grupo(children: [
                for (final a in r.avisos)
                  Fila(
                    titulo: t.tituloAviso(a),
                    detalle: t.detalleAviso(a),
                    icono: switch (a) {
                      Aviso.registroPendiente => CupertinoIcons.square_pencil,
                      Aviso.climaViejo => CupertinoIcons.cloud_download,
                      Aviso.plaga => CupertinoIcons.ant,
                      Aviso.fertilizar => CupertinoIcons.leaf_arrow_circlepath,
                      Aviso.cosechaCerca => CupertinoIcons.calendar,
                    },
                    colorIcono: a == Aviso.plaga ? Paleta.de(context, Paleta.ambar) : null,
                    alPulsar: switch (a) {
                      Aviso.registroPendiente => abrirRegistro,
                      Aviso.climaViejo => () => _sincronizar(context),
                      _ => null,
                    },
                  ),
              ]),
            ],

            Rotulo(t.clima),
            Grupo(children: [
              Fila(
                titulo: estadoClima,
                detalle: detalleClima,
                icono: CupertinoIcons.cloud_sun,
                colorIcono: Paleta.de(context, Paleta.azul),
              ),
              Fila(
                titulo: t.precision,
                detalle: t.precisionAyuda,
                icono: CupertinoIcons.scope,
                final_: Text(
                  t.nombrePrecision(r.precision),
                  style: letra(16, peso: 600, color: Paleta.de(context, Paleta.texto)),
                ),
              ),
            ]),

            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.borde + Espacio.m, Espacio.l, Espacio.borde + Espacio.m, Espacio.xl),
              child: Text(t.apoyaNoReemplaza, style: Texto.nota(context), textAlign: TextAlign.center),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Lo que estima la red del equipo para los próximos días. Solo se dibuja
/// donde la red se midió (ver `Recomendacion.desdeRed`).
class _TarjetaProximosDias extends StatelessWidget {
  const _TarjetaProximosDias({required this.r, required this.cultivoId});

  final Recomendacion r;
  final String cultivoId;

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    // El mismo umbral con que se midió la clase «hay estrés».
    final habraEstres = r.estresProx7! >= umbralEstresRed;
    final color = habraEstres ? Paleta.de(context, Paleta.ambar) : Paleta.de(context, Paleta.verde);
    return Tarjeta(
      key: const Key('tarjeta_proximos_dias'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.proximos7, style: Texto.fuerte(context)),
          const SizedBox(height: Espacio.s),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: Espacio.s),
                child: Icon(
                  habraEstres ? CupertinoIcons.exclamationmark_triangle : CupertinoIcons.checkmark_circle,
                  size: 20,
                  color: color,
                ),
              ),
              Expanded(
                child: Text(habraEstres ? t.estresEsperado : t.sinEstresEsperado, style: Texto.cuerpo(context)),
              ),
            ],
          ),
          const SizedBox(height: Espacio.s),
          Text(t.estresEn14(r.estresProx14!), style: Texto.nota(context)),
          // El factor final se mide mejor que el número de la app solo en tomate.
          if (cultivoId == 'tomate' && r.factorFinalRed != null) ...[
            const SizedBox(height: 2),
            Text(t.rendimientoFinal(r.factorFinalRed!), style: Texto.nota(context)),
          ],
          const SizedBox(height: Espacio.m),
          Text(t.leyendaRed, style: Texto.nota(context)),
        ],
      ),
    );
  }
}

/// Café: lo que dice la red de riego del equipo (donde se midió) y los avisos
/// con fuente. Se dibuja siempre en plantaciones de café con clima; los avisos
/// salen aunque la red no aplique.
class _TarjetaCafe extends StatelessWidget {
  const _TarjetaCafe({required this.r, required this.banano});

  final Recomendacion r;

  /// La sombra es banano: se dice lo que dice la auditoría del asesor y que los valores son de referencia.
  final bool banano;

  static IconData _icono(TipoAvisoCafe t) => switch (t) {
        TipoAvisoCafe.abono => CupertinoIcons.leaf_arrow_circlepath,
        TipoAvisoCafe.antracnosis => CupertinoIcons.ant,
        TipoAvisoCafe.roya => CupertinoIcons.thermometer,
      };

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    final riego = r.riegoCafe;
    final avisos = [for (final a in r.avisosCafe) if (a.seMuestra) a];
    final ambar = Paleta.de(context, Paleta.ambar);
    final verde = Paleta.de(context, Paleta.verde);

    Widget linea() => Padding(
          padding: const EdgeInsets.symmetric(vertical: Espacio.m),
          child: SizedBox(height: 0.5, child: ColoredBox(color: Paleta.de(context, Paleta.tenue))),
        );

    return Tarjeta(
      key: const Key('tarjeta_cafe'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.tarjetaCafe, style: Texto.fuerte(context)),
          const SizedBox(height: Espacio.s),
          if (riego != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2, right: Espacio.s),
                  child: Icon(
                    riego.regar ? CupertinoIcons.drop : CupertinoIcons.checkmark_circle,
                    size: 20,
                    color: riego.regar ? ambar : verde,
                  ),
                ),
                Expanded(child: Text(riego.regar ? t.conviene20 : t.noHaceFaltaRegar, style: Texto.cuerpo(context))),
              ],
            ),
            const SizedBox(height: Espacio.s),
            Text(t.diasEvitadosCafe(riego.diasEvitados), style: Texto.nota(context)),
            const SizedBox(height: 2),
            Text(t.prioridadUsada(riego.precio), style: Texto.nota(context)),
            if (riego.antracnosisCambioPrioridad) ...[
              const SizedBox(height: 2),
              Text(t.antracnosisCambioPrioridad, key: const Key('cafe_antracnosis_prioridad'), style: Texto.nota(context)),
            ],
            const SizedBox(height: 2),
            Text(t.reglaFao(riego.reglaRiega), style: Texto.nota(context)),
          ] else
            Text(t.redCafeNoAplica, style: Texto.nota(context)),
          if (avisos.isNotEmpty) ...[
            linea(),
            Text(t.avisosDelCafe, style: Texto.fuerte(context)),
            for (final a in avisos) ...[
              const SizedBox(height: Espacio.s),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: Espacio.s),
                    child: Icon(
                      _icono(a.tipo),
                      size: 20,
                      color: a.tipo == TipoAvisoCafe.abono && a.nivel == NivelAvisoCafe.abonarYa ? verde : ambar,
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.tituloAvisoCafe(a), style: Texto.cuerpo(context)),
                        Text(t.detalleAvisoCafe(a), style: Texto.nota(context)),
                        Text(
                          t.fuenteAviso(fuentesCafe[a.claveFuente]!.fuenteCorta, fuentesCafe[a.claveFuente]!.nivelConfianza),
                          style: Texto.nota(context),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: Espacio.s),
            Text(t.leyendaAvisosCafe, style: Texto.nota(context)),
          ],
          const SizedBox(height: Espacio.m),
          Text(t.leyendaRedCafe, style: Texto.nota(context)),
          if (banano) ...[
            const SizedBox(height: 2),
            Text(t.leyendaBananoCafe, key: const Key('leyenda_banano'), style: Texto.nota(context)),
          ],
        ],
      ),
    );
  }
}
