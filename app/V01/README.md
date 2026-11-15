# Field Shift

App Android (Flutter) para decidir riego y manejo de una parcela sin depender de la señal. Proyecto del equipo de Ciudad de Guatemala para *Field Shift: Adapting Farms with NASA Data*, NASA Space Apps Challenge 2026.

## Qué hace

1. El productor fija el punto de su parcela (GPS o coordenadas) y describe su plantación: cultivo, fecha, suelo, tipo y temporada de riego, plaga reciente y fertilización.
2. Con wifi, la app descarga el clima diario de NASA POWER para ese punto y lo guarda en el teléfono.
3. Cada semana el productor registra riegos, plaga y fertilizante.
4. La app calcula el agua disponible en la zona de raíces (FAO-56) y recomienda qué hacer.

Todo funciona sin conexión salvo la descarga del clima, que solo corre con wifi.

## Estructura

| Carpeta | Contenido |
|---|---|
| `lib/motor/` | Cálculo en Dart puro: ET₀ Penman-Monteith, balance diario de agua y recomendador |
| `lib/datos/` | Almacenamiento local y descarga de NASA POWER |
| `lib/ui/` | Sistema de diseño (`tema.dart`), gráficos y pantallas |
| `lib/modelos.dart` | Parcela, plantación, registro semanal, clima y catálogo de cultivos |
| `lib/textos.dart` | Textos en español e inglés |
| `test/` | Pruebas del motor y de las pantallas; `test/capturas/` guarda una imagen de cada pantalla |

## Cómo correrla

Flutter 3.50 o superior.

```bash
flutter pub get
```

```bash
flutter test
```

```bash
flutter run
```

Para generar el APK:

```bash
flutter build apk --release
```

Para regenerar las imágenes de las pantallas tras un cambio de diseño:

```bash
flutter test test/pantallas_test.dart --update-goldens
```

## Dónde conectar la red neuronal

`lib/motor/recomendador.dart` expone una sola función, `recomendar(...)`, que recibe parcela, plantación, clima y registros y devuelve un objeto `Recomendacion`. Hoy usa el balance de agua FAO-56 y reglas simples. Un modelo entrenado puede reemplazarla o complementarla manteniendo ese mismo tipo de salida, sin tocar las pantallas.

## Supuestos y límites

- **Lámina por riego.** Cada riego registrado se convierte en milímetros según el tipo: manual 4, goteo 6, aspersión 12, surcos 30. Son supuestos de trabajo, no mediciones.
- **Suelo.** Agua disponible por textura de FAO-56: arenoso 100, franco 150 y arcilloso 180 mm por metro.
- **Estado inicial.** El balance arranca con la mitad del agua disponible gastada.
- **Clima.** NASA POWER representa una celda de unos 50 km y publica con 3 o 4 días de retraso; los días sin dato se completan con el promedio reciente y lluvia cero. Su lluvia puede estar sobreestimada en el oriente de Guatemala.
- **Elevación.** Se usa la de la celda de NASA POWER, que puede diferir de la parcela.
- **Cultivos.** Maíz y frijol usan parámetros de FAO-56 e ICTA del repositorio del equipo. Los de café y tomate, y los factores Ky de FAO-33, están citados de memoria y hay que verificarlos.
- **Almacenamiento.** Se usa un almacén clave-valor con JSON. Para históricos largos convendría migrar a SQLite; `lib/datos/almacen.dart` aísla ese cambio.
- **Sincronización.** Ocurre al abrir la app y al pedirla; no hay tarea en segundo plano.
- **Sin validar en campo.** La recomendación apoya la decisión del productor; no la reemplaza.

## Créditos

- Clima: NASA POWER (MERRA-2 y CERES).
- Método: FAO-56 (Allen et al., 1998) y FAO-33 (Doorenbos y Kassam, 1979).
- Tipografía: Inter, licencia SIL OFL (`assets/fuentes/OFL.txt`).
