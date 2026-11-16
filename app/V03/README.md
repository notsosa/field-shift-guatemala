# Field Shift

**V03 · 1.4.2+8.** Esta entrega incorpora el plan diario, las sugerencias de siembra y el riego del café con redes neuronales que corren en la app. La ficha del lote ofrece «Borrar cultivo» en «Más opciones».

App Android (Flutter) para decidir riego y manejo de una parcela sin depender de la señal. Proyecto del equipo de Ciudad de Guatemala para *Field Shift: Adapting Farms with NASA Data*, NASA Space Apps Challenge 2026.

La versión base `1.3.0+5` incorporó la navegación en máximo 2 toques (`lib/ui/flujo.dart`), tipografía mínima de 18 px y soporte de escalado `2.0x`–`3.2x`, sistema de componentes emergentes propios de alto contraste y zonas táctiles >= 56 px (`lib/ui/emergentes.dart`: `elegirOpcion`, `confirmarAccion`, `mostrarAviso`, `elegirFecha`, `Interruptor`), formularios con revelación progresiva (`SeccionDesplegable`) y errores visibles sobre `PieGuardar`, recuperación ante JSON corrupto (`fincaV3.respaldoCorrupto` con degradación a `V2`/`V1`) y rezago real de 2 días en NASA POWER; además de campañas con historial, cosechas/pérdidas y bitácoras, riego con destinatario explícito, paquete JSON versionado con revisión e importación sin duplicados, disponibilidad de agua por fecha, lluvia desconocida explícita y lotes con geometría geográfica y validación espacial. Detalles de datos y migración en [etapas 1 y 2](docs/etapas-1-2.md) y [etapas 3–5](docs/etapas-3-5.md).

## Qué hace

1. El productor fija el punto de su finca (GPS, coordenadas o buscándola en un mapa que se arrastra) y dibuja sobre un mapa el contorno de la finca y el perímetro de cada plantación.
   Cada plantación guarda su cultivo, fecha, suelo, tipo y temporada de riego, plaga reciente y fertilización. Puede haber varias.
   Los pasos siguientes se numeran a partir de este.
2. Con wifi, la app descarga el clima diario de NASA POWER para ese punto y lo guarda en el teléfono.
3. Cada semana el productor registra riegos, plaga y fertilizante. En «Agua y riego por fecha» registra por separado el suministro compartido de la finca y la necesidad/aplicación del lote, con cantidades opcionales.
4. La app calcula el agua disponible en la zona de raíces (FAO-56) de cada plantación y recomienda qué hacer.

Todo funciona sin conexión salvo la descarga del clima y del mapa de fondo, que solo corren con wifi. El mapa ya visto queda guardado en el teléfono.

## Estructura

| Carpeta / Archivo | Contenido |
|---|---|
| `lib/motor/` | Cálculo en Dart puro: ET₀ Penman-Monteith (`fao56.dart`), balance diario de agua y recomendador con rezago real de 2 días de NASA POWER (`recomendador.dart`) |
| `lib/datos/` | Almacenamiento local con respaldo ante corrupción `fincaV3.respaldoCorrupto` (`almacen.dart`), descarga de NASA POWER (`clima.dart`) y mapa de fondo (`mapa.dart`) |
| `lib/ui/` | Sistema de diseño (`tema.dart`), componentes emergentes propios (`lib/ui/emergentes.dart`), flujo de máximo 2 toques (`lib/ui/flujo.dart`), agua (`agua.dart`), bitácoras (`bitacora.dart`), gráficos (`graficos.dart`), plano de la finca (`finca.dart`), mapa para ubicarla (`ubicar.dart`) y pantallas principales |
| `lib/ui/emergentes.dart` | Hojas modales, diálogos, selector de fecha con calendario/atajos e interruptor binario propios (`elegirOpcion`, `confirmarAccion`, `mostrarAviso`, `elegirFecha`, `Interruptor`) con zonas táctiles >= 56 px |
| `lib/ui/flujo.dart` | Ficha única de manejo por lote (`PantallaMiPlantacion`) y captura guiada de actividades (`PantallaActividad`) en máximo 2 toques |
| `lib/modelos.dart` | Finca, lotes estables, plantaciones, observaciones de agua, registros y catálogo |
| `lib/geometria.dart` | Coordenadas canónicas, GeoJSON, áreas y validación de polígonos simples |
| `lib/intercambio.dart` | Exportación, revisión e importación sin duplicados del paquete JSON versionado |
| `lib/textos.dart` | Textos en español e inglés |
| `test/` | **8 suites (220 pruebas)**: `agua_geometria_test.dart`, `campanias_test.dart`, `datos_1_3_test.dart`, `emergentes_test.dart`, `formularios_1_3_test.dart`, `mapa_test.dart`, `navegacion_1_3_test.dart` y `pantallas_test.dart`; referencias visuales en `test/capturas/` y `test/capturas/emergentes/` |

