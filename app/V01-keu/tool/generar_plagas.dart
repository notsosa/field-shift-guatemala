/// Genera `lib/datos/plagas_investigacion.dart` a partir de la investigación del
/// equipo (plagas_confirmadas.json + fuentes.json) y de la traducción al inglés
/// hecha a mano (plagas_en.json).
///
/// Para regenerarlo cuando la investigación crezca, desde `app/V01-keu`:
///
///   1. copia plagas_confirmadas.json, fuentes.json y verificacion.json a
///      tool/investigacion/ (de la carpeta `investigacion/plagas-7-cultivos-guatemala/confirmadas/`);
///   2. agrega la traducción de cada registro nuevo en tool/plagas_en.json;
///   3. dart tool/generar_plagas.dart COMMIT   (el commit de la investigación)
///
/// No inventa nada: cada texto sale del archivo de la investigación.
library;

import 'dart:convert';
import 'dart:io';

/// Registros de un mismo nombre común dentro de un cultivo.
class GrupoPlaga {
  GrupoPlaga(this.nombreEs);

  final String nombreEs;
  final List<Map<String, dynamic>> registros = [];
}

/// Resultado de generar: el código Dart y las advertencias (traducciones que faltan).
class SalidaPlagas {
  SalidaPlagas(this.codigo, this.advertencias);

  final String codigo;
  final List<String> advertencias;
}

const _sinAcento = {
  'á': 'a',
  'é': 'e',
  'í': 'i',
  'ó': 'o',
  'ú': 'u',
  'ü': 'u',
  'ñ': 'n',
};

/// Id estable de una plaga a partir de su nombre común: minúsculas, sin acentos, con guiones.
String idDePlaga(String nombreComun) {
  final sb = StringBuffer();
  for (final c in nombreComun.toLowerCase().split('')) {
    sb.write(_sinAcento[c] ?? c);
  }
  return sb
      .toString()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}

/// Agrupa los registros por cultivo y, dentro del cultivo, por nombre común
/// (una entrada por nombre; los taxones quedan debajo), en el orden del archivo.
Map<String, List<GrupoPlaga>> agruparPlagas(List registros) {
  final salida = <String, List<GrupoPlaga>>{};
  for (final r in registros.cast<Map<String, dynamic>>()) {
    final grupos = salida.putIfAbsent(r['cultivo_id'] as String, () => []);
    final nombre = r['nombre_comun'] as String;
    var g = grupos.where((x) => x.nombreEs == nombre).firstOrNull;
    if (g == null) {
      g = GrupoPlaga(nombre);
      grupos.add(g);
    }
    g.registros.add(r);
  }
  return salida;
}

String _q(String s) =>
    "'${s.replaceAll(r'\', r'\\').replaceAll("'", r"\'").replaceAll(r'$', r'\$')}'";

String _bi(String es, String en) => 'TextoBi(${_q(es)}, ${_q(en)})';

