/// Visor topográfico 3D interactivo (NASA SRTM + NASA POWER + Hidrología OSM)
/// y panel de telemetría agroclimática para el mapa de la finca.
library;

import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter/services.dart';

import '../datos/mapa.dart';
import '../estado.dart';
import '../modelos.dart';
import 'finca.dart';
import 'tema.dart';

/// Estado interactivo compartido entre el lienzo [VistaTopo3D] y el
/// [PanelTelemetria3D] en la pantalla del mapa de la finca.
class ControladorTopo3D extends ChangeNotifier {
  ControladorTopo3D();

  static final ControladorTopo3D instancia = ControladorTopo3D();

  /// Capa activa: `'moist'`, `'temp'`, `'rain'`, `'elev'`, `'slope'`, `'icta'`.
  String capaActiva = 'moist';

  /// `0.0` = 2D Plano cenital (Norte arriba), `1.0` = 3D Relieve volumétrico.
  double morph3D = 1.0;

  double yaw = -0.68;
  double pitch = 0.58;
  double zoom = 1.04;
  double exag = 2.2;

  bool curvas = true;
  bool flujo = true;
  bool agua = true;

  int? poiFila;
  int? poiCol;
  String? _fincaIdPoi;

  void asegurarPoiInicial(AppEstado estado, MallaTerreno terreno) {
    final pId = '${estado.parcela?.id}:${estado.plantacion?.id}';
    if (poiFila != null &&
        poiCol != null &&
        _fincaIdPoi == pId &&
        poiFila! >= 0 &&
        poiFila! < terreno.n &&
        poiCol! >= 0 &&
        poiCol! < terreno.n) {
      return;
    }
    _fincaIdPoi = pId;
    final p = estado.plantacion;
    if (p != null && p.contorno.length >= 3) {
      final c = centroDe(p.contorno);
      poiCol = (c.x * (terreno.n - 1)).round().clamp(0, terreno.n - 1);
      poiFila = (c.y * (terreno.n - 1)).round().clamp(0, terreno.n - 1);
    } else if (estado.parcela != null && estado.parcela!.contorno.length >= 3) {
      final c = centroDe(estado.parcela!.contorno);
      poiCol = (c.x * (terreno.n - 1)).round().clamp(0, terreno.n - 1);
      poiFila = (c.y * (terreno.n - 1)).round().clamp(0, terreno.n - 1);
    } else {
      poiFila = terreno.n ~/ 2;
      poiCol = terreno.n ~/ 2;
    }
  }

  void cambiarCapa(String nueva) {
    if (capaActiva == nueva) return;
    capaActiva = nueva;
    notifyListeners();
  }

  void fijarMorph3D(double valor) {
    final v = valor.clamp(0.0, 1.0);
    if ((morph3D - v).abs() < 1e-4) return;
    morph3D = v;
    notifyListeners();
  }

  void alternarCurvas() {
    curvas = !curvas;
    notifyListeners();
  }

  void alternarFlujo() {
    flujo = !flujo;
    notifyListeners();
  }

  void alternarAgua() {
    agua = !agua;
    notifyListeners();
  }

  void rotar(double dYaw, double dPitch) {
    yaw += dYaw;
    pitch = (pitch + dPitch).clamp(0.20, 1.48);
    notifyListeners();
  }

  void fijarZoom(double nuevoZoom) {
    final z = nuevoZoom.clamp(0.68, 2.60);
    if ((zoom - z).abs() < 1e-4) return;
    zoom = z;
    notifyListeners();
  }

  void fijarPoi(int fila, int col) {
    if (poiFila == fila && poiCol == col) return;
    poiFila = fila;
    poiCol = col;
    notifyListeners();
  }

  void restablecerVista() {
    yaw = -0.68;
    pitch = 0.58;
    zoom = 1.04;
    exag = 2.2;
    morph3D = 1.0;
    notifyListeners();
  }
}

/// Lienzo topográfico 3D interactivo para usar dentro de [LienzoFinca].
class VistaTopo3D extends StatefulWidget {
  const VistaTopo3D({
    super.key,
    required this.finca,
    this.zonas = const [],
    this.trazo = const [],
    this.trazoEsFinca = false,
    this.lado,
    this.alTocar,
    this.mostrarControles = true,
    this.controlador,
  });

  final List<Punto> finca;
  final List<Zona> zonas;
  final List<Punto> trazo;
  final bool trazoEsFinca;
  final double? lado;
  final ValueChanged<Punto>? alTocar;
  final bool mostrarControles;
  final ControladorTopo3D? controlador;

  @override
  State<VistaTopo3D> createState() => _EstadoVistaTopo3D();
}

