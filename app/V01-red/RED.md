# La red del equipo dentro de la app (V01-red)

Esta carpeta es una copia de `app/V01` tal como está en `origin/main` (commit `8302281`), con la red neuronal del equipo conectada en `recomendar(...)`. `app/V01` no se tocó. La copia compila sola: `flutter pub get`, `flutter analyze`, `flutter test` y `flutter build web --release`.

## Qué hace

En la pestaña Hoy aparece una tarjeta **Próximos 7 días** con lo que la red espera de estrés por falta de agua: una frase clara («Se espera estrés…» o «No se espera estrés…»), el valor de 14 días como texto secundario y una nota honesta (estimado por la red del equipo con el clima de las últimas semanas; no es un pronóstico del tiempo; se midió contra el balance de agua de la propia app). En tomate se muestra además el rendimiento esperado al final del ciclo. En maíz y frijol **no** se muestra, porque la red lo midió peor que el número que la app ya da.

Donde la red no se midió, los campos nuevos quedan en nulo y la pantalla es la de siempre (la regla del recomendador de la app, como pide la nota de integración del compañero).

## Archivos

| Archivo | Qué es |
|---|---|
| `lib/motor/red.dart` | Paso hacia adelante en Dart puro (solo `dart:math`). Copia sin cambios de `scripts/app/dart/red.dart`. |
| `lib/motor/pesos_app.dart` | Pesos de la red (5 283 parámetros), nombres de las 40 entradas, commit y SHA-256 de la fuente. **Generado, no se edita a mano.** |
| `lib/motor/entradas_red.dart` | Arma las 40 entradas con lo que `recomendar` ya tiene, `comprobarEntradasDeLaApp` (se llama antes de la primera predicción), `predecirRed` (recorta salidas a 0–1, 0–7 y 0–14 días) y `redAplica` (las condiciones de uso). |
| `lib/motor/recomendador.dart` | `Recomendacion` gana `factorFinalRed`, `estresProx7`, `estresProx14` y `desdeRed`; `recomendar` llama a la red después de `simularBalance` solo si `redAplica`. Lo demás no cambia. |
| `lib/textos.dart` | Textos nuevos en español e inglés. |
| `lib/ui/hoy.dart` | La tarjeta `_TarjetaProximosDias`, con `Tarjeta` y los estilos de la app, solo Cupertino; claro y oscuro. |
| `tool/generar_pesos.mjs` | Genera `pesos_app.dart` desde `web/data/app_mlp.json`. |
| `tool/generar_casos.mjs` | Genera `test/casos_red.json` con la referencia en JavaScript. |
| `test/casos_red.json` | 8 casos de referencia: clima, plantación, 40 entradas esperadas y 3 salidas esperadas. |
| `test/red_test.dart` | 23 pruebas: paridad, nulos y condiciones. |
| `test/pantallas_test.dart` | 5 pruebas de pantalla nuevas y 2 capturas nuevas (`16_proximos_7_dias.png`, `17_proximos_7_dias_oscuro.png`). Las capturas anteriores no cambiaron. |

`pubspec.yaml` no cambió: no hay dependencias nuevas.

## Cuándo se usa la red

Solo si se cumplen todas: cultivo maíz, frijol o tomate; tipo de riego «ninguno» y ningún riego anotado en los registros semanales (secano); entre el 20 % y el 80 % del ciclo (ambos extremos incluidos); y clima reciente (el último dato observado tiene como mucho 10 días). Si no, `desdeRed` es falso y los tres valores son nulos.

El umbral de la frase es el que se midió: la clase «hay estrés» es una predicción de 0,5 días o más.

## Cómo sigue la nota de integración del compañero (`Integración RN apps.md`)

Su nota propone ExecuTorch en la CPU del teléfono, con un módulo Kotlin y un canal de plataforma, para su política (ventana de 28 días, hasta 32 eventos, caja, precios, acciones candidatas y máscaras), y ONNX Runtime como alternativa. Sigue su método:

