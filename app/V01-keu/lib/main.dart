import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart' show GlobalWidgetsLocalizations;

import 'datos/almacen.dart';
import 'estado.dart';
import 'ui/ajustes.dart';
import 'ui/bienvenida.dart';
import 'ui/hoy.dart';
import 'ui/registro.dart';
import 'ui/tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final estado = AppEstado(await Almacen.abrir());
  runApp(FieldShift(estado: estado));
  // Al abrir, se intenta actualizar el clima; solo corre si hay wifi.
  if (estado.configurada) estado.sincronizar();
}

class FieldShift extends StatelessWidget {
  const FieldShift({super.key, required this.estado});

  final AppEstado estado;

  @override
  Widget build(BuildContext context) => Alcance(
        estado: estado,
        child: Builder(
          builder: (context) {
            final e = Alcance.de(context);
            return CupertinoApp(
              title: 'Field Shift',
              debugShowCheckedModeBanner: false,
              theme: temaApp(null),
              locale: Locale(e.idioma),
              supportedLocales: const [Locale('es'), Locale('en')],
              localizationsDelegates: const [
                GlobalCupertinoLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              home: e.configurada ? const Principal() : const Bienvenida(),
            );
          },
        ),
      );
}

/// Las tres pestañas de la app una vez configurada.
class Principal extends StatelessWidget {
  const Principal({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Alcance.de(context).txt;
    return CupertinoTabScaffold(
      tabBar: CupertinoTabBar(
        backgroundColor: Paleta.de(context, Paleta.fondo),
        activeColor: Paleta.de(context, Paleta.verde),
        inactiveColor: Paleta.de(context, Paleta.secundario),
        border: Border(top: BorderSide(color: Paleta.de(context, Paleta.tenue), width: 0.5)),
        items: [
          BottomNavigationBarItem(icon: const Icon(CupertinoIcons.drop), label: t.hoy),
          BottomNavigationBarItem(icon: const Icon(CupertinoIcons.square_list), label: t.registros),
          BottomNavigationBarItem(icon: const Icon(CupertinoIcons.gear), label: t.ajustes),
        ],
      ),
      tabBuilder: (context, indice) => CupertinoTabView(
        builder: (context) => switch (indice) {
          0 => const PestanaHoy(),
          1 => const PestanaRegistros(),
          _ => const PestanaAjustes(),
        },
      ),
    );
  }
}
