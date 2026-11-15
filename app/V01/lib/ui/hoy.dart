import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../motor/fao56.dart';
import '../motor/recomendador.dart';
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
    final parcela = estado.parcela!;
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
              child: Text(
                '${t.nombreCultivo(plantacion.cultivoId)} · ${parcela.nombre}',
                style: letra(16, color: Paleta.de(context, Paleta.secundario)),
              ),
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
