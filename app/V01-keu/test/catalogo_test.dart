import 'package:field_shift/modelos.dart';
import 'package:field_shift/textos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('el catálogo tiene los siete cultivos y conserva café y tomate', () {
    final ids = catalogo.map((c) => c.id).toList();
    expect(ids, containsAll(['maiz', 'frijol', 'ajonjoli', 'papa', 'cebolla', 'brocoli', 'lechuga', 'tomate', 'cafe']));
    expect(ids.toSet().length, ids.length);
  });

  test('parámetros de los cultivos agregados (web/data/crops.json de la rama)', () {
    void revisar(String id, List<double> kc, List<double> etapas, double raiz, double p, double ky, int ciclo) {
      final c = cultivoPorId(id);
      expect(c.id, id);
      final x = c.parametros;
      expect([x.kcInicial, x.kcMedio, x.kcFinal], kc, reason: id);
      expect(x.etapas, etapas, reason: id);
      expect(x.raizMaxima, raiz, reason: id);
      expect(x.p, p, reason: id);
      expect(x.ky, ky, reason: id);
      expect(c.ciclos, [ciclo], reason: id);
      expect(c.perenne, isFalse, reason: id);
    }

    revisar('ajonjoli', [0.35, 1.1, 0.25], [20, 30, 40, 20], 1.0, 0.6, 1.0, 110);
    revisar('papa', [0.5, 1.15, 0.75], [25, 30, 30, 30], 0.5, 0.35, 1.1, 115);
    revisar('cebolla', [0.7, 1.05, 0.75], [15, 25, 70, 40], 0.5, 0.3, 1.1, 150);
    revisar('brocoli', [0.7, 1.05, 0.95], [35, 45, 40, 15], 0.5, 0.45, 0.95, 135);
    revisar('lechuga', [0.7, 1.0, 0.95], [20, 30, 15, 10], 0.4, 0.3, 1.0, 75);
  });

  test('todos los cultivos tienen nombre en ES y EN', () {
    for (final c in catalogo) {
      expect(const Txt(false).nombreCultivo(c.id), isNot(c.id), reason: c.id);
      expect(const Txt(true).nombreCultivo(c.id), isNot(c.id), reason: c.id);
    }
  });
}
