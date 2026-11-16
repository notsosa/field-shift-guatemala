/// Componentes emergentes de Field Shift: hoja de opciones, confirmación,
/// aviso, selector de fecha con calendario e interruptor con texto.
///
/// Familia visual de las tarjetas de la app: superficies planas sin desenfoque
/// ni transparencias, esquinas amplias, verde de acento, textos de 18 o más y
/// zonas táctiles de al menos 56 px. Los colores salen de [Paleta] y se
/// resuelven con `Paleta.de(context, …)`, así que funcionan en claro y oscuro.
///
/// API:
/// - [elegirOpcion]: hoja inferior para elegir una opción (devuelve `null` si
///   se cancela o se toca fuera).
/// - [confirmarAccion]: tarjeta con acción principal y «Cancelar» apilados
///   (devuelve `false` si se cancela o se toca fuera).
/// - [mostrarAviso]: tarjeta informativa con un solo botón.
/// - [elegirFecha]: hoja inferior con calendario de un mes (devuelve `null`
///   si se cancela o se toca fuera).
/// - [Interruptor]: control de dos estados con las palabras «Sí» y «No».
library;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../estado.dart';
import 'tema.dart';

const _duracion = Duration(milliseconds: 220);
const _curva = Curves.easeOutCubic;

/// Mezcla [color] con [base] en la proporción [t]. Da un color sólido (sin
/// transparencia) para tintes y estados pulsados.
Color _mezcla(Color base, Color color, double t) =>
    Color.lerp(base, color, t) ?? base;

DateTime _dia(DateTime f) => DateTime(f.year, f.month, f.day);

// ---------------------------------------------------------------------------
// Piezas comunes
// ---------------------------------------------------------------------------

/// Zona táctil plana con estado pulsado y semántica de botón.
class _Toque extends StatefulWidget {
  const _Toque({
    required this.alPulsar,
    required this.child,
    this.color,
    this.radio = 18,
    this.minAlto = 56,
    this.etiqueta,
    this.seleccionada,
    this.borde,
    this.alineacion,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
  });

  final VoidCallback? alPulsar;
  final Widget child;
  final Color? color;
  final double radio;
  final double minAlto;
  final String? etiqueta;
  final bool? seleccionada;
  final Border? borde;
  final Alignment? alineacion;
  final EdgeInsetsGeometry padding;

  @override
  State<_Toque> createState() => _EstadoToque();
}

class _EstadoToque extends State<_Toque> {
  bool _pulsado = false;

  void _poner(bool v) {
    if (_pulsado != v && mounted) setState(() => _pulsado = v);
  }

  @override
  Widget build(BuildContext context) {
    final activo = widget.alPulsar != null;
    final texto = Paleta.de(context, Paleta.texto);
    final base = widget.color;
    final fondo = _pulsado
        ? (base == null
              ? Paleta.de(context, Paleta.tenue)
              : _mezcla(base, texto, 0.14))
        : base;
    return Semantics(
      button: true,
      enabled: activo,
      selected: widget.seleccionada,
      label: widget.etiqueta,
      excludeSemantics: widget.etiqueta != null,
      onTap: widget.alPulsar,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: activo ? (_) => _poner(true) : null,
        onTapUp: activo ? (_) => _poner(false) : null,
        onTapCancel: activo ? () => _poner(false) : null,
        onTap: widget.alPulsar,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: _curva,
          constraints: BoxConstraints(minHeight: widget.minAlto),
          alignment: widget.alineacion,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: fondo,
            borderRadius: BorderRadius.circular(widget.radio),
            border: widget.borde,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

enum _Estilo { principal, peligro, secundario, texto }

/// Botón de ancho completo de las ventanas emergentes.
class _Boton extends StatelessWidget {
  const _Boton(this.texto, this.alPulsar, {this.estilo = _Estilo.principal});

  final String texto;
  final VoidCallback? alPulsar;
  final _Estilo estilo;

  @override
  Widget build(BuildContext context) {
    final verde = Paleta.de(context, Paleta.verde);
    final rojo = Paleta.de(context, Paleta.rojo);
    final tarjeta = Paleta.de(context, Paleta.tarjeta);
    final tenue = Paleta.de(context, Paleta.tenue);
    final t = Paleta.de(context, Paleta.texto);
    final activo = alPulsar != null;

    Color? fondo;
    Color tinta;
    switch (estilo) {
      case _Estilo.principal:
        fondo = activo ? verde : tenue;
        tinta = activo ? tarjeta : Paleta.de(context, Paleta.secundario);
      case _Estilo.peligro:
        fondo = activo ? rojo : tenue;
        tinta = activo ? tarjeta : Paleta.de(context, Paleta.secundario);
      case _Estilo.secundario:
        fondo = tenue;
        tinta = t;
      case _Estilo.texto:
        fondo = null;
        tinta = t;
    }
    return SizedBox(
      width: double.infinity,
      child: _Toque(
        alPulsar: alPulsar,
        color: fondo,
        radio: 18,
        minAlto: 56,
        alineacion: Alignment.center,
        child: Text(
          texto,
          textAlign: TextAlign.center,
          style: letra(18, peso: 650, color: tinta, alto: 1.25),
        ),
      ),
    );
  }
}

/// Círculo tintado con un ícono, de color sólido sobre la tarjeta.
class _Medallon extends StatelessWidget {
  const _Medallon(this.icono, this.color, {this.tam = 44});

  final IconData icono;
  final Color color;
  final double tam;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: tam,
      height: tam,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _mezcla(Paleta.de(context, Paleta.tarjeta), color, 0.16),
      ),
      child: Icon(icono, size: tam * 0.5, color: color),
    ),
  );
}

