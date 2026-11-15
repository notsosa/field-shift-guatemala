import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:geolocator/geolocator.dart';

import '../estado.dart';
import '../modelos.dart';
import 'finca.dart';
import 'tema.dart';

/// Fija el punto de la parcela, con el GPS o escribiendo las coordenadas.
class PantallaParcela extends StatefulWidget {
  const PantallaParcela({super.key, this.primeraVez = false});

  /// En la configuración inicial, al guardar se pasa a la plantación.
  final bool primeraVez;

  @override
  State<PantallaParcela> createState() => _EstadoParcela();
}

class _EstadoParcela extends State<PantallaParcela> {
  final _nombre = TextEditingController();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  bool _buscando = false;
  String? _error;
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final p = Alcance.leer(context).parcela;
    if (p != null) {
      _nombre.text = p.nombre;
      _lat.text = p.latitud.toStringAsFixed(5);
      _lon.text = p.longitud.toStringAsFixed(5);
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _lat.dispose();
    _lon.dispose();
    super.dispose();
  }

  double? get _latitud => double.tryParse(_lat.text.trim().replaceAll(',', '.'));
  double? get _longitud => double.tryParse(_lon.text.trim().replaceAll(',', '.'));

  bool get _valida {
    final la = _latitud, lo = _longitud;
    return la != null && lo != null && la.abs() <= 90 && lo.abs() <= 180;
  }

  Future<void> _ubicar() async {
    final t = Alcance.leer(context).txt;
    setState(() {
      _buscando = true;
      _error = null;
    });
    try {
      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied || permiso == LocationPermission.deniedForever) {
        throw Exception('sin permiso');
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 25)),
      );
      if (!mounted) return;
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(5);
        _lon.text = pos.longitude.toStringAsFixed(5);
      });
    } catch (_) {
      if (mounted) setState(() => _error = t.sinUbicacion);
    } finally {
      if (mounted) setState(() => _buscando = false);
    }
  }

  Future<void> _guardar() async {
    final estado = Alcance.leer(context);
    final t = estado.txt;
    if (!_valida) {
      setState(() => _error = t.coordenadasInvalidas);
      return;
    }
    final nombre = _nombre.text.trim().isEmpty ? t.tuParcela : _nombre.text.trim();
    final navegador = Navigator.of(context);
    final anterior = estado.parcela;
    final mismoPunto = anterior != null && anterior.latitud == _latitud && anterior.longitud == _longitud;
    await estado.guardarParcela(Parcela(
      nombre: nombre,
      latitud: _latitud!,
      longitud: _longitud!,
      elevacion: mismoPunto ? anterior.elevacion : null,
      contorno: anterior?.contorno ?? const [],
      lado: anterior?.lado ?? 500,
    ));
    if (widget.primeraVez) {
      if (mounted) await agregarPlantacion(context, primeraVez: true);
    } else {
      estado.sincronizar();
      navegador.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.tuParcela),
        previousPageTitle: t.atras,
        border: null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Espacio.borde + Espacio.m, Espacio.m, Espacio.borde + Espacio.m, 0),
                    child: Text(t.parcelaAyuda, style: Texto.nota(context)),
                  ),
                  const SizedBox(height: Espacio.l),
                  Grupo(children: [
                    Campo(titulo: t.nombre, controlador: _nombre, ejemplo: t.nombreEjemplo),
                  ]),
                  Rotulo(t.coordenadas),
                  Grupo(children: [
                    Fila(
                      titulo: _buscando ? t.buscandoUbicacion : t.usarUbicacion,
                      icono: CupertinoIcons.location_fill,
                      final_: _buscando ? const CupertinoActivityIndicator() : null,
                      alPulsar: _buscando ? null : _ubicar,
                    ),
                    Campo(
                      titulo: t.latitud,
                      controlador: _lat,
                      ejemplo: '14.82500',
                      teclado: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      alCambiar: (_) => setState(() => _error = null),
                    ),
                    Campo(
                      titulo: t.longitud,
                      controlador: _lon,
                      ejemplo: '-89.53120',
                      teclado: const TextInputType.numberWithOptions(decimal: true, signed: true),
                      alCambiar: (_) => setState(() => _error = null),
                    ),
                  ]),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Espacio.borde + Espacio.m, Espacio.m, Espacio.borde + Espacio.m, 0),
                      child: Text(_error!, style: Texto.nota(context).copyWith(color: Paleta.de(context, Paleta.rojo))),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, Espacio.m),
              child: BotonPrincipal(
                texto: widget.primeraVez ? t.continuar : t.guardar,
                alPulsar: _valida ? _guardar : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
