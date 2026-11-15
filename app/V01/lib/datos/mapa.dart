/// Fondo de mapa para el plano de la finca. Las teselas se descargan solo con
/// wifi y se guardan en el teléfono, de modo que el mapa sigue disponible sin
/// conexión una vez visto.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'almacen.dart';

/// Qué se dibuja detrás de los contornos.
enum CapaMapa { mapa, satelite, croquis }

/// Posición en Web Mercator (x, y de 0 a 1) de una latitud y longitud.
(double, double) mundoDe(double latitud, double longitud) {
  final lat = latitud.clamp(-85.0, 85.0) * math.pi / 180;
  return ((longitud + 180) / 360, (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2);
}

/// Latitud y longitud de una posición en Web Mercator.
(double, double) latLonDe(double x, double y) {
  final n = math.pi * (1 - 2 * y);
  final latitud = math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi;
  return (latitud, x * 360 - 180);
}

/// Ventana cuadrada del mapa en coordenadas Web Mercator (de 0 a 1), centrada
/// en el punto de la finca.
class Ventana {
  const Ventana(this.izquierda, this.arriba, this.ancho);

  final double izquierda;
  final double arriba;
  final double ancho;

  /// Ventana de [lado] metros de ancho centrada en la latitud y longitud dadas.
  factory Ventana.centrada(double latitud, double longitud, double lado) {
    final (x, y) = mundoDe(latitud, longitud);
    final ancho = lado / (40075016.686 * math.cos(latitud.clamp(-85.0, 85.0) * math.pi / 180));
    return Ventana(x - ancho / 2, y - ancho / 2, ancho);
  }

  /// Nivel de zoom cuyas teselas dan una imagen nítida para esta ventana.
  int zoom(int maximo) => (math.log(900 / (256 * ancho)) / math.ln2).round().clamp(1, maximo);

  /// Teselas (x, y) que cubren la ventana en el zoom dado.
  List<(int, int)> teselas(int z) {
    final n = 1 << z;
    int indice(double v) => (v * n).floor().clamp(0, n - 1);
    final salida = <(int, int)>[];
    for (var ty = indice(arriba); ty <= indice(arriba + ancho - 1e-12); ty++) {
      for (var tx = indice(izquierda); tx <= indice(izquierda + ancho - 1e-12); tx++) {
        salida.add((tx, ty));
      }
    }
    return salida;
  }
}

class ServicioMapa {
  ServicioMapa(this._almacen, {http.Client? cliente, Future<bool> Function()? hayWifi})
      : _clienteDado = cliente,
        _hayWifi = hayWifi ?? (() async => true);

  final Almacen? _almacen;
  final http.Client? _clienteDado;
  http.Client? _propio;
  http.Client get _cliente => _clienteDado ?? (_propio ??= http.Client());
  final Future<bool> Function() _hayWifi;

  final _memoria = <String, Uint8List>{};
  final _enCurso = <String, Future<Uint8List?>>{};
  bool? _wifi;
  DateTime? _wifiVisto;

  static int zoomMaximo(CapaMapa capa) => capa == CapaMapa.satelite ? 18 : 19;

  static String atribucion(CapaMapa capa) => switch (capa) {
        CapaMapa.mapa => '© OpenStreetMap',
        CapaMapa.satelite => 'Esri, Maxar, Earthstar Geographics',
        CapaMapa.croquis => '',
      };

  Uri _url(CapaMapa capa, int z, int x, int y) => Uri.parse(switch (capa) {
        CapaMapa.satelite =>
          'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/$z/$y/$x',
        _ => 'https://tile.openstreetmap.org/$z/$x/$y.png',
      });

  Future<bool> _conWifi() async {
    final ahora = DateTime.now();
    if (_wifi != null && _wifiVisto != null && ahora.difference(_wifiVisto!).inSeconds < 5) return _wifi!;
    _wifi = await _hayWifi();
    _wifiVisto = ahora;
    return _wifi!;
  }

  /// Imagen de una tesela: de la memoria, del teléfono o, con wifi, de internet.
  /// Devuelve nulo si no está guardada y no se puede descargar. Con [guardar]
  /// en falso no se escribe en el teléfono: sirve para explorar el mapa sin
  /// desplazar las teselas guardadas de la finca.
  Future<Uint8List?> tesela(CapaMapa capa, int z, int x, int y, {bool guardar = true}) {
    if (capa == CapaMapa.croquis) return Future.value();
    final clave = '${capa.name}/$z/$x/$y';
    final enMemoria = _memoria[clave];
    if (enMemoria != null) return Future.value(enMemoria);
    // Ojo: el cierre no debe devolver el futuro quitado, o `whenComplete` se
    // quedaría esperándolo para siempre.
    return _enCurso[clave] ??= _traer(clave, capa, z, x, y, guardar).whenComplete(() {
      _enCurso.remove(clave);
    });
  }

  Uint8List _recordar(String clave, Uint8List bytes) {
    _memoria[clave] = bytes;
    while (_memoria.length > 400) {
      _memoria.remove(_memoria.keys.first);
    }
    return bytes;
  }

  Future<Uint8List?> _traer(String clave, CapaMapa capa, int z, int x, int y, bool guardar) async {
    final guardada = _almacen?.leerTesela(clave);
    if (guardada != null) return _recordar(clave, guardada);
    try {
      if (!await _conWifi()) return null;
      final r = await _cliente.get(
        _url(capa, z, x, y),
        // El servidor de OpenStreetMap exige que la app se identifique.
        headers: const {'User-Agent': 'gt.fieldshift.field_shift/1.0'},
      ).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200 || r.bodyBytes.isEmpty) return null;
      if (guardar) await _almacen?.guardarTesela(clave, r.bodyBytes);
      return _recordar(clave, r.bodyBytes);
    } catch (_) {
      return null;
    }
  }
}
