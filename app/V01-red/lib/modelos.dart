/// Datos que guarda la app: parcela, plantación, registros semanales y clima.
library;

import 'motor/fao56.dart';

DateTime soloFecha(DateTime f) => DateTime(f.year, f.month, f.day);

String _iso(DateTime f) =>
    '${f.year.toString().padLeft(4, '0')}-${f.month.toString().padLeft(2, '0')}-${f.day.toString().padLeft(2, '0')}';

DateTime _deIso(String s) => DateTime.parse(s);

/// Unidades para áreas y para la escala del plano. En Guatemala el productor
/// suele medir en manzanas (1 mz = 6 989 m²).
enum Unidad { manzanas, metrico }

/// Metros cuadrados de una manzana.
const metrosPorManzana = 6989.0;

/// Tamaños del plano de la finca que se ofrecen, como ancho en metros. En
/// manzanas son cuadrados de 10, 50, 200, 1 000, 5 000 y 20 000 mz; en métrico,
/// anchos de 200 m a 10 km.
List<double> ladosDe(Unidad u) => switch (u) {
      Unidad.metrico => const [200, 500, 1000, 2000, 5000, 10000],
      Unidad.manzanas => const [
          264.36717, // 10 mz
          591.14296, // 50 mz
          1182.28592, // 200 mz
          2643.67169, // 1 000 mz
          5911.42961, // 5 000 mz
          11822.85921, // 20 000 mz
        ],
    };

/// Punto del plano de la finca, en fracciones de 0 a 1 del lienzo cuadrado. El
/// lienzo representa un cuadrado de `Parcela.lado` metros centrado en el punto
/// de la finca, con el norte arriba.
class Punto {
  const Punto(this.x, this.y);

  final double x;
  final double y;

  List<double> aJson() => [x, y];
}

List<Punto> _puntos(dynamic j) => j == null
    ? const []
    : [for (final p in j as List<dynamic>) Punto(((p as List<dynamic>)[0] as num).toDouble(), (p[1] as num).toDouble())];

/// Centro de un contorno, para colocar el marcador.
Punto centroDe(List<Punto> c) {
  if (c.isEmpty) return const Punto(0.5, 0.5);
  var x = 0.0, y = 0.0;
  for (final p in c) {
    x += p.x;
    y += p.y;
  }
  return Punto(x / c.length, y / c.length);
}

/// Área de un contorno en metros cuadrados, para un lienzo de [lado] metros.
double areaDe(List<Punto> c, double lado) {
  if (c.length < 3) return 0;
  var suma = 0.0;
  for (var i = 0, j = c.length - 1; i < c.length; j = i++) {
    suma += (c[j].x + c[i].x) * (c[j].y - c[i].y);
  }
  return suma.abs() / 2 * lado * lado;
}

/// Contorno ajustado a un cambio del ancho del lienzo, sin moverlo en el terreno.
List<Punto> reescalar(List<Punto> c, double ladoViejo, double ladoNuevo) {
  final f = ladoViejo / ladoNuevo;
  return [for (final p in c) Punto(0.5 + (p.x - 0.5) * f, 0.5 + (p.y - 0.5) * f)];
}

