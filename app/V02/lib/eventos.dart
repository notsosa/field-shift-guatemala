/// Bitácora declarada; una fecha desconocida nunca se convierte en la de hoy.
library;

enum TipoEvento {
  cosecha,
  perdida,
  plaga,
  tratamiento,
  fertilizacion,
  observacion,
}

enum Observacion { sombra, humedadSuelo, vecinos }

enum ReferenciaPerdida { superficie, produccionEsperada, yaCosechado }

String fechaIso(DateTime f) => f.toIso8601String().substring(0, 10);

class Evento {
  const Evento({
    required this.id,
    required this.campaniaId,
    required this.loteId,
    required this.tipo,
    this.fecha,
    this.desde,
    this.hasta,
    this.cantidad,
    this.unidad,
    this.referencia,
    this.producto = '',
    this.severidad,
    this.observacion,
    this.profundidadCm,
    this.metodo = '',
    this.especieVecina = '',
    this.distanciaM,
    this.nota = '',
    this.origen = 'declarado',
  });
  final String id,
      campaniaId,
      loteId,
      producto,
      metodo,
      especieVecina,
      nota,
      origen;
  final TipoEvento tipo;
  final DateTime? fecha, desde, hasta;
  final double? cantidad, profundidadCm, distanciaM;
  final String? unidad, referencia, severidad;
  final Observacion? observacion;
  bool get derivado => origen != 'declarado';
  double? get kilos => tipo != TipoEvento.cosecha || cantidad == null
      ? null
      : switch (unidad) {
          'kg' => cantidad,
          'g' => cantidad! / 1000,
          't' => cantidad! * 1000,
          _ => null,
        };
  DateTime? get orden => fecha ?? hasta;
  Map<String, dynamic> aJson() => {
    'id': id,
    'campania': campaniaId,
    'lote': loteId,
    'tipo': tipo.name,
    'fecha': fecha == null ? null : fechaIso(fecha!),
    'desde': desde == null ? null : fechaIso(desde!),
    'hasta': hasta == null ? null : fechaIso(hasta!),
    'cantidad': cantidad,
    'unidad': unidad,
    'referencia': referencia,
    'producto': producto,
    'severidad': severidad,
    'observacion': observacion?.name,
    'profundidadCm': profundidadCm,
    'metodo': metodo,
    'especieVecina': especieVecina,
    'distanciaM': distanciaM,
    'nota': nota,
    'origen': origen,
  };
  factory Evento.deJson(Map<String, dynamic> j) {
    DateTime? f(String k) =>
        j[k] == null ? null : DateTime.parse(j[k] as String);
    double? n(String k) => (j[k] as num?)?.toDouble();
    return Evento(
      id: j['id'] as String,
      campaniaId: j['campania'] as String,
      loteId: j['lote'] as String,
      tipo: TipoEvento.values.byName(j['tipo'] as String),
      fecha: f('fecha'),
      desde: f('desde'),
      hasta: f('hasta'),
      cantidad: n('cantidad'),
      unidad: j['unidad'] as String?,
      referencia: j['referencia'] as String?,
      producto: j['producto'] as String? ?? '',
      severidad: j['severidad'] as String?,
      observacion: j['observacion'] == null
          ? null
          : Observacion.values.byName(j['observacion'] as String),
      profundidadCm: n('profundidadCm'),
      metodo: j['metodo'] as String? ?? '',
      especieVecina: j['especieVecina'] as String? ?? '',
      distanciaM: n('distanciaM'),
      nota: j['nota'] as String? ?? '',
      origen: j['origen'] as String? ?? 'declarado',
    );
  }
}
