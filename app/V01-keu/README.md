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

## Demo en el navegador

La misma app corre en Chrome; el clima de NASA POWER se descarga desde el navegador y los datos quedan en el almacenamiento local de la página. No hace falta Android.

```bash
cd app/V01-keu
flutter pub get
flutter build web --release
python -m http.server 8787 -d build/web
```

Abre `http://localhost:8787`. En Windows, si Flutter no está en el PATH, usa la ruta completa (`C:/Users/velas/dev/flutter/bin/flutter.bat`). El guion paso a paso del piloto está en `proyecto/demo-piloto.md`.

En el navegador: "Usar mi ubicación" pide permiso al navegador y puede fallar; escribe las coordenadas a mano. La app trata la web como conectada (no puede distinguir wifi de datos móviles). Para empezar de cero: Ajustes, "Borrar todos los datos". `build/` no se sube al repositorio.

## Qué cambia esta copia (`V01-keu`) respecto a `V01`

Esta carpeta es una copia de la app del compañero con cinco arreglos acotados del motor y del manejo, cada uno con pruebas en `test/`:

1. **Agua del subsuelo.** Antes, al crecer las raíces, el suelo recién alcanzado entraba siempre con el agotamiento inicial, sin importar si había llovido antes. Ahora el suelo bajo las raíces lleva su propio almacén (empieza con el agotamiento inicial, recibe lo que drena de la zona de raíces y no pierde nada más; lo que sobra es drenaje profundo) y el balance conserva el agua dentro de 1e-6 mm (para eso la ETa también se limita al agua que de verdad cabe en la zona de raíces). En un periodo seco antes de que crezca la raíz el resultado no cambia; en uno húmedo hay menos agotamiento que antes.
2. **Lluvia sin dato.** Un día cuya lluvia falta queda marcado como estimado y cuenta en `diasEstimados`; la lluvia no se inventa. La precisión baja un punto si hay días estimados en los últimos siete, salvo el retraso normal de publicación de NASA POWER (hasta 5 días tras el último clima observado): ese retraso no la baja, pero una lluvia faltante, un hueco dentro de lo observado o un retraso mayor sí. `diasEstimados` cuenta todos los días estimados.
3. **Rendimiento dentro del ciclo.** El factor de rendimiento (FAO-33) suma solo de la siembra a la cosecha; ya no baja por los días posteriores.
4. **Tipo de plaga.** Campo estructurado en la plantación y en el registro semanal, con la lista por cultivo en `tiposPlagaPorCultivo` (`lib/modelos.dart`). Café: roya, minador, antracnosis y otra. Cada tipo lleva sus nombres ES/EN en esa estructura (un tipo sin nombre se muestra con su id). Los demás cultivos solo tienen "otra / sin especificar" y no preguntan el tipo hasta que el compañero que investiga las plagas comunes entregue sus listas (es agregar datos). Solo registro y el recordatorio existente: sin predicción ni umbrales.
5. **Abonar solo si hay agua.** El recordatorio de fertilizar sale solo si llovió 1 mm o más en los últimos siete días o la plantación tiene riego; si no, la app muestra "Fertilizar: en espera".

La captura `test/capturas/09_hoy_oscuro.png` cambió por el arreglo 1.

**Fuera de alcance:** cambiar la fuente de lluvia (sigue siendo NASA POWER, no IMERG ni ERA5), el número de curva por suelo, el Ky por etapa, los parámetros de cultivo y cualquier red neuronal.

## Dónde conectar la red neuronal

`lib/motor/recomendador.dart` expone una sola función, `recomendar(...)`, que recibe parcela, plantación, clima y registros y devuelve un objeto `Recomendacion`. Hoy usa el balance de agua FAO-56 y reglas simples. Un modelo entrenado puede reemplazarla o complementarla manteniendo ese mismo tipo de salida, sin tocar las pantallas.

## Supuestos y límites

- **Lámina por riego.** Cada riego registrado se convierte en milímetros según el tipo: manual 4, goteo 6, aspersión 12, surcos 30. Son supuestos de trabajo, no mediciones.
- **Suelo.** Agua disponible por textura de FAO-56: arenoso 100, franco 150 y arcilloso 180 mm por metro.
- **Estado inicial.** El balance arranca con la mitad del agua disponible gastada.
- **Clima.** NASA POWER representa una celda de unos 50 km y publica con 3 o 4 días de retraso; los días sin dato se completan con el promedio reciente de ET₀ y lluvia cero, y quedan marcados como estimados; un día con datos pero sin lluvia conserva su propia ET₀, solo recibe lluvia cero (no se inventa) y también queda como estimado. Su lluvia puede estar sobreestimada en el oriente de Guatemala.
- **Elevación.** Se usa la de la celda de NASA POWER, que puede diferir de la parcela.
- **Cultivos.** Maíz y frijol usan parámetros de FAO-56 e ICTA del repositorio del equipo. Los de café y tomate, y los factores Ky de FAO-33, están citados de memoria y hay que verificarlos.
- **Almacenamiento.** Se usa un almacén clave-valor con JSON. Para históricos largos convendría migrar a SQLite; `lib/datos/almacen.dart` aísla ese cambio.
- **Sincronización.** Ocurre al abrir la app y al pedirla; no hay tarea en segundo plano.
- **Sin validar en campo.** La recomendación apoya la decisión del productor; no la reemplaza.

## Créditos

- Clima: NASA POWER (MERRA-2 y CERES).
- Método: FAO-56 (Allen et al., 1998) y FAO-33 (Doorenbos y Kassam, 1979).
- Tipografía: Inter, licencia SIL OFL (`assets/fuentes/OFL.txt`).
