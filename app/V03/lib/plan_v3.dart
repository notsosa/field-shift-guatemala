/// Opciones y resultado guardado del plan diario calculado en el dispositivo.
library;

import 'modelos.dart';

enum PrioridadPlanV3 { produccion, margen }

enum AccionPlanV3 { esperar, continuar, regar, pendiente }

enum FaltaParaSiembra { clima, presupuesto, temperatura, agua, humedad, fecha }

class SiembraNoDisponible implements Exception {
  const SiembraNoDisponible(this.motivo);

  final FaltaParaSiembra motivo;
}

class PropuestaSiembraV3 {
  const PropuestaSiembraV3({
    required this.cultivoId,
    required this.variedad,
    required this.fecha,
    required this.ciclo,
    required this.suelo,
    required this.riego,
    required this.cultivoAnterior,
    required this.convieneEsperar,
  });

  final String cultivoId, variedad, cultivoAnterior;
  final DateTime fecha;
  final int ciclo;
  final Suelo suelo;
  final TipoRiego riego;
  final bool convieneEsperar;
}

class OpcionesPlanV3 {
  const OpcionesPlanV3({
    required this.prioridad,
    this.presupuestoQ,
    this.costoRiegoQ,
  });

  static const inicial = OpcionesPlanV3(prioridad: PrioridadPlanV3.produccion);
  static const costoRiegoReferenciaQ = 28.0;

  final PrioridadPlanV3 prioridad;
  final double? presupuestoQ, costoRiegoQ;

  double get costoTurnoQ => costoRiegoQ ?? costoRiegoReferenciaQ;

  void validar() {
    for (final valor in [presupuestoQ, costoRiegoQ]) {
      if (valor != null && (!valor.isFinite || valor < 0)) {
        throw const FormatException('Revisa los montos en quetzales.');
      }
    }
  }

  Map<String, dynamic> aJson() => {
    'prioridad': prioridad.name,
    'presupuestoQ': presupuestoQ,
    'costoRiegoQ': costoRiegoQ,
  };

  factory OpcionesPlanV3.deJson(Map<String, dynamic> json) {
    final opciones = OpcionesPlanV3(
      prioridad: PrioridadPlanV3.values.byName(json['prioridad'] as String),
      presupuestoQ: (json['presupuestoQ'] as num?)?.toDouble(),
      costoRiegoQ: (json['costoRiegoQ'] as num?)?.toDouble(),
    );
    opciones.validar();
    return opciones;
  }
}

class ResultadoLotePlanV3 {
  const ResultadoLotePlanV3({
    required this.id,
    required this.nombre,
    required this.cultivoId,
    required this.accion,
    this.reserva,
    this.laminaMm = 0,
    this.aguaM3 = 0,
    this.costoQ,
    this.avisos = const [],
  });

  final String id, nombre, cultivoId;
  final AccionPlanV3 accion;
  final double? reserva, costoQ;
  final double laminaMm, aguaM3;
  final List<String> avisos;

  Map<String, dynamic> aJson() => {
    'id': id,
    'nombre': nombre,
    'cultivoId': cultivoId,
    'accion': accion.name,
    'reserva': reserva,
    'laminaMm': laminaMm,
    'aguaM3': aguaM3,
    'costoQ': costoQ,
    'avisos': avisos,
  };

  factory ResultadoLotePlanV3.deJson(Map<String, dynamic> json) =>
      ResultadoLotePlanV3(
        id: json['id'] as String,
        nombre: json['nombre'] as String,
        cultivoId: json['cultivoId'] as String,
        accion: AccionPlanV3.values.byName(json['accion'] as String),
        reserva: (json['reserva'] as num?)?.toDouble(),
        laminaMm: (json['laminaMm'] as num).toDouble(),
        aguaM3: (json['aguaM3'] as num).toDouble(),
        costoQ: (json['costoQ'] as num?)?.toDouble(),
        avisos: List<String>.unmodifiable(json['avisos'] as List),
      );
}

class ResultadoPlanV3 {
  const ResultadoPlanV3({
    required this.solicitudId,
    required this.calculado,
    required this.prioridad,
    required this.lotes,
    this.avisos = const [],
  });

  static const modelo = 'Red neuronal';
  static const version = 2;
  static const revision = 'v3-17-g60-local-1';

  final String solicitudId;
  final DateTime calculado;
  final PrioridadPlanV3 prioridad;
  final List<ResultadoLotePlanV3> lotes;
  final List<String> avisos;

  String get motor => modelo;
  int get evaluados =>
      lotes.where((lote) => lote.accion != AccionPlanV3.pendiente).length;
  double get aguaM3 => lotes.fold(0.0, (suma, lote) => suma + lote.aguaM3);
  double? get costoQ {
    final costos = lotes.map((lote) => lote.costoQ).whereType<double>();
    return costos.isEmpty
        ? null
        : costos.fold<double>(0.0, (suma, q) => suma + q);
  }

  Map<String, dynamic> aJson() => {
    'version': version,
    'revision': revision,
    'solicitudId': solicitudId,
    'calculado': calculado.toIso8601String(),
    'prioridad': prioridad.name,
    'lotes': lotes.map((lote) => lote.aJson()).toList(),
    'avisos': avisos,
  };

  factory ResultadoPlanV3.deJson(Map<String, dynamic> json) {
    if (json['version'] != version || json['revision'] != revision) {
      throw const FormatException('Versión de plan local incompatible.');
    }
    return ResultadoPlanV3(
      solicitudId: json['solicitudId'] as String,
      calculado: DateTime.parse(json['calculado'] as String),
      prioridad: PrioridadPlanV3.values.byName(json['prioridad'] as String),
      lotes: List.unmodifiable(
        (json['lotes'] as List).map(
          (lote) => ResultadoLotePlanV3.deJson(lote as Map<String, dynamic>),
        ),
      ),
      avisos: List.unmodifiable((json['avisos'] as List).cast<String>()),
    );
  }
}
