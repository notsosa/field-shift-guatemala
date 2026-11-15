import 'package:field_shift/modelos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tipo de plaga por cultivo', () {
    test('el café ofrece exactamente roya, minador, antracnosis y otra', () {
      expect(tiposPlaga('cafe'), ['roya', 'minador', 'antracnosis', 'otra']);
    });

    test('los demás cultivos solo ofrecen otra / sin especificar por ahora', () {
      for (final c in catalogo.where((c) => c.id != 'cafe')) {
        expect(tiposPlaga(c.id), ['otra'], reason: c.id);
      }
    });

    test('un cultivo desconocido también cae en otra', () {
      expect(tiposPlaga('quinoa'), ['otra']);
    });
  });

  group('el tipo de plaga se guarda y los datos viejos siguen cargando', () {
    test('plantación: ida y vuelta con el tipo', () {
      final p = Plantacion(
        cultivoId: 'cafe', fecha: DateTime(2026, 5, 1), ciclo: 365, suelo: Suelo.franco,
        riego: TipoRiego.ninguno, temporadaRiego: TemporadaRiego.auxilio,
        plagaReciente: true, tipoPlaga: 'roya', fertilizo: false,
      );
      expect(Plantacion.deJson(p.aJson()).tipoPlaga, 'roya');
    });

    test('plantación guardada sin el campo nuevo carga con tipo vacío', () {
      final viejo = {
        'cultivo': 'maiz', 'fecha': '2026-06-01', 'ciclo': 120, 'suelo': 'franco', 'riego': 'goteo',
        'temporadaRiego': 'auxilio', 'plagaReciente': true, 'notaPlaga': 'gusano', 'fertilizo': false,
      };
      final p = Plantacion.deJson(viejo);
      expect(p.tipoPlaga, '');
      expect(p.notaPlaga, 'gusano');
    });

    test('registro: ida y vuelta con el tipo', () {
      final r = RegistroSemanal(
        fecha: DateTime(2026, 7, 13), riegos: 0, plaga: NivelPlaga.moderada, tipoPlaga: 'minador', fertilizo: false,
      );
      expect(RegistroSemanal.deJson(r.aJson()).tipoPlaga, 'minador');
    });

    test('registro guardado sin el campo nuevo carga con tipo vacío', () {
      final viejo = {'fecha': '2026-07-13', 'riegos': 2, 'plaga': 'leve', 'notaPlaga': 'mosca', 'fertilizo': false};
      final r = RegistroSemanal.deJson(viejo);
      expect(r.tipoPlaga, '');
      expect(r.plaga, NivelPlaga.leve);
    });
  });
}
