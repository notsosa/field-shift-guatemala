/// Almacenamiento local: todo se guarda en el teléfono y la app funciona sin
/// conexión. Se usa un almacén clave-valor con JSON; la interfaz es pequeña
/// para poder cambiarlo por SQLite sin tocar el resto de la app.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../modelos.dart';

class Almacen {
  Almacen(this._prefs);

  final SharedPreferences _prefs;

  static Future<Almacen> abrir() async =>
      Almacen(await SharedPreferences.getInstance());

  /// Primer estado de finca legible (`fincaV3`, luego `fincaV2`). Nunca lanza:
  /// un texto dañado o de versión desconocida se pasa por alto.
  Map<String, dynamic>? leerEstadoFinca() {
    final c = candidatosFinca();
    return c.isEmpty ? null : c.first.$2;
  }

  /// Estados de finca con JSON válido y versión conocida, del más nuevo al más
  /// viejo. Los que no se pueden leer se respaldan sin borrarlos (ver
  /// [respaldarDanada]) y se omiten.
  List<(String, Map<String, dynamic>)> candidatosFinca() {
    final salida = <(String, Map<String, dynamic>)>[];
    for (final clave in const ['fincaV3', 'fincaV2']) {
      final String? s;
      try {
        s = _prefs.getString(clave);
      } catch (_) {
        continue;
      }
      if (s == null) continue;
      try {
        final j = jsonDecode(s);
        if (j is Map<String, dynamic> &&
            (j['version'] == 2 || j['version'] == 3)) {
          salida.add((clave, j));
          continue;
        }
      } catch (_) {}
      respaldarDanada(clave);
    }
    return salida;
  }

  /// Futuros de los respaldos pedidos; el arranque los espera.
  final List<Future<void>> respaldos = [];

  /// Guarda el texto crudo de [clave] en `<clave>_danada` (o `_danada2`, ...
  /// si ya hay otro respaldo distinto) sin tocar la clave original.
  void respaldarDanada(String clave) {
    try {
      final crudo = _prefs.getString(clave);
      if (crudo == null) return;
      var destino = '${clave}_danada';
      for (var n = 2; n <= 5; n++) {
        final previo = _prefs.getString(destino);
        if (previo == null || previo == crudo) break;
        destino = '${clave}_danada$n';
      }
      if (_prefs.getString(destino) == crudo) return;
      respaldos.add(
        _prefs.setString(destino, crudo).then((_) {}).catchError((Object _) {}),
      );
    } catch (_) {}
  }

  /// Una sola escritura mantiene juntos lotes, geometrías, registros y agua.
  /// Las claves antiguas quedan intactas como respaldo de la migración.
  Future<void> guardarEstadoFinca(Map<String, dynamic> estado) async {
    if (!await _prefs.setString('fincaV3', jsonEncode(estado))) {
      throw StateError('No se pudo guardar la finca');
    }
  }

  Parcela? leerParcela() {
    try {
      final s = _prefs.getString('parcela');
      return s == null
          ? null
          : Parcela.deJson(jsonDecode(s) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> guardarParcela(Parcela p) =>
      _prefs.setString('parcela', jsonEncode(p.aJson()));

  /// Plantaciones de la finca. Las versiones anteriores guardaban una sola,
  /// en la clave `plantacion`; si existe, se lee como la primera de la lista.
  List<Plantacion> leerPlantaciones() {
    try {
      final s = _prefs.getString('plantaciones');
      if (s != null) {
        return (jsonDecode(s) as List<dynamic>)
            .map((j) => Plantacion.deJson(j as Map<String, dynamic>))
            .toList();
      }
      final vieja = _prefs.getString('plantacion');
      return vieja == null
          ? []
          : [Plantacion.deJson(jsonDecode(vieja) as Map<String, dynamic>)];
    } catch (_) {
      return [];
    }
  }

  Future<void> guardarPlantaciones(List<Plantacion> p) => _prefs.setString(
    'plantaciones',
    jsonEncode(p.map((x) => x.aJson()).toList()),
  );

  String? leerSeleccionada() => _prefs.getString('seleccionada');

  Future<void> guardarSeleccionada(String id) =>
      _prefs.setString('seleccionada', id);

  List<RegistroSemanal> leerRegistros() {
    try {
      final s = _prefs.getString('registros');
      if (s == null) return [];
      return (jsonDecode(s) as List<dynamic>)
          .map((j) => RegistroSemanal.deJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> guardarRegistros(List<RegistroSemanal> r) => _prefs.setString(
    'registros',
    jsonEncode(r.map((x) => x.aJson()).toList()),
  );

  List<DiaClima> leerClima() {
    try {
      final s = _prefs.getString('clima');
      if (s == null) return [];
      return (jsonDecode(s) as List<dynamic>)
          .map((j) => DiaClima.deJson(j as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> guardarClima(List<DiaClima> d) =>
      _prefs.setString('clima', jsonEncode(d.map((x) => x.aJson()).toList()));

  DateTime? leerUltimaSincronizacion() {
    try {
      final s = _prefs.getString('ultimaSync');
      return s == null ? null : DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> guardarUltimaSincronizacion(DateTime f) =>
      _prefs.setString('ultimaSync', f.toIso8601String());

  /// Teselas del mapa guardadas para usarlas sin conexión. Se conservan como
  /// máximo [_maxTeselas]; al pasarse, se borran las más viejas.
  static const _maxTeselas = 100;

  Uint8List? leerTesela(String clave) {
    final s = _prefs.getString('tesela:$clave');
    return s == null ? null : base64Decode(s);
  }

  Future<void> guardarTesela(String clave, Uint8List bytes) async {
    final indice = [...?_prefs.getStringList('teselas')]..remove(clave);
    indice.add(clave);
    while (indice.length > _maxTeselas) {
      await _prefs.remove('tesela:${indice.removeAt(0)}');
    }
    await _prefs.setString('tesela:$clave', base64Encode(bytes));
    await _prefs.setStringList('teselas', indice);
  }

  String? leerUnidad() => _prefs.getString('unidad');

  Future<void> guardarUnidad(String nombre) =>
      _prefs.setString('unidad', nombre);

  String? leerCapa() => _prefs.getString('capa');

  Future<void> guardarCapa(String nombre) => _prefs.setString('capa', nombre);

  String? leerIdioma() => _prefs.getString('idioma');

  Future<void> guardarIdioma(String codigo) =>
      _prefs.setString('idioma', codigo);

  Future<void> borrarTodo() => _prefs.clear();
}
