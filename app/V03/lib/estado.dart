/// Estado de la finca; escritura versionada y geometría geográfica canónica.
library;

import 'package:flutter/widgets.dart';

import 'dart:async';
import 'dart:math' as math;
import 'dart:convert';

import 'eventos.dart';

import 'datos/almacen.dart';
import 'datos/clima.dart';
import 'datos/mapa.dart';
import 'datos/terreno.dart';
import 'modelos.dart';
import 'motor/recomendador.dart';
import 'textos.dart';

export 'datos/terreno.dart';

enum ResultadoSync { ok, sinWifi, error }

class AppEstado extends ChangeNotifier {
  AppEstado(
    this._almacen, {
    ServicioClima? servicioClima,
    ServicioMapa? servicioMapa,
    DateTime Function()? reloj,
  }) : _servicio = servicioClima ?? ServicioClima(),
       _reloj = reloj ?? DateTime.now {
    mapa = servicioMapa ?? ServicioMapa(_almacen, hayWifi: _servicio.hayWifi);
    unidad = Unidad.values.firstWhere(
      (u) => u.name == _almacen.leerUnidad(),
      orElse: () => Unidad.manzanas,
    );
    final capaGuardada = _almacen.leerCapa();
    capa = capaGuardada == 'croquis'
        ? CapaMapa.relieve3d
        : CapaMapa.values.firstWhere(
            (c) => c.name == capaGuardada,
            orElse: () => CapaMapa.mapa,
          );
    clima = _almacen.leerClima();
    ultimaSync = _almacen.leerUltimaSincronizacion();
    idioma = _almacen.leerIdioma() ?? 'es';
    // Un estado ilegible no impide abrir: se respalda su texto y se cae al
    // siguiente (V3 → V2 → claves antiguas).
    var cargado = false;
    for (final (clave, j) in _almacen.candidatosFinca()) {
      try {
        _cargarJson(j);
        cargado = true;
        break;
      } catch (_) {
        _almacen.respaldarDanada(clave);
      }
    }
    if (!cargado) {
      parcela = _almacen.leerParcela();
      campanias = _almacen.leerPlantaciones();
      todosLosRegistros = _almacen.leerRegistros();
      _seleccionada = _almacen.leerSeleccionada();
    }
    if (parcela != null && parcela!.id.isEmpty) {
      parcela = parcela!.con(id: _nuevaFincaId());
    }
    // La migración conserva los datos antiguos y asigna identidades una sola vez.
    final ids = campanias
        .where((p) => p.id.isNotEmpty)
        .map((p) => p.id)
        .toSet();
    var n = 1;
    campanias = [
      for (var p in campanias)
        (() {
          if (p.id.isEmpty) {
            while (ids.contains('p$n')) {
              n++;
            }
            p = p.conId('p$n');
            ids.add(p.id);
          }
          return p.loteId.isEmpty
              ? p.conLote('${parcela?.id ?? 'sin-finca'}-lote-${p.id}')
              : p;
        })(),
    ];
    final finca = parcela;
    if (finca != null) {
      if (finca.geometria.isEmpty && finca.contorno.isNotEmpty) {
        parcela = finca.con(geometria: finca.marco.aGeografico(finca.contorno));
      }
      for (final p in campanias) {
        if (lotePorId(p.loteId) == null) {
          lotes.add(
            Lote(
              id: p.loteId,
              geometria: finca.marco.aGeografico(p.contorno),
              origen: 'migrado-del-plano',
            ),
          );
        }
      }
      _proyectar();
    }
    if (campanias.isNotEmpty) {
      todosLosRegistros = [
        for (final r in todosLosRegistros)
          r.plantacionId.isEmpty ? r.conPlantacion(campanias.first.id) : r,
      ];
    }
    // Un riego V2 se asocia solo cuando su lote y fecha identifican una campaña.
    riegosDiarios = [
      for (final r in riegosDiarios)
        (() {
          if (r.campaniaId.isNotEmpty) return r;
          final candidatas = campanias
              .where(
                (p) =>
                    p.loteId == r.loteId &&
                    !soloFecha(r.fecha).isBefore(soloFecha(p.fecha)) &&
                    (p.fin == null ||
                        !soloFecha(r.fecha).isAfter(soloFecha(p.fin!))),
              )
              .toList();
          return candidatas.length == 1
              ? RegistroRiego.deJson({
                  ...r.aJson(),
                  'campania': candidatas.single.id,
                })
              : r;
        })(),
    ];
    // Si la escritura de arranque falla, la app abre con los datos en memoria
    // y la siguiente escritura vuelve a intentarlo (siempre guarda todo).
    _escritura = _guardarSnapshot().catchError((Object _) {});
    preparada = Future.wait<void>([_escritura, ..._almacen.respaldos])
        .then((_) {});
  }

  /// Datos del estado de finca; no modifica nada si algún dato es inválido.
  void _cargarJson(Map<String, dynamic> j) {
    List<T> lista<T>(String k, T Function(Map<String, dynamic>) f) => [
      for (final x in j[k] as List? ?? const []) f(x as Map<String, dynamic>),
    ];
    final p = j['parcela'] == null
        ? null
        : Parcela.deJson(j['parcela'] as Map<String, dynamic>);
    final c = lista('plantaciones', Plantacion.deJson);
    final l = lista('lotes', Lote.deJson);
    final r = lista('registros', RegistroSemanal.deJson);
    final su = lista('suministros', SuministroAgua.deJson);
    final rd = lista('riegosDiarios', RegistroRiego.deJson);
    final cl = j.containsKey('clima') ? lista('clima', DiaClima.deJson) : null;
    final us = j.containsKey('ultimaSync') && j['ultimaSync'] != null
        ? DateTime.parse(j['ultimaSync'] as String)
        : null;
    final ev = lista('eventos', Evento.deJson);
    final sel = j['seleccionada'] as String?;
    parcela = p;
    campanias = c;
    lotes = l;
    todosLosRegistros = r;
    suministros = su;
    riegosDiarios = rd;
    if (cl != null) clima = cl;
    if (j.containsKey('ultimaSync')) ultimaSync = us;
    _seleccionada = sel;
    _eventos = ev;
  }

  final Almacen _almacen;
  final ServicioClima _servicio;
  final DateTime Function() _reloj;
  late final Future<void> preparada;

  /// Verdadero si la última escritura falló: los datos están solo en memoria
  /// hasta que una escritura posterior tenga éxito.
  bool sinGuardar = false;
  Future<void> _escritura = Future.value();
  late final ServicioMapa mapa;
  CapaMapa capa = CapaMapa.mapa;
  Unidad unidad = Unidad.manzanas;
  Parcela? parcela;
  List<Plantacion> campanias = [];
  List<Plantacion> get plantaciones =>
      campanias.where((p) => p.activa).toList();
  List<Evento> _eventos = [];
  List<Lote> lotes = [];
  List<RegistroSemanal> todosLosRegistros = [];
  List<SuministroAgua> suministros = [];
  List<RegistroRiego> riegosDiarios = [];
  List<DiaClima> clima = [];
  DateTime? ultimaSync;
  String idioma = 'es';
  bool sincronizando = false;
  MallaTerreno? _terreno;
  bool cargandoTerreno = false;
  String? _seleccionada;
  final _recomendaciones = <String, Recomendacion>{};
  final _enCurso = <String>{};

  /// Ignora una segunda llamada mientras la primera sigue en curso (doble
  /// toque), para no duplicar registros.
  Future<void> _unaVez(String clave, Future<void> Function() accion) async {
    if (!_enCurso.add(clave)) return;
    try {
      await accion();
    } finally {
      _enCurso.remove(clave);
    }
  }

  DateTime? _fechaCalculo;

  Txt get txt => Txt(idioma == 'en', manzanas: unidad == Unidad.manzanas);
  DateTime get hoy => _reloj();
  bool get configurada => parcela != null && campanias.isNotEmpty;
  Plantacion? get plantacion => plantaciones.isEmpty
      ? null
      : plantaciones.firstWhere(
          (p) => p.id == _seleccionada,
          orElse: () => plantaciones.first,
        );
  Plantacion? plantacionPorId(String? id) {
    for (final p in campanias) {
      if (p.id == id) return p;
    }
    return null;
  }

