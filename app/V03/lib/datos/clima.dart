/// Descarga del clima diario desde NASA POWER. Es la única parte de la app que
/// usa internet, y solo se ejecuta con wifi.
library;

import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../modelos.dart';

class ClimaDescargado {
  const ClimaDescargado({required this.dias, required this.elevacion});

  final List<DiaClima> dias;

  /// Elevación de la celda de NASA POWER en metros, si la respuesta la trae.
  final double? elevacion;
}

class ServicioClima {
  static const _parametros =
      'T2M,T2M_MAX,T2M_MIN,RH2M,WS2M,ALLSKY_SFC_SW_DWN,PRECTOTCORR,GWETTOP,GWETROOT';

  /// Verdadero si el teléfono está en wifi, red cableada o datos móviles. En la
  /// vista web de desarrollo no se puede distinguir el tipo de red, así que se
  /// permite.
  Future<bool> hayWifi() async {
    if (kIsWeb) return true;
    final redes = await Connectivity().checkConnectivity();
    return redes.contains(ConnectivityResult.wifi) ||
        redes.contains(ConnectivityResult.ethernet) ||
        redes.contains(ConnectivityResult.mobile);
  }

  Future<ClimaDescargado> descargar({
    required double latitud,
    required double longitud,
    required DateTime desde,
    required DateTime hasta,
  }) async {
    final uri = Uri.https('power.larc.nasa.gov', '/api/temporal/daily/point', {
      'parameters': _parametros,
      'community': 'AG',
      'latitude': latitud.toStringAsFixed(4),
      'longitude': longitud.toStringAsFixed(4),
      'start': _compacta(desde),
      'end': _compacta(hasta),
      'format': 'JSON',
      'time-standard': 'LST',
    });
    final respuesta = await http.get(uri).timeout(const Duration(seconds: 40));
    if (respuesta.statusCode != 200) {
      throw Exception('NASA POWER respondió ${respuesta.statusCode}');
    }
    return interpretar(jsonDecode(respuesta.body) as Map<String, dynamic>);
  }

  /// Convierte la respuesta JSON de POWER en días de clima. POWER marca los
  /// datos faltantes con -999; aquí quedan como nulos.
  static ClimaDescargado interpretar(Map<String, dynamic> json) {
    final parametros = (json['properties'] as Map<String, dynamic>)['parameter'] as Map<String, dynamic>;
    Map<String, dynamic> serie(String nombre) => (parametros[nombre] as Map<String, dynamic>?) ?? const {};
    double? valor(Map<String, dynamic> s, String clave) {
      final v = (s[clave] as num?)?.toDouble();
      return v == null || v <= -900 ? null : v;
    }

    final tmedia = serie('T2M');
    final tmax = serie('T2M_MAX');
    final tmin = serie('T2M_MIN');
    final hr = serie('RH2M');
    final viento = serie('WS2M');
    final rad = serie('ALLSKY_SFC_SW_DWN');
    final lluvia = serie('PRECTOTCORR');
    final gwettop = serie('GWETTOP');
    final gwetroot = serie('GWETROOT');

    final dias = <DiaClima>[];
    for (final clave in tmax.keys.toList()..sort()) {
      if (clave.length != 8) continue;
      dias.add(DiaClima(
        fecha: DateTime(
          int.parse(clave.substring(0, 4)),
          int.parse(clave.substring(4, 6)),
          int.parse(clave.substring(6, 8)),
        ),
        tmedia: valor(tmedia, clave),
        tmax: valor(tmax, clave),
        tmin: valor(tmin, clave),
        humedad: valor(hr, clave),
        viento: valor(viento, clave),
        radiacion: valor(rad, clave),
        lluvia: valor(lluvia, clave),
        gwettop: valor(gwettop, clave),
        gwetroot: valor(gwetroot, clave),
      ));
    }

    double? elevacion;
    final coordenadas = (json['geometry'] as Map<String, dynamic>?)?['coordinates'] as List<dynamic>?;
    if (coordenadas != null && coordenadas.length >= 3) {
      elevacion = (coordenadas[2] as num?)?.toDouble();
    }
    return ClimaDescargado(dias: dias, elevacion: elevacion);
  }

  static String _compacta(DateTime f) =>
      '${f.year.toString().padLeft(4, '0')}${f.month.toString().padLeft(2, '0')}${f.day.toString().padLeft(2, '0')}';
}