/// Verdadero si el punto cae dentro del contorno (regla par-impar).
bool dentroDe(List<Punto> c, Punto p) {
  var dentro = false;
  for (var i = 0, j = c.length - 1; i < c.length; j = i++) {
    final a = c[i], b = c[j];
    if ((a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x) dentro = !dentro;
  }
  return dentro;
}

/// La finca: el punto fijado por el usuario y, si lo dibujó, su contorno.
class Parcela {
  const Parcela({
    required this.nombre,
    required this.latitud,
    required this.longitud,
    this.elevacion,
    this.contorno = const [],
    this.lado = 500,
  });

  final String nombre;
  final double latitud;
  final double longitud;

  /// Metros sobre el nivel del mar; la entrega NASA POWER al sincronizar.
  final double? elevacion;

  /// Contorno de la finca en el plano. Vacío si no se ha dibujado.
  final List<Punto> contorno;

  /// Ancho en metros del cuadrado que muestra el plano de la finca.
  final double lado;

  Parcela con({double? elevacion, List<Punto>? contorno, double? lado}) => Parcela(
        nombre: nombre,
        latitud: latitud,
        longitud: longitud,
        elevacion: elevacion ?? this.elevacion,
        contorno: contorno ?? this.contorno,
        lado: lado ?? this.lado,
      );

  Map<String, dynamic> aJson() => {
        'nombre': nombre,
        'latitud': latitud,
        'longitud': longitud,
        'elevacion': elevacion,
        'contorno': [for (final p in contorno) p.aJson()],
        'lado': lado,
      };

  factory Parcela.deJson(Map<String, dynamic> j) => Parcela(
        nombre: j['nombre'] as String,
        latitud: (j['latitud'] as num).toDouble(),
        longitud: (j['longitud'] as num).toDouble(),
        elevacion: (j['elevacion'] as num?)?.toDouble(),
        contorno: _puntos(j['contorno']),
        lado: (j['lado'] as num?)?.toDouble() ?? 500,
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

/// Catálogo inicial. Maíz y frijol salen de `datos/cultivos/maiz_frijol.json`
/// del repositorio del equipo (FAO-56 e ICTA). Café y tomate usan valores de
/// FAO-56 citados de memoria: verificar antes de publicar.
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

/// Sombra del cafetal. Solo se pregunta para café y solo la usa la red de riego
/// del café (`motor/cafe.dart`).
enum Sombra { ninguna, arbolesPerennes, arbolesCaducos, banano }

/// Parte del terreno cubierta por la copa del banano: «poco». Son los dos únicos
/// valores con que se entrenó la red del café (0.15 y 0.30 son convenciones de
/// los escenarios del equipo, no medidas); por eso el formulario no deja
/// escribir otro número.
const coberturaBananoPoco = 0.15;

/// Parte del terreno cubierta por la copa del banano: «bastante». Ver [coberturaBananoPoco].
const coberturaBananoBastante = 0.30;

/// Qué pesa más para quien riega el café. El «precio» es lo que cuesta regar,
/// en días de estrés que el riego tiene que evitar para valer la pena
/// (convención de la red del equipo).
enum PrioridadRiego {
  ahorrarAgua(3),
  protegerCultivo(1);

  const PrioridadRiego(this.precio);
  final int precio;
}

/// Una plantación de la finca. Puede haber varias, cada una con su perímetro
/// en el croquis, sus registros semanales y su recomendación.
class Plantacion {
  const Plantacion({
    this.id = '',
    this.nombre = '',
    this.contorno = const [],
    required this.cultivoId,
    required this.fecha,
    required this.ciclo,
    required this.suelo,
    required this.riego,
    required this.temporadaRiego,
    required this.plagaReciente,
    required this.fertilizo,
    this.notaPlaga = '',
    this.inicioPlaga,
    this.nivelPlaga = NivelPlaga.leve,
    this.plagaTratada = false,
    this.tratamientoPlaga = '',
    this.tipoFertilizante = TipoFertilizante.quimico,
    this.notaFertilizante = '',
    this.fechaFertilizante,
    this.sombra = Sombra.ninguna,
    this.coberturaBanano = coberturaBananoPoco,
    this.prioridadRiego = PrioridadRiego.ahorrarAgua,
  });

  /// Identificador dentro de la finca. Vacío hasta que se guarda.
  final String id;

  /// Nombre que le da el productor, por ejemplo «Lote norte». Opcional.
  final String nombre;

  /// Perímetro en el croquis de la finca. Vacío si no se ha dibujado.
  final List<Punto> contorno;

  final String cultivoId;

  /// Fecha de siembra, o de la última floración si el cultivo es fijo.
  final DateTime fecha;
  final int ciclo;
  final Suelo suelo;
  final TipoRiego riego;
  final TemporadaRiego temporadaRiego;

  // Plaga reciente al registrar la plantación. Los detalles solo cuentan si
  // [plagaReciente] es verdadero.
  final bool plagaReciente;

  /// Qué plaga es, en palabras del productor.
  final String notaPlaga;
  final DateTime? inicioPlaga;
  final NivelPlaga nivelPlaga;
  final bool plagaTratada;

  /// Con qué la trató.
  final String tratamientoPlaga;

  // Fertilización al registrar la plantación. Los detalles solo cuentan si
  // [fertilizo] es verdadero.
  final bool fertilizo;
  final TipoFertilizante tipoFertilizante;

  /// Producto aplicado.
  final String notaFertilizante;
  final DateTime? fechaFertilizante;

  // Solo café (`cultivo.perenne`). En los otros cultivos se guardan los valores
  // por omisión y nada los lee.

  /// Sombra del cafetal.
  final Sombra sombra;

  /// Parte del terreno cubierta por banano: [coberturaBananoPoco] o
  /// [coberturaBananoBastante]. Solo cuenta si [sombra] es banano.
  final double coberturaBanano;

  /// Prioridad de quien riega; fija el precio de regar en la red del café.
  final PrioridadRiego prioridadRiego;

  Cultivo get cultivo => cultivoPorId(cultivoId);

  Plantacion conId(String nuevo) => Plantacion.deJson({...aJson(), 'id': nuevo});

  Plantacion conContorno(List<Punto> nuevo) =>
      Plantacion.deJson({...aJson(), 'contorno': [for (final p in nuevo) p.aJson()]});

  Map<String, dynamic> aJson() => {
        'id': id,
        'nombre': nombre,
        'contorno': [for (final p in contorno) p.aJson()],
        'cultivo': cultivoId,
        'fecha': _iso(fecha),
        'ciclo': ciclo,
        'suelo': suelo.name,
        'riego': riego.name,
        'temporadaRiego': temporadaRiego.name,
        'plagaReciente': plagaReciente,
        'notaPlaga': notaPlaga,
        'inicioPlaga': inicioPlaga == null ? null : _iso(inicioPlaga!),
        'nivelPlaga': nivelPlaga.name,
        'plagaTratada': plagaTratada,
        'tratamientoPlaga': tratamientoPlaga,
        'fertilizo': fertilizo,
        'tipoFertilizante': tipoFertilizante.name,
        'notaFertilizante': notaFertilizante,
        'fechaFertilizante': fechaFertilizante == null ? null : _iso(fechaFertilizante!),
        'sombra': sombra.name,
        'coberturaBanano': coberturaBanano,
        'prioridadRiego': prioridadRiego.name,
      };

  factory Plantacion.deJson(Map<String, dynamic> j) => Plantacion(
        id: j['id'] as String? ?? '',
        nombre: j['nombre'] as String? ?? '',
        contorno: _puntos(j['contorno']),
        cultivoId: j['cultivo'] as String,
        fecha: _deIso(j['fecha'] as String),
        ciclo: (j['ciclo'] as num).toInt(),
        suelo: Suelo.values.byName(j['suelo'] as String),
        riego: TipoRiego.values.byName(j['riego'] as String),
        temporadaRiego: TemporadaRiego.values.byName(j['temporadaRiego'] as String),
        plagaReciente: j['plagaReciente'] as bool? ?? false,
        notaPlaga: j['notaPlaga'] as String? ?? '',
        inicioPlaga: j['inicioPlaga'] == null ? null : _deIso(j['inicioPlaga'] as String),
        nivelPlaga: NivelPlaga.values.byName(j['nivelPlaga'] as String? ?? 'leve'),
        plagaTratada: j['plagaTratada'] as bool? ?? false,
        tratamientoPlaga: j['tratamientoPlaga'] as String? ?? '',
        fertilizo: j['fertilizo'] as bool? ?? false,
        tipoFertilizante: TipoFertilizante.values.byName(j['tipoFertilizante'] as String? ?? 'quimico'),
        notaFertilizante: j['notaFertilizante'] as String? ?? '',
        fechaFertilizante: j['fechaFertilizante'] == null ? null : _deIso(j['fechaFertilizante'] as String),
        // Los datos guardados antes de estos campos no los traen: se usan los valores por omisión.
        sombra: Sombra.values.firstWhere((s) => s.name == j['sombra'], orElse: () => Sombra.ninguna),
        coberturaBanano: (j['coberturaBanano'] as num?)?.toDouble() ?? coberturaBananoPoco,
        prioridadRiego:
            PrioridadRiego.values.firstWhere((p) => p.name == j['prioridadRiego'], orElse: () => PrioridadRiego.ahorrarAgua),
      );
}

/// Qué tanto daño ve el productor.
enum NivelPlaga { ninguna, leve, moderada, fuerte }

/// Clase de fertilizante aplicado.
enum TipoFertilizante { quimico, organico, ambos }

/// Registro semanal: riego, plaga y fertilizante de los últimos siete días.
class RegistroSemanal {
  const RegistroSemanal({
    this.plantacionId = '',
    required this.fecha,
    required this.riegos,
    required this.plaga,
    required this.fertilizo,
    this.notaPlaga = '',
    this.notaFertilizante = '',
  });

  /// Plantación a la que pertenece.
  final String plantacionId;

  /// Día en que se llenó; cubre los siete días anteriores.
  final DateTime fecha;

  RegistroSemanal conPlantacion(String id) => RegistroSemanal.deJson({...aJson(), 'plantacion': id});

  /// Cuántas veces regó en la semana.
  final int riegos;
  final NivelPlaga plaga;
  final String notaPlaga;
  final bool fertilizo;
  final String notaFertilizante;

  Map<String, dynamic> aJson() => {
        'plantacion': plantacionId,
        'fecha': _iso(fecha),
        'riegos': riegos,
        'plaga': plaga.name,
        'notaPlaga': notaPlaga,
        'fertilizo': fertilizo,
        'notaFertilizante': notaFertilizante,
      };

  factory RegistroSemanal.deJson(Map<String, dynamic> j) => RegistroSemanal(
        plantacionId: j['plantacion'] as String? ?? '',
        fecha: _deIso(j['fecha'] as String),
        riegos: (j['riegos'] as num).toInt(),
        plaga: NivelPlaga.values.byName(j['plaga'] as String),
        notaPlaga: j['notaPlaga'] as String? ?? '',
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
