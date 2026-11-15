/// Plano de la finca: sobre un mapa (o un croquis en blanco) el productor
/// dibuja el contorno de su finca y el perímetro de cada plantación. El lienzo
/// es un cuadrado centrado en el punto de la finca, con el norte arriba; las
/// posiciones se guardan como fracciones de ese cuadrado.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../datos/mapa.dart';
import '../estado.dart';
import '../modelos.dart';
import '../motor/recomendador.dart';
import 'hoy.dart';
import 'plantacion.dart';
import 'tema.dart';

/// Anchos del plano que se ofrecen, en metros.
const ladosMapa = <double>[200, 500, 1000, 2000];

/// Un área dibujada sobre el plano: el perímetro de una plantación.
class Zona {
  const Zona({required this.id, required this.contorno, required this.color, required this.rotulo, this.destacada = false});

  final String id;
  final List<Punto> contorno;
  final Color color;
  final String rotulo;
  final bool destacada;
}

/// Zonas de todas las plantaciones con perímetro, coloreadas según su agua.
List<Zona> zonasDe(BuildContext context, AppEstado estado, {String? excepto, bool destacar = true}) => [
      for (final p in estado.plantaciones)
        if (p.contorno.length >= 3 && p.id != excepto)
          Zona(
            id: p.id,
            contorno: p.contorno,
            color: PestanaHoy.colorNivel(context, estado.recomendacionDe(p).nivel),
            rotulo: estado.txt.nombrePlantacion(p),
            destacada: destacar && p.id == estado.plantacion?.id,
          ),
    ];

/// Imágenes del mapa que cubren la ventana de la finca. Si no hay ninguna
/// guardada ni wifi para descargarlas, muestra un aviso.
class FondoMapa extends StatefulWidget {
  const FondoMapa({
    super.key,
    required this.servicio,
    required this.capa,
    required this.latitud,
    required this.longitud,
    required this.lado,
    required this.aviso,
  });

  final ServicioMapa servicio;
  final CapaMapa capa;
  final double latitud;
  final double longitud;
  final double lado;
  final String aviso;

  @override
  State<FondoMapa> createState() => _EstadoFondo();
}