1. **Fijar la referencia primero.** Su paso 1 es una referencia en Python con casos de decisión completos. Aquí la referencia es el código JavaScript del repositorio (`web/js/model/appInputs.js` y `emulator.js`), ya comprobado contra PyTorch a 1e-5, y los casos guardados en `test/casos_red.json`.
2. **Una sola red primero.** Se conectó una (semilla 17, la de menor pérdida de validación).
3. **Entradas reales y modo avión.** Las 40 entradas salen de lo que la app ya calcula y guarda; la red no necesita conexión. Si faltan entradas o la red no aplica, se usa el recomendador de la app.

Dónde se diferencia, y por qué: nuestra red tiene 5 283 parámetros y sus 40 entradas ya las calcula la app, así que corre en **Dart puro, sin módulo nativo, sin canal de plataforma y sin librería nueva**. Son unas 5 000 multiplicaciones por llamada, y se prueba con `flutter test` sin dispositivo. También funciona en la versión web. ExecuTorch sigue siendo la ruta documentada para su política grande, que sí necesita tensores de ventanas, máscaras y un motor de inferencia.

## Sin conexión: cómo se comprobó

- Ninguna dependencia nueva en `pubspec.yaml`.
- Los archivos nuevos (`red.dart`, `entradas_red.dart`, `pesos_app.dart`) solo importan `dart:math` y archivos de la propia app; no hay `http`, `dart:io` ni acceso a disco (se buscó con `grep`).
- Las pruebas de paridad corren sin red ni dispositivo.
- No se probó en un teléfono en modo avión.

## Paridad con la referencia

Con los 8 casos de `test/casos_red.json` (maíz, frijol y tomate; del 20 % al 78 % del ciclo; secos y húmedos; uno con días sin dato y retraso de POWER; uno con clima posterior a hoy que debe ignorarse):

- Diferencia máxima de las 40 entradas: 5.6e-17 (se exige 1e-9).
- Diferencia máxima de las salidas: 0.0 (se exige 1e-5).

El clima de los casos es sintético con semilla fija, no datos reales.

## Qué midió el equipo (`web/data/app_eval.json`, tarea 34)

El juez es el motor de la app con el clima real de POWER de todo el ciclo. Comparación con «lo que la app muestra hoy» (estrés de los últimos 7 días como predicción del de los próximos 7), prueba 2019–2024, 201 600 filas, semilla exportada 17:

| Estrés en los próximos 7 días | F1 (hay estrés, ≥ 0,5 d) | Error absoluto medio (días) |
|---|---|---|
| Red | 0.857 | 0.198 |
| Lo que la app muestra hoy | 0.693 | 0.268 |

Años reservados 2022–2024: F1 0.870 contra 0.694; error 0.250 contra 0.381. Promedio de las tres semillas en la prueba: F1 0.860. A 14 días: F1 0.726 contra 0.622, error 0.539 contra 0.679.

Rendimiento final (error absoluto medio): maíz 0.0187 contra 0.0149 de la app, frijol 0.0208 contra 0.0184 (la red es peor, por eso no se muestra); tomate 0.0293 contra 0.0464 (la red es mejor, por eso se muestra solo ahí).

Por parte del ciclo, la ventaja en F1 es menor al 20 % del ciclo (0.813 contra 0.613) y mayor al 80 % (0.911 contra 0.786); el error de 7 días al 20 % es casi igual (0.155 contra 0.167).

## Límites

