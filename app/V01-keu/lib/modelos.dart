/// Datos que guarda la app: parcela, plantación, registros semanales y clima.
library;

import 'motor/fao56.dart';

export 'plagas.dart';
export 'plagas_tipos.dart';

DateTime soloFecha(DateTime f) => DateTime(f.year, f.month, f.day);

String _iso(DateTime f) =>
    '${f.year.toString().padLeft(4, '0')}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

DateTime _deIso(String s) => DateTime.parse(s);

/// Punto fijado por el usuario para su parcela.
class Parcela {
  const Parcela({required this.nombre, required this.latitud, required this.longitud, this.elevacion});

  final String nombre;
  final double latitud;
  final double longitud;

  /// Metros sobre el nivel del mar; la entrega NASA POWER al sincronizar.
  final double? elevacion;

  Parcela con({double? elevacion}) =>
      Parcela(nombre: nombre, latitud: latitud, longitud: longitud, elevacion: elevacion ?? this.elevacion);

  Map<String, dynamic> aJson() =>
      {'nombre': nombre, 'latitud': latitud, 'longitud': longitud, 'elevacion': elevacion};

  factory Parcela.deJson(Map<String, dynamic> j) => Parcela(
        nombre: j['nombre'] as String,
        latitud: (j['latitud'] as num).toDouble(),
        longitud: (j['longitud'] as num).toDouble(),
        elevacion: (j['elevacion'] as num?)?.toDouble(),
      );
}

/// Cómo llega el agua al cultivo. Los mm por riego son supuestos de trabajo
/// para convertir "regué una vez" en lámina de agua; no son mediciones.
enum TipoRiego {
  ninguno(0),
  manual(4),
  goteo(6),
  aspersion(12),
  gravedad(30);

  const TipoRiego(this.mmPorRiego);
  final double mmPorRiego;
}

/// Cuándo riega el productor.
enum TemporadaRiego { todoElAnio, epocaSeca, auxilio }

/// Textura del suelo y su agua disponible en mm por metro (FAO-56, tabla 19).
enum Suelo {
  arenoso(100),
  franco(150),
  arcilloso(180);

  const Suelo(this.aguaDisponible);
  final double aguaDisponible;
}

/// Cultivo del catálogo. Los parámetros de agua son referencias publicadas.
class Cultivo {
  const Cultivo({required this.id, required this.ciclos, required this.parametros});

  final String id;

  /// Duraciones de ciclo ofrecidas, en días de siembra a cosecha.
  final List<int> ciclos;
  final ParametrosCultivo parametros;

  bool get perenne => parametros.perenne;
}