  Lote? lotePorId(String id) {
    for (final l in lotes) {
      if (l.id == id) return l;
    }
    return null;
  }

  SuministroAgua? suministroDe(DateTime fecha) {
    for (final s in suministros) {
      if (soloFecha(s.fecha) == soloFecha(fecha)) return s;
    }
    return null;
  }

  RegistroRiego? riegoDe(String lote, DateTime fecha, {String? campaniaId}) {
    for (final r in riegosDiarios) {
      if (r.loteId == lote &&
          (campaniaId == null || r.campaniaId == campaniaId) &&
          soloFecha(r.fecha) == soloFecha(fecha)) {
        return r;
      }
    }
    return null;
  }

  List<RegistroSemanal> registrosDe(String id) =>
      todosLosRegistros.where((r) => r.plantacionId == id).toList();
  List<RegistroSemanal> get registros =>
      plantacion == null ? [] : registrosDe(plantacion!.id);

  Map<String, dynamic> _snapshot() => {
    'version': 3,
    'parcela': parcela?.aJson(),
    'plantaciones': campanias.map((p) => p.aJson()).toList(),
    'lotes': lotes.map((l) => l.aJson()).toList(),
    'registros': todosLosRegistros.map((r) => r.aJson()).toList(),
    'suministros': suministros.map((s) => s.aJson()).toList(),
    'riegosDiarios': riegosDiarios.map((r) => r.aJson()).toList(),
    'clima': clima.map((x) => x.aJson()).toList(),
    'ultimaSync': ultimaSync?.toIso8601String(),
    'eventos': _eventos.map((x) => x.aJson()).toList(),
    'seleccionada': _seleccionada,
  };
  Future<void> _guardarSnapshot() async {
    try {
      await _almacen.guardarEstadoFinca(_snapshot());
      sinGuardar = false;
    } catch (_) {
      sinGuardar = true;
      rethrow;
    }
  }

  Future<void> _persistir() {
    final proxima = _escritura
        .catchError((Object _) {})
        .then((_) => _guardarSnapshot());
    _escritura = proxima;
    return proxima;
  }

  bool _mismosPuntos(List<Punto> a, List<Punto> b) =>
      a.length == b.length &&
      [
        for (var i = 0; i < a.length; i++)
          (a[i].x - b[i].x).abs() <= 1e-10 && (a[i].y - b[i].y).abs() <= 1e-10,
      ].every((v) => v);
  void _cambio() {
    _recomendaciones.clear();
    notifyListeners();
  }

  void _proyectar() {
    final p = parcela;
    if (p == null) return;
    parcela = p.con(contorno: p.marco.aPlano(p.geometria));
    campanias = [
      for (final x in campanias)
        x.conContorno(
          p.marco.aPlano(lotePorId(x.loteId)?.geometria ?? const []),
        ),
    ];
  }

  Recomendacion recomendacionDe(Plantacion p) {
    if (parcela == null) return Recomendacion.vacia;
    if (_fechaCalculo != soloFecha(hoy)) {
      _recomendaciones.clear();
      _fechaCalculo = soloFecha(hoy);
    }
    if (_recomendaciones.isEmpty) {
      final suministro = suministroDe(hoy);
      for (final x in plantaciones) {
        _recomendaciones[x.id] = recomendar(
          parcela: parcela!,
          plantacion: x,
          clima: clima,
          registros: registrosDe(x.id),
          hoy: hoy,
          disponibilidad:
              suministro?.disponibilidad ?? DisponibilidadAgua.desconocida,
          eventos: _eventos.where((e) => e.campaniaId == x.id).toList(),
          riegosDiarios: riegosDiarios
              .where((r) => r.campaniaId == x.id)
              .toList(),
        );
      }
      final volumen = suministro?.volumenM3;
      if (volumen != null &&
          suministro?.disponibilidad == DisponibilidadAgua.si) {
        var demanda = 0.0;
        final areas = <String, double>{};
        for (final x in plantaciones) {
          final l = lotePorId(x.loteId);
          final valida =
              l != null &&
              l.geometria.isNotEmpty &&
              validarPoligono(x.contorno, lado: parcela!.lado) == null;
          final area = valida ? l.areaM2 : 0.0;
          areas[x.id] = area;
          demanda += _recomendaciones[x.id]!.riegoSugerido * area / 1000;
        }
        final factor = demanda <= 0 ? 0.0 : (volumen / demanda).clamp(0.0, 1.0);
        for (final x in plantaciones) {
          final r = _recomendaciones[x.id]!;
          if (r.riegoSugerido <= 0) continue;
          _recomendaciones[x.id] = limitarRiego(
            r,
            areas[x.id] == 0 ? 0 : r.riegoSugerido * factor,
            x.riego,
            aviso: areas[x.id] == 0
                ? Aviso.areaPendiente
                : factor < 1
                ? Aviso.capacidadLimitada
                : null,
          );
        }
      }
    }
    return _recomendaciones[p.id] ?? Recomendacion.vacia;
  }

  Recomendacion get recomendacion =>
      plantacion == null ? Recomendacion.vacia : recomendacionDe(plantacion!);

  MallaTerreno? get terreno {
    final p = parcela;
    if (p == null) return null;
    if (_terreno == null ||
        _terreno!.latitud != p.latitud ||
        _terreno!.longitud != p.longitud) {
      final dim = (p.lado / 1000.0).clamp(0.5, 10.0);
      _terreno = MallaTerreno.sintetica(
        latitud: p.latitud,
        longitud: p.longitud,
        anchoKm: dim,
        altoKm: dim,
        elevacionBase: p.elevacion,
      );
    }
    return _terreno;
  }

  ({double lat, double lon}) _centroGeografico([Plantacion? p]) {
    final finca = parcela!;
    final objetivo = p ?? plantacion;
    if (objetivo != null) {
      final l = lotePorId(objetivo.loteId);
      if (l != null && l.geometria.isNotEmpty) {
        var sLat = 0.0, sLon = 0.0;
        for (final c in l.geometria) {
          sLat += c.latitud;
          sLon += c.longitud;
        }
        return (
          lat: sLat / l.geometria.length,
          lon: sLon / l.geometria.length,
        );
      }
      if (objetivo.contorno.isNotEmpty) {
        final centro = finca.marco.aGeografico([centroDe(objetivo.contorno)]).first;
        return (lat: centro.latitud, lon: centro.longitud);
      }
    }
    return (lat: finca.latitud, lon: finca.longitud);
  }

  CuerpoAguaCercano? cuerpoAguaDe([Plantacion? p]) {
    final t = terreno;
    if (t == null || parcela == null) return null;
    final (:lat, :lon) = _centroGeografico(p);
    return t.evaluarCuerpoAguaCercano(lat, lon);
  }

  double? humedadTierraDe([Plantacion? p]) {
    if (parcela == null) return null;
    final objetivo = p ?? plantacion;
    final base = objetivo == null
        ? null
        : recomendacionDe(objetivo).humedadTierraPct;
    final t = terreno;
    if (t == null) return base;
    final (:lat, :lon) = _centroGeografico(objetivo);
    final (:fila, :col) = t.filaColDeLatLon(lat, lon);
    return t.humedadTierraEn(fila, col, baseMoistPct: base ?? 53.0);
  }

  double? pendienteDe([Plantacion? p]) {
    final t = terreno;
    if (t == null || parcela == null) return null;
    final (:lat, :lon) = _centroGeografico(p);
    final (:fila, :col) = t.filaColDeLatLon(lat, lon);
    return t.pendienteEn(fila, col);
  }

  Future<void> actualizarTerreno({double? anchoKm, double? altoKm}) async {
    final p = parcela;
    if (p == null || cargandoTerreno) return;
    cargandoTerreno = true;
    notifyListeners();
    try {
      final dim = (p.lado / 1000.0).clamp(0.5, 10.0);
      final malla = await ServicioTerreno().cargar(
        latitud: p.latitud,
        longitud: p.longitud,
        anchoKm: anchoKm ?? dim,
        altoKm: altoKm ?? dim,
        elevacionBase: p.elevacion,
      );
      if (parcela?.latitud == p.latitud && parcela?.longitud == p.longitud) {
        _terreno = malla;
      }
    } finally {
      cargandoTerreno = false;
      notifyListeners();
    }
  }

