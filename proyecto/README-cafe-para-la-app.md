# Café: qué tiene el modelo de Keu y qué se puede llevar a la app

15 de noviembre de 2026. Rama `modelo-keu`. Escrito para quien trabaje en la app de Carlos (`app/V01/`, en `main`), sea una persona o un asistente. Dice qué funciones de café existen, qué necesita cada una, qué de eso ya tiene la app y qué conviene implementar primero.

Nada de esto está conectado a la app todavía. El código es JavaScript puro (sin dependencias, sin acceso a red ni a archivos), así que se puede traducir a Dart función por función.

## Dónde está cada cosa

| Qué | Archivo |
|---|---|
| Código de café (cultivo, sombra, avisos, decisión de riego) | `web/js/model/coffee.js` (216 líneas) |
| Pesos de la red de riego que mejor rinde (predice y luego elige) | `web/data/coffee_ptc_mlp.json` |
| Pesos de la red que recomienda riego directamente (rinde menos) | `web/data/coffee_recommender.json` |
| Textos, fuentes y nivel de confianza de cada aviso | `web/data/coffee_sources.json` |
| Resultados medidos | `web/data/coffee_eval.json` |
| Parámetros del café | `web/data/crops.json`, cultivo `cafe` |
| Pruebas con valores calculados a mano | `tests/coffee.test.mjs`, `tests/coffee_decision.test.mjs` |
| Explicación completa y tablas | `proyecto/resultados-modelo-keu.md`, sección «Café: cultivo perenne, sombra, avisos y recomendación de riego» |
| Cómo se corresponden las entradas de la app con las del modelo | `proyecto/contrato-app-modelo.md` |

## Qué recomiendo implementar, en orden

1. **Los cuatro avisos** (roya, minador, antracnosis, abono). Son reglas con fuente, no una red. Es lo que pidió el finquero de café y lo más barato de traducir.
2. **La sombra como dato de la plantación** (sin árboles / árboles de hoja perenne / árboles de hoja caduca) y su efecto en el balance de agua.
3. **La fecha de floración calculada a partir de la lluvia**, como valor sugerido que el productor puede corregir.
4. **La recomendación de riego** (regla primero; la red después, y solo con las advertencias de más abajo).

## 1. Avisos

Cada función recibe el clima diario hasta hoy (`t` es el índice de hoy) y devuelve `{ notice, level, triggers, sourceKey, confidence }`. `triggers` trae los números que activaron el aviso, para mostrarlos. `sourceKey` es la clave del texto y la fuente en `coffee_sources.json`. **Son avisos de condiciones, no predicciones de daño ni porcentajes.**

| Función | Cuándo se activa | Niveles | Datos que necesita |
|---|---|---|---|
| `royaNotice` | De junio a diciembre. Temperatura media de los últimos 14 días entre 21 y 25 °C **y** diferencia entre máxima y mínima menor que la mediana de ese mes en el sitio → `favorable`. Temperatura media entre 16 y 28 °C → `possible` | `none`, `possible`, `favorable` | Tmax y Tmin de 14 días; mediana histórica del mes |
| `minadorNotice` | Últimos 28 días con menos de 10 mm de lluvia **y** Tmax media mayor que la mediana de ese mes en el sitio | `none`, `probable` | Lluvia y Tmax de 28 días; mediana histórica del mes |
| `antracnosisNotice` | Estrés hídrico (Ks < 1) en más de la mitad de los últimos 28 días, **o** un aviso de roya `favorable` en los 60 días anteriores | `none`, `notice` | Ks diario de 28 días; lo mismo que roya para 60 días atrás |
| `abonoNotice` | En mayo–junio, agosto–septiembre u octubre–noviembre, con el suelo húmedo (agotamiento menor que el agua fácil y al menos 10 mm de lluvia en 7 días) → `apply_now`. Si no → `wait` («abono en espera: suelo seco») | `apply_now`, `wait` | Lluvia de 7 días; agotamiento, agua total y `p` del balance |