/// Marco de una hoja inferior: asa, contenido que se desplaza y pie fijo.
class _MarcoHoja extends StatelessWidget {
  const _MarcoHoja({
    required this.titulo,
    required this.cuerpo,
    required this.pie,
    this.ayuda,
  });

  final String titulo;
  final String? ayuda;
  final Widget cuerpo;
  final List<Widget> pie;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final fondo = Paleta.de(context, Paleta.tarjeta);
    final asa = _mezcla(fondo, Paleta.de(context, Paleta.secundario), 0.45);
    final abajo = mq.viewPadding.bottom + mq.viewInsets.bottom;
    // En pantallas bajas (horizontal) el pie se desplaza con el contenido.
    final corta = mq.size.height < 500;
    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: (mq.size.height - mq.viewPadding.top) * 0.94,
        ),
        child: Semantics(
          scopesRoute: true,
          explicitChildNodes: true,
          namesRoute: true,
          label: titulo,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: fondo,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                Espacio.borde,
                10,
                Espacio.borde,
                Espacio.m + abajo,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: ExcludeSemantics(
                      child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: asa,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(bottom: Espacio.s),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: Espacio.m),
                          Semantics(
                            header: true,
                            child: Text(
                              titulo,
                              style: letra(
                                26,
                                peso: 700,
                                color: Paleta.de(context, Paleta.texto),
                                alto: 1.2,
                                espaciado: -0.5,
                              ),
                            ),
                          ),
                          if (ayuda != null) ...[
                            const SizedBox(height: 6),
                            Text(ayuda!, style: Texto.nota(context)),
                          ],
                          const SizedBox(height: Espacio.m),
                          cuerpo,
                          if (corta) ...[
                            const SizedBox(height: Espacio.m),
                            for (var i = 0; i < pie.length; i++) ...[
                              if (i > 0) const SizedBox(height: Espacio.s),
                              pie[i],
                            ],
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (!corta) ...[
                    const SizedBox(height: Espacio.s),
                    for (var i = 0; i < pie.length; i++) ...[
                      if (i > 0) const SizedBox(height: Espacio.s),
                      pie[i],
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Muestra una hoja que sube desde abajo, con fondo sólido y sin desenfoque.
Future<T?> _mostrarHoja<T>(BuildContext context, WidgetBuilder builder) {
  final cancelar = Alcance.leer(context).txt.cancelar;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelar,
    barrierColor: const Color(0xA6000000),
    transitionDuration: _duracion,
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: anim, curve: _curva)),
      child: child,
    ),
  );
}

