import 'dart:convert';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../estado.dart';
import '../eventos.dart';
import '../modelos.dart';
import '../textos.dart' show Txt;
import 'tema.dart';
import 'ajustes.dart' show confirmar;
import 'agua.dart';
import 'emergentes.dart' as emergentes;

Future<T?> elegirOpcion<T>(
  BuildContext context,
  String titulo,
  Map<T, String> opciones, {
  T? seleccionada,
}) => emergentes.elegirOpcion<T>(
  context,
  titulo: titulo,
  seleccionada: seleccionada,
  opciones: [
    for (final e in opciones.entries)
      emergentes.OpcionHoja<T>(valor: e.key, texto: e.value),
  ],
);

/// Selector de fecha con «Cancelar» y «Listo». Devuelve nulo si se cancela o
/// se toca fuera. El rango siempre incluye la fecha actual: nunca se recorta
/// una fecha existente en silencio. Con [recortar] la fecha inicial se lleva al
/// rango, pero solo se aplica si la persona pulsa «Listo».
Future<DateTime?> elegirDiaOpcional(
  BuildContext context,
  DateTime actual, {
  DateTime? minimo,
  DateTime? maximo,
  bool recortar = false,
  String? titulo,
}) {
  final e = Alcance.leer(context);
  var min = soloFecha(minimo ?? DateTime(2000)),
      max = soloFecha(maximo ?? e.hoy);
  var fecha = soloFecha(actual);
  if (recortar) {
    if (fecha.isBefore(min)) fecha = min;
    if (fecha.isAfter(max)) fecha = max;
  } else {
    if (fecha.isBefore(min)) min = fecha;
    if (fecha.isAfter(max)) max = fecha;
  }
  return emergentes.elegirFecha(
    context,
    inicial: fecha,
    minimo: min,
    maximo: max,
    titulo: titulo,
  );
}

/// Igual que [elegirDiaOpcional], pero devuelve la fecha actual si se cancela.
Future<DateTime> elegirDia(
  BuildContext context,
  DateTime actual, {
  DateTime? minimo,
  DateTime? maximo,
}) async =>
    await elegirDiaOpcional(context, actual, minimo: minimo, maximo: maximo) ??
    soloFecha(actual);

/// Número sin ceros de más: 5.0 se escribe 5. No pierde decimales.
String numeroLimpio(double v) {
  if (!v.isFinite) return '';
  if (v == v.roundToDouble() && v.abs() < 1e15) return v.toInt().toString();
  return v.toString();
}

