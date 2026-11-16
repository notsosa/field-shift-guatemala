# Handoff · App Android Field Shift (`app/V02/`)

Estado al 15 de noviembre de 2026. Documento para retomar el trabajo de la app en otra sesión, con otra persona o con otro asistente. Complementa el `README.md` de esta carpeta, que describe la app; aquí va cómo está montado el entorno, cómo se trabaja y qué falta.

Actualización actual `1.3.0+5` (sobre la base `1.2.0+4`): blindaje de almacenamiento y rezago de NASA POWER, formularios con revelación progresiva y validación explícita, arquitectura de navegación en máximo 2 toques (`lib/ui/flujo.dart`), tipografía mínima de 18 px con soporte `2.0x`–`3.2x`, y sistema de componentes emergentes propios (`lib/ui/emergentes.dart`). Etapas previas de captura e intercambio documentadas en [agua y geometrías](docs/etapas-1-2.md) y [campañas, bitácoras y paquete](docs/etapas-3-5.md). El contrato neuronal y el DEM/escorrentía siguen pendientes.

## 1. Qué hay construido

App Android en Flutter, sin conexión salvo dos descargas que solo corren con wifi: el clima de NASA POWER y las imágenes del mapa de fondo.

- **Finca:** punto fijado con GPS, con coordenadas o buscándola en un mapa que se arrastra y se acerca.
- **Plano de la finca:** sobre mapa (OpenStreetMap), satélite (Esri World Imagery) o croquis en blanco, se dibuja el contorno de la finca y el perímetro de cada plantación tocando esquinas.
- **Varias plantaciones:** cada una con cultivo, fecha, suelo, riego, caja de plaga reciente y caja de fertilizante; su propia recomendación y sus propios registros semanales.
- **Recomendación:** balance FAO-56 por plantación con suministro confirmado por fecha y reparto de saldo compartido si se conoce. La lluvia faltante permanece nula y se explica el escenario numérico; el factor FAO-33 se oculta si falta lluvia en el balance.
- **Visibilidad del riego:** los accesos de captura se muestran solo si la plantación seleccionada tiene riego configurado. El historial anterior se conserva en consulta al cambiar a «Sin riego».
- **Agua por fecha:** registra necesidad y aplicación del lote separadas del suministro compartido de la finca. Cantidades opcionales en mm y m³; el dato no se hereda al día siguiente.
- **GeoJSON:** lotes con identidad estable, geometría geográfica y comprobación de cruces, límites y solapamientos; exportación al portapapeles desde Finca.
- **Unidades:** manzanas (por omisión) o hectáreas y kilómetros.
- **Idiomas:** español e inglés. Modo claro y oscuro.

Verificado en `1.3.0+5`: `flutter analyze` sin problemas y **220 pruebas** en verde en 8 archivos de test (`agua_geometria_test.dart`, `campanias_test.dart`, `datos_1_3_test.dart`, `emergentes_test.dart`, `formularios_1_3_test.dart`, `mapa_test.dart`, `navegacion_1_3_test.dart`, `pantallas_test.dart`). Probado a mano en un emulador de Android 16 y arrancado en un Samsung Galaxy A14 con Android 14.

## Lo que se hizo en la version 1.3.0+5 (etapas 1 a 5 de UX, datos y componentes emergentes)

- **Etapas 1 y 2 (`test/datos_1_3_test.dart`)**:
  - Blindaje de `Almacen` ante JSON truncado, estructura rota o versión desconocida en `fincaV3`: respaldo automático de la cadena dañada en `fincaV3.respaldoCorrupto` y degradación elegante a `fincaV2` / `V1` sin perder datos previos.
  - Reintento automático en `Almacen` si `setString` falla en el primer intento de persistencia.
  - Ajuste del rezago real de 2 días de NASA POWER en `lib/datos/clima.dart` y `lib/motor/recomendador.dart`, evitando tratar los últimos dos días en tránsito satelital como sequía confirmada o como desactualización falsa.
- **Etapas 3 y 4 (`test/formularios_1_3_test.dart`)**:
  - Formularios con revelación progresiva mediante `SeccionDesplegable` para separar campos esenciales de opciones avanzadas.
  - Validación estricta de rangos de fechas por campaña (siembra, cierre y eventos dentro de la ventana válida).
  - Confirmación antes de descartar cambios sin guardar en la pantalla de Agua (`PantallaAgua`).
  - Errores visibles en rojo directamente sobre `PieGuardar` y motivo explícito visible cuando el botón `Guardar` está desactivado.
