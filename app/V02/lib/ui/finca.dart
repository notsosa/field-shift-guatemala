/// Plano de la finca: sobre un mapa (o un croquis en blanco) el productor
/// dibuja el contorno de su finca y el perímetro de cada plantación. El lienzo
/// es un cuadrado centrado en el punto de la finca, con el norte arriba; las
/// posiciones se guardan como fracciones de ese cuadrado.
library;

import 'dart:math' as math;
import 'dart:convert';

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../datos/mapa.dart';
import '../estado.dart';
import '../modelos.dart';
import '../motor/recomendador.dart' show NivelAgua;
import 'hoy.dart';
import 'plantacion.dart';
import 'tema.dart';
import 'emergentes.dart' as emergentes;
import 'flujo.dart';
import 'parcela.dart';

/// Un área dibujada sobre el plano: el perímetro de una plantación.
class Zona {
  const Zona({
    required this.id,
    required this.contorno,
    required this.color,
    required this.rotulo,
    this.destacada = false,
  });

  final String id;
  final List<Punto> contorno;
  final Color color;
  final String rotulo;
  final bool destacada;
}

/// Zonas de todas las plantaciones con perímetro, coloreadas según su agua.
///
/// Los contornos están guardados para el ancho del plano de la finca. Si se
/// van a mostrar con otro [lado] (mientras se prueba un ancho sin guardarlo),
/// se ajustan para quedar en el mismo lugar del terreno.
List<Zona> zonasDe(
  BuildContext context,
  AppEstado estado, {
  String? excepto,
  bool destacar = true,
  double? lado,
}) => [
  for (final l in estado.lotes)
    if (!estado.plantaciones.any((p) => p.loteId == l.id) &&
        l.geometria.length >= 3)
      Zona(
        id: l.id,
        contorno: MarcoPlano(
          estado.parcela!.latitud,
          estado.parcela!.longitud,
          lado ?? estado.parcela!.lado,
        ).aPlano(l.geometria),
        color: Paleta.de(context, Paleta.secundario),
        rotulo:
            '${estado.txt.bilingue('Lote disponible', 'Available plot')} ${estado.lotes.indexOf(l) + 1}',
      ),
  for (final p in estado.plantaciones)
    if (p.contorno.length >= 3 && p.id != excepto)
      Zona(
        id: p.id,
        contorno: lado == null || lado == estado.parcela!.lado
            ? p.contorno
            : reescalar(p.contorno, estado.parcela!.lado, lado),
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
      final lado =
          caja.maxWidth /
          (_ventana.ancho * n); // tamaño de una tesela en pantalla
      return Stack(
        children: [
          for (final e in _imagenes.entries)
            Positioned(
              left:
                  (e.key.$1 / n - _ventana.izquierda) /
                  _ventana.ancho *
                  caja.maxWidth,
              top:
                  (e.key.$2 / n - _ventana.arriba) /
                  _ventana.ancho *
                  caja.maxWidth,
              // Un pelo más grande para que no se vean costuras entre teselas.
              width: lado + 0.5,
              height: lado + 0.5,
              child: Image.memory(
                e.value,
                fit: BoxFit.fill,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
          if (!_cargando && _imagenes.isEmpty)
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: Text(
                  widget.aviso,
                  style: Texto.nota(context),
                  textAlign: TextAlign.center,
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
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
    this.lado,
    this.alTocar,
  });

  final List<Punto> finca;
  final List<Zona> zonas;

  /// Ancho del plano que se muestra. Si falta, es el guardado en la finca.
  final double? lado;

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
            return InteractiveViewer(
              key: ValueKey('vista-${lado ?? parcela?.lado}'),
              minScale: 1,
              maxScale: 12,
              boundaryMargin: const EdgeInsets.all(100),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: alTocar == null
                    ? null
                    : (d) => alTocar!(
                        Punto(
                          (d.localPosition.dx / tam.width).clamp(0.0, 1.0),
                          (d.localPosition.dy / tam.height).clamp(0.0, 1.0),
                        ),
                      ),
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
                        lado: lado ?? parcela.lado,
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
  bool shouldRepaint(covariant _PintorRejilla viejo) =>
      viejo.fondo != fondo || viejo.linea != linea;
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
        salida.addPath(
          m.extractPath(d, math.min(d + raya, m.length)),
          Offset.zero,
        );
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
  void _linea(
    Canvas canvas,
    Path camino,
    Color color,
    double ancho, {
    Path? borde,
  }) {
    if (sobreMapa) {
      canvas.drawPath(
        borde ?? camino,
        _trazo(const Color(0xE6FFFFFF), ancho + 3),
      );
    }
    canvas.drawPath(camino, _trazo(color, ancho));
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Contorno de la finca: línea continua.
    if (finca.length >= 3) {
      final c = _camino(finca, size);
      canvas.drawPath(
        c,
        Paint()..color = acento.withValues(alpha: sobreMapa ? 0.10 : 0.06),
      );
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
      if (sobreMapa) {
        canvas.drawCircle(
          o,
          (z.destacada ? 10 : 8) + 2,
          Paint()..color = const Color(0xE6FFFFFF),
        );
      }
      canvas.drawCircle(o, z.destacada ? 10 : 8, Paint()..color = z.color);
      canvas.drawCircle(o, z.destacada ? 4 : 3, Paint()..color = fondo);

      final rotulo = TextPainter(
        text: TextSpan(
          text: z.rotulo,
          style: letra(12.5, peso: z.destacada ? 700 : 600, color: texto),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: size.width * 0.4);
      final esquina = Offset(o.dx - rotulo.width / 2, o.dy + 13);
      if (sobreMapa) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              esquina.dx - 5,
              esquina.dy - 1,
              rotulo.width + 10,
              rotulo.height + 2,
            ),
            const Radius.circular(6),
          ),
          Paint()..color = fondo.withValues(alpha: 0.88),
        );
      }
      rotulo.paint(canvas, esquina);
    }

    // Trazo en curso.
    if (trazo.isNotEmpty) {
      final color = trazoEsFinca
          ? (sobreMapa ? const Color(0xFF141614) : linea)
          : acento;
      final c = _camino(trazo, size);
      if (trazo.length >= 3) {
        canvas.drawPath(
          c,
          Paint()..color = acento.withValues(alpha: sobreMapa ? 0.22 : 0.12),
        );
      }
      _linea(canvas, trazoEsFinca ? c : _punteado(c), color, 2.5, borde: c);
      for (final p in trazo) {
        final o = Offset(p.x * size.width, p.y * size.height);
        if (sobreMapa) {
          canvas.drawCircle(o, 8.5, Paint()..color = const Color(0xE6FFFFFF));
        }
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

/// Lo que sale de [PantallaTrazo]: los puntos marcados y el ancho del plano
/// con el que se marcaron.
class Trazo {
  const Trazo(this.puntos, this.lado);

  final List<Punto> puntos;
  final double lado;
}

/// Pantalla para dibujar un contorno tocando sus esquinas sobre el mapa.
///
/// No guarda nada por sí misma: ni los puntos ni el ancho del plano. Al
/// continuar entrega un [Trazo] (con [alContinuar] si forma parte de un flujo
/// de varios pasos, o como resultado de la ruta si no). Si se sale con
/// «Atrás», no cambia nada.
class PantallaTrazo extends StatefulWidget {
  const PantallaTrazo({
    super.key,
    required this.titulo,
    required this.ayuda,
    this.inicial = const [],
    this.excepto,
    this.dibujaFinca = false,
    this.permiteOmitir = false,
    this.fincaPendiente,
    this.lado,
    this.alContinuar,
  });

  final String titulo;
  final String ayuda;
  final List<Punto> inicial;

  /// Contorno de la finca dibujado en un paso anterior y aún sin guardar.
  final List<Punto>? fincaPendiente;

  /// Ancho del plano elegido en un paso anterior y aún sin guardar.
  final double? lado;

  /// Paso siguiente del flujo. Recibe el trazo (sin puntos si se omitió). Si
  /// falta, la pantalla se cierra y devuelve el trazo.
  final void Function(BuildContext context, Trazo trazo)? alContinuar;

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

  /// Ancho del plano mientras se dibuja. Solo se guarda al terminar el flujo.
  double? _lado;

  void _cambiarLado(double actual, double nuevo) => setState(() {
    // Lo que ya se marcó se queda en el mismo lugar del terreno.
    _puntos = reescalar(_puntos, actual, nuevo);
    _lado = nuevo;
  });

  void _entregar(List<Punto> puntos, double lado) {
    final trazo = Trazo(puntos, lado);
    if (widget.alContinuar != null) {
      widget.alContinuar!(context, trazo);
    } else {
      Navigator.of(context).pop(trazo);
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final parcela = estado.parcela!;
    final verde = Paleta.de(context, Paleta.verde);
    final lado = _lado ?? widget.lado ?? parcela.lado;
    final finca = widget.dibujaFinca
        ? const <Punto>[]
        : widget.fincaPendiente ??
              reescalar(parcela.contorno, parcela.lado, lado);

    final error = _puntos.length < 3
        ? null
        : estado.validarTrazo(
            _puntos,
            finca: widget.dibujaFinca,
            excepto: widget.excepto,
            lado: lado,
            fincaPendiente: widget.fincaPendiente,
          );
    final listo = _puntos.length >= 3 && error == null;

    Widget accion(String texto, VoidCallback? alPulsar) => CupertinoButton(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      onPressed: alPulsar,
      child: Text(
        texto,
        style: Texto.accion(context).copyWith(
          color: alPulsar == null
              ? Paleta.de(context, Paleta.secundario)
              : verde,
        ),
      ),
    );

    // Escala del plano: se sube o baja por pasos entre los tamaños de la
    // unidad elegida en Ajustes.
    final tamanos = ladosDe(estado.unidad);
    final menores = tamanos.where((l) => l < lado - 0.5);
    final mayores = tamanos.where((l) => l > lado + 0.5);
    final menor = menores.isEmpty ? null : menores.last;
    final mayor = mayores.isEmpty ? null : mayores.first;

    Widget paso(IconData icono, VoidCallback? alPulsar) => CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: const Size(40, 40),
      onPressed: alPulsar,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Paleta.de(context, Paleta.tenue),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icono,
          size: 18,
          color: alPulsar == null
              ? Paleta.de(context, Paleta.secundario)
              : verde,
        ),
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
                onPressed: () => _entregar(const [], lado),
                child: Text(t.omitir),
              )
            : null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Espacio.borde + Espacio.m,
                Espacio.m,
                Espacio.borde + Espacio.m,
                Espacio.m,
              ),
              child: Text(
                '${widget.ayuda} ${t.vistaMapaAyuda}',
                style: Texto.nota(context),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: Espacio.m),
              child: SelectorCapa(),
            ),
            if (widget.dibujaFinca)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Espacio.m,
                  Espacio.s,
                  Espacio.m,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: Espacio.s),
                        child: Text(t.escalaMapa, style: Texto.nota(context)),
                      ),
                    ),
                    paso(
                      CupertinoIcons.minus,
                      menor == null ? null : () => _cambiarLado(lado, menor),
                    ),
                    SizedBox(
                      width: 96,
                      child: Text(
                        t.nombreLado(lado),
                        key: const Key('escala'),
                        textAlign: TextAlign.center,
                        style: Texto.fuerte(context),
                      ),
                    ),
                    paso(
                      CupertinoIcons.plus,
                      mayor == null ? null : () => _cambiarLado(lado, mayor),
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
                    finca: finca,
                    zonas: zonasDe(
                      context,
                      estado,
                      excepto: widget.excepto,
                      destacar: false,
                      lado: lado,
                    ),
                    trazo: _puntos,
                    trazoEsFinca: widget.dibujaFinca,
                    lado: lado,
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
                          ? '${t.puntosMarcados(_puntos.length)} · ${t.area(areaGeografica(MarcoPlano(parcela.latitud, parcela.longitud, lado).aGeografico(_puntos)))}'
                          : t.puntosMarcados(_puntos.length),
                      style: Texto.nota(context),
                    ),
                  ),
                  accion(
                    t.deshacer,
                    _puntos.isEmpty
                        ? null
                        : () => setState(
                            () => _puntos = _puntos.sublist(
                              0,
                              _puntos.length - 1,
                            ),
                          ),
                  ),
                  accion(
                    t.borrarTrazo,
                    _puntos.isEmpty ? null : () => setState(() => _puntos = []),
                  ),
                ],
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
                child: Text(
                  t.errorGeometria(error),
                  key: const Key('error-geometria'),
                  style: Texto.nota(context)
                      .copyWith(color: Paleta.de(context, Paleta.rojo)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Espacio.l,
                Espacio.s,
                Espacio.l,
                Espacio.m,
              ),
              child: BotonPrincipal(
                texto: t.continuar,
                alPulsar: listo ? () => _entregar(_puntos, lado) : null,
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
///
/// Cada paso abre el siguiente encima, sin cerrarse, de modo que «Atrás»
/// vuelve al paso anterior con lo que se había marcado. Nada se guarda hasta
/// pulsar «Guardar» en el último paso: si se abandona antes, la finca queda
/// como estaba.
Future<void> agregarPlantacion(
  BuildContext context, {
  bool primeraVez = false,
}) {
  final estado = Alcance.leer(context);
  final navegador = Navigator.of(context, rootNavigator: true);
  final t = estado.txt;

  // Paso 2: perímetro de la plantación. [finca] es el contorno recién dibujado
  // en el paso 1, todavía sin guardar.
  CupertinoPageRoute<void> perimetro({Trazo? finca}) => CupertinoPageRoute(
    builder: (_) => PantallaTrazo(
      titulo: t.perimetro,
      ayuda: t.ayudaTrazoPlantacion,
      fincaPendiente: finca != null && finca.puntos.length >= 3
          ? finca.puntos
          : null,
      lado: finca?.lado,
      // Paso 3: datos de la plantación; ahí se guarda todo.
      alContinuar: (ctx, trazo) => Navigator.of(ctx).push<void>(
        CupertinoPageRoute(
          builder: (_) => PantallaPlantacion(
            primeraVez: primeraVez,
            contornoNuevo: trazo.puntos,
            fincaNueva: finca,
          ),
        ),
      ),
    ),
  );

  if (estado.parcela!.contorno.length >= 3) {
    return navegador.push<void>(perimetro());
  }

  // Paso 1: contorno de la finca, que se puede omitir.
  return navegador.push<void>(
    CupertinoPageRoute(
      builder: (_) => PantallaTrazo(
        titulo: t.contornoFinca,
        ayuda: t.ayudaTrazoFinca,
        dibujaFinca: true,
        permiteOmitir: true,
        alContinuar: (ctx, trazo) =>
            Navigator.of(ctx).push<void>(perimetro(finca: trazo)),
      ),
    ),
  );
}

/// Nombre de la plantación que se está viendo. Si hay varias, es un botón para
/// cambiar de una a otra.
class CambioPlantacion extends StatelessWidget {
  const CambioPlantacion({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final actual = estado.plantacion;
    if (actual == null) return const SizedBox.shrink();
    final gris = Paleta.de(context, Paleta.secundario);
    final texto = Text(
      identificarPlantacion(estado, actual),
      style: Texto.cuerpo(context).copyWith(color: gris),
    );
    if (estado.plantaciones.length < 2) return texto;

    return Align(
      alignment: Alignment.centerLeft,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(vertical: 12),
        minimumSize: const Size(48, 56),
        onPressed: () async {
          final id = await emergentes.elegirOpcion<String>(
            context,
            titulo: t.plantaciones,
            seleccionada: actual.id,
            opciones: [
              for (final p in estado.plantaciones)
                emergentes.OpcionHoja(
                  valor: p.id,
                  texto:
                      '${identificarPlantacion(estado, p)} · ${t.fechaCorta(p.fecha)}',
                  icono: CupertinoIcons.tree,
                ),
            ],
          );
          if (id != null) estado.seleccionar(id);
        },
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(child: texto),
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_down, size: 14, color: gris),
          ],
        ),
      ),
    );
  }
}

