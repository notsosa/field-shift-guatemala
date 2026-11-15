import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import '../modelos.dart';
import 'ajustes.dart' show confirmar;
import 'finca.dart';
import 'tema.dart';

/// Formulario del registro semanal: riego, plaga y fertilizante.
class PantallaRegistro extends StatefulWidget {
  const PantallaRegistro({super.key});

  @override
  State<PantallaRegistro> createState() => _EstadoRegistro();
}

class _EstadoRegistro extends State<PantallaRegistro> {
  /// Plantación a la que pertenece el registro. Arranca en la que se estaba
  /// viendo y se puede cambiar en el formulario.
  String? _plantacionId;
  int _riegos = 0;
  NivelPlaga _plaga = NivelPlaga.ninguna;
  bool _fertilizo = false;
  final _notaPlaga = TextEditingController();
  final _notaFertilizante = TextEditingController();

  @override
  void dispose() {
    _notaPlaga.dispose();
    _notaFertilizante.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final estado = Alcance.leer(context);
    final navegador = Navigator.of(context);
    final plantacion = estado.plantacionPorId(_plantacionId) ?? estado.plantacion!;
    await estado.guardarRegistro(RegistroSemanal(
      plantacionId: plantacion.id,
      fecha: soloFecha(estado.hoy),
      riegos: _riegos,
      plaga: _plaga,
      notaPlaga: _plaga == NivelPlaga.ninguna ? '' : _notaPlaga.text.trim(),
      fertilizo: _fertilizo,
      notaFertilizante: _fertilizo ? _notaFertilizante.text.trim() : '',
    ));
    // Al volver se muestra la plantación a la que se le acaba de registrar.
    await estado.seleccionar(plantacion.id);
    navegador.pop();
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final verde = Paleta.de(context, Paleta.verde);
    final plantacion = estado.plantacionPorId(_plantacionId) ?? estado.plantacion!;
    final tieneRiego = plantacion.riego != TipoRiego.ninguno;

    Widget paso(IconData icono, VoidCallback? alPulsar) => CupertinoButton(
          padding: EdgeInsets.zero,
          minimumSize: const Size(40, 40),
          onPressed: alPulsar,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: Paleta.de(context, Paleta.tenue), shape: BoxShape.circle),
            child: Icon(icono, size: 18, color: alPulsar == null ? Paleta.de(context, Paleta.secundario) : verde),
          ),
        );

    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: Text(t.registroSemanal),
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.of(context).pop(),
          child: Text(t.cancelar),
        ),
        border: null,
      ),
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  if (estado.plantaciones.length > 1) ...[
                    Rotulo(t.paraCualPlantacion),
                    Grupo(children: [
                      for (final p in estado.plantaciones)
                        Fila(
                          key: Key('registro-${p.id}'),
                          titulo: t.nombrePlantacion(p),
                          detalle: t.fechaLarga(p.fecha),
                          final_: Icon(
                            p.id == plantacion.id ? CupertinoIcons.checkmark_circle_fill : CupertinoIcons.circle,
                            size: 24,
                            color: p.id == plantacion.id ? verde : Paleta.de(context, Paleta.tenue),
                          ),
                          alPulsar: () => setState(() {
                            _plantacionId = p.id;
                            if (p.riego == TipoRiego.ninguno) _riegos = 0;
                          }),
                        ),
                    ]),
                  ],
                  Rotulo('${t.nombrePlantacion(plantacion)} · ${t.ultimaSemana}'),
                  if (tieneRiego) ...[
                    Grupo(children: [
                      Fila(
                        titulo: t.vecesRiego,
                        icono: CupertinoIcons.drop,
                        final_: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            paso(CupertinoIcons.minus, _riegos > 0 ? () => setState(() => _riegos--) : null),
                            SizedBox(
                              width: 40,
                              child: Text(
                                '$_riegos',
                                textAlign: TextAlign.center,
                                style: letra(20, peso: 600, color: Paleta.de(context, Paleta.texto)),
                              ),
                            ),
                            paso(CupertinoIcons.plus, _riegos < 14 ? () => setState(() => _riegos++) : null),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: Espacio.m),
                  ],
                  Grupo(children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: Espacio.borde, vertical: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(CupertinoIcons.ant, size: 22, color: verde),
                            const SizedBox(width: 14),
                            Text(t.plaga, style: Texto.cuerpo(context)),
                          ]),
                          const SizedBox(height: 12),
                          Selector<NivelPlaga>(
                            opciones: {for (final n in NivelPlaga.values) n: t.nombrePlaga(n)},
                            valor: _plaga,
                            alCambiar: (v) => setState(() => _plaga = v),
                          ),
                        ],
                      ),
                    ),
                    if (_plaga != NivelPlaga.ninguna)
                      Campo(titulo: t.cualPlaga, controlador: _notaPlaga, ejemplo: t.notaOpcional),
                  ]),
                  const SizedBox(height: Espacio.m),
                  Grupo(children: [
                    Fila(
                      titulo: t.fertilizaste,
                      icono: CupertinoIcons.leaf_arrow_circlepath,
                      final_: CupertinoSwitch(
                        value: _fertilizo,
                        activeTrackColor: verde,
                        onChanged: (v) => setState(() => _fertilizo = v),
                      ),
                    ),
                    if (_fertilizo)
                      Campo(titulo: t.nota, controlador: _notaFertilizante, ejemplo: t.queAplicaste),
                  ]),
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