- **Etapa 5 (`test/navegacion_1_3_test.dart` y `lib/ui/flujo.dart`)**:
  - Arquitectura de navegación con máximo 2 toques hacia cualquier acción principal desde `Hoy`, `Registros` o `Finca`.
  - Ficha única de manejo por lote (`PantallaMiPlantacion`) y flujo de captura guiada (`PantallaActividad`).
  - Cuerpo tipográfico mínimo de 18 px (`Texto.cuerpo` y `Texto.fuerte` >= 18 px) y soporte verificado sin desbordamientos con escalado de texto `2.0x` y `3.2x` tanto en orientación vertical como horizontal.
- **Sistema de componentes emergentes propios (`lib/ui/emergentes.dart` y `test/emergentes_test.dart`)**:
  - Sustitución de modales, alertas, ruletas de fecha e interruptores nativos de iOS (`showCupertinoModalPopup`, `showCupertinoDialog`, `CupertinoDatePicker`, `CupertinoSwitch`) por componentes propios planos, de alto contraste y con zonas táctiles >= 56 px:
    - `elegirOpcion` (`OpcionHoja`): hoja modal inferior con título, subtítulo opcional, marca visual en la opción activa y botón explícito de cancelar.
    - `confirmarAccion`: diálogo centrado con jerarquía clara entre la acción principal (destructiva o de confirmación) y la secundaria.
    - `mostrarAviso`: diálogo informativo con un único botón de cierre de ancho completo (`Entendido` / `Aceptar`).
    - `elegirFecha`: hoja modal con calendario mensual en cuadrícula (`Lun`–`Dom`), atajos rápidos (`Hoy`, `Ayer`, `Hace una semana`), navegación por mes/año y aviso explícito cuando una fecha está fuera del rango permitido (`minima` / `maxima`).
    - `Interruptor`: control binario propio de 56 px de alto mínimo con estado visible (`Sí` / `No`), borde contrastado y semántica accesible de dos estados.

Verificación de la actualización 1.1 en el Galaxy A14: arranque, migración, conservación de tres plantaciones/punto, cancelación de agua sin guardado y reapertura en frío. La validación identificó el contorno existente de Frijol fuera de la finca; se conservó para revisión. Evidencia local en `tmp/etapas-1-2-telefono/resultado-final.json`, desde la raíz del repositorio.

No verificado: el recorrido completo a mano en el teléfono (GPS, pellizco con dos dedos en el mapa, uso sin wifi). No hay validación en campo.

## 2. Entorno local (Windows 11, sin Android Studio)

Todo vive bajo `%USERPROFILE%\dev`. El `PATH` del sistema no se modificó.

| Pieza | Ubicación | Versión |
|---|---|---|
| Flutter | `%USERPROFILE%\dev\flutter` | 3.50.0 estable (Dart 3.14) |
| JDK | `%USERPROFILE%\dev\jdk-21` | Temurin 21.0.13 |
| SDK de Android | `%USERPROFILE%\dev\android-sdk` | plataforma 36, build-tools 36, NDK 28.2, emulador 37 |
| Emulador | AVD `field_shift` | Pixel 7, Android 16, x86_64 |
| Copia de trabajo de la app | `%USERPROFILE%\dev\proyectos\field_shift` | carpeta suelta, **no es un repositorio git** |
| Clon del repositorio del equipo | `%USERPROFILE%\dev\proyectos\fsg_repo` | rama `main` |

Flutter está configurado con `flutter config --android-sdk ... --jdk-dir ...`. El emulador necesita la característica de Windows «Windows Hypervisor Platform», que ya está activada.

### Comandos habituales

Desde Git Bash, dentro de la copia de trabajo:

```bash
export PATH="$USERPROFILE/dev/flutter/bin:$PATH"
```

```bash
flutter analyze
```

```bash
flutter test
```

```bash
flutter build apk --release
```

Instalar el APK en el dispositivo conectado (emulador o teléfono con depuración por USB):

```bash
"$USERPROFILE/dev/android-sdk/platform-tools/adb.exe" install -r build/app/outputs/flutter-apk/app-release.apk
```

Arrancar el emulador:

```bash
"$USERPROFILE/dev/android-sdk/emulator/emulator.exe" -avd field_shift
```

Regenerar las capturas de las pantallas tras un cambio de diseño:

```bash
flutter test test/pantallas_test.dart --update-goldens
```

### Tropiezos conocidos del entorno

- **En PowerShell hay que llamar a `flutter.bat`**, no a `flutter`: sin la extensión se abre una ventana aparte.
- **En una terminal de PowerShell normal, Flutter no encuentra el SDK de Android** («Unable to locate an Android SDK») aunque `flutter config` esté hecho. Se arregla por sesión con `$env:ANDROID_HOME` y `$env:JAVA_HOME` apuntando a las carpetas de la tabla.
- **`flutter run` en modo depuración generó un APK sin `libdartjni.so`** y la app se quedaba en la pantalla del logo. El ciclo que funciona es: compilar en `--release` e instalar con `adb install -r`. Tarda unos dos minutos por tanda.
- **El APK de `--release` está firmado con las llaves de depuración.** Sirve para probar e instalar a mano; para publicar hace falta una llave propia.

## 3. Cómo se trabaja y cómo se sube

1. Para esta entrega se edita directamente `Space_apps/app/V02/`. Las otras copias son antecedentes y deben compararse antes de reutilizarlas.
2. Ejecutar `flutter.bat analyze` y `flutter.bat test`; las pruebas de pantallas guardan sus referencias en `test/capturas/`. En PowerShell puede hacer falta definir `PUB_CACHE` como `%LOCALAPPDATA%/Pub/Cache`.
3. Antes de subir, revisar el diff de `app/V02/` y sincronizar el repositorio conservando cambios ajenos. Los documentos raíz ya tenían cambios locales antes de esta entrega.
4. La publicación requiere la instrucción del usuario para esa subida; este trabajo aún no se ha publicado.

Acuerdos con el dueño del repositorio:

- La app va en `main`, dentro de `app/V02/`. La carpeta `app/` es una carpeta por versión.
- **Cada subida se le pregunta antes.** Una aprobación no vale para la siguiente.
- No se suben el APK, las carpetas de compilación ni el material de investigación en Python.
- No se tocan las carpetas de los demás miembros del equipo.

## 4. Arquitectura

| Archivo | Qué hace |
|---|---|
| `lib/main.dart` | Punto de entrada y montaje de la aplicación |
| `lib/motor/fao56.dart` | Dart puro: ET₀ Penman-Monteith, balance diario de agua, factor de rendimiento |
| `lib/motor/recomendador.dart` | `recomendar(...)`: de parcela, plantación, clima y registros a un objeto `Recomendacion` (considera rezago real de 2 días de NASA POWER). **Punto de conexión para la red neuronal del equipo** |
| `lib/geometria.dart` | Coordenadas geográficas, conversión GeoJSON, áreas y validación de polígonos cóncavos |
| `lib/intercambio.dart` | Paquete JSON versionado (`field-shift-finca`), revisión e importación sin duplicados |
| `lib/modelos.dart` | `Parcela`, `Plantacion`, `RegistroSemanal`, `DiaClima`, catálogo de cultivos, `Punto` y geometría del plano, `Unidad` |
| `lib/datos/almacen.dart` | Almacén clave-valor (`shared_preferences`) con JSON (`fincaV3`), respaldo ante corrupción (`fincaV3.respaldoCorrupto`), degradación a `V2`/`V1`, reintento en `setString` y caché de teselas |
| `lib/datos/clima.dart` | Descarga de NASA POWER (con ventana ajustada al rezago satelital de 2 días) y comprobación de wifi |
| `lib/datos/mapa.dart` | Proyección Web Mercator, ventana del plano y `ServicioMapa` (teselas con caché) |
| `lib/estado.dart` | `AppEstado` (`ChangeNotifier`) con todas las acciones; `Alcance` lo expone a las pantallas |
| `lib/textos.dart` | Todos los textos en español e inglés, y el formato de áreas y escalas |
| `lib/ui/tema.dart` | Sistema de diseño: colores, tipografía (`Texto.cuerpo` y `Texto.fuerte` >= 18 px) y piezas (`Tarjeta`, `Grupo`, `Fila`, `Selector`, `Campo`, `SeccionDesplegable`, `PieGuardar`…) |
| `lib/ui/emergentes.dart` | Sistema de componentes emergentes propios de alto contraste y >= 56 px: `elegirOpcion` (`OpcionHoja`), `confirmarAccion`, `mostrarAviso`, `elegirFecha` e `Interruptor` |
| `lib/ui/flujo.dart` | Navegación de máximo 2 toques, ficha única de manejo por lote (`PantallaMiPlantacion`) y captura guiada (`PantallaActividad`) |
| `lib/ui/agua.dart` | Suministro de la finca y observaciones de necesidad y aplicación por lote/fecha con aviso de cambios sin guardar |
| `lib/ui/bitacora.dart` | Bitácora de campaña (`PantallaBitacora`), historial de campañas (`PantallaCampanias`) y paquete de intercambio (`PantallaIntercambio`) |
| `lib/ui/finca.dart` | Plano de la finca, pantalla de trazo, flujo de alta de plantación y pestaña Finca |
| `lib/ui/ubicar.dart` | Mapa que se arrastra para elegir el punto de la finca |
| `lib/ui/graficos.dart` | Gráficos de humedad del suelo, lluvia y balance hídrico |
| `lib/ui/hoy.dart`, `registro.dart`, `plantacion.dart`, `parcela.dart`, `ajustes.dart`, `bienvenida.dart` | Pantallas principales de recomendación diaria, registros semanales, edición de plantación/parcela, ajustes y bienvenida |