Con `favorable`, `royaNotice` agrega `latent`: «los síntomas aparecerían en unas 5 semanas» (latencia de 31 a 37 días).

### Lo que la app ya tiene y lo que le falta para los avisos

- **Ya lo tiene:** Tmax, Tmin y lluvia diarias de NASA POWER; y del balance de agua, `ks`, `agotamiento`, `aguaTotal` y `aguaFacil` por día (`EstadoDia` en `lib/motor/fao56.dart`). Con eso, **`abonoNotice` se puede implementar hoy sin nada más**, y la parte de estrés de `antracnosisNotice` también.
- **Le falta el historial del sitio.** Roya (nivel `favorable`) y minador comparan contra la mediana de ese mes en años anteriores (`siteHistory` y `monthMedians`). La app solo descarga de 60 a 240 días. Hay tres salidas:
  - una descarga adicional de NASA POWER, una sola vez al crear la finca, de varios años de Tmax y Tmin, y guardar solo 24 números (12 medianas de la diferencia máxima–mínima y 12 de Tmax). En el modelo se usaron todos los años anteriores al actual, desde 2001;
  - mientras no exista ese historial, mostrar solo el nivel `possible` de roya (que no lo necesita) y no mostrar minador;
  - no inventar un valor fijo para la mediana: no hay fuente.
- **Roya necesita 14 días de clima hasta hoy y minador y antracnosis 28.** Las funciones lanzan un error si hay menos.
- La app ya registra la plaga que ve el productor (`notaPlaga`, `nivelPlaga`). Los avisos no la reemplazan: uno dice lo que el clima favorece y el otro lo que el productor observó. Conviene mostrarlos juntos.

### Confianza de cada aviso (está en `coffee_sources.json`; conviene mostrarla)

| Aviso | Fuente | Confianza |
|---|---|---|
| Roya, condiciones favorables | Avelino et al. 2015, Food Security 7:303-321 | Media-alta; es una correlación de campo, no un modelo |
| Roya, posible | Anacafé/Cedicafé, boletín técnico de abril de 2015 | Orientativa; condición necesaria, no suficiente |
| Minador | Ramírez-Valerio y García-Jiménez 2021 (Costa Rica); Anacafé 2026 | Baja-media; la evidencia se contradice entre sitios |
| Antracnosis | Campos-Almengor (Cedicafé), finca en Patulul | Baja-media; una finca, un año |
| Abono | Guía Técnica Anacafé 2014; boletín ENOS 2026 de Anacafé | Alta para las ventanas y para no abonar en seco; la regla numérica de humedad es convención del modelo |

## 2. Sombra

`plotAdjust(dates, shade, treeType)` devuelve dos ajustes diarios en mm para el balance de agua del lote. Sale de un solo estudio (Padovan et al. 2018, Nicaragua, 455 m): hay que decirlo donde se muestre.

| Caso | Mayo–octubre (lluvias) | Noviembre–abril (seca) |
|---|---|---|
| Con árboles: se resta a la evapotranspiración del cultivo (menos evaporación del suelo), sin bajar de cero | 0.52 mm/día | 0 |
| Árboles de hoja perenne: se suma el agua que usan los árboles | 0.2 mm/día | 0.2 mm/día |
| Árboles de hoja caduca: se suma el agua que usan los árboles | 1.2 mm/día | 0.06 mm/día |

No cambia el Kc del café ni la temperatura (no hay fuente para eso).

**En la app:** hace falta un campo nuevo en `Plantacion` (por ejemplo `sombra`: ninguna / perenne / caduca, solo para café) y aplicar los dos ajustes a `etc` dentro de `simularBalance`.

## 3. Floración

`floweringFor(dates, rain, F)`: el primer día entre el 15 de febrero y el 30 de abril del año `F` con lluvia de 10 mm o más; la floración es 9 días después. Si no hubo ese día, se usa el 9 de mayo y se marca `noTrigger`. Las ventanas sensibles después de la floración son los días 0–90 (cuaje y crecimiento del fruto) y 91–120 (llenado del grano).

