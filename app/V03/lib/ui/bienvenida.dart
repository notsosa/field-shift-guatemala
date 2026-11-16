import 'package:cupertino_ui/cupertino_ui.dart';

import '../estado.dart';
import 'parcela.dart';
import 'tema.dart';

/// Primera pantalla: explica la app en tres ideas y deja empezar o ver un ejemplo.
class Bienvenida extends StatelessWidget {
  const Bienvenida({super.key});

  @override
  Widget build(BuildContext context) {
    final estado = Alcance.de(context);
    final t = estado.txt;
    final verde = Paleta.de(context, Paleta.verde);

    Widget ventaja(IconData icono, String titulo, String detalle) => Padding(
      padding: const EdgeInsets.only(bottom: Espacio.l),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 26, color: verde),
          const SizedBox(width: Espacio.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: Texto.fuerte(context)),
                const SizedBox(height: 2),
                Text(detalle, style: Texto.nota(context)),
              ],
            ),
          ),
        ],
      ),
    );

    return CupertinoPageScaffold(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: Espacio.l),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 12),
                onPressed: () =>
                    Alcance.leer(context).cambiarIdioma(t.en ? 'es' : 'en'),
                child: Text(
                  t.en ? 'Español' : 'English',
                  style: letra(15, peso: 500, color: verde),
                ),
              ),
            ),
            const SizedBox(height: Espacio.m),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: verde,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(
                CupertinoIcons.drop_fill,
                color: Paleta.de(context, Paleta.tarjeta),
                size: 30,
              ),
            ),
            const SizedBox(height: Espacio.l),
            Text(
              t.app,
              style: letra(
                40,
                peso: 700,
                color: Paleta.de(context, Paleta.texto),
                espaciado: -1.4,
                alto: 1.05,
              ),
            ),
            const SizedBox(height: Espacio.s),
            Text(
              t.lema,
              style: letra(
                18,
                color: Paleta.de(context, Paleta.secundario),
                alto: 1.35,
                espaciado: -0.2,
              ),
            ),
            const SizedBox(height: Espacio.xl + Espacio.s),
            ventaja(CupertinoIcons.wifi_slash, t.ventaja1, t.ventaja1d),
            ventaja(CupertinoIcons.square_pencil, t.ventaja2, t.ventaja2d),
            ventaja(CupertinoIcons.checkmark_seal, t.ventaja3, t.ventaja3d),
            const SizedBox(height: Espacio.m),
            BotonPrincipal(
              texto: t.empezar,
              alPulsar: () => Navigator.of(context).push(
                CupertinoPageRoute<void>(
                  builder: (_) => const PantallaParcela(primeraVez: true),
                ),
              ),
            ),
            BotonPrincipal(
              texto: t.verEjemplo,
              secundario: true,
              alPulsar: () async {
                final e = Alcance.leer(context);
                await e.cargarEjemplo();
                await e.sincronizar();
              },
            ),
            const SizedBox(height: Espacio.s),
          ],
        ),
      ),
    );
  }
}
