// Genera lib/motor/pesos_cafe.dart (red de riego del café, versión 3, con las clases de la auditoría del asesor) y
// lib/motor/fuentes_cafe.dart (textos, fuentes y confianza de los avisos) a partir de los archivos del
// repositorio del equipo. Los archivos Dart no se editan a mano: se vuelven a generar con este script.
//
//   node tool/generar_pesos_cafe.mjs [ruta/a/coffee_ptc_mlp_v3.json] [ruta/a/coffee_sources.json]
//
// Corre desde app/V01-red/. Solo usa Node (sin paquetes) y git para anotar de qué commit salen los datos.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const raiz = resolve(aqui, '..');
const origenRed = resolve(process.argv[2] ?? resolve(raiz, '../../web/data/coffee_ptc_mlp_v3.json'));
const origenFuentes = resolve(process.argv[3] ?? resolve(raiz, '../../web/data/coffee_sources.json'));

function info(origen) {
  const bytes = readFileSync(origen);
  const carpeta = dirname(origen);
  const git = (...args) => {
    try {
      return execFileSync('git', args, { cwd: carpeta, encoding: 'utf8' }).trim();
    } catch {
      return '';
    }
  };
  const top = git('rev-parse', '--show-toplevel');
  return {
    json: JSON.parse(bytes.toString('utf8')),
    commit: git('log', '-1', '--format=%H', '--', origen) || 'desconocido',
    sucio: git('status', '--porcelain', '--', origen) !== '',
    sha256: createHash('sha256').update(bytes).digest('hex'),
    ruta: top ? relative(top, origen).replaceAll('\\', '/') : origen,
  };
}

// Un número de JavaScript (la forma más corta que vuelve al mismo valor) es también un literal de Dart válido.
const num = (v) => {
  if (!Number.isFinite(v)) throw new Error('Peso no finito');
  const s = String(v);
  return /[.eE]/.test(s) ? s : `${s}.0`;
};
const lista = (a) => `[${a.map(num).join(', ')}]`;
const cadenas = (a) => `[${a.map((s) => `'${s}'`).join(', ')}]`;
// Cadena de Dart con comillas simples y sin interpolación.
const cad = (s) => `'${s.replaceAll('\\', '\\\\').replaceAll("'", "\\'").replaceAll('$', '\\$').replaceAll('\n', '\\n')}'`;

// ---------- Pesos ----------
const r = info(origenRed);
const red = r.json;
const arq = red.architecture;
if (!Array.isArray(arq) || arq[0] !== red.inputNames.length || red.mean.length !== arq[0] || red.std.length !== arq[0]) {
  throw new Error('La arquitectura no coincide con las entradas');
}
if (red.inputNames.length !== 19 || red.inputNames[16] !== 'weeds' || red.inputNames[17] !== 'bananaRegulated' || red.inputNames[18] !== 'bananaDense') {
  throw new Error('Se esperaba la red versión 3 (19 entradas, weeds, bananaRegulated y bananaDense al final)');
}
red.layers.forEach((c, i) => {
  if (c.W.length !== arq[i + 1] || c.W.some((f) => f.length !== arq[i]) || c.b.length !== arq[i + 1]) throw new Error(`Capa ${i} con forma inesperada`);
});
const parametros = red.layers.reduce((a, c) => a + c.W.length * c.W[0].length + c.b.length, 0);
if (parametros !== red.params) throw new Error(`Parámetros: ${parametros} contra ${red.params} anotados`);

const capas = red.layers
  .map((c) => `    {\n      'W': [\n${c.W.map((f) => `        ${lista(f)},`).join('\n')}\n      ],\n      'b': ${lista(c.b)},\n    }`)
  .join(',\n');

