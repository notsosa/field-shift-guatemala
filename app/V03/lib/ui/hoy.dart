import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import 'agua.dart';
import 'cafe_red.dart';
import '../motor/fao56.dart';
import '../motor/recomendador.dart';
import 'finca.dart';
import 'graficos.dart';
import 'flujo.dart';
import 'emergentes.dart';
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

  /// Actualiza el clima. Si no se pudo, avisa por qué; el aviso no hace esperar
  /// al gesto de deslizar para actualizar.
  Future<void> _sincronizar(BuildContext context) async {
    final estado = Alcance.leer(context);
    if (estado.sincronizando) return;
    final resultado = await estado.sincronizar();
    if (!context.mounted || resultado == ResultadoSync.ok) return;
    final t = estado.txt;
    await mostrarAviso(
      context,
      titulo: t.clima,
      mensaje: resultado == ResultadoSync.sinWifi ? t.sinWifi : t.errorSync,
      icono: resultado == ResultadoSync.sinWifi
          ? CupertinoIcons.wifi_slash
          : CupertinoIcons.exclamationmark_circle_fill,
      boton: t.listo,
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    final p = e.plantacion;
    if (p == null) {
      return CupertinoPageScaffold(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Espacio.l),
            child: Text(
              t.bilingue(
                'No hay cultivos en curso. En Finca puedes elegir un lote e iniciar otro cultivo.',
                'There are no active crops. In Farm you can choose a plot and start another crop.',
              ),
              style: Texto.cuerpo(context),
            ),
          ),
        ),
      );
    }
    final r = e.recomendacion,
        color = colorNivel(context, e.recomendacion.nivel);
    final sinDatos = r.nivel == NivelAgua.sinDatos;
    void actividad() => Navigator.of(context, rootNavigator: true).push(
      CupertinoPageRoute<void>(
        builder: (_) => PantallaActividad(plantacionId: p.id),
      ),
    );
    void agua() => Navigator.of(
      context,
      rootNavigator: true,
    ).push(CupertinoPageRoute<void>(builder: (_) => const PantallaAgua()));
    Widget aviso(Aviso a) => Fila(
      titulo: t.tituloAviso(a),
      detalle: t.detalleAviso(a),
      icono: a == Aviso.plaga ? CupertinoIcons.ant : CupertinoIcons.info_circle,
      alPulsar: switch (a) {
        Aviso.registroPendiente || Aviso.plaga || Aviso.fertilizar => actividad,
        Aviso.capacidadLimitada => agua,
        Aviso.areaPendiente =>
          () => Navigator.of(context, rootNavigator: true).push(
            CupertinoPageRoute<void>(
              builder: (_) => PantallaMiPlantacion(loteId: p.loteId),
            ),
          ),
        Aviso.climaViejo => () => _sincronizar(context),
        _ => null,
      },
    );
    final avisos = r.avisos
        .where(
          (a) =>
              a != Aviso.lluviaFaltante &&
              a != Aviso.aguaSinConfirmar &&
              a != Aviso.sinAgua,
        )
        .toList();
    if (avisos.remove(Aviso.plaga)) avisos.insert(0, Aviso.plaga);
    return CupertinoPageScaffold(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(t.hoy),
            border: null,
            trailing: Semantics(
              button: true,
              label: e.sincronizando ? t.sincronizando : t.sincronizar,
              excludeSemantics: true,
              child: CupertinoButton(
                key: const Key('hoy-actualizar-clima'),
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
                onPressed: e.sincronizando ? null : () => _sincronizar(context),
                child: e.sincronizando
                    ? const CupertinoActivityIndicator()
                    : const Icon(CupertinoIcons.arrow_clockwise, size: 26),
              ),
            ),
          ),
          CupertinoSliverRefreshControl(onRefresh: () => _sincronizar(context)),
          SliverList.list(
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: Espacio.m),
                child: CambioPlantacion(),
              ),
              Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Tarjeta(
                  child: Column(
                    children: [
                      Text(
                        t.tituloNivel(r.nivel),
                        style: Texto.titulo(context),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: Espacio.m),
                      if (!sinDatos) ...[
                        Text(
                          '${(r.reserva * 100).round()} %',
                          style: letra(42, peso: 700, color: color),
                        ),
                        Text(
                          t.bilingue(
                            'Agua estimada en el suelo',
                            'Estimated water in soil',
                          ),
                          style: Texto.nota(context),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: Espacio.m),
                      ],
                      Text(
                        t.detalleNivel(r, p.riego),
                        style: Texto.cuerpo(context),
                        textAlign: TextAlign.center,
                      ),
                      if (!sinDatos) ...[
                        const SizedBox(height: Espacio.m),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          alignment: WrapAlignment.center,
                          children: [
                            _PildoraTelemetria(
                              texto: t.bilingue(
                                '💧 Tierra ${(e.humedadTierraDe(p) ?? r.humedadTierraPct ?? (r.reserva * 100)).round()} %',
                                '💧 Soil ${(e.humedadTierraDe(p) ?? r.humedadTierraPct ?? (r.reserva * 100)).round()} %',
                              ),
                            ),
                            if (r.temperaturaActual != null)
                              _PildoraTelemetria(
                                texto:
                                    '🌡️ ${r.temperaturaActual!.toStringAsFixed(1)} °C',
                              ),
                            _PildoraTelemetria(
                              texto:
                                  '⛰️ ${(e.parcela?.elevacion ?? e.terreno?.refElev ?? 500).round()} m · ${(e.pendienteDe(p) ?? e.terreno?.medianaPendiente ?? 8.0).toStringAsFixed(0)} %',
                            ),
                            if (e.cuerpoAguaDe(p) case final cw?)
                              _PildoraTelemetria(
                                texto: '🌊 ${cw.nombre} (${cw.distanciaM} m)',
                              ),
                          ],
                        ),
                      ],
                      if (r.diasLluviaFaltante > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: Espacio.m),
                          child: Text(
                            t.bilingue(
                              'Estimación con datos de lluvia incompletos.',
                              'Estimate with incomplete rainfall data.',
                            ),
                            style: Texto.nota(context),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      if (sinDatos) ...[
                        const SizedBox(height: Espacio.m),
                        BotonPrincipal(
                          texto: e.sincronizando
                              ? t.sincronizando
                              : t.sincronizar,
                          alPulsar: e.sincronizando
                              ? null
                              : () => _sincronizar(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              TarjetaRedCafe(plantacion: p, recomendacion: r),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
                child: BotonPrincipal(
                  texto: t.bilingue('Registrar actividad', 'Record activity'),
                  secundario: sinDatos,
                  alPulsar: actividad,
                ),
              ),
              if (p.tieneRiego)
                Padding(
                  padding: const EdgeInsets.only(top: Espacio.m),
                  child: Grupo(
                    children: [
                      Fila(
                        titulo: t.aguaHoy,
                        detalle: t.nombreDisponibilidad(
                          e.suministroDe(e.hoy)?.disponibilidad ??
                              DisponibilidadAgua.desconocida,
                        ),
                        icono: CupertinoIcons.drop,
                        alPulsar: agua,
                      ),
                    ],
                  ),
                ),
              if (avisos.isNotEmpty) ...[
                Rotulo(t.porHacer),
                Grupo(children: [for (final a in avisos.take(2)) aviso(a)]),
                if (avisos.length > 2)
                  SeccionDesplegable(
                    titulo: t.bilingue(
                      'Ver otros avisos',
                      'View other notices',
                    ),
                    children: [
                      Grupo(
                        children: [for (final a in avisos.skip(2)) aviso(a)],
                      ),
                    ],
                  ),
              ],
              const SizedBox(height: Espacio.m),
              Grupo(
                children: [
                  Fila(
                    titulo: t.bilingue(
                      'Ver detalle del agua y clima',
                      'View water and weather details',
                    ),
                    icono: CupertinoIcons.cloud_sun,
                    alPulsar: () =>
                        Navigator.of(context, rootNavigator: true).push(
                          CupertinoPageRoute<void>(
                            builder: (_) =>
                                PantallaDetalleAgua(plantacionId: p.id),
                          ),
                        ),
                  ),
                ],
              ),
              const SizedBox(height: Espacio.xl),
            ],
          ),
        ],
      ),
    );
  }
}

