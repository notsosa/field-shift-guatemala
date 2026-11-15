// Pruebas del fondo de mapa del plano de la finca, con un servicio de mentira
// que no usa internet.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/datos/mapa.dart';
import 'package:field_shift/ui/finca.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// PNG de 1 × 1 píxel.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==');

class _MapaFijo extends ServicioMapa {
  _MapaFijo(this.imagen) : super(null);

  final Uint8List? imagen;
  int pedidas = 0;

  @override
  Future<Uint8List?> tesela(CapaMapa capa, int z, int x, int y) async {
    pedidas++;
    return imagen;
  }
}

Widget _lienzo(ServicioMapa servicio, {double lado = 500}) => CupertinoApp(
      home: Center(
        child: SizedBox(
          width: 360,
          height: 360,
          child: FondoMapa(
            servicio: servicio,
            capa: CapaMapa.mapa,
            latitud: 14.8250,
            longitud: -89.5312,
            lado: lado,
            aviso: 'Sin mapa guardado',
          ),
        ),
      ),
    );

void main() {
  testWidgets('dibuja las teselas que cubren la ventana y la atribución', (tester) async {
    final servicio = _MapaFijo(_png);
    await tester.pumpWidget(_lienzo(servicio));
    await tester.pumpAndSettle();
    expect(servicio.pedidas, inInclusiveRange(4, 25));
    expect(find.byType(Image), findsNWidgets(servicio.pedidas));
    expect(find.text('© OpenStreetMap'), findsOneWidget);
    expect(find.text('Sin mapa guardado'), findsNothing);

    // Cada tesela queda dentro o tocando el lienzo, nunca lejos de él.
    final caja = tester.getRect(find.byType(FondoMapa));
    final colocadas = find.descendant(of: find.byType(FondoMapa), matching: find.byType(Positioned));
    for (final e in tester.widgetList<Positioned>(colocadas).where((p) => p.width != null)) {
      expect(e.left! + e.width!, greaterThan(0));
      expect(e.left!, lessThan(caja.width));
      expect(e.top! + e.height!, greaterThan(0));
      expect(e.top!, lessThan(caja.height));
    }
  });

  testWidgets('sin imágenes muestra el aviso', (tester) async {
    await tester.pumpWidget(_lienzo(_MapaFijo(null)));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsNothing);
    expect(find.text('Sin mapa guardado'), findsOneWidget);
  });

  test('descarga con wifi, guarda en el teléfono y luego no vuelve a pedir', () async {
    SharedPreferences.setMockInitialValues({});
    final almacen = await Almacen.abrir();
    var pedidos = 0;
    Uri? ultima;
    final cliente = MockClient((peticion) async {
      pedidos++;
      ultima = peticion.url;
      expect(peticion.headers['User-Agent'], isNotEmpty);
      return http.Response.bytes(_png, 200);
    });

    final servicio = ServicioMapa(almacen, cliente: cliente, hayWifi: () async => true);
    expect(await servicio.tesela(CapaMapa.mapa, 18, 65883, 120186), _png);
    expect(ultima.toString(), 'https://tile.openstreetmap.org/18/65883/120186.png');
    expect(await servicio.tesela(CapaMapa.satelite, 18, 65883, 120186), _png);
    expect(ultima!.path, endsWith('/World_Imagery/MapServer/tile/18/120186/65883'));
    expect(pedidos, 2);

    // Otro arranque, sin wifi: sale de lo guardado.
    final sinRed = ServicioMapa(almacen, cliente: cliente, hayWifi: () async => false);
    expect(await sinRed.tesela(CapaMapa.mapa, 18, 65883, 120186), _png);
    expect(await sinRed.tesela(CapaMapa.mapa, 18, 1, 1), isNull);
    expect(pedidos, 2);
  });
}
