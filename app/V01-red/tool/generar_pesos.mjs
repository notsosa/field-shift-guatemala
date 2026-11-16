// Genera lib/motor/pesos_app.dart a partir de web/data/app_mlp.json del repositorio del equipo.
// El archivo Dart no se edita a mano: se vuelve a generar con este script.
//
//   node tool/generar_pesos.mjs [ruta/a/app_mlp.json]
//
// Corre desde app/V01-red/. Solo usa Node (sin paquetes) y git para anotar de qué commit salen los pesos.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { dirname, resolve, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const aqui = dirname(fileURLToPath(import.meta.url));
const raiz = resolve(aqui, '..');
const origen = resolve(process.argv[2] ?? resolve(raiz, '../../web/data/app_mlp.json'));
const salida = resolve(raiz, 'lib/motor/pesos_app.dart');

const bytes = readFileSync(origen);
const red = JSON.parse(bytes.toString('utf8'));

const carpetaGit = dirname(origen);
const git = (...args) => {
  try {
    return execFileSync('git', args, { cwd: carpetaGit, encoding: 'utf8' }).trim();
  } catch {
    return '';
  }
};
const commit = git('log', '-1', '--format=%H', '--', origen) || 'desconocido';
const sucio = git('status', '--porcelain', '--', origen) !== '';
const sha256 = createHash('sha256').update(bytes).digest('hex');
const rutaRepo = git('rev-parse', '--show-toplevel') ? relative(git('rev-parse', '--show-toplevel'), origen).replaceAll('\\', '/') : origen;

// Comprobaciones: la forma de la red tiene que ser la que la app arma.
const arq = red.architecture;
if (!Array.isArray(arq) || arq[0] !== red.inputNames.length || red.mean.length !== arq[0] || red.std.length !== arq[0]) {
  throw new Error('La arquitectura no coincide con las entradas');
}
red.layers.forEach((c, i) => {
  if (c.W.length !== arq[i + 1] || c.W.some((f) => f.length !== arq[i]) || c.b.length !== arq[i + 1]) throw new Error(`Capa ${i} con forma inesperada`);
});
const parametros = red.layers.reduce((a, c) => a + c.W.length * c.W[0].length + c.b.length, 0);
if (parametros !== red.params) throw new Error(`Parámetros: ${parametros} contra ${red.params} anotados`);

// Un número de JavaScript (la forma más corta que vuelve al mismo valor) es también un literal de Dart válido.
const num = (v) => {
  if (!Number.isFinite(v)) throw new Error('Peso no finito');
  const s = String(v);
  return /[.eE]/.test(s) ? s : `${s}.0`;
};
const lista = (a) => `[${a.map(num).join(', ')}]`;
const cadenas = (a) => `[${a.map((s) => `'${s}'`).join(', ')}]`;

const capas = red.layers
  .map((c) => `    {\n      'W': [\n${c.W.map((f) => `        ${lista(f)},`).join('\n')}\n      ],\n      'b': ${lista(c.b)},\n    }`)
  .join(',\n');

const texto = `// GENERADO por tool/generar_pesos.mjs. No editar a mano: se vuelve a generar.
//
// Fuente: ${rutaRepo}${sucio ? ' (con cambios sin confirmar)' : ''}
// Commit de la fuente: ${commit}
// SHA-256 del archivo fuente: ${sha256}
// Red: ${arq.join(' → ')} (${red.params} parámetros), semilla ${red.seed}, ReLU en las capas ocultas y salida lineal.
// Entradas: ${red.inputNames.length}, en el orden de \`pesosAppEntradas\`.
// Salidas: ${red.targetNames.join(', ')}.
library;

/// Commit del repositorio del equipo del que salen estos pesos.
const pesosAppCommit = '${commit}';

/// Archivo fuente de los pesos.
const pesosAppFuente = '${rutaRepo}';

/// SHA-256 del archivo fuente.
const pesosAppSha256 = '${sha256}';

/// Nombres de las ${red.inputNames.length} entradas, en el orden que espera la red.
const pesosAppEntradas = <String>${cadenas(red.inputNames)};

/// Nombres de las ${red.targetNames.length} salidas, en orden.
const pesosAppSalidas = <String>${cadenas(red.targetNames)};

/// Red en el formato de \`web/data/app_mlp.json\` (lo que lee \`predecirCapas\` de red.dart).
const pesosApp = <String, dynamic>{
  'mean': ${lista(red.mean)},
  'std': ${lista(red.std)},
  'yMean': ${lista(red.yMean)},
  'yStd': ${lista(red.yStd)},
  'layers': <Map<String, dynamic>>[
${capas},
  ],
};
`;

writeFileSync(salida, texto);
console.log(`Escrito ${relative(process.cwd(), salida)}: ${red.params} parámetros, commit ${commit.slice(0, 7)}, ${texto.length} caracteres`);