- Solo secano (sin riego declarado ni anotado) y solo maíz, frijol y tomate.
- Solo entre el 20 % y el 80 % del ciclo.
- El «juez» es el motor FAO-56 de la propia app, no mediciones de campo. La red aprende a anticipar lo que ese motor diría; si el motor se equivoca, la red también.
- Lluvia de NASA POWER (celda de unos 50 km), no pluviómetro.
- No está validada en campo ni probada en un teléfono.
- Se entrenó con clima completo hasta hoy. En la app el último dato de POWER llega con unos días de retraso y la app completa esos días con el promedio de ET₀ y lluvia 0; ese caso no está medido (los 8 casos de paridad incluyen uno, pero la paridad solo prueba que Dart calcula lo mismo, no que la red acierte ahí). La tarjeta se muestra mientras el último dato tenga como mucho 10 días.
- Si la elevación de la finca aún no llegó con la primera sincronización, se usa 500 m, como ya hace la app para la ET₀.
- Los datos de plaga y fertilizante no entran en la red.

## Cómo regenerar

Desde `app/V01-red/`, con Node:

```bash
node tool/generar_pesos.mjs        # lib/motor/pesos_app.dart desde ../../web/data/app_mlp.json
node tool/generar_casos.mjs        # test/casos_red.json desde ../../web/js/model/
flutter test
```

Los dos scripts leen archivos del repositorio del equipo (`web/`), así que se corren dentro del repositorio. `generar_pesos.mjs` acepta otra ruta de `app_mlp.json` como argumento y anota en el encabezado el commit y el SHA-256 de la fuente. Si cambian los pesos o el orden de las entradas, hay que regenerar los dos y volver a correr las pruebas; `comprobarEntradas` falla con un mensaje claro si el orden no coincide.

## Cómo llevar el mismo cambio a `app/V01`

1. Copiar a `app/V01/lib/motor/`: `red.dart`, `pesos_app.dart` y `entradas_red.dart`.
2. Copiar a `app/V01/tool/`: `generar_pesos.mjs` y `generar_casos.mjs` (ajustar las rutas relativas `../../..` si la carpeta cambia).
3. Copiar a `app/V01/test/`: `casos_red.json` y `red_test.dart`.
4. En `lib/motor/recomendador.dart`: agregar `import 'entradas_red.dart';`, los cuatro campos opcionales de `Recomendacion` (`factorFinalRed`, `estresProx7`, `estresProx14`, `desdeRed`, con valor por omisión nulo y falso), el bloque que llama a `redAplica`, `entradasRed` y `predecirRed` justo antes de `return Recomendacion(` y los cuatro argumentos al final del constructor.
5. En `lib/textos.dart`: copiar los textos de «Próximos días» (`proximos7`, `estresEsperado`, `sinEstresEsperado`, `estresEn14`, `rendimientoFinal`, `leyendaRed`).
6. En `lib/ui/hoy.dart`: importar `entradas_red.dart` (`show umbralEstresRed`), agregar el bloque `if (r.desdeRed ...)` después de la tarjeta «Últimos 14 días» y la clase `_TarjetaProximosDias`.
7. En `test/pantallas_test.dart`: agregar `import 'package:field_shift/ui/hoy.dart';` y las pruebas «Próximos 7 días»; generar solo las dos capturas nuevas con `flutter test test/pantallas_test.dart --plain-name "en claro y en oscuro" --update-goldens`.
8. `flutter analyze` y `flutter test` en `app/V01`; no hace falta tocar `pubspec.yaml`. Antes de subir, como dice `HANDOFF.md`, preguntar al dueño del repositorio.

Los puntos 1 a 3 son copias de archivos; los 4 a 7 son adiciones sin borrar nada del código existente.

## Café: la red de riego v3 y los avisos

Para plantaciones de café, la tarjeta **Café** de la pestaña Hoy muestra la recomendación de riego de la red del equipo (versión 3, con las clases de la auditoría del asesor: café con malezas, banano regulado con mulch y banano denso), los avisos con fuente y una leyenda honesta. La tarjeta «Próximos 7 días» de arriba y sus pruebas no cambiaron.

### Entradas nuevas del formulario (solo para café)

