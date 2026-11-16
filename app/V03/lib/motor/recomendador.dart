/// Convierte la parcela, la plantación, el clima guardado y los registros
/// semanales en una recomendación. Es transparente a propósito: balance de agua
/// FAO-56 más reglas simples. Una red neuronal puede sustituir esta función
/// conservando la misma salida.
library;

import '../modelos.dart';
import '../eventos.dart';
import 'cafe.dart';
import 'fao56.dart';

enum NivelAgua { sinDatos, bien, atencion, estres }

enum Aviso {
  registroPendiente,
  climaViejo,
  plaga,
  fertilizar,
  cosechaCerca,
  aguaSinConfirmar,
  sinAgua,
  lluviaFaltante,
  riegoEstimado,
  capacidadLimitada,
  areaPendiente,
}

enum Precision { baja, media, alta }

class Recomendacion {
  const Recomendacion({
    required this.nivel,
    required this.reserva,
    required this.agotamiento,
    required this.riegoSugerido,
    required this.riegosSugeridos,
    required this.etapa,
    required this.diasDesdeSiembra,
    required this.diasACosecha,
    required this.factorRendimiento,
    required this.diasEstres,
    required this.lluviaSemana,
    required this.necesidadSemana,
    required this.ultimos,
    required this.avisos,
    required this.precision,
    required this.ultimoClima,
    required this.diasEstimados,
    this.necesidadRiego = 0,
    this.disponibilidad = DisponibilidadAgua.desconocida,
    this.diasLluviaFaltante = 0,
    this.diasSinLluvia = 0,
    this.humedadTierraPct,
    this.temperaturaActual,
    this.humedadRelativaActual,
    this.lluvia14dMm,
    this.cafeRed,
  });

  final NivelAgua nivel;

  /// Fracción del agua disponible que queda en la zona de raíces, de 0 a 1.
  final double reserva;

  /// Agua que falta para llenar la zona de raíces, mm.
  final double agotamiento;

  /// Lámina sugerida para volver a la zona sin estrés, mm. Cero si no hace
  /// falta o no hay riego.
  final double riegoSugerido;

  /// La misma lámina expresada en riegos del tipo que usa el productor.
  final int riegosSugeridos;

  final Etapa etapa;
  final int? diasDesdeSiembra;
  final int? diasACosecha;

  /// Rendimiento esperado por agua frente al potencial (FAO-33), de 0 a 1.
  final double? factorRendimiento;

  /// Días con estrés hídrico en los últimos siete.
  final int diasEstres;

  /// Lluvia de los últimos siete días, mm: suma solo los días con lluvia
  /// conocida. Es nula si ninguno de los siete tiene dato; [diasSinLluvia]
  /// dice cuántos días quedaron fuera de la suma.
  final double? lluviaSemana;

  /// Días, de los últimos siete, sin lluvia observada (retraso de NASA POWER
  /// o huecos del clima).
  final int diasSinLluvia;
  final double necesidadRiego;
  final DisponibilidadAgua disponibilidad;
  final int diasLluviaFaltante;
  final double? humedadTierraPct;
  final double? temperaturaActual;
  final double? humedadRelativaActual;
  final double? lluvia14dMm;
  final ResultadoCafe? cafeRed;

  /// Agua que el cultivo necesitó en los últimos siete días, mm.
  final double necesidadSemana;

  /// Últimos catorce días simulados, para la gráfica.
  final List<EstadoDia> ultimos;
  final List<Aviso> avisos;
  final Precision precision;

  /// Fecha del último día con clima observado.
  final DateTime? ultimoClima;

  /// Días finales consecutivos, hasta hoy, sin clima observado y completados
  /// con promedios. Es el retraso normal de NASA POWER (3 a 7 días); los
  /// huecos en medio de la temporada no se cuentan aquí.
  final int diasEstimados;

  static const vacia = Recomendacion(
    nivel: NivelAgua.sinDatos,
    reserva: 0,
    agotamiento: 0,
    riegoSugerido: 0,
    riegosSugeridos: 0,
    etapa: Etapa.inicial,
    diasDesdeSiembra: null,
    diasACosecha: null,
    factorRendimiento: null,
    diasEstres: 0,
    lluviaSemana: null,
    necesidadSemana: 0,
    ultimos: [],
    avisos: [Aviso.climaViejo],
    precision: Precision.baja,
    ultimoClima: null,
    diasEstimados: 0,
  );
}