class _EstadoVistaTopo3D extends State<VistaTopo3D> {
  late ControladorTopo3D _ctrl =
      widget.controlador ?? ControladorTopo3D.instancia;
  double _zoomAlEmpezar = 1.04;
  Offset _ultimoFoco = Offset.zero;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_alCambiarControlador);
  }

  @override
  void didUpdateWidget(VistaTopo3D viejo) {
    super.didUpdateWidget(viejo);
    final nuevo = widget.controlador ?? ControladorTopo3D.instancia;
    if (nuevo != _ctrl) {
      _ctrl.removeListener(_alCambiarControlador);
      _ctrl = nuevo;
      _ctrl.addListener(_alCambiarControlador);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_alCambiarControlador);
    super.dispose();
  }

  void _alCambiarControlador() {
    if (mounted) setState(() {});
  }

  MallaTerreno _obtenerTerreno(AppEstado estado) {
    final existente = estado.terreno;
    if (existente != null) return existente;
    final p = estado.parcela;
    final ladoKm = ((widget.lado ?? p?.lado ?? 5000.0) / 1000.0).clamp(
      0.5,
      12.0,
    );
    return MallaTerreno.sintetica(
      latitud: p?.latitud ?? 14.8250,
      longitud: p?.longitud ?? -89.5312,
      anchoKm: ladoKm,
      altoKm: ladoKm,
      elevacionBase: p?.elevacion,
    );
  }

  void _manejarToque(
    Offset pos,
    Size tam,
    AppEstado estado,
    MallaTerreno terreno,
  ) {
    final n = terreno.n;
    final vt = _TransformacionVista.calcular(
      terreno: terreno,
      morph3D: _ctrl.morph3D,
      yaw: _ctrl.yaw,
      pitch: _ctrl.pitch,
      zoom: _ctrl.zoom,
      exag: _ctrl.exag,
      w: tam.width,
      h: tam.height,
    );

    var mejorR = _ctrl.poiFila ?? (n ~/ 2);
    var mejorC = _ctrl.poiCol ?? (n ~/ 2);
    var mejorDist2 = double.infinity;

    for (var r = 0; r < n; r++) {
      final v = (r / (n - 1)) * 2.0 - 1.0;
      for (var c = 0; c < n; c++) {
        final u = (c / (n - 1)) * 2.0 - 1.0;
        final elev = terreno.elev[r * n + c];
        final p = vt.proyectar(u, v, elev);
        final dx = p.x - pos.dx;
        final dy = p.y - pos.dy;
        final d2 = dx * dx + dy * dy;
        if (d2 < mejorDist2) {
          mejorDist2 = d2;
          mejorR = r;
          mejorC = c;
        }
      }
    }

    HapticFeedback.selectionClick();
    _ctrl.fijarPoi(mejorR, mejorC);

    if (widget.alTocar != null) {
      if (!widget.mostrarControles || mejorDist2 > 900.0) {
        final px = (pos.dx / math.max(1.0, tam.width)).clamp(0.0, 1.0);
        final py = (pos.dy / math.max(1.0, tam.height)).clamp(0.0, 1.0);
        widget.alTocar!(Punto(px, py));
      } else {
        final px = (mejorC / math.max(1, n - 1)).clamp(0.0, 1.0);
        final py = (mejorR / math.max(1, n - 1)).clamp(0.0, 1.0);
        widget.alTocar!(Punto(px, py));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final terreno = _obtenerTerreno(estado);
    _ctrl.asegurarPoiInicial(estado, terreno);

    final poiFila = (_ctrl.poiFila ?? (terreno.n ~/ 2)).clamp(0, terreno.n - 1);
    final poiCol = (_ctrl.poiCol ?? (terreno.n ~/ 2)).clamp(0, terreno.n - 1);

    final rec = estado.recomendacion;
    final mesActual = estado.hoy.month.clamp(1, 12);
    final climMes =
        terreno.climatologia[mesActual] ?? climatologiaBaseNasa[mesActual]!;

    final baseTemp = rec.temperaturaActual ?? climMes.tmax;
    final baseMoistPct =
        rec.humedadTierraPct ??
        (estado.clima.isNotEmpty
            ? (rec.reserva * 100.0).clamp(18.0, 92.0)
            : climMes.humedadSueloPct);
    final lluviaBaseMm = estado.clima.isNotEmpty
        ? (estado.clima.last.lluvia ?? climMes.lluviaMmDia)
        : climMes.lluviaMmDia;
    final lluvia14dMm = rec.lluvia14dMm ?? (climMes.lluviaMmDia * 14.0);

    final poiLatLon = terreno.latLonDeFilaCol(poiFila, poiCol);
    final cuerpoAgua = terreno.evaluarCuerpoAguaCercano(
      poiLatLon.lat,
      poiLatLon.lon,
    );

    String rotuloPoi = t.bilingue('Punto de interés', 'Point of interest');
    final pPoi = Punto(
      poiCol / math.max(1, terreno.n - 1),
      poiFila / math.max(1, terreno.n - 1),
    );
    for (final z in widget.zonas.reversed) {
      if (dentroDe(z.contorno, pPoi)) {
        rotuloPoi = z.rotulo;
        break;
      }
    }
    if (rotuloPoi == t.bilingue('Punto de interés', 'Point of interest') &&
        estado.plantacion != null) {
      rotuloPoi = t.nombrePlantacion(estado.plantacion!);
    }

    final en3D = _ctrl.morph3D >= 0.5;

    return LayoutBuilder(
      builder: (context, caja) {
        final tam = Size(caja.maxWidth, caja.maxHeight);
        final trazando = widget.trazo.isNotEmpty || widget.trazoEsFinca;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onScaleStart: (d) {
            _zoomAlEmpezar = _ctrl.zoom;
            _ultimoFoco = d.localFocalPoint;
          },
          onScaleUpdate: (d) {
            if (d.pointerCount > 1) {
              _ctrl.fijarZoom(_zoomAlEmpezar * d.scale);
            } else if (!trazando && _ctrl.morph3D > 0.05) {
              final delta = d.localFocalPoint - _ultimoFoco;
              _ctrl.rotar(delta.dx * 0.009, delta.dy * 0.007);
            }
            _ultimoFoco = d.localFocalPoint;
          },
          onTapUp: (d) =>
              _manejarToque(d.localPosition, tam, estado, terreno),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CustomPaint(
                size: tam,
                painter: _PintorTopo3D(
                  terreno: terreno,
                  capaActiva: _ctrl.capaActiva,
                  morph3D: _ctrl.morph3D,
                  yaw: _ctrl.yaw,
                  pitch: _ctrl.pitch,
                  zoom: _ctrl.zoom,
                  exag: _ctrl.exag,
                  curvas: _ctrl.curvas,
                  flujo: _ctrl.flujo,
                  agua: _ctrl.agua,
                  poiFila: poiFila,
                  poiCol: poiCol,
                  rotuloPoi: rotuloPoi,
                  baseTemp: baseTemp,
                  baseMoistPct: baseMoistPct,
                  lluviaBaseMm: lluviaBaseMm,
                  lluvia14dMm: lluvia14dMm,
                  cuerpoAgua: cuerpoAgua,
                  finca: widget.finca,
                  zonas: widget.zonas,
                  trazo: widget.trazo,
                  trazoEsFinca: widget.trazoEsFinca,
                  enIngles: t.en,
                ),
              ),
              if (widget.mostrarControles) ...[
                // Píldora superior izquierda: indicador de capa activa y fuente
                Positioned(
                  left: 8,
                  top: 8,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xD90E1624),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF283A52)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 5,
                        ),
                        child: Text(
                          _tituloCapaHud(_ctrl.capaActiva, t),
                          style: letra(
                            11.5,
                            peso: 600,
                            color: const Color(0xFFF3F4F2),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Controles rápidos en esquina superior derecha: 2D/3D y recentrar
                Positioned(
                  right: 8,
                  top: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _BotonHud(
                        texto: en3D ? '2D' : '3D',
                        activo: en3D,
                        alPulsar: () {
                          HapticFeedback.selectionClick();
                          _ctrl.fijarMorph3D(en3D ? 0.0 : 1.0);
                        },
                      ),
                      const SizedBox(width: 6),
                      _BotonHud(
                        icono: CupertinoIcons.viewfinder,
                        alPulsar: () {
                          HapticFeedback.selectionClick();
                          _ctrl.restablecerVista();
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  static String _tituloCapaHud(String capa, dynamic t) => switch (capa) {
    'moist' => t.bilingue('💧 Agua en el suelo (%)', '💧 Soil moisture (%)'),
    'temp' => t.bilingue('🌡️ Temperatura (°C)', '🌡️ Temperature (°C)'),
    'rain' => t.bilingue('🌧️ Lluvia efectiva (mm/d)', '🌧️ Effective rain (mm/d)'),
    'elev' => t.bilingue('⛰️ Altitud SRTM (m)', '⛰️ SRTM Altitude (m)'),
    'slope' => t.bilingue('📐 Pendiente y escorrentía (%)', '📐 Slope & runoff (%)'),
    'icta' => t.bilingue('🌱 Pisos térmicos ICTA', '🌱 ICTA thermal zones'),
    _ => capa,
  };
}

class _BotonHud extends StatelessWidget {
  const _BotonHud({
    this.texto,
    this.icono,
    this.activo = false,
    required this.alPulsar,
  });

  final String? texto;
  final IconData? icono;
  final bool activo;
  final VoidCallback alPulsar;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: alPulsar,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: activo ? const Color(0xFF1D7A4C) : const Color(0xD90E1624),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: activo ? const Color(0xFF3DD68C) : const Color(0xFF283A52),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: icono != null
            ? Icon(icono, size: 14, color: const Color(0xFFF3F4F2))
            : Text(
                texto ?? '',
                style: letra(11.5, peso: 700, color: const Color(0xFFF3F4F2)),
              ),
      ),
    ),
  );
}

class _TransformacionVista {
  const _TransformacionVista({
    required this.m,
    required this.scaleX,
    required this.scaleY,
    required this.effYaw,
    required this.effPitch,
    required this.cy,
    required this.sy,
    required this.cp,
    required this.sp,
    required this.effVertScale,
    required this.effYOffset,
    required this.zoom,
    required this.minElev,
    required this.w,
    required this.h,
    required this.aspect,
  });

  final double m, scaleX, scaleY, effYaw, effPitch;
  final double cy, sy, cp, sp;
  final double effVertScale, effYOffset, zoom, minElev, w, h, aspect;

  factory _TransformacionVista.calcular({
    required MallaTerreno terreno,
    required double morph3D,
    required double yaw,
    required double pitch,
    required double zoom,
    required double exag,
    required double w,
    required double h,
  }) {
    final m = morph3D.clamp(0.0, 1.0);
    final maxDim = math.max(0.5, math.max(terreno.anchoKm, terreno.altoKm));
    final scaleX = terreno.anchoKm / maxDim;
    final scaleY = terreno.altoKm / maxDim;
    final wrappedYaw = math.atan2(math.sin(yaw), math.cos(yaw));
    final effYaw = wrappedYaw * m;
    final effPitch = (math.pi * 0.5) * (1.0 - m) + pitch * m;
    final refFactor = 6.5 / math.max(1.2, maxDim);
    final effVertScale = 0.00028 * refFactor * exag * m;
    final effYOffset = -0.26 * m;
    return _TransformacionVista(
      m: m,
      scaleX: scaleX,
      scaleY: scaleY,
      effYaw: effYaw,
      effPitch: effPitch,
      cy: math.cos(effYaw),
      sy: math.sin(effYaw),
      cp: math.cos(effPitch),
      sp: math.sin(effPitch),
      effVertScale: effVertScale,
      effYOffset: effYOffset,
      zoom: zoom,
      minElev: terreno.minElev,
      w: w,
      h: h,
      aspect: w / math.max(1.0, h),
    );
  }

  ({double x, double y, double depth}) proyectar(
    double u,
    double v,
    double elev,
  ) {
    final zMeters = elev - minElev;
    final yPos = (zMeters * effVertScale) + effYOffset;

    final gx = u * scaleX;
    final gy = v * scaleY;

    final x1 = gx * cy - gy * sy;
    final z1 = gx * sy + gy * cy;

    final y2 = yPos * cp - z1 * sp;
    final z2 = yPos * sp + z1 * cp;

    final ndcX = (x1 / math.max(0.5, aspect)) * 0.90 * zoom;
    final ndcY = y2 * 0.90 * zoom;

    return (
      x: (ndcX * 0.5 + 0.5) * w,
      y: (1.0 - (ndcY * 0.5 + 0.5)) * h,
      depth: z2,
    );
  }
}

class _QuadMalla {
  const _QuadMalla({
    required this.r0,
    required this.c0,
    required this.r1,
    required this.c1,
    required this.depth,
  });
  final int r0, c0, r1, c1;
  final double depth;
}

class _PintorTopo3D extends CustomPainter {
  _PintorTopo3D({
    required this.terreno,
    required this.capaActiva,
    required this.morph3D,
    required this.yaw,
    required this.pitch,
    required this.zoom,
    required this.exag,
    required this.curvas,
    required this.flujo,
    required this.agua,
    required this.poiFila,
    required this.poiCol,
    required this.rotuloPoi,
    required this.baseTemp,
    required this.baseMoistPct,
    required this.lluviaBaseMm,
    required this.lluvia14dMm,
    required this.cuerpoAgua,
    required this.finca,
    required this.zonas,
    required this.trazo,
    required this.trazoEsFinca,
    required this.enIngles,
  });

  final MallaTerreno terreno;
  final String capaActiva;
  final double morph3D, yaw, pitch, zoom, exag;
  final bool curvas, flujo, agua;
  final int poiFila, poiCol;
  final String rotuloPoi;
  final double baseTemp, baseMoistPct, lluviaBaseMm, lluvia14dMm;
  final CuerpoAguaCercano? cuerpoAgua;
  final List<Punto> finca;
  final List<Zona> zonas;
  final List<Punto> trazo;
  final bool trazoEsFinca;
  final bool enIngles;

  static (double, double, double) _mix(
    (double, double, double) a,
    (double, double, double) b,
    double t,
  ) {
    final u = t.clamp(0.0, 1.0);
    return (
      a.$1 + (b.$1 - a.$1) * u,
      a.$2 + (b.$2 - a.$2) * u,
      a.$3 + (b.$3 - a.$3) * u,
    );
  }

  static (double, double, double) _rampTemp(double t) {
    final u = ((t - 18.0) / 18.0).clamp(0.0, 1.0);
    const c0 = (0.18, 0.45, 0.95);
    const c1 = (0.05, 0.72, 0.68);
    const c2 = (0.22, 0.80, 0.35);
    const c3 = (0.98, 0.82, 0.15);
    const c4 = (0.97, 0.45, 0.08);
    const c5 = (0.86, 0.14, 0.14);
    const c6 = (0.48, 0.06, 0.18);
    if (u < 0.166) return _mix(c0, c1, u / 0.166);
    if (u < 0.333) return _mix(c1, c2, (u - 0.166) / 0.167);
    if (u < 0.500) return _mix(c2, c3, (u - 0.333) / 0.167);
    if (u < 0.666) return _mix(c3, c4, (u - 0.500) / 0.166);
    if (u < 0.833) return _mix(c4, c5, (u - 0.666) / 0.167);
    return _mix(c5, c6, (u - 0.833) / 0.167);
  }

  static (double, double, double) _rampMoist(double m) {
    final u = ((m - 20.0) / 65.0).clamp(0.0, 1.0);
    const c0 = (0.78, 0.24, 0.14);
    const c1 = (0.92, 0.58, 0.14);
    const c2 = (0.52, 0.80, 0.22);
    const c3 = (0.06, 0.72, 0.65);
    const c4 = (0.12, 0.38, 0.88);
    if (u < 0.25) return _mix(c0, c1, u / 0.25);
    if (u < 0.50) return _mix(c1, c2, (u - 0.25) / 0.25);
    if (u < 0.75) return _mix(c2, c3, (u - 0.50) / 0.25);
    return _mix(c3, c4, (u - 0.75) / 0.25);
  }

  (double, double, double) _rampElev(double e) {
    final u =
        ((e - terreno.minElev) /
                math.max(50.0, terreno.maxElev - terreno.minElev))
            .clamp(0.0, 1.0);
    const c0 = (0.12, 0.52, 0.34);
    const c1 = (0.45, 0.72, 0.28);
    const c2 = (0.88, 0.76, 0.32);
    const c3 = (0.72, 0.42, 0.22);
    const c4 = (0.92, 0.90, 0.88);
    if (u < 0.25) return _mix(c0, c1, u / 0.25);
    if (u < 0.55) return _mix(c1, c2, (u - 0.25) / 0.30);
    if (u < 0.82) return _mix(c2, c3, (u - 0.55) / 0.27);
    return _mix(c3, c4, (u - 0.82) / 0.18);
  }

  static (double, double, double) _rampSlope(double s) {
    final u = (s / 36.0).clamp(0.0, 1.0);
    const c0 = (0.08, 0.72, 0.48);
    const c1 = (0.96, 0.76, 0.14);
    const c2 = (0.94, 0.35, 0.12);
    const c3 = (0.68, 0.10, 0.22);
    if (u < 0.25) return _mix(c0, c1, u / 0.25);
    if (u < 0.60) return _mix(c1, c2, (u - 0.25) / 0.35);
    return _mix(c2, c3, (u - 0.60) / 0.40);
  }

  static (double, double, double) _rampIcta(double e) {
    if (e < 496.0) {
      final t = ((e - 250.0) / 250.0).clamp(0.0, 1.0);
      return _mix((0.92, 0.42, 0.10), (0.96, 0.68, 0.20), t);
    } else if (e <= 504.0) {
      return (1.0, 1.0, 1.0);
    } else {
      final t = ((e - 500.0) / 700.0).clamp(0.0, 1.0);
      return _mix((0.10, 0.72, 0.48), (0.08, 0.45, 0.78), t);
    }
  }

  static (double, double, double) _rampRain(double r) {
    final u = (r / 15.0).clamp(0.0, 1.0);
    const c0 = (0.86, 0.74, 0.44);
    const c1 = (0.32, 0.78, 0.52);
    const c2 = (0.06, 0.68, 0.85);
    const c3 = (0.12, 0.40, 0.92);
    const c4 = (0.36, 0.18, 0.85);
    if (u < 0.20) return _mix(c0, c1, u / 0.20);
    if (u < 0.48) return _mix(c1, c2, (u - 0.20) / 0.28);
    if (u < 0.76) return _mix(c2, c3, (u - 0.48) / 0.28);
    return _mix(c3, c4, (u - 0.76) / 0.24);
  }

  Color _colorCelda(int fila, int col) {
    final n = terreno.n;
    final idx = fila * n + col;
    final elev = terreno.elev[idx];
    final slope = terreno.pendiente[idx];

    final base = switch (capaActiva) {
      'temp' => _rampTemp(
        terreno.temperaturaEn(fila, col, baseTemp: baseTemp),
      ),
      'moist' => _rampMoist(
        terreno.humedadTierraEn(fila, col, baseMoistPct: baseMoistPct),
      ),
      'elev' => _rampElev(elev),
      'slope' => _rampSlope(slope),
      'rain' => _rampRain(
        terreno.lluviaEfectivaEn(
          fila,
          col,
          lluviaBaseMm: lluviaBaseMm,
          lluvia14dMm: lluvia14dMm,
        ),
      ),
      'icta' => _rampIcta(elev),
      _ => _rampMoist(
        terreno.humedadTierraEn(fila, col, baseMoistPct: baseMoistPct),
      ),
    };

    // Iluminación Lambertiana idéntica al shader GLSL de web/topo3d.html
    final nx = terreno.normales[idx * 3];
    final ny = terreno.normales[idx * 3 + 1];
    final nz = terreno.normales[idx * 3 + 2];
    // L = normalize(-0.55, 0.78, -0.35) ≈ (-0.541, 0.767, -0.344)
    final diff = math.max(0.0, nx * -0.541 + ny * 0.767 + nz * -0.344);
    final sky = 0.5 + 0.5 * ny;
    final shade = 0.42 + 0.46 * diff + 0.18 * sky;

    var r = (base.$1 * shade).clamp(0.0, 1.0);
    var g = (base.$2 * shade).clamp(0.0, 1.0);
    var b = (base.$3 * shade).clamp(0.0, 1.0);

    if (curvas && slope > 1.8) {
      final d50 = (((elev / 50.0 + 0.5) % 1.0) - 0.5).abs() * 50.0;
      final d200 = (((elev / 200.0 + 0.5) % 1.0) - 0.5).abs() * 200.0;
      if (d200 < 4.5) {
        final f = (1.0 - d200 / 4.5) * 0.65;
        r = r * (1 - f) + 1.0 * f;
        g = g * (1 - f) + 0.97 * f;
        b = b * (1 - f) + 0.88 * f;
      } else if (d50 < 2.8) {
        final f = (1.0 - d50 / 2.8) * 0.35;
        r = r * (1 - f) + 0.03 * f;
        g = g * (1 - f) + 0.05 * f;
        b = b * (1 - f) + 0.10 * f;
      }
    }

    return Color.fromARGB(
      255,
      (r * 255).round().clamp(0, 255),
      (g * 255).round().clamp(0, 255),
      (b * 255).round().clamp(0, 255),
    );
  }

  double _elevarPlano(double x01, double y01) {
    final n = terreno.n;
    final fc = (x01.clamp(0.0, 1.0) * (n - 1)).clamp(0.0, n - 1.001);
    final fr = (y01.clamp(0.0, 1.0) * (n - 1)).clamp(0.0, n - 1.001);
    final c0 = fc.floor(), r0 = fr.floor();
    final c1 = math.min(n - 1, c0 + 1), r1 = math.min(n - 1, r0 + 1);
    final wc = fc - c0, wr = fr - r0;
    final e00 = terreno.elev[r0 * n + c0];
    final e10 = terreno.elev[r0 * n + c1];
    final e01 = terreno.elev[r1 * n + c0];
    final e11 = terreno.elev[r1 * n + c1];
    return (e00 * (1 - wc) + e10 * wc) * (1 - wr) +
        (e01 * (1 - wc) + e11 * wc) * wr;
  }

  Offset _proyectarPuntoPlano(
    Punto p,
    _TransformacionVista vt, {
    double offsetElev = 3.0,
  }) {
    final u = p.x * 2.0 - 1.0;
    final v = p.y * 2.0 - 1.0;
    final elev = _elevarPlano(p.x, p.y) + offsetElev;
    final pr = vt.proyectar(u, v, elev);
    return Offset(pr.x, pr.y);
  }

  Path _camino3D(
    List<Punto> puntos,
    _TransformacionVista vt, {
    bool cerrado = true,
  }) {
    final path = Path();
    if (puntos.isEmpty) return path;
    const pasos = 6;
    for (var i = 0; i < puntos.length; i++) {
      final a = puntos[i];
      final b = puntos[(i + 1) % puntos.length];
      final oA = _proyectarPuntoPlano(a, vt);
      if (i == 0) {
        path.moveTo(oA.dx, oA.dy);
      } else {
        path.lineTo(oA.dx, oA.dy);
      }
      if (cerrado || i < puntos.length - 1) {
        for (var s = 1; s < pasos; s++) {
          final t = s / pasos;
          final m = Punto(a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t);
          final oM = _proyectarPuntoPlano(m, vt);
          path.lineTo(oM.dx, oM.dy);
        }
      }
    }
    if (cerrado && puntos.length >= 3) path.close();
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cw = size.width;
    final ch = size.height;

    // 1. Fondo atmosférico oscuro estilo dashboard topográfico 3D
    final bgPaint = Paint()
      ..shader = const RadialGradient(
        center: Alignment(0.0, -0.25),
        radius: 1.05,
        colors: [Color(0xFF142238), Color(0xFF090F1A)],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, bgPaint);

    final n = terreno.n;
    final vt = _TransformacionVista.calcular(
      terreno: terreno,
      morph3D: morph3D,
      yaw: yaw,
      pitch: pitch,
      zoom: zoom,
      exag: exag,
      w: cw,
      h: ch,
    );

    // 2. Proyectar vértices y construir Z-buffer de oclusión + Quads ordenados
    const step = 2;
    final projX = List<double>.filled(n * n, 0.0);
    final projY = List<double>.filled(n * n, 0.0);
    final projD = List<double>.filled(n * n, 0.0);

    const occW = 110;
    const occH = 110;
    final occGrid = List<double>.filled(occW * occH, -999.0);

    for (var r = 0; r < n; r += step) {
      final v = (r / (n - 1)) * 2.0 - 1.0;
      for (var c = 0; c < n; c += step) {
        final u = (c / (n - 1)) * 2.0 - 1.0;
        final idx = r * n + c;
        final pt = vt.proyectar(u, v, terreno.elev[idx]);
        projX[idx] = pt.x;
        projY[idx] = pt.y;
        projD[idx] = pt.depth;

        if (vt.m > 0.05) {
          final gx = ((pt.x / cw) * occW).floor();
          final gy = ((pt.y / ch) * occH).floor();
          if (gx >= 0 && gx < occW - 1 && gy >= 0 && gy < occH - 1) {
            final d = pt.depth;
            final i0 = gy * occW + gx;
            if (d > occGrid[i0]) occGrid[i0] = d;
            if (d > occGrid[i0 + 1]) occGrid[i0 + 1] = d;
            if (d > occGrid[i0 + occW]) occGrid[i0 + occW] = d;
            if (d > occGrid[i0 + occW + 1]) occGrid[i0 + occW + 1] = d;
          }
        }
      }
    }
    // Asegurar el borde final (n - 1) si (n - 1) no es múltiplo de step
    if ((n - 1) % step != 0) {
      for (var r = 0; r < n; r++) {
        if (r % step != 0 && r != n - 1) continue;
        final v = (r / (n - 1)) * 2.0 - 1.0;
        for (var c = 0; c < n; c++) {
          if (c % step != 0 && c != n - 1) continue;
          final idx = r * n + c;
          if (projX[idx] != 0.0 || projY[idx] != 0.0) continue;
          final u = (c / (n - 1)) * 2.0 - 1.0;
          final pt = vt.proyectar(u, v, terreno.elev[idx]);
          projX[idx] = pt.x;
          projY[idx] = pt.y;
          projD[idx] = pt.depth;
        }
      }
    }

    bool estaOcluido(double x, double y, double depth, [double tol = 0.14]) {
      if (vt.m <= 0.05) return false;
      final gx = ((x / cw) * occW).floor();
      final gy = ((y / ch) * occH).floor();
      if (gx < 0 || gx >= occW || gy < 0 || gy >= occH) return false;
      return occGrid[gy * occW + gx] > depth + tol;
    }

    final filas = <int>[
      for (var r = 0; r < n - 1; r += step) r,
      n - 1,
    ];
    final cols = <int>[
      for (var c = 0; c < n - 1; c += step) c,
      n - 1,
    ];

    final quads = <_QuadMalla>[];
    for (var ri = 0; ri < filas.length - 1; ri++) {
      final r0 = filas[ri], r1 = filas[ri + 1];
      for (var ci = 0; ci < cols.length - 1; ci++) {
        final c0 = cols[ci], c1 = cols[ci + 1];
        final d =
            (projD[r0 * n + c0] +
                projD[r0 * n + c1] +
                projD[r1 * n + c0] +
                projD[r1 * n + c1]) *
            0.25;
        quads.add(_QuadMalla(r0: r0, c0: c0, r1: r1, c1: c1, depth: d));
      }
    }
    // Painter's algorithm: de atrás (menor z2) hacia adelante (mayor z2)
    quads.sort((a, b) => a.depth.compareTo(b.depth));

    // Pedestal / faldón lateral 3D para dar volumen de bloque geológico
    if (vt.m > 0.12) {
      final skirtPaint = Paint()
        ..color = const Color(0xFF0E1826)
        ..style = PaintingStyle.fill;
      void dibujarBordeFaldon(List<(int, int)> indices) {
        final p = Path();
        for (var i = 0; i < indices.length; i++) {
          final (r, c) = indices[i];
          final idx = r * n + c;
          if (i == 0) {
            p.moveTo(projX[idx], projY[idx]);
          } else {
            p.lineTo(projX[idx], projY[idx]);
          }
        }
        for (var i = indices.length - 1; i >= 0; i--) {
          final (r, c) = indices[i];
          final u = (c / (n - 1)) * 2.0 - 1.0;
          final v = (r / (n - 1)) * 2.0 - 1.0;
          final basePt = vt.proyectar(u, v, terreno.minElev - 35.0);
          p.lineTo(basePt.x, basePt.y);
        }
        p.close();
        canvas.drawPath(p, skirtPaint);
      }

      dibujarBordeFaldon([for (final c in cols) (n - 1, c)]);
      dibujarBordeFaldon([for (final r in filas) (r, n - 1)]);
      dibujarBordeFaldon([for (final r in filas) (r, 0)]);
    }

    final quadFill = Paint()..style = PaintingStyle.fill;
    final quadStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.65
      ..strokeJoin = StrokeJoin.round;

    for (final q in quads) {
      final i00 = q.r0 * n + q.c0;
      final i10 = q.r0 * n + q.c1;
      final i01 = q.r1 * n + q.c0;
      final i11 = q.r1 * n + q.c1;

      final color = _colorCelda((q.r0 + q.r1) ~/ 2, (q.c0 + q.c1) ~/ 2);
      quadFill.color = color;
      quadStroke.color = color;

      final path = Path()
        ..moveTo(projX[i00], projY[i00])
        ..lineTo(projX[i10], projY[i10])
        ..lineTo(projX[i11], projY[i11])
        ..lineTo(projX[i01], projY[i01])
        ..close();
      canvas.drawPath(path, quadFill);
      canvas.drawPath(path, quadStroke);
    }

    // 3. Líneas curvas 3D de escorrentía superficial (Runoff Streamlines)
    if (flujo && terreno.escorrentia.isNotEmpty) {
      final casingPaint = Paint()
        ..color = const Color(0x8C070C17)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.8
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final flowPaint = Paint()
        ..color = const Color(0xD97DD3FC)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.65
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      final headFill = Paint()
        ..color = const Color(0xFFE0F2FE)
        ..style = PaintingStyle.fill;

      for (final stream in terreno.escorrentia) {
        final vis = <({double x, double y, double depth})>[];
        for (final p in stream) {
          final nz1 = p.nx * vt.sy + p.nz * vt.cy;
          final nCamZ = p.ny * vt.sp + nz1 * vt.cp;
          if (nCamZ < 0.12) break;
          final pr = vt.proyectar(p.u, p.v, p.elev);
          if (estaOcluido(pr.x, pr.y, pr.depth, 0.14)) break;
          vis.add(pr);
        }
        if (vis.length < 3) continue;
        final pStart = vis.first;
        final pEnd = vis.last;
        final len = math.sqrt(
          (pEnd.x - pStart.x) * (pEnd.x - pStart.x) +
              (pEnd.y - pStart.y) * (pEnd.y - pStart.y),
        );
        if (len < 7.0) continue;

        final path = Path()..moveTo(vis[0].x, vis[0].y);
        for (var i = 1; i < vis.length - 1; i++) {
          final xc = (vis[i].x + vis[i + 1].x) * 0.5;
          final yc = (vis[i].y + vis[i + 1].y) * 0.5;
          path.quadraticBezierTo(vis[i].x, vis[i].y, xc, yc);
        }
        path.lineTo(pEnd.x, pEnd.y);

        canvas.drawPath(path, casingPaint);
        canvas.drawPath(path, flowPaint);

        final pPrev = vis[vis.length - 2];
        final ang = math.atan2(pEnd.y - pPrev.y, pEnd.x - pPrev.x);
        const headLen = 5.0;
        const wing = 0.52;
        final arrow = Path()
          ..moveTo(pEnd.x, pEnd.y)
          ..lineTo(
            pEnd.x - headLen * math.cos(ang - wing),
            pEnd.y - headLen * math.sin(ang - wing),
          )
          ..lineTo(
            pEnd.x - headLen * math.cos(ang + wing),
            pEnd.y - headLen * math.sin(ang + wing),
          )
          ..close();
        canvas.drawPath(arrow, headFill);
      }
    }

    // 4. Cuerpos de agua 3D (Ríos, Quebradas y Cauces SRTM/OSM)
    if (agua && terreno.cuerposAgua.isNotEmpty) {
      for (final wb in terreno.cuerposAgua) {
        final visSegs = <List<({double x, double y, double depth})>>[];
        var curSeg = <({double x, double y, double depth})>[];
        for (final pt in wb.puntos) {
          final pr = vt.proyectar(pt.u, pt.v, pt.elev);
          if (!estaOcluido(pr.x, pr.y, pr.depth, 0.15)) {
            curSeg.add(pr);
          } else {
            if (curSeg.length >= 2) visSegs.add(curSeg);
            curSeg = [];
          }
        }
        if (curSeg.length >= 2) visSegs.add(curSeg);

        final esPrincipal = wb.permanente;
        for (final seg in visSegs) {
          final path = Path()..moveTo(seg[0].x, seg[0].y);
          for (var i = 1; i < seg.length - 1; i++) {
            final xc = (seg[i].x + seg[i + 1].x) * 0.5;
            final yc = (seg[i].y + seg[i + 1].y) * 0.5;
            path.quadraticBezierTo(seg[i].x, seg[i].y, xc, yc);
          }
          path.lineTo(seg.last.x, seg.last.y);

          canvas.drawPath(
            path,
            Paint()
              ..color = const Color(0xD1051226)
              ..style = PaintingStyle.stroke
              ..strokeWidth = esPrincipal ? 5.4 : 4.0
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
          canvas.drawPath(
            path,
            Paint()
              ..color = esPrincipal
                  ? const Color(0xFF0284C7)
                  : const Color(0xFF0EA5E9)
              ..style = PaintingStyle.stroke
              ..strokeWidth = esPrincipal ? 3.4 : 2.4
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
          canvas.drawPath(
            path,
            Paint()
              ..color = const Color(0xFFBAE6FD)
              ..style = PaintingStyle.stroke
              ..strokeWidth = esPrincipal ? 1.1 : 0.8
              ..strokeCap = StrokeCap.round
              ..strokeJoin = StrokeJoin.round,
          );
        }

        if (visSegs.isNotEmpty) {
          var bestSeg = visSegs.first;
          for (final s in visSegs) {
            if (s.length > bestSeg.length) bestSeg = s;
          }
          if (bestSeg.length >= 3) {
            final midPt = bestSeg[bestSeg.length ~/ 2];
            _dibujarEtiquetaPastilla(
              canvas,
              texto: '🌊 ${wb.nombre}',
              centro: Offset(midPt.x, midPt.y - 10),
              fondo: const Color(0xE6071930),
              borde: const Color(0xFF38BDF8),
              colorTexto: const Color(0xFFE0F2FE),
              tamFuente: 9.5,
            );
          }
        }
      }
    }

    // 5. Contorno de la finca, lotes/zonas de plantación y trazo activo en 3D
    if (finca.length >= 3) {
      final pathFinca = _camino3D(finca, vt);
      canvas.drawPath(
        pathFinca,
        Paint()
          ..color = const Color(0x243DD68C)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        pathFinca,
        Paint()
          ..color = const Color(0xD90A101D)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.2
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        pathFinca,
        Paint()
          ..color = const Color(0xFFF3F4F2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (final z in zonas) {
      if (z.contorno.length < 3) continue;
      final pathZona = _camino3D(z.contorno, vt);
      canvas.drawPath(
        pathZona,
        Paint()
          ..color = z.color.withValues(alpha: z.destacada ? 0.38 : 0.24)
          ..style = PaintingStyle.fill,
      );
      canvas.drawPath(
        pathZona,
        Paint()
          ..color = const Color(0xCCFFFFFF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = (z.destacada ? 3.2 : 2.2) + 1.6
          ..strokeJoin = StrokeJoin.round,
      );
      canvas.drawPath(
        pathZona,
        Paint()
          ..color = z.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = z.destacada ? 3.0 : 2.0
          ..strokeJoin = StrokeJoin.round,
      );

      final c = centroDe(z.contorno);
      final o = _proyectarPuntoPlano(c, vt, offsetElev: 6.0);
      canvas.drawCircle(o, z.destacada ? 9 : 7, Paint()..color = z.color);
      canvas.drawCircle(
        o,
        z.destacada ? 3.5 : 2.5,
        Paint()..color = const Color(0xFFFFFFFF),
      );
      _dibujarEtiquetaPastilla(
        canvas,
        texto: z.rotulo,
        centro: Offset(o.dx, o.dy + 16),
        fondo: const Color(0xEB14181F),
        borde: z.color,
        colorTexto: const Color(0xFFF3F4F2),
        tamFuente: 10.5,
      );
    }

    if (trazo.isNotEmpty) {
      final pathTrazo = _camino3D(
        trazo,
        vt,
        cerrado: trazo.length >= 3,
      );
      if (trazo.length >= 3) {
        canvas.drawPath(
          pathTrazo,
          Paint()
            ..color = const Color(0x383DD68C)
            ..style = PaintingStyle.fill,
        );
      }
      canvas.drawPath(
        pathTrazo,
        Paint()
          ..color = const Color(0xFF3DD68C)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeJoin = StrokeJoin.round,
      );
      for (final p in trazo) {
        final o = _proyectarPuntoPlano(p, vt, offsetElev: 5.0);
        canvas.drawCircle(
          o,
          6.5,
          Paint()..color = const Color(0xFF3DD68C),
        );
        canvas.drawCircle(
          o,
          2.8,
          Paint()..color = const Color(0xFFFFFFFF),
        );
      }
    }

    // 6. Rótulos cardinales anclados al borde del terreno 3D
    final mid = n ~/ 2;
    final cardinales = [
      (
        enIngles
            ? 'NORTH (${terreno.altoKm.toStringAsFixed(1)} km)'
            : 'NORTE (${terreno.altoKm.toStringAsFixed(1)} km)',
        0.0,
        -1.06,
        terreno.elev[0 * n + mid],
      ),
      (
        enIngles
            ? 'SOUTH (${terreno.altoKm.toStringAsFixed(1)} km)'
            : 'SUR (${terreno.altoKm.toStringAsFixed(1)} km)',
        0.0,
        1.06,
        terreno.elev[(n - 1) * n + mid],
      ),
      (
        enIngles
            ? 'EAST (${terreno.anchoKm.toStringAsFixed(1)} km)'
            : 'ESTE (${terreno.anchoKm.toStringAsFixed(1)} km)',
        1.06,
        0.0,
        terreno.elev[mid * n + (n - 1)],
      ),
      (
        enIngles
            ? 'WEST (${terreno.anchoKm.toStringAsFixed(1)} km)'
            : 'OESTE (${terreno.anchoKm.toStringAsFixed(1)} km)',
        -1.06,
        0.0,
        terreno.elev[mid * n + 0],
      ),
    ];
    for (final cd in cardinales) {
      final pt = vt.proyectar(cd.$2, cd.$3, cd.$4);
      if (estaOcluido(pt.x, pt.y, pt.depth, 0.04)) continue;
      _dibujarEtiquetaPastilla(
        canvas,
        texto: cd.$1,
        centro: Offset(
          pt.x.clamp(42.0, cw - 42.0),
          pt.y.clamp(14.0, ch - 14.0),
        ),
        fondo: const Color(0xE6191B1A),
        borde: const Color(0xFF2A2D2B),
        colorTexto: const Color(0xFFF3F4F2),
        tamFuente: 9.5,
      );
    }

    // 7. Línea de captación hidrológica y baliza del Punto de Interés (📍)
    final pu = (poiCol / (n - 1)) * 2.0 - 1.0;
    final pv = (poiFila / (n - 1)) * 2.0 - 1.0;
    final pElev = terreno.elevacionEn(poiFila, poiCol);
    final pPin = vt.proyectar(pu, pv, pElev);

    if (agua && cuerpoAgua != null) {
      final cwPt = cuerpoAgua!.punto;
      final pWater = vt.proyectar(cwPt.u, cwPt.v, cwPt.elev);

      canvas.drawLine(
        Offset(pPin.x, pPin.y),
        Offset(pWater.x, pWater.y),
        Paint()
          ..color = const Color(0xD807182E)
          ..strokeWidth = 3.6
          ..strokeCap = StrokeCap.round,
      );
      _dibujarLineaPunteada(
        canvas,
        Offset(pPin.x, pPin.y),
        Offset(pWater.x, pWater.y),
        Paint()
          ..color = const Color(0xFF38BDF8)
          ..strokeWidth = 2.0
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        Offset(pWater.x, pWater.y),
        4.5,
        Paint()..color = const Color(0xFF0284C7),
      );
      canvas.drawCircle(
        Offset(pWater.x, pWater.y),
        4.5,
        Paint()
          ..color = const Color(0xFFE0F2FE)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      final mx = (pPin.x + pWater.x) * 0.5;
      final my = (pPin.y + pWater.y) * 0.5;
      final dz = cuerpoAgua!.deltaZM;
      final gravTxt = dz <= 2
          ? (enIngles ? 'Gravity' : 'Gravedad')
          : 'ΔZ +${dz}m';
      final distBadge = enIngles
          ? '💧 Intake ${cuerpoAgua!.distanciaM} m ($gravTxt)'
          : '💧 Captación a ${cuerpoAgua!.distanciaM} m ($gravTxt)';
      _dibujarEtiquetaPastilla(
        canvas,
        texto: distBadge,
        centro: Offset(mx.clamp(65.0, cw - 65.0), my.clamp(16.0, ch - 16.0)),
        fondo: const Color(0xF0081C34),
        borde: const Color(0xFF38BDF8),
        colorTexto: const Color(0xFFBAE6FD),
        tamFuente: 9.5,
      );
    }

    // Anillo elíptico en la superficie y mástil vertical del POI
    final ryRing = 7.0 + 6.0 * (1.0 - vt.m);
    final poleHeight = 15.0 + 18.0 * vt.m;
    final rectRing = Rect.fromCenter(
      center: Offset(pPin.x, pPin.y),
      width: 26,
      height: ryRing * 2,
    );
    canvas.drawOval(
      rectRing,
      Paint()..color = const Color(0x40F59E0B),
    );
    canvas.drawOval(
      rectRing,
      Paint()
        ..color = const Color(0xF2F59E0B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
    canvas.drawLine(
      Offset(pPin.x, pPin.y),
      Offset(pPin.x, pPin.y - poleHeight),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = 2.2,
    );
    canvas.drawCircle(
      Offset(pPin.x, pPin.y),
      5.2,
      Paint()..color = const Color(0xFFF59E0B),
    );
    canvas.drawCircle(
      Offset(pPin.x, pPin.y),
      5.2,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );

    // Tarjeta flotante de telemetría del Punto de Interés
    final poiTemp = terreno
        .temperaturaEn(poiFila, poiCol, baseTemp: baseTemp)
        .toStringAsFixed(1);
    final poiMoist = terreno
        .humedadTierraEn(poiFila, poiCol, baseMoistPct: baseMoistPct)
        .round();
    final poiRain = terreno
        .lluviaEfectivaEn(
          poiFila,
          poiCol,
          lluviaBaseMm: lluviaBaseMm,
          lluvia14dMm: lluvia14dMm,
        )
        .toStringAsFixed(1);
    final poiSlope = terreno.pendienteEn(poiFila, poiCol).toStringAsFixed(1);
    final poiElevRound = pElev.round();

    var metrica = '$poiTemp °C · ${enIngles ? 'Moist' : 'Hum'}: $poiMoist%';
    if (capaActiva == 'rain') {
      metrica =
          '${enIngles ? 'Rain' : 'Lluvia'}: $poiRain mm/d · 14d: ${lluvia14dMm.toStringAsFixed(0)} mm';
    } else if (capaActiva == 'elev') {
      metrica = '$poiElevRound m s.n.m.';
    } else if (capaActiva == 'icta') {
      metrica =
          '$poiElevRound m (${poiElevRound < 500 ? '<500m' : '500-1500m'})';
    }

    final linea1 = '📍 $rotuloPoi ($poiElevRound m)';
    final linea2 =
        '$metrica · ${enIngles ? 'Slope' : 'Pend'}: $poiSlope%';

    _dibujarTarjetaPoi(
      canvas,
      size: size,
      ancla: Offset(pPin.x, pPin.y - poleHeight - 6),
      linea1: linea1,
      linea2: linea2,
    );
  }

  void _dibujarLineaPunteada(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint,
  ) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final dist = math.sqrt(dx * dx + dy * dy);
    if (dist < 1.0) return;
    final ux = dx / dist;
    final uy = dy / dist;
    const raya = 5.0;
    const hueco = 4.0;
    var d = 0.0;
    while (d < dist) {
      final fin = math.min(dist, d + raya);
      canvas.drawLine(
        Offset(a.dx + ux * d, a.dy + uy * d),
        Offset(a.dx + ux * fin, a.dy + uy * fin),
        paint,
      );
      d += raya + hueco;
    }
  }

  void _dibujarEtiquetaPastilla(
    Canvas canvas, {
    required String texto,
    required Offset centro,
    required Color fondo,
    required Color borde,
    required Color colorTexto,
    double tamFuente = 10.0,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: texto,
        style: letra(tamFuente, peso: 600, color: colorTexto),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final w = tp.width + 12;
    final h = tp.height + 5;
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: centro, width: w, height: h),
      const Radius.circular(6),
    );
    canvas.drawRRect(rect, Paint()..color = fondo);
    canvas.drawRRect(
      rect,
      Paint()
        ..color = borde
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
    tp.paint(canvas, Offset(centro.dx - tp.width / 2, centro.dy - tp.height / 2));
  }

  void _dibujarTarjetaPoi(
    Canvas canvas, {
    required Size size,
    required Offset ancla,
    required String linea1,
    required String linea2,
  }) {
    final tp1 = TextPainter(
      text: TextSpan(
        text: linea1,
        style: letra(11.5, peso: 700, color: const Color(0xFF3DD68C)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width - 24);

    final tp2 = TextPainter(
      text: TextSpan(
        text: linea2,
        style: letra(10.5, peso: 600, color: const Color(0xFFF3F4F2)),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: size.width - 24);

    final boxW = math.max(tp1.width, tp2.width) + 20;
    final boxH = tp1.height + tp2.height + 12;
    final bx = ancla.dx.clamp(boxW / 2 + 6, size.width - boxW / 2 - 6);
    final by = ancla.dy.clamp(boxH + 8, size.height - 8);

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(bx - boxW / 2, by - boxH, boxW, boxH),
      const Radius.circular(9),
    );
    canvas.drawRRect(rrect, Paint()..color = const Color(0xF214181F));
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = const Color(0xFF3DD68C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    tp1.paint(canvas, Offset(bx - tp1.width / 2, by - boxH + 5));
    tp2.paint(
      canvas,
      Offset(bx - tp2.width / 2, by - boxH + 7 + tp1.height),
    );
  }

  @override
  bool shouldRepaint(covariant _PintorTopo3D viejo) => true;
}

/// Panel de controles de capas 3D y tarjetas de telemetría satelital/topográfica
/// para [PantallaMapaFinca].
class PanelTelemetria3D extends StatefulWidget {
  const PanelTelemetria3D({super.key, this.controlador});

  final ControladorTopo3D? controlador;

  @override
  State<PanelTelemetria3D> createState() => _EstadoPanelTelemetria3D();
}

class _EstadoPanelTelemetria3D extends State<PanelTelemetria3D> {
  late ControladorTopo3D _ctrl =
      widget.controlador ?? ControladorTopo3D.instancia;

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(_alCambiar);
  }

  @override
  void didUpdateWidget(PanelTelemetria3D viejo) {
    super.didUpdateWidget(viejo);
    final nuevo = widget.controlador ?? ControladorTopo3D.instancia;
    if (nuevo != _ctrl) {
      _ctrl.removeListener(_alCambiar);
      _ctrl = nuevo;
      _ctrl.addListener(_alCambiar);
    }
  }

  @override
  void dispose() {
    _ctrl.removeListener(_alCambiar);
    super.dispose();
  }

  void _alCambiar() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final parcela = estado.parcela;
    if (parcela == null) return const SizedBox.shrink();

    final terreno =
        estado.terreno ??
        MallaTerreno.sintetica(
          latitud: parcela.latitud,
          longitud: parcela.longitud,
          elevacionBase: parcela.elevacion,
        );
    _ctrl.asegurarPoiInicial(estado, terreno);

    final poiFila = (_ctrl.poiFila ?? (terreno.n ~/ 2)).clamp(0, terreno.n - 1);
    final poiCol = (_ctrl.poiCol ?? (terreno.n ~/ 2)).clamp(0, terreno.n - 1);

    final p = estado.plantacion;
    final rec = estado.recomendacion;
    final mesActual = estado.hoy.month.clamp(1, 12);
    final climMes =
        terreno.climatologia[mesActual] ?? climatologiaBaseNasa[mesActual]!;

    final baseTemp = rec.temperaturaActual ?? climMes.tmax;
    final baseMoistPct =
        rec.humedadTierraPct ??
        (estado.clima.isNotEmpty
            ? (rec.reserva * 100.0).clamp(18.0, 92.0)
            : climMes.humedadSueloPct);
    final lluviaBaseMm = estado.clima.isNotEmpty
        ? (estado.clima.last.lluvia ?? climMes.lluviaMmDia)
        : climMes.lluviaMmDia;
    final lluvia14dMm = rec.lluvia14dMm ?? (climMes.lluviaMmDia * 14.0);
    final rhPct = (rec.humedadRelativaActual ?? climMes.rh2m).round();

    final humedadPoi = terreno
        .humedadTierraEn(poiFila, poiCol, baseMoistPct: baseMoistPct)
        .round();
    final tempPoi = terreno.temperaturaEn(
      poiFila,
      poiCol,
      baseTemp: baseTemp,
    );
    final elevPoi = terreno.elevacionEn(poiFila, poiCol).round();
    final pendientePoi = terreno.pendienteEn(poiFila, poiCol);
    final lluviaDiaPoi = terreno.lluviaEfectivaEn(
      poiFila,
      poiCol,
      lluviaBaseMm: lluviaBaseMm,
      lluvia14dMm: lluvia14dMm,
    );

    final poiLatLon = terreno.latLonDeFilaCol(poiFila, poiCol);
    final cw =
        terreno.evaluarCuerpoAguaCercano(poiLatLon.lat, poiLatLon.lon) ??
        estado.cuerpoAguaDe(p);

    final infilPct = ((0.92 - pendientePoi * 0.011).clamp(0.35, 0.95) * 100)
        .round();

    final capas = <(String, String)>[
      ('moist', t.bilingue('💧 Humedad (%)', '💧 Moisture (%)')),
      ('temp', t.bilingue('🌡️ Temp (°C)', '🌡️ Temp (°C)')),
      ('rain', t.bilingue('🌧️ Lluvia (mm)', '🌧️ Rain (mm)')),
      ('elev', t.bilingue('⛰️ Altitud (m)', '⛰️ Altitude (m)')),
      ('slope', t.bilingue('📐 Escorrentía (%)', '📐 Runoff (%)')),
      ('icta', t.bilingue('🌱 ICTA', '🌱 ICTA')),
    ];

    final verde = Paleta.de(context, Paleta.verde);
    final tarjeta = Paleta.de(context, Paleta.tarjeta);
    final tenue = Paleta.de(context, Paleta.tenue);
    final texto = Paleta.de(context, Paleta.texto);

    Widget chipCapa(String id, String rotulo) {
      final activo = _ctrl.capaActiva == id;
      return CupertinoButton(
        key: Key('capa-3d-$id'),
        padding: EdgeInsets.zero,
        minimumSize: const Size(44, 38),
        onPressed: () {
          HapticFeedback.selectionClick();
          _ctrl.cambiarCapa(id);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: activo ? verde : tenue,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Text(
            rotulo,
            style: letra(
              14,
              peso: activo ? 700 : 500,
              color: activo ? tarjeta : texto,
            ),
          ),
        ),
      );
    }

    Widget toggleOverlay(String clave, String rotulo, bool activo, VoidCallback fn) =>
        CupertinoButton(
          key: Key(clave),
          padding: EdgeInsets.zero,
          minimumSize: const Size(44, 36),
          onPressed: () {
            HapticFeedback.selectionClick();
            fn();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: activo ? verde.withValues(alpha: 0.16) : tenue,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: activo ? verde : tenue,
                width: 1.2,
              ),
            ),
            child: Text(
              rotulo,
              style: letra(
                13.5,
                peso: activo ? 650 : 500,
                color: activo ? verde : texto,
              ),
            ),
          ),
        );

    final esZonaBaja = elevPoi < 500;
    final pisoIcta = esZonaBaja
        ? t.bilingue(
            'Zona Baja (< 500 m) · Maíz ICTA HB-83 / ICTA B-7 · Frijol ICTA Chortí / ICTA Ligero',
            'Lowland (< 500 m) · Maize ICTA HB-83 / ICTA B-7 · Bean ICTA Chortí / ICTA Ligero',
          )
        : t.bilingue(
            'Zona Media (500–1500 m) · Maíz ICTA B-15 / ICTA Maya · Frijol ICTA Patriarca / ICTA Hunapú',
            'Midland (500–1500 m) · Maize ICTA B-15 / ICTA Maya · Bean ICTA Patriarca / ICTA Hunapú',
          );

    final diagPendiente = pendientePoi >= 16.0
        ? t.bilingue(
            'Escorrentía alta (infiltra $infilPct%) · Traza surcos en contorno y barreras vivas',
            'High runoff (infiltrates $infilPct%) · Use contour furrows and live barriers',
          )
        : pendientePoi >= 8.0
        ? t.bilingue(
            'Escorrentía moderada (infiltra $infilPct%) · Conviene cobertura de rastrojo',
            'Moderate runoff (infiltrates $infilPct%) · Crop residue mulch recommended',
          )
        : t.bilingue(
            'Infiltración favorable ($infilPct%) · Pendiente suave de valle',
            'Favorable infiltration ($infilPct%) · Gentle valley slope',
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (estado.capa == CapaMapa.relieve3d) ...[
          const SizedBox(height: Espacio.s),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: Espacio.xs),
            child: Row(
              children: [
                for (var i = 0; i < capas.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  chipCapa(capas[i].$1, capas[i].$2),
                ],
              ],
            ),
          ),
          const SizedBox(height: Espacio.s),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              toggleOverlay(
                'toggle-3d-perspectiva',
                _ctrl.morph3D >= 0.5
                    ? t.bilingue('Vista: 3D Relieve', 'View: 3D Relief')
                    : t.bilingue('Vista: 2D Plano', 'View: 2D Flat'),
                _ctrl.morph3D >= 0.5,
                () => _ctrl.fijarMorph3D(_ctrl.morph3D >= 0.5 ? 0.0 : 1.0),
              ),
              toggleOverlay(
                'toggle-3d-curvas',
                t.bilingue('Curvas 50m', 'Contours 50m'),
                _ctrl.curvas,
                _ctrl.alternarCurvas,
              ),
              toggleOverlay(
                'toggle-3d-flujo',
                t.bilingue('Escorrentía', 'Runoff flow'),
                _ctrl.flujo,
                _ctrl.alternarFlujo,
              ),
              toggleOverlay(
                'toggle-3d-agua',
                t.bilingue('🌊 Ríos', '🌊 Rivers'),
                _ctrl.agua,
                _ctrl.alternarAgua,
              ),
              toggleOverlay(
                'sync-terreno-3d',
                estado.cargandoTerreno
                    ? t.sincronizando
                    : t.bilingue('Actualizar DEM', 'Update DEM'),
                terreno.esRemoto,
                () => estado.actualizarTerreno(),
              ),
            ],
          ),
        ],
        Rotulo(
          t.bilingue(
            'Telemetría satelital y topográfica',
            'Satellite and topographic telemetry',
          ),
        ),
        Grupo(
          children: [
            Fila(
              key: const Key('telemetria-humedad-tierra'),
              titulo: t.bilingue(
                'Humedad de la tierra · $humedadPoi %',
                'Soil moisture · $humedadPoi %',
              ),
              detalle: t.bilingue(
                'Lluvia 14 d: ${lluvia14dMm.toStringAsFixed(1)} mm (${lluviaDiaPoi.toStringAsFixed(1)} mm/d) · HR $rhPct %',
                '14 d rain: ${lluvia14dMm.toStringAsFixed(1)} mm (${lluviaDiaPoi.toStringAsFixed(1)} mm/d) · RH $rhPct %',
              ),
              icono: CupertinoIcons.drop_fill,
            ),
            Fila(
              key: const Key('telemetria-temp-altitud'),
              titulo: t.bilingue(
                'Temperatura y altitud · ${tempPoi.toStringAsFixed(1)} °C · $elevPoi m',
                'Temperature & altitude · ${tempPoi.toStringAsFixed(1)} °C · $elevPoi m',
              ),
              detalle: t.bilingue(
                'Rango SRTM: ${terreno.minElev.round()}–${terreno.maxElev.round()} m s.n.m. · ${terreno.fuenteDem}',
                'SRTM range: ${terreno.minElev.round()}–${terreno.maxElev.round()} m a.s.l. · ${terreno.fuenteDem}',
              ),
              icono: CupertinoIcons.thermometer,
            ),
            if (cw != null)
              Fila(
                key: const Key('telemetria-cuerpo-agua'),
                titulo: t.bilingue(
                  'Cuerpo de agua · ${cw.nombre} (${cw.distanciaM} m)',
                  'Water body · ${cw.nombre} (${cw.distanciaM} m)',
                ),
                detalle: cw.deltaZM <= 3
                    ? t.bilingue(
                        '${cw.tipo} · Captación por gravedad factible (ΔZ ${cw.deltaZM} m)',
                        '${cw.tipo} · Gravity intake feasible (ΔZ ${cw.deltaZM} m)',
                      )
                    : t.bilingue(
                        '${cw.tipo} · Requiere bombeo (ΔZ +${cw.deltaZM} m)',
                        '${cw.tipo} · Pumping required (ΔZ +${cw.deltaZM} m)',
                      ),
                icono: CupertinoIcons.waveform_path,
              ),
            Fila(
              key: const Key('telemetria-pendiente'),
              titulo: t.bilingue(
                'Pendiente y escorrentía · ${pendientePoi.toStringAsFixed(1)} %',
                'Slope and runoff · ${pendientePoi.toStringAsFixed(1)} %',
              ),
              detalle: diagPendiente,
              icono: CupertinoIcons.compass,
            ),
            Fila(
              key: const Key('telemetria-icta'),
              titulo: t.bilingue(
                'Zonificación ICTA · $elevPoi m s.n.m.',
                'ICTA Zoning · $elevPoi m a.s.l.',
              ),
              detalle: pisoIcta,
              icono: CupertinoIcons.leaf_arrow_circlepath,
            ),
          ],
        ),
      ],
    );
  }
}
