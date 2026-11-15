/// Estado de la app: lo que hay guardado y las acciones que lo cambian.
library;

import 'package:flutter/widgets.dart';

import 'datos/almacen.dart';
import 'datos/clima.dart';
import 'datos/mapa.dart';
import 'modelos.dart';
import 'motor/recomendador.dart';
import 'textos.dart';

enum ResultadoSync { ok, sinWifi, error }

class AppEstado extends ChangeNotifier {
  AppEstado(this._almacen, {ServicioClima? servicioClima, ServicioMapa? servicioMapa, DateTime Function()? reloj})
      : _servicio = servicioClima ?? ServicioClima(),
        _reloj = reloj ?? DateTime.now {
    mapa = servicioMapa ?? ServicioMapa(_almacen, hayWifi: _servicio.hayWifi);
    final capaGuardada = _almacen.leerCapa();
    capa = CapaMapa.values.firstWhere((c) => c.name == capaGuardada, orElse: () => CapaMapa.mapa);
    parcela = _almacen.leerParcela();
    plantaciones = _almacen.leerPlantaciones();
    todosLosRegistros = _almacen.leerRegistros();
    clima = _almacen.leerClima();
    ultimaSync = _almacen.leerUltimaSincronizacion();
    idioma = _almacen.leerIdioma() ?? 'es';
    _seleccionada = _almacen.leerSeleccionada();

    // Datos de versiones con una sola plantación: se le da un identificador y
    // se le asignan los registros que no tenían dueña.
    if (plantaciones.any((p) => p.id.isEmpty)) {
      plantaciones = [for (final p in plantaciones) p.id.isEmpty ? p.conId(_nuevoId()) : p];
    }
    if (plantaciones.isNotEmpty && todosLosRegistros.any((r) => r.plantacionId.isEmpty)) {
      final primera = plantaciones.first.id;
      todosLosRegistros = [
        for (final r in todosLosRegistros) r.plantacionId.isEmpty ? r.conPlantacion(primera) : r,
      ];
    }
  }

  final Almacen _almacen;
  final ServicioClima _servicio;
  final DateTime Function() _reloj;

  /// Descarga y guarda las imágenes del mapa de fondo.
  late final ServicioMapa mapa;

  /// Fondo elegido para el plano de la finca.
  CapaMapa capa = CapaMapa.mapa;

  Parcela? parcela;
  List<Plantacion> plantaciones = [];

  /// Registros semanales de todas las plantaciones, del más reciente al más viejo.
  List<RegistroSemanal> todosLosRegistros = [];
  List<DiaClima> clima = [];
  DateTime? ultimaSync;
  String idioma = 'es';
  bool sincronizando = false;
  String? _seleccionada;
  final _recomendaciones = <String, Recomendacion>{};

  Txt get txt => Txt(idioma == 'en');
  DateTime get hoy => _reloj();
  bool get configurada => parcela != null && plantaciones.isNotEmpty;

  /// Plantación que se está viendo en Hoy y en Registros.
  Plantacion? get plantacion {
    if (plantaciones.isEmpty) return null;
    return plantaciones.firstWhere((p) => p.id == _seleccionada, orElse: () => plantaciones.first);
  }

  Plantacion? plantacionPorId(String? id) {
    for (final p in plantaciones) {
      if (p.id == id) return p;
    }
    return null;
  }

  List<RegistroSemanal> registrosDe(String id) => todosLosRegistros.where((r) => r.plantacionId == id).toList();

  /// Registros de la plantación seleccionada.
  List<RegistroSemanal> get registros => plantacion == null ? [] : registrosDe(plantacion!.id);

  Recomendacion recomendacionDe(Plantacion p) {
    if (parcela == null) return Recomendacion.vacia;
    return _recomendaciones[p.id] ??= recomendar(
      parcela: parcela!,
      plantacion: p,
      clima: clima,
      registros: registrosDe(p.id),
      hoy: hoy,
    );
  }

  /// Recomendación de la plantación seleccionada.
  Recomendacion get recomendacion => plantacion == null ? Recomendacion.vacia : recomendacionDe(plantacion!);

