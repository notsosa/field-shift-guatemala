/// Motor de cálculo: evapotranspiración de referencia y balance diario de agua
/// en la zona de raíces, según FAO-56 (Allen et al., 1998).
///
/// Es Dart puro, sin dependencias de Flutter, para poder probarlo aparte.
library;

import 'dart:math' as math;

/// Presión de vapor de saturación en kPa (FAO-56 ec. 11).
double presionSaturacion(double t) => 0.6108 * math.exp(17.27 * t / (t + 237.3));

/// ET₀ diaria en mm por Penman-Monteith (FAO-56 ec. 6).
///
/// [rs] es la radiación solar en MJ/m²/día, [ea] la presión de vapor real en
/// kPa y [u2] el viento a 2 m en m/s.
double et0PenmanMonteith({
  required double tmax,
  required double tmin,
  required double ea,
  required double u2,
  required double rs,
  required int diaDelAnio,
  required double latitud,
  required double elevacion,
}) {
  final tmed = (tmax + tmin) / 2;
  final es = (presionSaturacion(tmax) + presionSaturacion(tmin)) / 2;
  final delta = 4098 * presionSaturacion(tmed) / math.pow(tmed + 237.3, 2);
  final presion = 101.3 * math.pow((293 - 0.0065 * elevacion) / 293, 5.26);
  final gamma = 0.000665 * presion;

  final phi = latitud * math.pi / 180;
  final dr = 1 + 0.033 * math.cos(2 * math.pi * diaDelAnio / 365);
  final decl = 0.409 * math.sin(2 * math.pi * diaDelAnio / 365 - 1.39);
  final ws = math.acos((-math.tan(phi) * math.tan(decl)).clamp(-1.0, 1.0));
  final ra = 24 * 60 / math.pi * 0.0820 * dr *
      (ws * math.sin(phi) * math.sin(decl) + math.cos(phi) * math.cos(decl) * math.sin(ws));
  final rso = (0.75 + 2e-5 * elevacion) * ra;
  final rns = 0.77 * rs;
  final relativa = rso > 0 ? (rs / rso).clamp(0.3, 1.0) : 0.3;
  final rnl = 4.903e-9 *
      (math.pow(tmax + 273.16, 4) + math.pow(tmin + 273.16, 4)) / 2 *
      (0.34 - 0.14 * math.sqrt(math.max(ea, 0))) *
      (1.35 * relativa - 0.35);
  final rn = rns - rnl;
  final et0 = (0.408 * delta * rn + gamma * 900 / (tmed + 273) * u2 * (es - ea)) /
      (delta + gamma * (1 + 0.34 * u2));
  return math.max(et0, 0);
}

/// Día del año, de 1 a 366.
int diaDelAnio(DateTime f) => f.difference(DateTime(f.year)).inDays + 1;

/// Un día de clima ya convertido a lo que necesita el balance.
class DiaAgua {
  const DiaAgua({required this.fecha, required this.et0, required this.lluvia, this.estimado = false});

  final DateTime fecha;

  /// Evapotranspiración de referencia, mm.
  final double et0;

  /// Lluvia, mm.
  final double lluvia;

  /// Verdadero si no hay dato observado y se completó con un promedio.
  final bool estimado;
}

/// Parámetros de un cultivo. Kc, raíz y p vienen de FAO-56 (tablas 12 y 22);
/// la proporción de etapas, de la tabla 11; Ky, de FAO-33.
class ParametrosCultivo {
  const ParametrosCultivo({
    required this.kcInicial,
    required this.kcMedio,
    required this.kcFinal,
    required this.etapas,
    required this.raizMaxima,
    required this.p,
    required this.perenne,
    this.ky,
  });

  final double kcInicial;
  final double kcMedio;
  final double kcFinal;

  /// Duración relativa de las cuatro etapas: inicial, desarrollo, media, final.
  final List<double> etapas;

  /// Profundidad máxima de raíces, m.
  final double raizMaxima;

  /// Fracción del agua disponible que el cultivo usa sin estrés.
  final double p;