const pesos = `// GENERADO por tool/generar_pesos_cafe.mjs. No editar a mano: se vuelve a generar.
//
// Fuente: ${r.ruta}${r.sucio ? ' (con cambios sin confirmar)' : ''}
// Commit de la fuente: ${r.commit}
// SHA-256 del archivo fuente: ${r.sha256}
// Red: ${arq.join(' → ')} (${red.params} parámetros), semilla ${red.seed}, ReLU en las capas ocultas y salida lineal.
// Entradas: ${red.inputNames.length}, en el orden de \`pesosCafeEntradas\`.
// Salida: ${red.target}.
// Las clases de sistema (malezas, banano regulado, banano denso) son valores de referencia de FAO-56 de la auditoría del asesor, no medidas de campo (ver el campo \`systemSource\` del archivo fuente).
library;

/// Commit del repositorio del equipo del que salen estos pesos.
const pesosCafeCommit = '${r.commit}';

/// Archivo fuente de los pesos.
const pesosCafeFuente = '${r.ruta}';

/// SHA-256 del archivo fuente.
const pesosCafeSha256 = '${r.sha256}';

/// Semilla de la red exportada.
const pesosCafeSemilla = ${red.seed};

/// Nombres de las ${red.inputNames.length} entradas, en el orden que espera la red.
const pesosCafeEntradas = <String>${cadenas(red.inputNames)};

/// Red en el formato de \`web/data/coffee_ptc_mlp_v3.json\` (lo que lee \`predecirCapas\` de red.dart).
/// La salida, ya en sus unidades, son los días de estrés que evitaría regar 20 mm hoy en los 30 días siguientes.
const pesosCafe = <String, dynamic>{
  'mean': ${lista(red.mean)},
  'std': ${lista(red.std)},
  'yMean': ${lista(red.yMean)},
  'yStd': ${lista(red.yStd)},
  'layers': <Map<String, dynamic>>[
${capas},
  ],
};
`;
writeFileSync(resolve(raiz, 'lib/motor/pesos_cafe.dart'), pesos);
console.log(`Escrito lib/motor/pesos_cafe.dart: ${red.params} parámetros, commit ${r.commit.slice(0, 7)}`);

// ---------- Fuentes de los avisos ----------
const f = info(origenFuentes);
const fuentes = f.json.sources;
// Fuente abreviada para una sola línea en la pantalla (la completa va en `fuente`).
const corta = {
  roya_favorable: 'Avelino et al. 2015',
  roya_posible: 'Anacafé/Cedicafé 2015',
  roya_latencia: 'Anacafé/Cedicafé 2015',
  minador: 'Ramírez-Valerio y García-Jiménez 2021; Anacafé 2026',
  antracnosis: 'Campos-Almengor (Cedicafé); Anacafé',
  abono_ventanas: 'Anacafé, Guía Técnica 2014',
  abono_suelo_seco: 'Anacafé, boletín ENOS 2026',
  fao56_cafe: 'FAO-56 (Allen et al. 1998)',
  sombra_padovan: 'Padovan et al. 2018',
  floracion: 'Anacafé, Guía Técnica 2014',
  riego_20mm: 'Duarte-Canales et al. 2016',
};
// Nivel de confianza: la primera palabra (o par de palabras) de la frase del archivo fuente.
const nivel = (c) => c.split(/[;(]/)[0].trim();
const entradas = Object.entries(fuentes).map(([k, v]) => {
  if (!corta[k]) throw new Error(`Falta la fuente abreviada de ${k}`);
  return `  ${cad(k)}: FuenteCafe(
    texto: ${cad(v.text)},
    fuente: ${cad(v.source)},
    fuenteCorta: ${cad(corta[k])},
    url: ${cad(v.url)},
    confianza: ${cad(v.confidence)},
    nivelConfianza: ${cad(nivel(v.confidence))},
  ),`;
});

const fuentesDart = `// GENERADO por tool/generar_pesos_cafe.mjs. No editar a mano: se vuelve a generar.
//
// Fuente: ${f.ruta}${f.sucio ? ' (con cambios sin confirmar)' : ''}
// Commit de la fuente: ${f.commit}
// SHA-256 del archivo fuente: ${f.sha256}
// Textos, fuentes y confianza de los avisos de café. La clave es la \`sourceKey\` de web/js/model/coffee.js.
// Los textos están en español, como en el archivo fuente; \`fuenteCorta\` y \`nivelConfianza\` se usan en la pantalla.
library;

/// Commit del repositorio del equipo del que salen estos textos.
const fuentesCafeCommit = '${f.commit}';

/// SHA-256 del archivo fuente.
const fuentesCafeSha256 = '${f.sha256}';

/// Un texto con su fuente y su nivel de confianza.
class FuenteCafe {
  const FuenteCafe({
    required this.texto,
    required this.fuente,
    required this.fuenteCorta,
    required this.url,
    required this.confianza,
    required this.nivelConfianza,
  });

  final String texto;
  final String fuente;
  final String fuenteCorta;
  final String url;
  final String confianza;

  /// «alta», «media-alta», «media», «baja-media», «baja», «orientativa» o el texto del archivo fuente.
  final String nivelConfianza;
}

const fuentesCafe = <String, FuenteCafe>{
${entradas.join('\n')}
};
`;
writeFileSync(resolve(raiz, 'lib/motor/fuentes_cafe.dart'), fuentesDart);
console.log(`Escrito lib/motor/fuentes_cafe.dart: ${entradas.length} fuentes, commit ${f.commit.slice(0, 7)}`);
