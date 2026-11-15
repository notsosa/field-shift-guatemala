/// Estado de la app: lo que hay guardado y las acciones que lo cambian.
library;

import 'package:flutter/widgets.dart';

import 'datos/almacen.dart';
import 'datos/clima.dart';
import 'modelos.dart';
import 'motor/recomendador.dart';
import 'textos.dart';

enum ResultadoSync { ok, sinWifi, error }

class AppEstado extends ChangeNotifier {
  AppEstado(this._almacen, {ServicioClima? servicioClima, DateTime Function()? reloj})
      : _servicio = servicioClima ?? ServicioClima(),
        _reloj = reloj ?? DateTime.now {
    parcela = _almacen.leerParcela();
    plantacion = _almacen.leerPlantacion();
    registros = _almacen.leerRegistros();
    clima = _almacen.leerClima();
    ultimaSync = _almacen.leerUltimaSincronizacion();
    idioma = _almacen.leerIdioma() ?? 'es';
  }

  final Almacen _almacen;
  final ServicioClima _servicio;
  final DateTime Function() _reloj;

  Parcela? parcela;
  Plantacion? plantacion;
  List<RegistroSemanal> registros = [];
  List<DiaClima> clima = [];
  DateTime? ultimaSync;
  String idioma = 'es';
  bool sincronizando = false;
  Recomendacion? _recomendacion;

  Txt get txt => Txt(idioma == 'en');
  DateTime get hoy => _reloj();
  bool get configurada => parcela != null && plantacion != null;

  Recomendacion get recomendacion {
    if (!configurada) return Recomendacion.vacia;
    return _recomendacion ??= recomendar(
      parcela: parcela!,
      plantacion: plantacion!,
      clima: clima,
      registros: registros,
      hoy: hoy,
    );
  }

  void _cambio() {
    _recomendacion = null;
    notifyListeners();
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

  Future<void> guardarPlantacion(Plantacion p) async {
    plantacion = p;
    await _almacen.guardarPlantacion(p);
    _cambio();
  }

  /// Guarda un registro semanal; si ya hay uno de ese día, lo reemplaza.
  Future<void> guardarRegistro(RegistroSemanal r) async {
    registros = [
      ...registros.where((x) => soloFecha(x.fecha) != soloFecha(r.fecha)),
      r,
    ]..sort((a, b) => b.fecha.compareTo(a.fecha));
    await _almacen.guardarRegistros(registros);
    _cambio();
  }

  Future<void> borrarRegistro(RegistroSemanal r) async {
    registros = registros.where((x) => x != r).toList();
    await _almacen.guardarRegistros(registros);
    _cambio();
  }

  Future<void> cambiarIdioma(String codigo) async {
    idioma = codigo;
    await _almacen.guardarIdioma(codigo);
    _cambio();
  }

  /// Descarga el clima reciente de la parcela. Solo corre con wifi.
  Future<ResultadoSync> sincronizar() async {
    final p = parcela;
    if (p == null || sincronizando) return ResultadoSync.error;
    sincronizando = true;
    notifyListeners();
    try {
      if (!await _servicio.hayWifi()) return ResultadoSync.sinWifi;
      final fin = soloFecha(hoy);
      final siembra = plantacion?.fecha;
      // Desde la siembra, con un mínimo de 60 días y un máximo de 240.
      var desde = DateTime(fin.year, fin.month, fin.day - 60);
      if (siembra != null && siembra.isBefore(desde)) desde = soloFecha(siembra);
      final limite = DateTime(fin.year, fin.month, fin.day - 240);
      if (desde.isBefore(limite)) desde = limite;

      final r = await _servicio.descargar(latitud: p.latitud, longitud: p.longitud, desde: desde, hasta: fin);
      clima = r.dias;
      await _almacen.guardarClima(clima);
      if (r.elevacion != null) {
        parcela = p.con(elevacion: r.elevacion);
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

  /// Carga una parcela y una plantación de ejemplo para conocer la app.
  Future<void> cargarEjemplo() async {
    final h = soloFecha(hoy);
    await guardarParcela(const Parcela(nombre: 'Chiquimula', latitud: 14.8250, longitud: -89.5312));
    await guardarPlantacion(Plantacion(
      cultivoId: 'frijol',
      fecha: DateTime(h.year, h.month, h.day - 38),
      ciclo: 67,
      suelo: Suelo.franco,
      riego: TipoRiego.goteo,
      temporadaRiego: TemporadaRiego.auxilio,
      plagaReciente: false,
      fertilizo: true,
    ));
    await guardarRegistro(RegistroSemanal(
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
    plantacion = null;
    registros = [];
    clima = [];
    ultimaSync = null;
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