/// Zona fija bajo la lista: el error (en rojo) justo encima del botón y, si el
/// botón está desactivado, el motivo debajo.
class PieGuardar extends StatelessWidget {
  const PieGuardar({
    super.key,
    required this.texto,
    required this.alPulsar,
    this.error,
    this.motivo,
  });
  final String texto;
  final VoidCallback? alPulsar;
  final String? error, motivo;
  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .45,
    ),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Espacio.l,
          Espacio.s,
          Espacio.l,
          Espacio.m,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: Espacio.s),
                child: Semantics(
                  liveRegion: true,
                  child: Text(
                    error!,
                    key: const Key('error-guardar'),
                    style: Texto.cuerpo(context)
                        .copyWith(color: Paleta.de(context, Paleta.rojo)),
                  ),
                ),
              ),
            BotonPrincipal(texto: texto, alPulsar: alPulsar),
            if (alPulsar == null && motivo != null)
              Padding(
                padding: const EdgeInsets.only(top: Espacio.s),
                child: Text(
                  motivo!,
                  key: const Key('motivo-guardar'),
                  textAlign: TextAlign.center,
                  style: Texto.nota(context),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

String nombreEvento(AppEstado e, TipoEvento tipo) => switch (tipo) {
  TipoEvento.cosecha => e.txt.bilingue('Cosecha parcial', 'Partial harvest'),
  TipoEvento.perdida => e.txt.bilingue('Pérdida', 'Loss'),
  TipoEvento.plaga => e.txt.bilingue('Plaga observada', 'Pest observation'),
  TipoEvento.tratamiento => e.txt.bilingue('Tratamiento', 'Treatment'),
  TipoEvento.fertilizacion => e.txt.bilingue('Fertilización', 'Fertilization'),
  TipoEvento.observacion => e.txt.bilingue(
    'Suelo, sombra o vecinos',
    'Soil, shade or neighbors',
  ),
};

IconData iconoEvento(TipoEvento tipo) => switch (tipo) {
  TipoEvento.cosecha => CupertinoIcons.cart,
  TipoEvento.perdida => CupertinoIcons.arrow_down_circle,
  TipoEvento.plaga => CupertinoIcons.ant,
  TipoEvento.tratamiento => CupertinoIcons.drop,
  TipoEvento.fertilizacion => CupertinoIcons.leaf_arrow_circlepath,
  TipoEvento.observacion => CupertinoIcons.eye,
};

/// Unidad en palabras llanas; nunca el código interno.
String nombreUnidad(Txt t, String? u) => switch (u) {
  null || '' => '',
  'otra' => t.bilingue('otra unidad', 'other unit'),
  _ => u,
};

/// Referencia de una pérdida o de una dosis en palabras llanas. Devuelve vacío
/// si no se conoce: nunca el valor interno.
String nombreReferencia(Txt t, String? r) => switch (r) {
  'superficie' => t.bilingue('superficie del lote', 'plot area'),
  'produccionEsperada' => t.bilingue(
    'producción esperada',
    'expected production',
  ),
  'yaCosechado' => t.bilingue(
    'producto ya cosechado',
    'already harvested produce',
  ),
  'lote' => t.bilingue('todo el lote', 'the whole plot'),
  'ha' => t.bilingue('cada hectárea', 'each hectare'),
  'm²' => t.bilingue('cada metro cuadrado', 'each square meter'),
  'L de mezcla' => t.bilingue('cada litro de mezcla', 'each liter of mixture'),
  _ => '',
};

String detalleEvento(AppEstado estado, Evento e) {
  final t = estado.txt;
  final unidad = nombreUnidad(t, e.unidad);
  final referencia = nombreReferencia(t, e.referencia);
  var nota = e.nota;
  if (e.tipo == TipoEvento.fertilizacion && e.origen == 'ficha-inicial') {
    nota = TipoFertilizante.values.any((f) => f.name == e.nota)
        ? t.nombreFertilizante(TipoFertilizante.values.byName(e.nota))
        : '';
  }
  NivelPlaga? nivel;
  for (final n in NivelPlaga.values) {
    if (n.name == e.severidad) nivel = n;
  }
  final cantidad = e.cantidad == null
      ? null
      : '${numeroLimpio(e.cantidad!)}${unidad.isEmpty ? '' : ' $unidad'}'
            '${referencia.isEmpty
                ? ''
                : e.tipo == TipoEvento.perdida
                ? ' ($referencia)'
                : ' (${t.bilingue('para', 'for')} $referencia)'}';
  return [
    e.fecha != null
        ? t.fechaLarga(e.fecha!)
        : e.desde != null && e.hasta != null
        ? '${t.fechaCorta(e.desde!)} – ${t.fechaCorta(e.hasta!)}'
        : t.bilingue('Fecha desconocida', 'Date unknown'),
    ?cantidad,
    if (cantidad == null &&
        e.tipo == TipoEvento.perdida &&
        referencia.isNotEmpty)
      referencia,
    if (e.producto.isNotEmpty) e.producto,
    if (nivel != null)
      '${t.bilingue('Gravedad', 'Severity')}: ${t.nombrePlaga(nivel)}',
    if (e.observacion != null)
      switch (e.observacion!) {
        Observacion.sombra => t.bilingue(
          'Sombra sobre el lote',
          'Shade over plot',
        ),
        Observacion.humedadSuelo => t.bilingue(
          'Humedad del suelo',
          'Soil moisture',
        ),
        Observacion.vecinos => t.bilingue(
          'Cobertura o densidad vecina',
          'Neighbor cover or density',
        ),
      },
    if (e.profundidadCm != null)
      '${t.bilingue('Profundidad', 'Depth')} ${numeroLimpio(e.profundidadCm!)} cm',
    if (e.metodo.isNotEmpty) '${t.bilingue('Método', 'Method')}: ${e.metodo}',
    if (e.especieVecina.isNotEmpty) e.especieVecina,
    if (e.distanciaM != null)
      '${t.bilingue('a', 'at')} ${numeroLimpio(e.distanciaM!)} m',
    if (nota.isNotEmpty) nota,
    if (e.derivado)
      e.origen == 'ficha-inicial'
          ? t.bilingue(
              'Anotado al empezar el cultivo',
              'Noted when the crop started',
            )
          : t.bilingue(
              'Viene de un resumen de la semana',
              'From a weekly summary',
            ),
  ].join(' · ');
}

class PantallaCampanias extends StatelessWidget {
  const PantallaCampanias({super.key, this.loteId});
  final String? loteId;
  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.bilingue('Campañas e historial', 'Seasons and history')),
        previousPageTitle: t.atras,
      ),
      child: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(Espacio.l),
              child: Text(
                t.bilingue(
                  'Lo que se ha sembrado en cada lote. Toca uno para ver sus registros.',
                  'What has been planted in each plot. Tap one to see its records.',
                ),
                style: Texto.nota(context),
              ),
            ),
            for (final lote in e.lotes.where(
              (l) => loteId == null || l.id == loteId,
            )) ...[
              Rotulo(
                '${t.bilingue('Lote', 'Plot')} ${e.lotes.indexOf(lote) + 1} · ${t.area(lote.areaM2)}',
              ),
              Grupo(
                children: [
                  for (final p
                      in e.campanias.where((p) => p.loteId == lote.id).toList()
                        ..sort((a, b) => b.fecha.compareTo(a.fecha)))
                    Fila(
                      titulo: t.nombrePlantacion(p),
                      detalle:
                          '${t.fechaCorta(p.fecha)} · ${p.activa ? t.bilingue('En curso', 'Active') : '${t.bilingue('Cerrada', 'Closed')} ${t.fechaCorta(p.fin!)}'}',
                      icono: CupertinoIcons.tree,
                      alPulsar: () => Navigator.of(context).push(
                        CupertinoPageRoute<void>(
                          builder: (_) => PantallaBitacora(campaniaId: p.id),
                        ),
                      ),
                    ),
                  if (!e.campanias.any((p) => p.loteId == lote.id))
                    Fila(
                      titulo: t.bilingue(
                        'Sin cultivos todavía',
                        'No crops yet',
                      ),
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

class PantallaBitacora extends StatelessWidget {
  const PantallaBitacora({super.key, required this.campaniaId});
  final String campaniaId;
  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    final p = e.plantacionPorId(campaniaId);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.registros),
        previousPageTitle: t.atras,
      ),
      child: SafeArea(
        child: p == null
            ? const SizedBox()
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Espacio.l),
                    child: Text(
                      '${t.nombrePlantacion(p)} · ${t.fechaLarga(p.fecha)}',
                      style: Texto.cuerpo(context),
                    ),
                  ),
                  HistorialPlantacion(plantacion: p),
                ],
              ),
      ),
    );
  }
}

