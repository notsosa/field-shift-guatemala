/// Paso hacia adelante de las redes del equipo, en Dart puro (solo dart:math).
/// Referencia para copiar a `app/V01/lib/motor/`. Comprobada contra los pesos
/// exportados con `scripts/app/dart/comprobar.dart`.
library;

import 'dart:math' as math;

/// Tangente hiperbólica; `dart:math` no la trae. Esta forma no da NaN con
/// valores grandes (exp desborda a infinito y el resultado queda en 1 o -1).
double tanh(double x) => 1 - 2 / (math.exp(2 * x) + 1);

/// Lanza un error claro si el modelo y lo que la app arma no coinciden.
void comprobarEntradas(List<String> esperadas, List<String> armadas) {
  if (esperadas.length != armadas.length) {
    throw StateError(
      'La red espera ${esperadas.length} entradas y se armaron ${armadas.length}',
    );
  }
  for (var i = 0; i < esperadas.length; i++) {
    if (esperadas[i] != armadas[i]) {
      throw StateError(
        'Entrada $i: la red espera "${esperadas[i]}" y se armó "${armadas[i]}"',
      );
    }
  }
}

List<double> _lista(dynamic v) => [
  for (final n in v as List<dynamic>) (n as num).toDouble(),
];

List<double> _estandarizar(
  List<double> x,
  List<double> media,
  List<double> desv,
) {
  if (x.length != media.length || x.length != desv.length) {
    throw StateError(
      'Entradas: ${x.length}; media: ${media.length}; desviación: ${desv.length}',
    );
  }
  return [
    for (var j = 0; j < x.length; j++)
      (x[j] - media[j]) / (desv[j] == 0 ? 1 : desv[j]),
  ];
}

/// Formato de `web/data/app_mlp.json` (y de las redes `emulator_*`): capas con
/// matriz `W` (una fila por neurona de salida) y sesgo `b`; ReLU en las capas
/// ocultas, salida lineal; la salida vuelve a sus unidades con yMean y yStd.
List<double> predecirCapas(Map<String, dynamic> red, List<double> x) {
  var a = _estandarizar(x, _lista(red['mean']), _lista(red['std']));
  final capas = red['layers'] as List<dynamic>;
  for (var l = 0; l < capas.length; l++) {
    final capa = capas[l] as Map<String, dynamic>;
    final w = capa['W'] as List<dynamic>;
    final b = _lista(capa['b']);
    final ultima = l == capas.length - 1;
    final salida = List<double>.filled(w.length, 0);
    for (var o = 0; o < w.length; o++) {
      final fila = w[o] as List<dynamic>;
      if (fila.length != a.length) {
        throw StateError(
          'Capa $l: fila de ${fila.length} y entrada de ${a.length}',
        );
      }
      var s = b[o];
      for (var j = 0; j < fila.length; j++) {
        s += (fila[j] as num).toDouble() * a[j];
      }
      salida[o] = ultima ? s : math.max(0.0, s);
    }
    a = salida;
  }
  if (red['yMean'] != null && red['yStd'] != null) {
    final m = _lista(red['yMean']), d = _lista(red['yStd']);
    a = [for (var o = 0; o < a.length; o++) a[o] * d[o] + m[o]];
  }
  return a;
}

/// Formato de `web/data/coffee_recommender.json` y `recommender_mlp.json`:
/// `params` plano; por capa, primero los pesos fila por fila y luego los
/// sesgos; tanh en las capas ocultas, salida lineal. Devuelve la corrección
/// (sin tanh) para una entrada cruda.
double correccionPlana(Map<String, dynamic> red, List<double> x) {
  final tam = [
    for (final n in red['layerSizes'] as List<dynamic>) (n as num).toInt(),
  ];
  final p = _lista(red['params']);
  var esperado = 0;
  for (var l = 0; l < tam.length - 1; l++) {
    esperado += tam[l + 1] * tam[l] + tam[l + 1];
  }
  if (p.length != esperado) {
    throw StateError('Pesos: ${p.length}; la forma $tam pide $esperado');
  }
  var a = _estandarizar(x, _lista(red['mean']), _lista(red['std']));
  var o = 0;
  for (var l = 0; l < tam.length - 1; l++) {
    final nEnt = tam[l], nSal = tam[l + 1], ultima = l == tam.length - 2;
    final salida = List<double>.filled(nSal, 0);
    for (var r = 0; r < nSal; r++) {
      var s = p[o + nSal * nEnt + r];
      final w = o + r * nEnt;
      for (var j = 0; j < nEnt; j++) {
        s += p[w + j] * a[j];
      }
      salida[r] = ultima ? s : tanh(s);
    }
    o += nSal * nEnt + nSal;
    a = salida;
  }
  return a[0];
}

/// Decisión de riego del café: se puntúan las dos acciones y gana la mayor; en
/// empate, la de la regla. [estado] son las 17 primeras entradas (16 del lote
/// más la prioridad); la última entrada (`irrigate`) la pone esta función.
bool recomiendaRegar(
  Map<String, dynamic> red,
  List<double> estado, {
  required bool reglaRiega,
}) {
  double puntaje(bool regar) =>
      (regar == reglaRiega ? 1.0 : 0.0) +
      tanh(correccionPlana(red, [...estado, regar ? 1.0 : 0.0]));
  final si = puntaje(true), no = puntaje(false);
  if (si == no) return reglaRiega;
  return si > no;
}
