/// Almacenamiento local: todo se guarda en el teléfono y la app funciona sin
/// conexión. Se usa un almacén clave-valor con JSON; la interfaz es pequeña
/// para poder cambiarlo por SQLite sin tocar el resto de la app.
library;

import 'dart:convert';

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

  Plantacion? leerPlantacion() {
    final s = _prefs.getString('plantacion');
    return s == null ? null : Plantacion.deJson(jsonDecode(s) as Map<String, dynamic>);
  }

  Future<void> guardarPlantacion(Plantacion p) => _prefs.setString('plantacion', jsonEncode(p.aJson()));

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

  String? leerIdioma() => _prefs.getString('idioma');

  Future<void> guardarIdioma(String codigo) => _prefs.setString('idioma', codigo);

  Future<void> borrarTodo() => _prefs.clear();
}
