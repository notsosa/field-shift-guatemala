// Corre el código Dart REAL de la app sobre las entradas de make_input.mjs y escribe los estados diarios (Tarea 34, parte B).
// Los archivos de la app no se tocan: se copian de origin/main a una carpeta de trabajo con la misma estructura:
//   git show origin/main:app/V01/lib/motor/fao56.dart       > <w>/lib/motor/fao56.dart
//   git show origin/main:app/V01/lib/motor/recomendador.dart > <w>/lib/motor/recomendador.dart
//   git show origin/main:app/V01/lib/modelos.dart            > <w>/lib/modelos.dart
//   cp scripts/app/fixture/fixture.dart <w>/bin/fixture.dart
//   C:/Users/velas/dev/flutter/bin/dart.bat <w>/bin/fixture.dart entrada.json salida.json
import 'dart:convert';
import 'dart:io';
import '../lib/modelos.dart';
import '../lib/motor/fao56.dart';
import '../lib/motor/recomendador.dart';

double? _d(dynamic v) => (v as num?)?.toDouble();

void main(List<String> args) {
  final entrada = jsonDecode(File(args[0]).readAsStringSync()) as Map<String, dynamic>;
  final salida = <Map<String, dynamic>>[];
  for (final c in entrada['cases'] as List<dynamic>) {
    final caso = c as Map<String, dynamic>;
    final clima = [
      for (final j in caso['clima'] as List<dynamic>)
        DiaClima(
          fecha: DateTime.parse((j as Map<String, dynamic>)['f'] as String),
          tmax: _d(j['x']), tmin: _d(j['n']), humedad: _d(j['h']), viento: _d(j['v']), radiacion: _d(j['r']), lluvia: _d(j['l']),
        ),
    ];
    final parcela = Parcela(nombre: 'prueba', latitud: _d(caso['latitud'])!, longitud: -89.5, elevacion: _d(caso['elevacion']));
    final hoy = DateTime.parse(caso['hoy'] as String);
    final dias = prepararClima(clima, parcela, hoy);
    final cultivo = cultivoPorId(caso['cultivo'] as String);
    final riegos = <DateTime, double>{
      for (final e in (caso['riegos'] as Map<String, dynamic>).entries) DateTime.parse(e.key): _d(e.value)!,
    };
    final estados = simularBalance(
      dias: dias, siembra: DateTime.parse(caso['siembra'] as String), cultivo: cultivo.parametros,
      ciclo: caso['ciclo'] as int, aguaDisponible: _d(caso['aguaDisponible'])!, riegos: riegos,
    );
    final p = cultivo.parametros;
    String iso(DateTime f) => f.toIso8601String().substring(0, 10);
    salida.add({
      'id': caso['id'],
      'catalogo': {'ciclos': cultivo.ciclos, 'kcInicial': p.kcInicial, 'kcMedio': p.kcMedio, 'kcFinal': p.kcFinal, 'etapas': p.etapas, 'raizMaxima': p.raizMaxima, 'p': p.p, 'ky': p.ky},
      'dias': [for (final d in dias) {'f': iso(d.fecha), 'et0': d.et0, 'lluvia': d.lluvia, 'estimado': d.estimado}],
      'estados': [
        for (final e in estados)
          {'f': iso(e.fecha), 'etapa': e.etapa.name, 'kc': e.kc, 'etc': e.etc, 'eta': e.eta, 'ks': e.ks, 'agotamiento': e.agotamiento,
           'aguaTotal': e.aguaTotal, 'aguaFacil': e.aguaFacil, 'lluvia': e.lluvia, 'riego': e.riego, 'estimado': e.estimado, 'reserva': e.reserva},
      ],
      'factor': factorRendimiento(estados, p.ky),
    });
  }
  File(args[1]).writeAsStringSync(jsonEncode({'cases': salida}));
  stdout.writeln('escrito ${args[1]}: ${salida.length} casos');
}