- **Sombra**: sin sombra, árboles de hoja perenne, árboles de hoja caduca, banano regulado con mulch o banano denso sin deshije. Las dos de banano son clases de la auditoría del asesor del equipo (Kc y p compuestos de FAO-56; **valores de referencia, no medidos en campo**). No se combinan con los árboles.
- **Suelo entre los surcos**: limpio o con mulch, o con malezas. No se pregunta con banano (la auditoría ya trae su suelo, con mulch de *Musa*); con árboles de sombra se muestra, pero la red no tiene esa combinación: una nota lo dice y la entrada queda en 0.
- **Prioridad al regar**: ahorrar agua (precio 3 días de estrés) o proteger el cultivo (precio 1).

Se guardan en `Plantacion` (`sombra`, `sueloSurcos`, `prioridadRiego`) con valores por omisión (sin sombra, limpio, ahorrar agua). Se quitó el selector de cobertura de banano. **Datos guardados con la versión anterior:** traían `sombra: banano` y una `coberturaBanano` de 0.15 o 0.30; las dos cargan como **banano regulado** (la clase que el equipo recomienda y que la etiqueta «Regulada · 30 %» ya decía; no hay una clase de menos banano y «denso» sería afirmar de más). Hay una prueba. Los datos sin esos campos cargan con los valores por omisión.

**Por qué solo esas.** Una entrada que ningún modelo conectado usa no sirve. No se agregó «¿puede resembrar?», clase de fertilidad ni calor: ninguna red ni regla conectada en la app los consume.

### Archivos

| Archivo | Qué es |
|---|---|
| `lib/motor/pesos_cafe.dart` | Pesos de la red v3 (3 905 parámetros, 19 entradas), commit y SHA-256 de la fuente. **Generado.** |
| `lib/motor/fuentes_cafe.dart` | Textos, fuentes y confianza de los avisos (de `web/data/coffee_sources.json`). **Generado.** |
| `lib/motor/cafe.dart` | Dart puro: las 19 entradas, la regla, la decisión, la regla de antracnosis, dónde aplica y los avisos. |
| `lib/motor/recomendador.dart` | `Recomendacion` gana `riegoCafe` (decisión) y `avisosCafe`. |
| `lib/estado.dart` | `inicioDeClima`: ventana de clima de 365 días si hay café. |
| `lib/ui/plantacion.dart`, `lib/ui/hoy.dart`, `lib/textos.dart` | Formulario, tarjeta `_TarjetaCafe`, textos en español e inglés. |
| `tool/generar_pesos_cafe.mjs` | Genera los dos archivos `.dart` anteriores. |
| `tool/generar_casos_cafe.mjs` | Genera `test/casos_cafe.json` con la referencia en JavaScript (`web/js/model/coffee.js`). |
| `test/cafe_test.dart` | 44 pruebas: paridad, dónde aplica, avisos, plantación, ventana. |
| `test/pantallas_test.dart` | 6 pruebas de pantalla nuevas y 3 capturas nuevas (`18_cafe_hoy`, `19_cafe_hoy_oscuro`, `20_plantacion_cafe`). |

### Dónde aplica la red de riego

Café; la última floración (`Plantacion.fecha`) entre 20 y 100 días atrás (se entrenó a 30, 60 y 90) **y fechada del 15 de febrero al 15 de mayo** (la red solo vio floraciones del 24 de febrero al 9 de mayo, o sea decisiones entre el día del año 85 y el 219; una decisión de noviembre está fuera de lo que aprendió y daba consejos fuera de temporada); clima de hace 10 días o menos; la serie llega al 1 de noviembre anterior; y ningún riego anotado en los últimos 7 días. Si no, `riegoCafe` es nulo y la tarjeta solo muestra los avisos y una línea que explica cuándo está disponible la recomendación. Para esto la descarga de clima pasa a 365 días cuando alguna plantación es de café (sin café sigue igual: 60 a 240).

