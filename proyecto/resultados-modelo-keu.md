# Resultados · modelo-keu (simulador FAO-56 + emulador)

Actualizado el 15 de noviembre de 2026 (emulador reentrenado el 2026-11-15 con el árbol limpio del commit `337c803`; el simulador no cambió en esta ronda). Rama `modelo-keu`. Los números salen de `web/data/emulator_eval.json`, `web/data/emulator_mlp.json`, `scripts/emulator/feature_screening.json` y `web/data/referee_aquacrop.json`, que se regeneran con los scripts de `scripts/emulator/` y `scripts/referee/`. Las columnas "antes" de la ronda de entradas de agua antecedente salen de la versión anterior de esos mismos archivos (commit `88c879f`, 25 entradas); las de la ronda anterior del simulador, del commit `9d5b5f9`.

## Qué es este modelo

1. **Simulador** (`web/js/model/`, JavaScript sin dependencias): balance diario de agua en raíces FAO-56, ET₀ Penman-Monteith, etapas del cultivo por grados-día, respuesta del rendimiento al agua FAO-33 (Ky por etapa en maíz y frijol, Ky estacional en los demás) y rotaciones por año agrícola (abril–marzo). Clima: NASA POWER (temperatura, humedad, radiación, viento) y lluvia ERA5 de Copernicus tomada por Open-Meteo.
2. **Emulador**: dos redes que aprenden a imitar al simulador a partir de 27 entradas (clima del año, ventana de floración del maíz, el agua antecedente a esa ventana, suelo, pendiente, riego, rotación y desfase de siembra) y predicen 3 salidas:
   - **Red embudo** 27→64→32→16→3, entrenada con backpropagation en PyTorch.
   - **ELM** (Extreme Learning Machine), entrenada **sin backpropagation**: capa oculta aleatoria fija y una sola solución de mínimos cuadrados. Se puede entrenar en el navegador.
3. **Página** `web/emulator.html`: comparación red embudo vs ELM, mapa del Corredor Seco y prueba de fecha de siembra confirmada con el simulador.

El emulador **imita al simulador; no predice cosechas reales**.

## Qué cambió en el simulador desde el reporte anterior

1. **Reserva de agua del subsuelo.** Al crecer las raíces ya no aparece agua nueva a capacidad de campo (commit `4ea12c1`).
2. **Ky por etapa** (vegetativa, floración, formación, maduración) para maíz y frijol, combinadas multiplicando las fracciones de rendimiento (commit `df4da88`). Sorgo, sandía y tomate siguen con el Ky estacional porque no se pudo verificar su Ky por etapa.
3. **Suelo real en los pilotos** (SoilGrids) y lluvia comparada con dos series IMERG de ClimateSERV (conjuntos 26 y 226) y CHIRPS. El modelo sigue usando ERA5 (ver limitaciones).
4. **Corrección del número de curva** del grupo hidrológico D (clase `clay`) con residuo: 85 y no 87 (TR-55, cuadro 2-2b). Cambia un poco las corridas con `clay` y residuo.
5. Un solo lugar para calcular la ventana de floración (sin cambio numérico: diferencia 0 en 360 valores comprobados) y la fuente del Ky por etapa del frijol ahora cita solo el cuadro donde se verificó.

Todos los archivos derivados se regeneraron con ese modelo en la ronda anterior (25 entradas y 3 salidas). En la ronda actual el simulador no cambia: solo se agregan 2 entradas de agua antecedente al emulador (siguiente sección); el diseño de muestreo (50,000 ejemplos), las semillas, las divisiones, las capas ocultas 64→32→16→3, la receta de entrenamiento y la rejilla de la ELM son los mismos.

## Datos y prueba

- 50,000 ejemplos generados con el simulador: 20 cabeceras municipales del Corredor Seco × años agrícolas 2001–2024 × 4 rotaciones × riego × textura × pendiente × desfase de siembra.
- Entrenamiento: 29,974 ejemplos. Prueba: 20,026 ejemplos (años 2019–2024, o 4 municipios dejados fuera).
- Los 4 municipios dejados fuera comparten celda de NASA POWER con municipios de entrenamiento, así que **la prueba más limpia es "años nuevos" (2019–2024)**.
- Validación para elegir configuraciones: años 2017–2018. Los datos de prueba nunca se usaron para elegir nada.
- Aviso: las entradas de floración (Tarea 13e) y las de agua antecedente (Tarea 19) se diseñaron **después de conocer resultados de prueba anteriores**; los modelos nunca se ajustaron con filas de prueba. Las de la Tarea 19 se eligieron con la validación (2017–2018) y la prueba se midió una sola vez, después de fijar la elección.

## Entradas de agua antecedente

**Por qué.** El coeficiente de estrés en la floración depende del agua que el suelo guardó **antes** de esa ventana (zona de raíces y subsuelo), y el emulador solo tenía entradas de la propia ventana (`rainFlower`, `drySpellFlower`, `deficitFlower`). Con 25 entradas, en años nuevos la red embudo daba 0.815 / 0.705 y la ELM 0.715 / 0.550 (índice de agua / agua en floración), por debajo de la meta de 0.8 en tres de cuatro casos.

**Protocolo fijado de antemano** (las candidatas, los conjuntos, la regla y las constantes se escribieron antes de ver ningún número y no se cambiaron):

- Las filas de prueba (años 2019–2024 o los 4 municipios dejados fuera) no se usaron para diseñar, comparar, elegir ni ajustar nada. El código del cribado no puede ni calcularlas: `build_screening_superset.mjs` descarta las filas de prueba antes de calcular las candidatas y `screen_features.py` solo lee ese archivo (20,026 filas de prueba descartadas; `nTestRowsRead: 0` en `feature_screening.json`).
- Siete candidatas, solo del clima, ET₀ y los parámetros del maíz (sin balance hídrico simulado y sin suelo, pendiente, riego ni rotación), con `f0` = primer día de la ventana de floración, `s` = día de siembra, ventanas recortadas al 1 de abril y Kc de la siembra en adelante (`kc.ini` antes): `rainPre30` (lluvia de los 30 días antes de `f0`), `drySpellPre20` (racha seca más larga en los 20 días antes), `balancePre30` y `balanceSeason` (Σ lluvia − Kc·ET₀ en los 30 días antes y desde la siembra), `rainPreSow30` (lluvia de los 30 días antes de sembrar), `apiFlower` (índice de precipitación antecedente, `API = 0.9·API + lluvia` desde el 1 de abril) y `storeProxy` (balance corrido con piso en 0 y tope fijo de 150 mm para todo suelo, desde el 1 de abril). **`storeProxy` es un indicador sin suelo, no el simulador.**
- Cinco conjuntos: S0 (las 25 actuales, control), S1 = S0 + {`rainPre30`, `drySpellPre20`}, S2 = S0 + {`balancePre30`, `balanceSeason`, `rainPreSow30`}, S3 = S0 + {`apiFlower`, `storeProxy`}, S4 = S0 + las siete.
- Regla: red embudo con la receta estándar (mismo código que `train_mlp.py`, semilla 42), ajustada con las filas de entrenamiento fuera de 2017–2018 y puntuada en las filas de validación (2017–2018, puntos de entrenamiento); puntaje = promedio del R² de índice de agua y de agua en floración. Se excluye un conjunto si su R² de suelo desnudo en validación cae más de 0.005 bajo el de S0; gana el mayor puntaje, y entre conjuntos a menos de 0.005 el de menos entradas; si ninguno supera a S0 por al menos 0.01, se queda S0.

**Cribado (solo validación 2017–2018; 26,618 filas de ajuste, 3,356 de validación).**

| Conjunto | Entradas | R² índice de agua | R² agua en floración | R² suelo desnudo | Puntaje | ¿Excluido? |
|---|---|---|---|---|---|---|
| S0 (control) | 25 | 0.881 | 0.739 | 0.980 | 0.810 | no |
| S1 (+ `rainPre30`, `drySpellPre20`) | 27 | 0.902 | 0.842 | 0.980 | 0.872 | no |
| S2 (+ `balancePre30`, `balanceSeason`, `rainPreSow30`) | 28 | 0.913 | 0.843 | 0.984 | 0.878 | no |
| **S3 (+ `apiFlower`, `storeProxy`)** | 27 | 0.925 | 0.921 | 0.986 | 0.923 | no |
| S4 (+ las siete) | 32 | 0.924 | 0.925 | 0.989 | 0.924 | no |