  String _nuevoId() => 'campania-${_nuevaFincaId()}';

  String _nuevaFincaId() =>
      'finca-${DateTime.now().microsecondsSinceEpoch.toRadixString(16)}-${math.Random.secure().nextInt(0x100000000).toRadixString(16)}';
  String _nuevoLoteId() {
    var n = 1;
    final prefijo = '${parcela!.id}-lote-';
    while (lotes.any((l) => l.id == '$prefijo$n')) {
      n++;
    }
    return '$prefijo$n';
  }

  ErrorGeometria? validarTrazo(
    List<Punto> puntos, {
    bool finca = false,
    String? excepto,
    double? lado,
    List<Punto>? fincaPendiente,
  }) {
    final p = parcela!;
    final marco = MarcoPlano(p.latitud, p.longitud, lado ?? p.lado);
    // Un lote sin campañas o con un trazo ya inválido no debe bloquear al resto.
    bool cuenta(Lote x) => campanias.any((c) => c.loteId == x.id);
    if (finca) {
      final e = validarPoligono(puntos, lado: marco.lado);
      if (e != null) return e;
      for (final x in lotes) {
        if (!cuenta(x)) continue;
        final c = marco.aPlano(x.geometria);
        if (c.isEmpty || validarPoligono(c, lado: marco.lado) != null) continue;
        if (validarPoligono(c, lado: marco.lado, finca: puntos) ==
            ErrorGeometria.fueraFinca) {
          return ErrorGeometria.fueraFinca;
        }
      }
      return null;
    }
    return validarPoligono(
      puntos,
      lado: marco.lado,
      finca: fincaPendiente ?? marco.aPlano(p.geometria),
      otros: [
        for (final x in lotes)
          if (x.id != plantacionPorId(excepto)?.loteId && cuenta(x))
            marco.aPlano(x.geometria),
      ],
    );
  }

  Future<void> guardarParcela(Parcela p) async {
    final anterior = parcela;
    final cambio =
        anterior == null ||
        anterior.latitud != p.latitud ||
        anterior.longitud != p.longitud;
    // Una corrección del centro cambia la vista y el clima, nunca los lotes.
    parcela = p.con(
      id: anterior?.id ?? (p.id.isEmpty ? _nuevaFincaId() : p.id),
      geometria:
          anterior?.geometria ??
          (p.geometria.isNotEmpty
              ? p.geometria
              : p.marco.aGeografico(p.contorno)),
    );
    _proyectar();
    if (cambio) {
      clima = [];
      ultimaSync = null;
      _terreno = null;
      await _almacen.guardarClima(clima);
    }
    await _persistir();
    _cambio();
  }

  Future<void> guardarContornoFinca(List<Punto> contorno) =>
      guardarFinca(contorno: contorno, lado: parcela!.lado);
  Future<void> cambiarUnidad(Unidad nueva) async {
    unidad = nueva;
    await _almacen.guardarUnidad(nueva.name);
    notifyListeners();
  }

  Future<void> cambiarCapa(CapaMapa nueva) async {
    capa = nueva;
    await _almacen.guardarCapa(nueva.name);
    notifyListeners();
  }

  Future<void> cambiarLado(double nuevo) async {
    if (parcela == null || parcela!.lado == nuevo) return;
    parcela = parcela!.con(lado: nuevo);
    _proyectar();
    await _persistir();
    _cambio();
  }

  Future<void> guardarFinca({
    required List<Punto> contorno,
    required double lado,
  }) async {
    final p = parcela!;
    final marco = MarcoPlano(p.latitud, p.longitud, lado);
    // Si solo cambia el ancho del plano, el contorno es el mismo terreno: no
    // hay nada que revalidar.
    final mismoContorno =
        contorno.isNotEmpty &&
        _mismosPuntos(contorno, marco.aPlano(p.geometria));
    if (contorno.isNotEmpty && !mismoContorno) {
      final error = validarTrazo(contorno, finca: true, lado: lado);
      if (error != null) throw FormatException(txt.errorGeometria(error));
    }
    parcela = p.con(
      lado: lado,
      geometria: contorno.isEmpty || mismoContorno
          ? p.geometria
          : marco.aGeografico(contorno),
    );
    _proyectar();
    await _persistir();
    _cambio();
  }

  Future<void> guardarPlantacion(
    Plantacion p, {
    List<Punto>? fincaNueva,
    double? lado,
  }) => _unaVez(
    'plantacion',
    () => _guardarPlantacion(p, fincaNueva: fincaNueva, lado: lado),
  );

  Future<void> _guardarPlantacion(
    Plantacion p, {
    List<Punto>? fincaNueva,
    double? lado,
  }) async {
    validarCampania(p);
    final anterior = plantacionPorId(p.id);
    if (anterior != null && !anterior.activa) {
      throw FormatException(
        txt.bilingue('La campaña está cerrada', 'The campaign is closed'),
      );
    }
    if (anterior != null) {
      // Los eventos derivados de la ficha (p. ej. el «fertilizó» inicial) se
      // reconstruyen con la ficha nueva; solo el historial detallado bloquea.
      if (anterior.cultivoId != p.cultivoId &&
          (_eventos.any((e) => e.campaniaId == p.id) ||
              registrosDe(p.id).isNotEmpty ||
              riegosDiarios.any((r) => r.campaniaId == p.id))) {
        throw FormatException(
          txt.bilingue(
            'Cierra esta campaña e inicia otra para cambiar de cultivo conservando el historial.',
            'Close this campaign and start another to change the crop while keeping the history.',
          ),
        );
      }
      for (final e in _eventos.where((e) => e.campaniaId == p.id)) {
        validarEvento(e, destinos: [p]);
      }
      if (riegosDiarios.any(
        (r) =>
            r.campaniaId == p.id &&
            soloFecha(r.fecha).isBefore(soloFecha(p.fecha)),
      )) {
        throw FormatException(
          txt.bilingue(
            'La siembra no puede ser posterior a sus riegos.',
            'Planting cannot be later than its irrigation records.',
          ),
        );
      }
    }
    if (anterior != null) {
      // La campaña editada no puede empezar antes del cierre de la previa del
      // mismo lote, ni (si está cerrada) terminar después de la siembra de la
      // siguiente.
      for (final x in campanias) {
        if (x.id == p.id || x.loteId != anterior.loteId) continue;
        if (soloFecha(x.fecha).isBefore(soloFecha(anterior.fecha))) {
          if (x.fin == null || soloFecha(p.fecha).isBefore(soloFecha(x.fin!))) {
            throw FormatException(
              txt.bilingue(
                'La siembra debe ser posterior al cierre anterior',
                'Planting must not be before the previous campaign closed',
              ),
            );
          }
        } else if (p.fin != null &&
            soloFecha(p.fin!).isAfter(soloFecha(x.fecha))) {
          throw FormatException(
            txt.bilingue(
              'El cierre no puede ser posterior a la siembra de la campaña siguiente.',
              'The closing date cannot be after the next campaign planting.',
            ),
          );
        }
      }
    }
    final mismoLote = lotePorId(anterior?.loteId ?? p.loteId);
    if (anterior == null && p.loteId.isNotEmpty) {
      if (mismoLote == null || plantaciones.any((x) => x.loteId == p.loteId)) {
        throw FormatException(
          txt.bilingue(
            'El lote ya tiene una campaña activa',
            'The plot already has an active campaign',
          ),
        );
      }
      for (final x in campanias.where((x) => x.loteId == p.loteId)) {
        if (x.fin == null || soloFecha(p.fecha).isBefore(soloFecha(x.fin!))) {
          throw FormatException(
            txt.bilingue(
              'La siembra debe ser posterior al cierre anterior',
              'Planting must not be before the previous campaign closed',
            ),
          );
        }
      }
    }
    final marco = MarcoPlano(
      parcela!.latitud,
      parcela!.longitud,
      lado ?? parcela!.lado,
    );
    if (fincaNueva != null && fincaNueva.isNotEmpty) {
      final error = validarTrazo(fincaNueva, finca: true, lado: marco.lado);
      if (error != null) throw FormatException(txt.errorGeometria(error));
    }
    final sinCambios =
        mismoLote != null &&
        _mismosPuntos(p.contorno, marco.aPlano(mismoLote.geometria));
    if (p.contorno.isNotEmpty && !sinCambios) {
      final error = validarTrazo(
        p.contorno,
        excepto: p.id,
        lado: marco.lado,
        fincaPendiente: fincaNueva != null && fincaNueva.isNotEmpty
            ? fincaNueva
            : null,
      );
      if (error != null) throw FormatException(txt.errorGeometria(error));
    }
    final loteId =
        anterior?.loteId ?? (p.loteId.isNotEmpty ? p.loteId : _nuevoLoteId());
    final guardada = p.conId(p.id.isEmpty ? _nuevoId() : p.id).conLote(loteId);
    final anteriorLote = lotePorId(loteId);
    final iguales =
        anteriorLote != null &&
        _mismosPuntos(p.contorno, marco.aPlano(anteriorLote.geometria));
    final lote = iguales
        ? anteriorLote
        : Lote(id: loteId, geometria: marco.aGeografico(p.contorno));
    lotes = anteriorLote == null
        ? [...lotes, lote]
        : [for (final l in lotes) l.id == loteId ? lote : l];
    parcela = parcela!.con(
      lado: marco.lado,
      geometria: fincaNueva != null && fincaNueva.isNotEmpty
          ? marco.aGeografico(fincaNueva)
          : parcela!.geometria,
    );
    campanias = anterior == null
        ? [...campanias, guardada]
        : [for (final x in campanias) x.id == guardada.id ? guardada : x];
    _seleccionada = guardada.id;
    _proyectar();
    await _persistir();
    _cambio();
  }

