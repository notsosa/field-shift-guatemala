/// Sistema de diseño: colores, tipografía y piezas reutilizables.
///
/// Principios: un solo color de acento, mucho espacio, superficies planas sin
/// sombras, y el dato importante en grande. Todos los colores tienen versión
/// clara y oscura.
library;

import 'package:cupertino_ui/cupertino_ui.dart';

class Paleta {
  /// Verde hoja: único color de acento de la app.
  static const verde = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF1D7A4C),
    darkColor: Color(0xFF3DD68C),
  );
  static const ambar = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFB26A00),
    darkColor: Color(0xFFFFB84D),
  );
  static const rojo = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFC2392B),
    darkColor: Color(0xFFFF7A6B),
  );
  static const azul = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF2F6FB5),
    darkColor: Color(0xFF6CB0FF),
  );
  static const fondo = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFF4F4F1),
    darkColor: Color(0xFF0B0C0B),
  );
  static const tarjeta = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF191B1A),
  );
  static const texto = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF141614),
    darkColor: Color(0xFFF3F4F2),
  );
  static const secundario = CupertinoDynamicColor.withBrightness(
    color: Color(0xFF535B55),
    darkColor: Color(0xFFB9C2BA),
  );
  static const tenue = CupertinoDynamicColor.withBrightness(
    color: Color(0xFFE6E7E3),
    darkColor: Color(0xFF2A2D2B),
  );

  static Color de(BuildContext c, CupertinoDynamicColor color) =>
      color.resolveFrom(c);
}

/// Espacios de la app, en múltiplos de 4.
class Espacio {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
  static const double borde = 20;
  static const double radio = 22;
}

/// Estilo de texto con Inter. El peso se fija también en el eje variable de la
/// fuente para que se respete en todas las plataformas.
TextStyle letra(
  double tam, {
  double peso = 400,
  Color? color,
  double? alto,
  double espaciado = 0,
}) => TextStyle(
  fontFamily: 'Inter',
  fontSize: tam,
  fontWeight: FontWeight.values[((peso / 100).round() - 1).clamp(0, 8)],
  fontVariations: [FontVariation('wght', peso)],
  color: color,
  height: alto,
  letterSpacing: espaciado,
  decoration: TextDecoration.none,
  fontFeatures: const [FontFeature.tabularFigures()],
);

class Texto {
  static TextStyle titulo(BuildContext c) => letra(
    22,
    peso: 650,
    color: Paleta.de(c, Paleta.texto),
    alto: 1.2,
    espaciado: -0.4,
  );
  static TextStyle cuerpo(BuildContext c) =>
      letra(18, color: Paleta.de(c, Paleta.texto), alto: 1.4, espaciado: -0.1);
  static TextStyle fuerte(BuildContext c) => letra(
    18,
    peso: 600,
    color: Paleta.de(c, Paleta.texto),
    alto: 1.35,
    espaciado: -0.1,
  );
  static TextStyle nota(BuildContext c) =>
      letra(16, color: Paleta.de(c, Paleta.secundario), alto: 1.4);

  /// Texto de una acción (enlace o botón de texto), en el verde de acento.
  static TextStyle accion(BuildContext c) =>
      letra(18, peso: 500, color: Paleta.de(c, Paleta.verde), alto: 1.3);
  static TextStyle etiqueta(BuildContext c) => letra(
    14,
    peso: 600,
    color: Paleta.de(c, Paleta.secundario),
    espaciado: 0.6,
  );
}