/// Convierte el clima de NASA POWER en ET₀ y lluvia diarias, sin huecos, hasta
/// [hoy]. Los días sin dato observado se completan con el promedio reciente y
/// lluvia cero, y quedan marcados como estimados.
List<DiaAgua> prepararClima(
  List<DiaClima> clima,
  Parcela parcela,
  DateTime hoy,
) {
  final entradas =
      clima.where((d) => !soloFecha(d.fecha).isAfter(soloFecha(hoy))).toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));
  final validos = entradas.where((d) => d.completo).toList();
  if (validos.isEmpty) return [];
  final originales = {for (final d in entradas) soloFecha(d.fecha): d};
  final et0PorFecha = <DateTime, double>{};
  for (final d in validos) {
    final hr = d.humedad!.clamp(1.0, 100.0);
    final ea =
        hr /
        100 *
        (presionSaturacion(d.tmax!) + presionSaturacion(d.tmin!)) /
        2;
    et0PorFecha[soloFecha(d.fecha)] = et0PenmanMonteith(
      tmax: d.tmax!,
      tmin: d.tmin!,
      ea: ea,
      u2: d.viento!,
      rs: d.radiacion!,
      diaDelAnio: diaDelAnio(d.fecha),
      latitud: parcela.latitud,
      elevacion: parcela.elevacion ?? 500,
    );
  }
  final salida = <DiaAgua>[], recientes = <double>[];
  final fin = soloFecha(hoy);
  for (
    var f = soloFecha(entradas.first.fecha);
    !f.isAfter(fin);
    f = DateTime(f.year, f.month, f.day + 1)
  ) {
    final et0 = et0PorFecha[f], lluvia = originales[f]?.lluvia;
    final promedio = recientes.isEmpty
        ? 4.0
        : recientes.reduce((a, b) => a + b) / recientes.length;
    salida.add(
      DiaAgua(
        fecha: f,
        et0: et0 ?? promedio,
        et0Estimada: et0 == null,
        lluvia: lluvia != null && lluvia.isFinite && lluvia >= 0
            ? lluvia
            : null,
      ),
    );
    if (et0 != null) {
      recientes.add(et0);
      if (recientes.length > 7) {
        recientes.removeAt(0);
      }
    }
  }
  return salida;
}

/// Reparte los riegos de cada registro semanal en los siete días anteriores.
Map<DateTime, double> repartirRiegos(
  List<RegistroSemanal> registros,
  TipoRiego tipo,
) {
  final mapa = <DateTime, double>{};
  if (tipo == TipoRiego.ninguno) return mapa;
  for (final r in registros) {
    if (r.riegos <= 0) continue;
    final base = soloFecha(r.fecha);
    for (var k = 0; k < r.riegos; k++) {
      final atras = 1 + (k * 7 / r.riegos).floor();
      final f = DateTime(base.year, base.month, base.day - atras);
      mapa[f] = (mapa[f] ?? 0) + tipo.mmPorRiego;
    }
  }
  return mapa;
}

/// Los días explícitos sustituyen al reparto semanal; no se cuentan dos veces.
({Map<DateTime, double> laminas, Set<DateTime> estimados}) prepararRiegos(
  List<RegistroSemanal> semanales,
  List<RegistroRiego> diarios,
  TipoRiego tipo,
) {
  final laminas = repartirRiegos(semanales, tipo);
  final estimados = laminas.keys.toSet();
  for (final r in diarios) {
    if (r.rego == null) continue;
    final fecha = soloFecha(r.fecha);
    laminas[fecha] = r.rego! ? r.laminaMm ?? tipo.mmPorRiego : 0;
    if (r.rego! && r.laminaMm == null) {
      estimados.add(fecha);
    } else {
      estimados.remove(fecha);
    }
  }
  return (laminas: laminas, estimados: estimados);
}

