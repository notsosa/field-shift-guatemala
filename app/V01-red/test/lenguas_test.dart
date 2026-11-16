import 'package:field_shift/lenguas.dart';
import 'package:field_shift/textos.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Ortografía exacta del glosario del encargo. '' = sin borrador.
  const esperado = <String, Map<String, String>>{
    'maiz': {'quc': 'ixim', 'cak': 'ixim', 'kek': 'ixim', 'mam': "ixi'n"},
    'frijol': {'quc': "kinaq'", 'cak': "kinäq'", 'kek': "kenq'", 'mam': "chenaq'"},
    'tomate': {'quc': 'pix', 'cak': "ixkoya'", 'kek': 'pix', 'mam': "xko'ya'"},
    'cafe': {'quc': 'kape', 'cak': 'kape', 'kek': "kape'", 'mam': 'kape'},
    'banano': {'quc': "saq'ul", 'cak': "saq'ul", 'kek': 'tul', 'mam': ''},
    'agua': {'quc': "ja'", 'cak': "ya'", 'kek': "ha'", 'mam': "a'"},
    'lluvia': {'quc': "jab'", 'cak': "jäb'", 'kek': "hab'", 'mam': "jb'al"},
    'suelo': {'quc': 'ulew', 'cak': 'ulew', 'kek': "ch'och'", 'mam': "tx'otx'"},
    'hoy': {'quc': '', 'cak': 'wakami', 'kek': 'anaqwan', 'mam': "ja'la"},
    'siembra': {'quc': "tiko'n", 'cak': "tiko'n", 'kek': 'awimq', 'mam': 'awal'},
    'sombra': {'quc': "mu'j", 'cak': 'muj', 'kek': 'mu', 'mam': 'muj'},
    'cosecha': {'quc': "jach'", 'cak': "jach'", 'kek': "q'olok", 'mam': ''},
  };

  test('cada celda del glosario devuelve exactamente la ortografía acordada', () {
    expect(glosario.map((t) => t.id).toSet(), esperado.keys.toSet());
    for (final e in esperado.entries) {
      for (final l in lenguasMayas) {
        final w = e.value[l.codigo]!;
        expect(palabraMaya(l.codigo, e.key), w.isEmpty ? isNull : w, reason: '${e.key}/${l.codigo}');
      }
    }
  });

  test('las celdas vacías y lo desconocido caen al español', () {
    expect(conEspanol('mam', 'banano', 'banano'), 'banano');
    expect(conEspanol('mam', 'cosecha', 'cosecha (de maíz)'), 'cosecha (de maíz)');
    expect(conEspanol('quc', 'inexistente', 'algo'), 'algo');
    expect(conEspanol('quc', 'maiz', 'maíz'), 'ixim · maíz');
  });

  test('Txt: las lenguas mayas cambian solo términos sueltos; es y en no cambian', () {
    const es = Txt(false);
    const en = Txt(true);
    const quc = Txt(false, lengua: 'quc');
    expect(es.nombreCultivo('maiz'), 'Maíz');
    expect(en.nombreCultivo('maiz'), 'Maize');
    expect(es.esMaya, isFalse);
    expect(quc.nombreCultivo('maiz'), 'ixim · Maíz');
    expect(quc.nombreCultivoCorto('frijol'), "kinaq'");
    expect(quc.hoy, 'Hoy'); // sin borrador en K'iche': español
    expect(quc.hoyTitulo, 'Hoy');
    expect(const Txt(false, lengua: 'cak').hoyTitulo, 'wakami · Hoy');
    expect(quc.lluvia, "jab' · Lluvia");
    expect(quc.guardar, es.guardar); // lo que no está en el glosario, en español
    expect(quc.avisoBorrador,
        startsWith("Traducción en borrador: solo algunas palabras están en K'iche' y ningún hablante"));
  });

  test('idiomaValido acepta es, en y las lenguas mayas; rechaza lo demás', () {
    for (final c in ['es', 'en', 'quc', 'cak', 'kek', 'mam']) {
      expect(idiomaValido(c), isTrue, reason: c);
    }
    expect(idiomaValido('fr'), isFalse);
    expect(idiomaValido(null), isFalse);
  });
}
