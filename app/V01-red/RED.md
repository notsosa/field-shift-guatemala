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
