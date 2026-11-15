# Handoff · App Android Field Shift (`app/V01/`)

Estado al 15 de noviembre de 2026. Documento para retomar el trabajo de la app en otra sesión, con otra persona o con otro asistente. Complementa el `README.md` de esta carpeta, que describe la app; aquí va cómo está montado el entorno, cómo se trabaja y qué falta.

## 1. Qué hay construido

App Android en Flutter, sin conexión salvo dos descargas que solo corren con wifi: el clima de NASA POWER y las imágenes del mapa de fondo.

- **Finca:** punto fijado con GPS, con coordenadas o buscándola en un mapa que se arrastra y se acerca.
- **Plano de la finca:** sobre mapa (OpenStreetMap), satélite (Esri World Imagery) o croquis en blanco, se dibuja el contorno de la finca y el perímetro de cada plantación tocando esquinas.
- **Varias plantaciones:** cada una con cultivo, fecha, suelo, riego, caja de plaga reciente y caja de fertilizante; su propia recomendación y sus propios registros semanales.
- **Recomendación:** balance diario de agua en la zona de raíces (FAO-56) y factor de rendimiento (FAO-33), por plantación.
- **Unidades:** manzanas (por omisión) o hectáreas y kilómetros.
- **Idiomas:** español e inglés. Modo claro y oscuro.

Verificado: `flutter analyze` sin problemas y 35 pruebas en verde (motor, mapa y pantallas). Probado a mano en un emulador de Android 16 y arrancado en un Samsung Galaxy A14 con Android 14.

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

1. Los cambios se hacen en la copia de trabajo (`field_shift`), se pasan `flutter analyze` y `flutter test`, y se prueban en el emulador o en el teléfono.
2. Para subir, se copian a `fsg_repo/app/V01/` las carpetas `lib/` y `test/` completas (borrando antes las del clon, para que también se vayan los archivos eliminados) y los archivos `README.md`, `HANDOFF.md`, `pubspec.yaml`, `pubspec.lock` y `analysis_options.yaml`.
3. Antes del commit: `git pull --ff-only origin main` en el clon (el equipo sube a menudo), y `flutter analyze` y `flutter test` dentro de `app/V01`.
4. Commit en español, con prefijo tipo `feat(app):`, y `git push origin main`.

Acuerdos con el dueño del repositorio:

- La app va en `main`, dentro de `app/V01/`. La carpeta `app/` es una carpeta por versión.
- **Cada subida se le pregunta antes.** Una aprobación no vale para la siguiente.
- No se suben el APK, las carpetas de compilación ni el material de investigación en Python.
- No se tocan las carpetas de los demás miembros del equipo.

## 4. Arquitectura

| Archivo | Qué hace |
|---|---|
| `lib/motor/fao56.dart` | Dart puro: ET₀ Penman-Monteith, balance diario de agua, factor de rendimiento |
| `lib/motor/recomendador.dart` | `recomendar(...)`: de parcela, plantación, clima y registros a un objeto `Recomendacion`. **Punto de conexión para la red neuronal del equipo** |
| `lib/modelos.dart` | `Parcela`, `Plantacion`, `RegistroSemanal`, `DiaClima`, catálogo de cultivos, `Punto` y geometría del plano, `Unidad` |
| `lib/datos/almacen.dart` | Almacén clave-valor (`shared_preferences`) con JSON; también guarda las teselas del mapa |
| `lib/datos/clima.dart` | Descarga de NASA POWER y comprobación de wifi |
| `lib/datos/mapa.dart` | Proyección Web Mercator, ventana del plano y `ServicioMapa` (teselas con caché) |
| `lib/estado.dart` | `AppEstado` (`ChangeNotifier`) con todas las acciones; `Alcance` lo expone a las pantallas |
| `lib/textos.dart` | Todos los textos en español e inglés, y el formato de áreas y escalas |
| `lib/ui/tema.dart` | Sistema de diseño: colores, tipografía y piezas (`Tarjeta`, `Grupo`, `Fila`, `Selector`, `Campo`…) |
| `lib/ui/finca.dart` | Plano de la finca, pantalla de trazo, flujo de alta de plantación y pestaña Finca |
| `lib/ui/ubicar.dart` | Mapa que se arrastra para elegir el punto de la finca |
| `lib/ui/hoy.dart`, `registro.dart`, `plantacion.dart`, `parcela.dart`, `ajustes.dart`, `bienvenida.dart` | El resto de pantallas |