La red predice cuántos días de estrés evitaría regar 20 mm hoy; se riega si eso supera el precio. **Si el aviso de antracnosis por estrés está activo, el precio es 1 sea cual sea la prioridad elegida**, y la tarjeta lo dice. La tarjeta también muestra lo que dice la regla FAO-56 (regar si el agotamiento corrido supera el 40 % del agua disponible de 1.2 m de raíz). `soilAWmm` y la regla usan 1.2 m (la profundidad con que se entrenó la red); el balance propio de la app sigue usando 1.0 m.

### Avisos (sin red; reglas con fuente)

Salen siempre que haya clima, aunque la red no aplique. **Abono**: «aplicar ahora» o «en espera: suelo seco», solo dentro de las ventanas de Anacafé (fuera de ellas no se muestra). **Antracnosis**: Ks < 1 en más de la mitad de los últimos 28 días (balance de la app). **Roya, nivel «posible»**: junio a diciembre con temperatura media de 14 días entre 16 y 28 °C (se necesitan al menos 7 días con temperatura). Quedaron fuera el nivel «favorable» de la roya, el minador y la rama de roya de la antracnosis: necesitan medianas de varios años del sitio que la app no tiene.

### Lo medido por el equipo (`web/data/coffee_eval_v3.json`, escenarios sintéticos con el simulador del equipo)

Utilidad media (más alto es mejor; media de tres semillas) en años de prueba 2019–2024, 540 casos por sistema. La regla FAO-56 es la misma en todos (balance corrido del café, Kc 0.95, p 0.40):

| Sistema | Ahorrar agua: red | regla | Proteger: red | regla |
|---|---|---|---|---|
| Sin sombra (café de siempre) | 0.388 | 0.096 | 1.138 | 0.878 |
| Hoja perenne | 0.227 | −0.087 | 0.885 | 0.694 |
| Hoja caduca | 0.822 | 0.100 | 1.730 | 0.881 |
| Café con malezas | 0.788 | 0.120 | 1.652 | 0.902 |
| Banano regulado con mulch | 0.780 | 0.172 | 1.650 | 0.954 |
| Banano denso sin deshije | 0.894 | −0.217 | 1.844 | 0.565 |

Con la semilla exportada (29), todos los escenarios de prueba (3 240): ahorrar agua 0.650 contra 0.031 de la regla; proteger 1.479 contra 0.812. Años reservados 2022–2024 (1 620): 0.725 contra −0.189 y 1.604 contra 0.789. Estos números son contra el simulador del propio equipo, no contra una finca. Congruencia con la auditoría (2025, mismas entradas diarias): déficit regulado menos limpio +93.12 mm (auditoría +96.36), denso menos limpio +231.09 mm (+238.74), y regulado con **menos** déficit que el café con malezas (−85.19 mm; auditoría −87.16). Detalle en `proyecto/resultados-modelo-keu.md`, «Banano corregido según el asesor del equipo (tarea 41)».

### Límites

- **Las clases de banano y malezas son valores de referencia de FAO-56 de la auditoría del asesor, no mediciones** (la tarjeta lo dice con banano). Según esa auditoría, el banano regulado con mulch gasta menos agua que un cafetal al sol con malezas y más que uno con suelo limpio; la tarjeta no promete ahorro de agua. Lo que el modelo no representa: la luz, el microclima, la lluvia que baja por el pseudotallo y el flujo de caja del banano; la raíz es de 1.2 m (la auditoría usa 1.0 m). La versión anterior por cobertura (`bananaCover`, red v2) quedó archivada en el repositorio.
- La red se entrenó con lluvia de **ERA5** y temperaturas llevadas a la altura de la parcela; la app usa lluvia de **NASA POWER**, la temperatura de la celda y una ET₀ calculada con la humedad relativa. **La paridad prueba que Dart calcula lo mismo que JavaScript con la misma serie, no que la red acierte con el clima de la app.** En la app es una vista previa.
- La ventana de 365 días hace la descarga más pesada (solo con wifi, solo con café en la finca).
- Los días sin temperatura (retraso de POWER) no entran en los promedios de temperatura; lluvia y ET₀ de esos días se completan como ya hacía la app.
- No validada en campo ni probada en un teléfono. Roya favorable y minador no están.