  /// Cultivo establecido (café): Kc y raíz constantes, sin fecha de cosecha.
  final bool perenne;

  /// Factor de respuesta del rendimiento al agua (FAO-33). Nulo si no aplica.
  final double? ky;
}

/// Etapa del cultivo en un día dado.
enum Etapa { inicial, desarrollo, media, finalCiclo, cosechado, establecido }

/// Estado del agua en un día de la simulación.
class EstadoDia {
  const EstadoDia({
    required this.fecha,
    required this.etapa,
    required this.kc,
    required this.etc,
    required this.eta,
    required this.ks,
    required this.agotamiento,
    required this.aguaTotal,
    required this.aguaFacil,
    required this.lluvia,
    required this.riego,
    required this.estimado,
    this.escorrentia = 0,
    this.drenaje = 0,
    this.agotamientoSubsuelo = 0,
  });

  final DateTime fecha;
  final Etapa etapa;
  final double kc;

  /// Agua que el cultivo necesita ese día, mm.
  final double etc;

  /// Agua que el cultivo logró usar, mm.
  final double eta;

  /// Coeficiente de estrés: 1 sin estrés, 0 marchitez.
  final double ks;

  /// Agua que falta para volver a capacidad de campo, mm.
  final double agotamiento;

  /// Agua disponible total en la zona de raíces (TAW), mm.
  final double aguaTotal;

  /// Agua fácilmente aprovechable (RAW), mm.
  final double aguaFacil;

  final double lluvia;
  final double riego;
  final bool estimado;

  /// Lluvia que escurre por la superficie, mm.
  final double escorrentia;

  /// Agua que pasa por debajo de todo el perfil de raíces posible (drenaje
  /// profundo, se pierde), mm.
  final double drenaje;

  /// Agua que falta en el suelo por debajo de las raíces actuales, hasta la
  /// profundidad máxima de raíces, mm.
  final double agotamientoSubsuelo;

  /// Fracción del agua disponible que queda, de 0 a 1.
  double get reserva => aguaTotal <= 0 ? 0 : (1 - agotamiento / aguaTotal).clamp(0.0, 1.0);
}

const double _raizMinima = 0.20;