**Elegido: S3** (`apiFlower`, `storeProxy`; 27 entradas, 4,451 parámetros). S3 y S4 quedan a 0.0016 de diferencia (dentro de 0.005), así que gana el de menos entradas; S3 supera a S0 en +0.113 de puntaje (el mínimo era 0.01). Se compararon 5 conjuntos en validación. Dos precisiones: el R² de validación de la red de cada conjunto usa las mismas filas con las que esa red decide cuándo parar el entrenamiento (la receta estándar), lo que lo vuelve algo optimista, igual para todos los conjuntos; y el R² de prueba posterior es menor que el de validación (abajo).

**Una sola evaluación final de prueba**, con la configuración elegida y por la tubería normal (`generate.mjs` → `train_mlp.py` en CUDA → `evaluate.mjs`), sin segunda iteración. Lo que salió se informa tal cual.

## Exactitud frente al simulador (R², 1 = perfecto)

Salidas: índice de agua / agua en floración del maíz (Ks) / suelo desnudo en época lluviosa.

| Modelo | Todas las pruebas | Años nuevos 2019–2024 | Municipios nuevos |
|---|---|---|---|
| Red embudo (4,451 parámetros) | 0.896 / 0.934 / 0.989 | **0.842 / 0.876 / 0.986** | 0.916 / 0.948 / 0.992 |
| ELM, 1,500 neuronas (46,500 parámetros) | 0.841 / 0.886 / 0.974 | 0.763 / 0.796 / 0.968 | 0.876 / 0.912 / 0.982 |
| ELM del navegador, 600 neuronas | 0.780 / 0.818 / 0.961 | 0.711 / 0.698 / 0.952 | 0.808 / 0.854 / 0.971 |
| Línea base (promedio por manejo, sin clima) | 0.251 / 0.137 / 0.490 | 0.189 / 0.036 / 0.492 | 0.218 / 0.129 / 0.519 |

**Antes → después de las entradas de agua antecedente** (R² del emulador, commit `88c879f` con 25 entradas → ahora con 27; índice de agua / agua en floración / suelo desnudo):

| Modelo | Años nuevos 2019–2024 | Todas las pruebas | Municipios nuevos |
|---|---|---|---|
| Red embudo | 0.815 / 0.705 / 0.976 → **0.842 / 0.876 / 0.986** | 0.867 / 0.801 / 0.983 → 0.896 / 0.934 / 0.989 | 0.884 / 0.834 / 0.990 → 0.916 / 0.948 / 0.992 |
| ELM, 1,500 neuronas | 0.715 / 0.550 / 0.973 → 0.763 / 0.796 / **0.968** | 0.808 / 0.724 / 0.979 → 0.841 / 0.886 / **0.974** | 0.845 / 0.769 / 0.985 → 0.876 / 0.912 / **0.982** |
| ELM del navegador | 0.693 / 0.450 / 0.956 → 0.711 / 0.698 / **0.952** | 0.755 / 0.628 / 0.965 → 0.780 / 0.818 / **0.961** | 0.768 / 0.663 / 0.974 → 0.808 / 0.854 / **0.971** |
| Línea base | 0.189 / 0.036 / 0.492 (sin cambio) | 0.251 / 0.137 / 0.490 (sin cambio) | 0.218 / 0.129 / 0.519 (sin cambio) |

- **Mejoró:** el índice de agua y, sobre todo, el agua en floración en los tres modelos y en las tres divisiones. En años nuevos, el agua en floración de la red embudo subió de 0.705 a 0.876 y la de la ELM de 0.550 a 0.796.
- **Empeoró (en negritas arriba):** el R² del suelo desnudo de la ELM y de la ELM del navegador bajó en las tres divisiones (años nuevos 0.973 → 0.968 y 0.956 → 0.952; sigue alto). Las dos entradas nuevas no ayudan a esa salida en las ELM. En la red embudo el suelo desnudo mejoró (0.976 → 0.986). El RMSE del suelo desnudo también subió en las dos ELM en las tres divisiones (ELM en años nuevos 0.0148 → 0.0162). En la división de municipios nuevos en años nuevos (`testBoth`), el R² del índice de agua de la ELM del navegador bajó de 0.741 a 0.732 (RMSE 0.1127 → 0.1148).
- La validación fue más optimista que la prueba: S3 sacó 0.925 / 0.921 en validación y la red embudo 0.842 / 0.876 en años nuevos.
- La ELM se eligió otra vez con el barrido en validación: 1,500 neuronas, escala 0.1 y λ 0.1 (el borde de la rejilla); la del navegador, 600 neuronas con los mismos valores. Con 5 semillas distintas el R² casi no cambia (desviación ≈ 0.004).
- **Meta de R² > 0.8 en años nuevos para el índice de agua y el agua en floración** (la meta no se bajó ni se tocó la prueba):

  | Modelo | Índice de agua | Agua en floración | Estado |
  |---|---|---|---|
  | Red embudo | 0.842 (cumple) | 0.876 (cumple) | **Cumple las dos** |
  | ELM, 1,500 neuronas | 0.763 (no) | 0.796 (no, a 0.004) | **No cumple ninguna** |
  | ELM del navegador (no entra en la prueba de la meta) | 0.711 (no) | 0.698 (no) | No cumple |

  La prueba `emulator_eval.test.mjs` sigue marcada como pendiente porque la ELM no llega; la red embudo ya cumple.

**Ronda anterior (cambio del simulador; R² en años nuevos, índice de agua / agua en floración):**

| Modelo | Simulador anterior (`9d5b5f9`) | Simulador final con 25 entradas (`88c879f`) |
|---|---|---|
| Red embudo | 0.847 / 0.665 | 0.815 / 0.705 |
| ELM, 1,500 neuronas | 0.759 / 0.514 | 0.715 / 0.550 |
| ELM del navegador | 0.734 / 0.349 | 0.693 / 0.450 |

El índice de agua se había vuelto más difícil de imitar con el cambio del simulador (una causa probable, no medida: el simulador varía más entre años y combina las etapas por producto); con las entradas nuevas la red embudo pasa de 0.815 a 0.842, sin volver al 0.847 de antes.

## Medidas ligadas a la decisión

- **Detectar estrés en floración** (Ks < 0.7), en años nuevos. El 1.74 % de los casos tiene estrés real (igual que antes: esta vez sí es la misma comparación).

  | Modelo | F1 (antes, `88c879f`) | Precisión | Recuperación | F1 (ahora) |
  |---|---|---|---|---|
  | Red embudo | 0.72 | 0.80 | 0.79 | 0.80 |
  | ELM | 0.66 | 0.85 | 0.69 | 0.76 |
  | ELM del navegador | 0.52 | 0.84 | 0.61 | 0.71 |

- **Diferencia "alternativa menos rotación actual"** (años nuevos; error típico por municipio-año-manejo y porcentaje de casos con el signo correcto), antes (`88c879f`) → ahora:

  | Modelo | Alternativa | Índice de agua: error (puntos) | signo correcto | Suelo desnudo: error (días) | signo correcto |
  |---|---|---|---|---|---|
| Red embudo | Proteger | ±7.0 → ±5.9 | 68 % → 68 % | ±3.0 → ±2.4 | 97 % → 91 % |
| Red embudo | Extra (secano) | ±7.3 → ±7.2 | 92 % → 91 % | ±3.0 → ±2.5 | 99 % → 95 % |
| Red embudo | Extra (riego) | ±7.8 → ±7.2 | 97 % → 97 % | ±2.6 → ±2.1 | 91 % → 96 % |
| ELM | Proteger | ±7.4 → ±7.0 | 67 % → 71 % | ±2.7 → ±2.8 | 94 % → 95 % |
| ELM | Extra (secano) | ±7.7 → ±7.9 | 90 % → 91 % | ±2.6 → ±2.7 | 96 % → 95 % |
| ELM | Extra (riego) | ±7.1 → ±7.0 | 94 % → 96 % | ±2.3 → ±2.7 | 96 % → 93 % |
| ELM del navegador | Proteger | ±7.6 → ±7.3 | 65 % → 64 % | ±3.7 → ±3.7 | 97 % → 99 % |
| ELM del navegador | Extra (secano) | ±8.8 → ±9.2 | 89 % → 87 % | ±3.8 → ±3.8 | 96 % → 99 % |
| ELM del navegador | Extra (riego) | ±7.5 → ±7.3 | 98 % → 97 % | ±3.4 → ±3.6 | 95 % → 93 % |

  - La red embudo mejora el error del índice de agua en las tres alternativas, pero **el signo correcto de "Proteger" en el índice de agua no cambia** (68 %) y el de "Extra (secano)" baja un poco (92 % → 91 %).
  - **Empeoró, red embudo:** el signo correcto del suelo desnudo de "Proteger" (97 % → 91 %) y de "Extra (secano)" (99 % → 95 %), aunque su error en días bajó, y el signo correcto del índice de agua de "Extra (secano)" (92 % → 91 %).
  - **Empeoró, ELM:** el error del índice de agua de "Extra (secano)" (±7.7 → ±7.9 puntos); el error del suelo desnudo en las tres alternativas (±2.7 → ±2.8, ±2.6 → ±2.7 y ±2.3 → ±2.7 días); el signo del suelo desnudo de "Extra (secano)" (96 % → 95 %) y de "Extra (riego)" (96 % → 93 %); y el error de Ks de "Proteger" (RMSE 0.0083 → 0.0090).
  - **Empeoró, ELM del navegador:** el signo del índice de agua de "Proteger" (65 % → 64 %); el error y el signo del índice de agua de "Extra (secano)" (±8.8 → ±9.2 puntos; 89 % → 87 %); el signo del índice de agua de "Extra (riego)" (98 % → 97 %); y el error y el signo del suelo desnudo de "Extra (riego)" (±3.4 → ±3.6 días; 95 % → 93 %).
