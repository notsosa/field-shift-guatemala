/// Convierte la parcela, la plantación, el clima guardado y los registros
/// semanales en una recomendación. Es transparente a propósito: balance de agua
/// FAO-56 más reglas simples. Una red neuronal puede sustituir esta función
/// conservando la misma salida.
library;

import 'dart:math' as math;

import '../modelos.dart';
import 'fao56.dart';

enum NivelAgua { sinDatos, bien, atencion, estres }

enum Aviso { registroPendiente, climaViejo, plaga, fertilizar, fertilizarEnEspera, cosechaCerca }

/// Lluvia de la última semana, en mm, desde la cual se considera que llovió
/// para abonar (el productor no fertiliza si no llueve).
const lluviaMinimaParaAbonar = 1.0;

/// Días de retraso de publicación del clima que se consideran normales.
const _retrasoNormalDias = 5;

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
  final double lluviaSemana;

  /// Agua que el cultivo necesitó en los últimos siete días, mm.
  final double necesidadSemana;

  /// Últimos catorce días simulados, para la gráfica.
  final List<EstadoDia> ultimos;
  final List<Aviso> avisos;
  final Precision precision;

  /// Fecha del último día con clima observado.
  final DateTime? ultimoClima;

  /// Días recientes completados con promedios por falta de dato observado.
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
    lluviaSemana: 0,
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
/// quedan marcados como estimados. Un día cuya lluvia falta también es
/// estimado: la lluvia que falta se deja en cero (no se inventa) y se avisa en
/// `diasEstimados` y en la precisión.
List<DiaAgua> prepararClima(List<DiaClima> clima, Parcela parcela, DateTime hoy) {
  final validos = clima.where((d) => d.completo).toList()..sort((a, b) => a.fecha.compareTo(b.fecha));
  if (validos.isEmpty) return [];

  final porFecha = <DateTime, DiaAgua>{};
  for (final d in validos) {
    final hr = d.humedad!.clamp(1.0, 100.0);
    final ea = hr / 100 * (presionSaturacion(d.tmax!) + presionSaturacion(d.tmin!)) / 2; // FAO-56 ec. 19
    final et0 = et0PenmanMonteith(
      tmax: d.tmax!,
      tmin: d.tmin!,
      ea: ea,
      u2: d.viento!,
      rs: d.radiacion!,
      diaDelAnio: diaDelAnio(d.fecha),
      latitud: parcela.latitud,
      elevacion: parcela.elevacion ?? 500,
    );
    porFecha[soloFecha(d.fecha)] =
        DiaAgua(fecha: soloFecha(d.fecha), et0: et0, lluvia: d.lluvia ?? 0, estimado: d.lluvia == null);
  }

  final salida = <DiaAgua>[];
  final recientes = <double>[];
  final fin = soloFecha(hoy);
  for (var f = soloFecha(validos.first.fecha); !f.isAfter(fin); f = DateTime(f.year, f.month, f.day + 1)) {
    final observado = porFecha[f];
    if (observado != null) {
      salida.add(observado);
      recientes.add(observado.et0);
      if (recientes.length > 7) recientes.removeAt(0);
    } else {
      final promedio = recientes.isEmpty ? 4.0 : recientes.reduce((a, b) => a + b) / recientes.length;
      salida.add(DiaAgua(fecha: f, et0: promedio, lluvia: 0, estimado: true));
    }
  }
  return salida;
}

