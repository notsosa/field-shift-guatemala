# Café: qué tiene el modelo de Keu y qué se puede llevar a la app

15 de noviembre de 2026. Rama `modelo-keu`. Escrito para quien trabaje en la app de Carlos (`app/V01/`, en `main`), sea una persona o un asistente. Dice qué funciones de café existen, qué necesita cada una, qué de eso ya tiene la app y qué conviene implementar primero.

Nada de esto está conectado a la app todavía. El código es JavaScript puro (sin dependencias, sin acceso a red ni a archivos), así que se puede traducir a Dart función por función.

## Dónde está cada cosa

| Qué | Archivo |
|---|---|
| Código de café (cultivo, sombra, avisos, decisión de riego) | `web/js/model/coffee.js` (216 líneas) |
| Pesos de la red que recomienda riego | `web/data/coffee_recommender.json` |
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

- La red que está exportada (`coffee_recommender.json`) apenas iguala o supera a la regla, según la semilla. **No justifica por sí sola reemplazar la regla.**
- La política que sí mejora claramente (predecir y luego elegir) **no tiene sus pesos exportados**: solo se guardaron sus predicciones. Para usarla habría que volver a entrenarla y exportarla (`scripts/coffee/ptc_mlp.py`); eso lo hace Keu.
- La red se entrenó con **lluvia de ERA5** y temperatura llevada a la altura de la parcela. La app usa **lluvia de NASA POWER** y temperatura de la celda sin corregir. Las entradas no significan exactamente lo mismo; no se midió cuánto cambia el resultado.
- La red necesita la lluvia y la ET₀ **desde el 1 de noviembre anterior**. A los 90 días de una floración de mayo eso son unos 280 días, más que los 240 que descarga la app. Para café habría que ampliar la ventana a 365 días.
- En `soilAWmm` va el agua disponible total de la zona de raíces en mm (agua disponible del suelo × 1.2 m de raíz), no los mm por metro.

Por todo esto, para la entrega lo razonable es mostrar **la regla** como recomendación de riego del café y dejar la red como siguiente paso.

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