### Árbol de archivos (`lib/`, `test/`, `docs/`)

```text
lib/
├── main.dart
├── estado.dart
├── geometria.dart
├── intercambio.dart
├── modelos.dart
├── textos.dart
├── datos/
│   ├── almacen.dart
│   ├── clima.dart
│   └── mapa.dart
├── motor/
│   ├── fao56.dart
│   └── recomendador.dart
└── ui/
    ├── ajustes.dart
    ├── agua.dart
    ├── bienvenida.dart
    ├── bitacora.dart
    ├── emergentes.dart
    ├── finca.dart
    ├── flujo.dart
    ├── graficos.dart
    ├── hoy.dart
    ├── parcela.dart
    ├── plantacion.dart
    ├── registro.dart
    ├── tema.dart
    └── ubicar.dart

test/
├── agua_geometria_test.dart
├── campanias_test.dart
├── datos_1_3_test.dart
├── emergentes_test.dart
├── formularios_1_3_test.dart
├── mapa_test.dart
├── navegacion_1_3_test.dart
├── pantallas_test.dart
└── capturas/
    └── emergentes/

docs/
├── etapas-1-2.md
└── etapas-3-5.md
```

### Decisiones que conviene conocer antes de tocar el código

- **Solo widgets Cupertino.** En Flutter 3.50, Material y Cupertino son paquetes aparte; aquí se usa `cupertino_ui` y no `material_ui`. `package:flutter/cupertino.dart` está obsoleto.
- **Coordenadas canónicas.** `Lote.geometria` y `Parcela.geometria` conservan coordenadas geográficas; los puntos fraccionales de las pantallas se derivan con `MarcoPlano`. Cambiar ancho o centro de vista no mueve el terreno. Las geometrías antiguas se migran usando su encuadre original.
- **Guardado del flujo.** `PantallaTrazo` entrega un borrador. `guardarPlantacion` valida lote y finca pendientes antes de modificarlos y los persiste juntos en `fincaV3`. La ubicación de la finca se guarda en un paso anterior. Se conservan pruebas de cancelación.
- **El mapa solo se descarga con wifi.** Las teselas del plano de la finca se guardan en el teléfono (hasta 100); las que se ven al buscar la finca en el mapa arrastrable solo quedan en memoria.
- **Identidades y migración.** Finca y lote tienen identificadores estables; `Plantacion.loteId` referencia el terreno. `AppEstado.preparada` completa la migración antes de arrancar. Las escrituras de `fincaV3` se ordenan y las claves antiguas permanecen como respaldo. Cada Plantacion representa ahora una campaña; el historial completo se mantiene en AppEstado.campanias y la lista activa en plantaciones. Se conserva fincaV2 como respaldo.

### Tropiezos conocidos del código y de las pruebas

