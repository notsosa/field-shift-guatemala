// Pruebas del fondo de mapa del plano de la finca, con un servicio de mentira
// que no usa internet.
import 'dart:convert';
import 'dart:typed_data';

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:field_shift/datos/almacen.dart';
import 'package:field_shift/datos/mapa.dart';
import 'package:field_shift/estado.dart';
import 'package:field_shift/ui/finca.dart';
import 'package:field_shift/ui/ubicar.dart';
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
  Future<Uint8List?> tesela(CapaMapa capa, int z, int x, int y, {bool guardar = true}) async {
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

  test('latitud y longitud van y vuelven de la proyección del mapa', () {
    final (x, y) = mundoDe(14.8250, -89.5312);
    final (lat, lon) = latLonDe(x, y);
    expect(lat, closeTo(14.8250, 1e-9));
    expect(lon, closeTo(-89.5312, 1e-9));
    expect(latLonDe(0.5, 0.5), (0.0, 0.0));
  });

  testWidgets('ubicar la finca: al arrastrar el mapa cambia el punto elegido', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final estado = AppEstado(await Almacen.abrir(), servicioMapa: _MapaFijo(_png));
    (double, double)? elegido;
    await tester.pumpWidget(Alcance(
      estado: estado,
      child: CupertinoApp(
        home: Builder(
          builder: (context) => Center(
            child: CupertinoButton(
              onPressed: () async => elegido = await Navigator.of(context).push<(double, double)>(
                CupertinoPageRoute(builder: (_) => const PantallaUbicar(latitud: 14.6, longitud: -90.5)),
              ),
              child: const Text('abrir'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    expect(find.text('14.60000, -90.50000'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);

    // Arrastrar el mapa hacia la izquierda y hacia arriba lleva el centro al
    // este y al sur.
    await tester.drag(find.byKey(const Key('mapa-explorable')), const Offset(-120, -80));
    await tester.pumpAndSettle();
    expect(find.text('14.60000, -90.50000'), findsNothing);

    // Acercar con el botón no mueve el centro.
    await tester.tap(find.byIcon(CupertinoIcons.plus));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usar este punto'));
    await tester.pumpAndSettle();
    expect(elegido, isNotNull);
    expect(elegido!.$2, greaterThan(-90.5)); // más al este
    expect(elegido!.$1, lessThan(14.6)); // más al sur
    // A zoom 15, 120 px son unos 550 m: el punto se movió poco, no saltó.
    expect(elegido!.$2, closeTo(-90.5, 0.02));
    expect(elegido!.$1, closeTo(14.6, 0.02));
  });

  test('explorar el mapa no escribe teselas en el teléfono', () async {
    SharedPreferences.setMockInitialValues({});
    final almacen = await Almacen.abrir();
    final servicio = ServicioMapa(
      almacen,
      cliente: MockClient((_) async => http.Response.bytes(_png, 200)),
      hayWifi: () async => true,
    );
    expect(await servicio.tesela(CapaMapa.mapa, 10, 3, 4, guardar: false), _png);
    expect(almacen.leerTesela('mapa/10/3/4'), isNull);
    expect(await servicio.tesela(CapaMapa.mapa, 10, 5, 6), _png);
    expect(almacen.leerTesela('mapa/10/5/6'), _png);
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