/// Toda la configuración de finca y plantaciones empieza aquí.
class PestanaFinca extends StatelessWidget {
  const PestanaFinca({super.key});
  @override
  Widget build(BuildContext context) {
    final e = Alcance.de(context),
        t = Alcance.de(context).txt,
        finca = e.parcela!;
    final raiz = Navigator.of(context, rootNavigator: true);
    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(largeTitle: Text(t.finca), border: null),
          SliverList.list(
            children: [
              Grupo(
                children: [
                  Fila(
                    titulo: finca.nombre,
                    detalle: t.bilingue(
                      'Datos y ubicación de la finca',
                      'Farm details and location',
                    ),
                    icono: CupertinoIcons.location,
                    alPulsar: () => raiz.push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const PantallaParcela(),
                      ),
                    ),
                  ),
                ],
              ),
              Rotulo(t.plantaciones),
              Grupo(
                children: [
                  for (final lote in e.lotes)
                    Builder(
                      builder: (context) {
                        final actuales = e.plantaciones
                            .where((p) => p.loteId == lote.id)
                            .toList();
                        final p = actuales.isEmpty ? null : actuales.single;
                        final numero = e.lotes.indexOf(lote) + 1;
                        final r = p == null ? null : e.recomendacionDe(p);
                        final agua = r == null
                            ? null
                            : r.nivel == NivelAgua.sinDatos
                            ? t.sinDato
                            : t.porcentajeAgua((r.reserva * 100).round());
                        return Fila(
                          key: Key('finca-lote-${lote.id}'),
                          titulo: p == null
                              ? t.bilingue('Lote disponible', 'Available plot')
                              : t.nombrePlantacion(p),
                          detalle: p == null
                              ? '${t.bilingue('Lote', 'Plot')} $numero · ${t.bilingue('Sin cultivo actual', 'No current crop')}'
                              : '$agua · ${t.nombreEtapa(r!.etapa)}\n${t.bilingue('Lote', 'Plot')} $numero · ${t.nombreRiego(p.riego)}',
                          icono: p == null
                              ? CupertinoIcons.tree
                              : CupertinoIcons.circle_fill,
                          colorIcono: r == null
                              ? null
                              : PestanaHoy.colorNivel(context, r.nivel),
                          alPulsar: () {
                            if (p != null) e.seleccionar(p.id);
                            raiz.push(
                              CupertinoPageRoute<void>(
                                builder: (_) =>
                                    PantallaMiPlantacion(loteId: lote.id),
                              ),
                            );
                          },
                        );
                      },
                    ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(Espacio.m),
                child: BotonPrincipal(
                  texto: t.nuevaPlantacion,
                  alPulsar: () => agregarPlantacion(context),
                ),
              ),
              Grupo(
                children: [
                  Fila(
                    titulo: t.bilingue('Ver mapa de la finca', 'View farm map'),
                    icono: CupertinoIcons.map,
                    alPulsar: () => raiz.push(
                      CupertinoPageRoute<void>(
                        builder: (_) => const PantallaMapaFinca(),
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

class PantallaMapaFinca extends StatelessWidget {
  const PantallaMapaFinca({super.key});

  Future<void> _editarContorno(BuildContext context) async {
    final estado = Alcance.leer(context);
    final t = estado.txt;
    final nuevo = await Navigator.of(context, rootNavigator: true).push<Trazo>(
      CupertinoPageRoute(
        builder: (_) => PantallaTrazo(
          titulo: t.contornoFinca,
          ayuda: t.ayudaTrazoFinca,
          dibujaFinca: true,
          inicial: estado.parcela!.contorno,
        ),
      ),
    );
    // Solo llega un trazo si se pulsó «Continuar»; con «Atrás» no cambia nada.
    if (nuevo != null) {
      await estado.guardarFinca(contorno: nuevo.puntos, lado: nuevo.lado);
    }
  }

  static Future<void> copiarGeoJson(BuildContext context) async {
    final e = Alcance.leer(context);
    String mensaje;
    try {
      await Clipboard.setData(
        ClipboardData(
          text: const JsonEncoder.withIndent('  ').convert(e.exportarGeoJson()),
        ),
      );
      mensaje = e.txt.geoJsonCopiado;
    } on FormatException catch (error) {
      mensaje = error.message;
    }
    if (!context.mounted) return;
    await emergentes.mostrarAviso(
      context,
      titulo: e.txt.copiarGeoJson,
      mensaje: mensaje,
      icono: CupertinoIcons.doc_on_clipboard_fill,
      boton: e.txt.listo,
    );
  }

  /// Abre la ficha de la plantación (o del lote libre) cuya zona se tocó.
  void _abrirFicha(BuildContext context, String zonaId) {
    final estado = Alcance.leer(context);
    final p = estado.plantacionPorId(zonaId);
    if (p != null) estado.seleccionar(p.id);
    Navigator.of(context).push(
      CupertinoPageRoute<void>(
        builder: (_) => PantallaMiPlantacion(loteId: p?.loteId ?? zonaId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final parcela = estado.parcela!;
    final zonas = zonasDe(context, estado);
    final tieneContorno = parcela.contorno.length >= 3;
    final tam = MediaQuery.sizeOf(context);
    final horizontal = tam.width > tam.height;

    final resumen = Text(
      [
        parcela.nombre,
        t.cuantasPlantaciones(estado.plantaciones.length),
        if (tieneContorno) t.area(areaGeografica(parcela.geometria)),
      ].join(' · '),
      style: Texto.nota(context),
    );
    final lienzo = LienzoFinca(
      key: const Key('lienzo-finca'),
      finca: parcela.contorno,
      zonas: zonas,
      alTocar: (p) {
        // La última dibujada queda encima, así que se busca al revés.
        for (final z in zonas.reversed) {
          if (dentroDe(z.contorno, p)) {
            _abrirFicha(context, z.id);
            return;
          }
        }
      },
    );
    final controles = [
      const SelectorCapa(),
      if (zonas.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Espacio.s,
            Espacio.m,
            Espacio.s,
            0,
          ),
          child: Text(
            t.bilingue(
              'Toca una plantación en el mapa para abrir su ficha.',
              'Tap a planting on the map to open its sheet.',
            ),
            style: Texto.nota(context),
          ),
        ),
      CupertinoButton(
        padding: const EdgeInsets.symmetric(
          horizontal: Espacio.s,
          vertical: 10,
        ),
        minimumSize: const Size(48, 48),
        onPressed: () => _editarContorno(context),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.pencil,
              size: 20,
              color: Paleta.de(context, Paleta.verde),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                tieneContorno ? t.editarContorno : t.dibujarContorno,
                style: Texto.accion(context),
              ),
            ),
          ],
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(
          Espacio.s,
          Espacio.m,
          Espacio.s,
          Espacio.xl,
        ),
        child: Text(
          t.croquisNota,
          style: Texto.nota(context),
          textAlign: TextAlign.center,
        ),
      ),
    ];

    if (horizontal) {
      // En horizontal el mapa ocupa solo el alto disponible y los controles
      // quedan a su lado, sin tener que desplazar la pantalla.
      return CupertinoPageScaffold(
        navigationBar: CupertinoNavigationBar(
          middle: Text(t.bilingue('Mapa de la finca', 'Farm map')),
          previousPageTitle: t.atras,
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, caja) {
              final lado = math.max(
                120.0,
                math.min(caja.maxHeight - 2 * Espacio.m, caja.maxWidth * 0.5),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Espacio.m),
                    child: SizedBox.square(dimension: lado, child: lienzo),
                  ),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.only(
                        right: Espacio.m,
                        top: Espacio.m,
                      ),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: Espacio.m),
                          child: resumen,
                        ),
                        ...controles,
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    }

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(t.bilingue('Mapa de la finca', 'Farm map')),
            previousPageTitle: t.atras,
            border: null,
          ),
          SliverList.list(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Espacio.m,
                  0,
                  Espacio.m,
                  Espacio.m,
                ),
                child: resumen,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Espacio.m,
                  0,
                  Espacio.m,
                  Espacio.m,
                ),
                child: controles.first,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
                child: lienzo,
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: controles.skip(1).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
