// Comprueba red.dart contra los pesos exportados. Uso, desde la raíz del repo:
//   dart run scripts/app/dart/comprobar.dart [casos_cafe.json]
// casos_cafe.json lo escribe: node scripts/app/dart/casos_cafe.mjs <salida.json>
import 'dart:convert';
import 'dart:io';

import 'red.dart';

/// Compara predecirCapas con los casos guardados dentro del propio archivo.
void comprobarCapas(String archivo) {
  final red = jsonDecode(File('web/data/$archivo').readAsStringSync()) as Map<String, dynamic>;
  final entradas = red['checkInputs'] as List<dynamic>;
  final esperadas = red['checkPredictions'] as List<dynamic>;
  var peor = 0.0;
  for (var i = 0; i < entradas.length; i++) {
    final x = [for (final v in entradas[i] as List<dynamic>) (v as num).toDouble()];
    final y = predecirCapas(red, x);
    final e = (esperadas[i] as Map<String, dynamic>)['pred'] as List<dynamic>;
    for (var o = 0; o < y.length; o++) {
      final d = (y[o] - (e[o] as num).toDouble()).abs();
      if (d > peor) peor = d;
    }
  }
  print('$archivo: ${entradas.length} casos, diferencia máxima $peor');
}

void main(List<String> args) {
  comprobarCapas('app_mlp.json');
  comprobarCapas('coffee_ptc_mlp.json');

  if (args.isNotEmpty) {
    final cafe = jsonDecode(File('web/data/coffee_recommender.json').readAsStringSync()) as Map<String, dynamic>;
    final casos = jsonDecode(File(args[0]).readAsStringSync()) as List<dynamic>;
    var peorCafe = 0.0;
    for (final c in casos) {
      final caso = c as Map<String, dynamic>;
      final x = [for (final v in caso['x'] as List<dynamic>) (v as num).toDouble()];
      final d = (correccionPlana(cafe, x) - (caso['out'] as num).toDouble()).abs();
      if (d > peorCafe) peorCafe = d;
    }
    print('coffee_recommender.json: ${casos.length} casos, diferencia máxima $peorCafe');
    print('tanh(800) = ${tanh(800)}, tanh(-800) = ${tanh(-800)}');
  }
}