class _EstadoFondo extends State<FondoMapa> {
  late Ventana _ventana;
  int _zoom = 1;
  var _imagenes = <(int, int), Uint8List>{};
  bool _cargando = true;
  int _turno = 0;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void didUpdateWidget(FondoMapa viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.capa != widget.capa ||
        viejo.lado != widget.lado ||
        viejo.latitud != widget.latitud ||
        viejo.longitud != widget.longitud) {
      _cargar();
    }
  }

  void _cargar() {
    final turno = ++_turno;
    _ventana = Ventana.centrada(widget.latitud, widget.longitud, widget.lado);
    _zoom = _ventana.zoom(ServicioMapa.zoomMaximo(widget.capa));
    _imagenes = {};
    _cargando = true;
    final teselas = _ventana.teselas(_zoom);
    var pendientes = teselas.length;
    for (final t in teselas) {
      widget.servicio.tesela(widget.capa, _zoom, t.$1, t.$2).then((bytes) {
        if (!mounted || turno != _turno) return;
        setState(() {
          if (bytes != null) _imagenes[t] = bytes;
          if (--pendientes == 0) _cargando = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, caja) {
          final n = 1 << _zoom;
          final lado = caja.maxWidth / (_ventana.ancho * n); // tamaño de una tesela en pantalla
          return Stack(
            children: [
              for (final e in _imagenes.entries)
                Positioned(
                  left: (e.key.$1 / n - _ventana.izquierda) / _ventana.ancho * caja.maxWidth,
                  top: (e.key.$2 / n - _ventana.arriba) / _ventana.ancho * caja.maxWidth,
                  // Un pelo más grande para que no se vean costuras entre teselas.
                  width: lado + 0.5,
                  height: lado + 0.5,
                  child: Image.memory(e.value, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
                ),
              if (!_cargando && _imagenes.isEmpty)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(Espacio.m),
                    child: Text(widget.aviso, style: Texto.nota(context).copyWith(fontSize: 13), textAlign: TextAlign.center),
                  ),
                ),
              if (_imagenes.isNotEmpty)
                Positioned(
                  right: 6,
                  bottom: 4,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xB3FFFFFF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      child: Text(
                        ServicioMapa.atribucion(widget.capa),
                        style: letra(9.5, color: const Color(0xFF333333)),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      );
}

/// Lienzo cuadrado con el mapa de fondo, el contorno de la finca, las
/// plantaciones y, si se está dibujando, el trazo en curso.
class LienzoFinca extends StatelessWidget {
  const LienzoFinca({
    super.key,
    required this.finca,
    this.zonas = const [],
    this.trazo = const [],
    this.trazoEsFinca = false,
    this.alTocar,
  });

  final List<Punto> finca;
  final List<Zona> zonas;

  /// Puntos que el usuario lleva marcados.
  final List<Punto> trazo;

  /// El trazo en curso es el contorno de la finca y no una plantación.
  final bool trazoEsFinca;
  final ValueChanged<Punto>? alTocar;

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final parcela = estado.parcela;
    final conMapa = estado.capa != CapaMapa.croquis && parcela != null;

    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Espacio.radio),
        child: LayoutBuilder(
          builder: (context, caja) {
            final tam = Size(caja.maxWidth, caja.maxHeight);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: alTocar == null
                  ? null
                  : (d) => alTocar!(Punto(
                        (d.localPosition.dx / tam.width).clamp(0.0, 1.0),
                        (d.localPosition.dy / tam.height).clamp(0.0, 1.0),
                      )),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CustomPaint(
                    size: tam,
                    painter: _PintorRejilla(
                      fondo: Paleta.de(context, Paleta.tarjeta),
                      linea: Paleta.de(context, Paleta.tenue),
                    ),
                  ),
                  if (conMapa)
                    FondoMapa(
                      servicio: estado.mapa,
                      capa: estado.capa,
                      latitud: parcela.latitud,
                      longitud: parcela.longitud,
                      lado: parcela.lado,
                      aviso: estado.txt.sinMapa,
                    ),
                  CustomPaint(
                    size: tam,
                    painter: _PintorFinca(
                      finca: finca,
                      zonas: zonas,
                      trazo: trazo,
                      trazoEsFinca: trazoEsFinca,
                      sobreMapa: conMapa,
                      fondo: Paleta.de(context, Paleta.tarjeta),
                      linea: Paleta.de(context, Paleta.texto),
                      acento: Paleta.de(context, Paleta.verde),
                      texto: Paleta.de(context, Paleta.texto),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Fondo del lienzo: cuadrícula tenue para dar referencia cuando no hay mapa.
class _PintorRejilla extends CustomPainter {
  _PintorRejilla({required this.fondo, required this.linea});

  final Color fondo;
  final Color linea;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = fondo);
    final rejilla = Paint()
      ..color = linea.withValues(alpha: 0.7)
      ..strokeWidth = 1;
    for (var i = 1; i < 8; i++) {
      final v = size.width * i / 8;
      canvas.drawLine(Offset(v, 0), Offset(v, size.height), rejilla);
      canvas.drawLine(Offset(0, v), Offset(size.width, v), rejilla);
    }
  }

  @override
  bool shouldRepaint(covariant _PintorRejilla viejo) => viejo.fondo != fondo || viejo.linea != linea;
}

class _PintorFinca extends CustomPainter {
  _PintorFinca({
    required this.finca,
    required this.zonas,
    required this.trazo,
    required this.trazoEsFinca,
    required this.sobreMapa,
    required this.fondo,
    required this.linea,
    required this.acento,
    required this.texto,
  });

  final List<Punto> finca;
  final List<Zona> zonas;
  final List<Punto> trazo;
  final bool trazoEsFinca;

  /// Hay un mapa detrás: las líneas llevan un borde claro para que se lean
  /// sobre cualquier imagen.
  final bool sobreMapa;
  final Color fondo;
  final Color linea;
  final Color acento;
  final Color texto;

  Path _camino(List<Punto> puntos, Size s, {bool cerrado = true}) {
    final c = Path();
    for (var i = 0; i < puntos.length; i++) {
      final o = Offset(puntos[i].x * s.width, puntos[i].y * s.height);
      i == 0 ? c.moveTo(o.dx, o.dy) : c.lineTo(o.dx, o.dy);
    }
    if (cerrado && puntos.length >= 3) c.close();
    return c;
  }

  Path _punteado(Path origen, {double raya = 7, double hueco = 5}) {
    final salida = Path();
    for (final m in origen.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += raya + hueco) {
        salida.addPath(m.extractPath(d, math.min(d + raya, m.length)), Offset.zero);
      }
    }
    return salida;
  }

  Paint _trazo(Color color, double ancho) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = ancho
    ..strokeJoin = StrokeJoin.round
    ..strokeCap = StrokeCap.round;

  /// Dibuja una línea; sobre el mapa le pone debajo un borde claro.
  void _linea(Canvas canvas, Path camino, Color color, double ancho, {Path? borde}) {
    if (sobreMapa) canvas.drawPath(borde ?? camino, _trazo(const Color(0xE6FFFFFF), ancho + 3));
    canvas.drawPath(camino, _trazo(color, ancho));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Contorno de la finca: línea continua.
    if (finca.length >= 3) {
      final c = _camino(finca, size);
      canvas.drawPath(c, Paint()..color = acento.withValues(alpha: sobreMapa ? 0.10 : 0.06));
      _linea(canvas, c, sobreMapa ? const Color(0xFF141614) : linea, 2.5);
    }

    // Plantaciones: perímetro punteado, relleno suave y marcador con nombre.
    for (final z in zonas) {
      final c = _camino(z.contorno, size);
      final relleno = (z.destacada ? 0.30 : 0.14) + (sobreMapa ? 0.12 : 0);
      canvas.drawPath(c, Paint()..color = z.color.withValues(alpha: relleno));
      _linea(canvas, _punteado(c), z.color, z.destacada ? 3 : 2, borde: c);

      final centro = centroDe(z.contorno);
      final o = Offset(centro.x * size.width, centro.y * size.height - 8);
      if (sobreMapa) canvas.drawCircle(o, (z.destacada ? 10 : 8) + 2, Paint()..color = const Color(0xE6FFFFFF));
      canvas.drawCircle(o, z.destacada ? 10 : 8, Paint()..color = z.color);
      canvas.drawCircle(o, z.destacada ? 4 : 3, Paint()..color = fondo);

      final rotulo = TextPainter(
        text: TextSpan(text: z.rotulo, style: letra(12.5, peso: z.destacada ? 700 : 600, color: texto)),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width * 0.4);
      final esquina = Offset(o.dx - rotulo.width / 2, o.dy + 13);
      if (sobreMapa) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(esquina.dx - 5, esquina.dy - 1, rotulo.width + 10, rotulo.height + 2),
            const Radius.circular(6),
          ),
          Paint()..color = fondo.withValues(alpha: 0.88),
        );
      }
      rotulo.paint(canvas, esquina);
    }

    // Trazo en curso.
    if (trazo.isNotEmpty) {
      final color = trazoEsFinca ? (sobreMapa ? const Color(0xFF141614) : linea) : acento;
      final c = _camino(trazo, size);
      if (trazo.length >= 3) canvas.drawPath(c, Paint()..color = acento.withValues(alpha: sobreMapa ? 0.22 : 0.12));
      _linea(canvas, trazoEsFinca ? c : _punteado(c), color, 2.5, borde: c);
      for (final p in trazo) {
        final o = Offset(p.x * size.width, p.y * size.height);
        if (sobreMapa) canvas.drawCircle(o, 8.5, Paint()..color = const Color(0xE6FFFFFF));
        canvas.drawCircle(o, 6.5, Paint()..color = color);
        canvas.drawCircle(o, 3, Paint()..color = const Color(0xFFFFFFFF));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PintorFinca viejo) => true;
}

/// Elige el fondo del plano: mapa, satélite o croquis en blanco.
class SelectorCapa extends StatelessWidget {
  const SelectorCapa({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    return Selector<CapaMapa>(
      opciones: {for (final c in CapaMapa.values) c: estado.txt.nombreCapa(c)},
      valor: estado.capa,
      alCambiar: (c) => Alcance.leer(context).cambiarCapa(c),
    );
  }
}

/// Pantalla para dibujar un contorno tocando sus esquinas sobre el mapa.
/// Devuelve la lista de puntos, una lista vacía si se omite, o nada si se
/// cancela.
class PantallaTrazo extends StatefulWidget {
  const PantallaTrazo({
    super.key,
    required this.titulo,
    required this.ayuda,
    this.inicial = const [],
    this.excepto,
    this.dibujaFinca = false,
    this.permiteOmitir = false,
  });

  final String titulo;
  final String ayuda;
  final List<Punto> inicial;

  /// Plantación que no se dibuja de fondo porque es la que se está trazando.
  final String? excepto;

  /// Se está dibujando el contorno de la finca y no una plantación.
  final bool dibujaFinca;
  final bool permiteOmitir;

  @override
  State<PantallaTrazo> createState() => _EstadoTrazo();
}

class _EstadoTrazo extends State<PantallaTrazo> {
  late List<Punto> _puntos = [...widget.inicial];

  Future<void> _cambiarLado(double nuevo) async {
    final estado = Alcance.leer(context);
    final viejo = estado.parcela!.lado;
    await estado.cambiarLado(nuevo);
    // Lo que ya se marcó se queda en el mismo lugar del terreno.
    if (mounted) setState(() => _puntos = reescalar(_puntos, viejo, nuevo));
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final parcela = estado.parcela!;
    final verde = Paleta.de(context, Paleta.verde);
    final listo = _puntos.length >= 3;

    Widget accion(String texto, VoidCallback? alPulsar) => CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          onPressed: alPulsar,
          child: Text(
            texto,
            style: letra(15, peso: 500, color: alPulsar == null ? Paleta.de(context, Paleta.secundario) : verde),
          ),
        );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(widget.titulo),
        previousPageTitle: t.atras,
        border: null,
        trailing: widget.permiteOmitir
            ? CupertinoButton(
                padding: EdgeInsets.zero,
                onPressed: () => Navigator.of(context).pop(const <Punto>[]),
                child: Text(t.omitir),
              )
            : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.borde + Espacio.m, Espacio.m, Espacio.borde + Espacio.m, Espacio.m),
              child: Text(widget.ayuda, style: Texto.nota(context)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Espacio.m),
              child: SelectorCapa(),
            ),
            if (widget.dibujaFinca)
              Padding(
                padding: const EdgeInsets.fromLTRB(Espacio.m, Espacio.s, Espacio.m, 0),
                child: Row(
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: Espacio.s, right: Espacio.m),
                      child: Text(t.anchoMapa, style: Texto.nota(context)),
                    ),
                    Expanded(
                      child: Selector<double>(
                        opciones: {
                          for (final l in {...ladosMapa, parcela.lado}.toList()..sort()) l: t.nombreLado(l),
                        },
                        valor: parcela.lado,
                        alCambiar: _cambiarLado,
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Center(
                  child: LienzoFinca(
                    key: const Key('lienzo'),
                    finca: widget.dibujaFinca ? const [] : parcela.contorno,
                    zonas: zonasDe(context, estado, excepto: widget.excepto, destacar: false),
                    trazo: _puntos,
                    trazoEsFinca: widget.dibujaFinca,
                    alTocar: (p) => setState(() => _puntos = [..._puntos, p]),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
              child: Row(
                children: [
                  const SizedBox(width: Espacio.s),
                  Expanded(
                    child: Text(
                      listo
                          ? '${t.puntosMarcados(_puntos.length)} · ${t.area(areaDe(_puntos, parcela.lado))}'
                          : t.puntosMarcados(_puntos.length),
                      style: Texto.nota(context),
                    ),
                  ),
                  accion(
                    t.deshacer,
                    _puntos.isEmpty ? null : () => setState(() => _puntos = _puntos.sublist(0, _puntos.length - 1)),
                  ),
                  accion(t.borrarTrazo, _puntos.isEmpty ? null : () => setState(() => _puntos = [])),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, Espacio.m),
              child: BotonPrincipal(
                texto: t.continuar,
                alPulsar: listo ? () => Navigator.of(context).pop(_puntos) : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Flujo para ingresar una plantación nueva: si la finca aún no tiene
/// contorno, se ofrece dibujarlo; luego se marca el perímetro de la plantación
/// y al final se llenan sus datos.
Future<void> agregarPlantacion(BuildContext context, {bool primeraVez = false}) async {
  final estado = Alcance.leer(context);
  final navegador = Navigator.of(context, rootNavigator: true);
  final t = estado.txt;

  if (estado.parcela!.contorno.length < 3) {
    final finca = await navegador.push<List<Punto>>(CupertinoPageRoute(
      builder: (_) => PantallaTrazo(
        titulo: t.contornoFinca,
        ayuda: t.ayudaTrazoFinca,
        dibujaFinca: true,
        permiteOmitir: true,
      ),
    ));
    if (finca == null) return;
    if (finca.length >= 3) await estado.guardarContornoFinca(finca);
  }

  final perimetro = await navegador.push<List<Punto>>(CupertinoPageRoute(
    builder: (_) => PantallaTrazo(titulo: t.perimetro, ayuda: t.ayudaTrazoPlantacion),
  ));
  if (perimetro == null) return;

  await navegador.push<void>(CupertinoPageRoute(
    builder: (_) => PantallaPlantacion(primeraVez: primeraVez, contornoNuevo: perimetro),
  ));
}

/// Nombre de la plantación que se está viendo. Si hay varias, es un botón para
/// cambiar de una a otra.
class CambioPlantacion extends StatelessWidget {
  const CambioPlantacion({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final actual = estado.plantacion!;
    final gris = Paleta.de(context, Paleta.secundario);
    final texto = Text('${t.nombrePlantacion(actual)} · ${estado.parcela!.nombre}', style: letra(16, color: gris));
    if (estado.plantaciones.length < 2) return texto;

    return Align(
      alignment: Alignment.centerLeft,
      child: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => showCupertinoModalPopup<void>(
          context: context,
          builder: (ctx) => CupertinoActionSheet(
            title: Text(t.plantaciones),
            actions: [
              for (final p in estado.plantaciones)
                CupertinoActionSheetAction(
                  isDefaultAction: p.id == actual.id,
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    estado.seleccionar(p.id);
                  },
                  child: Text('${t.nombrePlantacion(p)} · ${t.fechaCorta(p.fecha)}'),
                ),
            ],
            cancelButton: CupertinoActionSheetAction(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(t.cancelar),
            ),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            texto,
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_down, size: 14, color: gris),
          ],
        ),
      ),
    );
  }
}

/// Pestaña con el mapa de la finca y la lista de plantaciones.
class PestanaFinca extends StatelessWidget {
  const PestanaFinca({super.key, required this.alVerHoy});

  /// Lleva a la pestaña Hoy después de elegir una plantación de la lista.
  final VoidCallback alVerHoy;

  Future<void> _editarContorno(BuildContext context) async {
    final estado = Alcance.leer(context);
    final t = estado.txt;
    final nuevo = await Navigator.of(context, rootNavigator: true).push<List<Punto>>(CupertinoPageRoute(
      builder: (_) => PantallaTrazo(
        titulo: t.contornoFinca,
        ayuda: t.ayudaTrazoFinca,
        dibujaFinca: true,
        inicial: estado.parcela!.contorno,
      ),
    ));
    if (nuevo != null && nuevo.length >= 3) await estado.guardarContornoFinca(nuevo);
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final parcela = estado.parcela!;
    final zonas = zonasDe(context, estado);
    final verde = Paleta.de(context, Paleta.verde);
    final tieneContorno = parcela.contorno.length >= 3;

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(t.finca),
            border: null,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => agregarPlantacion(context),
              child: const Icon(CupertinoIcons.add, size: 26),
            ),
          ),
          SliverList.list(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.m, 0, Espacio.m, Espacio.m),
              child: Text(
                [
                  parcela.nombre,
                  t.cuantasPlantaciones(estado.plantaciones.length),
                  if (tieneContorno) t.area(areaDe(parcela.contorno, parcela.lado)),
                ].join(' · '),
                style: letra(16, color: Paleta.de(context, Paleta.secundario)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(Espacio.m, 0, Espacio.m, Espacio.m),
              child: SelectorCapa(),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
              child: LienzoFinca(
                key: const Key('lienzo-finca'),
                finca: parcela.contorno,
                zonas: zonas,
                alTocar: (p) {
                  // La última dibujada queda encima, así que se busca al revés.
                  for (final z in zonas.reversed) {
                    if (dentroDe(z.contorno, p)) {
                      Alcance.leer(context).seleccionar(z.id);
                      return;
                    }
                  }
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.m, Espacio.xs, Espacio.m, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (zonas.length > 1)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Espacio.s, Espacio.s, Espacio.s, 0),
                      child: Text(t.tocaParaElegir, style: Texto.nota(context).copyWith(fontSize: 13)),
                    ),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(horizontal: Espacio.s, vertical: 10),
                    onPressed: () => _editarContorno(context),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.pencil, size: 18, color: verde),
                        const SizedBox(width: 6),
                        Text(
                          tieneContorno ? t.editarContorno : t.dibujarContorno,
                          style: letra(15, peso: 500, color: verde),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Rotulo(t.plantaciones),
            Grupo(children: [
              for (final p in estado.plantaciones)
                Builder(builder: (context) {
                  final r = estado.recomendacionDe(p);
                  final elegida = p.id == estado.plantacion?.id;
                  final agua = r.nivel == NivelAgua.sinDatos
                      ? t.nuncaSincronizado
                      : '${t.porcentajeAgua((r.reserva * 100).round())} · ${t.nombreEtapa(r.etapa)}';
                  return Fila(
                    titulo: t.nombrePlantacion(p),
                    detalle: p.contorno.length >= 3
                        ? '$agua\n${t.area(areaDe(p.contorno, parcela.lado))}'
                        : '$agua\n${t.perimetro}: ${t.sinDibujar.toLowerCase()}',
                    icono: elegida ? CupertinoIcons.largecircle_fill_circle : CupertinoIcons.circle_fill,
                    colorIcono: PestanaHoy.colorNivel(context, r.nivel),
                    alPulsar: () {
                      Alcance.leer(context).seleccionar(p.id);
                      alVerHoy();
                    },
                  );
                }),
            ]),
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.l, Espacio.l, 0),
              child: BotonPrincipal(texto: t.nuevaPlantacion, alPulsar: () => agregarPlantacion(context)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.borde + Espacio.m, Espacio.m, Espacio.borde + Espacio.m, Espacio.xl),
              child: Text(t.croquisNota, style: Texto.nota(context), textAlign: TextAlign.center),
            ),
          ]),
        ],
      ),
    );
  }
}