- `Future.whenComplete` espera el valor que devuelve su cierre. Un cierre que devolvía el propio futuro dejó la descarga del mapa colgada para siempre; por eso el de `ServicioMapa.tesela` lleva llaves y no devuelve nada.
- `Rotulo` pone el texto en mayúsculas: en las pruebas hay que buscarlo así.
- `tester.pageBack()` no encuentra el botón de volver de `cupertino_ui`; en las pruebas se pulsa el texto «Atrás».
- Las listas largas construyen sus filas según se desplazan: en las pruebas hace falta `scrollUntilVisible` o `ensureVisible` antes de pulsar algo que queda abajo.
- Las pruebas de pantallas usan un clima y un mapa de mentira (`ClimaFalso`, `MapaFalso`) y un reloj fijo en el 14 de noviembre de 2026. No usan internet.

## 5. Límites y cosas por verificar

- **Sin validar en campo.** La recomendación apoya la decisión del productor; no la reemplaza.
- **Parámetros citados de memoria.** Los de café y tomate, y los factores Ky de FAO-33, hay que contrastarlos con la fuente. Maíz y frijol salen de `datos/cultivos/` de este repositorio.
- **Supuestos del balance.** Estado inicial medio lleno, lámina por tipo si no se conoce la aplicación y clima de celda. La lluvia faltante es nula; el cálculo usa un escenario sin aporte y lo señala. La calidad de datos no es una precisión medida.
- **Condiciones de uso de los mapas.** OpenStreetMap y Esri permiten un uso ligero con atribución (ya se muestra), pero hay que revisar sus términos antes de publicar la app. La petición lleva un `User-Agent` con el identificador de la app, que OpenStreetMap exige.
- **Alcance cartográfico.** Se puede pellizcar y arrastrar dentro del encuadre. Las áreas son aproximadas; el editor produce polígonos simples. No hay levantamiento catastral ni importación de huecos/multipolígonos.
- **Los datos de plaga y fertilizante casi no cambian la recomendación.** Se guardan con detalle (tipo, fechas, daño, producto), pero el motor solo los usa para los avisos.
- **La compilación web está sin revisar** desde que se añadieron el mapa y las plantaciones múltiples.

## 6. Próximos pasos sugeridos

1. Completar pruebas de campo y recorridos de GPS y uso prolongado sin conexión; conservar la verificación por entrega en el teléfono.
2. Revisar con productores las capturas de campañas, cosechas, pérdidas y bitácoras implementadas en 1.2.0.
3. Acordar el contrato de datos con el compañero que desarrolla el modelo neuronal cuando publique su implementación.
4. Verificar los parámetros agronómicos pendientes y ampliar perfiles compatibles.
5. Preparar una firma propia antes de distribuir públicamente.

Prueba de la corrección 1.1.1 en el Galaxy A14: Maíz y Frijol ya figuraban «Sin riego»; Tomate se cambió de «Manual» a «Sin riego» por indicación del usuario. Se comprobó en los tres cultivos que Hoy y Registros ocultan los accesos de captura de riego. Evidencia local: `tmp/correccion-riego-secano/resultado.json`.

Verificación 1.2.0+4: `flutter analyze` limpio y 79 pruebas aprobadas, incluida comparación normal de capturas. APK instalado con `adb install -r` en Galaxy A14; Android confirma versión 1.2.0, código 4. Se conservó el almacenamiento y se respaldó el APK 1.1.1 en `tmp/etapas-3-5-telefono`. Revisión visual completada tras desbloquear: las tres plantaciones originales siguen sin riego; también se conservaron Maíz con goteo y Café manual, añadidos antes de esta revisión. El selector exige destinatario, muestra solo esos dos lotes y descarta el borrador al cambiar. Se revisaron bitácora e historial, se copió el paquete y se reabrió en frío conservando los datos. No se cerraron campañas ni se guardaron registros de prueba. Evidencia local: `tmp/etapas-3-5-telefono/resultado.json`. No se insertaron eventos ficticios en el teléfono.

Verificación 1.3.0+5: `flutter analyze` limpio y **220 pruebas aprobadas** en las 8 suites (`agua_geometria_test.dart`, `campanias_test.dart`, `datos_1_3_test.dart`, `emergentes_test.dart`, `formularios_1_3_test.dart`, `mapa_test.dart`, `navegacion_1_3_test.dart`, `pantallas_test.dart`), incluyendo referencias visuales en `test/capturas/` y `test/capturas/emergentes/`.