class HistorialPlantacion extends StatelessWidget {
  const HistorialPlantacion({super.key, required this.plantacion});
  final Plantacion plantacion;
  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt, p = plantacion;
    final eventos = e.eventosDe(p.id).where((x) => !x.derivado).toList();
    final semanales = e.registrosDe(p.id);
    final riegos = e.riegosDiarios.where((r) => r.campaniaId == p.id).toList();
    final rojo = Paleta.de(context, Paleta.rojo);
    String sn(bool? v) => v == null
        ? t.sinDato
        : v
        ? t.si
        : t.no;
    final filas = <(DateTime, Widget)>[
      for (final evento in eventos)
        (
          evento.orden ?? DateTime(1900),
          Fila(
            titulo:
                '${t.bilingue('Actividad', 'Activity')} · ${nombreEvento(e, evento.tipo)}',
            detalle: detalleEvento(e, evento),
            icono: iconoEvento(evento.tipo),
            colorIcono: evento.tipo == TipoEvento.perdida ? rojo : null,
            alPulsar: () => Navigator.of(context, rootNavigator: true).push(
              CupertinoPageRoute<void>(
                builder: (_) =>
                    PantallaEvento(campaniaId: p.id, evento: evento),
              ),
            ),
          ),
        ),
      for (final r in riegos)
        (
          r.fecha,
          Fila(
            titulo:
                '${t.bilingue('Riego', 'Irrigation')} · ${t.fechaLarga(r.fecha)}',
            detalle: [
              if (r.necesito != null)
                '${t.bilingue('Se necesitaba', 'Needed')}: ${sn(r.necesito)}',
              if (r.rego != null)
                '${t.bilingue('Regaste', 'You irrigated')}: ${sn(r.rego)}',
              if (r.laminaMm != null) t.mm(r.laminaMm!),
              if (r.necesito == null && r.rego == null && r.laminaMm == null)
                t.sinDato,
            ].join(' · '),
            icono: CupertinoIcons.drop,
            alPulsar: !p.tieneRiego
                ? null
                : () => Navigator.of(context, rootNavigator: true).push(
                    CupertinoPageRoute<void>(
                      builder: (_) =>
                          PantallaAgua(fechaInicial: r.fecha, campaniaId: p.id),
                    ),
                  ),
          ),
        ),
      for (final r in semanales)
        (
          r.fecha,
          Fila(
            titulo:
                '${t.bilingue('Resumen de la semana', 'Weekly summary')} · ${t.fechaLarga(r.fecha)}',
            detalle: t.resumenRegistro(r),
            icono: CupertinoIcons.calendar,
            alPulsar: () => confirmar(
              context,
              titulo:
                  '${t.bilingue('Resumen de la semana', 'Weekly summary')}\n${t.fechaLarga(r.fecha)}',
              mensaje: [
                t.resumenRegistro(r),
                r.notaPlaga,
                r.notaFertilizante,
                t.borrarRegistroPregunta,
              ].where((x) => x.isNotEmpty).join('\n'),
              accion: t.borrar,
              cancelar: t.cancelar,
              alConfirmar: () => e.borrarRegistro(r),
            ),
          ),
        ),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    final iniciales = e
        .eventosDe(p.id)
        .where((x) => x.origen == 'ficha-inicial')
        .toList();
    final sinConversion = eventos
        .where((x) => x.tipo == TipoEvento.cosecha && x.kilos == null)
        .length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (eventos.any((x) => x.tipo == TipoEvento.cosecha))
          Grupo(
            children: [
              Fila(
                titulo: t.bilingue('Cosecha registrada', 'Recorded harvest'),
                detalle: '${e.kilosCosechados(p.id).toStringAsFixed(2)} kg',
                icono: CupertinoIcons.cart,
              ),
            ],
          ),
        if (sinConversion > 0)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: Espacio.l,
              vertical: Espacio.s,
            ),
            child: Text(
              t.bilingue(
                'Hay cosechas en otras unidades que no se suman a los kg.',
                'Some harvests are in other units and are not added to the kg.',
              ),
              key: const Key('aviso-otras-unidades'),
              style: Texto.nota(context)
                  .copyWith(color: Paleta.de(context, Paleta.ambar)),
            ),
          ),
        if (filas.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Espacio.l),
            child: Text(t.sinRegistros, style: Texto.nota(context)),
          )
        else
          Grupo(children: [for (final fila in filas) fila.$2]),
        if (iniciales.isNotEmpty)
          SeccionDesplegable(
            titulo: t.bilingue(
              'Datos al iniciar el cultivo',
              'Details when starting this crop',
            ),
            children: [
              Grupo(
                children: [
                  for (final evento in iniciales)
                    Fila(
                      titulo: nombreEvento(e, evento.tipo),
                      detalle: detalleEvento(e, evento),
                      icono: iconoEvento(evento.tipo),
                    ),
                ],
              ),
            ],
          ),
        const SizedBox(height: Espacio.xl),
      ],
    );
  }
}

