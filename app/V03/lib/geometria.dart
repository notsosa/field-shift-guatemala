/// Geometrías geográficas persistentes y validación de polígonos simples.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show visibleForTesting;

class Punto {
  const Punto(this.x, this.y);
  final double x;
  final double y;
  List<double> aJson() => [x, y];
}

class Coordenada {
  const Coordenada(this.latitud, this.longitud);
  final double latitud;
  final double longitud;
  List<double> aJson() => [longitud, latitud];
  factory Coordenada.deJson(List<dynamic> j) =>
      Coordenada((j[1] as num).toDouble(), (j[0] as num).toDouble());
}

(double, double) mundoDe(double latitud, double longitud) {
  final lat = latitud.clamp(-85.0, 85.0) * math.pi / 180;
  return (
    (longitud + 180) / 360,
    (1 - math.log(math.tan(lat) + 1 / math.cos(lat)) / math.pi) / 2,
  );
}

(double, double) latLonDe(double x, double y) {
  final n = math.pi * (1 - 2 * y);
  return (
    math.atan((math.exp(n) - math.exp(-n)) / 2) * 180 / math.pi,
    x * 360 - 180,
  );
}

/// El encuadre transforma coordenadas; cambiarlo no modifica el terreno.
class MarcoPlano {
  const MarcoPlano(this.latitud, this.longitud, this.lado);
  final double latitud;
  final double longitud;
  final double lado;

  double get ancho =>
      lado /
      (40075016.686 * math.cos(latitud.clamp(-85.0, 85.0) * math.pi / 180));

  List<Coordenada> aGeografico(List<Punto> puntos) {
    final (cx, cy) = mundoDe(latitud, longitud);
    return [
      for (final p in puntos)
        _coordenada(cx + (p.x - .5) * ancho, cy + (p.y - .5) * ancho),
    ];
  }

  List<Punto> aPlano(List<Coordenada> puntos) {
    final (cx, cy) = mundoDe(latitud, longitud);
    return [for (final p in puntos) _punto(p, cx, cy)];
  }

  Punto _punto(Coordenada p, double cx, double cy) {
    final (x, y) = mundoDe(p.latitud, p.longitud);
    return Punto(.5 + (x - cx) / ancho, .5 + (y - cy) / ancho);
  }

  Coordenada _coordenada(double x, double y) {
    final (lat, lon) = latLonDe(x, y);
    return Coordenada(lat, lon);
  }
}

/// Área esférica en m² (radio medio IUGG); no es un levantamiento catastral.
double areaGeografica(List<Coordenada> puntos) {
  if (puntos.length < 3) return 0;
  var suma = 0.0;
  for (var i = 0; i < puntos.length; i++) {
    final a = puntos[i], b = puntos[(i + 1) % puntos.length];
    final dlon = (b.longitud - a.longitud) * math.pi / 180;
    suma +=
        dlon *
        (2 +
            math.sin(a.latitud * math.pi / 180) +
            math.sin(b.latitud * math.pi / 180));
  }
  return suma.abs() * 6371008.8 * 6371008.8 / 2;
}

Map<String, dynamic>? poligonoGeoJson(List<Coordenada> puntos) {
  if (puntos.isEmpty) return null;
  if (puntos.length < 3 ||
      puntos.any(
        (p) =>
            !p.latitud.isFinite ||
            !p.longitud.isFinite ||
            p.latitud.abs() > 85 ||
            p.longitud.abs() > 180,
      )) {
    throw const FormatException('Coordenadas inválidas');
  }
  var anillo = [...puntos];
  if (anillo.first.latitud == anillo.last.latitud &&
      anillo.first.longitud == anillo.last.longitud) {
    anillo.removeLast();
  }
  final marco = MarcoPlano(anillo.first.latitud, anillo.first.longitud, 500);
  if (validarPoligono(marco.aPlano(anillo)) != null) {
    throw const FormatException('Polígono inválido');
  }
  // RFC 7946: anillo exterior antihorario en longitud/latitud.
  final plano = [for (final p in anillo) Punto(p.longitud, p.latitud)];
  if (_areaFirmada(plano) < 0) anillo = anillo.reversed.toList();
  return {
    'type': 'Polygon',
    'coordinates': [
      [...anillo.map((p) => p.aJson()), anillo.first.aJson()],
    ],
  };
}

