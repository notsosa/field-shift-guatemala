/// Tipos de datos de las plagas: nombre en dos idiomas, registros de la
/// investigación del equipo y sus fuentes. Solo datos, sin lógica.
library;

/// Un texto en español e inglés.
class TextoBi {
  const TextoBi(this.es, this.en);

  final String es;
  final String en;

  String de(bool ingles) => ingles ? en : es;
}

/// Documento del que sale un registro (de fuentes.json de la investigación).
class FuentePlaga {
  const FuentePlaga({
    required this.id,
    required this.titulo,
    required this.institucion,
    required this.fecha,
    required this.url,
  });

  final String id;
  final String titulo;
  final String institucion;
  final String fecha;
  final String url;

  /// Cita corta: institución, título y fecha del documento.
  String get cita => '$institucion · $titulo · $fecha';
}

/// Dónde de la fuente sale el registro (página, cuadro o sección).
class ReferenciaPlaga {
  const ReferenciaPlaga(this.fuente, this.localizador);

  final FuentePlaga fuente;
  final String localizador;
}

/// Un registro cultivo–taxón de la investigación, tal como lo documenta ella.
class RegistroPlaga {
  const RegistroPlaga({
    required this.id,
    required this.taxon,
    required this.resolucion,
    required this.danio,
    required this.etapa,
    required this.lugar,
    required this.periodo,
    required this.limite,
    required this.referencias,
  });

  final String id;

  /// Nombre científico tal como lo identificó la fuente (puede ser solo género).
  final String taxon;

  /// "especie" o "grupo" (género), según la investigación.
  final String resolucion;

  /// Órgano o daño que describe la fuente.
  final TextoBi danio;
  final TextoBi etapa;
  final TextoBi lugar;
  final TextoBi periodo;

  /// Límite del registro, con las palabras de la investigación.
  final TextoBi limite;
  final List<ReferenciaPlaga> referencias;
}

/// De dónde sale una plaga de la lista.
enum OrigenPlaga {
  /// Registro local documentado por la investigación del equipo.
  investigacion,

  /// Lo nombró un caficultor; no es un registro con fuente.
  caficultor,

  /// La opción "Otra".
  otra,
}

/// Una plaga o enfermedad que el productor puede elegir, con su nombre en
/// español e inglés y, si viene de la investigación, sus registros.
class TipoPlaga {
  const TipoPlaga(
    this.id,
    this.es,
    this.en, {
    this.origen = OrigenPlaga.investigacion,
    this.registros = const [],
  });

  final String id;
  final String es;
  final String en;
  final OrigenPlaga origen;

  /// Un registro por taxón documentado bajo este nombre común.
  final List<RegistroPlaga> registros;
}

const otraPlaga = TipoPlaga('otra', 'Otra', 'Other', origen: OrigenPlaga.otra);