CupertinoThemeData temaApp(Brightness? brillo) {
  // Color dinámico: el tema lo resuelve en claro u oscuro según el sistema.
  const texto = Paleta.texto;
  return CupertinoThemeData(
    brightness: brillo,
    primaryColor: Paleta.verde,
    scaffoldBackgroundColor: Paleta.fondo,
    barBackgroundColor: Paleta.fondo,
    textTheme: CupertinoTextThemeData(
      primaryColor: Paleta.verde,
      textStyle: letra(16, color: texto, espaciado: -0.1),
      actionTextStyle: letra(16, peso: 500, color: Paleta.verde),
      navTitleTextStyle: letra(17, peso: 600, color: texto, espaciado: -0.3),
      navLargeTitleTextStyle: letra(
        34,
        peso: 700,
        color: texto,
        espaciado: -1.0,
      ),
      navActionTextStyle: letra(16, peso: 500, color: Paleta.verde),
      tabLabelTextStyle: letra(14, peso: 500),
      pickerTextStyle: letra(20, color: texto),
      dateTimePickerTextStyle: letra(20, color: texto),
    ),
  );
}

/// Superficie plana con esquinas amplias. Es el contenedor base de la app.
class Tarjeta extends StatelessWidget {
  const Tarjeta({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Espacio.borde),
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color ?? Paleta.de(context, Paleta.tarjeta),
      borderRadius: BorderRadius.circular(Espacio.radio),
    ),
    child: Padding(padding: padding, child: child),
  );
}

/// Rótulo en mayúsculas pequeñas sobre un grupo de contenido.
class Rotulo extends StatelessWidget {
  const Rotulo(this.texto, {super.key});

  final String texto;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      Espacio.m + Espacio.borde,
      Espacio.l,
      Espacio.borde,
      Espacio.s,
    ),
    child: Text(texto.toUpperCase(), style: Texto.etiqueta(context)),
  );
}

/// Botón principal de ancho completo.
class BotonPrincipal extends StatelessWidget {
  const BotonPrincipal({
    super.key,
    required this.texto,
    required this.alPulsar,
    this.secundario = false,
  });

  final String texto;
  final VoidCallback? alPulsar;
  final bool secundario;

  @override
  Widget build(BuildContext context) {
    final verde = Paleta.de(context, Paleta.verde);
    return SizedBox(
      width: double.infinity,
      child: CupertinoButton(
        onPressed: alPulsar,
        padding: const EdgeInsets.symmetric(vertical: 16),
        color: secundario ? null : verde,
        disabledColor: Paleta.de(context, Paleta.tenue),
        borderRadius: BorderRadius.circular(16),
        child: Text(
          texto,
          style: letra(
            18,
            peso: 600,
            color: alPulsar == null
                ? Paleta.de(context, Paleta.secundario)
                : (secundario ? verde : Paleta.de(context, Paleta.tarjeta)),
          ),
        ),
      ),
    );
  }
}

/// Fila de un grupo: título a la izquierda y un control o valor a la derecha.
class Fila extends StatelessWidget {
  const Fila({
    super.key,
    required this.titulo,
    this.detalle,
    this.final_,
    this.alPulsar,
    this.icono,
    this.colorIcono,
  });

  final String titulo;
  final String? detalle;
  final Widget? final_;
  final VoidCallback? alPulsar;
  final IconData? icono;
  final Color? colorIcono;

  @override
  Widget build(BuildContext context) {
    final contenido = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Espacio.borde,
          vertical: 14,
        ),
        child: Row(
          children: [
            if (icono != null) ...[
              Icon(
                icono,
                size: 22,
                color: colorIcono ?? Paleta.de(context, Paleta.verde),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: Texto.cuerpo(context)),
                  if (detalle != null) ...[
                    const SizedBox(height: 2),
                    Text(detalle!, style: Texto.nota(context)),
                  ],
                ],
              ),
            ),
            if (final_ != null) ...[const SizedBox(width: 12), final_!],
            if (alPulsar != null && final_ == null)
              Icon(
                CupertinoIcons.chevron_forward,
                size: 16,
                color: Paleta.de(context, Paleta.secundario),
              ),
          ],
        ),
      ),
    );
    if (alPulsar == null) return contenido;
    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: alPulsar,
      child: contenido,
    );
  }
}