**En la app:** para café, `Plantacion.fecha` ya es «la última floración» que escribe el productor. Esta función sirve para **proponer** la fecha cuando el productor no la sabe; lo que él diga manda. Necesita la lluvia desde el 15 de febrero, que cabe en la ventana de 240 días hasta mediados de octubre.

## 4. Recomendación de riego

**La decisión:** a los 30, 60 y 90 días después de la floración, regar 20 mm ahora o no regar. Se mide por los días de estrés (Ks < 1) que el riego evita en los 30 días siguientes. Regar tiene un «precio» en días de estrés: 3 si la prioridad es ahorrar agua y trabajo, 1 si es proteger el cultivo.

### La regla (sin red; se puede implementar ya)

`ruleIrrigates(depletion, taw, p)`: regar si el suelo gastó más del 40 % de su agua disponible (FAO-56, `p = 0.40`). En la app es `agotamiento > 0.40 × aguaTotal`, que es justo cuando `ks < 1`: la app ya lo calcula.

### La red que recomienda (`coffee_recommender.json`)

- **Forma:** 18 entradas → 64 → 32 → 16 → 1, tangente hiperbólica en las capas ocultas y salida lineal. 3,841 parámetros.
- **Cómo decide:** se evalúa dos veces, una por acción (`irrigate` = 0 y `irrigate` = 1). El puntaje de cada acción es `(1 si es la acción de la regla, 0 si no) + tanh(salida)`. Se recomienda la acción con el puntaje más alto; en empate, la de la regla.
- **Entradas, en este orden:** `daysSinceFlowering`, `doy`, `rain7`, `et0_7`, `rain28`, `et0_28`, `rainSinceNov1`, `et0SinceNov1`, `dryspell28`, `tmean28`, `tmaxMax28`, `runningDepletion`, `soilAWmm`, `elevation`, `shadeTrees`, `deciduous`, `priority`, `irrigate`. Las 16 primeras las arma `coffeeDecisionState`; `runningDepletion` es un balance sencillo desde el 1 de noviembre (función `runningDepletion`).
- **Estandarización:** `(valor − mean[j]) / std[j]`, con `mean` y `std` del mismo archivo.
- **Orden de los pesos en `params`:** por capa; primero los pesos fila por fila (una fila por neurona de salida, tantas columnas como entradas) y después los sesgos de esa capa. La función de referencia es `forward` en `web/js/model/recommender.js` (20 líneas; se traduce a Dart casi literal).
- **Semilla exportada:** la 17 (la de mejor validación).
- **Para comprobar la traducción:** `tests/recommender.test.mjs` prueba `forward` con valores calculados a mano; `scripts/coffee/evaluate.mjs` muestra cómo se arman las entradas y se puntúan las dos acciones con los pesos de café, y `tests/coffee_decision.test.mjs` fija las entradas del día de la decisión. Lo más seguro es sacar con Node el puntaje de unos pocos casos y comparar con el de Dart.

### Cómo rinde (1,620 casos de años nuevos, 2019–2024; utilidad media, más alto es mejor)

| Política | Prioridad «ahorrar agua» | Prioridad «proteger el cultivo» |
|---|---|---|
| Regla FAO-56 | 0.036 | 0.818 |
| Red que recomienda (tres semillas) | 0.03 – 0.16 | 0.79 – 1.10 |
| Predecir los días de estrés evitados y luego elegir (tres semillas) | 0.42 – 0.52 | 1.02 – 1.28 |

**Hay que leer esto antes de conectar la red:**