  void _cambio() {
    _recomendaciones.clear();
    notifyListeners();
  }

  String _nuevoId() {
    var n = 1;
    while (plantaciones.any((p) => p.id == 'p$n')) {
      n++;
    }
    return 'p$n';
  }

  Future<void> guardarParcela(Parcela p) async {
    final cambioDePunto = parcela == null || parcela!.latitud != p.latitud || parcela!.longitud != p.longitud;
    parcela = p;
    await _almacen.guardarParcela(p);
    if (cambioDePunto) {
      // El clima guardado era de otro lugar.
      clima = [];
      await _almacen.guardarClima(clima);
    }
    _cambio();
  }

  /// Guarda el contorno de la finca dibujado en el croquis.
  Future<void> guardarContornoFinca(List<Punto> contorno) async {
    final p = parcela;
    if (p == null) return;
    parcela = p.con(contorno: contorno);
    await _almacen.guardarParcela(parcela!);
    _cambio();
  }

  Future<void> cambiarCapa(CapaMapa nueva) async {
    capa = nueva;
    await _almacen.guardarCapa(nueva.name);
    notifyListeners();
  }

  /// Cambia el ancho del plano de la finca. Los contornos ya dibujados se
  /// ajustan para quedar en el mismo lugar del terreno.
  Future<void> cambiarLado(double nuevo) async {
    final p = parcela;
    if (p == null || p.lado == nuevo) return;
    parcela = p.con(lado: nuevo, contorno: reescalar(p.contorno, p.lado, nuevo));
    plantaciones = [for (final x in plantaciones) x.conContorno(reescalar(x.contorno, p.lado, nuevo))];
    await _almacen.guardarParcela(parcela!);
    await _almacen.guardarPlantaciones(plantaciones);
    _cambio();
  }

  /// Agrega una plantación nueva (sin identificador) o actualiza una existente,
  /// y la deja seleccionada.
  Future<void> guardarPlantacion(Plantacion p) async {
    final guardada = p.id.isEmpty ? p.conId(_nuevoId()) : p;
    final existe = plantaciones.any((x) => x.id == guardada.id);
    plantaciones = existe
        ? [for (final x in plantaciones) x.id == guardada.id ? guardada : x]
        : [...plantaciones, guardada];
    _seleccionada = guardada.id;
    await _almacen.guardarPlantaciones(plantaciones);
    await _almacen.guardarSeleccionada(guardada.id);
    _cambio();
  }

  /// Borra una plantación con sus registros semanales.
  Future<void> borrarPlantacion(String id) async {
    plantaciones = plantaciones.where((p) => p.id != id).toList();
    todosLosRegistros = todosLosRegistros.where((r) => r.plantacionId != id).toList();
    if (_seleccionada == id) _seleccionada = plantaciones.isEmpty ? null : plantaciones.first.id;
    await _almacen.guardarPlantaciones(plantaciones);
    await _almacen.guardarRegistros(todosLosRegistros);
    _cambio();
  }

  Future<void> seleccionar(String id) async {
    if (_seleccionada == id || plantacionPorId(id) == null) return;
    _seleccionada = id;
    await _almacen.guardarSeleccionada(id);
    notifyListeners();
  }

  /// Guarda un registro semanal; si esa plantación ya tiene uno de ese día, lo
  /// reemplaza.
  Future<void> guardarRegistro(RegistroSemanal r) async {
    todosLosRegistros = [
      ...todosLosRegistros
          .where((x) => x.plantacionId != r.plantacionId || soloFecha(x.fecha) != soloFecha(r.fecha)),
      r,
    ]..sort((a, b) => b.fecha.compareTo(a.fecha));
    await _almacen.guardarRegistros(todosLosRegistros);
    _cambio();
  }

  Future<void> borrarRegistro(RegistroSemanal r) async {
    todosLosRegistros = todosLosRegistros.where((x) => x != r).toList();
    await _almacen.guardarRegistros(todosLosRegistros);
    _cambio();
  }

