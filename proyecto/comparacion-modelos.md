# Cómo comparar los dos modelos

Este documento es para quien no ha visto nuestro código. Explica qué comparamos, con qué casos, con qué regla de información y cómo entregar las recomendaciones de la red de política para que nuestro simulador las puntúe en igualdad de condiciones. Los resultados de nuestro lado están en `resultados-modelo-keu.md`, sección "Decisiones con información previa".

## 1. Qué se compara y por qué

Hay dos modelos:

- **Nuestro modelo** (simulador de balance de agua FAO-56 y su emulador) predice resultados, pero no toma decisiones. Para poder compararlo, le dimos una sola decisión: cuántos días esperar, después del inicio de las lluvias, para sembrar el maíz principal.
- **La red de política** del equipo elige acciones (continuar, esperar, resembrar, cambiar de cultivo, dejar cobertura) con lo que se sabe en cada fecha de decisión.

La comparación no dice quién predice mejor la realidad. Dice cuánto vale cada decisión **cuando se la juzga con el mismo juez**. El juez es nuestro simulador, y para el maíz también AquaCrop, un segundo modelo independiente.

Nada se ajusta después de ver los resultados. La regla, los desfases, las prioridades y la tolerancia están fijados de antemano. Si un modelo no gana, se reporta que no gana.

## 2. Los casos y la regla de información

**Sitios:** Chiquimula, Jutiapa y San Martín Jilotepeque (los datos están en `web/data/snapshots/`).

**Años:** los años agrícolas 2019 a 2024. Un año agrícola va del 1 de abril al 31 de marzo. Ningún modelo debe haber entrenado con esos años.

**Manejo:** rotación actual (maíz al inicio de lluvias y frijol el 1 de septiembre), sin riego, pendiente plana.

**Suelos:** arena, franco y arcilla (las tres clases del simulador) y el suelo de SoilGrids de cada piloto. Son 3 sitios × 6 años × 4 suelos = 72 casos. Los casos con suelo del piloto son 18.

**Regla de información.** Una decisión para el año Y solo puede usar los años agrícolas anteriores a Y en ese sitio. Nada del año Y ni de años posteriores puede entrar. En nuestro código esto se cumple por construcción: la función que decide recibe los datos diarios recortados al 31 de marzo de Y. Una prueba cambia a propósito los datos desde el 1 de abril de Y y comprueba que la decisión no cambia.

Dentro del año Y, la red de política puede usar lo que se sepa hasta la fecha de decisión, pero nunca lo que pase después.

## 3. Qué puede decidir nuestro modelo y qué no

**Sí puede:** el desfase de siembra del maíz principal de la rotación actual, medido solo por agua. El desfase es de 0, 5, 10, 15, 20, 25 o 30 días después de la regla de inicio de lluvias (20 mm en 3 días después del 1 de mayo).

Los desfases negativos (sembrar antes del inicio) no son acciones posibles: exigen saber cuándo llegará la lluvia. Solo los reportamos como información de retrospectiva.

**No puede:**

- **Elegir una rotación por su valor.** Eso necesita precios y márgenes, y no están modelados.
- **Plagas y fertilización.** No están modelados.
- **Seguir una finca en el tiempo.** Cada acción se evalúa desde el suelo seco del 1 de abril. No hay estado que pase de un ciclo al siguiente, ni sublotes, ni caja.
- **Eventos a mitad de temporada** (daño, resiembra, falta de agua de riego en días concretos).

## 4. El archivo de acciones

Cada modelo entrega un archivo JSON con la lista `actions`. Cada acción lleva:

| Campo | Qué es |
|---|---|
| `id` | Nombre único de la acción (texto). |
| `site` | `chiquimula`, `jutiapa` o `sanmartin`. |
| `year` | Año agrícola (2001 a 2024), un número entero. |
| `texture` o `"soil": "site"` | `sand`, `loam` o `clay`; o el suelo de SoilGrids del piloto. Solo uno de los dos. |
| `slopeClass` | `flat`, `moderate` o `steep`. |
| `irrigation` | `none`, `limited` o `full`. |

Y además, **una** de estas dos formas:

- **Rotación:** `sequenceId` (`actual`, `proteger`, `extra_secano` o `extra_riego`) y `sowOffsetDays` (entero: días después del inicio de lluvias; negativo es antes). El desfase mueve la siembra del maíz principal. `extra_riego` exige `irrigation` distinto de `none`.
- **Un cultivo con fecha fija:** `crop` (`maiz`, `frijol` o `sorgo`) y `sowDate` (`"MM-DD"`, una fecha real del calendario).

Cualquier otro campo se rechaza, para que un error de escritura no pase en silencio. Solo se admite `note` como texto libre.

### Ejemplo que se puede correr

El archivo `scripts/compare/example_actions.json` trae dos acciones: la rotación actual en Chiquimula 2021 con franco y 10 días de espera, y maíz sembrado el 5 de junio en Jutiapa 2020 con el suelo del piloto.

```
node scripts/compare/score_actions.mjs --in scripts/compare/example_actions.json
node scripts/compare/score_actions.mjs --in mis_acciones.json --out puntuadas.json
```

Hace falta Node 18 o más. Para cada acción se obtiene:

- por cultivo: `relYield` (0 a 1, rendimiento relativo al de un año sin falta de agua), `effectiveRelYield` (0 si el ciclo no termina dentro del año agrícola), fechas de siembra y cosecha, `ksFlowerMean` y la marca `cycleIncomplete`;
- de la acción: `waterIndex` (promedio del `effectiveRelYield` de los cultivos de comida), `ksFlowerMain` (agua en la floración del cultivo principal), `bareFrac` (fracción de la época lluviosa con suelo desnudo), los días de traslape entre cultivos seguidos y `onsetFallback` (el año no tuvo inicio de lluvias y se sembró el 15 de junio).

