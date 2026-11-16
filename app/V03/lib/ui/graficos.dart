/// Gráficos dibujados a mano: las barras de agua de los últimos días. No
/// dependen de ninguna biblioteca.
library;

import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';

import '../motor/fao56.dart';
import 'tema.dart';

/// Barras de agua en la zona de raíces por día. El color indica estrés y los
/// días estimados se dibujan más tenues. Encima, un punto marca la lluvia.
class BarrasAgua extends StatelessWidget {
  const BarrasAgua({super.key, required this.dias});

  final List<EstadoDia> dias;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 96,
    width: double.infinity,
    child: CustomPaint(
      painter: _PintorBarras(
        dias,
        bien: Paleta.de(context, Paleta.verde),
        atencion: Paleta.de(context, Paleta.ambar),
        estres: Paleta.de(context, Paleta.rojo),
        lluvia: Paleta.de(context, Paleta.azul),
        fondo: Paleta.de(context, Paleta.tenue),
      ),
    ),
  );
}

class _PintorBarras extends CustomPainter {
  _PintorBarras(
    this.dias, {
    required this.bien,
    required this.atencion,
    required this.estres,
    required this.lluvia,
    required this.fondo,
  });

  final List<EstadoDia> dias;
  final Color bien;
  final Color atencion;
  final Color estres;
  final Color lluvia;
  final Color fondo;

  @override
  void paint(Canvas canvas, Size size) {
    if (dias.isEmpty) return;
    const altoLluvia = 14.0;
    final n = dias.length;
    final paso = size.width / n;
    final ancho = math.min(paso * 0.62, 14.0);
    final altoBarras = size.height - altoLluvia;
    for (var i = 0; i < n; i++) {
      final d = dias[i];
      final x = paso * i + (paso - ancho) / 2;
      final pista = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, altoLluvia, ancho, altoBarras),
        Radius.circular(ancho / 2),
      );
      canvas.drawRRect(pista, Paint()..color = fondo);

      final Color color;
      if (d.ks < 1) {
        color = estres;
      } else if (d.agotamiento > 0.8 * d.aguaFacil) {
        color = atencion;
      } else {
        color = bien;
      }
      final alto = math.max(altoBarras * d.reserva, ancho);
      final barra = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, altoLluvia + altoBarras - alto, ancho, alto),
        Radius.circular(ancho / 2),
      );
      canvas.drawRRect(
        barra,
        Paint()..color = color.withValues(alpha: d.estimado ? 0.38 : 1),
      );

      if ((d.lluvia ?? 0) + d.riego >= 1) {
        final radio = (1.5 + math.sqrt((d.lluvia ?? 0) + d.riego) * 0.45).clamp(
          2.0,
          4.5,
        );
        canvas.drawCircle(
          Offset(x + ancho / 2, altoLluvia / 2 - 1),
          radio,
          Paint()..color = lluvia,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PintorBarras anterior) =>
      anterior.dias != dias || anterior.bien != bien || anterior.fondo != fondo;
}