/// Construye el archivo Dart. Lanza [FormatException] si un registro cita una
/// fuente que no está en `fuentes`.
SalidaPlagas generarPlagasDart({
  required Map<String, dynamic> plagas,
  required List fuentes,
  required Map<String, dynamic> en,
  required String commit,
  required Map<String, String> sha256,
}) {
  final registros = plagas['registros'] as List;
  final fuentePorId = {
    for (final f in fuentes.cast<Map<String, dynamic>>()) f['id'] as String: f,
  };
  final enReg = (en['registros'] as Map?)?.cast<String, dynamic>() ?? const {};
  final enEtapa = (en['etapa'] as Map?)?.cast<String, dynamic>() ?? const {};
  final advertencias = <String>[];
  final usadas = <String>{};

  String fuenteVar(String id) => '_${id.toLowerCase()}';

  final cuerpo = StringBuffer();
  final grupos = agruparPlagas(registros);
  cuerpo.writeln(
    '/// Plagas por cultivo según la investigación del equipo, sin "otra" al final.',
  );
  cuerpo.writeln('const plagasInvestigacion = <String, List<TipoPlaga>>{');
  for (final entrada in grupos.entries) {
    cuerpo.writeln('  ${_q(entrada.key)}: [');
    for (final g in entrada.value) {
      final primero = g.registros.first;
      final enNombre = (enReg[primero['id']] as Map?)?['nombre'] as String?;
      cuerpo.writeln('    TipoPlaga(');
      cuerpo.writeln(
        '      ${_q(idDePlaga(g.nombreEs))}, ${_q(g.nombreEs)}, ${_q(enNombre ?? g.nombreEs)},',
      );
      cuerpo.writeln('      registros: [');
      for (final r in g.registros) {
        final id = r['id'] as String;
        final t = (enReg[id] as Map?)?.cast<String, dynamic>();
        if (t == null)
          advertencias.add(
            'Falta la traducción al inglés de $id en tool/plagas_en.json',
          );
        String tr(String campo, String es) => (t?[campo] as String?) ?? es;
        final etapa = r['etapa'] as String;
        cuerpo.writeln('        RegistroPlaga(');
        cuerpo.writeln('          id: ${_q(id)},');
        cuerpo.writeln('          taxon: ${_q(r['taxon'] as String)},');
        cuerpo.writeln(
          '          resolucion: ${_q(r['resolucion'] as String)},',
        );
        cuerpo.writeln(
          '          danio: ${_bi(r['organo_o_dano'] as String, tr('danio', r['organo_o_dano'] as String))},',
        );
        cuerpo.writeln(
          '          etapa: ${_bi(etapa, (enEtapa[etapa] as String?) ?? etapa)},',
        );
        cuerpo.writeln(
          '          lugar: ${_bi(r['lugar'] as String, tr('lugar', r['lugar'] as String))},',
        );
        cuerpo.writeln(
          '          periodo: ${_bi(r['periodo_documentado'] as String, tr('periodo', r['periodo_documentado'] as String))},',
        );
        cuerpo.writeln(
          '          limite: ${_bi(r['notas'] as String, tr('limite', r['notas'] as String))},',
        );
        cuerpo.writeln('          referencias: [');
        for (final ref
            in (r['referencias'] as List).cast<Map<String, dynamic>>()) {
          final fid = ref['fuente'] as String;
          if (!fuentePorId.containsKey(fid)) {
            throw FormatException(
              'El registro $id cita la fuente $fid, que no está en fuentes.json',
            );
          }
          usadas.add(fid);
          cuerpo.writeln(
            '            ReferenciaPlaga(${fuenteVar(fid)}, ${_q(ref['localizador'] as String)}),',
          );
        }
        cuerpo.writeln('          ],');
        cuerpo.writeln('        ),');
      }
      cuerpo.writeln('      ],');
      cuerpo.writeln('    ),');
    }
    cuerpo.writeln('    otraPlaga,');
    cuerpo.writeln('  ],');
  }
  cuerpo.writeln('};');

  final sb = StringBuffer()
    ..writeln(
      '// GENERADO por tool/generar_plagas.dart. No editar a mano: edita la investigación y regenera.',
    )
    ..writeln(
      '// Fuente: investigacion/plagas-7-cultivos-guatemala/confirmadas/ del repositorio del equipo,',
    )
    ..writeln("// commit $commit, revisión ${plagas['fecha']}.")
    ..writeln('library;')
    ..writeln()
    ..writeln("import '../plagas_tipos.dart';")
    ..writeln()
    ..writeln(
      '/// Commit del repositorio del equipo del que salen estos datos.',
    )
    ..writeln('const plagasFuenteCommit = ${_q(commit)};')
    ..writeln()
    ..writeln('/// Fecha de revisión de la investigación.')
    ..writeln('const plagasFechaRevision = ${_q(plagas['fecha'] as String)};')
    ..writeln()
    ..writeln(
      '/// SHA-256 de los archivos de la investigación (según su verificacion.json).',
    )
    ..writeln('const plagasFuenteSha256 = <String, String>{');
  for (final e in sha256.entries) {
    sb.writeln('  ${_q(e.key)}: ${_q(e.value)},');
  }
  sb
    ..writeln('};')
    ..writeln();
  for (final id in (usadas.toList()..sort())) {
    final f = fuentePorId[id]!;
    sb
      ..writeln('const ${fuenteVar(id)} = FuentePlaga(')
      ..writeln('  id: ${_q(id)},')
      ..writeln('  titulo: ${_q(f['titulo'] as String)},')
      ..writeln('  institucion: ${_q(f['institucion'] as String)},')
      ..writeln('  fecha: ${_q(f['fecha_documento'] as String)},')
      ..writeln('  url: ${_q(f['url'] as String)},')
      ..writeln(');')
      ..writeln();
  }
  sb.write(cuerpo);

  // Cultivos con plagas documentadas fuera de la tabla de registros confirmados
  // (papa y ajonjolí): solo cuántas entradas y de qué tipo, no plagas elegibles.
  final cob = plagas['cobertura_documental'] as Map<String, dynamic>?;
  final cobEn = (en['cobertura'] as Map?)?.cast<String, dynamic>() ?? const {};
  final tiposEn = (cobEn['tipos'] as Map?)?.cast<String, dynamic>() ?? const {};
  final cultivosCob =
      (cob?['cultivos_con_plagas_documentadas_fuera_de_tabla'] as List?)
          ?.cast<Map<String, dynamic>>() ??
      const [];
  if (cultivosCob.isNotEmpty) {
    final interpretacion = cob!['interpretacion'] as String;
    final interpretacionEn = cobEn['interpretacion'] as String?;
    sb
      ..writeln()
      ..writeln(
        '/// Cultivos con plagas documentadas por la revisión del equipo fuera de la tabla de',
      )
      ..writeln(
        '/// registros confirmados. No son registros ni plagas elegibles.',
      )
      ..writeln('const plagasCobertura = <String, CoberturaPlaga>{');
    for (final c in cultivosCob) {
      final nombre = c['cultivo'] as String;
      final tipos = (c['tipos_evidencia'] as List).cast<String>();
      if (interpretacionEn == null ||
          tipos.any((t) => !tiposEn.containsKey(t))) {
        advertencias.add(
          'Falta la traducción al inglés de la cobertura documental de $nombre en tool/plagas_en.json',
        );
      }
      sb
        ..writeln('  ${_q(idDePlaga(nombre))}: CoberturaPlaga(')
        ..writeln('    entradas: ${c['entradas_en_revision_documental']},')
        ..writeln('    tipos: [')
        ..writeln(
          [
            for (final t in tipos)
              '      ${_bi(t, (tiposEn[t] as String?) ?? t)},',
          ].join('\n'),
        )
        ..writeln('    ],')
        ..writeln(
          '    interpretacion: ${_bi(interpretacion, interpretacionEn ?? interpretacion)},',
        )
        ..writeln('  ),');
    }
    sb.writeln('};');
  } else {
    sb
      ..writeln()
      ..writeln('const plagasCobertura = <String, CoberturaPlaga>{};');
  }
  return SalidaPlagas(sb.toString(), advertencias);
}

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Uso: dart tool/generar_plagas.dart <commit de la investigación>',
    );
    exit(64);
  }
  Object leer(String ruta) => jsonDecode(File(ruta).readAsStringSync());
  final verificacion =
      leer('tool/investigacion/verificacion.json') as Map<String, dynamic>;
  final hashes = {
    for (final a
        in (verificacion['archivos'] as List).cast<Map<String, dynamic>>())
      if (a['ruta'] != 'README.md') a['ruta'] as String: a['sha256'] as String,
  };
  final salida = generarPlagasDart(
    plagas: leer(
      'tool/investigacion/plagas_confirmadas.json',
    ) as Map<String, dynamic>,
    fuentes: leer('tool/investigacion/fuentes.json') as List,
    en: leer('tool/plagas_en.json') as Map<String, dynamic>,
    commit: args.first,
    sha256: hashes,
  );
  File('lib/datos/plagas_investigacion.dart').writeAsStringSync(salida.codigo);
  for (final a in salida.advertencias) {
    stderr.writeln('AVISO: $a');
  }
  stdout.writeln(
    'Escrito lib/datos/plagas_investigacion.dart (${salida.advertencias.length} avisos).',
  );
}
