// Plagas por cultivo con fuente: lista por cultivo, detalle, generador y datos viejos.
import 'dart:convert';
import 'dart:io';

import 'package:field_shift/datos/plagas_investigacion.dart';
import 'package:field_shift/modelos.dart';
import 'package:field_shift/textos.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/generar_plagas.dart';

Map<String, dynamic> _json(String ruta) => jsonDecode(File(ruta).readAsStringSync()) as Map<String, dynamic>;

void main() {
  group('lista de plagas por cultivo (un nombre común por cultivo, y "otra")', () {
    test('maíz, frijol, cebolla, brócoli y lechuga: los nombres comunes de la investigación', () {
      expect(tiposPlaga('maiz'), ['acaro-del-maiz', 'otra']);
      expect(tiposPlaga('frijol'), ['trips-de-las-flores', 'mosca-minadora', 'otra']);
      expect(tiposPlaga('cebolla'), ['trips-de-la-cebolla', 'mosca-minadora', 'otra']);
      expect(tiposPlaga('brocoli'), ['palomilla-dorso-de-diamante', 'gallina-ciega', 'mosca-minadora', 'otra']);
      expect(tiposPlaga('lechuga'), ['pulgon', 'trips', 'mosca-minadora', 'otra']);
    });

    test('ajonjolí, papa y tomate no tienen registro confirmado: solo "otra"', () {
      for (final c in ['ajonjoli', 'papa', 'tomate']) {
        expect(tiposPlaga(c), ['otra'], reason: c);
        expect(sinRegistroConfirmado(c), isTrue, reason: c);
      }
      expect(sinRegistroConfirmado('maiz'), isFalse);
    });

    test('el café conserva roya, minador, antracnosis y otra, marcados como reportados por un caficultor', () {
      expect(tiposPlaga('cafe'), ['roya', 'minador', 'antracnosis', 'otra']);
      for (final id in ['roya', 'minador', 'antracnosis']) {
        final d = detallePlaga('cafe', id)!;
        expect(d.origen, OrigenPlaga.caficultor, reason: id);
        expect(d.registros, isEmpty, reason: id);
      }
      expect(sinRegistroConfirmado('cafe'), isFalse); // tiene lista propia, aunque no sea de la investigación
    });

    test('hay doce registros en total, repartidos bajo los nombres comunes', () {
      final registros = [
        for (final c in plagasInvestigacion.keys)
          for (final t in plagasInvestigacion[c]!) ...t.registros,
      ];
      expect(registros.length, 12);
      expect(registros.map((r) => r.id).toSet().length, 12);
    });
  });

  group('detalle de una plaga', () {
    test('trips de las flores en frijol: todos los campos de la investigación', () {
      final d = detallePlaga('frijol', 'trips-de-las-flores')!;
      expect(d.origen, OrigenPlaga.investigacion);
      expect(d.es, 'Trips de las flores');
      expect(d.en, 'Flower thrips');
      final r = d.registros.single;
      expect(r.id, 'frijol-01');
      expect(r.taxon, 'Megalurothrips usitatus');
      expect(r.danio.es, 'Flores y vainas');
      expect(r.danio.en, 'Flowers and pods');
      expect(r.etapa.es, 'campo');
      expect(r.lugar.es, startsWith('Petén, El Progreso, Zacapa y Chimaltenango'));
      expect(r.periodo.es, '2022');
      expect(r.limite.es, contains('No se extrapolan sus porcentajes de daño'));
      expect(r.limite.en, contains('not extrapolated'));
      final ref = r.referencias.single;
      expect(ref.fuente.id, 'S09');
      expect(ref.fuente.url, 'https://icta.gob.gt/plagacultivofrijolGuatemala.html');
      expect(ref.fuente.institucion, 'ICTA');
      expect(ref.localizador, 'Distribución y síntomas');
    });

    test('mosca minadora en frijol guarda sus dos taxones con su propia fuente', () {
      final d = detallePlaga('frijol', 'mosca-minadora')!;
      expect(d.registros.map((r) => r.taxon), ['Liriomyza huidobrensis', 'Liriomyza sabaziae']);
      expect(d.registros.map((r) => r.referencias.single.fuente.id), ['S20', 'S20']);
    });

    test('mosca minadora en cebolla tiene dos fuentes en un mismo registro', () {
      final d = detallePlaga('cebolla', 'mosca-minadora')!;
      expect(d.registros.single.referencias.map((r) => r.fuente.id), ['S16', 'S20']);
    });

    test('gallina ciega en brócoli: taxón a nivel de género', () {
      final r = detallePlaga('brocoli', 'gallina-ciega')!.registros.single;
      expect(r.taxon, 'Phyllophaga spp.');
      expect(r.resolucion, 'grupo');
    });

    test('el campo etapa "campo" se rotula como dónde se observó, no como etapa del cultivo', () {
      expect(const Txt(false).etiquetaEtapa('campo'), 'Observado en');
      expect(const Txt(true).etiquetaEtapa('campo'), 'Observed in');
      expect(const Txt(false).etiquetaEtapa('floración'), 'Etapa');
      expect(const Txt(true).etiquetaEtapa('flowering'), 'Stage');
      for (final c in plagasInvestigacion.keys) {
        for (final t in plagasInvestigacion[c]!) {
          for (final r in t.registros) {
            expect(const Txt(false).etiquetaEtapa(r.etapa.es), 'Observado en', reason: r.id);
          }
        }
      }
    });

    test('un id desconocido o un cultivo sin ese id devuelve nulo; "otra" no tiene detalle', () {
      expect(detallePlaga('frijol', 'broca'), isNull);
      expect(detallePlaga('maiz', 'pulgon'), isNull);
      expect(detallePlaga('quinoa', 'otra'), isNull);
      expect(detallePlaga('maiz', 'otra'), isNull);
    });

    test('todos los registros traen fuente, lugar, periodo y límite, en español e inglés', () {
      for (final c in plagasInvestigacion.keys) {
        for (final t in plagasInvestigacion[c]!) {
          expect(t.en, isNotEmpty);
          for (final r in t.registros) {
            for (final x in [r.danio, r.lugar, r.periodo, r.limite]) {
              expect(x.es, isNotEmpty, reason: r.id);
              expect(x.en, isNotEmpty, reason: r.id);
            }
            expect(r.referencias, isNotEmpty, reason: r.id);
            expect(r.referencias.every((x) => x.fuente.url.startsWith('http')), isTrue, reason: r.id);
          }
        }
      }
    });

    test('el nombre se muestra en el idioma elegido y el id desconocido se muestra tal cual', () {
      expect(const Txt(false).nombreTipoPlaga('palomilla-dorso-de-diamante'), 'Palomilla dorso de diamante');
      expect(const Txt(true).nombreTipoPlaga('palomilla-dorso-de-diamante'), 'Diamondback moth');
      expect(const Txt(false).nombreTipoPlaga('broca'), 'broca');
    });
  });

  group('datos guardados antes de esta versión', () {
    test('una plantación de café con tipo roya sigue cargando', () {
      final viejo = {
        'cultivo': 'cafe', 'fecha': '2026-05-01', 'ciclo': 365, 'suelo': 'franco', 'riego': 'ninguno',
        'temporadaRiego': 'auxilio', 'plagaReciente': true, 'tipoPlaga': 'roya',
      };
      final p = Plantacion.deJson(viejo);
      expect(p.tipoPlaga, 'roya');
      expect(detallePlaga(p.cultivoId, p.tipoPlaga)!.origen, OrigenPlaga.caficultor);
    });

    test('un registro con un tipo que ya no existe se muestra con su id y no falla', () {
      final r = RegistroSemanal.deJson(
          {'fecha': '2026-07-13', 'riegos': 1, 'plaga': 'leve', 'tipoPlaga': 'broca', 'fertilizo': false});
      expect(const Txt(false).resumenRegistro(r), contains('(broca)'));
      expect(detallePlaga('maiz', r.tipoPlaga), isNull);
    });
  });

  group('generador de datos (tool/generar_plagas.dart)', () {
    final plagas = _json('tool/investigacion/plagas_confirmadas.json');
    final fuentes = jsonDecode(File('tool/investigacion/fuentes.json').readAsStringSync()) as List;
    final en = _json('tool/plagas_en.json');

    test('agrupa por cultivo y por nombre común, conservando los taxones', () {
      final g = agruparPlagas(plagas['registros'] as List);
      expect(g.keys, ['maiz', 'frijol', 'cebolla', 'brocoli', 'lechuga']);
      expect([for (final n in g['frijol']!) n.nombreEs], ['Trips de las flores', 'Mosca minadora']);
      expect(g['frijol']![1].registros.length, 2);
      expect(idDePlaga('Palomilla dorso de diamante'), 'palomilla-dorso-de-diamante');
      expect(idDePlaga('Pulgón'), 'pulgon');
      expect(idDePlaga('Ácaro del maíz'), 'acaro-del-maiz');
    });

    test('lo generado coincide con el archivo del repositorio (si no, hay que regenerar)', () {
      final salida = generarPlagasDart(
        plagas: plagas, fuentes: fuentes, en: en,
        commit: plagasFuenteCommit, sha256: plagasFuenteSha256,
      );
      expect(salida.codigo, File('lib/datos/plagas_investigacion.dart').readAsStringSync().replaceAll('\r\n', '\n'));
      expect(salida.advertencias, isEmpty);
    });

    test('un registro sin traducción al inglés se avisa y conserva el texto en español', () {
      final sinEn = {'registros': <String, dynamic>{}, 'etapa': <String, dynamic>{}};
      final salida = generarPlagasDart(
        plagas: plagas, fuentes: fuentes, en: sinEn, commit: 'x', sha256: const {},
      );
      expect(salida.advertencias.length, 12);
      expect(salida.codigo, contains("TextoBi('Flores y vainas', 'Flores y vainas')"));
    });

    test('rechaza un registro que cita una fuente que no está en fuentes.json', () {
      final malo = {
        'registros': [
          {
            'id': 'x-01', 'taxon': 'T', 'resolucion': 'especie', 'nombre_comun': 'N', 'organo_o_dano': 'D',
            'etapa': 'campo', 'lugar': 'L', 'periodo_documentado': 'P', 'notas': 'n', 'cultivo_id': 'maiz',
            'referencias': [{'fuente': 'S99', 'localizador': 'l'}],
          }
        ],
      };
      expect(
        () => generarPlagasDart(plagas: malo, fuentes: fuentes, en: en, commit: 'x', sha256: const {}),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
