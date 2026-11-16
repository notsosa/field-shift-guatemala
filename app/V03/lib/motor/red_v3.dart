/// Inferencia en Dart del `NeuralPolicy.forward` entrenado de Field Shift V3.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

class EntradaLoteV3 {
  const EntradaLoteV3({
    required this.estatico,
    required this.recientes,
    required this.historia,
    required this.contexto,
    required this.candidatas,
    required this.base,
    required this.recientesValidos,
    required this.historiaValida,
    required this.factibles,
    this.activo = true,
  });

  final List<double> estatico, contexto, base;
  final List<List<double>> recientes, historia, candidatas;
  final List<bool> recientesValidos, historiaValida, factibles;
  final bool activo;

  void _verificarDimensiones() {
    if (estatico.length != 24 ||
        contexto.length != 59 ||
        !_tieneForma(recientes, 28, 12) ||
        !_tieneForma(historia, 32, 16) ||
        !_tieneForma(candidatas, RedV3.acciones, 45) ||
        recientesValidos.length != 28 ||
        historiaValida.length != 32 ||
        base.length != RedV3.acciones ||
        factibles.length != RedV3.acciones) {
      throw ArgumentError('Las dimensiones del lote no corresponden a V3.');
    }
  }

  static bool _tieneForma(List<List<double>> filas, int alto, int ancho) =>
      filas.length == alto && filas.every((fila) => fila.length == ancho);
}

class RedV3 {
  RedV3._(Float32List pesos) {
    // Mismo orden que NeuralPolicy.named_parameters(). Cada secuencia empieza
    // con el vector aprendido para un historial sin observaciones.
    final origen = _LectorPesos(pesos);
    _estatico = _Codificador(origen, 24);
    _recientes = _Secuencia(origen, 12);
    _historia = _Secuencia(origen, 16);
    _finanzas = _Codificador(origen, 59);
    _fusion = origen.densa(128, 64);
    _residuales = [_Residual(origen), _Residual(origen)];
    _proyectarLotes = origen.densa(64, 192);
    _proyectarContexto = origen.densa(64, 64, conSesgo: false);
    _accion = _Codificador(origen, 45);
    _puntaje1 = origen.densa(160, 64);
    _puntaje2 = origen.densa(64, 32);
    _puntaje3 = origen.densa(32, 1);
    if (origen.posicion != cantidadPesos) {
      throw StateError('La arquitectura V3 no consumió todos los pesos.');
    }
  }

  static const acciones = 25;
  static const cantidadPesos = 72099;
  static const semilla = 17;
  static const generacion = 60;
  static const rutaAsset = 'assets/modelos/field_shift_v3.f32';
  static const sha256Checkpoint =
      'e2bf12901e4a67f7aee3d891df5679d4fa7fe6ec53ac87fe260940221cdbd7d8';
  static const sha256Asset =
      'd60a22b7e73ecf1610a4bc50336dca98983be7ab3b5d7098d995d13d0ae2889f';

  late final _Codificador _estatico, _finanzas, _accion;
  late final _Secuencia _recientes, _historia;
  late final List<_Residual> _residuales;
  late final _Densa _fusion, _proyectarLotes, _proyectarContexto;
  late final _Densa _puntaje1, _puntaje2, _puntaje3;

  static Future<RedV3> cargar([AssetBundle? bundle]) async =>
      RedV3.desdeBytes(await (bundle ?? rootBundle).load(rutaAsset));

  factory RedV3.desdeBytes(ByteData bytes) {
    if (bytes.lengthInBytes != cantidadPesos * Float32List.bytesPerElement) {
      throw const FormatException('El archivo de pesos V3 está incompleto.');
    }
    final pesos = Float32List(cantidadPesos);
    for (var i = 0; i < pesos.length; i++) {
      final valor = bytes.getFloat32(
        i * Float32List.bytesPerElement,
        Endian.little,
      );
      if (!valor.isFinite) {
        throw const FormatException(
          'El archivo de pesos V3 contiene valores inválidos.',
        );
      }
      pesos[i] = valor;
    }
    return RedV3._(pesos);
  }