enum ErrorGeometria {
  pocosPuntos,
  coordenadas,
  degenerado,
  cruce,
  fueraFinca,
  solapamiento,
  fincaInvalida,
}

// Tolerancia de superficie: 0.01 m². Los cálculos topológicos usan metros.
const toleranciaArea = .01;
const _eps = 1e-8;

double _cruz(Punto a, Punto b, Punto c) =>
    (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x);
double _areaFirmada(List<Punto> p) {
  var suma = 0.0;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    suma += a.x * b.y - a.y * b.x;
  }
  return suma / 2;
}

bool _sobre(Punto a, Punto b, Punto p) =>
    _cruz(a, b, p).abs() <= _eps &&
    p.x >= math.min(a.x, b.x) - _eps &&
    p.x <= math.max(a.x, b.x) + _eps &&
    p.y >= math.min(a.y, b.y) - _eps &&
    p.y <= math.max(a.y, b.y) + _eps;

bool _intersectan(Punto a, Punto b, Punto c, Punto d) {
  final u = _cruz(a, b, c),
      v = _cruz(a, b, d),
      w = _cruz(c, d, a),
      z = _cruz(c, d, b);
  return ((u > _eps && v < -_eps || u < -_eps && v > _eps) &&
          (w > _eps && z < -_eps || w < -_eps && z > _eps)) ||
      _sobre(a, b, c) ||
      _sobre(a, b, d) ||
      _sobre(c, d, a) ||
      _sobre(c, d, b);
}

ErrorGeometria? _validez(List<Punto> p) {
  if (p.length < 3) return ErrorGeometria.pocosPuntos;
  if (p.any((v) => !v.x.isFinite || !v.y.isFinite)) {
    return ErrorGeometria.coordenadas;
  }
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    final c = p[(i + 2) % p.length];
    if (_cruz(a, b, c).abs() <= _eps &&
        (b.x - a.x) * (c.x - b.x) + (b.y - a.y) * (c.y - b.y) < -_eps) {
      return ErrorGeometria.degenerado;
    }
    if (math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2) < _eps) {
      return ErrorGeometria.degenerado;
    }
    for (var j = i + 1; j < p.length; j++) {
      if (j == i + 1 || i == 0 && j == p.length - 1) continue;
      if (_intersectan(a, b, p[j], p[(j + 1) % p.length])) {
        return ErrorGeometria.cruce;
      }
    }
  }
  if (_areaFirmada(p).abs() <= toleranciaArea) return ErrorGeometria.degenerado;
  return null;
}

bool _enTriangulo(Punto p, Punto a, Punto b, Punto c) =>
    _cruz(a, b, p) >= -_eps &&
    _cruz(b, c, p) >= -_eps &&
    _cruz(c, a, p) >= -_eps;

