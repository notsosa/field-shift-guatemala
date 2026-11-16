/// Ubicar la finca en un mapa que se puede desplazar y acercar. Sirve cuando
/// el productor no está en la finca y no puede usar el GPS del teléfono.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';

import '../datos/mapa.dart';
import '../estado.dart';
import 'tema.dart';

/// Mapa que se arrastra con un dedo y se acerca con dos, con doble toque o con
/// los botones. La marca del centro señala el punto elegido.
class MapaExplorable extends StatefulWidget {
  const MapaExplorable({
    super.key,
    required this.servicio,
    required this.capa,
    required this.latitud,
    required this.longitud,
    required this.zoom,
    required this.alMover,
    required this.aviso,
  });

  final ServicioMapa servicio;
  final CapaMapa capa;
  final double latitud;
  final double longitud;
  final double zoom;

  /// Se llama con la latitud y la longitud del centro cada vez que cambia.
  final void Function(double latitud, double longitud) alMover;

  /// Texto que se muestra si no hay forma de cargar el mapa.
  final String aviso;

  @override
  State<MapaExplorable> createState() => _EstadoExplorable();
}

class _EstadoExplorable extends State<MapaExplorable> {
  static const _zoomMinimo = 3.0;

  // Centro del mapa en coordenadas Web Mercator, de 0 a 1.
  late double _cx;
  late double _cy;
  late double _zoom;
  double _zoomAlEmpezar = 0;
  Offset _ultimoToque = Offset.zero;

  final _imagenes = <String, Uint8List>{};
  final _pedidas = <String>{};
  bool _sinRed = false;

  double get _zoomMaximo => ServicioMapa.zoomMaximo(widget.capa).toDouble();

  @override
  void initState() {
    super.initState();
    final (x, y) = mundoDe(widget.latitud, widget.longitud);
    _cx = x;
    _cy = y;
    _zoom = widget.zoom.clamp(_zoomMinimo, _zoomMaximo);
  }

  @override
  void didUpdateWidget(MapaExplorable viejo) {
    super.didUpdateWidget(viejo);
    if (viejo.capa != widget.capa) {
      _zoom = _zoom.clamp(_zoomMinimo, _zoomMaximo);
      _sinRed = false;
    }
  }

  double _escala(double zoom) => 256 * math.pow(2, zoom).toDouble();

  void _limitar() {
    _cx = _cx - _cx.floorToDouble(); // da la vuelta al mundo
    _cy = _cy.clamp(0.02, 0.98);
  }

  /// Cambia el zoom dejando quieto el punto del mapa que está bajo [foco].
  void _zoomEn(double nuevo, Offset foco, Size tam) {
    nuevo = nuevo.clamp(_zoomMinimo, _zoomMaximo);
    final antes = _escala(_zoom), despues = _escala(nuevo);
    final dx = foco.dx - tam.width / 2, dy = foco.dy - tam.height / 2;
    _cx += dx / antes - dx / despues;
    _cy += dy / antes - dy / despues;
    _zoom = nuevo;
    _limitar();
  }

  void _avisar() {
    final (lat, lon) = latLonDe(_cx, _cy);
    widget.alMover(lat, lon);
  }