### Paridad con la referencia

Con los 12 casos de `test/casos_cafe.json` (cada sombra y las dos clases de suelo, las dos prioridades, seco y húmedo, uno con antracnosis activa que cambia la prioridad, abono «ahora» y roya posible): diferencia máxima de las 19 entradas 0.0 (se exige 1e-9); de la predicción 0.0 (se exige 1e-5); decisión y niveles de aviso idénticos. Los 50 casos de comprobación del archivo de pesos (PyTorch, 32 bits): 8.9e-7. El clima de los casos es sintético con semilla fija.

### Cómo regenerar

```bash
node tool/generar_pesos_cafe.mjs   # pesos_cafe.dart y fuentes_cafe.dart
node tool/generar_casos_cafe.mjs   # test/casos_cafe.json
flutter test
```

### Cómo llevarlo a `app/V01`

1. Copiar a `lib/motor/`: `cafe.dart`, `pesos_cafe.dart`, `fuentes_cafe.dart` (y `red.dart` si falta); a `tool/` los dos `.mjs`; a `test/` `casos_cafe.json` y `cafe_test.dart`.
2. `lib/modelos.dart`: enums `Sombra`, `SueloSurcos` y `PrioridadRiego` y los tres campos de `Plantacion` (constructor, `aJson`, `deJson`).
3. `lib/motor/recomendador.dart`: `import 'cafe.dart';`, los campos `riegoCafe` y `avisosCafe`, y el bloque `resultadoCafe` antes del `return`.
4. `lib/estado.dart`: `diasDeClimaConCafe` e `inicioDeClima`, y usarla en `sincronizar`.
5. `lib/textos.dart`, `lib/ui/plantacion.dart` (bloque «Café») y `lib/ui/hoy.dart` (`_TarjetaCafe`).
6. Pruebas de pantalla del café y sus tres capturas; `flutter analyze` y `flutter test`. Antes de subir, preguntar al dueño del repositorio (`HANDOFF.md`).

## Lenguas mayas (borrador)

El selector de idioma de Ajustes ofrece K'iche', Kaqchikel, Q'eqchi' y Mam (bajo «Lenguas mayas (borrador)»), con textos fijos y sin conexión. **Son un borrador sin revisión de hablantes**; la app lo dice en Hoy, en Ajustes y en la pantalla «Palabras en <lengua>».

- **Qué se traduce:** solo términos sueltos del glosario: los cultivos (maíz, frijol, tomate, café) en listas, selectores y encabezado (`ixim · Maíz`; en el plano y la barra de pestañas solo el término), la pestaña «Hoy» y los rótulos sueltos de lluvia, suelo, sombra y siembra. Lo que no está en el glosario o tiene la celda vacía (banano y cosecha en mam) se queda en español.
- **Qué no se traduce y por qué:** frases, consejos, avisos y leyendas. Nadie del equipo puede verificar oraciones, y una frase equivocada de riego o plagas podría confundir a un productor. No se hace reemplazo de texto dentro de frases.
- **Cotejo:** `GLOSARIO_LENGUAS.md`. De 46 palabras, 15 coinciden con los diccionarios del equipo, 3 con otra escritura, 0 difieren y 28 están sin verificar (mam no tiene fuente).
- **Agregar o corregir una palabra:** una sola tabla, `glosario` en `lib/lenguas.dart` (palabra, cotejo y nota por lengua). Para un término nuevo, usar su `id` en `lib/textos.dart` con `_m('id', español)` (con el español al lado) o `_solo` (solo el término).
- **Traducción real:** el camino sigue siendo el traductor experimental del equipo (`modelo_lenguas_mayas/`), cuando hablantes hayan corregido sus resultados. La app no lo llama.