/// Catálogo. Maíz y frijol salen de `datos/cultivos/maiz_frijol.json` del
/// repositorio del equipo (FAO-56 e ICTA). Ajonjolí, papa, cebolla, brócoli y
/// lechuga salen de `web/data/crops.json` (rama modelo-keu); los valores que ahí
/// están marcados como proxy se indican en cada cultivo. Café y tomate usan
/// valores de FAO-56 citados de memoria: verificar antes de publicar.
const catalogo = <Cultivo>[
  Cultivo(
    id: 'maiz',
    ciclos: [90, 120],
    parametros: ParametrosCultivo(
      kcInicial: 0.30, kcMedio: 1.20, kcFinal: 0.35,
      etapas: [20, 35, 40, 30], raizMaxima: 1.0, p: 0.55, perenne: false, ky: 1.25,
    ),
  ),
  Cultivo(
    id: 'frijol',
    ciclos: [67, 80, 90],
    parametros: ParametrosCultivo(
      kcInicial: 0.40, kcMedio: 1.15, kcFinal: 0.35,
      etapas: [15, 25, 35, 20], raizMaxima: 0.6, p: 0.45, perenne: false, ky: 1.15,
    ),
  ),
  // Ajonjolí: FAO-56 (Kc, raíz, p) y etapas de la tabla 11 ajustadas a tierras bajas (web/data/crops.json). PROXY: Ky (se usa 1.0).
  Cultivo(
    id: 'ajonjoli',
    ciclos: [110],
    parametros: ParametrosCultivo(
      kcInicial: 0.35, kcMedio: 1.1, kcFinal: 0.25,
      etapas: [20, 30, 40, 20], raizMaxima: 1.0, p: 0.6, perenne: false, ky: 1.0,
    ),
  ),
  // Papa: FAO-56 con los valores auditados del equipo (commit a0d0690); ciclo de referencia de 115 días. Sin proxies en estos valores (el de la web es la temperatura base, que la app no usa).
  Cultivo(
    id: 'papa',
    ciclos: [115],
    parametros: ParametrosCultivo(
      kcInicial: 0.5, kcMedio: 1.15, kcFinal: 0.75,
      etapas: [25, 30, 30, 30], raizMaxima: 0.5, p: 0.35, perenne: false, ky: 1.1,
    ),
  ),
  // Cebolla: FAO-56 con los valores auditados del equipo (commit a0d0690); ciclo de referencia de 150 días (bulbo seco). Sin proxies en estos valores.
  Cultivo(
    id: 'cebolla',
    ciclos: [150],
    parametros: ParametrosCultivo(
      kcInicial: 0.7, kcMedio: 1.05, kcFinal: 0.75,
      etapas: [15, 25, 70, 40], raizMaxima: 0.5, p: 0.3, perenne: false, ky: 1.1,
    ),
  ),
  // Brócoli: FAO-56 con los valores auditados del equipo (commit a0d0690); ciclo FAO de 135 días. PROXY: Ky.
  Cultivo(
    id: 'brocoli',
    ciclos: [135],
    parametros: ParametrosCultivo(
      kcInicial: 0.7, kcMedio: 1.05, kcFinal: 0.95,
      etapas: [35, 45, 40, 15], raizMaxima: 0.5, p: 0.45, perenne: false, ky: 0.95,
    ),
  ),
  // Lechuga: FAO-56 con los valores auditados del equipo (commit a0d0690); ciclo de referencia de 75 días. PROXY: Ky.
  Cultivo(
    id: 'lechuga',
    ciclos: [75],
    parametros: ParametrosCultivo(
      kcInicial: 0.7, kcMedio: 1.0, kcFinal: 0.95,
      etapas: [20, 30, 15, 10], raizMaxima: 0.4, p: 0.3, perenne: false, ky: 1.0,
    ),
  ),
  Cultivo(
    id: 'tomate',
    ciclos: [120, 145],
    parametros: ParametrosCultivo(
      kcInicial: 0.60, kcMedio: 1.15, kcFinal: 0.80,
      etapas: [30, 40, 45, 30], raizMaxima: 1.0, p: 0.40, perenne: false, ky: 1.05,
    ),
  ),
  Cultivo(
    id: 'cafe',
    ciclos: [365],
    parametros: ParametrosCultivo(
      kcInicial: 0.95, kcMedio: 0.95, kcFinal: 0.95,
      etapas: [1, 1, 1, 1], raizMaxima: 1.0, p: 0.40, perenne: true,
    ),
  ),
];

Cultivo cultivoPorId(String id) => catalogo.firstWhere((c) => c.id == id, orElse: () => catalogo.first);

/// Información de la plantación que el usuario da al configurar la app.
class Plantacion {
  const Plantacion({
    required this.cultivoId,
    required this.fecha,
    required this.ciclo,
    required this.suelo,
    required this.riego,
    required this.temporadaRiego,
    required this.plagaReciente,
    required this.fertilizo,
    this.notaPlaga = '',
    this.tipoPlaga = '',
  });

  final String cultivoId;

  /// Fecha de siembra, o de la última floración si el cultivo es fijo.
  final DateTime fecha;
  final int ciclo;
  final Suelo suelo;
  final TipoRiego riego;
  final TemporadaRiego temporadaRiego;
  final bool plagaReciente;
  final String notaPlaga;

  /// Tipo de plaga elegido de [tiposPlaga]; vacío si no hay plaga o no se eligió.
  final String tipoPlaga;
  final bool fertilizo;

  Cultivo get cultivo => cultivoPorId(cultivoId);

