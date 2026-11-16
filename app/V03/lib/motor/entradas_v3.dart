import 'dart:math' as math;

import '../eventos.dart';
import '../modelos.dart';
import '../plan_v3.dart';
import 'fao56.dart';
import 'recomendador.dart';
import 'red_v3.dart';

part 'catalogo_entradas_v3.dart';

const accionEsperarV3 = 0;
const accionContinuarV3 = 1;
const accionRegarV3 = 5;
const costoRiegoReferenciaQV3 = 28.0;
const _numeroAcciones = 25;
const _perfilesEntrenados = 19;
const _escalaCaja = 5500.0;
const _cajaReferencia = 4000.0;
const _intervaloRiego = 5;

// Constantes del config.resolved.json que acompaña los pesos seleccionados.
typedef _Perfil = ({
  int indice,
  String nombre,
  String familia,
  int inicio,
  int fin,
  double costoSiembra,
  double humedadMinima,
  bool requiereRiego,
  double ciclo,
  double gdd,
  double gddEmergencia,
  double base,
  double techo,
  double minima,
  double maxima,
  double kgHa,
  double precio,
  double raices,
  double seco,
  double kc,
  double gastos,
  double polinizacion,
  double toleranciaSal,
  double demanda,
  double cortes,
});

String? _perfilId(String cultivo, [String variedad = '']) {
  final id = switch (cultivo.trim().toLowerCase()) {
    'maiz' || 'maíz' => 'maize',
    'frijol' ||
    'fríjol' ||
    'bean' => variedad.trim().toLowerCase() == 'icta zam' ? 'bean_zam' : 'bean',
    'tomate' => 'tomato',
    final valor => valor,
  };
  return _catalogo.containsKey(id) ? id : null;
}

String? perfilCultivoV3(Plantacion campania) =>
    _perfilId(campania.cultivoId, campania.variedad);

double _b(bool valor) => valor ? 1 : 0;
double _unidad(double valor) => valor.clamp(0.0, 1.0);
DateTime _fecha(DateTime d, [int dias = 0]) =>
    DateTime.utc(d.year, d.month, d.day + dias);
int _diaV3(DateTime d) => d.difference(DateTime.utc(d.year)).inDays + 1;
double _fraccionAnual(DateTime d) =>
    d.difference(DateTime.utc(d.year)).inDays /
    (DateTime.utc(d.year + 1).difference(DateTime.utc(d.year)).inDays - 1);
double _severidad(String? nivel) => switch (nivel) {
  'leve' => .25,
  'moderada' => .50,
  'fuerte' => .75,
  _ => 0,
};

Map<DateTime, DiaClima> _observacionesClima(
  List<DiaClima> clima,
  DateTime antesDe,
) => {
  for (final d in clima)
    if (_fecha(d.fecha).isBefore(antesDe) &&
        d.completo &&
        d.tmin!.isFinite &&
        d.tmax!.isFinite &&
        d.radiacion!.isFinite &&
        d.humedad!.isFinite &&
        d.viento!.isFinite &&
        d.lluvia != null &&
        d.lluvia!.isFinite &&
        d.lluvia! >= 0)
      _fecha(d.fecha): d,
};

class CandidatoSiembraV3 {
  const CandidatoSiembraV3({
    required this.accion,
    required this.id,
    required this.variedad,
    required this.ciclo,
    required this.costoQ,
  });

  final int accion;
  final String id, variedad;
  final int ciclo;
  final double costoQ;
}

class PreparacionSiembraV3 {
  const PreparacionSiembraV3({
    required this.entrada,
    required this.fecha,
    required this.candidatos,
  });

  final EntradaLoteV3 entrada;
  final DateTime fecha;
  final List<CandidatoSiembraV3> candidatos;
}

int _accionSiembra(_Perfil p) => p.indice <= 2 ? p.indice + 1 : p.indice + 5;