/// Agrupa filas en una tarjeta con separadores finos.
class Grupo extends StatelessWidget {
  const Grupo({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final linea = Padding(
      padding: const EdgeInsets.only(left: Espacio.borde),
      child: SizedBox(
        height: 0.5,
        child: ColoredBox(color: Paleta.de(context, Paleta.tenue)),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
      child: Tarjeta(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) linea,
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Selector de opciones en una sola línea, con el estilo de control segmentado.
class Selector<T extends Object> extends StatelessWidget {
  const Selector({
    super.key,
    required this.opciones,
    required this.valor,
    required this.alCambiar,
  });

  final Map<T, String> opciones;
  final T valor;
  final ValueChanged<T> alCambiar;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, limite) {
      final grandes =
          MediaQuery.textScalerOf(context).scale(16) > 20 ||
          opciones.length > 3;
      if (grandes) {
        return Column(
          children: [
            for (final e in opciones.entries)
              Semantics(
                selected: e.key == valor,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  minimumSize: const Size(48, 48),
                  onPressed: () => alCambiar(e.key),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(e.value, style: Texto.cuerpo(context)),
                      ),
                      ExcludeSemantics(
                        child: Icon(
                          e.key == valor
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.circle,
                          color: Paleta.de(context, Paleta.verde),
                          size: 24,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      }
      return SizedBox(
        width: double.infinity,
        child: CupertinoSlidingSegmentedControl<T>(
          groupValue: valor,
          backgroundColor: Paleta.de(context, Paleta.tenue),
          thumbColor: Paleta.de(context, Paleta.tarjeta),
          padding: const EdgeInsets.all(3),
          children: {
            for (final e in opciones.entries)
              e.key: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      e.value,
                      textAlign: TextAlign.center,
                      style: letra(
                        16,
                        peso: e.key == valor ? 600 : 400,
                        color: Paleta.de(context, Paleta.texto),
                      ),
                    ),
                  ),
                ),
              ),
          },
          onValueChanged: (v) {
            if (v != null) alCambiar(v);
          },
        ),
      );
    },
  );
}

/// Campo de texto sin bordes para usar dentro de un [Grupo].
class Campo extends StatelessWidget {
  const Campo({
    super.key,
    required this.titulo,
    required this.controlador,
    this.ejemplo,
    this.teclado,
    this.alCambiar,
  });

  final String titulo;
  final TextEditingController controlador;
  final String? ejemplo;
  final TextInputType? teclado;
  final ValueChanged<String>? alCambiar;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: Espacio.borde,
      vertical: 12,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(child: Text(titulo, style: Texto.cuerpo(context))),
        const SizedBox(height: 6),
        Semantics(
          label: titulo,
          child: CupertinoTextField(
            controller: controlador,
            placeholder: ejemplo,
            keyboardType: teclado,
            onChanged: alCambiar,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            decoration: BoxDecoration(
              color: Paleta.de(context, Paleta.fondo),
              borderRadius: BorderRadius.circular(10),
            ),
            style: Texto.cuerpo(context),
            placeholderStyle: Texto.nota(context),
          ),
        ),
      ],
    ),
  );
}

/// Muestra datos secundarios solo cuando el usuario los pide.
class SeccionDesplegable extends StatefulWidget {
  const SeccionDesplegable({
    super.key,
    required this.titulo,
    required this.children,
    this.inicialmenteAbierta = false,
  });
  final String titulo;
  final List<Widget> children;
  final bool inicialmenteAbierta;
  @override
  State<SeccionDesplegable> createState() => _SeccionDesplegable();
}

class _SeccionDesplegable extends State<SeccionDesplegable> {
  late bool _abierta = widget.inicialmenteAbierta;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: Espacio.m,
          vertical: Espacio.s,
        ),
        child: Semantics(
          expanded: _abierta,
          child: Fila(
            titulo: widget.titulo,
            final_: ExcludeSemantics(
              child: Icon(
                _abierta
                    ? CupertinoIcons.chevron_up
                    : CupertinoIcons.chevron_down,
                color: Paleta.de(context, Paleta.verde),
                size: 22,
              ),
            ),
            alPulsar: () => setState(() => _abierta = !_abierta),
          ),
        ),
      ),
      if (_abierta) ...widget.children,
    ],
  );
}
