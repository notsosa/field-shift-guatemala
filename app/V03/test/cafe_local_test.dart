// Caso numérico de app/V01-red/test/casos_cafe.json en la rama modelo-keu.
import 'package:field_shift/modelos.dart';
import 'package:field_shift/motor/cafe.dart';
import 'package:field_shift/motor/recomendador.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la red de café conserva la salida de la semilla exportada', () {
    const entradas = EntradasCafe(
      x: [
        90,
        197,
        24.6,
        24.87571097993102,
        152,
        97.6504463353621,
        679.3,
        858.3346686517111,
        4,
        17.428214285714283,
        22.94,
        8.233993087401597,
        156,
        1787,
        0,
        0,
        0,
        1,
        0,
      ],
      agotamiento: 8.233993087401597,
      taw: 156,
    );
    final decision = decidirRiegoCafe(
      entradas: entradas,
      prioridad: PrioridadRiego.protegerCultivo,
      antracnosisPorEstres: false,
    );
    expect(decision.diasEvitados, closeTo(2.629100216262189, 1e-6));
    expect(decision.regar, isTrue);
  });

  test(
    'Hoy usa el modelo en café observado y conserva los límites de agua',
    () {
      const parcela = Parcela(
        nombre: 'Finca',
        latitud: 14.6,
        longitud: -90.5,
        elevacion: 1100,
      );
      final hoy = DateTime(2026, 4, 14);
      final cafetal = Plantacion(
        cultivoId: 'cafe',
        fecha: DateTime(2026, 2, 15),
        ciclo: 365,
        suelo: Suelo.franco,
        riego: TipoRiego.goteo,
        temporadaRiego: TemporadaRiego.auxilio,
        plagaReciente: false,
        fertilizo: false,
        sombra: Sombra.bananoRegulado,
        prioridadRiego: PrioridadRiego.protegerCultivo,
      );
      final clima = [
        for (
          var dia = DateTime(2025, 11);
          !dia.isAfter(hoy);
          dia = DateTime(dia.year, dia.month, dia.day + 1)
        )
          DiaClima(
            fecha: dia,
            tmax: 29,
            tmin: 17,
            humedad: 70,
            viento: 1.8,
            radiacion: 19,
            lluvia: 0,
          ),
      ];
      final recuperado = Plantacion.deJson(cafetal.aJson());
      expect(recuperado.sombra, Sombra.bananoRegulado);
      expect(recuperado.prioridadRiego, PrioridadRiego.protegerCultivo);

      Recomendacion calcular(
        List<DiaClima> datos, {
        List<RegistroRiego> riegos = const [],
      }) => recomendar(
        parcela: parcela,
        plantacion: recuperado,
        clima: datos,
        registros: const [],
        hoy: hoy,
        disponibilidad: DisponibilidadAgua.no,
        riegosDiarios: riegos,
      );
      final rec = calcular(clima);
      expect(rec.cafeRed?.riego?.diasEvitados.isFinite, isTrue);
      expect(rec.riegoSugerido, 0);
      expect(limitarRiego(rec, 0, cafetal.riego).cafeRed, same(rec.cafeRed));
      expect(
        calcular(clima.sublist(15)).cafeRed?.motivo,
        MotivoCafe.historialClimaticoInsuficiente,
      );
      final riegoReciente = RegistroRiego(
        loteId: 'lote',
        fecha: hoy,
        rego: true,
        laminaMm: 20,
      );
      expect(
        calcular(clima, riegos: [riegoReciente]).cafeRed?.motivo,
        MotivoCafe.riegoReciente,
      );
    },
  );
}