  Future<void> cambiarIdioma(String codigo) async {
    idioma = codigo;
    await _almacen.guardarIdioma(codigo);
    _cambio();
  }

  /// Descarga el clima reciente de la finca. Solo corre con wifi.
  Future<ResultadoSync> sincronizar() async {
    final p = parcela;
    if (p == null || sincronizando) return ResultadoSync.error;
    sincronizando = true;
    notifyListeners();
    try {
      if (!await _servicio.hayWifi()) return ResultadoSync.sinWifi;
      final fin = soloFecha(hoy);
      // Desde la siembra más antigua, con un mínimo de 60 días y un máximo de 240.
      var desde = DateTime(fin.year, fin.month, fin.day - 60);
      for (final x in plantaciones) {
        if (x.fecha.isBefore(desde)) desde = soloFecha(x.fecha);
      }
      final limite = DateTime(fin.year, fin.month, fin.day - 240);
      if (desde.isBefore(limite)) desde = limite;

      final r = await _servicio.descargar(latitud: p.latitud, longitud: p.longitud, desde: desde, hasta: fin);
      clima = r.dias;
      await _almacen.guardarClima(clima);
      if (r.elevacion != null) {
        parcela = parcela!.con(elevacion: r.elevacion);
        await _almacen.guardarParcela(parcela!);
      }
      ultimaSync = hoy;
      await _almacen.guardarUltimaSincronizacion(ultimaSync!);
      return ResultadoSync.ok;
    } catch (_) {
      return ResultadoSync.error;
    } finally {
      sincronizando = false;
      _cambio();
    }
  }

  /// Carga una finca de ejemplo con dos plantaciones para conocer la app.
  Future<void> cargarEjemplo() async {
    final h = soloFecha(hoy);
    await guardarParcela(const Parcela(
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
    ));
    await guardarPlantacion(Plantacion(
      cultivoId: 'maiz',
      contorno: const [Punto(0.17, 0.22), Punto(0.50, 0.19), Punto(0.48, 0.47), Punto(0.16, 0.49)],
      fecha: DateTime(h.year, h.month, h.day - 55),
      ciclo: 120,
      suelo: Suelo.franco,
      riego: TipoRiego.ninguno,
      temporadaRiego: TemporadaRiego.auxilio,
      plagaReciente: false,
      fertilizo: true,
    ));
    await guardarPlantacion(Plantacion(
      cultivoId: 'frijol',
      contorno: const [Punto(0.56, 0.54), Punto(0.86, 0.54), Punto(0.86, 0.82), Punto(0.56, 0.82)],
      fecha: DateTime(h.year, h.month, h.day - 38),
      ciclo: 67,
      suelo: Suelo.franco,
      riego: TipoRiego.goteo,
      temporadaRiego: TemporadaRiego.auxilio,
      plagaReciente: false,
      fertilizo: true,
    ));
    // Queda seleccionada la última guardada: el frijol.
    await guardarRegistro(RegistroSemanal(
      plantacionId: plantacion!.id,
      fecha: DateTime(h.year, h.month, h.day - 9),
      riegos: 2,
      plaga: NivelPlaga.leve,
      notaPlaga: 'Mosca blanca',
      fertilizo: false,
    ));
  }

  Future<void> borrarTodo() async {
    await _almacen.borrarTodo();
    parcela = null;
    plantaciones = [];
    todosLosRegistros = [];
    clima = [];
    ultimaSync = null;
    _seleccionada = null;
    await _almacen.guardarIdioma(idioma);
    _cambio();
  }
}

/// Da acceso al estado desde cualquier pantalla y la redibuja cuando cambia.
class Alcance extends InheritedNotifier<AppEstado> {
  const Alcance({super.key, required AppEstado estado, required super.child}) : super(notifier: estado);

  static AppEstado de(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Alcance>()!.notifier!;

  /// Para llamar acciones sin suscribirse a los cambios.
  static AppEstado leer(BuildContext context) =>
      (context.getElementForInheritedWidgetOfExactType<Alcance>()!.widget as Alcance).notifier!;
}
