# Resultados · modelo-keu (simulador FAO-56 + emulador)

Actualizado el 14 de noviembre de 2026, 19:00 (hora de Guatemala). Rama `modelo-keu`. Los números salen de `web/data/emulator_eval.json` y `web/data/emulator_mlp.json`, que se regeneran con los scripts de `scripts/emulator/`.

## Qué es este modelo

1. **Simulador** (`web/js/model/`, JavaScript sin dependencias): balance diario de agua en raíces FAO-56, ET₀ Penman-Monteith, etapas del cultivo por grados-día, respuesta del rendimiento al agua FAO-33 y rotaciones por año agrícola (abril–marzo). Clima: NASA POWER (temperatura, humedad, radiación, viento) y lluvia ERA5 de Copernicus tomada por Open-Meteo.
2. **Emulador**: dos redes que aprenden a imitar al simulador a partir de 25 entradas (clima del año, ventana de floración del maíz, suelo, pendiente, riego, rotación y desfase de siembra) y predicen 3 salidas:
   - **Red embudo** 25→64→32→16→3, entrenada con backpropagation en PyTorch.
   - **ELM** (Extreme Learning Machine), entrenada **sin backpropagation**: capa oculta aleatoria fija y una sola solución de mínimos cuadrados. Se puede entrenar en el navegador.
3. **Página** `web/emulator.html`: comparación red embudo vs ELM, mapa del Corredor Seco y prueba de fecha de siembra confirmada con el simulador.

El emulador **imita al simulador; no predice cosechas reales**.

## Datos y prueba

- 50,000 ejemplos generados con el simulador: 20 cabeceras municipales del Corredor Seco × años agrícolas 2001–2024 × 4 rotaciones × riego × textura × pendiente × desfase de siembra.
- Entrenamiento: 29,974 ejemplos. Prueba: 20,026 ejemplos (años 2019–2024, o 4 municipios dejados fuera).
- Los 4 municipios dejados fuera comparten celda de NASA POWER con municipios de entrenamiento, así que **la prueba más limpia es "años nuevos" (2019–2024)**.
- Validación para elegir configuraciones: años 2017–2018. Los datos de prueba nunca se usaron para elegir nada.
- Aviso: las entradas de floración (Tarea 13e) se diseñaron después de ver un primer R² de prueba; los modelos nunca se ajustaron con filas de prueba.

## Exactitud frente al simulador (R², 1 = perfecto)

Salidas: índice de agua / agua en floración del maíz (Ks) / suelo desnudo en época lluviosa.

| Modelo | Todas las pruebas | Años nuevos 2019–2024 | Municipios nuevos |
|---|---|---|---|
| Red embudo (4,323 parámetros) | 0.872 / 0.740 / 0.984 | **0.847 / 0.665 / 0.978** | 0.878 / 0.773 / 0.990 |
| ELM, 1,500 neuronas (43,500 parámetros) | 0.814 / 0.674 / 0.979 | 0.759 / 0.514 / 0.973 | 0.846 / 0.725 / 0.985 |
| ELM del navegador, 600 neuronas | 0.756 / 0.582 / 0.965 | 0.734 / 0.349 / 0.956 | 0.765 / 0.643 / 0.974 |
| Línea base (promedio por manejo, sin clima) | 0.302 / 0.154 / 0.490 | 0.250 / 0.024 / 0.492 | 0.277 / 0.150 / 0.519 |

- La ELM se eligió con un barrido en validación (neuronas, escala de los pesos aleatorios y regularización). Ganó 1,500 neuronas, escala 0.1 y λ 0.1, en el borde de la rejilla. Con 5 semillas distintas el R² casi no cambia (desviación ≤ 0.009).
- **Meta pendiente:** el equipo fijó R² > 0.8 en años nuevos para el índice de agua y el agua en floración.
  - La red embudo la cumple en el índice de agua (0.847) y no en floración (0.665).
  - La ELM no la cumple en ninguna de las dos (0.759 y 0.514).
  - La meta no se bajó: la prueba está marcada como pendiente de decisión.

## Medidas ligadas a la decisión

- **Detectar estrés en floración** (Ks < 0.7), en años nuevos. Solo el 0.98 % de los casos tiene estrés real.

  | Modelo | Precisión | Recuperación | F1 |
  |---|---|---|---|
  | Red embudo | 0.69 | 0.73 | 0.71 |
  | ELM | 0.73 | 0.46 | 0.57 |
  | ELM del navegador | — | — | 0.36 |

- **Diferencia "alternativa menos rotación actual"** (red embudo, años nuevos):
  - índice de agua de "Proteger": error típico de ±4.5 puntos, con el signo correcto en 77 % de los casos;
  - suelo desnudo: error de ±2.7 días, con el signo correcto en 93 % de los casos.
- El agua en floración del maíz es idéntica entre rotaciones por construcción (el maíz es el mismo), así que no sirve para compararlas.

## Costo