  Future<void> borrarPlantacion(String id) async {
    final borrada = plantacionPorId(id);
    campanias = campanias.where((p) => p.id != id).toList();
    todosLosRegistros = todosLosRegistros
        .where((r) => r.plantacionId != id)
        .toList();
    if (_seleccionada == id) {
      _seleccionada = plantaciones.isEmpty ? null : plantaciones.first.id;
    }
    _eventos.removeWhere((x) => x.campaniaId == id);
    riegosDiarios.removeWhere((x) => x.campaniaId == id);
    // Un lote sin ninguna campaña ya no representa nada: se borra con ella
    // (y con sus riegos sueltos) para que no bloquee trazos nuevos.
    final loteId = borrada?.loteId;
    if (loteId != null && !campanias.any((p) => p.loteId == loteId)) {
      lotes = lotes.where((l) => l.id != loteId).toList();
      riegosDiarios.removeWhere((x) => x.loteId == loteId);
    }
    await _persistir();
    _cambio();
  }

  Future<void> seleccionar(String id) async {
    if (_seleccionada == id || plantacionPorId(id) == null) return;
    _seleccionada = id;
    await _persistir();
    notifyListeners();
  }

  Future<void> guardarRegistro(RegistroSemanal r) async {
    final p = plantacionPorId(r.plantacionId);
    if (p == null ||
        r.riegos < 0 ||
        r.riegos > 14 ||
        soloFecha(r.fecha).isBefore(soloFecha(p.fecha)) ||
        soloFecha(r.fecha).isAfter(soloFecha(p.fin ?? hoy))) {
      throw FormatException(
        txt.bilingue('Resumen semanal inválido', 'Invalid weekly summary'),
      );
    }
    todosLosRegistros = [
      ...todosLosRegistros.where(
        (x) =>
            x.plantacionId != r.plantacionId ||
            soloFecha(x.fecha) != soloFecha(r.fecha),
      ),
      r,
    ]..sort((a, b) => b.fecha.compareTo(a.fecha));
    await _persistir();
    _cambio();
  }

  Future<void> borrarRegistro(RegistroSemanal r) async {
    todosLosRegistros = todosLosRegistros.where((x) => x != r).toList();
    await _persistir();
    _cambio();
  }

  /// Borra la observación de riego de una campaña en una fecha. El suministro
  /// de la finca de ese día se conserva: es compartido por todos los lotes.
  Future<void> borrarRiego(RegistroRiego r) async {
    riegosDiarios = riegosDiarios
        .where(
          (x) =>
              x.campaniaId != r.campaniaId ||
              x.loteId != r.loteId ||
              soloFecha(x.fecha) != soloFecha(r.fecha),
        )
        .toList();
    await _persistir();
    _cambio();
  }

  Future<void> guardarAgua(SuministroAgua s, RegistroRiego r) =>
      _unaVez('agua', () => _guardarAgua(s, r));

  Future<void> _guardarAgua(SuministroAgua s, RegistroRiego r) async {
    // El saldo solo tiene sentido con agua confirmada; en otro caso se guarda
    // nulo (sin error), y así todo paquete propio se puede volver a importar.
    if (s.disponibilidad != DisponibilidadAgua.si && s.volumenM3 != null) {
      s = SuministroAgua(fecha: s.fecha, disponibilidad: s.disponibilidad);
    }
    if (r.campaniaId.isEmpty) {
      final candidatas = campanias
          .where(
            (p) =>
                p.loteId == r.loteId &&
                !soloFecha(r.fecha).isBefore(soloFecha(p.fecha)) &&
                (p.fin == null ||
                    !soloFecha(r.fecha).isAfter(soloFecha(p.fin!))),
          )
          .toList();
      if (candidatas.length != 1) {
        throw FormatException(
          txt.bilingue('Elige la plantación', 'Choose the planting'),
        );
      }
      r = RegistroRiego.deJson({
        ...r.aJson(),
        'campania': candidatas.single.id,
      });
    }
    final destino = plantacionPorId(r.campaniaId);
    if (destino == null ||
        destino.loteId != r.loteId ||
        soloFecha(r.fecha).isBefore(soloFecha(destino.fecha)) ||
        destino.fin != null &&
            soloFecha(r.fecha).isAfter(soloFecha(destino.fin!))) {
      throw FormatException(
        txt.bilingue('Fecha fuera de la campaña', 'Date outside the campaign'),
      );
    }
    if (soloFecha(s.fecha) != soloFecha(r.fecha) ||
        soloFecha(s.fecha).isAfter(soloFecha(hoy)) ||
        lotePorId(r.loteId) == null ||
        s.volumenM3 != null && (!s.volumenM3!.isFinite || s.volumenM3! < 0) ||
        r.laminaMm != null &&
            (!r.laminaMm!.isFinite || r.laminaMm! <= 0 || r.rego != true)) {
      throw FormatException(txt.datosAguaInvalidos);
    }
    // Una observación sin ningún dato no se guarda y borra la que hubiera.
    final suministroVacio =
        s.disponibilidad == DisponibilidadAgua.desconocida &&
        s.volumenM3 == null;
    final riegoVacio =
        r.necesito == null && r.rego == null && r.laminaMm == null;
    suministros = [
      ...suministros.where((x) => soloFecha(x.fecha) != soloFecha(s.fecha)),
      if (!suministroVacio) s,
    ];
    riegosDiarios = [
      ...riegosDiarios.where(
        (x) =>
            x.campaniaId != r.campaniaId ||
            soloFecha(x.fecha) != soloFecha(r.fecha),
      ),
      if (!riegoVacio) r,
    ];
    await _persistir();
    _cambio();
  }