- La red que recomienda directamente (`coffee_recommender.json`) apenas iguala o supera a la regla, según la semilla. **No justifica por sí sola reemplazar la regla.**
- La política que sí mejora claramente es predecir y luego elegir. **Sus pesos ya están exportados** en `web/data/coffee_ptc_mlp.json` (ver el apartado siguiente). Si se conecta una red de riego de café, que sea esa.
- La red se entrenó con **lluvia de ERA5** y temperatura llevada a la altura de la parcela. La app usa **lluvia de NASA POWER** y temperatura de la celda sin corregir. Las entradas no significan exactamente lo mismo; no se midió cuánto cambia el resultado.
- La red necesita la lluvia y la ET₀ **desde el 1 de noviembre anterior**. A los 90 días de una floración de mayo eso son unos 280 días, más que los 240 que descarga la app. Para café habría que ampliar la ventana a 365 días.
- En `soilAWmm` va el agua disponible total de la zona de raíces en mm (agua disponible del suelo × 1.2 m de raíz), no los mm por metro.

Las tres últimas advertencias (lluvia de ERA5, ventana desde el 1 de noviembre, unidades de `soilAWmm`) valen igual para la red del apartado siguiente, porque usa las mismas 16 entradas.

Por todo esto, lo más seguro para la entrega es mostrar **la regla** como recomendación de riego del café; si hay tiempo para una red, la del apartado siguiente.

### La red que mejor rinde: predecir y luego elegir (`coffee_ptc_mlp.json`)

- **Qué predice:** cuántos días de estrés (Ks < 1) evitaría regar 20 mm hoy, en los 30 días siguientes.
- **Cómo decide:** regar si la predicción es mayor que el precio de regar: **3** días si la prioridad es ahorrar agua y trabajo, **1** día si es proteger el cultivo. No usa la regla ni necesita evaluarse dos veces.
- **Forma:** 16 entradas → 64 → 32 → 16 → 1, ReLU en las capas ocultas, salida lineal. 3,713 parámetros.
- **Entradas:** las 16 de `coffeeDecisionState`, en el mismo orden (`inputNames` del archivo): `daysSinceFlowering`, `doy`, `rain7`, `et0_7`, `rain28`, `et0_28`, `rainSinceNov1`, `et0SinceNov1`, `dryspell28`, `tmean28`, `tmaxMax28`, `runningDepletion`, `soilAWmm`, `elevation`, `shadeTrees`, `deciduous`. Sin prioridad ni acción.
- **Formato:** el mismo de `app_mlp.json` (capas con `W` y `b`, `mean`, `std`, `yMean`, `yStd`). En Dart: `predecirCapas(red, x)[0] > precio`.
- **Semilla exportada:** la 29, la de menor pérdida de validación (2017–2018) entre 17, 29 y 43.
- **Es exactamente la red que se midió:** al reentrenar para exportar, las predicciones de las tres semillas salieron idénticas a las guardadas (diferencia 0 en los 6,480 escenarios). Lo comprueba `tests/coffee_ptc.test.mjs`.
- **Casos para probar la versión en Dart:** `checkInputs` y `checkPredictions` dentro del archivo (50 casos, tolerancia 1e-5).

Utilidad media de la red exportada (de `utilityOfExported` en el archivo; más alto es mejor):

| Casos | Prioridad «ahorrar agua» | Regla | Prioridad «proteger el cultivo» | Regla |
|---|---|---|---|---|
| Años nuevos 2019–2024 (1,620) | 0.523 | 0.036 | 1.223 | 0.818 |
| Años reservados 2022–2024 (810) | 0.565 | −0.177 | 1.367 | 0.801 |

La predicción en sí es floja (R² de 0.24 en años nuevos para la semilla exportada; 0.17 a 0.28 entre las tres semillas): acierta lo suficiente para decidir mejor que la regla, pero el número de días que predice no conviene mostrárselo al productor como dato.

## Diferencias entre el café del modelo y el café de la app

| | Modelo (`crops.json`) | App (`lib/modelos.dart`) |
|---|---|---|
| Kc | 0.90 / 0.95 / 0.95 (FAO-56, suelo desnudo) | 0.95 constante |
| Profundidad de raíces | 1.2 m (rango FAO-56: 0.9–1.5) | 1.0 m |
| `p` | 0.40 | 0.40 |
| Ky (rendimiento) | No hay: FAO no lo publica | No hay |
| Suelo | Dos depósitos (raíces y subsuelo) | Un depósito que arranca medio lleno |

