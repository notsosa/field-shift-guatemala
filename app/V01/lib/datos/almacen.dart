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

  static Future<Almacen> abrir() async => Almacen(await SharedPreferences.getInstance());

  Parcela? leerParcela() {
    final s = _prefs.getString('parcela');
    return s == null ? null : Parcela.deJson(jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> guardarParcela(Parcela p) => _prefs.setString('parcela', jsonEncode(p.aJson()));

  /// Plantaciones de la finca. Las versiones anteriores guardaban una sola,
  /// en la clave `plantacion`; si existe, se lee como la primera de la lista.
  List<Plantacion> leerPlantaciones() {
    final s = _prefs.getString('plantaciones');
    if (s != null) {
      return (jsonDecode(s) as List<dynamic>).map((j) => Plantacion.deJson(j as Map<String, dynamic>)).toList();
    }
    final vieja = _prefs.getString('plantacion');
    return vieja == null ? [] : [Plantacion.deJson(jsonDecode(vieja) as Map<String, dynamic>)];
  }

  Future<void> guardarPlantaciones(List<Plantacion> p) =>
      _prefs.setString('plantaciones', jsonEncode(p.map((x) => x.aJson()).toList()));

  String? leerSeleccionada() => _prefs.getString('seleccionada');

  Future<void> guardarSeleccionada(String id) => _prefs.setString('seleccionada', id);

  List<RegistroSemanal> leerRegistros() {
    final s = _prefs.getString('registros');
    if (s == null) return [];
    return (jsonDecode(s) as List<dynamic>)
        .map((j) => RegistroSemanal.deJson(j as Map<String, dynamic>))
        .toList();
  }

  Future<void> guardarRegistros(List<RegistroSemanal> r) =>
      _prefs.setString('registros', jsonEncode(r.map((x) => x.aJson()).toList()));

  List<DiaClima> leerClima() {
    final s = _prefs.getString('clima');
    if (s == null) return [];
    return (jsonDecode(s) as List<dynamic>).map((j) => DiaClima.deJson(j as Map<String, dynamic>)).toList();
  }

  Future<void> guardarClima(List<DiaClima> d) =>
      _prefs.setString('clima', jsonEncode(d.map((x) => x.aJson()).toList()));

  DateTime? leerUltimaSincronizacion() {
    final s = _prefs.getString('ultimaSync');
    return s == null ? null : DateTime.tryParse(s);
  }

  Future<void> guardarUltimaSincronizacion(DateTime f) => _prefs.setString('ultimaSync', f.toIso8601String());

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

  String? leerCapa() => _prefs.getString('capa');

  Future<void> guardarCapa(String nombre) => _prefs.setString('capa', nombre);

  String? leerIdioma() => _prefs.getString('idioma');

  Future<void> guardarIdioma(String codigo) => _prefs.setString('idioma', codigo);

  Future<void> borrarTodo() => _prefs.clear();
}