- La diferencia de "Proteger" en el índice de agua sigue siendo la medida menos confiable del emulador: la red embudo se equivoca de signo en 1 de cada 3 casos (68 % correcto) y la ELM en 29 % de los casos.
- El agua en floración del maíz es idéntica entre rotaciones por construcción (el maíz es el mismo), así que no sirve para compararlas.

## Costo

| | Red embudo | ELM (1,500) |
|---|---|---|
| Tiempo de entrenamiento | 23.9 s en GPU (RTX 4050, CUDA) · 6.9 s en CPU | 45 s en JavaScript puro (no comparable) |
| Memoria de entrenamiento (calculada) | 0.35 MB | 17.6 MB |
| Tiempo por predicción | 9.5 µs | 57.7 µs |
| Velocidad frente al simulador (394 µs por año) | 42× por predicción, 7.7× de punta a punta | 6.8× por predicción, 3.3× de punta a punta |

- Antes (`88c879f`): 9.9 s GPU / 4.9 s CPU; ELM 47 s; 9.7 µs y 52.3 µs por predicción; simulador 321 µs por año; 33× y 6× por predicción, 7.8× y 3.7× de punta a punta. Los tiempos dependen de la máquina y de lo que estuviera corriendo (el simulador no cambió y midió 394 µs en lugar de 321 µs), así que las diferencias pequeñas no son reales y los factores de velocidad no se pueden comparar con exactitud. **Más lento:** la red embudo tardó más en entrenar (48 épocas contra 34: 23.9 s en GPU y 6.9 s en CPU) y el tiempo por predicción de la ELM subió de 52.3 a 57.7 µs y la preparación de entradas de punta a punta cuesta más (51 µs contra 41 µs por año con la red embudo; 119 µs contra 87 µs con la ELM; 78 µs contra 51 µs con la ELM del navegador), porque ahora se calculan también `apiFlower` y `storeProxy`. Parámetros: 4,323 → 4,451 la red embudo y 43,500 → 46,500 la ELM (27 entradas); la memoria calculada casi no cambia (0.339 → 0.345 MB y 17.53 → 17.56 MB).
- La GPU sigue siendo más lenta que la CPU para esta red tan pequeña. Los 6.9 s de CPU salen de una corrida aparte, con los mismos datos, cuyos pesos no se guardan.
- Para acercarse a la red embudo, la ELM necesita muchas más neuronas y unas 50 veces más memoria. Su ventaja es la sencillez: no usa backpropagation y la versión de 600 neuronas se entrena en el navegador en ~1 s.

## Juez independiente (AquaCrop)

AquaCrop-OSPy 3.1.0 en Chiquimula, mismo clima (ERA5 del bundle actual) y suelo seco al inicio, 2001–2024. **Una sola corrida de AquaCrop** se compara con cuatro versiones del simulador, así que solo cambia el modelo. **Ojo con el suelo:** los casos con suelo por clase (franco, arena, arcilla) **no usan el mismo suelo** en los dos modelos: AquaCrop usa su propio perfil por defecto y el simulador el suyo (tabla siguiente). El 0.85 del titular compara el franco de cada modelo con el suyo; solo los casos con el suelo de SoilGrids dan los mismos θFC y θWP a los dos modelos. Maíz sembrado el 20 de mayo (`maiz_0520`) y frijol el 1 de septiembre (`frijol_0901`).

| Clase | AquaCrop (por defecto): θWP / θFC / θs, Ksat (mm/día) | Simulador: θWP / θFC |
|---|---|---|
| Franco | 0.15 / 0.31 / 0.46, 500 | 0.12 / 0.25 |
| Arena | 0.06 / 0.13 / 0.36, 3000 | 0.045 / 0.12 |
| Arcilla | 0.39 / 0.54 / 0.55, 35 | 0.22 / 0.36 |

Los perfiles de AquaCrop se leen del paquete `aquacrop` (`soilComparison` en `web/data/referee_aquacrop.json`), no se escribieron a mano. La arena es la clase más parecida entre los dos modelos; la arcilla es la menos comparable (en AquaCrop θs casi igual a θFC y Ksat muy baja).

| Versión del simulador | Spearman maíz | Coincidencia en 5 peores (maíz) | CV maíz (AquaCrop 0.40) | Años en 1.0 (maíz) | Spearman frijol | CV frijol (AquaCrop 0.35) | Años en 1.0 (frijol) |
|---|---|---|---|---|---|---|---|
| `pre-subsoil` (d02febe) | 0.615 | 3 de 5 | 0.078 | 13 de 24 | 0.599 | 0.118 | 5 |
| `subsoil` (4ea12c1) | 0.856 | 3 de 5 | 0.111 | 9 de 24 | 0.599 | 0.118 | 5 |
| `stage-ky` (df4da88) | 0.851 | 3 de 5 | 0.250 | 9 de 24 | 0.635 | 0.204 | 5 |
| `final` (HEAD) | 0.851 | 3 de 5 | 0.250 | 9 de 24 | 0.635 | 0.204 | 5 |

Lugar de los años secos en el maíz (1 = el peor; entre paréntesis, el lugar en AquaCrop):

| Versión | 2014 | 2015 | 2018 | 2019 |
|---|---|---|---|---|
| `pre-subsoil` | 2 (4) | 1 (1) | 5 (11) | 4 (2) |
| `subsoil` | 2 (4) | 1 (1) | 5 (11) | 3 (2) |
| `stage-ky` y `final` | 2 (4) | 1 (1) | 4 (11) | 3 (2) |

Frijol, lugar de 2014 / 2015 / 2018 / 2019 (AquaCrop: 19 / 20 / 13 / 21): 17 / 15 / 10 / 20 en `pre-subsoil` y `subsoil`; 17 / 13 / 12 / 20 en `stage-ky` y `final`.

- **Lo que mejoró:** el acuerdo de rangos del maíz subió de 0.62 a 0.85 con el subsuelo, y el índice dejó de ser tan plano (CV de 0.08 a 0.25; AquaCrop da 0.40). Los años exactamente en 1.0 bajaron de 13 a 9 de 24.
- **Lo que no mejoró:** la coincidencia en los 5 peores años sigue en 3 de 5 (AquaCrop: 2011, 2014, 2015, 2019, 2023; simulador: 2004, 2014, 2015, 2018, 2019). 2011 y 2023 no se detectan. En frijol el acuerdo es bajo (0.64). El índice sigue más plano que el de AquaCrop (0.25 contra 0.40) y sigue valiendo exactamente 1.0 en 9 años.
- `final` y `stage-ky` dan lo mismo en maíz y frijol con suelo franco: la corrección del número de curva solo afecta a la clase `clay`.
- Con el suelo de SoilGrids de Chiquimula en los dos modelos (`maiz_0520_site`) el acuerdo es 0.89 y la coincidencia en los 5 peores años, 4 de 5. Las versiones anteriores no aceptan un objeto de suelo, así que ese caso solo existe para `final`.

**Fecha de siembra (maíz, versión `final`).** Valor relativo mediano por fecha. AquaCrop se mide contra su mejor rendimiento de todas las fechas y años; el simulador, contra el rendimiento sin estrés.