  /// Puntajes en el orden del catálogo. Una acción inviable vale -infinito.
  List<List<double>> puntuar(List<EntradaLoteV3> lotes) {
    for (final lote in lotes) {
      lote._verificarDimensiones();
    }
    final latentes = [
      for (final lote in lotes)
        if (lote.activo) _representacion(lote) else null,
    ];
    final proyectados = [
      for (final latente in latentes)
        if (latente != null) _proyectarLotes.evaluar(latente) else null,
    ];
    return [
      for (var i = 0; i < lotes.length; i++)
        if (latentes[i] case final List<double> latente)
          _puntuarLote(lotes[i], latente, _atencion(i, proyectados))
        else
          List<double>.filled(acciones, double.negativeInfinity),
    ];
  }

  List<double> _representacion(EntradaLoteV3 lote) {
    List<double> representacion = _activar(
      _fusion.evaluar([
        ..._estatico.evaluar(lote.estatico),
        ..._recientes.evaluar(lote.recientes, lote.recientesValidos),
        ..._historia.evaluar(lote.historia, lote.historiaValida),
        ..._finanzas.evaluar(lote.contexto),
      ]),
    );
    for (final capa in _residuales) {
      representacion = capa.evaluar(representacion);
    }
    return representacion;
  }

  List<double> _atencion(int destino, List<List<double>?> proyectados) {
    const cabezas = 4;
    const ancho = 16;
    const bloque = cabezas * ancho;
    final contexto = Float64List(bloque);
    if (proyectados.length == 1) return contexto;
    final consulta = proyectados[destino]!;
    final logits = Float64List(proyectados.length);
    for (var cabeza = 0; cabeza < cabezas; cabeza++) {
      final inicio = cabeza * ancho;
      // El vecino nulo del modelo aporta logit cero y un vector de ceros.
      var maximo = 0.0;
      for (var origen = 0; origen < proyectados.length; origen++) {
        final vecino = proyectados[origen];
        if (origen == destino || vecino == null) continue;
        var producto = 0.0;
        for (var j = 0; j < ancho; j++) {
          producto += consulta[inicio + j] * vecino[bloque + inicio + j];
        }
        final logit = producto / 4;
        logits[origen] = logit;
        maximo = math.max(maximo, logit);
      }
      var total = math.exp(-maximo);
      for (var origen = 0; origen < proyectados.length; origen++) {
        final vecino = proyectados[origen];
        if (origen == destino || vecino == null) continue;
        final peso = math.exp(logits[origen] - maximo);
        total += peso;
        for (var j = 0; j < ancho; j++) {
          contexto[inicio + j] += peso * vecino[2 * bloque + inicio + j];
        }
      }
      for (var j = 0; j < ancho; j++) {
        contexto[inicio + j] /= total;
      }
    }
    return _proyectarContexto.evaluar(contexto);
  }

  List<double> _puntuarLote(
    EntradaLoteV3 lote,
    List<double> latente,
    List<double> contexto,
  ) {
    final puntajes = List<double>.filled(acciones, double.negativeInfinity);
    final entrada = Float64List(160)
      ..setAll(0, latente)
      ..setAll(64, contexto);
    for (var i = 0; i < acciones; i++) {
      if (!lote.factibles[i]) continue;
      entrada.setAll(128, _accion.evaluar(lote.candidatas[i]));
      final oculta1 = _activar(_puntaje1.evaluar(entrada));
      final oculta2 = _activar(_puntaje2.evaluar(oculta1));
      final delta = _puntaje3.evaluar(oculta2).single;
      final e = math.exp(-2 * delta.abs());
      final magnitud = (1 - e) / (1 + e);
      final puntaje = lote.base[i] + (delta.isNegative ? -magnitud : magnitud);
      if (!puntaje.isFinite) {
        throw StateError('V3 recibió datos que producen un puntaje no válido.');
      }
      puntajes[i] = puntaje;
    }
    return puntajes;
  }
}

class _LectorPesos {
  _LectorPesos(this.datos);

  final Float32List datos;
  var posicion = 0;

  Float32List leer(int cantidad) {
    final vista = Float32List.sublistView(datos, posicion, posicion + cantidad);
    posicion += cantidad;
    return vista;
  }