/// Lista de registros semanales guardados.
class PestanaRegistros extends StatelessWidget {
  const PestanaRegistros({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;

    void nuevo() => Navigator.of(context, rootNavigator: true).push(
          CupertinoPageRoute<void>(fullscreenDialog: true, builder: (_) => const PantallaRegistro()),
        );

    return CupertinoPageScaffold(
      child: CustomScrollView(
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(t.registros),
            border: null,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: nuevo,
              child: const Icon(CupertinoIcons.add, size: 26),
            ),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(Espacio.m, 0, Espacio.m, Espacio.s),
              child: CambioPlantacion(),
            ),
          ),
          if (estado.registros.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(Espacio.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.square_pencil, size: 44, color: Paleta.de(context, Paleta.secundario)),
                    const SizedBox(height: Espacio.m),
                    Text(t.sinRegistros, style: Texto.titulo(context), textAlign: TextAlign.center),
                    const SizedBox(height: Espacio.s),
                    Text(t.sinRegistrosAyuda, style: Texto.nota(context), textAlign: TextAlign.center),
                    const SizedBox(height: Espacio.l),
                    BotonPrincipal(texto: t.registroSemanal, alPulsar: nuevo),
                  ],
                ),
              ),
            )
          else
            SliverList.list(children: [
              const SizedBox(height: Espacio.s),
              Grupo(children: [
                for (final r in estado.registros)
                  Fila(
                    titulo: t.fechaLarga(r.fecha),
                    detalle: [
                      t.resumenRegistro(r),
                      if (r.notaPlaga.isNotEmpty) r.notaPlaga,
                      if (r.notaFertilizante.isNotEmpty) r.notaFertilizante,
                    ].join(' · '),
                    final_: CupertinoButton(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(36, 36),
                      onPressed: () => confirmar(
                        context,
                        titulo: t.fechaLarga(r.fecha),
                        mensaje: t.borrarRegistroPregunta,
                        accion: t.borrar,
                        cancelar: t.cancelar,
                        alConfirmar: () => Alcance.leer(context).borrarRegistro(r),
                      ),
                      child: Icon(CupertinoIcons.trash, size: 19, color: Paleta.de(context, Paleta.secundario)),
                    ),
                  ),
              ]),
              const SizedBox(height: Espacio.xl),
            ]),
        ],
      ),
    );
  }
}