| Fecha | AquaCrop | Simulador (mediana) | Simulador (media) | Simulador (p10) |
|---|---|---|---|---|
| 1 may | 0.60 | 0.89 | 0.80 | 0.44 |
| 11 may | 0.76 | 0.95 | 0.84 | 0.57 |
| 21 may | 0.76 | 0.97 | 0.88 | 0.57 |
| 31 may | 0.86 | 1.00 | 0.91 | 0.69 |
| 10 jun | 0.90 | 1.00 | 0.95 | 0.83 |
| 20 jun | 0.94 | 1.00 | 0.97 | 0.98 |
| 30 jun | 0.79 | 1.00 | 0.99 | 0.95 |
| 10 jul | 0.82 | 1.00 | 0.98 | 0.92 |

Los dos coinciden en que sembrar el 1 de mayo es lo peor y en que de mediados de junio en adelante es mejor. La mejor fecha de AquaCrop es el 20 de junio; en el simulador es una meseta (1.00 desde el 31 de mayo). El simulador no ve la pérdida que AquaCrop da al sembrar el 30 de junio o después.

AquaCrop usa parámetros de cultivo sin calibrar para Guatemala: mide si la lógica coincide, no la verdad de campo. La prueba con DSSAT (CERES-Maize) del reporte anterior se hizo fuera del repo con la versión anterior del simulador y no se repitió, así que ya no se cita.

### Los 3 pilotos con el modelo final

Maíz sembrado el 20 de mayo, 2001–2024, clima propio de cada piloto (ERA5), tres suelos: franco (el de cada modelo, **no** el mismo), el suelo de SoilGrids del piloto (**la única comparación con el mismo suelo**: mismos θFC y θWP en los dos modelos, CN del piloto en el simulador) y la clase `nearestTexture` del piloto (la de cada modelo, tampoco es el mismo suelo), que es lo que recibiría el emulador.

| Piloto | Suelo | Spearman | Coincidencia 5 peores | CV AquaCrop / simulador | Años en 1.0 |
|---|---|---|---|---|---|
| Chiquimula | franco | 0.851 | 3 | 0.40 / 0.25 | 9 |
| | SoilGrids | 0.888 | 4 | 0.41 / 0.26 | 9 |
| | `nearestTexture` = arcilla (*) | −0.051 | 3 | 1.15 / 0.26 | 9 |
| Jutiapa | franco | 0.879 | 4 | 0.47 / 0.36 | 8 |
| | SoilGrids | 0.792 | 3 | 0.53 / 0.78 | 0 |
| | `nearestTexture` = arena (*) | 0.716 | 3 | 0.38 / 0.67 | 2 |
| San Martín | franco | 0.514 | 3 | 0.25 / 0.11 | 5 |
| | SoilGrids | 0.550 | 3 | 0.25 / 0.11 | 5 |
| | `nearestTexture` = franco | 0.514 | 3 | 0.25 / 0.11 | 5 |

En los 3 pilotos ningún ciclo de maíz quedó incompleto en el simulador y AquaCrop dio rendimiento en todos los años.

(*) Todas las filas con suelo por clase (franco, arena, arcilla) comparan el perfil de AquaCrop con el del simulador, que son distintos (tabla de suelos arriba). La fila de arcilla es la menos comparable: en AquaCrop la arcilla tiene θs casi igual a θFC y Ksat muy baja, y por eso el CV de AquaCrop en Chiquimula llega a 1.15; no se debe leer como un fallo del simulador. Con el suelo de SoilGrids (mismos θFC y θWP) la comparación sí es del mismo suelo: Chiquimula 0.888, Jutiapa 0.792, San Martín 0.550.

**Suelos de los pilotos (SoilGrids, 0–100 cm).** Son una predicción global, no una medición de campo, y **necesitan verificación local**.

| Piloto | θFC | θWP | Agua disponible | CN (cultivo / residuo / desnudo) | `nearestTexture` |
|---|---|---|---|---|---|
| Chiquimula (franco arcilloso) | 0.330 | 0.180 | 0.150 | 89 / 85 / 94 | arcilla |
| Jutiapa (arcilla) | 0.359 | 0.304 | 0.056 | 89 / 85 / 94 | arena |
| San Martín (franco arcilloso) | 0.342 | 0.211 | 0.131 | 89 / 85 / 94 | franco |

`nearestTexture` (en `scripts/emulator/points.json`) se elige **solo por el agua disponible** (θFC − θWP) y no mira la escorrentía. Por eso puede no coincidir con la clase más cercana en el resultado del simulador. Jutiapa es una arcilla del grupo hidrológico D (CN 89/85/94) pero queda como `arena` (CN 67/64/77); Chiquimula, un franco arcilloso, queda como `arcilla`. Error medido: diferencia absoluta media del `relYield` entre el suelo del sitio y cada clase (maíz 20 de mayo, 2001–2024, mismo clima):

| Piloto | arena | franco | arcilla | Clase más cercana en resultado | ¿Es `nearestTexture`? |
|---|---|---|---|---|---|
| Chiquimula | 0.141 | 0.039 | 0.013 | arcilla | sí |
| Jutiapa | 0.096 | 0.329 | 0.354 | arena | sí |
| San Martín | 0.123 | 0.006 | 0.020 | franco | sí |

En estos 3 pilotos `nearestTexture` sí es la clase más cercana en resultado, pero eso no está garantizado en otro punto, porque la regla no mira la escorrentía. El error que hereda el emulador por tener solo 3 clases de suelo es de 0.013 (Chiquimula), 0.096 (Jutiapa) y 0.006 (San Martín) en `relYield`. El de Jutiapa es grande: su agua disponible es muy baja (0.056) y ninguna de las tres clases se le parece (las otras dos quedan a más de 0.32).

### Sensibilidad a la lluvia (Chiquimula)