/// Muestra una tarjeta centrada que aparece con un leve zoom.
Future<T?> _mostrarTarjeta<T>(BuildContext context, WidgetBuilder builder) {
  final cancelar = Alcance.leer(context).txt.cancelar;
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: cancelar,
    barrierColor: const Color(0xA6000000),
    transitionDuration: _duracion,
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, anim, _, child) {
      final a = CurvedAnimation(parent: anim, curve: _curva);
      return FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1).animate(a),
          child: child,
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// 1. Hoja de opciones
// ---------------------------------------------------------------------------

/// Una opción de [elegirOpcion].
class OpcionHoja<T> {
  const OpcionHoja({
    required this.valor,
    required this.texto,
    this.detalle,
    this.icono,
    this.destructiva = false,
  });

  /// Valor que devuelve [elegirOpcion] al elegirla.
  final T valor;
  final String texto;

  /// Línea secundaria opcional bajo el texto.
  final String? detalle;

  /// Ícono opcional, que se dibuja en un círculo tintado.
  final IconData? icono;

  /// Si es verdadera, la fila va en rojo.
  final bool destructiva;
}

/// Hoja inferior para elegir entre varias opciones.
///
/// Devuelve el valor elegido, o `null` si se pulsa «Cancelar» o se toca fuera.
/// [seleccionada] marca la opción actual. [cancelar] cambia el texto del botón.
Future<T?> elegirOpcion<T>(
  BuildContext context, {
  required String titulo,
  String? ayuda,
  required List<OpcionHoja<T>> opciones,
  T? seleccionada,
  String? cancelar,
}) => _mostrarHoja<T>(
  context,
  (ctx) => _HojaOpciones<T>(
    titulo: titulo,
    ayuda: ayuda,
    opciones: opciones,
    seleccionada: seleccionada,
    cancelar: cancelar ?? Alcance.de(ctx).txt.cancelar,
  ),
);

class _HojaOpciones<T> extends StatelessWidget {
  const _HojaOpciones({
    required this.titulo,
    required this.ayuda,
    required this.opciones,
    required this.seleccionada,
    required this.cancelar,
  });

  final String titulo;
  final String? ayuda;
  final List<OpcionHoja<T>> opciones;
  final T? seleccionada;
  final String cancelar;

  @override
  Widget build(BuildContext context) => _MarcoHoja(
    titulo: titulo,
    ayuda: ayuda,
    cuerpo: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < opciones.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _FilaOpcion<T>(
            opcion: opciones[i],
            elegida: seleccionada != null && opciones[i].valor == seleccionada,
            alPulsar: () => Navigator.of(context).pop(opciones[i].valor),
          ),
        ],
      ],
    ),
    pie: [
      _Boton(
        cancelar,
        () => Navigator.of(context).pop(),
        estilo: _Estilo.secundario,
      ),
    ],
  );
}

class _FilaOpcion<T> extends StatelessWidget {
  const _FilaOpcion({
    required this.opcion,
    required this.elegida,
    required this.alPulsar,
  });