  Map<String, dynamic> aJson() => {
        'cultivo': cultivoId,
        'fecha': _iso(fecha),
        'ciclo': ciclo,
        'suelo': suelo.name,
        'riego': riego.name,
        'temporadaRiego': temporadaRiego.name,
        'plagaReciente': plagaReciente,
        'notaPlaga': notaPlaga,
        'tipoPlaga': tipoPlaga,
        'fertilizo': fertilizo,
      };

  factory Plantacion.deJson(Map<String, dynamic> j) => Plantacion(
        cultivoId: j['cultivo'] as String,
        fecha: _deIso(j['fecha'] as String),
        ciclo: (j['ciclo'] as num).toInt(),
        suelo: Suelo.values.byName(j['suelo'] as String),
        riego: TipoRiego.values.byName(j['riego'] as String),
        temporadaRiego: TemporadaRiego.values.byName(j['temporadaRiego'] as String),
        plagaReciente: j['plagaReciente'] as bool? ?? false,
        notaPlaga: j['notaPlaga'] as String? ?? '',
        tipoPlaga: j['tipoPlaga'] as String? ?? '',
        fertilizo: j['fertilizo'] as bool? ?? false,
      );
}

/// Qué tanto daño ve el productor.
enum NivelPlaga { ninguna, leve, moderada, fuerte }

/// Registro semanal: riego, plaga y fertilizante de los últimos siete días.
class RegistroSemanal {
  const RegistroSemanal({
    required this.fecha,
    required this.riegos,
    required this.plaga,
    required this.fertilizo,
    this.notaPlaga = '',
    this.tipoPlaga = '',
    this.notaFertilizante = '',
  });

  /// Día en que se llenó; cubre los siete días anteriores.
  final DateTime fecha;

  /// Cuántas veces regó en la semana.
  final int riegos;
  final NivelPlaga plaga;
  final String notaPlaga;

  /// Tipo de plaga elegido de [tiposPlaga]; vacío si no hubo plaga o no se eligió.
  final String tipoPlaga;
  final bool fertilizo;
  final String notaFertilizante;

  Map<String, dynamic> aJson() => {
        'fecha': _iso(fecha),
        'riegos': riegos,
        'plaga': plaga.name,
        'notaPlaga': notaPlaga,
        'tipoPlaga': tipoPlaga,
        'fertilizo': fertilizo,
        'notaFertilizante': notaFertilizante,
      };

  factory RegistroSemanal.deJson(Map<String, dynamic> j) => RegistroSemanal(
        fecha: _deIso(j['fecha'] as String),
        riegos: (j['riegos'] as num).toInt(),
        plaga: NivelPlaga.values.byName(j['plaga'] as String),
        notaPlaga: j['notaPlaga'] as String? ?? '',
        tipoPlaga: j['tipoPlaga'] as String? ?? '',
        fertilizo: j['fertilizo'] as bool? ?? false,
        notaFertilizante: j['notaFertilizante'] as String? ?? '',
      );
}

/// Un día de clima tal como llega de NASA POWER.
class DiaClima {
  const DiaClima({
    required this.fecha,
    required this.tmax,
    required this.tmin,
    required this.humedad,
    required this.viento,
    required this.radiacion,
    required this.lluvia,
  });

  final DateTime fecha;
  final double? tmax;
  final double? tmin;

  /// Humedad relativa media, %.
  final double? humedad;

  /// Viento a 2 m, m/s.
  final double? viento;

  /// Radiación solar, MJ/m²/día.
  final double? radiacion;

  /// Lluvia, mm.
  final double? lluvia;

  bool get completo =>
      tmax != null && tmin != null && humedad != null && viento != null && radiacion != null;

  Map<String, dynamic> aJson() => {
        'f': _iso(fecha),
        'x': tmax,
        'n': tmin,
        'h': humedad,
        'v': viento,
        'r': radiacion,
        'l': lluvia,
      };

  factory DiaClima.deJson(Map<String, dynamic> j) => DiaClima(
        fecha: _deIso(j['f'] as String),
        tmax: (j['x'] as num?)?.toDouble(),
        tmin: (j['n'] as num?)?.toDouble(),
        humedad: (j['h'] as num?)?.toDouble(),
        viento: (j['v'] as num?)?.toDouble(),
        radiacion: (j['r'] as num?)?.toDouble(),
        lluvia: (j['l'] as num?)?.toDouble(),
      );
}