  void _pedir(String clave, int z, int x, int y) {
    if (!_pedidas.add(clave)) return;
    widget.servicio.tesela(widget.capa, z, x, y, guardar: false).then((bytes) {
      if (!mounted) return;
      setState(() {
        if (bytes == null) {
          _sinRed = true;
          return;
        }
        _sinRed = false;
        _imagenes[clave] = bytes;
        // Al explorar mucho se sueltan las imágenes más viejas.
        while (_imagenes.length > 260) {
          final vieja = _imagenes.keys.first;
          _imagenes.remove(vieja);
          _pedidas.remove(vieja);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final verde = Paleta.de(context, Paleta.verde);

    Widget boton(IconData icono, VoidCallback alPulsar) => CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 44),
          onPressed: alPulsar,
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Paleta.de(context, Paleta.tarjeta),
              shape: BoxShape.circle,
              border: Border.all(color: Paleta.de(context, Paleta.tenue)),
            ),
            child: Icon(icono, size: 20, color: verde),
          ),
        );

    return LayoutBuilder(
      builder: (context, caja) {
        final tam = caja.biggest;
        final centro = Offset(tam.width / 2, tam.height / 2);
        final escala = _escala(_zoom);
        // Un nivel más de detalle que el zoom, para que se vea nítido.
        final z = (_zoom + 1).round().clamp(0, _zoomMaximo.toInt());
        final izquierda = _cx * escala - tam.width / 2;
        final arriba = _cy * escala - tam.height / 2;
        final teselas = <Widget>[];

        void nivel(int zz, {required bool pedir}) {
          final n = 1 << zz;
          final lado = escala / n;
          for (var ty = (arriba / lado).floor(); ty <= ((arriba + tam.height) / lado).floor(); ty++) {
            if (ty < 0 || ty >= n) continue;
            for (var tx = (izquierda / lado).floor(); tx <= ((izquierda + tam.width) / lado).floor(); tx++) {
              final x = ((tx % n) + n) % n;
              final clave = '${widget.capa.name}/$zz/$x/$ty';
              final bytes = _imagenes[clave];
              if (bytes == null) {
                if (pedir) _pedir(clave, zz, x, ty);
                continue;
              }
              teselas.add(Positioned(
                key: ValueKey('$clave@$tx'),
                left: tx * lado - izquierda,
                top: ty * lado - arriba,
                width: lado + 0.5,
                height: lado + 0.5,
                child: Image.memory(bytes, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium),
              ));
            }
          }
        }

        // Debajo va el nivel anterior, que ya suele estar cargado, para que al
        // acercar no quede en blanco mientras llega el detalle.
        if (z > 0) nivel(z - 1, pedir: false);
        nivel(z, pedir: true);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (_) => _zoomAlEmpezar = _zoom,
          onScaleUpdate: (d) {
            setState(() {
              if (d.pointerCount > 1) {
                _zoomEn(_zoomAlEmpezar + math.log(d.scale) / math.ln2, d.localFocalPoint, tam);
              }
              final e = _escala(_zoom);
              _cx -= d.focalPointDelta.dx / e;
              _cy -= d.focalPointDelta.dy / e;
              _limitar();
            });
            _avisar();
          },
          onDoubleTapDown: (d) => _ultimoToque = d.localPosition,
          onDoubleTap: () {
            setState(() => _zoomEn(_zoom + 1, _ultimoToque, tam));
            _avisar();
          },
          child: ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Paleta.de(context, Paleta.tenue)),
                ...teselas,
                if (_sinRed && _imagenes.isEmpty)
                  Align(
                    alignment: const Alignment(0, 0.4),
                    child: Padding(
                      padding: const EdgeInsets.all(Espacio.l),
                      child: Text(widget.aviso, style: Texto.nota(context), textAlign: TextAlign.center),
                    ),
                  ),
                // Marca del punto elegido, en el centro exacto.
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: verde,
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFFFFFFFF), width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6)],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: Espacio.m,
                  bottom: Espacio.l + 4,
                  child: Column(
                    children: [
                      boton(CupertinoIcons.plus, () {
                        setState(() => _zoomEn(_zoom + 1, centro, tam));
                        _avisar();
                      }),
                      const SizedBox(height: Espacio.s),
                      boton(CupertinoIcons.minus, () {
                        setState(() => _zoomEn(_zoom - 1, centro, tam));
                        _avisar();
                      }),
                    ],
                  ),
                ),
                if (_imagenes.isNotEmpty)
                  Positioned(
                    left: 6,
                    bottom: 4,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: const Color(0xB3FFFFFF), borderRadius: BorderRadius.circular(4)),
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
            ),
          ),
        );
      },
    );
  }
}

/// Pantalla para elegir el punto de la finca moviendo el mapa. Devuelve la
/// latitud y la longitud elegidas, o nada si se cancela.
class PantallaUbicar extends StatefulWidget {
  const PantallaUbicar({super.key, this.latitud, this.longitud});

  /// Punto desde el que arranca el mapa. Si falta, se muestra Guatemala.
  final double? latitud;
  final double? longitud;

  @override
  State<PantallaUbicar> createState() => _EstadoUbicar();
}

class _EstadoUbicar extends State<PantallaUbicar> {
  late double _latitud = widget.latitud ?? 15.6;
  late double _longitud = widget.longitud ?? -90.3;
  CapaMapa? _capa;

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final capa = _capa ?? (estado.capa == CapaMapa.croquis ? CapaMapa.mapa : estado.capa);
    final conPunto = widget.latitud != null && widget.longitud != null;

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.ubicarFinca),
        previousPageTitle: t.atras,
        border: null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.borde + Espacio.m, Espacio.s, Espacio.borde + Espacio.m, Espacio.m),
              child: Text(t.ayudaUbicar, style: Texto.nota(context)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.m, 0, Espacio.m, Espacio.m),
              child: Selector<CapaMapa>(
                opciones: {for (final c in const [CapaMapa.mapa, CapaMapa.satelite]) c: t.nombreCapa(c)},
                valor: capa,
                alCambiar: (c) => setState(() => _capa = c),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Espacio.m),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Espacio.radio),
                  child: MapaExplorable(
                    key: const Key('mapa-explorable'),
                    servicio: estado.mapa,
                    capa: capa,
                    latitud: _latitud,
                    longitud: _longitud,
                    zoom: conPunto ? 15 : 6.5,
                    aviso: t.sinWifiMapa,
                    alMover: (lat, lon) => setState(() {
                      _latitud = lat;
                      _longitud = lon;
                    }),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.m, Espacio.l, 0),
              child: Text(
                '${_latitud.toStringAsFixed(5)}, ${_longitud.toStringAsFixed(5)}',
                style: letra(15, peso: 500, color: Paleta.de(context, Paleta.secundario)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, Espacio.m),
              child: BotonPrincipal(
                texto: t.usarEstePunto,
                alPulsar: () => Navigator.of(context).pop((_latitud, _longitud)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
