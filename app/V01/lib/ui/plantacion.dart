import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import 'ajustes.dart' show confirmar;
import 'finca.dart';
import 'tema.dart';

/// Registro de la plantación: siembra, plaga reciente, fertilizante, suelo y
/// riego. La plaga y el fertilizante son cajas que se despliegan al activarlas.
class PantallaPlantacion extends StatefulWidget {
  const PantallaPlantacion({super.key, this.primeraVez = false, this.id, this.contornoNuevo});

  final bool primeraVez;

  /// Plantación que se edita. Si es nulo, se crea una nueva.
  final String? id;

  /// Perímetro recién dibujado para una plantación nueva.
  final List<Punto>? contornoNuevo;

  @override
  State<PantallaPlantacion> createState() => _EstadoPlantacion();
}

class _EstadoPlantacion extends State<PantallaPlantacion> {
  final _nombre = TextEditingController();
  List<Punto> _contorno = const [];
  String _cultivo = 'maiz';
  late DateTime _fecha;
  int _ciclo = 120;
  Suelo _suelo = Suelo.franco;
  TipoRiego _riego = TipoRiego.ninguno;
  TemporadaRiego _temporada = TemporadaRiego.auxilio;

  bool _plaga = false;
  final _notaPlaga = TextEditingController();
  late DateTime _inicioPlaga;
  NivelPlaga _nivelPlaga = NivelPlaga.leve;
  bool _plagaTratada = false;
  final _tratamiento = TextEditingController();