  void validarCampania(Plantacion p) {
    final min = p.proporcionMinima;
    final limite = soloFecha(p.fin ?? hoy);
    if (!catalogo.any((c) => c.id == p.cultivoId) ||
        p.ciclo <= 0 ||
        soloFecha(p.fecha).isAfter(soloFecha(hoy)) ||
        p.fin != null &&
            (soloFecha(p.fin!).isBefore(soloFecha(p.fecha)) ||
                soloFecha(p.fin!).isAfter(soloFecha(hoy))) ||
        p.plagaReciente &&
            p.inicioPlaga != null &&
            soloFecha(p.inicioPlaga!).isAfter(limite) ||
        p.fertilizo &&
            p.fechaFertilizante != null &&
            soloFecha(p.fechaFertilizante!).isAfter(limite) ||
        min != null &&
            (!p.permitirMezcla || !min.isFinite || min < 0 || min > 100)) {
      throw FormatException(
        txt.bilingue(
          'Revisa la fecha y el porcentaje del lote (0–100).',
          'Check the date and the plot percentage (0–100).',
        ),
      );
    }
  }

  Future<void> cerrarCampania(
    String id,
    DateTime fecha, {
    String motivo = '',
  }) async {
    final p = plantacionPorId(id);
    if (p == null || !p.activa) {
      throw FormatException(
        txt.bilingue('Campaña no activa', 'The campaign is not active'),
      );
    }
    final cerrada = Plantacion.deJson({
      ...p.aJson(),
      'fin': fechaIso(fecha),
      'motivoCierre': motivo,
    });
    validarCampania(cerrada);
    final fechas = <DateTime>[
      for (final e in eventosDe(id))
        if (e.orden != null) e.orden!,
      for (final r in riegosDiarios)
        if (r.campaniaId == id) r.fecha,
      for (final r in registrosDe(id)) r.fecha,
    ];
    if (fechas.any((f) => soloFecha(f).isAfter(soloFecha(fecha)))) {
      throw FormatException(
        txt.bilingue(
          'El cierre no puede ser anterior al último registro.',
          'The closing date cannot be before the latest record.',
        ),
      );
    }
    campanias = [for (final x in campanias) x.id == id ? cerrada : x];
    _seleccionada = plantaciones.isEmpty ? null : plantaciones.first.id;
    await _persistir();
    _cambio();
  }

  List<Evento> get eventos => [
    ..._eventos,
    for (final p in campanias) ...[
      if (p.plagaReciente)
        Evento(
          id: 'ficha-${p.id}-plaga',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: TipoEvento.plaga,
          fecha: p.inicioPlaga,
          severidad: p.nivelPlaga.name,
          nota: p.notaPlaga,
          origen: 'ficha-inicial',
        ),
      if (p.plagaReciente && p.plagaTratada)
        Evento(
          id: 'ficha-${p.id}-tratamiento',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: TipoEvento.tratamiento,
          producto: p.tratamientoPlaga,
          origen: 'ficha-inicial',
        ), // La ficha no preguntaba la fecha del tratamiento.
      if (p.fertilizo)
        Evento(
          id: 'ficha-${p.id}-fertilizacion',
          campaniaId: p.id,
          loteId: p.loteId,
          tipo: TipoEvento.fertilizacion,
          fecha: p.fechaFertilizante,
          producto: p.notaFertilizante,
          nota: p.tipoFertilizante.name,
          origen: 'ficha-inicial',
        ),
    ],
    for (final r in todosLosRegistros) ...[
      if (r.plaga != NivelPlaga.ninguna)
        Evento(
          id: 'semana-${r.plantacionId}-${fechaIso(r.fecha)}-plaga',
          campaniaId: r.plantacionId,
          loteId: plantacionPorId(r.plantacionId)?.loteId ?? '',
          tipo: TipoEvento.plaga,
          desde: r.fecha.subtract(const Duration(days: 6)),
          hasta: r.fecha,
          severidad: r.plaga.name,
          nota: r.notaPlaga,
          origen: 'resumen-semanal',
        ),
      if (r.fertilizo)
        Evento(
          id: 'semana-${r.plantacionId}-${fechaIso(r.fecha)}-fertilizacion',
          campaniaId: r.plantacionId,
          loteId: plantacionPorId(r.plantacionId)?.loteId ?? '',
          tipo: TipoEvento.fertilizacion,
          desde: r.fecha.subtract(const Duration(days: 6)),
          hasta: r.fecha,
          producto: r.notaFertilizante,
          origen: 'resumen-semanal',
        ),
    ],
  ];
  List<Evento> eventosDe(String id) =>
      eventos.where((e) => e.campaniaId == id).toList()..sort(
        (a, b) =>
            (b.orden ?? DateTime(1900)).compareTo(a.orden ?? DateTime(1900)),
      );
  double kilosCosechados(String id) =>
      eventosDe(id).fold(0, (n, e) => n + (e.kilos ?? 0));

  void validarEvento(Evento e, {List<Plantacion>? destinos}) {
    if (e.tipo == TipoEvento.plaga &&
        e.severidad != null &&
        !NivelPlaga.values.any((n) => n.name == e.severidad)) {
      throw FormatException(
        txt.bilingue('Severidad inválida', 'Invalid severity'),
      );
    }
    if (!e.derivado &&
        (e.id.startsWith('ficha-') || e.id.startsWith('semana-'))) {
      throw FormatException(
        txt.bilingue(
          'Identificador reservado para resúmenes',
          'Identifier reserved for summaries',
        ),
      );
    }
    final candidatas = (destinos ?? campanias)
        .where((p) => p.id == e.campaniaId)
        .toList();
    if (candidatas.length != 1 ||
        candidatas.single.loteId != e.loteId ||
        e.id.isEmpty) {
      throw FormatException(
        txt.bilingue(
          'Evento sin lote o campaña válidos',
          'Event without a valid plot or campaign',
        ),
      );
    }
    final p = candidatas.single;
    if (!e.derivado &&
        (e.fecha == null ||
            soloFecha(e.fecha!).isBefore(soloFecha(p.fecha)) ||
            soloFecha(e.fecha!).isAfter(soloFecha(p.fin ?? hoy)))) {
      throw FormatException(
        txt.bilingue(
          'La fecha debe estar dentro de la campaña.',
          'The date must fall within the campaign.',
        ),
      );
    }
    for (final v in [e.cantidad, e.profundidadCm, e.distanciaM]) {
      if (v != null && (!v.isFinite || v < 0)) {
        throw FormatException(
          txt.bilingue('Cantidad inválida', 'Invalid amount'),
        );
      }
    }
    if (e.cantidad != null && (e.unidad == null || e.unidad!.isEmpty)) {
      throw FormatException(
        txt.bilingue(
          'Indica la unidad de la cantidad.',
          'Give the unit of the amount.',
        ),
      );
    }
    if (e.unidad == '%' && e.cantidad != null && e.cantidad! > 100) {
      throw FormatException(
        txt.bilingue(
          'El porcentaje debe estar entre 0 y 100.',
          'The percentage must be between 0 and 100.',
        ),
      );
    }
    if (e.tipo == TipoEvento.cosecha &&
        (e.cantidad == null ||
            e.cantidad! <= 0 ||
            !['kg', 'g', 't', 'otra'].contains(e.unidad))) {
      throw FormatException(
        txt.bilingue(
          'Indica la cosecha y su unidad.',
          'Give the harvest and its unit.',
        ),
      );
    }
    if (e.tipo == TipoEvento.perdida) {
      if (!ReferenciaPerdida.values.any((r) => r.name == e.referencia) ||
          e.cantidad != null &&
              !(e.referencia == 'superficie'
                      ? ['%', 'm²', 'ha']
                      : ['%', 'kg', 'g', 't'])
                  .contains(e.unidad)) {
        throw FormatException(
          txt.bilingue(
            'Indica si la pérdida es de superficie, producción esperada o producto ya cosechado.',
            'Say whether the loss is of area, expected production or already harvested product.',
          ),
        );
      }
    }
    if (e.tipo == TipoEvento.observacion && e.observacion == null) {
      throw FormatException(
        txt.bilingue('Indica qué observaste.', 'Say what you observed.'),
      );
    }
    if (e.tipo == TipoEvento.observacion &&
        e.cantidad != null &&
        !(switch (e.observacion!) {
          Observacion.sombra => ['%'],
          Observacion.humedadSuelo => ['%', 'm³/m³', 'kPa'],
          Observacion.vecinos => ['%', 'plantas/m²', 'plantas/ha'],
        }).contains(e.unidad)) {
      throw FormatException(
        txt.bilingue(
          'Revisa la unidad de observación.',
          'Check the observation unit.',
        ),
      );
    }
    if (e.tipo == TipoEvento.tratamiento ||
        e.tipo == TipoEvento.fertilizacion) {
      if (e.cantidad != null &&
          (!['kg', 'g', 'L', 'mL', 'otra'].contains(e.unidad) ||
              ![
                'lote',
                'ha',
                'm²',
                'L de mezcla',
                'desconocida',
              ].contains(e.referencia))) {
        throw FormatException(
          txt.bilingue(
            'Indica la unidad y la referencia de la dosis.',
            'Give the unit and the reference of the dose.',
          ),
        );
      }
    }
  }