class PantallaEvento extends StatefulWidget {
  const PantallaEvento({
    super.key,
    required this.campaniaId,
    this.evento,
    this.tipoInicial,
  });
  final String campaniaId;
  final Evento? evento;
  final TipoEvento? tipoInicial;
  @override
  State<PantallaEvento> createState() => _FormularioEvento();
}

class _FormularioEvento extends State<PantallaEvento> {
  TipoEvento _tipo = TipoEvento.cosecha;
  Observacion _observacion = Observacion.sombra;
  String _unidad = 'kg',
      _referencia = 'produccionEsperada',
      _severidad = 'leve';
  final _cantidad = TextEditingController(),
      _producto = TextEditingController(),
      _nota = TextEditingController(),
      _profundidad = TextEditingController(),
      _metodo = TextEditingController(),
      _vecina = TextEditingController(),
      _distancia = TextEditingController();
  DateTime? _fecha;
  bool _guardando = false;
  String? _error;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_fecha != null) return;
    final e = Alcance.leer(context), previo = widget.evento;
    final p = e.plantacionPorId(widget.campaniaId)!;
    _fecha = previo?.fecha ?? p.fin ?? soloFecha(e.hoy);
    if (widget.tipoInicial != null) _cambiarTipo(widget.tipoInicial!);
    if (previo != null) {
      _tipo = previo.tipo;
      _observacion = previo.observacion ?? Observacion.sombra;
      _unidad = previo.unidad ?? _unidades.first;
      _referencia = previo.referencia ?? 'desconocida';
      _severidad = previo.severidad ?? 'leve';
      _cantidad.text = previo.cantidad == null
          ? ''
          : numeroLimpio(previo.cantidad!);
      _producto.text = previo.producto;
      _nota.text = previo.nota;
      _profundidad.text = previo.profundidadCm == null
          ? ''
          : numeroLimpio(previo.profundidadCm!);
      _metodo.text = previo.metodo;
      _vecina.text = previo.especieVecina;
      _distancia.text = previo.distanciaM == null
          ? ''
          : numeroLimpio(previo.distanciaM!);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _cantidad,
      _producto,
      _nota,
      _profundidad,
      _metodo,
      _vecina,
      _distancia,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  List<String> get _unidades => switch (_tipo) {
    TipoEvento.cosecha => ['kg', 'g', 't', 'otra'],
    TipoEvento.perdida =>
      _referencia == 'superficie' ? ['%', 'm²', 'ha'] : ['%', 'kg', 'g', 't'],
    TipoEvento.observacion => switch (_observacion) {
      Observacion.sombra => ['%'],
      Observacion.humedadSuelo => ['%', 'm³/m³', 'kPa'],
      Observacion.vecinos => ['%', 'plantas/m²', 'plantas/ha'],
    },
    _ => ['kg', 'g', 'L', 'mL', 'otra'],
  };
  void _cambiarTipo(TipoEvento v) {
    _tipo = v;
    _cantidad.clear();
    _referencia = v == TipoEvento.perdida
        ? 'produccionEsperada'
        : 'desconocida';
    _unidad = _unidades.first;
  }

  Future<void> _guardar() async {
    final e = Alcance.leer(context),
        p = Alcance.leer(context).plantacionPorId(widget.campaniaId)!;
    double? numero(TextEditingController c) {
      final texto = c.text.trim();
      if (texto.isEmpty) return null;
      final n = double.tryParse(texto.replaceAll(',', '.'));
      if (n == null || !n.isFinite) {
        throw FormatException(
          e.txt.bilingue(
            'Revisa la cantidad: escribe solo números.',
            'Check the amount: type numbers only.',
          ),
        );
      }
      return n;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final aplicacion =
          _tipo == TipoEvento.fertilizacion || _tipo == TipoEvento.tratamiento;
      final cantidad = _tipo == TipoEvento.plaga ? null : numero(_cantidad);
      final humedad =
          _tipo == TipoEvento.observacion &&
          _observacion == Observacion.humedadSuelo;
      final vecinos =
          _tipo == TipoEvento.observacion &&
          _observacion == Observacion.vecinos;
      await e.guardarEvento(
        Evento(
          id: widget.evento?.id ?? '',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: _tipo,
          fecha: _fecha,
          cantidad: cantidad,
          // La unidad y la referencia de la dosis solo tienen sentido con
          // cantidad. En una pérdida, la referencia dice qué se perdió.
          unidad: cantidad == null ? null : _unidad,
          referencia: _tipo == TipoEvento.perdida
              ? _referencia
              : aplicacion && cantidad != null
              ? _referencia
              : null,
          producto: aplicacion ? _producto.text.trim() : '',
          severidad: _tipo == TipoEvento.plaga ? _severidad : null,
          observacion: _tipo == TipoEvento.observacion ? _observacion : null,
          profundidadCm: humedad ? numero(_profundidad) : null,
          metodo: _tipo == TipoEvento.observacion ? _metodo.text.trim() : '',
          especieVecina: vecinos ? _vecina.text.trim() : '',
          distanciaM: vecinos ? numero(_distancia) : null,
          nota: _nota.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    final p = e.plantacionPorId(widget.campaniaId)!;
    final aplicacion =
        _tipo == TipoEvento.fertilizacion || _tipo == TipoEvento.tratamiento;
    Widget campo(
      String titulo,
      TextEditingController c, {
      bool numero = false,
      String? ejemplo,
    }) => Campo(
      titulo: titulo,
      controlador: c,
      ejemplo:
          ejemplo ??
          (c == _cantidad && _tipo == TipoEvento.cosecha
              ? t.bilingue('Escribe la cantidad', 'Enter the amount')
              : t.opcional),
      teclado: numero
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
    );
    final hayDetalles =
        _nota.text.isNotEmpty ||
        _metodo.text.isNotEmpty ||
        _profundidad.text.isNotEmpty ||
        _vecina.text.isNotEmpty ||
        _distancia.text.isNotEmpty ||
        aplicacion && _referencia != 'desconocida';
    final etiquetaDosis = _referencia == 'desconocida'
        ? t.bilingue('No sé', 'I do not know')
        : nombreReferencia(t, _referencia);
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.bilingue('Registrar evento', 'Record event')),
        previousPageTitle: t.atras,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Rotulo('${t.nombrePlantacion(p)} · ${t.fechaCorta(p.fecha)}'),
                  Grupo(
                    children: [
                      if (widget.tipoInicial == null)
                        Fila(
                          titulo: t.bilingue('Tipo de registro', 'Record type'),
                          detalle: nombreEvento(e, _tipo),
                          alPulsar: () async {
                            final v = await elegirOpcion(
                              context,
                              t.bilingue('Tipo de registro', 'Record type'),
                                {
                                  for (final tipo in TipoEvento.values)
                                    tipo: nombreEvento(e, tipo),
                                },
                                seleccionada: _tipo,
                              );
                              if (v != null && v != _tipo && mounted) {
                                setState(() => _cambiarTipo(v));
                              }
                          },
                        ),
                      Fila(
                        titulo: t.fechaObservacion,
                        detalle: t.fechaLarga(_fecha!),
                        alPulsar: () async {
                          final f = await elegirDiaOpcional(
                            context,
                            _fecha!,
                            minimo: p.fecha,
                            maximo: p.fin,
                          );
                          if (f != null && mounted) setState(() => _fecha = f);
                        },
                      ),
                      if (_tipo == TipoEvento.perdida)
                        Fila(
                          titulo: t.bilingue(
                            '¿Qué se perdió?',
                            'What was lost?',
                          ),
                          detalle: switch (_referencia) {
                            'superficie' => t.bilingue(
                              'Superficie del lote',
                              'Plot area',
                            ),
                            'yaCosechado' => t.bilingue(
                              'Producto ya cosechado',
                              'Already harvested produce',
                            ),
                            _ => t.bilingue(
                              'Producción esperada',
                              'Expected production',
                            ),
                          },
                          alPulsar: () async {
                            final v = await elegirOpcion(
                              context,
                              t.bilingue('¿Qué se perdió?', 'What was lost?'),
                              {
                                'superficie': t.bilingue(
                                  'Superficie del lote',
                                  'Plot area',
                                ),
                                'produccionEsperada': t.bilingue(
                                  'Producción esperada',
                                  'Expected production',
                                ),
                                'yaCosechado': t.bilingue(
                                  'Producto ya cosechado',
                                  'Already harvested produce',
                                ),
                              },
                              seleccionada: _referencia,
                            );
                            if (v != null && v != _referencia && mounted) {
                              setState(() {
                                _referencia = v;
                                _unidad = '%';
                                _cantidad.clear();
                              });
                            }
                          },
                        ),
                      if (_tipo == TipoEvento.observacion)
                        Fila(
                          titulo: t.bilingue(
                            '¿Qué observaste?',
                            'What did you observe?',
                          ),
                          detalle: switch (_observacion) {
                            Observacion.sombra => t.bilingue(
                              'Sombra (%)',
                              'Shade (%)',
                            ),
                            Observacion.humedadSuelo => t.bilingue(
                              'Humedad del suelo',
                              'Soil moisture',
                            ),
                            Observacion.vecinos => t.bilingue(
                              'Cultivos vecinos',
                              'Neighboring crops',
                            ),
                          },
                          alPulsar: () async {
                            final v = await elegirOpcion(
                              context,
                              t.bilingue(
                                '¿Qué observaste?',
                                'What did you observe?',
                              ),
                              {
                                Observacion.sombra: t.bilingue(
                                  'Sombra sobre el lote',
                                  'Shade over plot',
                                ),
                                Observacion.humedadSuelo: t.bilingue(
                                  'Humedad del suelo',
                                  'Soil moisture',
                                ),
                                Observacion.vecinos: t.bilingue(
                                  'Cobertura o densidad vecina',
                                  'Neighbor cover or density',
                                ),
                              },
                              seleccionada: _observacion,
                            );
                            if (v != null && v != _observacion && mounted) {
                              setState(() {
                                _observacion = v;
                                _unidad = '%';
                                _cantidad.clear();
                              });
                            }
                          },
                        ),
                      if (_tipo == TipoEvento.plaga)
                        Fila(
                          titulo: t.bilingue(
                            '¿Qué tan fuerte es la plaga?',
                            'How bad is the pest?',
                          ),
                          detalle: t.nombrePlaga(
                            NivelPlaga.values.byName(_severidad),
                          ),
                          alPulsar: () async {
                            final v = await elegirOpcion(
                              context,
                              t.bilingue(
                                '¿Qué tan fuerte es la plaga?',
                                'How bad is the pest?',
                              ),
                              {
                                for (final n in const [
                                  NivelPlaga.leve,
                                  NivelPlaga.moderada,
                                  NivelPlaga.fuerte,
                                ])
                                  n.name: t.nombrePlaga(n),
                              },
                              seleccionada: _severidad,
                            );
                            if (v != null && mounted) {
                              setState(() => _severidad = v);
                            }
                          },
                        ),
                      if (aplicacion)
                        campo(t.bilingue('Producto', 'Product'), _producto),
                      if (_tipo != TipoEvento.plaga) ...[
                        campo(
                          switch (_tipo) {
                            TipoEvento.cosecha => t.bilingue(
                              'Cantidad cosechada',
                              'Harvested amount',
                            ),
                            TipoEvento.perdida => t.bilingue(
                              'Cantidad perdida',
                              'Amount lost',
                            ),
                            TipoEvento.observacion => t.bilingue(
                              'Valor medido',
                              'Measured value',
                            ),
                            _ => t.bilingue(
                              'Cantidad aplicada',
                              'Amount applied',
                            ),
                          },
                          _cantidad,
                          numero: true,
                        ),
                        Fila(
                          titulo: t.bilingue('Unidad', 'Unit'),
                          detalle: nombreUnidad(t, _unidad),
                          alPulsar: () async {
                            final v = await elegirOpcion(
                              context,
                              t.bilingue('Unidad', 'Unit'),
                              {
                                for (final u in _unidades)
                                  u: u == 'otra'
                                        ? t.bilingue(
                                            'Otra: describir en la nota',
                                            'Other: describe in the note',
                                          )
                                        : u,
                                },
                                seleccionada: _unidad,
                              );
                            if (v != null && mounted) {
                              setState(() => _unidad = v);
                            }
                          },
                        ),
                      ],
                    ],
                  ),
                  SeccionDesplegable(
                    titulo: t.bilingue(
                      'Más detalles (opcional)',
                      'More details (optional)',
                    ),
                    inicialmenteAbierta: hayDetalles,
                    children: [
                      Grupo(
                        children: [
                          if (aplicacion)
                            Fila(
                              titulo: t.bilingue(
                                '¿La cantidad es para…?',
                                'Is the amount for…?',
                              ),
                              detalle: etiquetaDosis,
                              alPulsar: () async {
                                final v = await elegirOpcion(
                                  context,
                                  t.bilingue(
                                    '¿La cantidad es para…?',
                                    'Is the amount for…?',
                                  ),
                                  {
                                    'desconocida': t.bilingue(
                                      'No sé',
                                      'I do not know',
                                    ),
                                    'lote': nombreReferencia(t, 'lote'),
                                    'ha': nombreReferencia(t, 'ha'),
                                    'm²': nombreReferencia(t, 'm²'),
                                      'L de mezcla': nombreReferencia(
                                        t,
                                        'L de mezcla',
                                      ),
                                    },
                                    seleccionada: _referencia,
                                  );
                                if (v != null && mounted) {
                                  setState(() => _referencia = v);
                                }
                              },
                            ),
                          if (_tipo == TipoEvento.observacion) ...[
                            if (_observacion == Observacion.humedadSuelo)
                              campo(
                                t.bilingue('Profundidad (cm)', 'Depth (cm)'),
                                _profundidad,
                                numero: true,
                              ),
                            campo(
                              t.bilingue(
                                '¿Cómo lo mediste?',
                                'How did you measure it?',
                              ),
                              _metodo,
                            ),
                            if (_observacion == Observacion.vecinos) ...[
                              campo(
                                t.bilingue(
                                  '¿Qué cultivo hay al lado?',
                                  'What crop is next to it?',
                                ),
                                _vecina,
                              ),
                              campo(
                                t.bilingue('Distancia (m)', 'Distance (m)'),
                                _distancia,
                                numero: true,
                              ),
                            ],
                          ],
                          campo(
                            _tipo == TipoEvento.plaga
                                ? t.bilingue(
                                    'Describe lo que viste',
                                    'Describe what you saw',
                                  )
                                : t.bilingue('Nota', 'Note'),
                            _nota,
                          ),
                        ],
                      ),
                    ],
                  ),
                  SeccionDesplegable(
                    titulo: t.bilingue(
                      'Ayuda para este registro',
                      'Help with this record',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(Espacio.l),
                        child: Text(switch (_tipo) {
                          TipoEvento.cosecha => t.bilingue(
                            'Anota lo que cosechaste en esta fecha. Puedes agregar otras cosechas después.',
                            'Record what you harvested on this date. You can add other harvests later.',
                          ),
                          TipoEvento.perdida => t.bilingue(
                            'Indica qué se perdió. La pérdida se guarda aparte de la cosecha.',
                            'Specify what was lost. Loss is kept separate from the harvest.',
                          ),
                          TipoEvento.plaga => t.bilingue(
                            'Anota qué tan fuerte es la plaga. Si quieres, describe lo que viste en «Más detalles».',
                            'Record how bad the pest is. If you like, describe what you saw in «More details».',
                          ),
                          TipoEvento.observacion => t.bilingue(
                            'La sombra es el porcentaje del lote que queda en sombra. Deja vacío lo que no sepas.',
                            'Shade is the percentage of the plot that is shaded. Leave blank what you do not know.',
                          ),
                          _ => t.bilingue(
                            'Deja vacía la cantidad si no la conoces. Aplicar un producto no confirma que el cultivo se recuperó.',
                            'Leave the amount blank if unknown. Applying a product does not confirm the crop has recovered.',
                          ),
                        }, style: Texto.nota(context)),
                      ),
                    ],
                  ),
                  if (widget.evento != null)
                    CupertinoButton(
                      child: Text(
                        t.borrar,
                        style: letra(
                          18,
                          peso: 600,
                          color: Paleta.de(context, Paleta.rojo),
                        ),
                      ),
                      onPressed: () => confirmar(
                        context,
                        titulo: t.borrar,
                        mensaje: t.bilingue(
                          '¿Borrar este evento?',
                          'Delete this event?',
                        ),
                        accion: t.borrar,
                        cancelar: t.cancelar,
                        alConfirmar: () async {
                          await e.borrarEvento(widget.evento!.id);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ),
                ],
              ),
            ),
            PieGuardar(
              texto: t.guardar,
              alPulsar: _guardando ? null : _guardar,
              error: _error,
            ),
          ],
        ),
      ),
    );
  }
}

