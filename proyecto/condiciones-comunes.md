# Condiciones comunes para adaptar y medir los dos modelos

15 de noviembre de 2026. Este documento **no compara nada**. Fija las condiciones que deben cumplir por igual el modelo de la rama `modelo-keu` (Keu) y la red de política de la rama `modelo-linds` (Alex), para que la comparación sea justa cuando los dos estén entrenados. Lo único que puede cambiar entre uno y otro es la arquitectura y su forma de entrenar.

Es una propuesta de Keu. Alex puede pedir cambios; lo que se acuerde se anota al final con fecha.

## 1. La misma tarea

**Decisión:** el maíz sembrado al inicio de las lluvias se pierde. Hay que elegir qué hacer con el terreno.

- **Momento de la pérdida:** 30, 45 o 60 días después de la siembra.
- **Acciones permitidas (8):** resembrar maíz, frijol, ajonjolí, papa, cebolla, brócoli o lechuga, o dejar el terreno sin cultivo.
- **Cuándo se resiembra:** 14 días después de la pérdida.
- **Una decisión por caso.** La versión que vuelve a decidir en cada fecha queda para después, y también se haría igual para los dos.

## 2. Los mismos datos

| Uso | Sitios | Años agrícolas (abril–marzo) |
|---|---|---|
| Entrenamiento | Los 20 puntos de `scripts/emulator/points.json` | 2001–2016 |
| Validación (elegir pesos, parar) | Los mismos 20 | 2017–2018 |
| Prueba | Chiquimula, Jutiapa y San Martín Jilotepeque | 2019–2024 |

- **Casos de prueba:** 3 pilotos × 6 años × 3 momentos de pérdida = 54. Nadie los usa para entrenar, elegir ni ajustar nada.
- **Clima:** NASA POWER para temperatura, humedad, radiación y viento, con la temperatura llevada a la altura de la parcela; lluvia ERA5. Son los archivos de `web/data/snapshots/` (pilotos) y `scripts/emulator/cache/` (los 20 puntos; se regeneran con `node scripts/emulator/fetch_points.mjs`).
- **Suelo:** el de SoilGrids de cada piloto (`scripts/emulator/points.json`); en los demás puntos, las clases arena, franco y arcilla.
- **Cultivos:** los parámetros de `web/data/crops.json`.

## 3. La misma información el día de la decisión

El modelo solo puede usar lo que el productor sabría ese día:

- el clima diario **hasta el día de la decisión**, y los años anteriores completos;
- el sitio, el suelo y la fecha;
- los parámetros de los cultivos y de cada acción.

No puede usar la lluvia ni la temperatura posteriores a ese día. **Prueba obligatoria para los dos:** si se alteran los datos posteriores al día de la decisión, la decisión no cambia.

Si un modelo necesita entradas que el otro no tiene (por ejemplo, finanzas o historial de eventos), se dice cuáles y se dejan vacías en los dos, o se agregan a los dos.

## 4. El mismo juez

- **Resultado de una acción:** el rendimiento relativo por agua del cultivo resembrado, calculado con el simulador de esta rama en un commit fijo. Vale 0 si el ciclo no termina dentro del año agrícola o si se deja el terreno.
- **Cómo obtenerlo:** `scripts/compare/score_actions.mjs` califica una lista de acciones de cualquier modelo. El formato está en `proyecto/comparacion-modelos.md`, sección 4.
- **Segundo juez:** AquaCrop, donde tiene parámetros (maíz y frijol), con el mismo suelo en los dos modelos.
- Si se cambia de simulador, se cambia para los dos y se vuelve a medir a los dos.

## 5. La misma referencia

Los dos se miden contra las mismas dos referencias:

- **Regla agronómica sencilla:** resembrar maíz si quedan al menos 120 días antes del 15 de noviembre; si no, frijol si quedan al menos 70; si no, dejar el terreno.
- **Mejor opción en retrospectiva:** la acción que el juez califica más alto en ese año. Nadie puede alcanzarla; sirve de techo.

## 6. Las mismas medidas

Sobre los 54 casos de prueba, y siempre con el conteo al lado de cada porcentaje:

| Medida | Qué dice |
|---|---|
| Rendimiento relativo medio de lo elegido | Qué tan bien decide en promedio |
| Ganancia sobre la regla, con casos ganados / empatados / perdidos (tolerancia 0.001) | Si aporta algo frente a lo sencillo |
| Arrepentimiento medio frente a la mejor opción | Cuánto deja sobre la mesa |
| Percentil 10 y peor caso | Pérdidas en años malos |
| Proporción de acciones ejecutables (el ciclo termina en el año) | Si lo recomendado se puede hacer |
| Frecuencia de resultados por debajo de 0.5 | Riesgo de mala cosecha |
| Casos en que se aparta de la regla | Cuánto decide por sí mismo |
| Recomendaciones que ganan en el simulador y no en AquaCrop | Si la ventaja es solo del simulador |

**Margen:** no se mide todavía. El juez no tiene precios ni costos. Si Alex aporta precios y costos con su fuente, se agregan al juez y se mide para los dos.

## 7. El mismo presupuesto y el mismo reporte

Cada quien reporta, para su modelo:

- arquitectura y número de parámetros;
- algoritmo de entrenamiento, generaciones o épocas, y tamaño de población o de lote;
- **tres semillas** (17, 29 y 43), con el resultado de cada una y no solo el de la mejor;
- qué se eligió con validación;
- tiempo de entrenamiento y equipo usado;
- tiempo por decisión;
- el commit del simulador con que se midió.

No se fija el mismo algoritmo para los dos, porque es parte de lo que cada arquitectura propone. Sí se fija que nada se ajuste después de ver los casos de prueba.

## 8. Qué falta de cada lado

| | Keu (`modelo-keu`) | Alex (`modelo-linds`) |
|---|---|---|
| Tarea de la sección 1 | Ya medida con el simulador y las redes v2 (`web/data/decision_loss_eval.json`) | Por adaptar: sus pesos se entrenaron en otro simulador y con otras prioridades |
| Datos y juez de esta rama | Sí | Falta conectar su red a estos datos, o publicar el código que arma sus entradas |
| Tres semillas 17 / 29 / 43 | Falta: se usó la semilla 42 | Sí |
| Prueba de "sin datos futuros" | Sí | Por confirmar |
| Años de prueba 2019–2024 | Sí | Reservó 2022–2025: hay que alinear |

## Acuerdos

*(Aquí se anota, con fecha, lo que Keu y Alex acepten o cambien.)*