/// Riegos del tipo dado que equivalen a [mm]. Redondea hacia arriba, salvo
/// que [limitado] indique que el saldo de agua no alcanza: entonces hacia
/// abajo, para no pasarse de lo disponible.
int riegosPara(double mm, TipoRiego tipo, {bool limitado = false}) {
  if (mm <= 0 || tipo.mmPorRiego <= 0) return 0;
  final n = mm / tipo.mmPorRiego;
  // La tolerancia evita que el ruido de coma flotante sume un riego de más.
  return limitado ? (n + 1e-9).floor() : (n - 1e-9).ceil();
}

Recomendacion recomendar({
  required Parcela parcela,
  required Plantacion plantacion,
  required List<DiaClima> clima,
  required List<RegistroSemanal> registros,
  required DateTime hoy,
  DisponibilidadAgua disponibilidad = DisponibilidadAgua.desconocida,
  List<RegistroRiego> riegosDiarios = const [],
  List<Evento> eventos = const [],
}) {
  final dias = prepararClima(clima, parcela, hoy);
  if (dias.isEmpty) return Recomendacion.vacia;

  final cultivo = plantacion.cultivo;
  final riegos = prepararRiegos(registros, riegosDiarios, plantacion.riego);
  final estados = simularBalance(
    dias: dias,
    siembra: plantacion.fecha,
    cultivo: cultivo.parametros,
    ciclo: plantacion.ciclo,
    aguaDisponible: plantacion.suelo.aguaDisponible,
    riegos: riegos.laminas,
    riegosEstimados: riegos.estimados,
  );
  if (estados.isEmpty) return Recomendacion.vacia;

  final actual = estados.last;
  final semana = estados.length > 7
      ? estados.sublist(estados.length - 7)
      : estados;
  final ultimos = estados.length > 14
      ? estados.sublist(estados.length - 14)
      : estados;
  final observados = dias.where((d) => !d.estimado);
  final ultimoClima = observados.isEmpty ? null : observados.last.fecha;
  // NASA POWER publica con 3 a 7 días de retraso: los últimos días hasta hoy
  // no tienen clima observado. Ese hueco final es esperado y se cuenta aparte
  // de los huecos dentro de la temporada observada.
  bool sinDato(EstadoDia d) => d.et0Estimada || d.lluvia == null;
  var diasEstimados = 0;
  for (var i = estados.length - 1; i >= 0 && sinDato(estados[i]); i--) {
    diasEstimados++;
  }
  final observadosHasta = estados.length - diasEstimados;
  final lluviaFaltante = estados.where((d) => d.lluvia == null).length;

  final NivelAgua nivel;
  if (actual.etapa == Etapa.cosechado) {
    nivel = NivelAgua.bien;
  } else if (actual.ks < 1) {
    nivel = NivelAgua.estres;
  } else if (actual.agotamiento > 0.8 * actual.aguaFacil) {
    nivel = NivelAgua.atencion;
  } else {
    nivel = NivelAgua.bien;
  }

  final puedeRegar =
      plantacion.riego != TipoRiego.ninguno &&
      disponibilidad == DisponibilidadAgua.si;
  // Se sugiere lo necesario para dejar el suelo a mitad de la zona sin estrés,
  // no para llenarlo por completo.
  final objetivo = actual.agotamiento - 0.5 * actual.aguaFacil;
  final necesidadRiego = nivel != NivelAgua.bien
      ? (objetivo > 0 ? objetivo : 0.0)
      : 0.0;
  final riegoSugerido = puedeRegar ? necesidadRiego : 0.0;
  final riegosSugeridos = riegosPara(riegoSugerido, plantacion.riego);

  final int? desdeSiembra;
  final int? aCosecha;
  if (cultivo.perenne) {
    desdeSiembra = null;
    aCosecha = null;
  } else {
    desdeSiembra = soloFecha(hoy)
        .difference(soloFecha(plantacion.fecha))
        .inDays;
    aCosecha = plantacion.ciclo - desdeSiembra;
  }

  final ordenados = [...registros]..sort((a, b) => a.fecha.compareTo(b.fecha));
  final ultimoRegistro = ordenados.isEmpty ? null : ordenados.last;
  final diasSinRegistro = ultimoRegistro == null
      ? null
      : soloFecha(hoy).difference(soloFecha(ultimoRegistro.fecha)).inDays;
  final climaViejo =
      ultimoClima == null || soloFecha(hoy).difference(ultimoClima).inDays > 10;

  final avisos = <Aviso>[];
  if (plantacion.riego != TipoRiego.ninguno &&
      disponibilidad == DisponibilidadAgua.desconocida) {
    avisos.add(Aviso.aguaSinConfirmar);
  }
  if (plantacion.riego != TipoRiego.ninguno &&
      disponibilidad == DisponibilidadAgua.no) {
    avisos.add(Aviso.sinAgua);
  }
  if (lluviaFaltante > 0) avisos.add(Aviso.lluviaFaltante);
  if (estados.any((d) => d.riegoEstimado)) avisos.add(Aviso.riegoEstimado);
  if (diasSinRegistro == null || diasSinRegistro >= 7) {
    avisos.add(Aviso.registroPendiente);
  }
  if (climaViejo) avisos.add(Aviso.climaViejo);
  final plagas =
      [
        for (final (i, e) in eventos.indexed)
          if (e.tipo == TipoEvento.plaga &&
              e.fecha != null &&
              !soloFecha(e.fecha!).isAfter(soloFecha(hoy)))
            (i, e),
      ]..sort((a, b) {
        final cmp = soloFecha(b.$2.fecha!).compareTo(soloFecha(a.$2.fecha!));
        return cmp != 0 ? cmp : b.$1.compareTo(a.$1);
      });
  final ultimaPlaga = plagas.isEmpty ? null : plagas.first.$2;
  final plagaActiva =
      ultimaPlaga != null &&
          (ultimoRegistro == null ||
              !ultimaPlaga.fecha!.isBefore(ultimoRegistro.fecha))
      ? ['moderada', 'fuerte'].contains(ultimaPlaga.severidad)
      : ultimoRegistro != null
      ? ultimoRegistro.plaga.index >= NivelPlaga.moderada.index
      // Sin registros aún: cuenta la plaga declarada al registrar la plantación,
      // salvo que ya esté tratada y el daño no sea fuerte.
      : plantacion.plagaReciente &&
            (!plantacion.plagaTratada ||
                plantacion.nivelPlaga == NivelPlaga.fuerte);
  if (plagaActiva) avisos.add(Aviso.plaga);
  final fertilizado =
      plantacion.fertilizo ||
      registros.any((r) => r.fertilizo) ||
      eventos.any(
        (e) =>
            e.tipo == TipoEvento.fertilizacion &&
            e.fecha != null &&
            !e.fecha!.isAfter(hoy),
      );
  if (!cultivo.perenne && actual.etapa == Etapa.desarrollo && !fertilizado) {
    avisos.add(Aviso.fertilizar);
  }
  if (aCosecha != null && aCosecha >= 0 && aCosecha <= 10) {
    avisos.add(Aviso.cosechaCerca);
  }

  // La precisión sube con clima reciente y con registros semanales al día.
  final registrosRecientes = registros
      .where((r) => soloFecha(hoy).difference(soloFecha(r.fecha)).inDays <= 21)
      .length;
  // El hueco final por el retraso de NASA no la baja; sí la baja un clima
  // observado viejo, huecos dentro de la última semana observada y la falta
  // de registros semanales.
  final ventanaObservada = estados.sublist(
    observadosHasta > 7 ? observadosHasta - 7 : 0,
    observadosHasta,
  );
  final huecosRecientes = ventanaObservada.any(sinDato);
  final puntos = huecosRecientes || climaViejo
      ? 0
      : 1 + (registrosRecientes >= 2 ? 1 : 0);

  // El rendimiento cubre hasta el último día con lluvia conocida; si falta
  // algún dato dentro de esa temporada observada, no se muestra.
  final conLluvia = estados.lastIndexWhere((d) => d.lluvia != null);
  final temporada = conLluvia < 0
      ? <EstadoDia>[]
      : estados.sublist(0, conLluvia + 1);
  final rendimiento =
      temporada.isEmpty || temporada.any((d) => d.lluvia == null)
      ? null
      : factorRendimiento(temporada, cultivo.parametros.ky);
  final lluviasSemana = [
    for (final d in semana)
      if (d.lluvia != null) d.lluvia!,
  ];
  final cafeRed = plantacion.cultivoId == cultivoCafe
      ? resultadoCafe(
          parcela: parcela,
          plantacion: plantacion,
          serie: SerieCafe.deClima(dias, clima),
          estados: estados,
          registros: registros,
          riegosDiarios: riegosDiarios,
          climaViejo: climaViejo,
        )
      : null;

  final entradas =
      clima.where((d) => !soloFecha(d.fecha).isAfter(soloFecha(hoy))).toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));
  double? humedadNasa;
  double? tempActual;
  double? hrActual;
  for (final d in entradas) {
    if (d.humedadSueloPct != null) humedadNasa = d.humedadSueloPct;
    final t = d.tmax ?? d.tmedia;
    if (t != null && t.isFinite) tempActual = t;
    if (d.humedad != null && d.humedad!.isFinite) hrActual = d.humedad;
  }
  final humedadTierraPct =
      humedadNasa ?? (15.0 + actual.reserva * 65.0).clamp(8.0, 98.0);
  final lluvia14dMm = ultimos.fold<double>(
    0.0,
    (a, d) => a + (d.lluvia != null && d.lluvia!.isFinite ? d.lluvia! : 0.0),
  );

  return Recomendacion(
    nivel: nivel,
    reserva: actual.reserva,
    agotamiento: actual.agotamiento,
    riegoSugerido: riegoSugerido,
    riegosSugeridos: riegosSugeridos,
    etapa: actual.etapa,
    diasDesdeSiembra: desdeSiembra,
    diasACosecha: aCosecha,
    factorRendimiento: rendimiento,
    diasEstres: semana
        .where((d) => d.ks < 1 && d.etapa != Etapa.cosechado)
        .length,
    lluviaSemana: lluviasSemana.isEmpty
        ? null
        : lluviasSemana.fold<double>(0, (a, v) => a + v),
    diasSinLluvia: semana.length - lluviasSemana.length,
    necesidadSemana: semana.fold(0, (a, d) => a + d.etc),
    ultimos: ultimos,
    avisos: avisos,
    precision: Precision.values[puntos],
    ultimoClima: ultimoClima,
    diasEstimados: diasEstimados,
    necesidadRiego: necesidadRiego,
    disponibilidad: disponibilidad,
    diasLluviaFaltante: lluviaFaltante,
    humedadTierraPct: humedadTierraPct,
    temperaturaActual: tempActual,
    humedadRelativaActual: hrActual,
    lluvia14dMm: lluvia14dMm,
    cafeRed: cafeRed,
  );
}