/// Balance diario de agua en la zona de raíces (FAO-56 ecs. 82 a 85).
///
/// [dias] debe venir ordenado y sin huecos. [riegos] es agua aplicada en mm por
/// fecha. [aguaDisponible] es el agua disponible del suelo en mm por metro,
/// [numeroCurva] el número de curva SCS para la escorrentía y
/// [agotamientoInicial] la fracción del agua disponible ya gastada al empezar.
List<EstadoDia> simularBalance({
  required List<DiaAgua> dias,
  required DateTime siembra,
  required ParametrosCultivo cultivo,
  required int ciclo,
  required double aguaDisponible,
  Map<DateTime, double> riegos = const {},
  double numeroCurva = 78,
  double agotamientoInicial = 0.5,
}) {
  final total = cultivo.etapas.fold<double>(0, (a, b) => a + b);
  final f1 = cultivo.etapas[0] / total * ciclo;
  final f2 = f1 + cultivo.etapas[1] / total * ciclo;
  final f3 = f2 + cultivo.etapas[2] / total * ciclo;
  final s = 25400 / numeroCurva - 254;

  final salida = <EstadoDia>[];
  // Agotamiento de la zona de raíces y del suelo por debajo de ella, hasta la
  // profundidad máxima de raíces. El subsuelo guarda su propia agua: recibe lo
  // que drena de la zona de raíces y no pierde nada más; cuando la raíz crece,
  // la capa nueva entra con el agotamiento que el subsuelo tenía en ese grosor.
  double? agotado;
  var agotadoSub = 0.0;
  var tawPrevio = 0.0;
  final tawMaximo = aguaDisponible * cultivo.raizMaxima;

  for (final d in dias) {
    final t = _soloFecha(d.fecha).difference(_soloFecha(siembra)).inDays;
    if (!cultivo.perenne && t < 0) continue;

    final Etapa etapa;
    final double kc;
    final double zr;
    if (cultivo.perenne) {
      etapa = Etapa.establecido;
      kc = cultivo.kcMedio;
      zr = cultivo.raizMaxima;
    } else if (t >= ciclo) {
      etapa = Etapa.cosechado;
      kc = cultivo.kcFinal;
      zr = cultivo.raizMaxima;
    } else {
      zr = _raizMinima + (cultivo.raizMaxima - _raizMinima) * (t / f2).clamp(0.0, 1.0);
      if (t < f1) {
        etapa = Etapa.inicial;
        kc = cultivo.kcInicial;
      } else if (t < f2) {
        etapa = Etapa.desarrollo;
        kc = cultivo.kcInicial + (cultivo.kcMedio - cultivo.kcInicial) * (t - f1) / (f2 - f1);
      } else if (t < f3) {
        etapa = Etapa.media;
        kc = cultivo.kcMedio;
      } else {
        etapa = Etapa.finalCiclo;
        kc = cultivo.kcMedio + (cultivo.kcFinal - cultivo.kcMedio) * (t - f3) / math.max(ciclo - f3, 1);
      }
    }

    final taw = aguaDisponible * zr;
    if (agotado == null) {
      agotado = agotamientoInicial * taw;
      agotadoSub = agotamientoInicial * (tawMaximo - taw);
    } else if (taw > tawPrevio) {
      final capaPrevia = tawMaximo - tawPrevio;
      final aporte = capaPrevia > 0 ? agotadoSub * (taw - tawPrevio) / capaPrevia : 0.0;
      agotado += aporte;
      agotadoSub -= aporte;
    }
    tawPrevio = taw;

    final raw = cultivo.p * taw;
    final ks = agotado <= raw ? 1.0 : ((taw - agotado) / (taw - raw)).clamp(0.0, 1.0);
    final etc = kc * d.et0;
    final escorrentia =
        d.lluvia > 0.2 * s ? math.pow(d.lluvia - 0.2 * s, 2) / (d.lluvia + 0.8 * s) : 0.0;
    final riego = riegos[_soloFecha(d.fecha)] ?? 0.0;
    // Lo que sobra sobre capacidad de campo baja al subsuelo; si este también
    // se llena, el resto es drenaje profundo.
    final balance = agotado - (d.lluvia - escorrentia) - riego;
    final exceso = balance < 0 ? -balance : 0.0;
    final alSubsuelo = math.min(exceso, agotadoSub);
    agotadoSub -= alSubsuelo;
    final drenaje = exceso - alSubsuelo;
    final antes = balance < 0 ? 0.0 : balance;
    // El cultivo no puede sacar más agua de la que cabe en la zona de raíces.
    final eta = etapa == Etapa.cosechado ? 0.0 : math.min(ks * etc, taw - antes);
    agotado = antes + eta;

    salida.add(EstadoDia(
      fecha: d.fecha,
      etapa: etapa,
      kc: kc,
      etc: etc,
      eta: eta,
      ks: ks,
      agotamiento: agotado,
      aguaTotal: taw,
      aguaFacil: raw,
      lluvia: d.lluvia,
      riego: riego,
      estimado: d.estimado,
      escorrentia: escorrentia,
      drenaje: drenaje,
      agotamientoSubsuelo: agotadoSub,
    ));
  }
  return salida;
}

/// Factor de rendimiento por agua de FAO-33: 1 − Ky · (1 − ETa/ETc).
double? factorRendimiento(List<EstadoDia> dias, double? ky) {
  if (ky == null || dias.isEmpty) return null;
  final etc = dias.fold<double>(0, (a, d) => a + d.etc);
  final eta = dias.fold<double>(0, (a, d) => a + d.eta);
  if (etc <= 0) return null;
  return (1 - ky * (1 - eta / etc)).clamp(0.0, 1.0);
}

DateTime _soloFecha(DateTime f) => DateTime(f.year, f.month, f.day);