Ninguno de los dos da rendimiento para café. El `HANDOFF.md` de la app dice que los parámetros de café están citados de memoria: los del modelo salen de FAO-56, cuadros 12 y 22, y sirven para contrastarlos.

## Límites que hay que conservar en la app

- No hay datos de fincas para validar nada de esto. El juez de la recomendación de riego es el simulador del propio equipo.
- Los sitios usados son los diez puntos del modelo a más de 900 m. Solo Olopa y Jalapa están dentro del rango óptimo del arábica (18–21 °C de temperatura media); la mayoría no es tierra cafetalera.
- Los efectos de la sombra vienen de un solo sitio en Nicaragua.
- La lámina de 20 mm viene de un ensayo en una finca; el «precio» de regar (3 o 1 días de estrés) y el 9 de mayo como floración sin lluvia disparadora son convenciones del modelo.
- Los avisos de plagas dicen qué favorece el clima; no dicen cuánta plaga hay ni cuánto daño habrá.

---

# Cómo integrar las redes en la app (investigación del 15 de noviembre de 2026)

Vale para todas las redes del equipo, no solo la de café. Las fuentes se consultaron hoy; las notas completas, con lo que se leyó y lo que no se pudo verificar, están fuera del repositorio, en las notas de investigación de Keu (`integrar-redes-flutter.md`). Las páginas se leyeron a través de un resumen automático, no del texto crudo: conviene abrir el enlace antes de depender de un dato de versión.

## Recomendación

**Calcular la red en Dart puro, sin ninguna librería nueva.** Las redes son muy pequeñas (3,841 y 5,283 parámetros, cuatro capas): el cálculo son cuatro bucles de sumas y multiplicaciones. Un motor de inferencia (TensorFlow Lite, ONNX Runtime) agrega megabytes de código nativo y una conversión de formato para un modelo que pesa menos de 200 KB en JSON, y quita la posibilidad de probarlo con `flutter test` sin dispositivo.

El código ya está escrito y comprobado: **`scripts/app/dart/red.dart`** (solo importa `dart:math`). Se puede copiar tal cual a `app/V01/lib/motor/`.

## Opciones comparadas

| Opción | Esfuerzo | Dependencias nuevas | Tamaño que agrega | Funciona en web | Se prueba en Dart puro | Riesgo |
|---|---|---|---|---|---|---|
| **Dart puro, pesos en un archivo `.dart` generado** | 1–2 horas | Ninguna | Unos 100–200 KB | Sí | Sí | Muy bajo |
| Dart puro, pesos como recurso JSON (`rootBundle`) | 1–2 horas | Ninguna | Igual | Sí | Solo con el entorno de pruebas de Flutter inicializado | Bajo |
| `tflite_flutter` (0.12.1, publicado hace unos 12 meses; su README dice que está en desarrollo) | Días | 1, más convertir el modelo con `litert-torch` | Megabytes | **No** | No | Alto |
| `flutter_litert` (4.1.1, de un tercero; tres versiones en seis días) | Un día o más | 1 | Megabytes | Sí, solo asíncrono | No | Medio-alto |
| `flutter_onnxruntime` (1.9.0, de un tercero) | Medio día a un día | 1, más exportar a ONNX | Varios megabytes (no verificado) | Sí, con un script en `web/index.html` | No | Medio |

El esfuerzo y los tamaños de las opciones con motor son estimaciones de la investigación, no mediciones.

## Lo que hay que saber de Dart para hacerlo

