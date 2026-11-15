import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import 'plagas.dart';
import 'tema.dart';

/// Información de la plantación: cultivo, fecha, suelo, riego y manejo.
class PantallaPlantacion extends StatefulWidget {
  const PantallaPlantacion({super.key, this.primeraVez = false});

  final bool primeraVez;

  @override
  State<PantallaPlantacion> createState() => _EstadoPlantacion();
}

class _EstadoPlantacion extends State<PantallaPlantacion> {
  String _cultivo = 'maiz';
  late DateTime _fecha;
  int _ciclo = 120;
  Suelo _suelo = Suelo.franco;
  TipoRiego _riego = TipoRiego.ninguno;
  TemporadaRiego _temporada = TemporadaRiego.auxilio;
  bool _plaga = false;
  String? _tipoPlaga;
  bool _fertilizo = false;
  final _notaPlaga = TextEditingController();
  bool _iniciado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_iniciado) return;
    _iniciado = true;
    final estado = Alcance.leer(context);
    final p = estado.plantacion;
    _fecha = soloFecha(estado.hoy);
    if (p != null) {
      _cultivo = p.cultivoId;
      _fecha = p.fecha;
      _ciclo = p.ciclo;
      _suelo = p.suelo;
      _riego = p.riego;
      _temporada = p.temporadaRiego;
      _plaga = p.plagaReciente;
      _tipoPlaga = p.tipoPlaga.isEmpty ? null : p.tipoPlaga;
      _fertilizo = p.fertilizo;
      _notaPlaga.text = p.notaPlaga;
    }
  }

  @override
  void dispose() {
    _notaPlaga.dispose();
    super.dispose();
  }

  void _elegirCultivo(String id) => setState(() {
    _cultivo = id;
    final c = cultivoPorId(id);
    if (!c.ciclos.contains(_ciclo)) _ciclo = c.ciclos.first;
    if (!tiposPlaga(id).contains(_tipoPlaga)) _tipoPlaga = null;
  });

  Future<void> _elegirFecha() async {
    final estado = Alcance.leer(context);
    final hoy = soloFecha(estado.hoy);
    var elegida = _fecha.isAfter(hoy) ? hoy : _fecha;
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
                  child: Text(
                    estado.txt.listo,
                    style: letra(
                      16,
                      peso: 600,
                      color: Paleta.de(ctx, Paleta.verde),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: elegida,
                  maximumDate: hoy,
                  minimumDate: DateTime(hoy.year - 3),
                  onDateTimeChanged: (f) => elegida = soloFecha(f),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted) setState(() => _fecha = elegida);
  }

  Future<void> _guardar() async {
    final estado = Alcance.leer(context);
    final navegador = Navigator.of(context);
    final c = cultivoPorId(_cultivo);
    final tipos = tiposPlaga(_cultivo);
    await estado.guardarPlantacion(
      Plantacion(
        cultivoId: _cultivo,
        fecha: _fecha,
        ciclo: c.perenne ? c.ciclos.first : _ciclo,
        suelo: _suelo,
        riego: _riego,
        temporadaRiego: _temporada,
        plagaReciente: _plaga,
        notaPlaga: _plaga ? _notaPlaga.text.trim() : '',
        tipoPlaga: !_plaga
            ? ''
            : (tipos.contains(_tipoPlaga) ? _tipoPlaga! : tipos.last),
        fertilizo: _fertilizo,
      ),
    );
    estado.sincronizar();
    if (widget.primeraVez) {
      navegador.popUntil((r) => r.isFirst);
    } else {
      navegador.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    final cultivo = cultivoPorId(_cultivo);
    final verde = Paleta.de(context, Paleta.verde);
    final tipos = tiposPlaga(_cultivo);

    Widget bloque(String titulo, Widget control) => Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Espacio.borde,
        vertical: 14,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titulo, style: Texto.cuerpo(context)),
          const SizedBox(height: 10),
          control,
        ],
      ),
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
                padding: const EdgeInsets.only(bottom: Espacio.l),
                children: [
                  Rotulo(t.cultivo),
                  Grupo(
                    children: [
                      for (final c in catalogo)
                        Fila(
                          titulo: t.nombreCultivo(c.id),
                          final_: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                c.perenne ? t.fijo : t.deTemporada,
                                style: Texto.nota(context),
                              ),
                              const SizedBox(width: 12),
                              Icon(
                                c.id == _cultivo
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.circle,
                                size: 24,
                                color: c.id == _cultivo
                                    ? verde
                                    : Paleta.de(context, Paleta.secundario),
                              ),
                            ],
                          ),
                          alPulsar: () => _elegirCultivo(c.id),
                        ),
                    ],
                  ),
                  const SizedBox(height: Espacio.m),
                  Grupo(
                    children: [
                      Fila(
                        titulo: cultivo.perenne
                            ? t.fechaReferencia
                            : t.fechaSiembra,
                        final_: Text(
                          t.fechaLarga(_fecha),
                          style: letra(16, peso: 500, color: verde),
                        ),
                        alPulsar: _elegirFecha,
                      ),
                      if (!cultivo.perenne && cultivo.ciclos.length > 1)
                        bloque(
                          t.ciclo,
                          Selector<int>(
                            opciones: {
                              for (final d in cultivo.ciclos) d: t.dias(d),
                            },
                            valor: _ciclo,
                            alCambiar: (v) => setState(() => _ciclo = v),
                          ),
                        ),
                      bloque(
                        t.suelo,
                        Selector<Suelo>(
                          opciones: {
                            for (final s in Suelo.values) s: t.nombreSuelo(s),
                          },
                          valor: _suelo,
                          alCambiar: (v) => setState(() => _suelo = v),
                        ),
                      ),
                    ],
                  ),
                  Rotulo(t.riego),
                  Grupo(
                    children: [
                      for (final r in TipoRiego.values)
                        Fila(
                          titulo: t.nombreRiego(r),
                          final_: Icon(
                            r == _riego
                                ? CupertinoIcons.checkmark_circle_fill
                                : CupertinoIcons.circle,
                            size: 24,
                            color: r == _riego
                                ? verde
                                : Paleta.de(context, Paleta.secundario),
                          ),
                          alPulsar: () => setState(() => _riego = r),
                        ),
                      if (_riego != TipoRiego.ninguno)
                        bloque(
                          t.temporadaRiego,
                          Selector<TemporadaRiego>(
                            opciones: {
                              for (final x in TemporadaRiego.values)
                                x: t.nombreTemporada(x),
                            },
                            valor: _temporada,
                            alCambiar: (v) => setState(() => _temporada = v),
                          ),
                        ),
                    ],
                  ),
                  Rotulo(t.manejo),
                  Grupo(
                    children: [
                      Fila(
                        titulo: t.plagaReciente,
                        final_: CupertinoSwitch(
                          value: _plaga,
                          activeTrackColor: verde,
                          onChanged: (v) => setState(() => _plaga = v),
                        ),
                      ),
                      if (_plaga)
                        ListaPlagas(
                          cultivoId: _cultivo,
                          valor: tipos.contains(_tipoPlaga)
                              ? _tipoPlaga!
                              : tipos.last,
                          alCambiar: (v) => setState(() => _tipoPlaga = v),
                        ),
                      if (_plaga)
                        Campo(
                          titulo: t.cualPlaga,
                          controlador: _notaPlaga,
                          ejemplo: t.notaOpcional,
                        ),
                      Fila(
                        titulo: t.fertilizacion,
                        final_: CupertinoSwitch(
                          value: _fertilizo,
                          activeTrackColor: verde,
                          onChanged: (v) => setState(() => _fertilizo = v),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Espacio.l,
                Espacio.s,
                Espacio.l,
                Espacio.m,
              ),
              child: BotonPrincipal(texto: t.guardar, alPulsar: _guardar),
            ),
          ],
        ),
      ),
    );
  }
}