/// Triangulación de polígonos simples cóncavos, eliminando vértices colineales.
List<List<Punto>> _triangulos(List<Punto> entrada) {
  final p = _areaFirmada(entrada) < 0
      ? entrada.reversed.toList()
      : [...entrada];
  var cambio = true;
  while (cambio && p.length > 3) {
    cambio = false;
    for (var i = 0; i < p.length; i++) {
      if (_cruz(
            p[(i - 1 + p.length) % p.length],
            p[i],
            p[(i + 1) % p.length],
          ).abs() <=
          _eps) {
        p.removeAt(i);
        cambio = true;
        break;
      }
    }
  }
  final salida = <List<Punto>>[];
  while (p.length > 3) {
    var encontrado = false;
    for (var i = 0; i < p.length; i++) {
      final ai = (i - 1 + p.length) % p.length, ci = (i + 1) % p.length;
      final a = p[ai], b = p[i], c = p[ci];
      if (_cruz(a, b, c) <= _eps) continue;
      if ([
        for (var j = 0; j < p.length; j++)
          if (j != ai && j != i && j != ci) p[j],
      ].any((v) => _enTriangulo(v, a, b, c))) {
        continue;
      }
      salida.add([a, b, c]);
      p.removeAt(i);
      encontrado = true;
      break;
    }
    if (!encontrado) {
      throw const FormatException('No se pudo triangular el polígono');
    }
  }
  salida.add(p);
  return salida;
}

List<Punto> _recortar(List<Punto> poligono, List<Punto> triangulo) {
  var salida = poligono;
  for (var i = 0; i < 3; i++) {
    final a = triangulo[i], b = triangulo[(i + 1) % 3];
    final entrada = salida;
    salida = [];
    if (entrada.isEmpty) break;
    var previo = entrada.last;
    for (final actual in entrada) {
      final d1 = _cruz(a, b, previo), d2 = _cruz(a, b, actual);
      final dentro1 = d1 >= -_eps, dentro2 = d2 >= -_eps;
      if (dentro1 != dentro2) {
        final t = d1 / (d1 - d2);
        salida.add(
          Punto(
            previo.x + t * (actual.x - previo.x),
            previo.y + t * (actual.y - previo.y),
          ),
        );
      }
      if (dentro2) salida.add(actual);
      previo = actual;
    }
  }
  return salida;
}

/// Triangulador usado por [validarPoligono]; solo las pruebas lo sustituyen
/// para simular un fallo.
@visibleForTesting
List<List<Punto>> Function(List<Punto>) triangulador = _triangulos;

bool _triangulable(List<Punto> p) {
  try {
    triangulador(p);
    return true;
  } on FormatException {
    return false;
  }
}

double _interseccion(List<Punto> a, List<Punto> b) {
  var area = 0.0;
  for (final ta in triangulador(a)) {
    for (final tb in triangulador(b)) {
      area += _areaFirmada(_recortar(ta, tb)).abs();
    }
  }
  return area;
}

ErrorGeometria? validarPoligono(
  List<Punto> puntos, {
  double lado = 500,
  List<Punto> finca = const [],
  List<List<Punto>> otros = const [],
}) {
  if (!lado.isFinite || lado <= 0) return ErrorGeometria.coordenadas;
  List<Punto> metros(List<Punto> p) => [
    for (final v in p) Punto(v.x * lado, v.y * lado),
  ];
  final p = metros(puntos);
  final error = _validez(p);
  if (error != null) return error;
  if (finca.isNotEmpty) {
    final f = metros(finca);
    if (_validez(f) != null) return ErrorGeometria.fincaInvalida;
    final double dentro;
    try {
      dentro = _interseccion(p, f);
    } on FormatException {
      // Si no se puede triangular el trazo, el problema es el trazo.
      return _triangulable(p)
          ? ErrorGeometria.fincaInvalida
          : ErrorGeometria.degenerado;
    }
    if (_areaFirmada(p).abs() - dentro > toleranciaArea) {
      return ErrorGeometria.fueraFinca;
    }
  }
  for (final otro in otros) {
    if (otro.isEmpty) continue;
    final o = metros(otro);
    // Un lote vecino ya inválido (con cruces) no impide validar este trazo.
    if (_validez(o) != null) continue;
    final double comun;
    try {
      comun = _interseccion(p, o);
    } on FormatException {
      if (_triangulable(p)) continue;
      return ErrorGeometria.degenerado;
    }
    if (comun > toleranciaArea) {
      return ErrorGeometria.solapamiento;
    }
  }
  return null;
}