/// Reparte los riegos de cada registro semanal en los siete días anteriores.
Map<DateTime, double> repartirRiegos(List<RegistroSemanal> registros, TipoRiego tipo) {
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

Recomendacion recomendar({
  required Parcela parcela,
  required Plantacion plantacion,
  required List<DiaClima> clima,
  required List<RegistroSemanal> registros,
  required DateTime hoy,
}) {
  final dias = prepararClima(clima, parcela, hoy);
  if (dias.isEmpty) return Recomendacion.vacia;

  final cultivo = plantacion.cultivo;
  final estados = simularBalance(
    dias: dias,
    siembra: plantacion.fecha,
    cultivo: cultivo.parametros,
    ciclo: plantacion.ciclo,
    aguaDisponible: plantacion.suelo.aguaDisponible,
    riegos: repartirRiegos(registros, plantacion.riego),
  );
  if (estados.isEmpty) return Recomendacion.vacia;

  final actual = estados.last;
  final semana = estados.length > 7 ? estados.sublist(estados.length - 7) : estados;
  final ultimos = estados.length > 14 ? estados.sublist(estados.length - 14) : estados;
  final observados = dias.where((d) => !d.estimado);
  final ultimoClima = observados.isEmpty ? null : observados.last.fecha;
  // Días estimados de la ventana reciente (catorce días, o toda la racha final
  // si es más larga).
  final racha = dias.reversed.takeWhile((d) => d.estimado).length;
  final diasEstimados = dias.reversed.take(racha > 14 ? racha : 14).where((d) => d.estimado).length;
  // El retraso normal de publicación de NASA POWER (hasta 5 días tras el último
  // día con clima) no baja la precisión; un hueco dentro de lo observado, una
  // lluvia faltante o un retraso mayor sí.
  final completos = clima.where((d) => d.completo).map((d) => soloFecha(d.fecha));
  final ultimoCompleto = completos.isEmpty ? null : completos.reduce((a, b) => a.isAfter(b) ? a : b);
  final retraso = ultimoCompleto == null ? 0 : soloFecha(hoy).difference(ultimoCompleto).inDays;
  final estimadoEstaSemana = dias.reversed.take(7).any(
      (d) => d.estimado && (retraso > _retrasoNormalDias || ultimoCompleto == null || !d.fecha.isAfter(ultimoCompleto)));

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

  final puedeRegar = plantacion.riego != TipoRiego.ninguno;
  // Se sugiere lo necesario para dejar el suelo a mitad de la zona sin estrés,
  // no para llenarlo por completo.
  final objetivo = actual.agotamiento - 0.5 * actual.aguaFacil;
  final riegoSugerido = puedeRegar && nivel != NivelAgua.bien ? (objetivo > 0 ? objetivo : 0.0) : 0.0;
  final riegosSugeridos = riegoSugerido <= 0 ? 0 : (riegoSugerido / plantacion.riego.mmPorRiego).ceil();

  final int? desdeSiembra;
  final int? aCosecha;
  if (cultivo.perenne) {
    desdeSiembra = null;
    aCosecha = null;
  } else {
    desdeSiembra = soloFecha(hoy).difference(soloFecha(plantacion.fecha)).inDays;
    aCosecha = plantacion.ciclo - desdeSiembra;
  }

  final ordenados = [...registros]..sort((a, b) => a.fecha.compareTo(b.fecha));
  final ultimoRegistro = ordenados.isEmpty ? null : ordenados.last;
  final diasSinRegistro =
      ultimoRegistro == null ? null : soloFecha(hoy).difference(soloFecha(ultimoRegistro.fecha)).inDays;
  final climaViejo = ultimoClima == null || soloFecha(hoy).difference(ultimoClima).inDays > 10;

  final lluviaSemana = semana.fold<double>(0, (a, d) => a + d.lluvia);
  final avisos = <Aviso>[];
  if (diasSinRegistro == null || diasSinRegistro >= 7) avisos.add(Aviso.registroPendiente);
  if (climaViejo) avisos.add(Aviso.climaViejo);
  final plagaActiva = ultimoRegistro != null
      ? ultimoRegistro.plaga.index >= NivelPlaga.moderada.index
      : plantacion.plagaReciente;
  if (plagaActiva) avisos.add(Aviso.plaga);
  final fertilizado = plantacion.fertilizo || registros.any((r) => r.fertilizo);
  if (!cultivo.perenne && actual.etapa == Etapa.desarrollo && !fertilizado) {
    // Sin lluvia reciente ni riego el abono no se aprovecha: se pospone.
    final hayAgua = plantacion.riego != TipoRiego.ninguno || lluviaSemana >= lluviaMinimaParaAbonar;
    avisos.add(hayAgua ? Aviso.fertilizar : Aviso.fertilizarEnEspera);
  }
  if (aCosecha != null && aCosecha >= 0 && aCosecha <= 10) avisos.add(Aviso.cosechaCerca);

  // La precisión sube con clima reciente y con registros semanales al día.
  final registrosRecientes =
      registros.where((r) => soloFecha(hoy).difference(soloFecha(r.fecha)).inDays <= 21).length;
  // Si algún día de la última semana es estimado (clima o lluvia sin dato), baja un punto.
  final puntos = math.max(0, (climaViejo ? 0 : 1) + (registrosRecientes >= 2 ? 1 : 0) - (estimadoEstaSemana ? 1 : 0));

  return Recomendacion(
    nivel: nivel,
    reserva: actual.reserva,
    agotamiento: actual.agotamiento,
    riegoSugerido: riegoSugerido,
    riegosSugeridos: riegosSugeridos,
    etapa: actual.etapa,
    diasDesdeSiembra: desdeSiembra,
    diasACosecha: aCosecha,
    factorRendimiento: factorRendimiento(estados, cultivo.parametros.ky),
    diasEstres: semana.where((d) => d.ks < 1 && d.etapa != Etapa.cosechado).length,
    lluviaSemana: lluviaSemana,
    necesidadSemana: semana.fold(0, (a, d) => a + d.etc),
    ultimos: ultimos,
    avisos: avisos,
    precision: Precision.values[puntos],
    ultimoClima: ultimoClima,
    diasEstimados: diasEstimados,
  );
}