**Nombres de las series IMERG.** ClimateSERV ofrece dos conjuntos de datos IMERG diarios. En la página de documentación de ClimateSERV (https://climateserv2.servirglobal.net/develop-api, "List of Datatypes", consultada el 15 de noviembre de 2026) el conjunto **26** se llama "NASA-IMERG-V06-Late 1 Day" y el **226**, "NASA-IMERG-V07-Late 1 Day". Las respuestas de datos de la API traen solo el número del conjunto, no el nombre. Aquí `IMERG` es el conjunto 26 (el de las rondas anteriores) e `IMERG_LATE` es el conjunto 226. El conjunto 226 se probó porque la auditoría de un compañero (`auditorias/prueba frijol maiz 2025` en `origin/main`) obtuvo con él los 365 días de 2025.

Maíz el 20 de mayo, franco de cada modelo (no es el mismo suelo; ver la tabla de suelos), modelo final, con cada producto de lluvia en el simulador **y** en AquaCrop. Primera comparación: los tres productos originales (ERA5, IMERG conjunto 26, CHIRPS), solo los 22 años agrícolas completos en los tres (se excluyen 2019 y 2024, donde el conjunto 26 tiene huecos; no se rellenó ningún hueco). POWER no se usa nunca como lluvia. El modelo sigue usando ERA5: esto mide una brecha de información, no elige un producto. Estas cifras no cambiaron al agregar el conjunto 226.

| Producto | Lluvia media (mm por año agrícola) | Spearman simulador vs AquaCrop | Coincidencia 5 peores | CV del simulador | Años en 1.0 |
|---|---|---|---|---|---|
| ERA5 | 1,098.9 | 0.846 | 3 | 0.24 | 9 |
| IMERG (conjunto 26) | 1,164.1 | 0.602 | 4 | 0.21 | 6 |
| CHIRPS | 1,307.9 | 0.632 | 2 | 0.07 | 14 |

Acuerdo entre productos:

| Par | Spearman del simulador | Coincidencia 5 peores del simulador | Diferencia media de `relYield` | Spearman de AquaCrop |
|---|---|---|---|---|
| ERA5–IMERG (26) | 0.633 | 3 | 0.099 | 0.673 |
| ERA5–CHIRPS | 0.658 | 3 | 0.087 | 0.735 |
| IMERG (26)–CHIRPS | 0.831 | 3 | 0.096 | 0.791 |

**Con el conjunto 226 (cuatro productos).** El conjunto 226 tampoco está completo: faltan 40 días (`rain_compare.json`, `coverage.missingDays`), los mismos en los 3 pilotos (del 1 al 7 de junio de 2014, el 31 de diciembre de 2023, el 1 de enero de 2024 y todo mayo de 2024), y por eso quedan fuera los años agrícolas 2014, 2023 y 2024. Los años agrícolas completos en los cuatro productos son 20 (2001–2013, 2015–2018 y 2020–2022); no se rellenó ningún hueco.

| Producto | Lluvia media (mm por año agrícola) | Spearman simulador vs AquaCrop | Coincidencia 5 peores | CV del simulador | Años en 1.0 |
|---|---|---|---|---|---|
| ERA5 | 1,110.3 | 0.834 | 3 | 0.22 | 9 |
| IMERG (26) | 1,139.6 | 0.609 | 3 | 0.19 | 5 |
| CHIRPS | 1,317.9 | 0.693 | 3 | 0.06 | 13 |
| IMERG_LATE (226) | 1,574.5 | 0.843 | 4 | 0.06 | 10 |

| Par | Spearman del simulador | Coincidencia 5 peores del simulador | Diferencia media de `relYield` | Spearman de AquaCrop |
|---|---|---|---|---|
| ERA5–IMERG (26) | 0.672 | 2 | 0.105 | 0.683 |
| ERA5–CHIRPS | 0.659 | 2 | 0.076 | 0.678 |
| ERA5–IMERG_LATE | 0.753 | 3 | 0.074 | 0.681 |
| IMERG (26)–CHIRPS | 0.813 | 4 | 0.090 | 0.806 |
| IMERG (26)–IMERG_LATE | 0.677 | 3 | 0.087 | 0.881 |
| CHIRPS–IMERG_LATE | 0.747 | 4 | 0.020 | 0.832 |

Con la lluvia del conjunto 226 el CV del simulador baja a 0.06 (con ERA5, 0.22): es el mismo CV bajo que da CHIRPS (0.06), así que su Spearman de 0.843 se calcula sobre diferencias pequeñas de `relYield`. Este documento no establece por qué el CV es bajo con esas dos series.

**Solo los productos completos, los 24 años (2001–2024).** Solo ERA5 y CHIRPS no tienen ningún día faltante en los 24 años agrícolas; ninguna de las dos series IMERG es completa, así que no entran aquí.

| Producto | Lluvia media (mm por año agrícola) | Spearman simulador vs AquaCrop | Coincidencia 5 peores | CV del simulador | Años en 1.0 |
|---|---|---|---|---|---|
| ERA5 | 1,094.9 | 0.851 | 3 | 0.25 | 9 |
| CHIRPS | 1,297.4 | 0.625 | 1 | 0.07 | 14 |

Par ERA5–CHIRPS en los 24 años: Spearman del simulador 0.692, coincidencia de los 5 peores 4, diferencia media de `relYield` 0.101, Spearman de AquaCrop 0.693.

Con otro producto de lluvia el orden de los años del simulador cambia mucho (Spearman entre productos de 0.63 a 0.83 en los 22 años y de 0.66 a 0.81 en los 20) y AquaCrop se mueve parecido: la elección de la lluvia pesa tanto como los cambios de modelo de esta ronda. Que ERA5 concuerde mejor con AquaCrop no prueba que ERA5 esté más cerca de la realidad: en cada fila los dos modelos reciben la misma lluvia.

**Lluvia media por producto y piloto** (mm por año agrícola, de `web/data/rain_compare.json`; POWER solo para comparar, el modelo no la usa; n/d = no se calcula sobre ese conjunto de años).

| Piloto | Años | ERA5 | IMERG (26) | CHIRPS | IMERG_LATE (226) | POWER |
|---|---|---|---|---|---|---|
| Chiquimula | 22 comunes sin IMERG_LATE | 1,098.9 | 1,164.1 | 1,307.9 | n/d | 1,566.5 |
| Jutiapa | 22 comunes sin IMERG_LATE | 1,084.2 | 1,313.1 | 1,302.5 | n/d | 1,253.2 |
| San Martín | 22 comunes sin IMERG_LATE | 1,100.7 | 1,224.5 | 1,158.3 | n/d | 1,398.6 |
| Chiquimula | 21 comunes sin IMERG (26) | 1,103.0 | n/d | 1,316.4 | 1,565.9 | 1,545.1 |
| Jutiapa | 21 comunes sin IMERG (26) | 1,097.8 | n/d | 1,309.2 | 1,507.9 | 1,256.7 |
| San Martín | 21 comunes sin IMERG (26) | 1,095.7 | n/d | 1,164.1 | 1,701.9 | 1,424.6 |
| Chiquimula | 20 comunes a los cinco | 1,110.3 | 1,139.6 | 1,317.9 | 1,574.5 | 1,551.0 |
| Jutiapa | 20 comunes a los cinco | 1,102.6 | 1,329.2 | 1,311.7 | 1,521.7 | 1,252.1 |
| San Martín | 20 comunes a los cinco | 1,103.3 | 1,239.4 | 1,164.6 | 1,724.2 | 1,409.3 |
| Chiquimula | todos los años completos de cada serie (24, 22, 24, 21, 24) | 1,094.9 | 1,164.1 | 1,297.4 | 1,565.9 | 1,543.5 |
| Jutiapa | todos los años completos de cada serie (24, 22, 24, 21, 24) | 1,092.9 | 1,313.1 | 1,313.0 | 1,507.9 | 1,250.4 |
| San Martín | todos los años completos de cada serie (24, 22, 24, 21, 24) | 1,101.6 | 1,224.5 | 1,154.5 | 1,701.9 | 1,413.4 |

En los 21 años comunes con ERA5, el conjunto 226 queda 42 % (Chiquimula), 37 % (Jutiapa) y 55 % (San Martín) por encima de ERA5, y 19 %, 15 % y 46 % por encima de CHIRPS. El servicio no explica esa diferencia y no se investigó su causa. Comprobación de orden de magnitud: el total de 2025 del conjunto 226 en Chiquimula con nuestro cuadro (±0.03° alrededor de 14.80, −89.54) es 2,389.0 mm (`web/data/rain_compare.json`, `pilots.chiquimula.sources.IMERG_LATE.coverage.calendarYearTotalMm`, suma de los 365 días con 1 decimal por día); el archivo del compañero (cuadro ±0.015° alrededor de 14.825, −89.5312) da 2,243.5 mm. El nuestro es 6.5 % mayor (145.5 mm sobre 2,243.5). Son puntos y cuadros distintos, así que esto solo muestra que ambos obtienen el mismo orden de magnitud, no que las cifras coincidan.

**Corrida Late, no Final.** El conjunto 226 es de la corrida Late de IMERG. La página de NASA sobre IMERG (https://gpm.nasa.gov/data/imerg, consultada el 15 de noviembre de 2026) indica que las corridas Early y Late sirven para aplicaciones de baja latencia y la Final para investigación cuando la latencia no importa; el directorio de datos de GPM (https://gpm.nasa.gov/data/directory) describe la Final como la que usa datos mensuales de pluviómetros. Esas páginas no dicen cuál corrida entrega ClimateSERV en cada conjunto: eso solo consta en la documentación de ClimateSERV citada arriba.

**Qué haría falta para usar el conjunto 226 en el entrenamiento (opción abierta para decidir; no se hizo).** (1) Descargar los otros 17 puntos: en la descarga de los 3 pilotos del 15 de noviembre de 2026 se hicieron 75 solicitudes con 8 trabajadores en paralelo en unos 10 minutos (observación de esa descarga, no reproducible desde el repositorio; ClimateSERV había respondido HTTP 503 con más trabajadores), lo que haría pensar en del orden de 1 hora para 17 puntos si el ritmo se mantuviera. (2) Los pilotos pierden los años agrícolas 2014, 2023 y 2024; no se sabe si los demás puntos tienen los mismos huecos, y sin rellenarlos el entrenamiento tendría como máximo 21 años (o habría que decidir cómo tratarlos). (3) Regenerar las entradas y etiquetas del emulador con esa lluvia, reentrenar las tres redes y volver a evaluar. (4) Decidir si se acepta una lluvia 15 % a 55 % más alta que la de ERA5 y CHIRPS en los pilotos (ver arriba) y una corrida Late en lugar de la Final. El modelo y el emulador siguen con ERA5.

## Decisiones con información previa

Nuestro modelo no decide nada por sí solo. Para poder compararlo con la red de política del equipo se le dio **una sola decisión**: cuántos días esperar, después del inicio de lluvias, para sembrar el maíz principal de la rotación actual (maíz, luego frijol el 1 de septiembre; sin riego; pendiente plana). Protocolo completo, formato de acciones y lo que no se puede decidir: `proyecto/comparacion-modelos.md`. Los números salen de `web/data/decision_eval.json` (`scripts/compare/sowing_policy.mjs`; reproducir en `scripts/compare/README.md`).

**Diseño, fijado antes de ver ningún número** (no se cambió después):

- 3 pilotos × años agrícolas 2019–2024 × 4 suelos = 72 casos: 54 con las clases `sand`, `loam` y `clay` y 18 con el suelo de SoilGrids del piloto (el simulador corre ese suelo; los emuladores reciben el `nearestTexture` del piloto, que es lo único que pueden recibir).
- Desfases posibles: 0, 5, 10, 15, 20, 25 y 30 días después de la regla de inicio. Los negativos no son acciones (necesitan saber cuándo llega la lluvia).
- **Regla de información:** la decisión para el año Y usa solo los años agrícolas anteriores a Y (de 18 años en 2019 a 23 en 2024). Una prueba cambia los datos de Y en adelante y la decisión no cambia.
- Se elige el desfase con mayor resumen del índice de agua de esos años pasados; prioridad **típica** = mediana, **cauta** = percentil 20; empate al desfase más cercano a 0.
- Tres políticas con la misma regla y distinto motor: **simulador** (corre el simulador en los años pasados: lo mejor que esta regla puede hacer), **red embudo** (`emulator_mlp.json`) y **ELM del navegador** (entrenada sin backpropagation con `emulator_train_subset.json`, 600 neuronas, escala 0.1, λ 0.1, semilla 42, igual que la página).
- **Línea base:** sembrar en el inicio de lluvias (desfase 0). **Oráculo:** el mejor desfase posible según el simulador en el propio año Y.
- Verdad para puntuar: el simulador con el suelo del caso. Se reporta el índice de agua de la rotación, el rendimiento relativo del maíz (0 si su ciclo no termina) y los días de traslape entre maíz y frijol.
- Revisión independiente: AquaCrop 3.1.0 solo en los 18 casos con suelo del piloto, solo maíz, con las mismas θFC y θWP, suelo seco al inicio y la fecha de siembra que da la regla de inicio más el desfase (126 temporadas).
- Tolerancia de 0.001 para ganar, empatar o perder el índice de agua y el rendimiento relativo del maíz (parte del diseño fijado).
- **Convenciones nuestras, no fijadas por el diseño** (se eligieron al programar, antes de correr): la misma tolerancia de 0.001 aplicada a los rendimientos de AquaCrop en t/ha; el porcentaje de AquaCrop es la **razón de medias** (ganancia media dividida entre el rendimiento medio de la línea base), no el promedio de porcentajes por caso; los desfases negativos de la retrospectiva (−20, −15, −10 y −5 días); y la tolerancia numérica de 1e-12 con la que dos resúmenes cuentan como empate al elegir el desfase.

**Suelos de clase (54 casos).** Línea base (desfase 0): índice medio 0.858, percentil 10 de 0.634, peor caso 0.454, maíz medio 0.868, traslape mediano 48 días. Oráculo: índice medio 0.931.

| Política | Prioridad | Índice medio elegido | Ganancia sobre la línea base | Gana / empata / pierde (de 54) | Arrepentimiento medio | Percentil 10 / peor caso | Ganancia del maíz | Maíz: gana / empata / pierde | Índice sube y maíz baja | Traslape mediano (días) |
|---|---|---|---|---|---|---|---|---|---|---|
| Simulador | típica | 0.916 | +0.058 | 37 / 8 / 9 | 0.015 | 0.729 / 0.508 | +0.080 | 25 / 16 / 13 | 5 | 75 |
| Simulador | cauta | 0.909 | +0.051 | 36 / 8 / 10 | 0.022 | 0.746 / 0.465 | +0.063 | 26 / 15 / 13 | 4 | 75 |
| Red embudo | típica | 0.913 | +0.055 | 32 / 15 / 7 | 0.017 | 0.751 / 0.508 | +0.077 | 22 / 22 / 10 | 4 | 75 |
| Red embudo | cauta | 0.910 | +0.052 | 35 / 11 / 8 | 0.021 | 0.737 / 0.485 | +0.070 | 23 / 17 / 14 | 7 | 75 |
| ELM navegador | típica | 0.912 | +0.054 | 36 / 10 / 8 | 0.019 | 0.751 / 0.533 | +0.076 | 26 / 15 / 13 | 4 | 75 |
| ELM navegador | cauta | 0.919 | +0.061 | 38 / 7 / 9 | 0.012 | 0.737 / 0.533 | +0.080 | 24 / 13 / 17 | 9 | 76 |

**Suelo del piloto (18 casos).** Línea base: índice medio 0.797, percentil 10 de 0.450, peor caso 0.311, maíz medio 0.758, traslape mediano 48 días. Oráculo: índice medio 0.900. La columna AquaCrop es la ganancia del rendimiento del maíz (t/ha y %), contra la siembra en el inicio de lluvias.

| Política | Prioridad | Índice medio elegido | Ganancia (simulador) | Gana / empata / pierde (de 18) | Arrepentimiento medio | Ganancia del maíz (simulador) | Maíz: gana / empata / pierde | AquaCrop: ganancia media | AquaCrop: gana / empata / pierde | Gana solo el simulador |
|---|---|---|---|---|---|---|---|---|---|---|
| Simulador | típica | 0.891 | +0.094 | 13 / 2 / 3 | 0.009 | +0.153 | 9 / 6 / 3 | −2.12 t/ha (−18.1 %) | 6 / 0 / 12 | 7 |
| Simulador | cauta | 0.890 | +0.093 | 13 / 2 / 3 | 0.010 | +0.149 | 10 / 5 / 3 | −2.23 t/ha (−19.0 %) | 5 / 0 / 13 | 7 |
| Red embudo | típica | 0.883 | +0.086 | 11 / 4 / 3 | 0.017 | +0.143 | 8 / 7 / 3 | −2.39 t/ha (−20.4 %) | 4 / 2 / 12 | 7 |
| Red embudo | cauta | 0.868 | +0.071 | 10 / 6 / 2 | 0.032 | +0.116 | 7 / 8 / 3 | −0.82 t/ha (−7.0 %) | 4 / 4 / 10 | 5 |
| ELM navegador | típica | 0.883 | +0.087 | 12 / 3 / 3 | 0.016 | +0.144 | 9 / 5 / 4 | −2.50 t/ha (−21.4 %) | 4 / 0 / 14 | 8 |
| ELM navegador | cauta | 0.891 | +0.094 | 13 / 2 / 3 | 0.009 | +0.150 | 9 / 5 / 4 | −2.37 t/ha (−20.2 %) | 5 / 0 / 13 | 7 |

(En los 18 casos, percentil 10 y peor caso del índice elegido: 0.681 / 0.458 en cinco de las seis filas y 0.645 / 0.397 en la red embudo cauta; los de la línea base están arriba. "Índice sube y maíz baja": 0 casos en cinco filas y 1 caso en la red embudo cauta y en la ELM cauta.)

**Qué muestra, en claro:**

1. **En el simulador, las tres políticas ganan a sembrar en el inicio de lluvias** en promedio (+0.05 a +0.06 con suelos de clase, +0.07 a +0.09 con el suelo del piloto) y quedan cerca del oráculo (arrepentimiento medio de 0.009 a 0.032). Pero ese resultado lo juzga el mismo simulador que eligió; no prueba nada sobre el campo.
2. **AquaCrop no lo confirma: lo contradice.** Con el suelo del piloto, las seis combinaciones pierden contra la línea base: de −0.82 a −2.50 t/ha (−7 % a −21 %), y ganan solo 4 a 6 de los 18 casos. Hay **5 a 8 "ganancias solo del simulador"** por política (en los 18 casos). Por piloto, la ganancia de AquaCrop es negativa en todos (de −0.09 a −5.73 t/ha; 6 casos por piloto).
3. **Casi todas las políticas eligen el borde de la rejilla.** Con la política simulador típica, 47 de los 72 casos eligen 30 días (el máximo permitido); la ELM cauta elige 30 días en los 72. Es probable que el mejor desfase del simulador esté más allá de 30, pero la rejilla no se amplió (el diseño estaba fijado de antemano). Una política así no "decide": reporta que el índice del simulador sube con el desfase.
4. **Las redes no superan a la política simulador, salvo por suerte.** El simulador es lo mejor que esta regla puede hacer con esos datos. La red embudo y la ELM coinciden con su desfase en 41 y 32 de 54 casos (típica) con suelos de clase, y en 18 y 13 de 54 (cauta). En la prioridad cauta con suelos de clase, la ELM saca una ganancia mayor (+0.061) que el propio simulador (+0.051); eso viene de elegir siempre 30, no de estimar mejor, y no se interpreta como mejora.
5. **El índice de rotación sube a veces mientras el maíz baja.** Con suelos de clase pasa en 4 a 9 de 54 casos según la política (por ejemplo, simulador típica: 5 casos, como `chiquimula_2022_sand` con +0.075 en el índice y −0.014 en el maíz). Con el suelo del piloto, en 0 o 1 de 18.
6. **Sembrar tarde hace que maíz y frijol compartan el campo:** el traslape mediano pasa de 48 días (línea base) a 74–76 días. El modelo no cobra ese costo (competencia por luz, agua y trabajo), así que parte de la "ganancia" del índice podría no existir en la realidad.
7. **Por piloto** (política típica; el índice cuenta los 24 casos de cada piloto, AquaCrop solo sus 6 casos con suelo del piloto):

   | Piloto | Simulador: ganancia, gana/empata/pierde | Red embudo | ELM | AquaCrop (6 casos): ganancia media, gana/empata/pierde, simulador / red embudo / ELM |
   |---|---|---|---|---|
   | Chiquimula | +0.087, 18 / 6 / 0 | +0.087, 18 / 6 / 0 | +0.083, 18 / 6 / 0 | −0.54, 1 / 0 / 5 en las tres |
   | Jutiapa | +0.088, 17 / 3 / 4 | +0.088, 17 / 3 / 4 | +0.088, 17 / 3 / 4 | −5.73, 2 / 0 / 4 en las tres |
   | San Martín | +0.027, 15 / 1 / 8 | +0.014, 8 / 10 / 6 | +0.016, 13 / 4 / 7 | −0.09 (3 / 0 / 3), −0.91 (1 / 2 / 3), −1.24 (1 / 0 / 5) |

**Dónde discrepan los dos modelos.** En los 18 casos con suelo del piloto, el promedio por desfase es:

| Desfase (días) | 0 | 5 | 10 | 15 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|
| Índice de agua (simulador) | 0.797 | 0.809 | 0.828 | 0.851 | 0.870 | 0.884 | 0.891 |
| Maíz, rendimiento relativo (simulador) | 0.758 | 0.772 | 0.797 | 0.836 | 0.867 | 0.892 | 0.908 |
| Maíz, rendimiento (AquaCrop, t/ha) | 11.72 | 10.95 | 11.20 | 11.48 | 11.42 | 11.01 | 9.35 |

Para el simulador, cuanto más tarde se siembra, mejor. Para AquaCrop, la siembra en el inicio y hasta 20 días después rinden parecido y a 30 días el rendimiento cae. Cuál de los dos se acerca más al campo no se puede saber aquí: AquaCrop corre con parámetros de cultivo sin calibrar. Lo que sí se sabe es que **una decisión que gana en el simulador no gana en AquaCrop**.

**Las "ganancias solo del simulador" de la política simulador típica** (maíz; relYield del simulador y rendimiento de AquaCrop en t/ha, en la línea base → con el desfase elegido):

| Caso | Desfase | Maíz, simulador | Maíz, AquaCrop (t/ha) |
|---|---|---|---|
| `chiquimula_2019_site` | 30 | 0.341 → 1.000 | 0.03 → 0.00 |
| `chiquimula_2020_site` | 30 | 0.999 → 1.000 | 14.73 → 13.04 |
| `chiquimula_2023_site` | 30 | 0.979 → 1.000 | 14.78 → 12.17 |
| `jutiapa_2019_site` | 30 | 0.050 → 0.506 | 5.79 → 0.00 |
| `jutiapa_2020_site` | 30 | 0.571 → 1.000 | 13.32 → 0.00 |
| `jutiapa_2024_site` | 30 | 0.849 → 0.928 | 14.86 → 5.01 |
| `sanmartin_2019_site` | 15 | 0.606 → 0.911 | 5.46 → 1.44 |

Las listas de las otras cinco combinaciones están en `decision_eval.json` (`aggregates.siteSoil.aquacrop.<política>.<prioridad>.simulatorOnlyWins`).

*Nota.* "Gana solo el simulador" sigue la definición exacta del diseño (ganancia del maíz en el simulador > 0 y ganancia de AquaCrop ≤ 0, sin tolerancia). Por eso `chiquimula_2020_site` cuenta aunque su ganancia en el simulador es de solo 0.0005 (0.999 → 1.000), que bajo la tolerancia de 0.001 sería un empate.

**Retrospectiva (solo informativa).** En 11 de los 72 casos el mejor desfase de todos, contando −20, −15, −10 y −5 días, fue negativo, y en ellos el índice supera al del oráculo factible en 0.034 en promedio (`aggregates.all.hindsightNegative`). Sembrar antes del inicio exige saber cuándo llegará la lluvia, así que no es una acción posible.

**Análisis posterior, no forma parte del diseño fijado: las temporadas de AquaCrop con rendimiento casi cero.** Las tablas de arriba no cambian. Esto se añadió después de ver los resultados, para saber cuánto pesan unas temporadas en que AquaCrop da 0 t/ha. Todo sale de `posthocAquacrop` en `decision_eval.json` (rendimiento menor de 0.01 t/ha cuenta como casi cero). AquaCrop se volvió a correr con los mismos casos y dio rendimientos y fechas de cosecha idénticos.

| Desfase (días) | 0 | 5 | 10 | 15 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|
| Temporadas con rendimiento < 0.01 t/ha (de 18) | 0 | 0 | 1 | 1 | 2 | 2 | 4 |
| Rendimiento medio (t/ha) | 11.72 | 10.95 | 11.20 | 11.48 | 11.42 | 11.01 | 9.35 |
| Rendimiento mediano (t/ha) | 13.11 | 12.41 | 13.56 | 14.05 | 13.39 | 13.52 | 12.64 |

Son 10 temporadas con rendimiento 0 en total:

| Piloto | Año | Desfase | Siembra | Cosecha de AquaCrop | Días de siembra a cosecha |
|---|---|---|---|---|---|
| Chiquimula | 2019 | 10 | 1 jun | 13 ago 2019 | 73 |
| Chiquimula | 2019 | 15 | 6 jun | 13 ago 2019 | 68 |
| Chiquimula | 2019 | 20 | 11 jun | 12 ago 2019 | 62 |
| Chiquimula | 2019 | 25 | 16 jun | 11 ago 2019 | 56 |
| Chiquimula | 2019 | 30 | 21 jun | 11 ago 2019 | 51 |
| Jutiapa | 2019 | 20 | 23 may | 22 jul 2019 | 60 |
| Jutiapa | 2019 | 25 | 28 may | 22 jul 2019 | 55 |
| Jutiapa | 2019 | 30 | 2 jun | 18 jul 2019 | 46 |
| Jutiapa | 2020 | 30 | 8 jun | 9 jul 2020 | 31 |
| San Martín | 2019 | 30 | 9 jun | 14 ago 2019 | 66 |

- **Qué muestran las salidas sobre esos ceros:** en las 10, la fecha de cosecha que da AquaCrop cae entre 31 y 73 días después de la siembra y mucho antes del fin de la ventana de la corrida (31 de marzo). En las otras 116 temporadas la cosecha cae entre 79 y 132 días después de la siembra (mediana 132). No es, por lo tanto, un corte por la longitud de la ventana de la temporada. Las salidas que guardamos (rendimiento y fecha de cosecha) **no dicen por qué** el cultivo termina tan pronto; no permiten distinguir una pérdida real por falta de agua de otro mecanismo interno de AquaCrop, y no lo investigamos más. Chiquimula 2019 da 0.028 t/ha con desfases de 0 y de 5 días, también casi nulo pero sobre el umbral.
- **Ganancias solo del simulador que descansan en un cero:** de 5 a 8 por fila, 2 a 4 tienen un rendimiento de AquaCrop menor de 0.01 t/ha con el desfase elegido (simulador típica 3 de 7, simulador cauta 3 de 7, red embudo típica 3 de 7, red embudo cauta 2 de 5, ELM típica 3 de 8, ELM cauta 4 de 7).
- **Ganancia de AquaCrop sin las temporadas con cero** (solo casos donde la línea base y el desfase elegido rinden ≥ 0.01 t/ha):

  | Política | Prioridad | Casos que quedan (de 18) | Ganancia media | Gana / empata / pierde | Gana solo el simulador |
  |---|---|---|---|---|---|
  | Simulador | típica | 15 | −1.27 t/ha (−9.9 %) | 6 / 0 / 9 | 4 |
  | Simulador | cauta | 15 | −1.40 t/ha (−10.9 %) | 5 / 0 / 10 | 4 |
  | Red embudo | típica | 15 | −1.60 t/ha (−12.5 %) | 4 / 2 / 9 | 4 |
  | Red embudo | cauta | 16 | −0.56 t/ha (−4.4 %) | 4 / 4 / 8 | 3 |
  | ELM navegador | típica | 15 | −1.73 t/ha (−13.5 %) | 4 / 0 / 11 | 5 |
  | ELM navegador | cauta | 14 | −1.29 t/ha (−9.7 %) | 5 / 0 / 9 | 3 |

- **Conclusión de este análisis:** la contradicción se debilita en tamaño (de −0.82 a −2.50 t/ha pasa a −0.56 a −1.73 t/ha), pero no desaparece. Sin los ceros, las seis filas siguen perdiendo en promedio contra la siembra en el inicio y ganan 4 a 6 de los 14 a 16 casos restantes. Siguen quedando 3 a 5 ganancias solo del simulador por fila.

**Límites de esta evaluación.**

- La muestra es pequeña: 18 casos con suelo del piloto, 54 con clases. Los 4 suelos de un mismo sitio y año comparten el mismo clima, así que los 72 casos **no son independientes**. Se dan los conteos y no se calcula significancia.
- Los emuladores se entrenaron con los años anteriores a 2019 de 16 de los 20 municipios (se dejaron fuera gualan, sanarate, asuncionmita y rabinal; `meta.emulators.municipalities` en `decision_eval.json`). Los 3 pilotos están entre los 16. La red embudo usó 2017–2018 solo para validar. Los años 2019–2024 no se usaron para entrenar ninguno de los dos. Con el suelo del piloto, el emulador solo recibe la textura más cercana (en Jutiapa, `sand`, aunque el suelo del piloto es una arcilla de agua disponible muy baja).
- Solo se decide un desfase de siembra y solo por agua: no hay precios, márgenes, plagas ni fertilización. Detalle en el protocolo.
- Tiempos: la evaluación de las políticas (72 casos, 3 políticas, 2 prioridades) tarda unos 5 s en Node, más 1 s para entrenar la ELM; AquaCrop tarda unos 30 s de reloj para las 126 temporadas.

## Limitaciones conocidas

- El modelo solo simula agua. No incluye plagas, fertilización, sombra, precios ni mano de obra.
- **Subsuelo corregido:** las raíces que crecen ya solo alcanzan el agua que la lluvia percoló hasta ahí (commit `4ea12c1`). Ya no "regala" agua.
- **Ky por etapa solo para maíz y frijol** (verificados en FAO-66 cap. 2 y en IAEA/FAO Water Reports 22). Sorgo, sandía y tomate usan el Ky estacional porque su Ky por etapa no se pudo verificar; ajonjolí y melón no tienen. La regla de multiplicar las fracciones de rendimiento de cada etapa está documentada en una fuente secundaria (ayuda de WEAP/SEI); no se pudo confirmar que sea la forma de Rao, Sarma y Chander (1988), así que no se cita como su fuente.
- **Lluvia:** el modelo usa ERA5 (Copernicus, por Open-Meteo). ClimateSERV ofrece dos conjuntos IMERG diarios y ninguno está completo en 2001–2024. **El conjunto 26** ("NASA-IMERG-V06-Late 1 Day" según la documentación de ClimateSERV) termina el 1 de junio de 2024 y le falta el 30 de junio de 2019, así que cubre 22 de los 24 años agrícolas (579 días faltantes de 2001–2025, `rain_compare.json`, `coverage.missingDays`). **El conjunto 226** ("NASA-IMERG-V07-Late 1 Day") llega hasta el 31 de diciembre de 2025, pero le faltan 40 días en los 3 pilotos (1–7 de junio de 2014, 31 de diciembre de 2023, 1 de enero de 2024 y mayo de 2024), así que cubre 21 de los 24 años agrícolas. Ninguno de los dos puede ser la única fuente sin rellenar huecos, y no se rellenó ninguno. El conjunto 226 solo se descargó en los 3 pilotos y es de la corrida Late, no de la Final. CHIRPS está completo, pero no se cambió de fuente. En los 3 pilotos ERA5 es el producto más seco: en los 21 años comunes con el conjunto 226, la lluvia media por año agrícola con ERA5 / CHIRPS / conjunto 226 es 1,103.0 / 1,316.4 / 1,565.9 mm en Chiquimula, 1,097.8 / 1,309.2 / 1,507.9 en Jutiapa y 1,095.7 / 1,164.1 / 1,701.9 en San Martín. En los 22 años comunes de las series anteriores (ERA5 / conjunto 26 / CHIRPS): Chiquimula 1,098.9 / 1,164.1 / 1,307.9; Jutiapa 1,084.2 / 1,313.1 / 1,302.5; San Martín 1,100.7 / 1,224.5 / 1,158.3. La lluvia de NASA POWER no se usa. Ver la sensibilidad a la lluvia arriba.
- **Suelo:** el simulador y el emulador usan 3 clases (arena, franco, arcilla). Los suelos de SoilGrids de los 3 pilotos solo entran en el simulador y en las pruebas de AquaCrop de arriba, no en el emulador. SoilGrids es una predicción global y necesita verificación local; en Jutiapa el agua disponible (0.056) es muy baja para una arcilla. `nearestTexture` se elige solo por el agua disponible y puede no coincidir con la clase más cercana en resultado (ver arriba).
- El número de curva del grupo hidrológico D con residuo es 85; la asignación de grupo según la textura es una aproximación.
- En cultivos traslapados (relevo) se usa el Kc mayor y la raíz mayor, sin competencia entre cultivos.
- Varios municipios comparten celda de clima. Salamá, Rabinal, Cubulco y San Martín Jilotepeque usan una celda a 1,516 m; los tres valles de Baja Verapaz están a unos 950 m.
- El índice de agua promedia los cultivos de comida de cada rotación, así que no es comparable entre rotaciones con cultivos distintos.
- Un cultivo que no termina su ciclo dentro del año agrícola cuenta como rendimiento 0.
- **Empeoró en la ronda del cambio del simulador:** el R² del índice de agua en años nuevos (todos los modelos) y el error de la diferencia "Proteger" en el índice de agua. **Empeoró con las entradas de agua antecedente:** el R² y el RMSE del suelo desnudo de las dos ELM; el R² del índice de agua de la ELM del navegador en municipios nuevos en años nuevos; varios errores y signos de la diferencia entre rotaciones en las tres redes (lista completa en Medidas ligadas a la decisión); y los costos (entrenamiento de la red embudo, preparación de entradas de punta a punta en las tres, tiempo por predicción de la ELM).
- **Meta no cumplida:** la ELM sigue bajo 0.8 en años nuevos (0.763 y 0.796). Las entradas nuevas se diseñaron después de conocer resultados de prueba anteriores; la evaluación de prueba final fue una sola.
- `storeProxy` usa un tope fijo de 150 mm para todo suelo: es un indicador sin suelo, no el balance del simulador.

## Cómo reproducir

```bash
npm test                                             # 221 pruebas (1 pendiente: la meta de R² de la ELM)
node scripts/emulator/fetch_points.mjs               # descarga clima de los 20 puntos (NASA POWER + ERA5); ya hecho, usa cachés
node scripts/emulator/generate.mjs                   # genera los 50,000 ejemplos (guarda commit, lluvia y fecha)
node scripts/emulator/build_screening_superset.mjs && python scripts/emulator/screen_features.py   # cribado en validación de las entradas de agua antecedente (sin filas de prueba)
python scripts/emulator/train_mlp.py --device cpu --out <tmp>/mlp_cpu.json                     # tiempo de CPU
python scripts/emulator/train_mlp.py --device cuda --cpu-timing <tmp>/mlp_cpu.json             # red embudo (pesos de esta corrida)
node --expose-gc scripts/emulator/evaluate.mjs       # barrido de la ELM y todas las métricas
# juez AquaCrop: ver scripts/referee/README.md
node scripts/referee/compare.mjs --aquacrop <resultados> --bundle web/data/snapshots/chiquimula.json --stage pre-subsoil=<d02febe> --stage subsoil=<4ea12c1> --stage stage-ky=<df4da88> --stage final=.
node scripts/referee/pilots.mjs prepare --dir <tmp>  # pilotos y sensibilidad a la lluvia (luego AquaCrop y `score`)
node scripts/compare/sowing_policy.mjs prepare --dir <tmp>   # decisiones con información previa (luego AquaCrop y `score`; ver scripts/compare/README.md)
python -m http.server 8765 -d web                    # abrir http://localhost:8765/emulator.html
```

## Propuesta para comparar con el otro modelo del equipo

Para saber cuál modelo es mejor, o si conviene alimentar uno con el otro, los dos deberían evaluarse igual (el protocolo detallado, el formato de acciones y el evaluador están en `proyecto/comparacion-modelos.md`; nuestra parte ya está medida en la sección "Decisiones con información previa"):

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
