import 'dart:isolate';
import 'dart:math' as math;

import '../eventos.dart';
import '../modelos.dart';
import '../plan_v3.dart';
import 'entradas_v3.dart';
import 'recomendador.dart';
import 'red_v3.dart';

typedef LoteParaPlanV3 = ({
  Plantacion campania,
  String nombre,
  double areaHa,
  Recomendacion balance,
  List<RegistroRiego> riegos,
  List<RegistroSemanal> registros,
  List<Evento> eventos,
});

class PlanificadorV3 {
  RedV3? _red;

  Future<PropuestaSiembraV3> proponerSiembra({
    required Parcela parcela,
    required List<DiaClima> clima,
    required DateTime hoy,
    required double areaHa,
    required Suelo suelo,
    required TipoRiego riego,
    required String cultivoAnterior,
    required OpcionesPlanV3 opciones,
    required SuministroAgua? suministro,
  }) async {
    final preparacion = prepararSiembraV3(
      parcela: parcela,
      clima: clima,
      hoy: hoy,
      areaHa: areaHa,
      suelo: suelo,
      priorizarMargen: opciones.prioridad == PrioridadPlanV3.margen,
      cultivoAnterior: cultivoAnterior,
      presupuestoQ: opciones.presupuestoQ,
      suministro: riego == TipoRiego.ninguno ? null : suministro,
    );
    if (preparacion == null) {
      throw const SiembraNoDisponible(FaltaParaSiembra.clima);
    }
    final puntajes = (await _puntuar([preparacion.entrada])).single;
    final candidato = preparacion.candidatos.reduce(
      (mejor, otro) =>
          puntajes[otro.accion] > puntajes[mejor.accion] ? otro : mejor,
    );
    final cultivo = switch (candidato.id) {
      'maize' => 'maiz',
      'bean' || 'bean_zam' => 'frijol',
      'tomato' => 'tomate',
      final id => id,
    };
    return PropuestaSiembraV3(
      cultivoId: cultivo,
      variedad: candidato.variedad,
      fecha: preparacion.fecha,
      ciclo: candidato.ciclo,
      suelo: suelo,
      riego: riego,
      cultivoAnterior: cultivoAnterior,
      convieneEsperar:
          preparacion.fecha.isAfter(soloFecha(hoy)) ||
          puntajes[candidato.accion] <= puntajes[accionEsperarV3] + 1e-6,
    );
  }

  Future<List<List<double>>> _puntuar(List<EntradaLoteV3> entradas) async {
    if (entradas.isEmpty) return const [];
    final red = _red ??= await RedV3.cargar();
    return Isolate.run(() => red.puntuar(entradas));
  }