class PantallaDetalleAgua extends StatelessWidget {
  const PantallaDetalleAgua({super.key, required this.plantacionId});
  final String plantacionId;
  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    final p = e.plantacionPorId(plantacionId)!;
    final r = e.recomendacionDe(p);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.bilingue('Agua y clima', 'Water and weather')),
        previousPageTitle: t.atras,
      ),
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(Espacio.l),
              child: Text(
                identificarPlantacion(e, p),
                style: Texto.cuerpo(context),
              ),
            ),
            Grupo(
              children: [
                Fila(titulo: t.etapa, detalle: t.nombreEtapa(r.etapa)),
                if (r.diasACosecha != null && r.etapa != Etapa.cosechado)
                  Fila(titulo: t.cosecha, detalle: t.enDias(r.diasACosecha!)),
                Fila(
                  titulo: t.rendimiento,
                  detalle: r.factorRendimiento == null
                      ? t.sinDato
                      : '${(r.factorRendimiento! * 100).round()} %',
                ),
                Fila(
                  titulo: '${t.lluvia} · 7 d',
                  // NASA publica con días de retraso: si faltan días, se dice
                  // cuántos en lugar de presentar la suma como completa.
                  detalle: r.lluviaSemana == null
                      ? t.sinDato
                      : r.diasSinLluvia > 0
                      ? t.bilingue(
                          '${t.mm(r.lluviaSemana!)} · faltan ${r.diasSinLluvia} ${r.diasSinLluvia == 1 ? 'día' : 'días'} por publicar',
                          '${t.mm(r.lluviaSemana!)} · ${r.diasSinLluvia} ${r.diasSinLluvia == 1 ? 'day' : 'days'} not yet published',
                        )
                      : t.mm(r.lluviaSemana!),
                ),
                Fila(
                  titulo: '${t.necesidad} · 7 d',
                  detalle: t.mm(r.necesidadSemana),
                ),
              ],
            ),
            if (r.ultimos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Tarjeta(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.ultimosDias, style: Texto.fuerte(context)),
                      const SizedBox(height: 8),
                      Text(t.leyendaReserva, style: Texto.nota(context)),
                      const SizedBox(height: Espacio.m),
                      BarrasAgua(dias: r.ultimos),
                      const SizedBox(height: 8),
                      Text(
                        t.diasEstres(r.diasEstres),
                        style: Texto.nota(context),
                      ),
                    ],
                  ),
                ),
              ),
            if (r.diasLluviaFaltante > 0)
              Padding(
                padding: const EdgeInsets.all(Espacio.l),
                child: Text(t.escenarioLluvia, style: Texto.nota(context)),
              ),
            Rotulo(
              t.bilingue(
                'Telemetría satelital y terreno',
                'Satellite and terrain telemetry',
              ),
            ),
            Grupo(
              children: [
                Fila(
                  titulo: t.bilingue(
                    'Humedad de la tierra (NASA)',
                    'Soil moisture (NASA)',
                  ),
                  detalle:
                      '${(e.humedadTierraDe(p) ?? r.humedadTierraPct ?? (r.reserva * 100)).round()} %',
                ),
                if (r.temperaturaActual != null)
                  Fila(
                    titulo: t.bilingue(
                      'Temperatura y humedad relativa',
                      'Temperature and relative humidity',
                    ),
                    detalle:
                        '${r.temperaturaActual!.toStringAsFixed(1)} °C · HR ${(r.humedadRelativaActual ?? 75).round()} %',
                  ),
                Fila(
                  titulo: t.bilingue(
                    'Altitud y pendiente (SRTM)',
                    'Altitude and slope (SRTM)',
                  ),
                  detalle:
                      '${(e.parcela?.elevacion ?? e.terreno?.refElev ?? 500).round()} m · ${(e.pendienteDe(p) ?? e.terreno?.medianaPendiente ?? 8.0).toStringAsFixed(1)} %',
                ),
                if (e.cuerpoAguaDe(p) case final cw?)
                  Fila(
                    titulo: t.bilingue(
                      'Cuerpo de agua cercano',
                      'Nearest water body',
                    ),
                    detalle: '${cw.nombre} (${cw.distanciaM} m)',
                  ),
              ],
            ),
            Rotulo(t.clima),
            Grupo(
              children: [
                Fila(
                  titulo: r.ultimoClima == null
                      ? t.nuncaSincronizado
                      : t.fechaLarga(r.ultimoClima!),
                  detalle: t.bilingue(
                    'Último día con datos de clima completos.',
                    'Last day with complete weather data.',
                  ),
                ),
                Fila(
                  titulo: t.precision,
                  detalle:
                      '${t.nombrePrecision(r.precision)}. ${t.precisionAyuda}',
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(Espacio.l),
              child: Text(t.apoyaNoReemplaza, style: Texto.nota(context)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PildoraTelemetria extends StatelessWidget {
  const _PildoraTelemetria({required this.texto});

  final String texto;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Paleta.de(context, Paleta.tenue),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      child: Text(
        texto,
        style: letra(13, peso: 600, color: Paleta.de(context, Paleta.texto)),
      ),
    ),
  );
}