  Future<void> guardarEvento(Evento evento) =>
      _unaVez('evento', () => _guardarEvento(evento));

  Future<void> _guardarEvento(Evento evento) async {
    final e = evento.id.isEmpty
        ? Evento.deJson({...evento.aJson(), 'id': 'evento-${_nuevaFincaId()}'})
        : evento;
    if (e.derivado || eventos.any((x) => x.id == e.id && x.derivado)) {
      throw FormatException(
        txt.bilingue(
          'Edita este resumen desde su registro original.',
          'Edit this summary from its original record.',
        ),
      );
    }
    validarEvento(e);
    _eventos = [..._eventos.where((x) => x.id != e.id), e];
    await _persistir();
    _cambio();
  }

  Future<void> borrarEvento(String id) async {
    _eventos = _eventos.where((x) => x.id != id).toList();
    await _persistir();
    _cambio();
  }

  Future<void> cambiarIdioma(String codigo) async {
    idioma = codigo;
    await _almacen.guardarIdioma(codigo);
    _cambio();
  }

  Map<String, dynamic> exportarPaquete() => {
    'esquema': 'field-shift-finca',
    'version': 1,
    'generado': hoy.toIso8601String(),
    'datos': _snapshot(),
    'procedencia': {
      'captura':
          'declarada por productor; fechas semanales conservan intervalo',
      'clima': 'NASA POWER; punto central de finca; null significa faltante',
      'unidadesClima': {
        'x': '°C',
        'n': '°C',
        'h': '%',
        'v': 'm/s',
        'r': 'MJ/m²/día',
        'l': 'mm',
      },
      'geometria': 'WGS84; posiciones [longitud,latitud]; área esférica IUGG',
      'proporcionMinima': '% del área del lote para el cultivo actual',
      'dosis': 'cantidad en unidad original por referencia indicada',
    },
    'geografico': {
      'type': 'FeatureCollection',
      'features': [
        for (final l in lotes)
          {
            'type': 'Feature', 'id': l.id,
            'properties': {
              'origen': l.origen,
              'area_m2': l.areaM2,
              'validacion': validarPoligono(
                parcela!.marco.aPlano(l.geometria),
                lado: parcela!.lado,
                finca: parcela!.contorno,
                otros: [
                  for (final otro in lotes)
                    if (otro.id != l.id) parcela!.marco.aPlano(otro.geometria),
                ],
              )?.name,
            },
            // Se conserva el contorno original en datos.lotes aun si no se puede emitir un anillo simple.
            'geometry':
                l.geometria.isEmpty ||
                    validarPoligono(
                          parcela!.marco.aPlano(l.geometria),
                          lado: parcela!.lado,
                        ) !=
                        null
                ? null
                : poligonoGeoJson(l.geometria),
          },
      ],
    },
    'bitacora': eventos.map((x) => x.aJson()).toList(),
    'revision': {
      'contratoModelo': 'provisional; motor neuronal todavía no publicado',
      'relieve': terreno != null
          ? {
              'estado': terreno!.esRemoto
                  ? 'sincronizado-srtm'
                  : 'estimado-local',
              'fuente': terreno!.fuenteDem,
              'elevacionParcelaM':
                  (parcela?.elevacion ??
                          terreno!.elevacionEn(
                            terreno!.n ~/ 2,
                            terreno!.n ~/ 2,
                          ))
                      .round(),
              'pendienteMedianaPct': terreno!.medianaPendiente,
            }
          : {
              'estado': 'pendiente',
              'motivo':
                  'Requiere un modelo de elevación y un método de escorrentía.',
            },
      'riegosSinCampania': riegosDiarios
          .where((x) => x.campaniaId.isEmpty)
          .length,
      'lluviaFaltante': clima.where((x) => x.lluvia == null).length,
      'campanias': [
        for (final p in campanias)
          {
            'id': p.id,
            'perfil':
                p.cultivoId == 'maiz' &&
                    p.variedad.trim().toLowerCase() == 'icta b-5'
                ? 'maiz-icta-b5-reportado'
                : p.cultivoId == 'frijol' &&
                      p.variedad.trim().toLowerCase() == 'icta ligero'
                ? 'frijol-icta-ligero-reportado'
                : null,
            'estadoPerfil': 'pendiente de confirmar con el autor del modelo',
            'geometria': lotePorId(p.loteId)!.geometria.isEmpty
                ? 'faltante'
                : validarTrazo(p.contorno, excepto: p.id)?.name ?? 'valida',
            'cosechadoKg': kilosCosechados(p.id),
            'cosechasSinConversion': eventosDe(p.id)
                .where((x) => x.tipo == TipoEvento.cosecha && x.kilos == null)
                .length,
            'restricciones': {
              'mantenerCultivo': p.mantenerCultivo,
              'permitirMezcla': p.permitirMezcla,
              'proporcionMinimaPorcentajeLote': p.proporcionMinima,
            },
          },
      ],
    },
  };

  /// Prepara una combinación sin mutar el estado; un mismo ID nunca se sobrescribe.
  Map<String, dynamic> revisarPaquete(String texto) {
    try {
      final paquete = jsonDecode(texto) as Map<String, dynamic>;
      if (paquete['esquema'] != 'field-shift-finca' ||
          paquete['version'] != 1) {
        throw FormatException(
          txt.bilingue(
            'Esquema de paquete no compatible',
            'Package schema not supported',
          ),
        );
      }
      final entrante = Map<String, dynamic>.from(paquete['datos'] as Map);
      validarSnapshot(entrante);
      final actual = _snapshot();
      if (parcela != null &&
          _canon(actual['parcela']) != _canon(entrante['parcela'])) {
        throw FormatException(
          txt.bilingue(
            'El paquete pertenece a otra finca o modifica su ubicación.',
            'The package belongs to another farm or changes its location.',
          ),
        );
      }
      if (parcela == null) return entrante;
      final combinado = {...actual};
      const claves = [
        'plantaciones',
        'lotes',
        'registros',
        'suministros',
        'riegosDiarios',
        'eventos',
        'clima',
      ];
      String identidad(String clave, Map x) => switch (clave) {
        'registros' => '${x['plantacion']}/${x['fecha']}',
        'suministros' => x['fecha'] as String,
        'riegosDiarios' => '${x['campania']}/${x['lote']}/${x['fecha']}',
        'clima' => x['f'] as String,
        _ => x['id'] as String,
      };
      for (final clave in claves) {
        final filas = <String, dynamic>{
          for (final x in actual[clave] as List) identidad(clave, x as Map): x,
        };
        for (final x in entrante[clave] as List) {
          final id = identidad(clave, x as Map);
          if (filas.containsKey(id) && _canon(filas[id]) != _canon(x)) {
            throw FormatException(
              txt.bilingue(
                'Conflicto en $clave ($id). No se cambió ningún dato.',
                'Conflict in $clave ($id). No data was changed.',
              ),
            );
          }
          filas[id] = x;
        }
        combinado[clave] = filas.values.toList();
      }
      validarSnapshot(combinado);
      return combinado;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw FormatException(
        txt.bilingue(
          'Paquete incompleto o con datos inválidos',
          'Incomplete package or invalid data',
        ),
      );
    }
  }

  String _canon(dynamic valor) {
    dynamic ordenar(dynamic v) => v is Map
        ? {
            for (final k in (v.keys.cast<String>().toList()..sort()))
              k: ordenar(v[k]),
          }
        : v is List
        ? v.map(ordenar).toList()
        : v;
    return jsonEncode(ordenar(valor));
  }