/// Limita el volumen sugerido, manteniendo visible la necesidad física original.
Recomendacion limitarRiego(
  Recomendacion r,
  double mm,
  TipoRiego tipo, {
  Aviso? aviso,
}) => Recomendacion(
  nivel: r.nivel,
  reserva: r.reserva,
  agotamiento: r.agotamiento,
  riegoSugerido: mm,
  // Si el saldo no limita, el mismo redondeo que `recomendar` (hacia arriba);
  // si limita, hacia abajo para no pasarse del saldo.
  riegosSugeridos: riegosPara(mm, tipo, limitado: mm < r.riegoSugerido - 1e-9),
  etapa: r.etapa,
  diasDesdeSiembra: r.diasDesdeSiembra,
  diasACosecha: r.diasACosecha,
  factorRendimiento: r.factorRendimiento,
  diasEstres: r.diasEstres,
  lluviaSemana: r.lluviaSemana,
  necesidadSemana: r.necesidadSemana,
  ultimos: r.ultimos,
  avisos: [...r.avisos, ?aviso],
  precision: r.precision,
  ultimoClima: r.ultimoClima,
  diasEstimados: r.diasEstimados,
  necesidadRiego: r.necesidadRiego,
  disponibilidad: r.disponibilidad,
  diasLluviaFaltante: r.diasLluviaFaltante,
  diasSinLluvia: r.diasSinLluvia,
  humedadTierraPct: r.humedadTierraPct,
  temperaturaActual: r.temperaturaActual,
  humedadRelativaActual: r.humedadRelativaActual,
  lluvia14dMm: r.lluvia14dMm,
  cafeRed: r.cafeRed,
);