### Decisiones que conviene conocer antes de tocar el código

- **Solo widgets Cupertino.** En Flutter 3.50, Material y Cupertino son paquetes aparte; aquí se usa `cupertino_ui` y no `material_ui`. `package:flutter/cupertino.dart` está obsoleto.
- **El plano de la finca no está en latitud y longitud.** Es un cuadrado de `Parcela.lado` metros centrado en el punto de la finca, con el norte arriba. Los contornos se guardan como fracciones de 0 a 1 de ese cuadrado. Si cambia el ancho, `reescalar` los ajusta para que queden en el mismo lugar del terreno; si se mueve el punto de la finca, los contornos se mueven con él.
- **Nada se guarda a mitad de un flujo.** El alta de plantación tiene tres pasos (contorno, perímetro, formulario) apilados uno sobre otro; el contorno, el ancho del plano y la plantación se guardan juntos en `PantallaPlantacion._guardar`. `PantallaTrazo` nunca escribe en el estado: entrega un `Trazo`. Hay pruebas que abandonan el flujo en cada paso; conviene mantenerlas en verde.
- **El mapa solo se descarga con wifi.** Las teselas del plano de la finca se guardan en el teléfono (hasta 100); las que se ven al buscar la finca en el mapa arrastrable solo quedan en memoria.
- **Una plantación sin identificador es nueva.** `guardarPlantacion` le asigna uno (`p1`, `p2`…). Los datos de la versión con una sola plantación se migran al abrir.

### Tropiezos conocidos del código y de las pruebas

- `Future.whenComplete` espera el valor que devuelve su cierre. Un cierre que devolvía el propio futuro dejó la descarga del mapa colgada para siempre; por eso el de `ServicioMapa.tesela` lleva llaves y no devuelve nada.
- `Rotulo` pone el texto en mayúsculas: en las pruebas hay que buscarlo así.
- `tester.pageBack()` no encuentra el botón de volver de `cupertino_ui`; en las pruebas se pulsa el texto «Atrás».
- Las listas largas construyen sus filas según se desplazan: en las pruebas hace falta `scrollUntilVisible` o `ensureVisible` antes de pulsar algo que queda abajo.
- Las pruebas de pantallas usan un clima y un mapa de mentira (`ClimaFalso`, `MapaFalso`) y un reloj fijo en el 14 de noviembre de 2026. No usan internet.

## 5. Límites y cosas por verificar

- **Sin validar en campo.** La recomendación apoya la decisión del productor; no la reemplaza.
- **Parámetros citados de memoria.** Los de café y tomate, y los factores Ky de FAO-33, hay que contrastarlos con la fuente. Maíz y frijol salen de `datos/cultivos/` de este repositorio.
- **Supuestos del balance de agua.** El suelo arranca medio lleno, cada riego vale una lámina fija según el tipo y el clima es de una celda de unos 50 km.
- **Condiciones de uso de los mapas.** OpenStreetMap y Esri permiten un uso ligero con atribución (ya se muestra), pero hay que revisar sus términos antes de publicar la app. La petición lleva un `User-Agent` con el identificador de la app, que OpenStreetMap exige.
- **El plano de la finca no se desplaza ni se acerca.** En planos grandes, los lotes pequeños se dibujan con poca precisión.
- **Los datos de plaga y fertilizante casi no cambian la recomendación.** Se guardan con detalle (tipo, fechas, daño, producto), pero el motor solo los usa para los avisos.
- **La compilación web está sin revisar** desde que se añadieron el mapa y las plantaciones múltiples.

## 6. Próximos pasos sugeridos

1. Recorrer la app completa a mano en el teléfono y corregir lo que aparezca.
2. Hacer que el plano de la finca se pueda arrastrar y acercar, reutilizando `MapaExplorable` de `lib/ui/ubicar.dart`. Implica guardar los contornos en latitud y longitud, con migración de los actuales.
3. Conectar el modelo del equipo en `recomendar(...)`, manteniendo el tipo `Recomendacion` para no tocar las pantallas.
4. Usar en la recomendación los datos de plaga y fertilizante que ya se registran.
5. Verificar los parámetros de cultivo pendientes y ampliar el catálogo.
6. Firmar el APK con una llave propia si se va a distribuir.