  _Densa densa(int entradas, int salidas, {bool conSesgo = true}) => _Densa(
    entradas,
    salidas,
    leer(entradas * salidas),
    conSesgo ? leer(salidas) : null,
  );
}

class _Densa {
  const _Densa(this.entradas, this.salidas, this.pesos, this.sesgo);

  final int entradas, salidas;
  final Float32List pesos;
  final Float32List? sesgo;

  Float64List evaluar(List<double> vector) {
    final salida = Float64List(salidas);
    final bias = sesgo;
    for (var i = 0; i < salidas; i++) {
      var suma = bias?[i] ?? 0.0;
      final fila = i * entradas;
      for (var j = 0; j < entradas; j++) {
        suma += pesos[fila + j] * vector[j];
      }
      salida[i] = suma;
    }
    return salida;
  }
}

double _silu(double valor) => valor / (1 + math.exp(-valor));

Float64List _activar(Float64List datos) {
  for (var i = 0; i < datos.length; i++) {
    datos[i] = _silu(datos[i]);
  }
  return datos;
}

class _Codificador {
  _Codificador(_LectorPesos origen, int entradas)
    : _oculta = origen.densa(entradas, 64),
      _salida = origen.densa(64, 32);

  final _Densa _oculta, _salida;

  List<double> evaluar(List<double> datos) =>
      _salida.evaluar(_activar(_oculta.evaluar(datos)));
}

class _Secuencia {
  _Secuencia(_LectorPesos origen, int entradas)
    : _ausente = origen.leer(32),
      _valor = origen.densa(entradas, 32),
      _posicion = origen.densa(2, 32, conSesgo: false),
      _puntaje = origen.densa(32, 1),
      _salida = origen.densa(32, 32);

  final Float32List _ausente;
  final _Densa _valor, _posicion, _puntaje, _salida;

  List<double> evaluar(List<List<double>> datos, List<bool> validos) {
    final vectores = <List<double>>[];
    final logits = <double>[];
    var maximo = double.negativeInfinity;
    for (var i = 0; i < datos.length; i++) {
      if (!validos[i]) continue;
      final tiempo = -1 + i / (datos.length - 1);
      final valor = _valor.evaluar(datos[i]);
      final posicion = _posicion.evaluar([tiempo, tiempo * tiempo]);
      for (var j = 0; j < valor.length; j++) {
        valor[j] = _silu(valor[j] + posicion[j]);
      }
      final logit = _puntaje.evaluar(valor).single;
      vectores.add(valor);
      logits.add(logit);
      maximo = math.max(maximo, logit);
    }
    if (vectores.isEmpty) return _ausente;

    final combinado = Float64List(32);
    var total = 0.0;
    for (var i = 0; i < vectores.length; i++) {
      final peso = math.exp(logits[i] - maximo);
      total += peso;
      for (var j = 0; j < combinado.length; j++) {
        combinado[j] += vectores[i][j] * peso;
      }
    }
    for (var j = 0; j < combinado.length; j++) {
      combinado[j] /= total;
    }
    return _salida.evaluar(combinado);
  }
}

class _Residual {
  _Residual(_LectorPesos origen)
    : _escala = origen.leer(64),
      _centro = origen.leer(64),
      _oculta = origen.densa(64, 64),
      _salida = origen.densa(64, 64);

  final Float32List _escala, _centro;
  final _Densa _oculta, _salida;

  List<double> evaluar(List<double> entrada) {
    final media = entrada.reduce((a, b) => a + b) / entrada.length;
    var varianza = 0.0;
    for (final valor in entrada) {
      final diferencia = valor - media;
      varianza += diferencia * diferencia;
    }
    final desvio = math.sqrt(varianza / entrada.length + 1e-5);
    final normalizado = Float64List(entrada.length);
    for (var i = 0; i < entrada.length; i++) {
      normalizado[i] =
          ((entrada[i] - media) / desvio) * _escala[i] + _centro[i];
    }
    final salida = _salida.evaluar(_activar(_oculta.evaluar(normalizado)));
    for (var i = 0; i < salida.length; i++) {
      salida[i] += entrada[i];
    }
    return salida;
  }
}