  bool _fertilizo = false;
  TipoFertilizante _tipoFertilizante = TipoFertilizante.quimico;
  final _notaFertilizante = TextEditingController();
  late DateTime _fechaFertilizante;

  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final estado = Alcance.leer(context);
    final hoy = soloFecha(estado.hoy);
    final p = estado.plantacionPorId(widget.id);
    _contorno = p?.contorno ?? widget.contornoNuevo ?? const [];
    _fecha = hoy;
    _inicioPlaga = hoy;
    _fechaFertilizante = hoy;
    if (p != null) {
      _nombre.text = p.nombre;
      _cultivo = p.cultivoId;
      _fecha = p.fecha;
      _ciclo = p.ciclo;
      _suelo = p.suelo;
      _riego = p.riego;
      _temporada = p.temporadaRiego;
      _plaga = p.plagaReciente;
      _notaPlaga.text = p.notaPlaga;
      _inicioPlaga = p.inicioPlaga ?? hoy;
      _nivelPlaga = p.nivelPlaga == NivelPlaga.ninguna ? NivelPlaga.leve : p.nivelPlaga;
      _plagaTratada = p.plagaTratada;
      _tratamiento.text = p.tratamientoPlaga;
      _fertilizo = p.fertilizo;
      _tipoFertilizante = p.tipoFertilizante;
      _notaFertilizante.text = p.notaFertilizante;
      _fechaFertilizante = p.fechaFertilizante ?? hoy;
    }
  }

  @override
  void dispose() {
    _nombre.dispose();
    _notaPlaga.dispose();
    _tratamiento.dispose();
    _notaFertilizante.dispose();
    super.dispose();
  }

  void _elegirCultivo(String id) => setState(() {
        _cultivo = id;
        final c = cultivoPorId(id);
        if (!c.ciclos.contains(_ciclo)) _ciclo = c.ciclos.first;
      });

  /// Abre el selector de fecha y devuelve la elegida. No deja pasar de hoy.
  Future<DateTime> _pedirFecha(DateTime actual, {int aniosAtras = 3}) async {
    final estado = Alcance.leer(context);
    final hoy = soloFecha(estado.hoy);
    final minima = DateTime(hoy.year - aniosAtras, hoy.month, hoy.day);
    var elegida = actual.isAfter(hoy) ? hoy : (actual.isBefore(minima) ? minima : actual);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: Paleta.de(ctx, Paleta.tarjeta),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: CupertinoButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(estado.txt.listo, style: letra(16, peso: 600, color: Paleta.de(ctx, Paleta.verde))),
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: elegida,
                  maximumDate: hoy,
                  minimumDate: minima,
                  onDateTimeChanged: (f) => elegida = soloFecha(f),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return elegida;
  }

  Future<void> _guardar() async {
    final estado = Alcance.leer(context);
    final navegador = Navigator.of(context);
    final c = cultivoPorId(_cultivo);
    await estado.guardarPlantacion(Plantacion(
      id: widget.id ?? '',
      nombre: _nombre.text.trim(),
      contorno: _contorno,
      cultivoId: _cultivo,
      fecha: _fecha,
      ciclo: c.perenne ? c.ciclos.first : _ciclo,
      suelo: _suelo,
      riego: _riego,
      temporadaRiego: _temporada,
      plagaReciente: _plaga,
      notaPlaga: _plaga ? _notaPlaga.text.trim() : '',
      inicioPlaga: _plaga ? _inicioPlaga : null,
      nivelPlaga: _plaga ? _nivelPlaga : NivelPlaga.leve,
      plagaTratada: _plaga && _plagaTratada,
      tratamientoPlaga: _plaga && _plagaTratada ? _tratamiento.text.trim() : '',
      fertilizo: _fertilizo,
      tipoFertilizante: _tipoFertilizante,
      notaFertilizante: _fertilizo ? _notaFertilizante.text.trim() : '',
      fechaFertilizante: _fertilizo ? _fechaFertilizante : null,
    ));
    estado.sincronizar();
    if (widget.primeraVez) {
      navegador.popUntil((r) => r.isFirst);
    } else {
      navegador.pop();
    }
  }

  Future<void> _redibujar() async {
    final estado = Alcance.leer(context);
    final t = estado.txt;
    final nuevo = await Navigator.of(context).push<List<Punto>>(CupertinoPageRoute(
      builder: (_) => PantallaTrazo(
        titulo: t.perimetro,
        ayuda: t.ayudaTrazoPlantacion,
        excepto: widget.id,
        inicial: _contorno,
      ),
    ));
    if (nuevo != null && nuevo.length >= 3 && mounted) setState(() => _contorno = nuevo);
  }

  void _borrar() {
    final estado = Alcance.leer(context);
    final t = estado.txt;
    final navegador = Navigator.of(context);
    confirmar(
      context,
      titulo: t.borrarPlantacion,
      mensaje: t.borrarPlantacionPregunta,
      accion: t.borrar,
      cancelar: t.cancelar,
      alConfirmar: () async {
        await estado.borrarPlantacion(widget.id!);
        navegador.pop();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final cultivo = cultivoPorId(_cultivo);
    final verde = Paleta.de(context, Paleta.verde);

    Widget bloque(String titulo, Widget control) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: Espacio.borde, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo, style: Texto.cuerpo(context)),
              const SizedBox(height: 10),
              control,
            ],
          ),
        );

    Widget interruptor(Key clave, bool valor, ValueChanged<bool> alCambiar) => CupertinoSwitch(
          key: clave,
          value: valor,
          activeTrackColor: verde,
          onChanged: alCambiar,
        );

    Widget filaFecha(String titulo, DateTime fecha, ValueChanged<DateTime> alElegir, {int aniosAtras = 3}) => Fila(
          titulo: titulo,
          final_: Text(t.fechaLarga(fecha), style: letra(16, peso: 500, color: verde)),
          alPulsar: () async {
            final f = await _pedirFecha(fecha, aniosAtras: aniosAtras);
            if (mounted) alElegir(f);
          },
        );

    Widget marca(bool elegido) => Icon(
          elegido ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
          size: 24,
          color: elegido ? verde : Paleta.de(context, Paleta.tenue),
        );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.plantacion),
        previousPageTitle: t.atras,
        border: null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                scrollCacheExtent: const ScrollCacheExtent.pixels(2400),
                padding: const EdgeInsets.only(bottom: Espacio.l),
                children: [
                  // Siembra: fecha y cultivo.
                  Rotulo(t.siembra),
                  Grupo(children: [
                    filaFecha(
                      cultivo.perenne ? t.fechaReferencia : t.fechaSiembra,
                      _fecha,
                      (f) => setState(() => _fecha = f),
                    ),
                    Campo(titulo: t.nombreLote, controlador: _nombre, ejemplo: t.ejemploLote),
                  ]),
                  const SizedBox(height: Espacio.m),
                  Grupo(children: [
                    for (final c in catalogo)
                      Fila(
                        titulo: t.nombreCultivo(c.id),
                        detalle: c.perenne ? t.fijo : t.deTemporada,
                        final_: marca(c.id == _cultivo),
                        alPulsar: () => _elegirCultivo(c.id),
                      ),
                    if (!cultivo.perenne && cultivo.ciclos.length > 1)
                      bloque(
                        t.ciclo,
                        Selector<int>(
                          opciones: {for (final d in cultivo.ciclos) d: t.dias(d)},
                          valor: _ciclo,
                          alCambiar: (v) => setState(() => _ciclo = v),
                        ),
                      ),
                  ]),

                  // Caja de plaga reciente.
                  Rotulo(t.manejo),
                  Grupo(children: [
                    Fila(
                      titulo: t.plagaReciente,
                      detalle: t.plagaAyuda,
                      icono: CupertinoIcons.ant,
                      final_: interruptor(const Key('plaga'), _plaga, (v) => setState(() => _plaga = v)),
                    ),
                    if (_plaga) ...[
                      Campo(titulo: t.cualPlaga, controlador: _notaPlaga, ejemplo: t.ejemploPlaga),
                      filaFecha(t.desdeCuando, _inicioPlaga, (f) => setState(() => _inicioPlaga = f), aniosAtras: 1),
                      bloque(
                        t.danio,
                        Selector<NivelPlaga>(
                          opciones: {
                            for (final n in NivelPlaga.values)
                              if (n != NivelPlaga.ninguna) n: t.nombrePlaga(n),
                          },
                          valor: _nivelPlaga,
                          alCambiar: (v) => setState(() => _nivelPlaga = v),
                        ),
                      ),
                      Fila(
                        titulo: t.yaTratada,
                        final_: interruptor(
                            const Key('plagaTratada'), _plagaTratada, (v) => setState(() => _plagaTratada = v)),
                      ),
                      if (_plagaTratada) Campo(titulo: t.conQue, controlador: _tratamiento, ejemplo: t.notaOpcional),
                    ],
                  ]),
                  const SizedBox(height: Espacio.m),

                  // Caja de fertilizante.
                  Grupo(children: [
                    Fila(
                      titulo: t.fertilizacion,
                      detalle: t.fertilizanteAyuda,
                      icono: CupertinoIcons.leaf_arrow_circlepath,
                      final_: interruptor(const Key('fertilizo'), _fertilizo, (v) => setState(() => _fertilizo = v)),
                    ),
                    if (_fertilizo) ...[
                      bloque(
                        t.claseFertilizante,
                        Selector<TipoFertilizante>(
                          opciones: {for (final f in TipoFertilizante.values) f: t.nombreFertilizante(f)},
                          valor: _tipoFertilizante,
                          alCambiar: (v) => setState(() => _tipoFertilizante = v),
                        ),
                      ),
                      Campo(titulo: t.producto, controlador: _notaFertilizante, ejemplo: t.ejemploFertilizante),
                      filaFecha(
                        t.fechaAplicacion,
                        _fechaFertilizante,
                        (f) => setState(() => _fechaFertilizante = f),
                        aniosAtras: 1,
                      ),
                    ],
                  ]),

                  // Suelo y riego: lo que necesita el cálculo de agua.
                  Rotulo(t.sueloYRiego),
                  Grupo(children: [
                    bloque(
                      t.suelo,
                      Selector<Suelo>(
                        opciones: {for (final s in Suelo.values) s: t.nombreSuelo(s)},
                        valor: _suelo,
                        alCambiar: (v) => setState(() => _suelo = v),
                      ),
                    ),
                  ]),
                  const SizedBox(height: Espacio.m),
                  Grupo(children: [
                    for (final r in TipoRiego.values)
                      Fila(
                        titulo: t.nombreRiego(r),
                        final_: marca(r == _riego),
                        alPulsar: () => setState(() => _riego = r),
                      ),
                    if (_riego != TipoRiego.ninguno)
                      bloque(
                        t.temporadaRiego,
                        Selector<TemporadaRiego>(
                          opciones: {for (final x in TemporadaRiego.values) x: t.nombreTemporada(x)},
                          valor: _temporada,
                          alCambiar: (v) => setState(() => _temporada = v),
                        ),
                      ),
                  ]),

                  // Perímetro en el croquis y borrado, solo al editar.
                  if (widget.id != null) ...[
                    Rotulo(t.finca),
                    Grupo(children: [
                      Fila(
                        titulo: t.perimetro,
                        detalle: _contorno.length >= 3
                            ? t.area(areaDe(_contorno, estado.parcela!.lado))
                            : t.sinDibujar,
                        icono: CupertinoIcons.map,
                        alPulsar: _redibujar,
                      ),
                      if (estado.plantaciones.length > 1)
                        Fila(
                          titulo: t.borrarPlantacion,
                          icono: CupertinoIcons.trash,
                          colorIcono: Paleta.de(context, Paleta.rojo),
                          alPulsar: _borrar,
                        ),
                    ]),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(Espacio.l, Espacio.s, Espacio.l, Espacio.m),
              child: BotonPrincipal(texto: t.guardar, alPulsar: _guardar),
            ),
          ],
        ),
      ),
    );
  }
}