## Cómo correrla

Flutter 3.50 o superior.

```bash
flutter pub get
```

```bash
flutter test
```

Ejecuta las **8 suites de pruebas (220 pruebas en total)**:
- `test/agua_geometria_test.dart` (balance de agua, reparto de suministro y validación geométrica/GeoJSON)
- `test/campanias_test.dart` (ciclo de campañas, bitácoras e intercambio de paquetes)
- `test/datos_1_3_test.dart` (recuperación ante JSON corrupto en `fincaV3.respaldoCorrupto`, reintento de escritura y rezago de 2 días en NASA POWER)
- `test/emergentes_test.dart` (componentes emergentes propios: `elegirOpcion`, `confirmarAccion`, `mostrarAviso`, `elegirFecha`, `Interruptor` y capturas en `test/capturas/emergentes/`)
- `test/formularios_1_3_test.dart` (revelación progresiva, rangos de fechas por campaña, aviso de descarte en Agua y errores visibles sobre `PieGuardar`)
- `test/mapa_test.dart` (proyección Web Mercator y caché de teselas)
- `test/navegacion_1_3_test.dart` (regla de máximo 2 toques, tipografía >= 18 px y escalado de texto `2.0x`–`3.2x` en vertical y horizontal)
- `test/pantallas_test.dart` (recorridos completos y capturas de referencia en `test/capturas/`)

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

## Redes neuronales

Desde **Finca → Plan diario**, la red neuronal calcula qué hacer hoy en los lotes. Para una siembra nueva se puede usar **Nueva plantación** o **Sugerir cultivo con red neuronal**. En un cafetal, la tarjeta **Riego del café** aparece en **Hoy** y en el detalle del lote. Ambas redes ejecutan la inferencia localmente en Dart. [Datos, alcance y origen de los pesos](docs/plan-v3.md)

## Supuestos y límites

- **Unidades.** En Ajustes se elige entre manzanas (1 mz = 6 989 m², por omisión) y hectáreas con kilómetros.
- **Plano de la finca.** Permite pellizcar y arrastrar dentro del encuadre. Las coordenadas geográficas se conservan al cambiar la vista; el editor comprueba cruces, superficie, límites y solapamientos. Finca permite copiar GeoJSON. Áreas aproximadas y polígonos simples, sin huecos ni multipolígonos. Todas las plantaciones comparten el punto de consulta climática.
- **Mapa de fondo.** Teselas de OpenStreetMap (mapa) o Esri World Imagery (satélite), descargadas solo con wifi y guardadas en el almacén local (hasta 100). Hay que revisar las condiciones de uso de ambos servicios antes de publicar la app; la petición lleva un `User-Agent` con el identificador de la app, que OpenStreetMap exige.
- **Riego.** El suministro se confirma por fecha; un sistema instalado no garantiza agua. El saldo opcional en m³ se reparte entre lotes con área válida. Una lámina diaria conocida sustituye el reparto semanal. Sin cantidad conocida, las láminas por tipo (4/6/12/30 mm) siguen siendo supuestos señalados.
- **Suelo.** Agua disponible por textura de FAO-56: arenoso 100, franco 150 y arcilloso 180 mm por metro.
- **Estado inicial.** El balance arranca con la mitad del agua disponible gastada.
- **Clima.** POWER es información de celda. La lluvia faltante permanece desconocida; el balance muestra un escenario sin aporte en esos días y lo advierte. ET₀ usa el promedio reciente si falta, sin descartar una lluvia conocida. No hay pronóstico integrado ni precisión calibrada.
- **Elevación.** Se usa la de la celda de NASA POWER, que puede diferir de la parcela.
- **Cultivos.** Maíz y frijol usan parámetros de FAO-56 e ICTA del repositorio del equipo. Los de café y tomate, y los factores Ky de FAO-33, están citados de memoria y hay que verificarlos.
- **Almacenamiento.** Finca, lotes, campañas, bitácoras, clima y agua se guardan juntos en el JSON versionado `fincaV3`; las claves antiguas permanecen como respaldo de migración. No se inventan observaciones de agua para registros antiguos.
- **Sincronización.** Ocurre al abrir la app y al pedirla; no hay tarea en segundo plano.
- **Sin validar en campo.** La recomendación apoya la decisión del productor; no la reemplaza.

## Créditos

- Clima: NASA POWER (MERRA-2 y CERES).
- Mapa: © colaboradores de OpenStreetMap; imágenes de satélite de Esri, Maxar y Earthstar Geographics.
- Método: FAO-56 (Allen et al., 1998) y FAO-33 (Doorenbos y Kassam, 1979).
- Tipografía: Inter, licencia SIL OFL (`assets/fuentes/OFL.txt`).