class PantallaPaquete extends StatefulWidget {
  const PantallaPaquete({super.key});
  @override
  State<PantallaPaquete> createState() => _Paquete();
}

class _Paquete extends State<PantallaPaquete> {
  final _texto = TextEditingController();
  String? _mensaje;
  Map<String, dynamic>? _revision;
  bool _ocupado = false;
  @override
  void dispose() {
    _texto.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context), t = Alcance.de(context).txt;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.bilingue('Paquete de datos', 'Data package')),
        previousPageTitle: t.atras,
      ),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Espacio.m),
          children: [
            Text(
              t.bilingue(
                'Incluye finca, lotes, campañas, bitácoras, restricciones y clima con sus faltantes. El contrato del modelo neuronal está pendiente de publicación.',
                'Includes farm, plots, seasons, logbooks, constraints and weather with missing values. The neural model contract is pending publication.',
              ),
              style: Texto.nota(context),
            ),
            const SizedBox(height: Espacio.m),
            BotonPrincipal(
              texto: t.bilingue('Copiar paquete JSON', 'Copy JSON package'),
              alPulsar: () async {
                await Clipboard.setData(
                  ClipboardData(
                    text: const JsonEncoder.withIndent('  ')
                        .convert(e.exportarPaquete()),
                  ),
                );
                if (mounted) {
                  setState(
                    () => _mensaje = t.bilingue(
                      'Paquete copiado.',
                      'Package copied.',
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: Espacio.l),
            Rotulo(t.bilingue('Importar paquete', 'Import package')),
            if (_revision == null)
              CupertinoTextField(
                key: const Key('paquete-json'),
                controller: _texto,
                placeholder: t.bilingue('Pegar JSON aquí', 'Paste JSON here'),
                minLines: 4,
                maxLines: 8,
                onChanged: (_) => setState(() {
                  _revision = null;
                  _mensaje = null;
                }),
              ),
            if (_revision != null)
              Fila(
                titulo: t.bilingue('Paquete revisado', 'Package reviewed'),
                detalle: t.bilingue(
                  'Toca para editar el contenido y revisarlo de nuevo.',
                  'Tap to edit the contents and review again.',
                ),
                icono: CupertinoIcons.doc_text,
                alPulsar: () => setState(() => _revision = null),
              ),
            CupertinoButton(
              onPressed: _ocupado
                  ? null
                  : () {
                      try {
                        final r = e.revisarPaquete(_texto.text);
                        setState(() {
                          _revision = r;
                          _mensaje = null;
                        });
                      } catch (error) {
                        setState(() {
                          _revision = null;
                          _mensaje = error is FormatException
                              ? error.message
                              : t.noSeGuardo;
                        });
                      }
                    },
              child: Text(
                t.bilingue(
                  'Revisar antes de importar',
                  'Review before importing',
                ),
              ),
            ),
            if (_revision != null) ...[
              Text(
                '${(_revision!['plantaciones'] as List).length} ${t.bilingue('campañas', 'seasons')} · ${(_revision!['eventos'] as List).length} ${t.bilingue('eventos detallados', 'detailed events')}',
                style: Texto.cuerpo(context),
              ),
              Text(
                t.bilingue(
                  'Los datos idénticos se conservan una sola vez. Si un identificador tiene datos distintos, se rechaza la importación completa.',
                  'Identical records are kept once. If an identifier has different data, the entire import is rejected.',
                ),
                style: Texto.nota(context),
              ),
              BotonPrincipal(
                texto: t.bilingue(
                  'Importar datos revisados',
                  'Import reviewed data',
                ),
                alPulsar: _ocupado
                    ? null
                    : () async {
                        setState(() => _ocupado = true);
                        try {
                          await e.importarPaquete(_texto.text);
                          if (mounted) {
                            setState(() {
                              _revision = null;
                              _mensaje = t.bilingue(
                                'Datos importados.',
                                'Data imported.',
                              );
                            });
                          }
                        } catch (error) {
                          if (mounted) {
                            setState(
                              () => _mensaje = error is FormatException
                                  ? error.message
                                  : t.noSeGuardo,
                            );
                          }
                        } finally {
                          if (mounted) setState(() => _ocupado = false);
                        }
                      },
              ),
            ],
            if (_mensaje != null)
              Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Text(_mensaje!, style: Texto.cuerpo(context)),
              ),
          ],
        ),
      ),
    );
  }
}