  void validarSnapshot(Map<String, dynamic> j) {
    if (j['version'] != 3 || j['parcela'] == null) {
      throw FormatException(
        txt.bilingue(
          'Falta una finca versión 3',
          'A version 3 farm is missing',
        ),
      );
    }
    if (j['ultimaSync'] != null &&
        (j['ultimaSync'] is! String ||
            DateTime.tryParse(j['ultimaSync'] as String) == null)) {
      throw FormatException(
        txt.bilingue(
          'Fecha de calendario inválida',
          'Invalid calendar date',
        ),
      );
    }
    final finca = Parcela.deJson(
      Map<String, dynamic>.from(j['parcela'] as Map),
    );
    if (finca.id.isEmpty ||
        !finca.latitud.isFinite ||
        !finca.longitud.isFinite ||
        finca.latitud.abs() > 85 ||
        finca.longitud.abs() > 180 ||
        !finca.lado.isFinite ||
        finca.lado <= 0 ||
        finca.elevacion != null &&
            (!finca.elevacion!.isFinite ||
                finca.elevacion! < -500 ||
                finca.elevacion! > 9000) ||
        finca.geometria.any(
          (g) =>
              !g.latitud.isFinite ||
              !g.longitud.isFinite ||
              g.latitud.abs() > 85 ||
              g.longitud.abs() > 180,
        )) {
      throw FormatException(
        txt.bilingue('Ubicación de finca inválida', 'Invalid farm location'),
      );
    }
    List<Map<String, dynamic>> filas(String k) =>
        (j[k] as List).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    for (final clave in [
      'plantaciones',
      'eventos',
      'registros',
      'riegosDiarios',
      'suministros',
      'clima',
    ]) {
      for (final fila in filas(clave)) {
        for (final k in [
          'fecha',
          'fin',
          'inicioPlaga',
          'fechaFertilizante',
          'desde',
          'hasta',
          'f',
        ]) {
          if (fila[k] == null) continue;
          final valor = fila[k] as String,
              fecha = DateTime.tryParse(fila[k] as String);
          if (fecha == null ||
              !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(valor) ||
              fechaIso(fecha) != valor) {
            throw FormatException(
              txt.bilingue(
                'Fecha de calendario inválida',
                'Invalid calendar date',
              ),
            );
          }
        }
      }
    }
    final lotesJ = filas('lotes'), campaniasJ = filas('plantaciones');
    void unicos(List<String> ids) {
      if (ids.any((x) => x.isEmpty) || ids.toSet().length != ids.length) {
        throw FormatException(
          txt.bilingue(
            'Identificadores repetidos o vacíos',
            'Repeated or empty identifiers',
          ),
        );
      }
    }

    unicos(lotesJ.map((x) => x['id'] as String).toList());
    unicos(campaniasJ.map((x) => x['id'] as String).toList());
    final ls = lotesJ.map(Lote.deJson).toList();
    for (final l in ls) {
      if (l.geometria.any(
        (g) =>
            !g.latitud.isFinite ||
            !g.longitud.isFinite ||
            g.latitud.abs() > 85 ||
            g.longitud.abs() > 180,
      )) {
        throw FormatException(
          txt.bilingue(
            'Coordenada de lote inválida',
            'Invalid plot coordinate',
          ),
        );
      }
    }
    final ps = campaniasJ.map(Plantacion.deJson).toList();
    final activos = <String>{};
    for (final p in ps) {
      validarCampania(p);
      if (!ls.any((l) => l.id == p.loteId) ||
          p.activa && !activos.add(p.loteId)) {
        throw FormatException(
          txt.bilingue(
            'Campaña sin lote o lote con dos campañas activas',
            'Campaign without a plot, or plot with two active campaigns',
          ),
        );
      }
    }
    for (final l in ls) {
      final historia = ps.where((p) => p.loteId == l.id).toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));
      for (var i = 1; i < historia.length; i++) {
        final anterior = historia[i - 1];
        if (anterior.fin == null ||
            soloFecha(historia[i].fecha).isBefore(soloFecha(anterior.fin!))) {
          throw FormatException(
            txt.bilingue(
              'Campañas solapadas en el mismo lote',
              'Overlapping campaigns in the same plot',
            ),
          );
        }
      }
    }
    final es = filas('eventos').map(Evento.deJson).toList();
    unicos(es.map((e) => e.id).toList());
    for (final e in es) {
      if (e.derivado) {
        throw FormatException(
          txt.bilingue(
            'Los resúmenes se reconstruyen desde su ficha original',
            'Summaries are rebuilt from their original sheet',
          ),
        );
      }
      validarEvento(e, destinos: ps);
    }
    final rs = filas('registros').map(RegistroSemanal.deJson).toList();
    unicos(rs.map((r) => '${r.plantacionId}/${fechaIso(r.fecha)}').toList());
    for (final r in rs) {
      if (!ps.any((p) => p.id == r.plantacionId) ||
          r.riegos < 0 ||
          r.riegos > 14 ||
          soloFecha(r.fecha).isAfter(soloFecha(hoy))) {
        throw FormatException(
          txt.bilingue('Resumen semanal inválido', 'Invalid weekly summary'),
        );
      }
    }
    final ds = filas('riegosDiarios').map(RegistroRiego.deJson).toList();
    unicos(
      ds
          .map((r) => '${r.campaniaId}/${r.loteId}/${fechaIso(r.fecha)}')
          .toList(),
    );
    for (final r in ds) {
      final destino = ps
          .where((p) => p.id == r.campaniaId && p.loteId == r.loteId)
          .toList();
      if (!ls.any((l) => l.id == r.loteId) ||
          soloFecha(r.fecha).isAfter(soloFecha(hoy)) ||
          r.campaniaId.isNotEmpty &&
              (destino.length != 1 ||
                  soloFecha(r.fecha)
                      .isBefore(soloFecha(destino.single.fecha)) ||
                  destino.single.fin != null &&
                      soloFecha(r.fecha)
                          .isAfter(soloFecha(destino.single.fin!))) ||
          r.laminaMm != null &&
              (!r.laminaMm!.isFinite || r.laminaMm! <= 0 || r.rego != true)) {
        throw FormatException(
          txt.bilingue('Riego inválido', 'Invalid irrigation'),
        );
      }
    }
    final ss = filas('suministros').map(SuministroAgua.deJson).toList();
    unicos(ss.map((s) => fechaIso(s.fecha)).toList());
    for (final s in ss) {
      if (soloFecha(s.fecha).isAfter(soloFecha(hoy)) ||
          s.volumenM3 != null &&
              (!s.volumenM3!.isFinite ||
                  s.volumenM3! < 0 ||
                  s.disponibilidad != DisponibilidadAgua.si)) {
        throw FormatException(
          txt.bilingue('Suministro inválido', 'Invalid supply'),
        );
      }
    }
    final cs = filas('clima').map(DiaClima.deJson).toList();
    unicos(cs.map((d) => fechaIso(d.fecha)).toList());
    for (final d in cs) {
      if ([
            d.tmedia,
            d.tmax,
            d.tmin,
            d.humedad,
            d.viento,
            d.radiacion,
            d.lluvia,
            d.gwettop,
            d.gwetroot,
          ].any((v) => v != null && !v.isFinite) ||
          d.lluvia != null && d.lluvia! < 0 ||
          d.humedad != null && (d.humedad! < 0 || d.humedad! > 100) ||
          d.viento != null && d.viento! < 0 ||
          d.radiacion != null && d.radiacion! < 0 ||
          d.tmax != null && d.tmin != null && d.tmax! < d.tmin!) {
        throw FormatException(
          txt.bilingue('Clima inválido', 'Invalid weather data'),
        );
      }
    }
  }

  void _aplicarSnapshot(Map<String, dynamic> j) {
    parcela = j['parcela'] == null
        ? null
        : Parcela.deJson(j['parcela'] as Map<String, dynamic>);
    campanias = [
      for (final x in j['plantaciones'] as List)
        Plantacion.deJson(x as Map<String, dynamic>),
    ];
    lotes = [
      for (final x in j['lotes'] as List)
        Lote.deJson(x as Map<String, dynamic>),
    ];
    todosLosRegistros = [
      for (final x in j['registros'] as List)
        RegistroSemanal.deJson(x as Map<String, dynamic>),
    ];
    suministros = [
      for (final x in j['suministros'] as List)
        SuministroAgua.deJson(x as Map<String, dynamic>),
    ];
    riegosDiarios = [
      for (final x in j['riegosDiarios'] as List)
        RegistroRiego.deJson(x as Map<String, dynamic>),
    ];
    _eventos = [
      for (final x in j['eventos'] as List)
        Evento.deJson(x as Map<String, dynamic>),
    ];
    clima = [
      for (final x in j['clima'] as List)
        DiaClima.deJson(x as Map<String, dynamic>),
    ];
    ultimaSync = j['ultimaSync'] == null
        ? null
        : DateTime.parse(j['ultimaSync'] as String);
    _seleccionada = j['seleccionada'] as String?;
    _proyectar();
  }

  Future<void> importarPaquete(String texto) async {
    await _escritura.catchError((Object _) {});
    final combinado = revisarPaquete(texto), anterior = _snapshot();
    try {
      _aplicarSnapshot(combinado);
      await _persistir();
    } catch (_) {
      _aplicarSnapshot(anterior);
      rethrow;
    }
    _cambio();
  }

  Map<String, dynamic> exportarGeoJson() {
    final p = parcela!;
    final features = <Map<String, dynamic>>[];
    if (p.geometria.isNotEmpty) {
      final e = validarPoligono(p.contorno, lado: p.lado);
      if (e != null) throw FormatException(txt.errorGeometria(e));
      features.add({
        'type': 'Feature',
        'id': p.id,
        'properties': {
          'tipo': 'finca',
          'nombre': p.nombre,
          'area_m2': areaGeografica(p.geometria),
        },
        'geometry': poligonoGeoJson(p.geometria),
      });
    }
    for (final l in lotes) {
      final c = p.marco.aPlano(l.geometria);
      final asociadas = campanias.where((x) => x.loteId == l.id).toList();
      final nombre = asociadas.isEmpty
          ? 'Lote ${lotes.indexOf(l) + 1}'
          : txt.nombrePlantacion(asociadas.last);
      if (l.geometria.isNotEmpty) {
        final error = validarPoligono(
          c,
          lado: p.lado,
          finca: p.contorno,
          otros: [
            for (final otro in lotes)
              if (otro.id != l.id) p.marco.aPlano(otro.geometria),
          ],
        );
        if (error != null) {
          throw FormatException('$nombre: ${txt.errorGeometria(error)}');
        }
      }
      features.add({
        'type': 'Feature',
        'id': l.id,
        'properties': {
          'tipo': 'lote',
          'finca_id': p.id,
          'campanias': asociadas.map((x) => x.id).toList(),
          'nombre': nombre,
          'area_m2': l.areaM2,
          'origen': l.origen,
        },
        'geometry': poligonoGeoJson(l.geometria),
      });
    }
    return {
      'type': 'FeatureCollection',
      'version_esquema': 2,
      'metodo_area': 'esfera-IUGG-6371008.8m',
      'features': features,
    };
  }

  Future<ResultadoSync> sincronizar() async {
    final p = parcela;
    if (p == null || sincronizando) return ResultadoSync.error;
    sincronizando = true;
    notifyListeners();
    try {
      if (!await _servicio.hayWifi()) return ResultadoSync.sinWifi;
      final fin = soloFecha(hoy);
      var desde = DateTime(fin.year, fin.month, fin.day - 60);
      // Las campañas cerradas ya no necesitan clima nuevo.
      for (final x in plantaciones) {
        if (x.fecha.isBefore(desde)) desde = soloFecha(x.fecha);
      }
      final limite = DateTime(fin.year, fin.month, fin.day - 240);
      if (desde.isBefore(limite)) desde = limite;
      final r = await _servicio.descargar(
        latitud: p.latitud,
        longitud: p.longitud,
        desde: desde,
        hasta: fin,
      );
      // Una respuesta de un punto anterior no debe reemplazar el clima actual.
      if (parcela?.latitud != p.latitud || parcela?.longitud != p.longitud) {
        return ResultadoSync.error;
      }
      final porFecha = <DateTime, DiaClima>{
        for (final d in clima) soloFecha(d.fecha): d,
        for (final d in r.dias) soloFecha(d.fecha): d,
      };
      clima = porFecha.values.toList()
        ..sort((a, b) => a.fecha.compareTo(b.fecha));
      await _almacen.guardarClima(clima);
      if (r.elevacion != null) {
        parcela = parcela!.con(elevacion: r.elevacion);
        await _persistir();
      }
      ultimaSync = hoy;
      await _almacen.guardarUltimaSincronizacion(ultimaSync!);
      await _persistir();
      if (_servicio.runtimeType == ServicioClima) {
        unawaited(actualizarTerreno());
      }
      return ResultadoSync.ok;
    } catch (_) {
      return ResultadoSync.error;
    } finally {
      sincronizando = false;
      _cambio();
    }
  }

  /// Carga una finca de ejemplo con dos campanias para conocer la app.
  Future<void> cargarEjemplo() async {
    final h = soloFecha(hoy);
    await guardarParcela(
      const Parcela(
        nombre: 'Chiquimula',
        latitud: 14.8250,
        longitud: -89.5312,
        contorno: [
          Punto(0.10, 0.16),
          Punto(0.74, 0.10),
          Punto(0.90, 0.26),
          Punto(0.92, 0.86),
          Punto(0.16, 0.90),
          Punto(0.08, 0.52),
        ],
      ),
    );
    await guardarPlantacion(
      Plantacion(
        cultivoId: 'maiz',
        contorno: const [
          Punto(0.17, 0.22),
          Punto(0.50, 0.19),
          Punto(0.48, 0.47),
          Punto(0.16, 0.49),
        ],
        fecha: DateTime(h.year, h.month, h.day - 55),
        ciclo: 120,
        suelo: Suelo.franco,
        riego: TipoRiego.ninguno,
        temporadaRiego: TemporadaRiego.auxilio,
        plagaReciente: false,
        fertilizo: true,
      ),
    );
    await guardarPlantacion(
      Plantacion(
        cultivoId: 'frijol',
        contorno: const [
          Punto(0.56, 0.54),
          Punto(0.86, 0.54),
          Punto(0.86, 0.82),
          Punto(0.56, 0.82),
        ],
        fecha: DateTime(h.year, h.month, h.day - 38),
        ciclo: 67,
        suelo: Suelo.franco,
        riego: TipoRiego.goteo,
        temporadaRiego: TemporadaRiego.auxilio,
        plagaReciente: false,
        fertilizo: true,
      ),
    );
    // Queda seleccionada la última guardada: el frijol.
    await guardarRegistro(
      RegistroSemanal(
        plantacionId: plantacion!.id,
        fecha: DateTime(h.year, h.month, h.day - 9),
        riegos: 2,
        plaga: NivelPlaga.leve,
        notaPlaga: 'Mosca blanca',
        fertilizo: false,
      ),
    );
  }

  Future<void> borrarTodo() async {
    await _escritura.catchError((Object _) {});
    await _almacen.borrarTodo();
    parcela = null;
    _terreno = null;
    campanias = [];
    lotes = [];
    todosLosRegistros = [];
    suministros = [];
    riegosDiarios = [];
    clima = [];
    _eventos = [];
    ultimaSync = null;
    _seleccionada = null;
    await _almacen.guardarIdioma(idioma);
    await _guardarSnapshot();
    _cambio();
  }
}

/// Da acceso al estado desde cualquier pantalla y la redibuja cuando cambia.
class Alcance extends InheritedNotifier<AppEstado> {
  const Alcance({super.key, required AppEstado estado, required super.child})
    : super(notifier: estado);

  static AppEstado de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Alcance>()!.notifier!;

  /// Para llamar acciones sin suscribirse a los cambios.
  static AppEstado leer(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<Alcance>()!.widget
              as Alcance)
          .notifier!;
}