Resultado de la primera acción del ejemplo (resumido): `waterIndex` 0.883, maíz sembrado el 16 de mayo de 2021 y cosechado el 1 de octubre, frijol sembrado el 1 de septiembre, 30 días de traslape.

Si hay una acción inválida, el programa no puntúa nada y lista todos los problemas, cada uno con el `id` de su acción. Se rechaza un sitio desconocido, un año fuera de los datos, una rotación que exige riego con `irrigation: "none"`, una fecha que no existe y cualquier campo mal escrito o faltante.

## 5. Cómo se agrega AquaCrop

AquaCrop se usa solo para el **maíz** y solo en casos con el **suelo del piloto**, porque ahí los dos modelos usan los mismos valores de θFC y θWP (con suelos de clase no son el mismo suelo). Se corre con suelo seco al inicio, una temporada por caso.

Los pasos están en `scripts/referee/README.md`, sección "How to score another model's recommendations". En resumen: para cada año y sitio se escriben dos casos de AquaCrop (la acción recomendada y la línea base), se corre `aquacrop_referee.py` y se compara el rendimiento en t/ha. Un script de ejemplo completo para nuestro lado es `scripts/compare/sowing_policy.mjs` (ver `scripts/compare/README.md`).

AquaCrop usa parámetros de cultivo sin calibrar para Guatemala. No es la verdad de campo; es un segundo modelo independiente. Sirve para detectar recomendaciones que ganan solo en nuestro simulador.

## 6. Las medidas

Por cada modelo (y prioridad), sobre todos los casos, por piloto, y por separado con suelos de clase y con el suelo del piloto:

- **Línea base:** sembrar en el inicio de lluvias (desfase 0). **Oráculo:** el mejor desfase posible de ese año, que solo se conoce al final.
- Índice de agua medio de la acción, de la línea base y del oráculo; ganancia media sobre la línea base; **arrepentimiento** medio (oráculo menos lo elegido).
- **Gana, empata, pierde** contra la línea base, con tolerancia de 0.001, siempre con el conteo de casos.
- Peor caso y percentil 10 de la acción y de la línea base.
- Lo mismo para el rendimiento relativo del **maíz** solo. Un índice de rotación que sube mientras el maíz baja debe verse, no quedar escondido.
- Días de traslape entre maíz y frijol (mediana). Sembrar tarde hace que los dos cultivos compartan el campo.
- Para suelos del piloto, con AquaCrop: ganancia media en t/ha y en %, gana/empata/pierde, y **ganancias solo del simulador** (el simulador dice que el maíz mejora y AquaCrop dice que no).

Con 18 a 72 casos no se calcula significancia. Se dan los conteos al lado de cada porcentaje.

## 7. Qué necesitamos del compañero

Para cada sitio y año (los 3 sitios y los años 2019 a 2024, o los que su red pueda cubrir):

1. **La acción recomendada** por su red, en el formato de la sección 4, decidida solo con la información disponible en la fecha de decisión.
2. **Una línea base**, también como acción: lo que se haría sin la red (por ejemplo, sembrar en el inicio de lluvias, o su regla simple).
3. **Cuándo** decidió (la fecha de decisión) y qué datos usó, para poder verificar que no entró información futura.
4. Si puede, el `id` con el sitio, año y modelo, por ejemplo `politica_chiquimula_2021`.

Con eso corremos `score_actions.mjs` sobre las dos listas y calculamos las medidas de la sección 6 con los mismos casos.

## 8. Cómo se traduce cada acción de la red

| Acción de la red | ¿Se puede puntuar? | Cómo |
|---|---|---|
| **Continuar** | Sí | Es la acción de la línea base: `sequenceId: "actual"` con `sowOffsetDays: 0`, o el plan que ya estaba en marcha. |
| **Esperar** | Sí, si es esperar a sembrar | `sowOffsetDays` positivo (días después del inicio de lluvias). Esperar a mitad de temporada, con el cultivo ya sembrado, no se puede representar. |
| **Resembrar una variedad** | **No** | El simulador tiene un solo conjunto de parámetros por cultivo, sin variedades, y no tiene evento de resiembra. Solo se puede puntuar la segunda siembra como un cultivo nuevo (`crop` y `sowDate`) desde suelo seco, sin la pérdida de la primera. Eso no es lo mismo y hay que decirlo al leer el resultado. |
| **Cambiar de cultivo** | En parte | Para maíz, frijol o sorgo: `crop` y `sowDate`. Ajonjolí, sandía, melón y tomate solo existen dentro de las rotaciones `extra_secano` y `extra_riego`, no como cultivo suelto. Solo se mide el agua: sin precios ni márgenes no se puede decir si el cambio conviene. |
| **Dejar cobertura** | En parte | La única cobertura que simula el modelo es la mucuna en relevo de la rotación `proteger`, más el rastrojo después de la cosecha. Dejar el lote con cobertura en una fecha cualquiera no se puede representar. |

En resumen, **no se pueden representar**: resiembra de una variedad, cualquier acción en medio de la temporada, el estado que pasa de un ciclo a otro, los sublotes, la caja y el flujo de dinero, la fertilización y las plagas. Esas partes de la red solo pueden evaluarse con sus propios indicadores, no con nuestro simulador.
