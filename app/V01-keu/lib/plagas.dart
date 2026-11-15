/// Lista de plagas por cultivo y su detalle. Solo registro: no hay predicción,
/// umbrales ni recomendaciones de tratamiento.
library;

import 'datos/plagas_investigacion.dart';
import 'plagas_tipos.dart';

/// Tipos de plaga o enfermedad que el productor puede elegir al reportarla, por
/// cultivo. Maíz, frijol, cebolla, brócoli y lechuga salen de la investigación
/// del equipo (datos/plagas_investigacion.dart, generado desde sus archivos); el
/// café conserva lo que nombró un caficultor. 'otra' va siempre al final. Un
/// cultivo sin entrada (ajonjolí, papa, tomate) solo ofrece 'otra'.
const tiposPlagaPorCultivo = <String, List<TipoPlaga>>{
  ...plagasInvestigacion,
  'cafe': [
    TipoPlaga('roya', 'Roya', 'Rust', origen: OrigenPlaga.caficultor),
    TipoPlaga('minador', 'Minador', 'Leaf miner', origen: OrigenPlaga.caficultor),
    TipoPlaga('antracnosis', 'Antracnosis', 'Anthracnose', origen: OrigenPlaga.caficultor),
    otraPlaga,
  ],
};

/// Ids de los tipos de plaga de un cultivo; los que no tienen lista propia solo
/// ofrecen 'otra'.
List<String> tiposPlaga(String cultivoId) =>
    [for (final t in tiposPlagaPorCultivo[cultivoId] ?? const [otraPlaga]) t.id];

/// Los tipos de plaga de un cultivo, con nombres y registros.
List<TipoPlaga> tiposPlagaDe(String cultivoId) => tiposPlagaPorCultivo[cultivoId] ?? const [otraPlaga];

/// Verdadero si el equipo aún no tiene una lista de plagas para este cultivo.
bool sinRegistroConfirmado(String cultivoId) => !tiposPlagaPorCultivo.containsKey(cultivoId);

/// Busca un tipo de plaga por id en todas las listas; nulo si no existe.
TipoPlaga? tipoPlagaPorId(String id) {
  for (final lista in [...tiposPlagaPorCultivo.values, const [otraPlaga]]) {
    for (final t in lista) {
      if (t.id == id) return t;
    }
  }
  return null;
}

/// Detalle de una plaga en un cultivo; nulo si ese cultivo no la tiene ('otra'
/// tampoco tiene detalle).
TipoPlaga? detallePlaga(String cultivoId, String id) {
  for (final t in tiposPlagaPorCultivo[cultivoId] ?? const <TipoPlaga>[]) {
    if (t.id == id && t.origen != OrigenPlaga.otra) return t;
  }
  return null;
}
