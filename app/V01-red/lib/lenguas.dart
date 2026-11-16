/// Glosario en idiomas mayas (BORRADOR, sin revisión de hablantes).
///
/// Es el ÚNICO lugar donde se agrega o corrige una palabra: edita la tabla
/// [glosario]. Una lengua sin entrada para un término muestra el español.
/// Solo se traducen términos sueltos; las frases siguen en español.
/// Ortografía ALMG con la glotal escrita como apóstrofo. Detalle de fuentes y
/// del cotejo en GLOSARIO_LENGUAS.md.
library;

class Lengua {
  const Lengua(this.codigo, this.nombre);
  final String codigo;
  final String nombre;
}

const lenguasMayas = <Lengua>[
  Lengua('quc', "K'iche'"),
  Lengua('cak', 'Kaqchikel'),
  Lengua('kek', "Q'eqchi'"),
  Lengua('mam', 'Mam'),
];

bool esLenguaMaya(String? codigo) => lenguasMayas.any((l) => l.codigo == codigo);

/// Un idioma guardado que la app conoce: español, inglés o una lengua maya.
bool idiomaValido(String? codigo) => codigo == 'es' || codigo == 'en' || esLenguaMaya(codigo);

String nombreLengua(String codigo) => lenguasMayas.firstWhere((l) => l.codigo == codigo).nombre;

/// Resultado del cotejo con los diccionarios del equipo.
enum Cotejo { verificado, variante, sinVerificar }

class Palabra {
  const Palabra(this.texto, this.cotejo, [this.nota = '']);
  final String texto;
  final Cotejo cotejo;
  final String nota;
}

class Termino {
  const Termino(this.id, this.es, this.palabras);

  /// Identificador estable que usa el código (por ejemplo, `maiz`).
  final String id;
  final String es;

  /// Por código de lengua. Sin entrada = sin borrador: se queda el español.
  final Map<String, Palabra> palabras;
}

const _s = Cotejo.sinVerificar;
const _v = Cotejo.verificado;
const _c = Cotejo.variante;

const glosario = <Termino>[
  Termino('maiz', 'maíz', {
    'quc': Palabra('ixim', _v, 'kiche.md, p. 93'),
    'cak': Palabra('ixim', _s),
    'kek': Palabra('ixim', _v, 'qeqchi.md, p. 268'),
    'mam': Palabra("ixi'n", _s),
  }),
  Termino('frijol', 'frijol', {
    'quc': Palabra("kinaq'", _v, 'kiche.md, p. 93'),
    'cak': Palabra("kinäq'", _c, "kaqchikel.md: kinaq' (sin diéresis), pp. 64-66"),
    'kek': Palabra("kenq'", _v, 'qeqchi.md, p. 238'),
    'mam': Palabra("chenaq'", _s),
  }),
  Termino('tomate', 'tomate', {
    'quc': Palabra('pix', _v, 'kiche.md, p. 92'),
    'cak': Palabra("ixkoya'", _c, "kaqchikel.md: xkoya', p. 64"),
    'kek': Palabra('pix', _s, 'qeqchi.md no trae «tomate»'),
    'mam': Palabra("xko'ya'", _s),
  }),
  Termino('cafe', 'café', {
    'quc': Palabra('kape', _v, 'kiche.md, p. 114 (bebida; la planta es qakoj)'),
    'cak': Palabra('kape', _v, 'kaqchikel.md, p. 66 (bebida)'),
    'kek': Palabra("kape'", _c, 'qeqchi.md: kape (sin apóstrofo), p. 208'),
    'mam': Palabra('kape', _s),
  }),
  Termino('banano', 'banano', {
    'quc': Palabra("saq'ul", _s),
    'cak': Palabra("saq'ul", _s),
    'kek': Palabra('tul', _s),
  }),
  Termino('agua', 'agua', {
    'quc': Palabra("ja'", _v, 'kiche.md, p. 105'),
    'cak': Palabra("ya'", _v, "kaqchikel.md, p. 66 (el archivo la marca «por verificar»)"),
    'kek': Palabra("ha'", _v, 'qeqchi.md, p. 181'),
    'mam': Palabra("a'", _s),
  }),
  Termino('lluvia', 'lluvia', {
    'quc': Palabra("jab'", _v, 'kiche.md, p. 105'),
    'cak': Palabra("jäb'", _s),
    'kek': Palabra("hab'", _v, 'qeqchi.md, p. 266'),
    'mam': Palabra("jb'al", _s),
  }),
  Termino('suelo', 'tierra / suelo', {
    'quc': Palabra('ulew', _v, 'kiche.md, p. 81 (derivada de «piocha»)'),
    'cak': Palabra('ulew', _s),
    'kek': Palabra("ch'och'", _v, 'qeqchi.md, p. 326'),
    'mam': Palabra("tx'otx'", _s),
  }),
  Termino('hoy', 'hoy', {
    'quc': Palabra('kamik', _s, 'kiche.md solo trae kamik como «morir»: ojo'),
    'cak': Palabra('wakami', _s),
    'kek': Palabra('anaqwan', _s),
    'mam': Palabra("ja'la", _s),
  }),
  Termino('siembra', 'siembra', {
    'quc': Palabra("tiko'n", _s, "kiche.md solo propone tikonik (sin revisar)"),
    'cak': Palabra("tiko'n", _s, "kaqchikel.md trae ajtiko'n (agricultor), no la palabra"),
    'kek': Palabra('awimq', _s, "qeqchi.md trae awk (sembrar) y awleb'aal (época de siembra)"),
    'mam': Palabra('awal', _s),
  }),
  Termino('sombra', 'sombra', {
    'quc': Palabra("mu'j", _s),
    'cak': Palabra('muj', _s),
    'kek': Palabra('mu', _s),
    'mam': Palabra('muj', _s),
  }),
  Termino('cosecha', 'cosecha (de maíz)', {
    'quc': Palabra("jach'", _s, "kiche.md solo propone k'ob'anik / sik'ixik (sin revisar)"),
    'cak': Palabra("jach'", _s),
    'kek': Palabra("q'olok", _v, 'qeqchi.md, p. 208 (cosechar milpa)'),
  }),
];

/// Palabra del glosario en [lengua], o null si no hay borrador (queda el español).
String? palabraMaya(String lengua, String id) {
  for (final t in glosario) {
    if (t.id == id) return t.palabras[lengua]?.texto;
  }
  return null;
}

/// «ixim · maíz»: el término en la lengua con el español al lado; solo el
/// español si no hay borrador.
String conEspanol(String lengua, String id, String es) {
  final p = palabraMaya(lengua, id);
  return p == null ? es : '$p · $es';
}