- **`dart:math` no trae `tanh`.** Se usa `1 - 2 / (exp(2x) + 1)`. La forma `(eˣ − e⁻ˣ) / (eˣ + e⁻ˣ)` da `NaN` con valores grandes. La de `red.dart` devuelve 1 y −1 con ±800 (comprobado).
- **Los números son de 64 bits en Android y en web**, así que el resultado es el mismo en las dos plataformas ([dart.dev, representación de números](https://dart.dev/resources/language/number-representation)).
- **No hace falta un isolate ni `compute`.** La guía de Flutter los recomienda cuando el trabajo no cabe en un cuadro de unos 16 ms ([docs.flutter.dev, isolates](https://docs.flutter.dev/perf/isolates)); aquí son unas 5,000 multiplicaciones por llamada. En web, además, `compute` corre en el hilo principal. No se midió el tiempo en un teléfono.
- **Cómo cargar los pesos.** Hay dos caminos:
  - *Archivo Dart generado* (recomendado): un script convierte el JSON en un `const` dentro de `lib/motor/pesos_*.dart`. `recomendar(...)` sigue sin importar nada de Flutter y las pruebas de `test/motor_test.dart` funcionan igual.
  - *Recurso JSON*: declararlo en `pubspec.yaml` bajo `flutter: assets:` y leerlo con `rootBundle.loadString` ([docs.flutter.dev, recursos](https://docs.flutter.dev/ui/assets/assets-and-images)). Obliga a importar `package:flutter/services.dart`, así que conviene cargarlo en `AppEstado` y **pasar el modelo ya leído a `recomendar` como parámetro**, para que el motor siga siendo Dart puro.
- La app guarda el resultado de `recomendar` por plantación (`_recomendaciones` en `lib/estado.dart`), así que la red se evalúa una vez por plantación y cambio de datos, no en cada redibujado.

## Qué trae `scripts/app/dart/red.dart`

| Función | Para qué formato | Qué hace |
|---|---|---|
| `predecirCapas(red, x)` | `web/data/app_mlp.json` y las redes `emulator_*` (capas con `W` y `b`) | Estandariza con `mean` y `std`, ReLU en las capas ocultas, salida lineal, y la devuelve a sus unidades con `yMean` y `yStd` |
| `correccionPlana(red, x)` | `web/data/coffee_recommender.json` y `recommender_mlp.json` (`params` plano) | Estandariza, tanh en las capas ocultas, salida lineal |
| `recomiendaRegar(red, estado, reglaRiega:)` | Red de riego de café | Puntúa regar y no regar (1 para la acción de la regla más tanh de la salida) y devuelve la mayor; en empate, la regla |
| `comprobarEntradas(esperadas, armadas)` | Cualquiera | Falla con un mensaje claro si el orden o el número de entradas no coincide con `inputNames` del modelo |
| `tanh(x)` | — | La que falta en `dart:math` |

Todas fallan con `StateError` si el número de pesos no coincide con la forma de la red o si el número de entradas no coincide con `mean` y `std`.

**Ojo: los dos formatos usan activaciones distintas.** `app_mlp.json` usa ReLU; las redes que recomiendan usan tanh. `red.dart` ya lo respeta.

### Comprobación hecha

Con Dart 3.14 (`dart run scripts/app/dart/comprobar.dart`):

| Red | Casos | Diferencia máxima contra la referencia |
|---|---|---|
| `app_mlp.json` (los casos de `checkInputs` y `checkPredictions`, calculados en PyTorch) | 100 | 1.5e-6 (PyTorch calcula en 32 bits; la prueba en JS usa tolerancia 1e-5) |
| `coffee_ptc_mlp.json` (los casos guardados en el archivo, calculados en PyTorch) | 50 | 9.5e-7 |
| `coffee_recommender.json` (entradas al azar contra `forward` en JS) | 20 | 1.5e-15 |

`dart analyze` no encontró problemas. **No está probado dentro de la app ni en un teléfono.**

Para repetirlo, desde la raíz del repositorio:

```bash
node scripts/app/dart/casos_cafe.mjs casos_cafe.json
```

```bash
dart run scripts/app/dart/comprobar.dart casos_cafe.json
```

## Pasos para integrar la red alineada con la app (`app_mlp.json`)

Es la que conviene conectar primero: usa solo lo que la app ya tiene y fue medida contra el propio motor de la app (ver `proyecto/contrato-app-modelo.md`, sección 4, que trae las 40 entradas con su definición).

1. Copiar `scripts/app/dart/red.dart` a `lib/motor/red.dart`.
2. Llevar los pesos de `web/data/app_mlp.json` a la app (archivo Dart generado o recurso JSON).
3. Escribir en Dart la función que arma las 40 entradas a partir de `parcela`, `plantacion`, los `dias` de `prepararClima` y los `estados` de `simularBalance`. La referencia es `web/js/model/appInputs.js`; `tests/appInputs.test.mjs` tiene un caso calculado a mano que sirve de prueba para la versión en Dart.
4. Llamar a `comprobarEntradas(red['inputNames'], nombresArmados)` una vez al cargar.
5. En `recomendar(...)`, después de `simularBalance`, llamar a `predecirCapas` y agregar a `Recomendacion` tres campos opcionales: factor de rendimiento al final del ciclo y días de estrés esperados en los próximos 7 y 14 días. Los campos actuales no cambian, así que las pantallas siguen funcionando.
6. Mostrar el aviso solo donde la red fue medida: maíz, frijol y tomate, a secano, con el ciclo entre el 20 % y el 80 %. Fuera de eso (café, con riego registrado, cerca de la cosecha), dejar los campos en nulo.
7. Agregar a `test/motor_test.dart` una prueba con dos o tres de los casos de `checkInputs` y `checkPredictions`, con tolerancia 1e-5.

De las tres salidas, la que más aporta es el **estrés de los próximos 7 días** (F1 0.86–0.87 contra 0.69 de lo que la app muestra hoy). El rendimiento final mejora poco y en maíz y frijol es peor que el número que la app ya enseña; el aviso a 14 días avisa de más (precisión 0.55–0.60).

## Cómo evitar que un cambio de modelo rompa la app sin avisar

Son prácticas de ingeniería, no salen de una fuente:

- Guardar junto a los pesos los nombres y el orden de las entradas, la media y la desviación, y la forma de la red; comprobarlos al cargar (ya lo hacen las funciones de `red.dart`).
- Guardar unos pocos casos de entrada y salida dentro del mismo archivo (como `checkInputs` y `checkPredictions`) y probarlos en `flutter test`.
- Generar el archivo de pesos de la app con un script desde el JSON de este repositorio, nunca a mano, y anotar de qué commit salió.
- Tolerancias: 1e-9 cuando la referencia se calculó en 64 bits; 1e-5 cuando viene de PyTorch en 32 bits.

## Fuentes consultadas

- Dart: [representación de números](https://dart.dev/resources/language/number-representation), [`Float32List`](https://api.dart.dev/stable/dart-typed_data/Float32List-class.html).
- Flutter: [recursos e imágenes](https://docs.flutter.dev/ui/assets/assets-and-images), [isolates](https://docs.flutter.dev/perf/isolates), [`TestWidgetsFlutterBinding.ensureInitialized`](https://api.flutter.dev/flutter/flutter_test/TestWidgetsFlutterBinding/ensureInitialized.html).
- Paquetes: [`tflite_flutter`](https://pub.dev/packages/tflite_flutter), [`flutter_litert`](https://pub.dev/packages/flutter_litert), [`flutter_onnxruntime`](https://pub.dev/packages/flutter_onnxruntime), [`onnxruntime`](https://pub.dev/packages/onnxruntime) (sin actualizar desde hace unos dos años), [`executorch_flutter`](https://pub.dev/packages/executorch_flutter) (muy reciente).

No se pudo leer la documentación de exportación a ONNX de PyTorch ni se verificó cuánto pesa ONNX Runtime en el APK. No se confirmó en la documentación que `rootBundle` lea recursos reales bajo `flutter test`.
