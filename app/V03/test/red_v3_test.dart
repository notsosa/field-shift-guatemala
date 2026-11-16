import 'dart:io';
import 'dart:typed_data';

import 'package:field_shift/motor/red_v3.dart';
import 'package:flutter_test/flutter_test.dart';

List<double> _valores(int longitud, int sal, [int inicio = 0]) => List.generate(
  longitud,
  (i) => (((inicio + i) * 17 + sal * 13) % 67 - 33) / 32,
);

EntradaLoteV3 _lote(int i) {
  final sal = i * 11;
  return EntradaLoteV3(
    estatico: _valores(24, sal + 1),
    recientes: List.generate(28, (j) => _valores(12, sal + 2, j * 12)),
    historia: List.generate(32, (j) => _valores(16, sal + 3, j * 16)),
    contexto: _valores(59, sal + 4),
    candidatas: List.generate(25, (j) => _valores(45, sal + 5, j * 45)),
    base: _valores(25, sal + 6),
    recientesValidos: List.generate(28, (j) => i != 1 && j % 3 != 0),
    historiaValida: List.generate(32, (j) => i != 0 && j % 4 == 2),
    factibles: List.generate(25, (j) => j % 4 != i),
    activo: i != 2,
  );
}

void main() {
  test(
    'la V3 reproduce los puntajes PyTorch y las máscaras de lote y acción',
    () {
      final pesos = File(RedV3.rutaAsset).readAsBytesSync();
      final red = RedV3.desdeBytes(ByteData.sublistView(pesos));
      final obtenidos = red.puntuar(List.generate(3, _lote));
      const invalido = double.negativeInfinity;
      // NeuralPolicy.prepare con best.pt (semilla 17, generación 60) en CPU.
      const referencia = [
        [
          invalido,
          .3530505896,
          1.0199992657,
          1.5289407969,
          invalido,
          .6419644952,
          .8761824369,
          1.6000552177,
          invalido,
          .5729995966,
          1.1610772610,
          1.4319911003,
          invalido,
          .4194100201,
          1.1194596291,
          1.5730848312,
          invalido,
          .7411220074,
          .9387329817,
          1.6674367189,
          invalido,
          .6232801676,
          1.2273654938,
          -.5624826550,
          invalido,
        ],
        [
          -.5741486549,
          invalido,
          .5579826236,
          -1.2350945473,
          -.5578145981,
          invalido,
          .2580849528,
          -1.1538838148,
          -.6927251220,
          invalido,
          .4474282265,
          -1.2536042929,
          -.4247874022,
          invalido,
          .7352662683,
          -1.1541628838,
          -.4557865858,
          invalido,
          .2777296901,
          -1.0454416275,
          -.5561580658,
          invalido,
          .5469565392,
          -1.2088994980,
          -.3094686270,
        ],
      ];
      expect(obtenidos.length, 3);
      for (var lote = 0; lote < referencia.length; lote++) {
        expect(obtenidos[lote].length, RedV3.acciones);
        for (var accion = 0; accion < RedV3.acciones; accion++) {
          final esperado = referencia[lote][accion];
          expect(
            obtenidos[lote][accion],
            esperado == invalido ? invalido : closeTo(esperado, 2e-6),
            reason: 'lote $lote, acción $accion',
          );
        }
      }
      expect(obtenidos[2], everyElement(invalido));
    },
  );
}