/// Puntúa la decisión inicial de una parcela libre. Una fecha futura solo
/// indica el comienzo de la ventana del catálogo y requiere revisar el clima
/// al llegar a esa fecha. El historial proviene del clima observado localmente.
PreparacionSiembraV3? prepararSiembraV3({
  required Parcela parcela,
  required List<DiaClima> clima,
  required DateTime hoy,
  required double areaHa,
  required Suelo suelo,
  required bool priorizarMargen,
  required String? cultivoAnterior,
  double? presupuestoQ,
  SuministroAgua? suministro,
}) {
  if (!areaHa.isFinite || areaHa <= 0) return null;
  final hoyUtc = _fecha(hoy);
  final observados = _observacionesClima(clima, hoyUtc);
  final et0 = {
    for (final d in prepararClima(clima, parcela, _fecha(hoyUtc, -1)))
      if (!d.et0Estimada) _fecha(d.fecha): d.et0,
  };

  final capacidad = suelo.aguaDisponible;
  final capacidadSuperficial = capacidad * .10200139864797363;
  final capacidadProfunda = capacidad - capacidadSuperficial;
  var superficie = capacidadSuperficial / 2;
  var profundo = capacidadProfunda / 2;
  final elevacion = parcela.elevacion ?? 500;
  final presion = 101.3 * math.pow((293 - .0065 * elevacion) / 293, 5.26);
  final temp = <double>[];
  final ejemplos = <(DateTime, List<double>)>[];
  DateTime? ultimo;
  for (var i = 28; i > 0; i--) {
    final fecha = _fecha(hoyUtc, -i), climaDia = observados[fecha];
    final evaporacion = et0[fecha];
    if (climaDia == null || evaporacion == null) continue;
    // Estimación de barbecho con las dos capas, Kc original V3 = 0.28.
    superficie += climaDia.lluvia!;
    final exceso = math.max(0.0, superficie - capacidadSuperficial);
    final percolacion = math.min(.65 * exceso, capacidadProfunda - profundo);
    profundo += percolacion;
    superficie = math.min(capacidadSuperficial, superficie - percolacion);
    superficie = math.max(0.0, superficie - .28 * evaporacion);
    final reserva = (superficie + profundo) / capacidad;
    temp.add((climaDia.tmin! + climaDia.tmax!) / 2);
    ultimo = fecha;
    ejemplos.add((
      fecha,
      [
        climaDia.lluvia! / 25,
        climaDia.tmin! / 40,
        climaDia.tmax! / 40,
        evaporacion / 10,
        climaDia.radiacion! / 30,
        climaDia.humedad! / 100,
        climaDia.viento! / 10,
        presion / 100,
        reserva,
        0,
        .265,
        0,
      ],
    ));
  }
  if (ultimo == null ||
      hoyUtc.difference(ultimo).inDays > 10 ||
      temp.length < 4) {
    return null;
  }

  final muestra = temp.skip(math.max(0, temp.length - 7));
  final temperatura = muestra.reduce((a, b) => a + b) / muestra.length;
  final reserva = (superficie + profundo) / capacidad;
  final semillero = superficie / capacidadSuperficial;
  final caja =
      presupuestoQ != null && presupuestoQ.isFinite && presupuestoQ >= 0
      ? presupuestoQ
      : _cajaReferencia;
  final aguaConocida = suministro != null && _fecha(suministro.fecha) == hoyUtc;
  final aguaHoy =
      aguaConocida &&
      suministro.disponibilidad == DisponibilidadAgua.si &&
      (suministro.volumenM3 ?? double.infinity) > 0;
  final asequibles = _catalogo.entries.where(
    (e) => e.value.gastos * areaHa <= caja + 1e-6,
  );
  if (asequibles.isEmpty) {
    throw const SiembraNoDisponible(FaltaParaSiembra.presupuesto);
  }
  final perfiles = asequibles.where((e) {
    final p = e.value;
    return temperatura >= p.minima && temperatura <= p.maxima;
  }).toList();
  if (perfiles.isEmpty) {
    throw const SiembraNoDisponible(FaltaParaSiembra.temperatura);
  }

  final diaCalendario = _diaV3(hoyUtc);
  final enVentana = perfiles
      .where(
        (e) => diaCalendario >= e.value.inicio && diaCalendario <= e.value.fin,
      )
      .toList();
  var fechaDecision = hoyUtc;
  var aplicables = enVentana
      .where(
        (e) =>
            (!e.value.requiereRiego || aguaHoy) &&
            semillero >= e.value.humedadMinima,
      )
      .toList();
  if (enVentana.isEmpty) {
    DateTime? siguiente;
    for (final e in perfiles.where((e) => !e.value.requiereRiego)) {
      final inicio = DateTime.utc(
        hoyUtc.year + (diaCalendario > e.value.fin ? 1 : 0),
        1,
        e.value.inicio,
      );
      if (siguiente == null || inicio.isBefore(siguiente)) siguiente = inicio;
    }
    if (siguiente != null) {
      fechaDecision = siguiente;
      final apertura = _diaV3(siguiente);
      aplicables = perfiles
          .where(
            (e) =>
                !e.value.requiereRiego &&
                e.value.inicio <= apertura &&
                apertura <= e.value.fin,
          )
          .toList();
    }
  }
  if (aplicables.isEmpty) {
    final motivo = enVentana.isEmpty
        ? FaltaParaSiembra.fecha
        : enVentana.every((e) => e.value.requiereRiego && !aguaHoy)
        ? FaltaParaSiembra.agua
        : FaltaParaSiembra.humedad;
    throw SiembraNoDisponible(motivo);
  }

  final dia = _fraccionAnual(fechaDecision);
  final previo = cultivoAnterior == null
      ? null
      : _catalogo[_perfilId(cultivoAnterior)];
  final factibles = List<bool>.filled(_numeroAcciones, false)
    ..[accionEsperarV3] = true;
  final referencia = List<double>.filled(_numeroAcciones, 0)
    ..[accionEsperarV3] = .36;
  final candidatas = List.generate(
    _numeroAcciones,
    (_) => List<double>.filled(45, 0),
  );
  candidatas[accionEsperarV3] = [
    1,
    ...List<double>.filled(24, 0),
    0,
    0,
    0,
    0,
    0,
    1,
    .75,
    dia,
    0,
    0,
    0,
    0,
    -temperatura / 20,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  final candidatos = <CandidatoSiembraV3>[];
  for (final e in aplicables) {
    final perfil = e.value, accion = _accionSiembra(e.value);
    final mismoGrupo = previo?.familia == perfil.familia;
    final ingreso = perfil.precio * perfil.kgHa;
    final margen =
        (ingreso - perfil.gastos) / (ingreso.abs() + perfil.gastos + 1);
    final materiaSeca = perfil.kgHa * perfil.seco / perfil.ciclo;
    final produccion = materiaSeca / (materiaSeca + 25);
    final costo = perfil.costoSiembra * areaHa;
    factibles[accion] = true;
    referencia[accion] =
        .50 +
        .32 * (priorizarMargen ? margen : produccion) -
        (mismoGrupo ? .09 : 0) -
        (reserva < .20 ? .13 : 0);
    candidatas[accion] = _candidata(
      perfil,
      accion,
      costo,
      caja,
      3,
      dia,
      capacidad,
      reserva,
      temperatura,
      mismoGrupo,
    );
    candidatos.add(
      CandidatoSiembraV3(
        accion: accion,
        id: e.key,
        variedad: perfil.nombre,
        ciclo: perfil.ciclo.round(),
        costoQ: costo,
      ),
    );
  }

  final aguaEnDecision = fechaDecision == hoyUtc && aguaHoy;
  final regable = _b(aguaEnDecision);
  final porFecha = Map.fromEntries(ejemplos.map((e) => MapEntry(e.$1, e.$2)));
  return PreparacionSiembraV3(
    fecha: DateTime(fechaDecision.year, fechaDecision.month, fechaDecision.day),
    candidatos: candidatos,
    entrada: EntradaLoteV3(
      estatico: [
        areaHa,
        0,
        elevacion / 1000,
        1,
        regable,
        capacidad / 200,
        parcela.latitud / 20,
        parcela.longitud / 100,
        0,
        0,
        .5,
        .265,
        .705,
        0,
        0,
        .75,
        0,
        1 - regable,
        0,
        math.sqrt(areaHa),
        0,
        regable,
        capacidad * .5 / 200,
        areaHa * capacidad / 200,
      ],
      recientes: [
        for (var i = 28; i > 0; i--)
          porFecha[_fecha(hoyUtc, -i)] ?? List<double>.filled(12, 0),
      ],
      recientesValidos: [
        for (var i = 28; i > 0; i--) porFecha.containsKey(_fecha(hoyUtc, -i)),
      ],
      historia: List.generate(32, (_) => List<double>.filled(16, 0)),
      historiaValida: List<bool>.filled(32, false),
      contexto: [
        caja / _escalaCaja,
        0,
        0,
        0,
        dia,
        1,
        0,
        0,
        0,
        .265,
        .265,
        .705,
        reserva,
        0,
        0,
        regable,
        _b(fechaDecision == hoyUtc && aguaConocida),
        1,
        .75,
        _b(!priorizarMargen),
        _b(priorizarMargen),
        _catalogo['maize']!.precio / 10,
        _catalogo['bean']!.precio / 10,
        1,
        0,
        0,
        0,
        semillero,
        0,
        0,
        0,
        0,
        0,
        0,
        (previo?.indice ?? 0) / _perfilesEntrenados,
        0,
        1,
        1,
        1,
        1,
        0,
        0,
        0,
        .85,
        .85,
        1,
        1,
        1,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        _unidad(caja / math.max(caja, 1)) / 2,
      ],
      candidatas: candidatas,
      base: referencia,
      factibles: factibles,
    ),
  );
}

List<double> _candidata(
  _Perfil perfil,
  int accion,
  double costo,
  double caja,
  int semillas,
  double dia,
  double capacidad,
  double reserva,
  double temperatura,
  bool mismoGrupo,
) => [
  for (var i = 0; i < _numeroAcciones; i++) _b(i == accion),
  costo / 25000,
  perfil.ciclo / 180,
  perfil.kgHa / 40000,
  perfil.precio / 15,
  perfil.raices,
  _b(costo <= caja),
  semillas / 4,
  dia,
  capacidad * perfil.raices * reserva / 150,
  perfil.seco,
  perfil.kc,
  perfil.gdd / 2200,
  math.min(temperatura - perfil.minima, perfil.maxima - temperatura) / 20,
  _b(mismoGrupo),
  ((perfil.kgHa * perfil.precio - perfil.gastos) / 50000).clamp(-3.0, 3.0),
  _b(perfil.requiereRiego),
  perfil.polinizacion,
  perfil.toleranciaSal / 8,
  perfil.demanda,
  perfil.cortes,
];

/// Adapta el estado observado y el balance local a la decisión diaria de V3.
/// Los perfiles usan costos/precios de referencia. Suelo profundo, NPK y
/// entorno sin medidas conservan supuestos de inicio de V3. La app omite
/// las acciones que exigirían simular una siembra o prescribir un insumo.
EntradaLoteV3? prepararEntradaV3({
  required Parcela parcela,
  required Plantacion campania,
  required Recomendacion recomendacion,
  required List<DiaClima> clima,
  required List<RegistroRiego> riegos,
  required List<Evento> eventos,
  required DateTime hoy,
  required double areaHa,
  required bool priorizarMargen,
  double? presupuestoQ,
  SuministroAgua? suministro,
  double costoRiegoQ = costoRiegoReferenciaQV3,
  int indiceLote = 0,
  List<RegistroSemanal> registros = const [],
}) {
  final perfil = _catalogo[perfilCultivoV3(campania)];
  final ultimoClima = recomendacion.ultimoClima;
  final fecha = _fecha(hoy), siembra = _fecha(campania.fecha);
  if (perfil == null ||
      !campania.activa ||
      !areaHa.isFinite ||
      areaHa <= 0 ||
      !costoRiegoQ.isFinite ||
      costoRiegoQ < 0 ||
      siembra.isAfter(fecha) ||
      recomendacion.etapa == Etapa.cosechado ||
      ultimoClima == null ||
      fecha.difference(_fecha(ultimoClima)).inDays > 10) {
    return null;
  }

  final dados = <DateTime, DiaClima>{
    for (final d in clima)
      if (_fecha(d.fecha).isBefore(fecha) &&
          d.completo &&
          d.tmin!.isFinite &&
          d.tmax!.isFinite &&
          d.radiacion!.isFinite &&
          d.humedad!.isFinite &&
          d.viento!.isFinite &&
          d.lluvia != null &&
          d.lluvia!.isFinite &&
          d.lluvia! >= 0)
        _fecha(d.fecha): d,
  };
  final climaBalance = prepararClima(clima, parcela, _fecha(fecha, -1));
  final riegoLocal = prepararRiegos(registros, riegos, campania.riego);
  final balance = {
    for (final d in simularBalance(
      dias: climaBalance,
      siembra: campania.fecha,
      cultivo: campania.cultivo.parametros,
      ciclo: campania.ciclo,
      aguaDisponible: campania.suelo.aguaDisponible,
      riegos: riegoLocal.laminas,
      riegosEstimados: riegoLocal.estimados,
    ))
      _fecha(d.fecha): d,
  };
  final et0 = {for (final d in climaBalance) _fecha(d.fecha): d.et0};
  final edad = fecha.difference(siembra).inDays;
  double termico(DiaClima d) => math.max(
    0.0,
    math.min(perfil.techo, (d.tmax! + d.tmin!) / 2) - perfil.base,
  );
  final termicos = dados.entries
      .where((d) => !d.key.isBefore(siembra))
      .toList();
  final gdd = edad > 0 && termicos.length >= .8 * edad
      ? termicos.fold(0.0, (total, d) => total + termico(d.value)) *
            edad /
            termicos.length
      : _unidad(edad / campania.ciclo) * perfil.gdd;
  final avance = _unidad(gdd / perfil.gdd);
  double cobertura(DateTime d) => math.min(
    .92,
    2 * _unidad(d.difference(siembra).inDays / math.max(1, edad)) * avance,
  );
  final reserva =
      balance[_fecha(fecha, -1)]?.reserva ?? _unidad(recomendacion.reserva);
  final elevacion = parcela.elevacion ?? 500;
  final presion = 101.3 * math.pow((293 - .0065 * elevacion) / 293, 5.26);
  final recientes = <List<double>>[];
  final recientesValidos = <bool>[];
  double? temperatura;
  for (var i = 28; i > 0; i--) {
    final dia = _fecha(fecha, -i);
    final d = dados[dia], agua = balance[dia], evapotranspiracion = et0[dia];
    final valido = d != null && agua != null && evapotranspiracion != null;
    recientesValidos.add(valido);
    if (valido) {
      temperatura = (d.tmin! + d.tmax!) / 2;
      recientes.add([
        d.lluvia! / 25,
        d.tmin! / 40,
        d.tmax! / 40,
        evapotranspiracion / 10,
        d.radiacion! / 30,
        d.humedad! / 100,
        d.viento! / 10,
        presion / 100,
        agua.reserva,
        0,
        cobertura(dia),
        _b(agua.riego > 0),
      ]);
    } else {
      recientes.add(List.filled(12, 0));
    }
  }
  if (temperatura == null) return null;

  final dias = <DateTime, List<Evento>>{};
  for (final e in eventos) {
    final dia = e.fecha == null ? null : _fecha(e.fecha!);
    if (e.campaniaId == campania.id &&
        dia != null &&
        !dia.isBefore(siembra) &&
        !dia.isAfter(fecha)) {
      (dias[dia] ??= []).add(e);
    }
  }
  final riegoConfirmado = {
    for (final r in riegos)
      if (r.campaniaId == campania.id &&
          r.rego == true &&
          (r.laminaMm == null || r.laminaMm! > 0) &&
          !_fecha(r.fecha).isAfter(fecha) &&
          !_fecha(r.fecha).isBefore(siembra))
        _fecha(r.fecha),
  };
  final fechas = {siembra, ...dias.keys, ...riegoConfirmado}.toList()..sort();
  final anterior = _catalogo[_perfilId(campania.cultivoAnterior)]?.indice ?? 0;
  const nitrogeno = .705; // Promedio de los dos perfiles base de V3.
  const residuo = .265;
  var diasRiego = 60,
      diasControl = 60,
      diasFertilizacion = 120,
      diasPlaga = 366;
  var plaga = 0.0, sombra = 1.0;
  final historiaReal = <List<double>>[];
  for (final dia in fechas) {
    final registrosDia = dias[dia] ?? const [];
    final tipos = registrosDia.map((e) => e.tipo).toSet();
    final lapso = fecha.difference(dia).inDays;
    final rego = riegoConfirmado.contains(dia);
    final visto = tipos.contains(TipoEvento.plaga);
    final fert = tipos.contains(TipoEvento.fertilizacion);
    final control = tipos.contains(TipoEvento.tratamiento);
    final cosecha = tipos.contains(TipoEvento.cosecha);
    var plagaDia = 0.0;
    for (final e in registrosDia) {
      if (e.tipo == TipoEvento.plaga) {
        plagaDia = math.max(plagaDia, _severidad(e.severidad));
      }
      if (e.observacion == Observacion.sombra &&
          e.unidad == '%' &&
          e.cantidad != null) {
        sombra = 1 - _unidad(e.cantidad! / 100);
      }
    }
    if (rego) diasRiego = math.min(diasRiego, lapso);
    if (control) diasControl = math.min(diasControl, lapso);
    if (fert) diasFertilizacion = math.min(diasFertilizacion, lapso);
    if (visto) {
      diasPlaga = math.min(diasPlaga, lapso);
      plaga = plagaDia;
    }
    if (dia.isBefore(fecha) &&
        (dia == siembra || rego || fert || control || visto || cosecha)) {
      historiaReal.add([
        _fraccionAnual(dia),
        0,
        _b(dia == siembra),
        _b(rego),
        _b(fert),
        _b(control),
        _b(visto),
        _b(cosecha),
        plagaDia,
        0,
        0,
        0,
        0,
        anterior / _perfilesEntrenados,
        perfil.indice / _perfilesEntrenados,
        nitrogeno,
      ]);
    }
  }
  final historiaUsada = historiaReal
      .skip(math.max(0, historiaReal.length - 32))
      .toList();
  final relleno = 32 - historiaUsada.length;

  final tieneRiego = campania.tieneRiego;
  final suministroHoy = suministro != null && _fecha(suministro.fecha) == fecha
      ? suministro
      : null;
  final acceso =
      suministroHoy?.disponibilidad ?? DisponibilidadAgua.desconocida;
  final confirmado = acceso == DisponibilidadAgua.si;
  final volumen = suministroHoy?.volumenM3 ?? double.infinity;
  final aguaDisponible = confirmado && volumen > 0;
  final caja =
      presupuestoQ != null && presupuestoQ.isFinite && presupuestoQ >= 0
      ? presupuestoQ
      : _cajaReferencia;
  final necesita = tieneRiego && recomendacion.necesidadRiego > 0;
  final permiteRiego =
      necesita &&
      aguaDisponible &&
      recomendacion.riegoSugerido > 0 &&
      volumen + 1e-6 >= recomendacion.riegoSugerido * areaHa * 10 &&
      diasRiego >= _intervaloRiego &&
      caja >= costoRiegoQ;
  final eficiencia = switch (campania.riego) {
    TipoRiego.goteo => .90,
    TipoRiego.manual || TipoRiego.aspersion => .75,
    TipoRiego.gravedad => .60,
    TipoRiego.ninguno => 1.0,
  };
  final capacidad = campania.suelo.aguaDisponible;
  final dia = _fraccionAnual(fecha), regable = _b(tieneRiego);
  final cubierta = math.max(residuo, cobertura(fecha));
  final contexto = <double>[
    // Estado base (24), hidrología (3), establecimiento (4), enfermedad (2).
    caja / _escalaCaja, 0, 0, 0, dia, 0,
    _b(perfil.indice == 1), _b(perfil.indice == 2),
    avance, cubierta, residuo, nitrogeno, reserva, 0,
    _b(necesita),
    _b(aguaDisponible),
    _b(acceso != DisponibilidadAgua.desconocida),
    diasPlaga / 366, 0, _b(!priorizarMargen), _b(priorizarMargen),
    _catalogo['maize']!.precio / 10, _catalogo['bean']!.precio / 10, 1,
    0, 0, 0, reserva, 0, _unidad(gdd / perfil.gddEmergencia), 0, 0, 0,
    // Contexto del catálogo (10) y manejo V3 (16).
    perfil.indice / _perfilesEntrenados, anterior / _perfilesEntrenados,
    perfil.precio / 15, diasRiego / 60, diasControl / 60,
    math.min(240, edad) / 240, diasFertilizacion / 120, 0, 0, 0,
    .85, .85, 1, 1, sombra, 0, 1, plaga * math.pow(.9, diasPlaga).toDouble(),
    0, 0, eficiencia, 0, 0, 0, 0, _unidad(caja / math.max(caja, 1)) / 2,
  ];

  final factibles = List<bool>.filled(_numeroAcciones, false)
    ..[accionEsperarV3] = true
    ..[accionContinuarV3] = true
    ..[accionRegarV3] = permiteRiego;
  final candidatas = List.generate(_numeroAcciones, (accion) {
    if (!factibles[accion]) return List<double>.filled(45, 0);
    final costo = accion == accionRegarV3 ? costoRiegoQ : 0.0;
    final mismoGrupo =
        anterior != 0 &&
        (anterior == perfil.indice ||
            ((anterior == 2 || anterior == 19) &&
                (perfil.indice == 2 || perfil.indice == 19)));
    return <double>[
      for (var i = 0; i < _numeroAcciones; i++) _b(i == accion),
      costo / 25000,
      perfil.ciclo / 180,
      perfil.kgHa / 40000,
      perfil.precio / 15,
      perfil.raices,
      _b(costo <= caja),
      0,
      dia,
      capacidad * perfil.raices * reserva / 150,
      perfil.seco,
      perfil.kc,
      perfil.gdd / 2200,
      math.min(temperatura! - perfil.minima, perfil.maxima - temperatura) / 20,
      _b(mismoGrupo),
      ((perfil.kgHa * perfil.precio - perfil.gastos) / 50000).clamp(-3.0, 3.0),
      0,
      perfil.polinizacion,
      perfil.toleranciaSal / 8,
      perfil.demanda,
      perfil.cortes,
    ];
  });
  final referencia = List<double>.filled(_numeroAcciones, 0)
    ..[accionEsperarV3] = .36
    ..[accionContinuarV3] = .42
    ..[accionRegarV3] = .67 + (reserva < .30 ? .15 : 0);

  return EntradaLoteV3(
    estatico: [
      areaHa,
      0,
      elevacion / 1000,
      sombra,
      regable,
      capacidad / 200,
      parcela.latitud / 20,
      parcela.longitud / 100,
      campania.riego.mmPorRiego / 20,
      0,
      .5,
      residuo,
      nitrogeno,
      0,
      costoRiegoQ / 100,
      0,
      indiceLote.toDouble(),
      1 - regable,
      1 - sombra,
      math.sqrt(areaHa),
      0,
      regable,
      capacidad * .5 / 200,
      areaHa * capacidad / 200,
    ],
    recientes: recientes,
    historia: [
      for (var i = 0; i < relleno; i++) List<double>.filled(16, 0),
      ...historiaUsada,
    ],
    contexto: contexto,
    candidatas: candidatas,
    base: referencia,
    recientesValidos: recientesValidos,
    historiaValida: [for (var i = 0; i < 32; i++) i >= relleno],
    factibles: factibles,
  );
}