| | Red embudo | ELM (1,500) |
|---|---|---|
| Tiempo de entrenamiento | 8.8 s en GPU (RTX 4050, CUDA) · 4.3 s en CPU | 51 s en JavaScript puro (no comparable) |
| Memoria de entrenamiento (calculada) | 0.34 MB | 17.5 MB |
| Tiempo por predicción | 12.6 µs | 72.6 µs |
| Velocidad frente al simulador (384 µs por año) | 30× por predicción, 4.9× de punta a punta | 5× por predicción, 2.9× de punta a punta |

- La GPU salió más lenta que la CPU para esta red tan pequeña.
- Para acercarse a la red embudo, la ELM necesita muchas más neuronas y unas 50 veces más memoria. Su ventaja es la sencillez: no usa backpropagation y la versión de 600 neuronas se entrena en el navegador en ~1 s.

## Juez independiente (preliminar)

Prueba hecha fuera del repo con la versión anterior del simulador, en Chiquimula, maíz sembrado el 20 de mayo, 2001–2024, mismo clima y suelo seco al inicio.

| | AquaCrop-OSPy 3.1.0 | DSSAT (CERES-Maize, DSSATTools 3.0.2) |
|---|---|---|
| Acuerdo de rangos con nuestro simulador (Spearman) | 0.62 | 0.72 |
| Coincidencia en los 5 peores años | 3 de 5 | 4 de 5 |

- 2015 es el peor año en los tres modelos; 2014 y 2019 están entre los 4 peores en los tres.
- **Debilidad encontrada:** nuestro índice es demasiado plano. Vale exactamente 1.0 en 13 de 24 años, y su coeficiente de variación es 0.08 frente a 0.40 (AquaCrop) y 0.37 (DSSAT).
- Fecha de siembra: los tres coinciden en que sembrar del 1 al 11 de mayo es lo peor; la mejor ventana difiere entre modelos.
- Son modelos sin calibrar para Guatemala: miden si la lógica coincide, no la verdad de campo.

## Limitaciones conocidas

- El modelo solo simula agua. No incluye plagas, fertilización, sombra, precios ni mano de obra.
- Al crecer las raíces, el suelo nuevo se asume a capacidad de campo. Eso "regala" agua y explica en parte el índice plano. Corrección en curso (reserva de agua del subsuelo).
- En cultivos traslapados (relevo) se usa el Kc mayor y la raíz mayor, sin competencia entre cultivos.
- Varios municipios comparten celda de clima. Salamá, Rabinal, Cubulco y San Martín Jilotepeque usan una celda a 1,516 m; los tres valles de Baja Verapaz están a unos 950 m.
- El índice de agua promedia los cultivos de comida de cada rotación, así que no es comparable entre rotaciones con cultivos distintos.
- La lluvia es ERA5 por Open-Meteo. Falta pasar a IMERG de NASA (ClimateSERV) y al suelo real de SoilGrids.
- Un cultivo que no termina su ciclo dentro del año agrícola cuenta como rendimiento 0.

## Cómo reproducir

```bash
npm test                                             # 118 pruebas (1 pendiente: la meta de R²)
node scripts/emulator/fetch_points.mjs               # descarga clima de los 20 puntos (NASA POWER + ERA5)
node scripts/emulator/generate.mjs                   # genera los 50,000 ejemplos
python scripts/emulator/train_mlp.py --device auto   # entrena la red embudo (usa CUDA si hay)
node --expose-gc scripts/emulator/evaluate.mjs       # barrido de la ELM y todas las métricas
python -m http.server 8765 -d web                    # abrir http://localhost:8765/emulator.html
```

## Propuesta para comparar con el otro modelo del equipo

Para saber cuál modelo es mejor, o si conviene alimentar uno con el otro, los dos deberían evaluarse igual:

1. **Mismos casos:** Chiquimula (14.80, −89.54), Jutiapa (14.29, −89.90) y San Martín Jilotepeque (14.78, −90.79), años agrícolas 2019–2024, que ningún modelo use para entrenar.
2. **Mismo juez:** el resultado de cada decisión se calcula con este simulador en el mismo commit, y además con AquaCrop como juez independiente para maíz, frijol y sorgo.
3. **Misma regla de información:** el modelo decide solo con lo que se sabe en la fecha de decisión, sin la lluvia futura de ese año.
4. **Mismas medidas:**
   - pérdida frente a la mejor opción posible de ese año;
   - porcentaje de casos en que gana a la práctica actual;
   - resultado en el peor año;
   - porcentaje de recomendaciones que solo ganan en nuestro simulador y no en AquaCrop.

Formas de alimentar un modelo con el otro:
- **Simulador como entorno:** este simulador sirve de entorno para la red de política (≈ 0.4 ms por año simulado).
- **Emulador como entrada:** las salidas del emulador entran como indicadores a la política.
- **Política como muestreo:** los estados que visita la política sirven como ejemplos nuevos para reentrenar el emulador.