  final OpcionHoja<T> opcion;
  final bool elegida;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) {
    final verde = Paleta.de(context, Paleta.verde);
    final rojo = Paleta.de(context, Paleta.rojo);
    final tarjeta = Paleta.de(context, Paleta.tarjeta);
    final acento = opcion.destructiva ? rojo : verde;
    final tinta = opcion.destructiva ? rojo : Paleta.de(context, Paleta.texto);
    return _Toque(
      alPulsar: alPulsar,
      color: elegida ? _mezcla(tarjeta, acento, 0.12) : null,
      borde: Border.all(
        color: elegida ? acento : const Color(0x00000000),
        width: 2,
      ),
      radio: 20,
      minAlto: 64,
      seleccionada: elegida,
      etiqueta: opcion.detalle == null
          ? opcion.texto
          : '${opcion.texto}. ${opcion.detalle}',
      child: Row(
        children: [
          if (opcion.icono != null) ...[
            _Medallon(opcion.icono!, acento),
            const SizedBox(width: 14),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  opcion.texto,
                  style: letra(
                    18,
                    peso: elegida ? 650 : 500,
                    color: tinta,
                    alto: 1.3,
                  ),
                ),
                if (opcion.detalle != null) ...[
                  const SizedBox(height: 2),
                  Text(opcion.detalle!, style: Texto.nota(context)),
                ],
              ],
            ),
          ),
          if (elegida) ...[
            const SizedBox(width: 12),
            ExcludeSemantics(
              child: Icon(
                CupertinoIcons.checkmark_alt,
                size: 26,
                color: acento,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2 y 3. Confirmación y aviso
// ---------------------------------------------------------------------------

/// Tarjeta de confirmación con la acción y «Cancelar» apilados.
///
/// Devuelve `true` solo si se pulsa [accion]; `false` al cancelar o tocar fuera.
/// Si [destructiva], la acción va en rojo y el ícono por omisión es de
/// advertencia.
Future<bool> confirmarAccion(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String accion,
  String? cancelar,
  bool destructiva = false,
  IconData? icono,
}) async {
  final r = await _mostrarTarjeta<bool>(
    context,
    (ctx) => _TarjetaDialogo(
      titulo: titulo,
      mensaje: mensaje,
      icono:
          icono ??
          (destructiva
              ? CupertinoIcons.exclamationmark_triangle_fill
              : CupertinoIcons.question_circle_fill),
      colorIcono: destructiva ? Paleta.rojo : Paleta.verde,
      botones: [
        _Boton(
          accion,
          () => Navigator.of(ctx).pop(true),
          estilo: destructiva ? _Estilo.peligro : _Estilo.principal,
        ),
        _Boton(
          cancelar ?? Alcance.de(ctx).txt.cancelar,
          () => Navigator.of(ctx).pop(false),
          estilo: _Estilo.texto,
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Tarjeta informativa con un solo botón («Entendido» por omisión).
Future<void> mostrarAviso(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  IconData? icono,
  String? boton,
}) => _mostrarTarjeta<void>(
  context,
  (ctx) => _TarjetaDialogo(
    titulo: titulo,
    mensaje: mensaje,
    icono: icono ?? CupertinoIcons.info_circle_fill,
    colorIcono: Paleta.azul,
    botones: [
      _Boton(
        boton ?? Alcance.de(ctx).txt.bilingue('Entendido', 'Got it'),
        () => Navigator.of(ctx).pop(),
      ),
    ],
  ),
);

class _TarjetaDialogo extends StatelessWidget {
  const _TarjetaDialogo({
    required this.titulo,
    required this.mensaje,
    required this.icono,
    required this.colorIcono,
    required this.botones,
  });

  final String titulo;
  final String mensaje;
  final IconData icono;
  final CupertinoDynamicColor colorIcono;
  final List<Widget> botones;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          Espacio.l,
          Espacio.m + mq.viewPadding.top,
          Espacio.l,
          Espacio.m + mq.viewPadding.bottom + mq.viewInsets.bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            namesRoute: true,
            label: titulo,
            child: Tarjeta(
              padding: const EdgeInsets.all(Espacio.l),
              color: Paleta.de(context, Paleta.tarjeta),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: _Medallon(
                              icono,
                              Paleta.de(context, colorIcono),
                              tam: 64,
                            ),
                          ),
                          const SizedBox(height: Espacio.m),
                          Semantics(
                            header: true,
                            child: Text(
                              titulo,
                              textAlign: TextAlign.center,
                              style: letra(
                                24,
                                peso: 700,
                                color: Paleta.de(context, Paleta.texto),
                                alto: 1.2,
                                espaciado: -0.4,
                              ),
                            ),
                          ),
                          const SizedBox(height: Espacio.s),
                          Text(
                            mensaje,
                            textAlign: TextAlign.center,
                            style: letra(
                              18,
                              color: Paleta.de(context, Paleta.secundario),
                              alto: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Espacio.l),
                  for (var i = 0; i < botones.length; i++) ...[
                    if (i > 0) const SizedBox(height: 6),
                    botones[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. Selector de fecha con calendario
// ---------------------------------------------------------------------------

const _mesesEs = [
  'enero',
  'febrero',
  'marzo',
  'abril',
  'mayo',
  'junio',
  'julio',
  'agosto',
  'septiembre',
  'octubre',
  'noviembre',
  'diciembre',
];
const _mesesEn = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];

/// Hoja inferior con un calendario de un mes para elegir una fecha.
///
/// Devuelve la fecha elegida (solo día, sin hora) o `null` si se cancela o se
/// toca fuera. Los días fuera de [minimo]..[maximo] no se pueden elegir. Si
/// [inicial] está fuera del rango no se recorta: se muestra marcada en rojo,
/// con un aviso, y «Listo» queda desactivado hasta elegir otra fecha.
Future<DateTime?> elegirFecha(
  BuildContext context, {
  required DateTime inicial,
  required DateTime minimo,
  required DateTime maximo,
  String? titulo,
}) => _mostrarHoja<DateTime>(
  context,
  (ctx) => _HojaFecha(
    inicial: _dia(inicial),
    minimo: _dia(minimo),
    maximo: _dia(maximo),
    titulo: titulo,
  ),
);

class _HojaFecha extends StatefulWidget {
  const _HojaFecha({
    required this.inicial,
    required this.minimo,
    required this.maximo,
    this.titulo,
  });

  final DateTime inicial;
  final DateTime minimo;
  final DateTime maximo;
  final String? titulo;

  @override
  State<_HojaFecha> createState() => _EstadoHojaFecha();
}

class _EstadoHojaFecha extends State<_HojaFecha> {
  late DateTime _mes = DateTime(widget.inicial.year, widget.inicial.month);
  late DateTime _elegida = widget.inicial;
  bool _avanza = true;

  bool _enRango(DateTime f) =>
      !f.isBefore(widget.minimo) && !f.isAfter(widget.maximo);

  DateTime get _primerMes => DateTime(widget.minimo.year, widget.minimo.month);
  DateTime get _ultimoMes => DateTime(widget.maximo.year, widget.maximo.month);

  bool get _puedeAtras => _mes.isAfter(_primerMes);
  bool get _puedeAdelante => _mes.isBefore(_ultimoMes);

  void _moverMes(int d) {
    if (d < 0 ? !_puedeAtras : !_puedeAdelante) return;
    setState(() {
      _avanza = d > 0;
      _mes = DateTime(_mes.year, _mes.month + d);
    });
    HapticFeedback.selectionClick();
  }

  void _elegir(DateTime f) {
    if (!_enRango(f)) return;
    setState(() {
      _elegida = f;
      _mes = DateTime(f.year, f.month);
    });
  }

  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context);
    final t = e.txt;
    final hoy = _dia(e.hoy);
    final fuera = !_enRango(widget.inicial);
    final valida = _enRango(_elegida);
    final nombres = t.en ? _mesesEn : _mesesEs;
    final nombreMes = nombres[_mes.month - 1];
    final rotuloMes =
        '${t.en ? nombreMes : '${nombreMes[0].toUpperCase()}${nombreMes.substring(1)}'} ${_mes.year}';

    final atajos = <(String, DateTime)>[
      (t.bilingue('Hoy', 'Today'), hoy),
      (
        t.bilingue('Ayer', 'Yesterday'),
        DateTime(hoy.year, hoy.month, hoy.day - 1),
      ),
      (
        t.bilingue('Hace una semana', 'A week ago'),
        DateTime(hoy.year, hoy.month, hoy.day - 7),
      ),
    ].where((a) => _enRango(a.$2)).toList();

    return _MarcoHoja(
      titulo: widget.titulo ?? t.bilingue('Elige una fecha', 'Pick a date'),
      cuerpo: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fuera) ...[
            _AvisoRango(
              mensaje: t.en
                  ? 'The date ${t.fechaLarga(widget.inicial)} is outside the allowed range. Pick another one.'
                  : 'La fecha ${t.fechaLarga(widget.inicial)} está fuera del rango permitido. Elige otra.',
            ),
            const SizedBox(height: Espacio.m),
          ],
          if (atajos.isNotEmpty) ...[
            Wrap(
              spacing: Espacio.s,
              runSpacing: Espacio.s,
              children: [
                for (final a in atajos)
                  _Toque(
                    alPulsar: () => _elegir(a.$2),
                    color: _elegida == a.$2
                        ? Paleta.de(context, Paleta.verde)
                        : Paleta.de(context, Paleta.tenue),
                    radio: 28,
                    minAlto: 56,
                    seleccionada: _elegida == a.$2,
                    etiqueta: a.$1,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Text(
                      a.$1,
                      textAlign: TextAlign.center,
                      style: letra(
                        18,
                        peso: 600,
                        color: _elegida == a.$2
                            ? Paleta.de(context, Paleta.tarjeta)
                            : Paleta.de(context, Paleta.texto),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: Espacio.m),
          ],
          Row(
            children: [
              _Flecha(
                icono: CupertinoIcons.chevron_left,
                etiqueta: t.bilingue('Mes anterior', 'Previous month'),
                alPulsar: _puedeAtras ? () => _moverMes(-1) : null,
              ),
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  header: true,
                  child: Text(
                    rotuloMes,
                    textAlign: TextAlign.center,
                    style: letra(
                      20,
                      peso: 650,
                      color: Paleta.de(context, Paleta.texto),
                      alto: 1.25,
                    ),
                  ),
                ),
              ),
              _Flecha(
                icono: CupertinoIcons.chevron_right,
                etiqueta: t.bilingue('Mes siguiente', 'Next month'),
                alPulsar: _puedeAdelante ? () => _moverMes(1) : null,
              ),
            ],
          ),
          const SizedBox(height: Espacio.s),
          ExcludeSemantics(
            child: Row(
              children: [
                for (final d
                    in t.en
                        ? const ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                        : const ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
                  Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: letra(
                          16,
                          peso: 650,
                          color: Paleta.de(context, Paleta.secundario),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: _duracion,
            curve: _curva,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: _duracion,
              switchInCurve: _curva,
              switchOutCurve: _curva,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: Offset(_avanza ? 0.06 : -0.06, 0),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              layoutBuilder: (actual, previos) => Stack(
                alignment: Alignment.topCenter,
                children: [...previos, ?actual],
              ),
              child: _Cuadricula(
                key: ValueKey(_mes),
                mes: _mes,
                hoy: hoy,
                elegida: _elegida,
                enRango: _enRango,
                alElegir: _elegir,
              ),
            ),
          ),
        ],
      ),
      pie: [
        _Boton(
          t.listo,
          valida ? () => Navigator.of(context).pop(_elegida) : null,
        ),
        _Boton(
          t.cancelar,
          () => Navigator.of(context).pop(),
          estilo: _Estilo.texto,
        ),
      ],
    );
  }
}

class _AvisoRango extends StatelessWidget {
  const _AvisoRango({required this.mensaje});

  final String mensaje;

  @override
  Widget build(BuildContext context) {
    final rojo = Paleta.de(context, Paleta.rojo);
    return Semantics(
      liveRegion: true,
      container: true,
      label: mensaje,
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _mezcla(Paleta.de(context, Paleta.tarjeta), rojo, 0.12),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  size: 22,
                  color: rojo,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  mensaje,
                  style: letra(
                    18,
                    peso: 500,
                    color: Paleta.de(context, Paleta.texto),
                    alto: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Flecha extends StatelessWidget {
  const _Flecha({
    required this.icono,
    required this.etiqueta,
    required this.alPulsar,
  });

  final IconData icono;
  final String etiqueta;
  final VoidCallback? alPulsar;

  @override
  Widget build(BuildContext context) {
    final activo = alPulsar != null;
    return SizedBox(
      width: 56,
      height: 56,
      child: _Toque(
        alPulsar: alPulsar,
        etiqueta: etiqueta,
        color: Paleta.de(context, Paleta.tenue),
        radio: 28,
        padding: EdgeInsets.zero,
        alineacion: Alignment.center,
        child: Icon(
          icono,
          size: 24,
          color: activo
              ? Paleta.de(context, Paleta.texto)
              : _mezcla(
                  Paleta.de(context, Paleta.tenue),
                  Paleta.de(context, Paleta.secundario),
                  0.45,
                ),
        ),
      ),
    );
  }
}

class _Cuadricula extends StatelessWidget {
  const _Cuadricula({
    super.key,
    required this.mes,
    required this.hoy,
    required this.elegida,
    required this.enRango,
    required this.alElegir,
  });

  final DateTime mes;
  final DateTime hoy;
  final DateTime elegida;
  final bool Function(DateTime) enRango;
  final ValueChanged<DateTime> alElegir;

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    final vacios = DateTime(mes.year, mes.month).weekday - 1; // lunes = 0
    final dias = DateTime(mes.year, mes.month + 1, 0).day;
    final filas = ((vacios + dias) / 7).ceil();
    final verde = Paleta.de(context, Paleta.verde);
    final rojo = Paleta.de(context, Paleta.rojo);
    final tarjeta = Paleta.de(context, Paleta.tarjeta);
    final texto = Paleta.de(context, Paleta.texto);
    final apagado = _mezcla(
      tarjeta,
      Paleta.de(context, Paleta.secundario),
      0.5,
    );

    Widget celda(int indice) {
      final n = indice - vacios + 1;
      if (n < 1 || n > dias) return const Expanded(child: SizedBox(height: 48));
      final f = DateTime(mes.year, mes.month, n);
      final libre = enRango(f);
      final marcada = f == elegida;
      final esHoy = f == hoy;
      final rotulo = [
        t.fechaLarga(f),
        if (esHoy) t.bilingue('hoy', 'today'),
        if (!libre) t.bilingue('no disponible', 'unavailable'),
      ].join(', ');
      Color tinta = libre ? texto : apagado;
      Color? fondo;
      Border? borde;
      if (marcada && libre) {
        fondo = verde;
        tinta = tarjeta;
      } else if (marcada) {
        borde = Border.all(color: rojo, width: 2.5);
        tinta = rojo;
      } else if (esHoy) {
        borde = Border.all(color: verde, width: 2);
      }
      return Expanded(
        child: Center(
          child: SizedBox(
            width: 48,
            height: 48,
            child: _Toque(
              alPulsar: libre ? () => alElegir(f) : null,
              etiqueta: rotulo,
              seleccionada: marcada,
              color: fondo,
              borde: borde,
              radio: 24,
              minAlto: 48,
              padding: EdgeInsets.zero,
              alineacion: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$n',
                  style: letra(
                    18,
                    peso: marcada || esHoy ? 700 : 500,
                    color: tinta,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        for (var r = 0; r < filas; r++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [for (var c = 0; c < 7; c++) celda(r * 7 + c)],
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 5. Interruptor con texto
// ---------------------------------------------------------------------------

/// Control de dos estados con las palabras «Sí» y «No» siempre visibles.
///
/// Es un segmentado de dos opciones con el estilo de [Selector]: el «Sí»
/// activo va en verde y el «No» activo en tarjeta clara. [si] y [no] cambian
/// las palabras; [etiqueta] es el nombre que leen los lectores de pantalla.
class Interruptor extends StatelessWidget {
  const Interruptor({
    super.key,
    required this.valor,
    required this.alCambiar,
    this.si,
    this.no,
    this.etiqueta,
  });

  final bool valor;
  final ValueChanged<bool> alCambiar;
  final String? si;
  final String? no;
  final String? etiqueta;

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    final textoSi = si ?? t.si;
    final textoNo = no ?? t.no;
    final verde = Paleta.de(context, Paleta.verde);
    final tarjeta = Paleta.de(context, Paleta.tarjeta);
    final texto = Paleta.de(context, Paleta.texto);

    Widget segmento(bool v, String rotulo) {
      final activo = valor == v;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            alCambiar(valor == v ? !valor : v);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56, minWidth: 72),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  curve: _curva,
                  style: letra(
                    18,
                    peso: activo ? 700 : 500,
                    color: activo && v ? tarjeta : texto,
                  ),
                  child: Text(rotulo),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      toggled: valor,
      label: etiqueta,
      value: valor ? textoSi : textoNo,
      onTap: () => alCambiar(!valor),
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Paleta.de(context, Paleta.tenue),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: IntrinsicWidth(
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    curve: _curva,
                    alignment: valor
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: FractionallySizedBox(
                      widthFactor: 0.5,
                      heightFactor: 1,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: _curva,
                        decoration: BoxDecoration(
                          color: valor ? verde : tarjeta,
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                    ),
                  ),
                ),
                Row(
                  children: [segmento(true, textoSi), segmento(false, textoNo)],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