  Future<ResultadoPlanV3> calcular({
    required String solicitudId,
    required Parcela parcela,
    required List<LoteParaPlanV3> lotes,
    required List<DiaClima> clima,
    required DateTime hoy,
    required OpcionesPlanV3 opciones,
    required SuministroAgua? suministro,
  }) async {
    final entradas = <EntradaLoteV3>[];
    final indiceEntrada = <String, int>{};
    final perfiles = <String, String>{};
    final avisosPorLote = <String, List<String>>{};
    final costoTurno = opciones.costoTurnoQ;

    for (final lote in lotes) {
      final p = lote.campania;
      final id = p.loteId;
      final perfil = perfilCultivoV3(p);
      final avisos = avisosPorLote[id] = [];
      if (perfil == null) {
        avisos.add('cultivo_no_compatible');
        continue;
      }
      perfiles[id] = perfil;
      if (lote.areaHa <= 0) {
        avisos.add('area_pendiente');
        continue;
      }
      final ayer = lote.balance.ultimoClima;
      if (ayer == null ||
          lote.balance.nivel == NivelAgua.sinDatos ||
          lote.balance.avisos.contains(Aviso.climaViejo)) {
        avisos.add('clima_insuficiente');
        continue;
      }
      final dias = soloFecha(hoy).difference(soloFecha(p.fecha)).inDays;
      if (dias < 0 || dias >= p.ciclo) {
        avisos.add('campania_fuera_de_ciclo');
        continue;
      }
      final entrada = prepararEntradaV3(
        parcela: parcela,
        campania: p,
        recomendacion: lote.balance,
        clima: clima,
        riegos: lote.riegos,
        registros: lote.registros,
        eventos: lote.eventos,
        hoy: hoy,
        areaHa: lote.areaHa,
        priorizarMargen: opciones.prioridad == PrioridadPlanV3.margen,
        presupuestoQ: opciones.presupuestoQ,
        suministro: suministro,
        costoRiegoQ: costoTurno,
        indiceLote: entradas.length,
      );
      if (entrada == null) {
        avisos.add('clima_insuficiente');
        continue;
      }
      if (p.riego != TipoRiego.ninguno && lote.balance.necesidadRiego > 0) {
        if (suministro?.disponibilidad != DisponibilidadAgua.si) {
          avisos.add('agua_sin_confirmar');
        } else if (suministro?.volumenM3 == 0) {
          avisos.add('volumen_insuficiente');
        } else if (opciones.presupuestoQ != null &&
            opciones.presupuestoQ! < costoTurno) {
          avisos.add('presupuesto_insuficiente');
        } else if (lote.riegos.any((r) {
          final dias = soloFecha(hoy).difference(soloFecha(r.fecha)).inDays;
          return r.rego == true && dias >= 0 && dias < 5;
        })) {
          avisos.add('riego_reciente');
        }
      }
      indiceEntrada[id] = entradas.length;
      entradas.add(entrada);
    }

    final puntajes = await _puntuar(entradas);

    // Las parcelas comparten un turno. La V3 evalúa cada lote y se asigna
    // el turno al que más mejora el puntaje de esperar entre los elegibles.
    String? elegido;
    var ventaja = 1e-6;
    for (final lote in lotes) {
      final id = lote.campania.loteId;
      final i = indiceEntrada[id];
      if (i == null || !entradas[i].factibles[accionRegarV3]) continue;
      final puntaje = puntajes[i][accionRegarV3] - puntajes[i][accionEsperarV3];
      if (puntaje > ventaja && _lamina(lote, suministro) > 0) {
        ventaja = puntaje;
        elegido = id;
      }
    }

    final resultados = <ResultadoLotePlanV3>[];
    for (final lote in lotes) {
      final p = lote.campania;
      final id = p.loteId;
      final i = indiceEntrada[id];
      final avisos = avisosPorLote[id]!;
      final regar = id == elegido;
      final lamina = regar ? _lamina(lote, suministro) : 0.0;
      var accion = AccionPlanV3.pendiente;
      if (i != null) {
        final valores = puntajes[i];
        if (regar) {
          accion = AccionPlanV3.regar;
        } else {
          accion = valores[accionContinuarV3] > valores[accionEsperarV3] + 1e-6
              ? AccionPlanV3.continuar
              : AccionPlanV3.esperar;
          if (elegido != null &&
              entradas[i].factibles[accionRegarV3] &&
              valores[accionRegarV3] > valores[accionEsperarV3] + 1e-6) {
            avisos.add('turno_compartido');
          }
        }
      }
      resultados.add(
        ResultadoLotePlanV3(
          id: id,
          nombre: lote.nombre,
          cultivoId: perfiles[id] ?? p.cultivoId,
          accion: accion,
          reserva: lote.balance.nivel == NivelAgua.sinDatos
              ? null
              : lote.balance.reserva,
          laminaMm: lamina,
          aguaM3: lamina * lote.areaHa * 10,
          costoQ: regar ? costoTurno : null,
          avisos: List.unmodifiable(avisos),
        ),
      );
    }

    return ResultadoPlanV3(
      solicitudId: solicitudId,
      calculado: hoy,
      prioridad: opciones.prioridad,
      lotes: List.unmodifiable(resultados),
      avisos: [
        if (lotes.isEmpty) 'sin_campanias',
        if (entradas.isNotEmpty) 'entradas_estimadas',
        if (elegido != null && opciones.costoRiegoQ == null)
          'costo_referencial',
      ],
    );
  }

  double _lamina(LoteParaPlanV3 lote, SuministroAgua? suministro) {
    if (suministro?.disponibilidad != DisponibilidadAgua.si ||
        lote.areaHa <= 0) {
      return 0;
    }
    final sugerida = lote.balance.riegoSugerido;
    final volumen = suministro?.volumenM3;
    return volumen == null
        ? sugerida
        : math.min(sugerida, volumen / (lote.areaHa * 10));
  }
}
