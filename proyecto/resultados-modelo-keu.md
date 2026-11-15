# Resultados · modelo-keu (simulador FAO-56 + emulador)

Actualizado el 15 de noviembre de 2026 (Tarea 22: la temperatura de NASA POWER se lleva a la elevación de la parcela y todo lo derivado se regeneró: bundles, 50,000 ejemplos, las tres redes, el juez AquaCrop y las decisiones). Rama `modelo-keu`. Los números salen de `web/data/emulator_eval.json`, `web/data/emulator_mlp.json`, `web/data/grid_features.json`, `web/data/cycle_lengths.json`, `web/data/referee_aquacrop.json`, `web/data/decision_eval.json`, `scripts/data/site_elevation.json` y `scripts/emulator/feature_screening.json`, que se regeneran con los scripts de `scripts/`. Las columnas "antes" salen de la versión de esos mismos archivos en el commit `e5a3d49` (temperatura de la celda de NASA POWER sin corregir); las rondas anteriores (cribado de agua antecedente y cambio del simulador) ya no se repiten aquí y quedan en el historial de git (`88c879f`, `9d5b5f9`).

## Qué es este modelo

1. **Simulador** (`web/js/model/`, JavaScript sin dependencias): balance diario de agua en raíces FAO-56, ET₀ Penman-Monteith, etapas del cultivo por grados-día, respuesta del rendimiento al agua FAO-33 (Ky por etapa en maíz y frijol, Ky estacional en los demás) y rotaciones por año agrícola (abril–marzo). Clima: NASA POWER (temperatura, humedad, radiación, viento), con la temperatura, el punto de rocío y la presión llevados a la elevación de la parcela (sección "Temperatura a la elevación de la parcela"), y lluvia ERA5 de Copernicus tomada por Open-Meteo.
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

El código del modelo (`web/js/model/`) no cambió en la Tarea 22: lo que cambia es el clima que recibe (sección siguiente). Los archivos derivados se regeneraron con el clima corregido: 50,000 ejemplos y 27 entradas, y 3 salidas; el diseño de muestreo, las semillas, las divisiones, las capas ocultas 64→32→16→3, la receta de entrenamiento y la rejilla de la ELM son los mismos de la ronda de las entradas de agua antecedente.

## Temperatura a la elevación de la parcela (Tarea 22)

**Por qué.** Hasta el commit `e5a3d49` el simulador usaba la temperatura de la celda de NASA POWER (unos 0.5°) tal cual, y esa celda tiene la elevación **media de la celda**, no la de la parcela (Chiquimula: celda a 762 m, municipio a 403 m). Las etapas de cada cultivo se miden en grados-día (`días × (TREF − tbase)`, con `TREF = 26 °C`), así que una temperatura más fría que la real estiraba los ciclos. Con ese commit, franco, secano, 2001–2024: maíz 138.5 días en Chiquimula, 155.5 en Jutiapa y 205.5 en San Martín contra los ~120 días citados (ICTA); frijol 85 / 96.5 / 130 contra 64–70 (ICTA); ajonjolí 157.5 / 174 / 212 contra 110 (FAO-56 cuadro 11); y el maíz seguía en pie cuando se siembra el segundo cultivo el 1 de septiembre en 24 de 24 años en los tres pilotos.

**Corrección** (diseño fijado antes de ver ningún número; después de ver los resultados no se ajustó nada: ni el gradiente, ni `TREF`, ni las etapas):

- **Elevación de la parcela** de los 20 puntos: API de elevación de Open-Meteo (modelo digital Copernicus GLO-90, unos 90 m; Open-Meteo es un agregador de datos de Copernicus), una sola consulta que envía solo las coordenadas (`scripts/data/fetch_site_elevation.mjs`). Queda en `scripts/data/site_elevation.json` y como `siteElevation` y `siteElevationSource` en `scripts/emulator/points.json`. Es la elevación de un punto (la cabecera municipal), no la de un campo.
- **Temperatura:** `ΔT = −0.0065 °C/m × (z_parcela − z_celda)`, que se suma a `tmax` y `tmin` (gradiente estándar de la atmósfera, el que usa FAO-56; no es una calibración: ninguna constante se ajustó para que los ciclos salgan con su duración nominal). **Humedad relativa constante:** la presión de vapor real sale del punto de rocío de la celda, la humedad relativa se calcula contra la saturación a la temperatura media de la celda, y el punto de rocío de la parcela sale de esa misma humedad relativa a la temperatura media de la parcela. **Presión:** se escala con la fórmula barométrica de FAO-56 (cociente entre las dos elevaciones). Radiación, viento y lluvia no cambian.
- El bundle guarda `elevation` (la de la parcela, que es la que usa el ET₀ y la que recibe el emulador como entrada), `cellElevation` y `temperatureCorrection` (`lapseRate`, `deltaT`, `method`, `source`). `buildBundle` falla si el punto no trae elevación de la parcela: no hay valor de respaldo. La función es `correctToSiteElevation` en `web/js/data/climate.js`, con pruebas de ΔT calculado a mano, humedad relativa conservada, cociente de presiones, corrección cero con elevaciones iguales y error sin elevación.
- Lo demás no cambia: `TREF`, `tbase`, días por etapa, reglas de siembra, suelos y Ky. El emulador sigue con 27 entradas; **las dos entradas de agua antecedente se eligieron antes de esta corrección y el cribado no se repitió.**
- La página `emulator.html` solo lee los snapshots y los archivos de resultados; no baja clima en vivo, así que no hay una ruta de navegador que arme bundles. Sus textos y los tooltips del mapa se actualizaron (ver Limitaciones).

**Los 3 pilotos** (`web/data/cycle_lengths.json`, `scripts/data/cycle_lengths.mjs`; "antes" = commit `e5a3d49`; ΔT de cada piloto en su bundle):

| Piloto | Elevación celda → parcela | ΔT | Temperatura media mayo–agosto, antes → ahora |
|---|---|---|---|
| Chiquimula | 762 m → 403 m | +2.34 °C | 24.45 → 26.79 °C |
| Jutiapa | 1,040 m → 903 m | +0.89 °C | 23.03 → 23.92 °C |
| San Martín Jilotepeque | 1,516 m → 1,787 m | −1.76 °C | 20.37 → 18.61 °C |

En los 20 puntos, ΔT va de −2.19 °C (Olopa) a +3.95 °C (Gualán) (`grid_features.json`, `deltaT`).

**Duración del ciclo** (días de calendario, mediana de 24 años; entre paréntesis, mínimo–máximo; franco, secano, maíz sembrado al inicio de lluvias; frijol y ajonjolí como segundo cultivo el 1 de septiembre):

| Piloto | Cultivo | Citado | Antes | Ahora |
|---|---|---|---|---|
| Chiquimula | Maíz | ~120 | 138.5 (131–151) | **118** (112–124) |
| | Frijol | 64–70 | 85 (76–94) | **70** (66–77) |
| | Ajonjolí | 110 | 157.5 (142–180) | 124 (115–140) |
| Jutiapa | Maíz | ~120 | 155.5 (141–169) | 144 (132–154) |
| | Frijol | 64–70 | 96.5 (87–111) | 88 (80–98) |
| | Ajonjolí | 110 | 174 (156–198) | 159.5 (143–179) |
| San Martín | Maíz | ~120 | 205.5 (172–231) | **273** (215–309) |
| | Frijol | 64–70 | 130 (114–150) | **172.5** (144–198) |
| | Ajonjolí | 110 | 212 (205–213) | 212 (212–213) |

| Piloto | Años con el maíz aún en pie el 1 de septiembre (de 24) | Traslape mediano maíz–segundo cultivo (días) | Cosecha del ajonjolí (primera, mediana, última de 24 años) | Años con un ciclo incompleto (rotación con ajonjolí) |
|---|---|---|---|---|
| Chiquimula | 24 → **18** | 34.5 → 14 | 20 ene, 5 feb, 27 feb → 24 dic, 2 ene, 18 ene | 0 → 0 |
| Jutiapa | 24 → 24 | 51.5 → 40 | 3 feb, 22 feb, 17 mar → 21 ene, 7 feb, 26 feb | 0 → 0 |
| San Martín | 24 → 24 | 94.5 → **161** | 23 mar, 31 mar, 31 mar → 31 mar, 31 mar, 31 mar | 19 → **24** |

**Lo que mejoró y lo que no, sin adornos:**

- **Chiquimula** quedó en la duración citada para maíz (118 días contra ~120) y frijol (70, el borde de 64–70). El ajonjolí sigue 14 días largo (124 contra 110). El maíz todavía está en pie al sembrar el segundo cultivo en 18 de 24 años (antes 24 de 24), con un traslape mediano de 14 días (antes 34.5).
- **Jutiapa** mejoró pero **sigue lejos**: maíz 144 días (20 % sobre los ~120), frijol 88 (contra 64–70) y ajonjolí 159.5 (contra 110); el maíz sigue en pie en 24 de 24 años. La causa visible es que el municipio, a 903 m, es de verdad más fresco: su temperatura media de mayo a agosto es 23.9 °C, 2.1 °C bajo los 26 °C de `TREF`, y los días de cada etapa están calibrados para tierras bajas (ICTA, "ciclo ~120 d en tierras bajas").
- **San Martín Jilotepeque empeoró:** el municipio (1,787 m) está **271 m más alto** que la celda de POWER (1,516 m), así que la corrección lo enfría (−1.76 °C) en vez de calentarlo. El maíz tarda 273 días (antes 205.5), el frijol 172.5 (antes 130), el traslape llega a 161 días y la rotación con ajonjolí queda incompleta en los 24 años (antes 19). Es un efecto esperado, no un error de la corrección: a esa altura los ciclos de tierras bajas sí se alargan. Los días por etapa no se tocaron, así que para esas alturas el modelo sigue sin ser confiable (ver Limitaciones).

**Lo que sigue sin corregirse:** la lluvia (ERA5 por Open-Meteo, malla de 0.25°) y la radiación y el viento (POWER, unos 0.5°) siguen a escala de la celda (los municipios de una misma celda de POWER comparten radiación, viento y la humedad relativa de partida; solo Chiquimula y Jocotán tienen también la misma lluvia); el gradiente es fijo y no capta inversiones térmicas ni diferencias de ladera; la elevación de la parcela es la de un punto de un modelo de unos 90 m; el segundo cultivo se siembra siempre el 1 de septiembre (fecha fija, sin importar cuándo termina el maíz); y el traslape entre el maíz y el segundo cultivo se trata como relevo sin competencia por luz, agua ni trabajo.

**Efecto en el resto de los resultados** (detalle en las secciones siguientes): el emulador pierde algo en el índice de agua de años nuevos (red embudo 0.842 → 0.819) y gana en el agua en floración (0.876 → 0.897); el acuerdo con AquaCrop en Chiquimula sube (Spearman del maíz 0.851 → 0.886) pero **se pierde en San Martín** (0.51 → −0.09); y el patrón "sembrar más tarde es mejor" se mantiene en el simulador, más débil, y AquaCrop lo sigue contradiciendo.

## Datos y prueba

- 50,000 ejemplos generados con el simulador: 20 cabeceras municipales del Corredor Seco × años agrícolas 2001–2024 × 4 rotaciones × riego × textura × pendiente × desfase de siembra.
- Entrenamiento: 29,974 ejemplos. Prueba: 20,026 ejemplos (años 2019–2024, o 4 municipios dejados fuera).
- Los 4 municipios dejados fuera comparten celda de NASA POWER con municipios de entrenamiento, así que **la prueba más limpia es "años nuevos" (2019–2024)**.
- Validación para elegir configuraciones: años 2017–2018. Los datos de prueba nunca se usaron para elegir nada.
- Aviso: las entradas de floración (Tarea 13e) y las de agua antecedente (Tarea 19) se diseñaron **después de conocer resultados de prueba anteriores**; los modelos nunca se ajustaron con filas de prueba. Las de la Tarea 19 se eligieron con la validación (2017–2018) y la prueba se midió una sola vez, después de fijar la elección. **Esa elección se hizo antes de la corrección de temperatura de la Tarea 22 y no se repitió**: los resultados de más abajo usan las mismas 27 entradas.

## Entradas de agua antecedente

*Esta sección describe el cribado de la Tarea 19, hecho con el clima de la celda de NASA POWER sin corregir. No se repitió con la temperatura corregida (`feature_screening.json` no cambió); los R² citados aquí son los de ese momento, los vigentes están en la sección siguiente.*

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

Salidas: índice de agua / agua en floración del maíz (Ks) / suelo desnudo en época lluviosa. Mismas 27 entradas, mismos 50,000 ejemplos de diseño, semillas, divisiones y recetas; lo único que cambió son los datos (temperatura a la elevación de la parcela).

| Modelo | Todas las pruebas | Años nuevos 2019–2024 | Municipios nuevos |
|---|---|---|---|
| Red embudo (4,451 parámetros) | 0.888 / 0.931 / 0.982 | **0.819 / 0.897 / 0.984** | 0.924 / 0.938 / 0.979 |
| ELM, 1,500 neuronas (46,500 parámetros) | 0.832 / 0.892 / 0.963 | 0.739 / 0.826 / 0.961 | 0.881 / 0.910 / 0.964 |
| ELM del navegador, 600 neuronas | 0.753 / 0.821 / 0.918 | 0.687 / 0.719 / 0.930 | 0.797 / 0.846 / 0.900 |
| Línea base (promedio por manejo, sin clima) | 0.217 / 0.126 / 0.371 | 0.141 / 0.031 / 0.437 | 0.231 / 0.104 / 0.296 |

**Antes → después de la corrección térmica** (R² del emulador; antes = commit `e5a3d49`; índice de agua / agua en floración / suelo desnudo; en negritas lo que empeoró):

| Modelo | Años nuevos 2019–2024 | Todas las pruebas | Municipios nuevos |
|---|---|---|---|
| Red embudo | **0.842** / 0.876 / **0.986** → **0.819** / 0.897 / **0.984** | **0.896** / **0.934** / **0.989** → **0.888** / **0.931** / **0.982** | 0.916 / **0.948** / **0.992** → 0.924 / **0.938** / **0.979** |
| ELM, 1,500 neuronas | **0.763** / 0.796 / **0.968** → **0.739** / 0.826 / **0.961** | **0.841** / 0.886 / **0.974** → **0.832** / 0.892 / **0.963** | 0.876 / **0.912** / **0.982** → 0.881 / **0.910** / **0.964** |
| ELM del navegador | **0.711** / 0.698 / **0.952** → **0.687** / 0.719 / **0.930** | **0.780** / 0.818 / **0.961** → **0.753** / 0.821 / **0.918** | **0.808** / **0.854** / **0.971** → **0.797** / **0.846** / **0.900** |
| Línea base | 0.189 / 0.036 / 0.492 → 0.141 / 0.031 / 0.437 | 0.251 / 0.137 / 0.490 → 0.217 / 0.126 / 0.371 | 0.218 / 0.129 / 0.519 → 0.231 / 0.104 / 0.296 |

- **Empeoró:** el índice de agua en años nuevos en los tres modelos (red embudo 0.842 → 0.819, ELM 0.763 → 0.739, ELM del navegador 0.711 → 0.687) y el **suelo desnudo en todas las divisiones y en los tres modelos**, sobre todo en la ELM del navegador (años nuevos 0.952 → 0.930; municipios nuevos 0.971 → 0.900). La línea base también cae en suelo desnudo (municipios nuevos 0.519 → 0.296). No se midió la causa; una explicación probable, no comprobada, es que con la temperatura a la elevación de cada pueblo los municipios se diferencian más entre sí y las redes tienen más que aprender con los mismos ejemplos.
- **Mejoró:** el agua en floración en años nuevos en los tres modelos (red embudo 0.876 → 0.897, ELM 0.796 → 0.826, ELM del navegador 0.698 → 0.719) y la detección de estrés (siguiente sección).
- En municipios nuevos, la red embudo y la ELM casi no cambian en el índice de agua (0.916 → 0.924 y 0.876 → 0.881) y bajan un poco en el agua en floración (0.948 → 0.938 y 0.912 → 0.910).
- En la división de municipios nuevos en años nuevos (`testBoth`), índice de agua / agua en floración / suelo desnudo: red embudo 0.886 / 0.938 / 0.991 → 0.885 / 0.924 / 0.974; ELM 0.803 / 0.872 / 0.976 → 0.824 / 0.871 / 0.959; ELM del navegador 0.732 / 0.787 / 0.966 → 0.693 / 0.795 / 0.894.
- La ELM se eligió otra vez con el barrido en validación: 1,500 neuronas, escala 0.1 y λ 0.1 (el borde de la rejilla); la del navegador, 600 neuronas con los mismos valores. Con 5 semillas distintas la desviación del R² es 0.005 / 0.002 / 0.001 (antes 0.004 / 0.002 / 0.001).
- **Meta de R² > 0.8 en años nuevos para el índice de agua y el agua en floración** (la meta no se bajó ni se tocó la prueba):

  | Modelo | Índice de agua | Agua en floración | Estado |
  |---|---|---|---|
  | Red embudo | 0.819 (cumple) | 0.897 (cumple) | **Cumple las dos** (antes 0.842 y 0.876) |
  | ELM, 1,500 neuronas | 0.739 (no) | 0.826 (cumple) | **Cumple una de dos** (antes ninguna: 0.763 y 0.796) |
  | ELM del navegador (no entra en la prueba de la meta) | 0.687 (no) | 0.719 (no) | No cumple |

  La prueba `emulator_eval.test.mjs` sigue marcada como pendiente porque el índice de agua de la ELM (0.739) no llega a 0.8; la prueba de la meta no se tocó.

## Medidas ligadas a la decisión

- **Detectar estrés en floración** (Ks < 0.7), en años nuevos. El 1.82 % de los casos tiene estrés real (antes 1.74 %: el conjunto de prueba es el mismo, pero los valores del simulador cambiaron).

  | Modelo | F1 (antes, `e5a3d49`) | Precisión (antes → ahora) | Recuperación (antes → ahora) | F1 (ahora) |
  |---|---|---|---|---|
  | Red embudo | 0.80 | 0.80 → 0.83 | 0.79 → 0.86 | 0.85 |
  | ELM | 0.76 | 0.85 → 0.84 | 0.69 → 0.75 | 0.79 |
  | ELM del navegador | 0.71 | 0.84 → 0.88 | 0.61 → 0.66 | 0.75 |

  La detección de estrés mejora en los tres modelos (la precisión de la ELM baja una centésima).

- **Diferencia "alternativa menos rotación actual"** (años nuevos; error típico por municipio-año-manejo y porcentaje de casos con el signo correcto), antes (`e5a3d49`) → ahora:

  | Modelo | Alternativa | Índice de agua: error (puntos) | signo correcto | Suelo desnudo: error (días) | signo correcto |
  |---|---|---|---|---|---|
  | Red embudo | Proteger | ±5.9 → ±7.2 | 68 % → 69 % | ±2.4 → ±3.6 | 91 % → 92 % |
  | Red embudo | Extra (secano) | ±7.2 → ±7.4 | 91 % → 88 % | ±2.5 → ±3.0 | 95 % → 98 % |
  | Red embudo | Extra (riego) | ±7.2 → ±5.5 | 97 % → 96 % | ±2.1 → ±2.4 | 96 % → 97 % |
  | ELM | Proteger | ±7.0 → ±6.9 | 71 % → 65 % | ±2.8 → ±3.7 | 95 % → 98 % |
  | ELM | Extra (secano) | ±7.9 → ±8.0 | 91 % → 85 % | ±2.7 → ±3.3 | 95 % → 98 % |
  | ELM | Extra (riego) | ±7.0 → ±5.8 | 96 % → 92 % | ±2.7 → ±3.2 | 93 % → 97 % |
  | ELM del navegador | Proteger | ±7.3 → ±7.4 | 64 % → 56 % | ±3.7 → ±6.4 | 99 % → 99 % |
  | ELM del navegador | Extra (secano) | ±9.2 → ±9.0 | 87 % → 84 % | ±3.8 → ±5.4 | 99 % → 99 % |
  | ELM del navegador | Extra (riego) | ±7.3 → ±6.2 | 97 % → 94 % | ±3.6 → ±3.9 | 93 % → 99 % |

  - **Mejoró:** el error del índice de agua de "Extra (riego)" en los tres modelos (±7.2 → ±5.5, ±7.0 → ±5.8 y ±7.3 → ±6.2 puntos) y el signo del suelo desnudo (mejora en siete de las nueve filas y no cambia en dos).
  - **Empeoró:** el error del suelo desnudo en las nueve filas (por ejemplo, ELM del navegador "Proteger" ±3.7 → ±6.4 días); el error del índice de agua de "Proteger" en la red embudo (±5.9 → ±7.2); y el signo correcto del índice de agua en 8 de las 9 filas (por ejemplo, ELM "Extra (secano)" 91 % → 85 % y ELM del navegador "Proteger" 64 % → 56 %). El error de Ks de "Proteger" (RMSE) sube en la red embudo (0.0084 → 0.0101) y baja en la ELM (0.0090 → 0.0082).
- La diferencia de "Proteger" en el índice de agua sigue siendo la medida menos confiable del emulador: se equivoca de signo en 31 % de los casos con la red embudo (69 % correcto), 35 % con la ELM (65 %) y 44 % con la ELM del navegador (56 %).
- El agua en floración del maíz es idéntica entre rotaciones por construcción (el maíz es el mismo), así que no sirve para compararlas.

## Costo

| | Red embudo | ELM (1,500) |
|---|---|---|
| Tiempo de entrenamiento | 9.2 s en GPU (RTX 4050, CUDA) · 4.3 s en CPU | 48.6 s en JavaScript puro (no comparable) |
| Memoria de entrenamiento (calculada) | 0.35 MB | 17.6 MB |
| Tiempo por predicción | 9.6 µs | 56.5 µs |
| Velocidad frente al simulador (380 µs por año) | 40× por predicción, 7.3× de punta a punta | 6.7× por predicción, 3.5× de punta a punta |

- Antes (`e5a3d49`): 23.9 s GPU / 6.9 s CPU (48 épocas); ELM 45.4 s; 9.5 µs y 57.7 µs por predicción; simulador 394 µs por año; 42× y 6.8× por predicción, 7.7× y 3.3× de punta a punta. Los tiempos dependen de la máquina y de lo que estuviera corriendo, así que las diferencias pequeñas no son reales y los factores de velocidad no se pueden comparar con exactitud (la red embudo entrenó 38 épocas contra 48, y el tiempo de GPU de esa corrida no es comparable con el anterior). La preparación de entradas de punta a punta cuesta 51.8 µs por año con la red embudo (antes 51.5), 109.9 µs con la ELM (119.1) y 68.2 µs con la ELM del navegador (77.7). Parámetros (4,451 y 46,500) y memoria calculada (0.345 MB y 17.56 MB) no cambian.
- La GPU sigue siendo más lenta que la CPU para esta red tan pequeña. Los 4.3 s de CPU salen de una corrida aparte, con los mismos datos, cuyos pesos no se guardan.
- Para acercarse a la red embudo, la ELM necesita muchas más neuronas y unas 50 veces más memoria. Su ventaja es la sencillez: no usa backpropagation y la versión de 600 neuronas se entrena en el navegador en ~1 s.

## Juez independiente (AquaCrop)

AquaCrop-OSPy 3.1.0 en Chiquimula, mismo clima (ERA5 y la temperatura a 403 m del bundle actual: **AquaCrop recibe las mismas temperaturas corregidas y el mismo ET₀ que el simulador**) y suelo seco al inicio, 2001–2024. **Una sola corrida de AquaCrop** se compara con cuatro versiones del simulador, así que solo cambia el modelo. **Ojo con el suelo:** los casos con suelo por clase (franco, arena, arcilla) **no usan el mismo suelo** en los dos modelos: AquaCrop usa su propio perfil por defecto y el simulador el suyo (tabla siguiente). El 0.89 del titular compara el franco de cada modelo con el suyo; solo los casos con el suelo de SoilGrids dan los mismos θFC y θWP a los dos modelos. Maíz sembrado el 20 de mayo (`maiz_0520`) y frijol el 1 de septiembre (`frijol_0901`).

**Sobre la etapa "antes de la corrección de temperatura".** La corrección vive en la capa de datos (`web/js/data/climate.js`), no en `web/js/model/`: el código del simulador es idéntico en `e5a3d49` y ahora. Se probó agregar esa revisión como etapa sobre el clima nuevo y da exactamente los mismos resultados que `final` (casos y curva de siembra idénticos), así que no aporta nada y no está en el archivo. El "antes" de esta sección es el archivo `referee_aquacrop.json` del commit `e5a3d49` (clima de la celda sin corregir, con su propia corrida de AquaCrop), y el "ahora" es el archivo nuevo, con AquaCrop corrido otra vez sobre el clima corregido.

| Clase | AquaCrop (por defecto): θWP / θFC / θs, Ksat (mm/día) | Simulador: θWP / θFC |
|---|---|---|
| Franco | 0.15 / 0.31 / 0.46, 500 | 0.12 / 0.25 |
| Arena | 0.06 / 0.13 / 0.36, 3000 | 0.045 / 0.12 |
| Arcilla | 0.39 / 0.54 / 0.55, 35 | 0.22 / 0.36 |

Los perfiles de AquaCrop se leen del paquete `aquacrop` (`soilComparison` en `web/data/referee_aquacrop.json`), no se escribieron a mano. La arena es la clase más parecida entre los dos modelos; la arcilla es la menos comparable (en AquaCrop θs casi igual a θFC y Ksat muy baja).

Antes → ahora (CV de AquaCrop: maíz 0.40 → 0.45; frijol 0.35 → 0.41):

| Versión del simulador | Spearman maíz | Coincidencia en 5 peores (maíz) | CV maíz | Años en 1.0 (maíz) | Spearman frijol | CV frijol | Años en 1.0 (frijol) |
|---|---|---|---|---|---|---|---|
| `pre-subsoil` (d02febe) | 0.615 → 0.630 | 3 → 4 de 5 | 0.078 → 0.107 | 13 → 10 de 24 | 0.599 → 0.670 | 0.118 → 0.092 | 5 → 10 |
| `subsoil` (4ea12c1) | 0.856 → 0.897 | 3 → 4 de 5 | 0.111 → 0.149 | 9 → 7 de 24 | 0.599 → 0.670 | 0.118 → 0.092 | 5 → 10 |
| `stage-ky` (df4da88) | 0.851 → 0.886 | 3 → 3 de 5 | 0.250 → 0.251 | 9 → 7 de 24 | 0.635 → 0.653 | 0.204 → 0.146 | 5 → 10 |
| `final` (HEAD) | 0.851 → 0.886 | 3 → 3 de 5 | 0.250 → 0.251 | 9 → 7 de 24 | 0.635 → 0.653 | 0.204 → 0.146 | 5 → 10 |

Lugar de los años secos en el maíz, ahora (1 = el peor; entre paréntesis, el lugar en AquaCrop, que ahora es 3 / 1 / 11 / 2; antes 4 / 1 / 11 / 2):

| Versión | 2014 | 2015 | 2018 | 2019 |
|---|---|---|---|---|
| `pre-subsoil` | 2 (3) | 1 (1) | 3 (11) | 4 (2) |
| `subsoil` | 3 (3) | 1 (1) | 5 (11) | 2 (2) |
| `stage-ky` y `final` | 3 (3) | 1 (1) | 5 (11) | 2 (2) |

Frijol, lugar de 2014 / 2015 / 2018 / 2019 (AquaCrop: 19 / 20 / 11 / 21; antes 19 / 20 / 13 / 21): 15 / 8 / 14 / 15 en `pre-subsoil` y `subsoil`; 15 / 6 / 14 / 15 en `stage-ky` y `final` (antes 17 / 15 / 10 / 20 y 17 / 13 / 12 / 20).

- **Lo que mejoró:** con la temperatura corregida el acuerdo de rangos del maíz sube en las cuatro versiones (la versión final, 0.851 → 0.886) y sigue siendo alto en `subsoil` (0.897). El índice del simulador sigue sin ser plano (CV 0.25; AquaCrop 0.45) y los años exactamente en 1.0 bajan de 9 a 7 de 24.
- **Lo que no mejoró:** la coincidencia en los 5 peores años sigue en 3 de 5 en la versión final (AquaCrop: 2002, 2014, 2015, 2019, 2023; simulador: 2001, 2014, 2015, 2018, 2019; antes fallaba 2011 y 2023, ahora 2002 y 2023). En frijol el acuerdo sigue bajo (0.65). El índice del simulador sigue más plano que el de AquaCrop (0.25 contra 0.45 en maíz, 0.15 contra 0.41 en frijol).
- `final` y `stage-ky` dan lo mismo en maíz y frijol con suelo franco: la corrección del número de curva solo afecta a la clase `clay`.
- Con el suelo de SoilGrids de Chiquimula en los dos modelos (`maiz_0520_site`) el acuerdo es 0.885 (antes 0.888) y la coincidencia en los 5 peores años, 4 de 5 (igual que antes). Las versiones anteriores no aceptan un objeto de suelo, así que ese caso solo existe para `final`.

**Fecha de siembra (maíz, versión `final`).** Valor relativo mediano por fecha, antes → ahora. AquaCrop se mide contra su mejor rendimiento de todas las fechas y años; el simulador, contra el rendimiento sin estrés.

| Fecha | AquaCrop | Simulador (mediana) | Simulador (media) | Simulador (p10) |
|---|---|---|---|---|
| 1 may | 0.60 → 0.56 | 0.89 → 0.88 | 0.80 → 0.77 | 0.44 → 0.32 |
| 11 may | 0.76 → 0.75 | 0.95 → 0.92 | 0.84 → 0.82 | 0.57 → 0.49 |
| 21 may | 0.76 → 0.69 | 0.97 → 0.95 | 0.88 → 0.85 | 0.57 → 0.58 |
| 31 may | 0.86 → 0.86 | 1.00 → 0.99 | 0.91 → 0.88 | 0.69 → 0.64 |
| 10 jun | 0.90 → 0.88 | 1.00 → 1.00 | 0.95 → 0.91 | 0.83 → 0.74 |
| 20 jun | 0.94 → 0.90 | 1.00 → 1.00 | 0.97 → 0.95 | 0.98 → 0.83 |
| 30 jun | 0.79 → 0.75 | 1.00 → 1.00 | 0.99 → 0.97 | 0.95 → 0.98 |
| 10 jul | 0.82 → 0.79 | 1.00 → 1.00 | 0.98 → 0.99 | 0.92 → 0.97 |

Los dos siguen coincidiendo en que sembrar el 1 de mayo es lo peor y en que de mediados de junio en adelante es mejor. La mejor fecha de AquaCrop sigue siendo el 20 de junio; en el simulador es una meseta (0.99 el 31 de mayo y 1.00 desde el 10 de junio). El simulador sigue sin ver la pérdida que AquaCrop da al sembrar el 30 de junio (0.75) o después.

AquaCrop usa parámetros de cultivo sin calibrar para Guatemala: mide si la lógica coincide, no la verdad de campo. La prueba con DSSAT (CERES-Maize) del reporte anterior se hizo fuera del repo con la versión anterior del simulador y no se repitió, así que ya no se cita.

### Los 3 pilotos con el modelo final

Maíz sembrado el 20 de mayo, 2001–2024, clima propio de cada piloto (ERA5 y la temperatura corregida de cada uno), tres suelos: franco (el de cada modelo, **no** el mismo), el suelo de SoilGrids del piloto (**la única comparación con el mismo suelo**: mismos θFC y θWP en los dos modelos, CN del piloto en el simulador) y la clase `nearestTexture` del piloto (la de cada modelo, tampoco es el mismo suelo), que es lo que recibiría el emulador. Antes → ahora:

| Piloto | Suelo | Spearman | Coincidencia 5 peores | CV AquaCrop / simulador (ahora) | Años en 1.0 |
|---|---|---|---|---|---|
| Chiquimula | franco | 0.851 → 0.886 | 3 → 3 | 0.45 / 0.25 | 9 → 7 |
| | SoilGrids | 0.888 → 0.885 | 4 → 4 | 0.44 / 0.27 | 9 → 7 |
| | `nearestTexture` = arcilla (*) | −0.051 → −0.080 | 3 → 3 | 1.11 / 0.27 | 9 → 7 |
| Jutiapa | franco | 0.879 → 0.860 | 4 → 4 | 0.48 / 0.36 | 8 → 6 |
| | SoilGrids | 0.792 → 0.819 | 3 → 4 | 0.58 / 0.85 | 0 → 1 |
| | `nearestTexture` = arena (*) | 0.716 → 0.805 | 3 → 3 | 0.40 / 0.70 | 2 → 3 |
| San Martín | franco | 0.514 → **−0.091** | 3 → **1** | 0.21 / 0.12 | 5 → 1 |
| | SoilGrids | 0.550 → **−0.144** | 3 → **0** | 0.22 / 0.12 | 5 → 1 |
| | `nearestTexture` = franco | 0.514 → **−0.091** | 3 → **1** | 0.21 / 0.12 | 5 → 1 |

En los 3 pilotos ningún ciclo de maíz quedó incompleto en el simulador (franco ni suelo del piloto) y AquaCrop dio rendimiento en todos los años.

**San Martín perdió el acuerdo con AquaCrop.** El Spearman pasó de 0.51–0.55 a valores negativos (−0.09 con franco, −0.14 con el suelo del piloto) y la coincidencia de los 5 peores años, de 3 a 1 (franco) y 0 (SoilGrids). En el franco, el simulador ve como peores años 2001, 2004, 2008, 2010 y 2012; AquaCrop, 2004, 2016, 2018, 2019 y 2024. Es el piloto en el que la temperatura cambió en sentido contrario (−1.76 °C a 1,787 m) y donde el ciclo del maíz del simulador pasó de 205.5 a 273 días de mediana. No se investigó la causa: una explicación probable, no medida, es que con un ciclo tan largo el simulador mide la sequía en otra ventana de la temporada que AquaCrop, que usa su propio calendario de cultivo. Con lo medido, a esta altura los dos modelos ya no coinciden y no hay nada con lo que verificar la corrección en San Martín.

(*) Todas las filas con suelo por clase (franco, arena, arcilla) comparan el perfil de AquaCrop con el del simulador, que son distintos (tabla de suelos arriba). La fila de arcilla es la menos comparable: en AquaCrop la arcilla tiene θs casi igual a θFC y Ksat muy baja, y por eso el CV de AquaCrop en Chiquimula llega a 1.11; no se debe leer como un fallo del simulador. Con el suelo de SoilGrids (mismos θFC y θWP) la comparación sí es del mismo suelo: Chiquimula 0.885, Jutiapa 0.819, San Martín −0.144.

**Suelos de los pilotos (SoilGrids, 0–100 cm).** Son una predicción global, no una medición de campo, y **necesitan verificación local**. No cambian con la corrección de temperatura.

| Piloto | θFC | θWP | Agua disponible | CN (cultivo / residuo / desnudo) | `nearestTexture` |
|---|---|---|---|---|---|
| Chiquimula (franco arcilloso) | 0.330 | 0.180 | 0.150 | 89 / 85 / 94 | arcilla |
| Jutiapa (arcilla) | 0.359 | 0.304 | 0.056 | 89 / 85 / 94 | arena |
| San Martín (franco arcilloso) | 0.342 | 0.211 | 0.131 | 89 / 85 / 94 | franco |

`nearestTexture` (en `scripts/emulator/points.json`) se elige **solo por el agua disponible** (θFC − θWP) y no mira la escorrentía. Por eso puede no coincidir con la clase más cercana en el resultado del simulador. Jutiapa es una arcilla del grupo hidrológico D (CN 89/85/94) pero queda como `arena` (CN 67/64/77); Chiquimula, un franco arcilloso, queda como `arcilla`. Error medido: diferencia absoluta media del `relYield` entre el suelo del sitio y cada clase (maíz 20 de mayo, 2001–2024, mismo clima, con la temperatura corregida; antes → ahora donde cambió):

| Piloto | arena | franco | arcilla | Clase más cercana en resultado | ¿Es `nearestTexture`? |
|---|---|---|---|---|---|
| Chiquimula | 0.141 → 0.145 | 0.039 → 0.040 | 0.013 → 0.014 | arcilla | sí |
| Jutiapa | 0.096 → 0.102 | 0.329 → 0.348 | 0.354 → 0.372 | arena | sí |
| San Martín | 0.123 → 0.115 | 0.006 → 0.002 | 0.020 → 0.014 | franco | sí |

En estos 3 pilotos `nearestTexture` sí es la clase más cercana en resultado, pero eso no está garantizado en otro punto, porque la regla no mira la escorrentía. El error que hereda el emulador por tener solo 3 clases de suelo es de 0.014 (Chiquimula), 0.102 (Jutiapa) y 0.002 (San Martín) en `relYield`. El de Jutiapa es grande: su agua disponible es muy baja (0.056) y ninguna de las tres clases se le parece (las otras dos quedan a más de 0.34).

### Sensibilidad a la lluvia (Chiquimula)

**Nombres de las series IMERG.** ClimateSERV ofrece dos conjuntos de datos IMERG diarios. En la página de documentación de ClimateSERV (https://climateserv2.servirglobal.net/develop-api, "List of Datatypes", consultada el 15 de noviembre de 2026) el conjunto **26** se llama "NASA-IMERG-V06-Late 1 Day" y el **226**, "NASA-IMERG-V07-Late 1 Day". Las respuestas de datos de la API traen solo el número del conjunto, no el nombre. Aquí `IMERG` es el conjunto 26 (el de las rondas anteriores) e `IMERG_LATE` es el conjunto 226. El conjunto 226 se probó porque la auditoría de un compañero (`auditorias/prueba frijol maiz 2025` en `origin/main`) obtuvo con él los 365 días de 2025.

Maíz el 20 de mayo, franco de cada modelo (no es el mismo suelo; ver la tabla de suelos), modelo final, con cada producto de lluvia en el simulador **y** en AquaCrop, **con la temperatura corregida** (las series de lluvia y sus medias no cambian; los Spearman, CV y años en 1.0 sí, y se muestran antes → ahora donde cambian). Primera comparación: los tres productos originales (ERA5, IMERG conjunto 26, CHIRPS), solo los 22 años agrícolas completos en los tres (se excluyen 2019 y 2024, donde el conjunto 26 tiene huecos; no se rellenó ningún hueco). POWER no se usa nunca como lluvia. El modelo sigue usando ERA5: esto mide una brecha de información, no elige un producto.

| Producto | Lluvia media (mm por año agrícola) | Spearman simulador vs AquaCrop | Coincidencia 5 peores | CV del simulador | Años en 1.0 |
|---|---|---|---|---|---|
| ERA5 | 1,098.9 | 0.846 → 0.886 | 3 | 0.24 | 9 → 7 |
| IMERG (conjunto 26) | 1,164.1 | 0.602 → 0.633 | 4 | 0.21 → 0.22 | 6 → 5 |
| CHIRPS | 1,307.9 | 0.632 → 0.652 | 2 | 0.07 → 0.09 | 14 → 11 |

Acuerdo entre productos:

| Par | Spearman del simulador | Coincidencia 5 peores del simulador | Diferencia media de `relYield` | Spearman de AquaCrop |
|---|---|---|---|---|
| ERA5–IMERG (26) | 0.633 → 0.522 | 3 | 0.099 → 0.122 | 0.673 → 0.705 |
| ERA5–CHIRPS | 0.658 → 0.657 | 3 | 0.087 → 0.095 | 0.735 → 0.770 |
| IMERG (26)–CHIRPS | 0.831 → 0.813 | 3 → 4 | 0.096 → 0.095 | 0.791 → 0.860 |

**Con el conjunto 226 (cuatro productos).** El conjunto 226 tampoco está completo: faltan 40 días (`rain_compare.json`, `coverage.missingDays`), los mismos en los 3 pilotos (del 1 al 7 de junio de 2014, el 31 de diciembre de 2023, el 1 de enero de 2024 y todo mayo de 2024), y por eso quedan fuera los años agrícolas 2014, 2023 y 2024. Los años agrícolas completos en los cuatro productos son 20 (2001–2013, 2015–2018 y 2020–2022); no se rellenó ningún hueco.

| Producto | Lluvia media (mm por año agrícola) | Spearman simulador vs AquaCrop | Coincidencia 5 peores | CV del simulador | Años en 1.0 |
|---|---|---|---|---|---|
| ERA5 | 1,110.3 | 0.834 → 0.877 | 3 | 0.22 → 0.24 | 9 → 7 |
| IMERG (26) | 1,139.6 | 0.609 → 0.638 | 3 | 0.19 → 0.21 | 5 → 4 |
| CHIRPS | 1,317.9 | 0.693 → 0.677 | 3 | 0.06 → 0.08 | 13 → 10 |
| IMERG_LATE (226) | 1,574.5 | 0.843 → 0.777 | 4 | 0.06 → 0.09 | 10 → 9 |

| Par | Spearman del simulador | Coincidencia 5 peores del simulador | Diferencia media de `relYield` | Spearman de AquaCrop |
|---|---|---|---|---|
| ERA5–IMERG (26) | 0.672 → 0.543 | 2 | 0.105 → 0.127 | 0.683 → 0.701 |
| ERA5–CHIRPS | 0.659 → 0.634 | 2 | 0.076 → 0.090 | 0.678 → 0.720 |
| ERA5–IMERG_LATE | 0.753 → 0.768 | 3 | 0.074 → 0.092 | 0.681 → 0.713 |
| IMERG (26)–CHIRPS | 0.813 → 0.831 | 4 | 0.090 → 0.096 | 0.806 → 0.878 |
| IMERG (26)–IMERG_LATE | 0.677 → 0.836 | 3 | 0.087 → 0.090 | 0.881 → 0.889 |
| CHIRPS–IMERG_LATE | 0.747 → 0.850 | 4 → 3 | 0.020 | 0.832 → 0.877 |

Con la lluvia del conjunto 226 el CV del simulador es 0.09 (con ERA5, 0.24), parecido al de CHIRPS (0.08), así que su Spearman de 0.777 se calcula sobre diferencias pequeñas de `relYield`. Este documento no establece por qué el CV es bajo con esas dos series.

**Solo los productos completos, los 24 años (2001–2024).** Solo ERA5 y CHIRPS no tienen ningún día faltante en los 24 años agrícolas; ninguna de las dos series IMERG es completa, así que no entran aquí.

| Producto | Lluvia media (mm por año agrícola) | Spearman simulador vs AquaCrop | Coincidencia 5 peores | CV del simulador | Años en 1.0 |
|---|---|---|---|---|---|
| ERA5 | 1,094.9 | 0.851 → 0.886 | 3 | 0.25 | 9 → 7 |
| CHIRPS | 1,297.4 | 0.625 → 0.656 | 1 | 0.07 → 0.09 | 14 → 11 |

Par ERA5–CHIRPS en los 24 años: Spearman del simulador 0.692 → 0.688, coincidencia de los 5 peores 4, diferencia media de `relYield` 0.101 → 0.107, Spearman de AquaCrop 0.693 → 0.735.

Con otro producto de lluvia el orden de los años del simulador cambia mucho (Spearman entre productos de 0.52 a 0.81 en los 22 años y de 0.54 a 0.85 en los 20) y AquaCrop se mueve parecido: la elección de la lluvia pesa tanto como los cambios de modelo de esta ronda. Que ERA5 concuerde mejor con AquaCrop no prueba que ERA5 esté más cerca de la realidad: en cada fila los dos modelos reciben la misma lluvia.

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

(La lluvia no cambió con la corrección térmica; los totales y porcentajes siguientes son los de antes.) En los 21 años comunes con ERA5, el conjunto 226 queda 42 % (Chiquimula), 37 % (Jutiapa) y 55 % (San Martín) por encima de ERA5, y 19 %, 15 % y 46 % por encima de CHIRPS. El servicio no explica esa diferencia y no se investigó su causa. Comprobación de orden de magnitud: el total de 2025 del conjunto 226 en Chiquimula con nuestro cuadro (±0.03° alrededor de 14.80, −89.54) es 2,389.0 mm (`web/data/rain_compare.json`, `pilots.chiquimula.sources.IMERG_LATE.coverage.calendarYearTotalMm`, suma de los 365 días con 1 decimal por día); el archivo del compañero (cuadro ±0.015° alrededor de 14.825, −89.5312) da 2,243.5 mm. El nuestro es 6.5 % mayor (145.5 mm sobre 2,243.5). Son puntos y cuadros distintos, así que esto solo muestra que ambos obtienen el mismo orden de magnitud, no que las cifras coincidan.

**Corrida Late, no Final.** El conjunto 226 es de la corrida Late de IMERG. La página de NASA sobre IMERG (https://gpm.nasa.gov/data/imerg, consultada el 15 de noviembre de 2026) indica que las corridas Early y Late sirven para aplicaciones de baja latencia y la Final para investigación cuando la latencia no importa; el directorio de datos de GPM (https://gpm.nasa.gov/data/directory) describe la Final como la que usa datos mensuales de pluviómetros. Esas páginas no dicen cuál corrida entrega ClimateSERV en cada conjunto: eso solo consta en la documentación de ClimateSERV citada arriba.

**Qué haría falta para usar el conjunto 226 en el entrenamiento (opción abierta para decidir; no se hizo).** (1) Descargar los otros 17 puntos: en la descarga de los 3 pilotos del 15 de noviembre de 2026 se hicieron 75 solicitudes con 8 trabajadores en paralelo en unos 10 minutos (observación de esa descarga, no reproducible desde el repositorio; ClimateSERV había respondido HTTP 503 con más trabajadores), lo que haría pensar en del orden de 1 hora para 17 puntos si el ritmo se mantuviera. (2) Los pilotos pierden los años agrícolas 2014, 2023 y 2024; no se sabe si los demás puntos tienen los mismos huecos, y sin rellenarlos el entrenamiento tendría como máximo 21 años (o habría que decidir cómo tratarlos). (3) Regenerar las entradas y etiquetas del emulador con esa lluvia, reentrenar las tres redes y volver a evaluar. (4) Decidir si se acepta una lluvia 15 % a 55 % más alta que la de ERA5 y CHIRPS en los pilotos (ver arriba) y una corrida Late en lugar de la Final. El modelo y el emulador siguen con ERA5.

## Decisiones con información previa

Nuestro modelo no decide nada por sí solo. Para poder compararlo con la red de política del equipo se le dio **una sola decisión**: cuántos días esperar, después del inicio de lluvias, para sembrar el maíz principal de la rotación actual (maíz, luego frijol el 1 de septiembre; sin riego; pendiente plana). Protocolo completo, formato de acciones y lo que no se puede decidir: `proyecto/comparacion-modelos.md`. Los números salen de `web/data/decision_eval.json` (`scripts/compare/sowing_policy.mjs`; reproducir en `scripts/compare/README.md`). **Todo esto se volvió a correr con la temperatura a la elevación de la parcela, con el mismo diseño fijo** (incluido el análisis posterior de los ceros de AquaCrop); "antes" es el archivo del commit `e5a3d49`.

**Diseño, fijado antes de ver ningún número** (no se cambió después):

- 3 pilotos × años agrícolas 2019–2024 × 4 suelos = 72 casos: 54 con las clases `sand`, `loam` y `clay` y 18 con el suelo de SoilGrids del piloto (el simulador corre ese suelo; los emuladores reciben el `nearestTexture` del piloto, que es lo único que pueden recibir).
- Desfases posibles: 0, 5, 10, 15, 20, 25 y 30 días después de la regla de inicio. Los negativos no son acciones (necesitan saber cuándo llega la lluvia).
- **Regla de información:** la decisión para el año Y usa solo los años agrícolas anteriores a Y (de 18 años en 2019 a 23 en 2024). Una prueba cambia los datos de Y en adelante y la decisión no cambia.
- Se elige el desfase con mayor resumen del índice de agua de esos años pasados; prioridad **típica** = mediana, **cauta** = percentil 20; empate al desfase más cercano a 0.
- Tres políticas con la misma regla y distinto motor: **simulador** (corre el simulador en los años pasados: lo mejor que esta regla puede hacer), **red embudo** (`emulator_mlp.json`) y **ELM del navegador** (entrenada sin backpropagation con `emulator_train_subset.json`, 600 neuronas, escala 0.1, λ 0.1, semilla 42, igual que la página).
- **Línea base:** sembrar en el inicio de lluvias (desfase 0). **Oráculo:** el mejor desfase posible según el simulador en el propio año Y.
- Verdad para puntuar: el simulador con el suelo del caso. Se reporta el índice de agua de la rotación, el rendimiento relativo del maíz (0 si su ciclo no termina) y los días de traslape entre maíz y frijol.
- Revisión independiente: AquaCrop 3.1.0 solo en los 18 casos con suelo del piloto, solo maíz, con las mismas θFC y θWP, suelo seco al inicio y la fecha de siembra que da la regla de inicio más el desfase (126 temporadas), con el mismo clima corregido que el simulador.
- Tolerancia de 0.001 para ganar, empatar o perder el índice de agua y el rendimiento relativo del maíz (parte del diseño fijado).
- **Convenciones nuestras, no fijadas por el diseño** (se eligieron al programar, antes de correr): la misma tolerancia de 0.001 aplicada a los rendimientos de AquaCrop en t/ha; el porcentaje de AquaCrop es la **razón de medias** (ganancia media dividida entre el rendimiento medio de la línea base), no el promedio de porcentajes por caso; los desfases negativos de la retrospectiva (−20, −15, −10 y −5 días); y la tolerancia numérica de 1e-12 con la que dos resúmenes cuentan como empate al elegir el desfase.

**Suelos de clase (54 casos).** Línea base (desfase 0): índice medio 0.831 (antes 0.858), percentil 10 de 0.612 (0.634), peor caso 0.462 (0.454), maíz medio 0.873 (0.868), traslape mediano 32 días (48). Oráculo: índice medio 0.874 (0.931).

| Política | Prioridad | Índice medio elegido | Ganancia sobre la línea base | Gana / empata / pierde (de 54) | Arrepentimiento medio | Percentil 10 / peor caso | Ganancia del maíz | Maíz: gana / empata / pierde | Índice sube y maíz baja | Traslape mediano (días) |
|---|---|---|---|---|---|---|---|---|---|---|
| Simulador | típica | 0.869 | +0.038 | 29 / 19 / 6 | 0.005 | 0.621 / 0.445 | +0.047 | 25 / 23 / 6 | 0 | 64.5 |
| Simulador | cauta | 0.869 | +0.039 | 28 / 24 / 2 | 0.004 | 0.620 / 0.462 | +0.047 | 24 / 28 / 2 | 0 | 64.5 |
| Red embudo | típica | 0.865 | +0.034 | 27 / 22 / 5 | 0.009 | 0.620 / 0.455 | +0.038 | 23 / 26 / 5 | 0 | 64 |
| Red embudo | cauta | 0.863 | +0.032 | 25 / 25 / 4 | 0.011 | 0.618 / 0.462 | +0.040 | 21 / 29 / 4 | 0 | 64 |
| ELM navegador | típica | 0.868 | +0.037 | 29 / 15 / 10 | 0.005 | 0.610 / 0.445 | +0.045 | 25 / 17 / 12 | 1 | 64 |
| ELM navegador | cauta | 0.853 | +0.022 | 27 / 21 / 6 | 0.021 | 0.613 / 0.462 | +0.023 | 22 / 23 / 9 | 3 | 63 |

(Antes, ganancia sobre la línea base +0.051 a +0.061 y arrepentimiento 0.012 a 0.022; ahora +0.022 a +0.039 y 0.004 a 0.021.)

**Suelo del piloto (18 casos).** Línea base: índice medio 0.767 (antes 0.797), percentil 10 de 0.487 (0.450), peor caso 0.355 (0.311), maíz medio 0.754 (0.758), traslape mediano 32 días (48). Oráculo: índice medio 0.847 (0.900). La columna AquaCrop es la ganancia del rendimiento del maíz (t/ha y %), contra la siembra en el inicio de lluvias.

| Política | Prioridad | Índice medio elegido | Ganancia (simulador) | Gana / empata / pierde (de 18) | Arrepentimiento medio | Ganancia del maíz (simulador) | Maíz: gana / empata / pierde | AquaCrop: ganancia media | AquaCrop: gana / empata / pierde | Gana solo el simulador |
|---|---|---|---|---|---|---|---|---|---|---|
| Simulador | típica | 0.843 | +0.076 | 9 / 7 / 2 | 0.003 | +0.118 | 9 / 6 / 3 | −2.09 t/ha (−18.1 %) | 4 / 5 / 9 | 6 |
| Simulador | cauta | 0.844 | +0.077 | 8 / 9 / 1 | 0.003 | +0.121 | 9 / 8 / 1 | −2.04 t/ha (−17.7 %) | 3 / 7 / 8 | 6 |
| Red embudo | típica | 0.828 | +0.061 | 7 / 9 / 2 | 0.019 | +0.091 | 8 / 8 / 2 | −1.24 t/ha (−10.7 %) | 4 / 7 / 7 | 4 |
| Red embudo | cauta | 0.845 | +0.078 | 9 / 8 / 1 | 0.002 | +0.123 | 10 / 7 / 1 | −2.32 t/ha (−20.1 %) | 3 / 6 / 9 | 7 |
| ELM navegador | típica | 0.844 | +0.077 | 8 / 9 / 1 | 0.003 | +0.121 | 9 / 8 / 1 | −2.04 t/ha (−17.7 %) | 3 / 7 / 8 | 6 |
| ELM navegador | cauta | 0.826 | +0.059 | 9 / 8 / 1 | 0.021 | +0.095 | 8 / 8 / 2 | −1.92 t/ha (−16.7 %) | 6 / 6 / 6 | 5 |

(En los 18 casos, percentil 10 y peor caso del índice elegido: 0.588 / 0.390 en cinco de las seis filas y 0.548 / 0.360 en la red embudo típica; los de la línea base están arriba. "Índice sube y maíz baja": 0 casos en cuatro filas y 1 caso en el simulador típica y en la ELM cauta.)

**Qué muestra, en claro:**

1. **En el simulador, las tres políticas siguen ganando a sembrar en el inicio de lluvias** en promedio, pero menos que antes: +0.02 a +0.04 con suelos de clase (antes +0.05 a +0.06) y +0.06 a +0.08 con el suelo del piloto (antes +0.07 a +0.09); quedan cerca del oráculo (arrepentimiento medio de 0.002 a 0.021; antes 0.009 a 0.032). Pero ese resultado lo juzga el mismo simulador que eligió; no prueba nada sobre el campo.
2. **El patrón "sembrar más tarde es mejor" no desaparece, pero se debilita:** con el suelo del piloto, el índice medio del simulador pasa de 0.797 (siembra en el inicio) a 0.891 con 30 días de espera antes de la corrección y de 0.767 a 0.820 ahora; el rendimiento relativo del maíz, de 0.758 a 0.908 antes y de 0.754 a 0.823 ahora. Con desfases de 0 a 10 días ahora la curva es casi plana (0.767, 0.764, 0.768).
3. **AquaCrop sigue sin confirmarlo: lo contradice igual.** Con el suelo del piloto, las seis combinaciones pierden contra la línea base: de −1.24 a −2.32 t/ha (−10.7 % a −20.1 %; antes −0.82 a −2.50), y ganan solo 3 a 6 de los 18 casos (antes 4 a 6). Hay **4 a 7 "ganancias solo del simulador"** por política (antes 5 a 8). Por piloto, la ganancia de AquaCrop es negativa en Chiquimula y Jutiapa (de −0.38 a −5.53 t/ha) y nula en San Martín (de −0.15 a 0.00; casi todos empates).
4. **Hay menos políticas pegadas al borde de la rejilla, pero muchas siguen en 30 días.** Con 72 casos, la política simulador típica elige 30 días en 44 (antes 47) y la cauta en 47 (antes 19); la red embudo en 26 y 38 (antes 47 y 32); la ELM en 42 y 28 (antes 43 y 72). Es probable que el mejor desfase del simulador esté más allá de 30 en parte de los casos, pero la rejilla no se amplió (el diseño estaba fijado de antemano).
5. **Las redes no superan a la política simulador, salvo por ruido.** El simulador es lo mejor que esta regla puede hacer con esos datos. La red embudo y la ELM coinciden con su desfase en 35 y 36 de 54 casos con suelos de clase (típica) y en 42 y 34 de 54 (cauta); antes 41 y 32, y 18 y 13. Con el suelo del piloto la red embudo cauta saca +0.078 contra +0.077 del simulador cauta: una diferencia de 0.001 que no se interpreta como mejora.
6. **El índice de rotación sube a veces mientras el maíz baja,** pero mucho menos: 0 a 3 de 54 casos con suelos de clase según la política (antes 4 a 9) y 0 o 1 de 18 con el suelo del piloto.
7. **Sembrar tarde hace que maíz y frijol compartan el campo:** el traslape mediano pasa de 32 días (línea base; antes 48) a 61–64.5 días con las políticas (antes 74–76). El modelo no cobra ese costo (competencia por luz, agua y trabajo), así que parte de la "ganancia" del índice podría no existir en la realidad. Que la línea base ahora traslape menos es justo el efecto de la corrección: en Chiquimula el maíz termina antes de la siembra del segundo cultivo en 6 de 24 años.
8. **Por piloto** (política típica; el índice cuenta los 24 casos de cada piloto, AquaCrop solo sus 6 casos con suelo del piloto):

   | Piloto | Simulador: ganancia, gana/empata/pierde | Red embudo | ELM | AquaCrop (6 casos): ganancia media, gana/empata/pierde, simulador / red embudo / ELM |
   |---|---|---|---|---|
   | Chiquimula | +0.079, 15 / 9 / 0 | +0.068, 15 / 9 / 0 | +0.074, 14 / 10 / 0 | −0.59 (1 / 1 / 4), −0.38 (1 / 1 / 4), −0.59 (1 / 1 / 4) |
   | Jutiapa | +0.067, 22 / 0 / 2 | +0.054, 18 / 0 / 6 | +0.072, 22 / 0 / 2 | −5.53 (2 / 0 / 4), −3.33 (3 / 0 / 3), −5.53 (2 / 0 / 4) |
   | San Martín | −0.003, 1 / 17 / 6 | −0.000, 1 / 22 / 1 | −0.004, 1 / 14 / 9 | −0.15 (1 / 4 / 1), 0.00 (0 / 6 / 0), 0.00 (0 / 6 / 0) |

   En San Martín el desfase casi no cambia el índice del simulador (ganancia media entre −0.004 y 0.000, casi todo empates): a 1,787 m el maíz del simulador tarda 273 días y la decisión de sembrar antes o después ya no mueve el resultado; no hay nada que decidir con este modelo ahí.

**Dónde discrepan los dos modelos.** En los 18 casos con suelo del piloto, el promedio por desfase es:

| Desfase (días) | 0 | 5 | 10 | 15 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|
| Índice de agua (simulador) | 0.767 | 0.764 | 0.768 | 0.777 | 0.788 | 0.804 | 0.820 |
| Maíz, rendimiento relativo (simulador) | 0.754 | 0.751 | 0.754 | 0.768 | 0.778 | 0.799 | 0.823 |
| Maíz, rendimiento (AquaCrop, t/ha) | 11.55 | 10.75 | 10.86 | 11.16 | 11.11 | 10.76 | 9.08 |

Para el simulador, cuanto más tarde se siembra, mejor (menos que antes). Para AquaCrop, la siembra en el inicio es lo mejor y a 30 días el rendimiento cae (antes la curva era parecida: 11.72 a 9.35 t/ha). Cuál de los dos se acerca más al campo no se puede saber aquí: AquaCrop corre con parámetros de cultivo sin calibrar. Lo que sí se sabe es que **una decisión que gana en el simulador sigue sin ganar en AquaCrop**: la contradicción con AquaCrop no cambió con la corrección de temperatura.

**Las "ganancias solo del simulador" de la política simulador típica** (maíz; relYield del simulador y rendimiento de AquaCrop en t/ha, en la línea base → con el desfase elegido):

| Caso | Desfase | Maíz, simulador | Maíz, AquaCrop (t/ha) |
|---|---|---|---|
| `chiquimula_2019_site` | 30 | 0.402 → 0.974 | 0.00 → 0.00 |
| `chiquimula_2020_site` | 30 | 0.999 → 1.000 | 14.72 → 12.99 |
| `chiquimula_2023_site` | 30 | 0.983 → 1.000 | 14.77 → 12.02 |
| `jutiapa_2019_site` | 30 | 0.066 → 0.264 | 4.60 → 0.00 |
| `jutiapa_2020_site` | 30 | 0.460 → 1.000 | 12.98 → 0.00 |
| `jutiapa_2024_site` | 30 | 0.701 → 0.947 | 14.87 → 4.96 |

Las listas de las otras cinco combinaciones están en `decision_eval.json` (`aggregates.siteSoil.aquacrop.<política>.<prioridad>.simulatorOnlyWins`).

*Nota.* "Gana solo el simulador" sigue la definición exacta del diseño (ganancia del maíz en el simulador > 0 y ganancia de AquaCrop ≤ 0, sin tolerancia). Por eso `chiquimula_2020_site` cuenta aunque su ganancia en el simulador es de solo 0.0005 (0.999 → 1.000), que bajo la tolerancia de 0.001 sería un empate.

**Retrospectiva (solo informativa).** En 25 de los 72 casos el mejor desfase de todos, contando −20, −15, −10 y −5 días, fue negativo (antes 11), y en ellos el índice supera al del oráculo factible en 0.056 en promedio (antes 0.034; `aggregates.all.hindsightNegative`). Sembrar antes del inicio exige saber cuándo llegará la lluvia, así que no es una acción posible.

**Análisis posterior, no forma parte del diseño fijado: las temporadas de AquaCrop con rendimiento casi cero.** Las tablas de arriba no cambian. Esto se añadió después de ver los resultados de la ronda anterior, para saber cuánto pesan unas temporadas en que AquaCrop da 0 t/ha, y se repitió igual con el clima corregido. Todo sale de `posthocAquacrop` en `decision_eval.json` (rendimiento menor de 0.01 t/ha cuenta como casi cero).

| Desfase (días) | 0 | 5 | 10 | 15 | 20 | 25 | 30 |
|---|---|---|---|---|---|---|---|
| Temporadas con rendimiento < 0.01 t/ha (de 18) | 1 | 1 | 1 | 1 | 2 | 2 | 5 |
| Rendimiento medio (t/ha) | 11.55 | 10.75 | 10.86 | 11.16 | 11.11 | 10.76 | 9.08 |
| Rendimiento mediano (t/ha) | 12.88 | 12.05 | 13.10 | 13.41 | 12.99 | 13.26 | 12.20 |

Son 13 temporadas con rendimiento casi nulo en total (antes 10):

| Piloto | Año | Desfase | Siembra | Cosecha de AquaCrop | Días de siembra a cosecha | Rendimiento (t/ha) |
|---|---|---|---|---|---|---|
| Chiquimula | 2019 | 0 | 22 may | 12 ago 2019 | 82 | 0 |
| Chiquimula | 2019 | 5 | 27 may | 12 ago 2019 | 77 | 0 |
| Chiquimula | 2019 | 10 | 1 jun | 11 ago 2019 | 71 | 0 |
| Chiquimula | 2019 | 15 | 6 jun | 11 ago 2019 | 66 | 0 |
| Chiquimula | 2019 | 20 | 11 jun | 11 ago 2019 | 61 | 0 |
| Chiquimula | 2019 | 25 | 16 jun | 10 ago 2019 | 55 | 0 |
| Chiquimula | 2019 | 30 | 21 jun | 10 ago 2019 | 50 | 0 |
| Jutiapa | 2019 | 20 | 23 may | 21 jul 2019 | 59 | 0 |
| Jutiapa | 2019 | 25 | 28 may | 21 jul 2019 | 54 | 0 |
| Jutiapa | 2019 | 30 | 2 jun | 17 jul 2019 | 45 | 0 |
| Jutiapa | 2020 | 30 | 8 jun | 8 jul 2020 | 30 | 0 |
| Jutiapa | 2023 | 30 | 29 jun | 8 nov 2023 | 132 | 0.005 |
| San Martín | 2019 | 30 | 9 jun | 17 ago 2019 | 69 | 0 |

- **Qué muestran las salidas sobre esos ceros:** en 12 de las 13 la cosecha de AquaCrop cae entre 30 y 82 días después de la siembra, mucho antes del fin de la ventana de la corrida (31 de marzo); la otra (Jutiapa 2023, desfase 30) corrió sus 132 días y dio 0.005 t/ha. En las otras 113 temporadas la cosecha cae siempre a los 132 días de la siembra. Las salidas que guardamos (rendimiento y fecha de cosecha) **no dicen por qué** el cultivo termina tan pronto; no permiten distinguir una pérdida real por falta de agua de otro mecanismo interno de AquaCrop, y no lo investigamos más. Con el clima corregido, Chiquimula 2019 ya da 0 t/ha también con desfases de 0 y de 5 días (antes 0.028 t/ha, apenas sobre el umbral).
- **Ganancias solo del simulador que descansan en un cero:** de 4 a 7 por fila, 1 a 3 tienen un rendimiento de AquaCrop menor de 0.01 t/ha con el desfase elegido (simulador típica 3 de 6, simulador cauta 3 de 6, red embudo típica 1 de 4, red embudo cauta 3 de 7, ELM típica 3 de 6, ELM cauta 3 de 5).
- **Ganancia de AquaCrop sin las temporadas con cero** (solo casos donde la línea base y el desfase elegido rinden ≥ 0.01 t/ha):

  | Política | Prioridad | Casos que quedan (de 18) | Ganancia media | Gana / empata / pierde | Gana solo el simulador |
  |---|---|---|---|---|---|
  | Simulador | típica | 14 | −0.65 t/ha (−5.0 %) | 4 / 4 / 6 | 3 |
  | Simulador | cauta | 14 | −0.58 t/ha (−4.5 %) | 3 / 6 / 5 | 3 |
  | Red embudo | típica | 15 | −0.44 t/ha (−3.5 %) | 4 / 6 / 5 | 3 |
  | Red embudo | cauta | 14 | −0.95 t/ha (−7.4 %) | 3 / 5 / 6 | 4 |
  | ELM navegador | típica | 14 | −0.58 t/ha (−4.5 %) | 3 / 6 / 5 | 3 |
  | ELM navegador | cauta | 14 | −0.43 t/ha (−3.4 %) | 6 / 5 / 3 | 2 |

- **Conclusión de este análisis:** la contradicción se debilita en tamaño (de −1.24 a −2.32 t/ha pasa a −0.43 a −0.95 t/ha), pero no desaparece. Sin los ceros, las seis filas siguen perdiendo en promedio contra la siembra en el inicio (la ELM cauta es la que más se acerca: gana 6 y pierde 3 de 14, con −0.43 t/ha de media). Siguen quedando 2 a 4 ganancias solo del simulador por fila.

**Límites de esta evaluación.**

- La muestra es pequeña: 18 casos con suelo del piloto, 54 con clases. Los 4 suelos de un mismo sitio y año comparten el mismo clima, así que los 72 casos **no son independientes**. Se dan los conteos y no se calcula significancia.
- Los emuladores se entrenaron con los años anteriores a 2019 de 16 de los 20 municipios (se dejaron fuera gualan, sanarate, asuncionmita y rabinal; `meta.emulators.municipalities` en `decision_eval.json`). Los 3 pilotos están entre los 16. La red embudo usó 2017–2018 solo para validar. Los años 2019–2024 no se usaron para entrenar ninguno de los dos. Con el suelo del piloto, el emulador solo recibe la textura más cercana (en Jutiapa, `sand`, aunque el suelo del piloto es una arcilla de agua disponible muy baja).
- Solo se decide un desfase de siembra y solo por agua: no hay precios, márgenes, plagas ni fertilización. Detalle en el protocolo.
- En San Martín (1,787 m) el modelo ya no distingue entre desfases (ver la tabla por piloto), así que la política no aporta nada ahí.
- Tiempos: la evaluación de las políticas (72 casos, 3 políticas, 2 prioridades) tarda unos 5 s en Node, más 1 s para entrenar la ELM; AquaCrop tarda unos 13 s de reloj para las 126 temporadas en esta corrida.

## Siete cultivos y matriz de sucesiones (Tarea 23)

**Qué se hizo.** El equipo (Carlos) publicó en `main` auditorías de siete cultivos (maíz, frijol, ajonjolí, papa, cebolla, brócoli, lechuga) y de las 42 sucesiones entre ellos, con parámetros FAO-56 por cultivo (`auditorias/combinaciones pendientes 7 cultivos 2025/datos/cultivos/parametros_auditados.json`, commit `a0d0690`). Con eso agregamos al simulador los cuatro cultivos que faltaban y corrimos las 42 sucesiones con nuestro simulador y 24 años. Es un **cribado de agua y calendario, no una recomendación**: sin precios, plagas, adaptación al calor ni mercado. **El emulador no se reentrenó**: sus cuatro rotaciones no cambian y no conoce estos cultivos (no hubo tiempo antes de la evaluación de hoy). Los archivos existentes (`emulator_*.json`, `grid_features.json`, `referee_aquacrop.json`, `decision_eval.json`, `cycle_lengths.json`, snapshots) no cambiaron, y una prueba comprueba que las cuatro rotaciones dan los mismos resultados anuales con 8 o con 12 cultivos en el catálogo.

### Los cuatro cultivos nuevos (`web/data/crops.json`)

| | Papa | Cebolla | Brócoli | Lechuga |
|---|---|---|---|---|
| Etapas ini/dev/mid/late (días) | 25/30/30/30 = 115 | 15/25/70/40 = 150 | 35/45/40/15 = 135 | 20/30/15/10 = 75 |
| Kc ini / mid / end | 0.5 / 1.15 / 0.75 | 0.7 / 1.05 / 0.75 | 0.7 / 1.05 / 0.95 | 0.7 / 1.0 / 0.95 |
| Raíz máxima (m) / p | 0.5 / 0.35 | 0.5 / 0.30 | 0.5 / 0.45 | 0.4 / 0.30 |
| Ky estacional | 1.1 (FAO-56 cuadro 24) | 1.1 (FAO-56 cuadro 24) | 0.95, **proxy** (Ky de la col) | 1.0, **proxy** |
| tbase | 5 °C, **proxy** | 5 °C, **proxy** | 5 °C, **proxy** | 5 °C, **proxy** |
| Familia | Solanaceae | Amaryllidaceae | Brassicaceae | Asteraceae |

- **Fuente de Kc, raíz, p y etapas:** FAO-56 cuadros 11, 12 y 22, con los valores del archivo auditado del equipo (ruta y commit `a0d0690` en `sources`). Se usó el ciclo de referencia FAO de cada cultivo, no las variantes prorrateadas de sensibilidad. Para el brócoli el archivo marca los 75 y 90 días como prorrateados y los 135 días como la referencia FAO, así que usamos 135; **la corrida de referencia del equipo usa 90**, no es el mismo ciclo.
- **Ky (FAO-33):** papa 1.1 y cebolla 1.1 se leyeron en FAO-56 cuadro 24 (https://www.fao.org/4/x0490e/x0490e0e.htm). Brócoli y lechuga **no están** en esa tabla. El brócoli usa el Ky de la col (0.95, misma especie) y la lechuga usa 1.0 (rendimiento proporcional al agua, igual que el ajonjolí); ambos figuran en `proxy: ['ky', 'tbase']` con el motivo en `sources.ky`. No encontramos una fuente legible de Ky de lechuga. `kyStages` es `null` en los cuatro.
- **tbase:** el modelo la necesita para los grados-día y **no tiene fuente legible** (FAO-56 no da temperatura base y el archivo del equipo tampoco): 5 °C es un supuesto para hortalizas de clima templado, rotulado como proxy en los cuatro. No se presenta como verificado.
- **`needsIrrigation: true` y `harvestRainSensitive: true`:** el archivo del equipo no los indica; se tomó el valor más conservador y se anotó en `sources`. `econ` es `null` (sin costos MAGA para estos cultivos).
- `scripts/compare/score_actions.mjs` ya acepta los cuatro en acciones de un solo cultivo (prueba incluida).

### La matriz (`web/data/succession_matrix.json`)

Generada con `node scripts/compare/succession_matrix.mjs` (sin red ni AquaCrop). Para cada una de las 42 parejas ordenadas A→B, en los tres pilotos, años agrícolas 2001–2024 (24), secano, pendiente plana y dos suelos (el de SoilGrids del piloto y franco): A se siembra con la regla de inicio de lluvias; B el día siguiente a la cosecha simulada de A más 14 días (el intervalo de referencia del equipo), sin relevo ni traslape. Los ciclos son los de grados-día del propio simulador. Por pareja, piloto y suelo el archivo guarda: años en que caben los dos ciclos (de 24), ciclo mediano de A y de B, fechas medianas de siembra y cosecha, `relYield` (mediana, percentil 10 y peor año; un ciclo incompleto cuenta 0), déficit de ET (ETc − ETa, en mm, como la métrica del equipo) y temperatura máxima media del ciclo. Los ciclos, fechas, déficits y temperaturas son medianas solo de los años en que cabe la sucesión.

**Cuántas de las 42 caben (dos ciclos completos en al menos 20 de 24 años), suelo de SoilGrids; con franco sale igual:**

| Piloto | Caben | No caben |
|---|---:|---:|
| Chiquimula | 40 de 42 | 2 |
| Jutiapa | 27 de 42 | 15 |
| San Martín | 2 de 42 | 40 |

- **Chiquimula.** No caben cebolla→brócoli (15 de 24 años) y brócoli→cebolla (14 de 24). Arriba, ordenadas por el menor de los dos `relYield` medianos: frijol→ajonjolí 0.961, frijol→lechuga 0.960, frijol→maíz 0.948, lechuga→frijol 0.922, lechuga→ajonjolí 0.921. Abajo: cebolla→frijol 0.321, cebolla→maíz 0.301 (21 de 24 años) y cebolla→papa 0.258 (23 de 24). En esas el segundo cultivo se siembra ya tarde, tras el ciclo largo de la cebolla (mediana de 148 a 166.5 días según la pareja).
- **Jutiapa.** Arriba: lechuga→frijol 0.683, frijol→lechuga 0.647, frijol→ajonjolí 0.507. Abajo, con mínimo 0: brócoli→frijol, cebolla→frijol y papa→maíz (22 de 24 años). Los ciclos son más largos (maíz 139 a 163 días, cebolla 169 a 186.5).
- **San Martín.** Solo caben frijol→lechuga (24 de 24 años, pero la lechuga tiene `relYield` mediano 0.372) y lechuga→frijol (21 de 24, `relYield` del frijol 0.066). En las otras el segundo cultivo ya no cabe en el año agrícola. Los ciclos de papa y de frijol son de 167 a 193.5 y de 116.5 a 169 días según la pareja: es el piloto frío.

**Comparación con las direcciones del equipo (Chiquimula, suelo SoilGrids).** Para las 21 parejas leímos de sus archivos de resultados el déficit de ET de la corrida de referencia en cada orden (2025, IMERG, secano, escorrentía 15%, intervalo 14 días; maíz↔frijol, maíz↔ajonjolí, papa↔cebolla y brócoli↔lechuga usan el calendario de referencia de su propia carpeta) y vimos qué orden tiene el menor déficit. De nuestro lado contamos los años en que cada orden tiene el menor déficit total (suma de los dos cultivos), entre los años en que caben ambos órdenes, y el mayor `relYield` medio de la pareja. **Coinciden 7 de 21 en el déficit y 7 de 21 en el `relYield`**; en dos parejas (frijol↔papa y frijol↔lechuga) nuestros conteos empatan 12 a 12. No es una prueba de error de ninguno de los dos: él evalúa un solo año (2025) con duraciones fijas de cada cultivo (maíz 90, frijol 70, ajonjolí 110, papa 115, cebolla 150, brócoli 90, lechuga 75 días) y calendarios que empiezan el 1 de marzo (época seca) en 19 de las 21 parejas (maíz↔ajonjolí empieza el 15 de mayo y maíz↔frijol el 1 de junio), y nosotros 24 años con ciclos por grados-día, siembra con el inicio de lluvias (mayo–junio) y un balance distinto, así que miden cosas distintas. Está en `comparison` del JSON, pareja por pareja.

### Límites, dichos sin rodeos

- **Los cuatro cultivos nuevos son hortalizas de estación fresca y el modelo no tiene respuesta al calor ni al fotoperíodo.** La temperatura máxima media durante el ciclo (mediana de los años en que cabe), solo de las sucesiones que caben en al menos 20 de 24 años y con el suelo de SoilGrids, va de 27.1 a 30.3 °C en Chiquimula, de 25.9 a 27.9 °C en Jutiapa y de 21.2 a 22.4 °C en San Martín (donde solo caben dos sucesiones). Por cultivo, Chiquimula y Jutiapa: papa 27.5–29.8 y 26.1–27.5; cebolla 28–29.8 y 26.6–27.1; brócoli 27.7–29.8 y 26.3–27.2; lechuga 27.1–30.2 y 25.9–27.8. El modelo solo usa la temperatura para alargar o acortar las etapas; no baja el rendimiento por calor, bulbificación, espigado ni fotoperíodo. Un `relYield` alto en este cribado **no** dice que el cultivo se adapte.
- El propio índice del equipo advierte que cobertura de evaluación no equivale a rotaciones aprobadas y que la adaptación de variedad, la sanidad y la viabilidad comercial deben validarse localmente.
- **No se corrió AquaCrop para estos cultivos**: ningún número de esta sección tiene juez independiente. El emulador no los conoce.
- **Una sola variante de etapas por cultivo** (la de referencia FAO); no se probó la sensibilidad a la duración.
- `tbase` de los cuatro y Ky de brócoli y lechuga son proxies (arriba); los resultados dependen de ellos.
- Intervalo fijo de 14 días entre cultivos; sin almácigo, curado, retiro ni traslape.
- La comparación con el equipo es de direcciones (un orden contra el otro) y no de valores: sus déficits son de un año y no son nuestros.

## Modelo v2: siete cultivos y decisión tras perder la cosecha

**Qué se hizo.** Un segundo emulador (v2) que sí conoce los siete cultivos (maíz, frijol, ajonjolí, papa, cebolla, brócoli, lechuga) en sucesiones A→B, donde B puede ser ninguno, y una prueba de decisión: qué hacer con el campo cuando el maíz se pierde. **El modelo que muestra la página sigue siendo el v1**; el v2 no está conectado a la página. Archivos nuevos: `web/js/model/emulatorV2.js`, `scripts/emulator/generate_v2.mjs`, `train_mlp_v2.py`, `evaluate_v2.mjs`, `scripts/compare/loss_decision.mjs` (más `loss_decision_lib.mjs`), y los resultados `web/data/emulator_v2_eval.json`, `emulator_v2_mlp.json` y `decision_loss_eval.json`. Los archivos del v1 no cambiaron.

### El emulador v2

**Datos.** Muestras de nuestro simulador por el mismo código de la matriz de sucesiones: los 20 puntos, años 2001–2024, A en los 7 cultivos sembrado en el inicio de lluvias más 0, 15 o 30 días, B en los otros 6 o ninguno, suelo arena, franco o arcilla, plano y sin riego. Hay 211,680 combinaciones; se conservaron 60,000 por reservorio determinista (`mulberry32(42)`). Prueba = años 2019–2024 o los 4 puntos dejados fuera (23,945 filas); validación = 2017–2018; el resto entrena (36,055 filas; la ELM usa 32,131, sin los años de validación).

**Entradas (31) y salidas (3).** Las 7 variables de clima del v1, día del año de la siembra de A, lluvia y ET₀ en los primeros 60 días tras sembrar y en los días 61–150 (solo del bundle), A (7), B (8 con "ninguno"), suelo (3) y desfase/30. Salidas: `relYieldA`, `relYieldB` (0 sin B o con ciclo incompleto) y `fit` (1 si todo lo sembrado termina dentro del año agrícola).

**Exactitud en años nuevos** (2019–2024 en puntos de entrenamiento, 12,107 filas; la verdad es el simulador):

| | R² `relYieldA` | R² `relYieldB` | R² `fit` | F1 de `fit` (umbral 0.5) |
|---|---|---|---|---|
| Red embudo (MLP) | 0.607 | 0.903 | 0.897 | 0.981 |
| ELM (sin retropropagación) | 0.501 | 0.852 | 0.737 | 0.971 |
| Línea base (media por A×B×suelo, sin clima) | −0.040 | 0.441 | 0.332 | 0.857 |

En puntos nuevos (4 puntos dejados fuera, 8,824 filas) los R² de la red son 0.807 / 0.898 / 0.883 y los de la ELM 0.750 / 0.839 / 0.698 (línea base −0.143 / 0.144 / 0.334). En toda la prueba (23,945 filas): red 0.752 / 0.896 / 0.890, ELM 0.689 / 0.841 / 0.715, línea base 0.034 / 0.268 / 0.328. Exactitud de `fit` en años nuevos: red 0.973, ELM 0.960, línea base 0.800. La parte difícil es el rendimiento del primer cultivo en años nuevos: la red llega a 0.607 y la ELM a 0.501, lejos de 0.8. La ELM de 1,500 neuronas usa la configuración que se escogió en el v1; no se hizo un barrido nuevo.

**Costo.** La red tiene 4,707 parámetros y entrenó en 7.7 s (29 épocas, GPU RTX 4050). La ELM tiene 52,500 parámetros (4,500 son los pesos de salida que se calculan) y entrenó en 56.6 s en Node. Una predicción tarda 10.5 µs (red) y 68.7 µs (ELM); el simulador, 123.4 µs por muestra: la red es 11.7 veces más rápida y la ELM 1.8. Procedencia en `emulator_v2_eval.json` (fecha 2026-11-15, lluvia ERA5).

### La decisión tras perder el maíz

**Casos (54).** Los 3 pilotos × años objetivo 2019–2024 × maíz sembrado en el inicio de lluvias y perdido a los 30, 45 o 60 días. El campo queda libre al día siguiente y la nueva siembra es 14 días después (45, 60 o 75 días tras el inicio de lluvias). La verdad la da el simulador en ese año con el suelo SoilGrids del piloto (las redes reciben `nearestTexture`). **Acciones:** resembrar uno de los siete cultivos o dejar el campo sin cultivo ("cobertura/barbecho": rendimiento 0, siempre ejecutable). **Objetivo:** rendimiento relativo del cultivo resembrado (0 si su ciclo no termina dentro del año agrícola). **Información:** la decisión del año Y usa solo los años anteriores a Y en ese sitio (la misma doble protección de `decision.js`; una prueba comprueba que alterar los datos desde Y no cambia la decisión). Prioridad "típico" = mediana de los años pasados; "cauto" = percentil 20. En empate gana dejar el campo y luego el orden de la lista.

**La regla agronómica sencilla (de Alex), fijada de antemano:** resembrar maíz si quedan al menos 120 días antes del 15 de noviembre; si no, frijol si quedan al menos 70; si no, dejar el campo. **Oráculo:** la mejor acción en el año Y mismo (rendimiento medio 0.971).

**Resultados** (n = 54 casos por fila; G / E / P = casos en que gana, empata o pierde contra la regla, tolerancia 0.001; pérdidas en años malos = percentil 10 y peor caso del rendimiento relativo de lo elegido; ejecutable = el ciclo de lo elegido termina dentro del año agrícola):

| Política | Prioridad | Rendimiento medio elegido | Ganancia sobre la regla | G / E / P | Arrepentimiento medio | Percentil 10 | Peor caso | Ejecutable | Misma acción que el simulador |
|---|---|---|---|---|---|---|---|---|---|
| Regla agronómica | – | 0.802 | 0 | 0 / 54 / 0 | 0.169 | 0.466 | 0.000 | 49 / 54 | 24 (típico), 6 (cauto) |
| Simulador | típico | 0.925 | +0.123 | 20 / 29 / 5 | 0.046 | 0.809 | 0.243 | 54 / 54 | – |
| Simulador | cauto | 0.945 | +0.143 | 26 / 17 / 11 | 0.026 | 0.837 | 0.711 | 54 / 54 | – |
| Red (MLP) | típico | 0.942 | +0.140 | 25 / 19 / 10 | 0.030 | 0.837 | 0.640 | 54 / 54 | 22 de 54 |
| Red (MLP) | cauto | 0.943 | +0.141 | 27 / 16 / 11 | 0.028 | 0.837 | 0.640 | 54 / 54 | 42 de 54 |
| ELM | típico | 0.943 | +0.141 | 24 / 17 / 13 | 0.028 | 0.800 | 0.640 | 54 / 54 | 19 de 54 |
| ELM | cauto | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54 / 54 | 36 de 54 |

Cultivos elegidos (de 54): la regla, maíz 28 y frijol 26; el simulador típico, frijol 35, maíz 11, ajonjolí 6, lechuga 2, y el cauto, ajonjolí 24, lechuga 24, frijol 6; la red típica, ajonjolí 18, lechuga 18, frijol 11, maíz 7, y la cauta, ajonjolí 36, lechuga 18; la ELM típica, ajonjolí 21, maíz 15, lechuga 12, frijol 6, y la cauta, ajonjolí 18, maíz 18, lechuga 18.

**Lectura.** En estos 54 casos las políticas con información previa superan a la regla en el rendimiento medio (0.925 a 0.945 contra 0.802). El peor caso de la regla es 0 (maíz o frijol resembrado sin tiempo de terminar) y no es ejecutable en 5 de 54 casos; los peores casos de las demás políticas quedan entre 0.243 y 0.711 y todas sus acciones son ejecutables. Pero también pierden contra la regla en 5 a 13 casos de 54, y con 54 casos que comparten 3 sitios y 6 años no hay prueba de significancia: no se afirma que una red decida mejor que el simulador ni que una prioridad sea mejor que la otra. Las dos redes coinciden con el simulador en 19 a 42 de 54 decisiones, según la prioridad. Que una red quede por encima del simulador en rendimiento medio (0.942 contra 0.925, típico) no la hace mejor: la verdad es el propio simulador en un año nuevo, y la decisión se toma con años pasados.

### Límites (estos números no son una recomendación)

- **La verdad es nuestro propio simulador.** No se corrió AquaCrop para estos cultivos; no hay juez independiente de ningún número de esta sección. En el v1, AquaCrop contradijo la ganancia del simulador por sembrar más tarde en maíz.
- **Sin respuesta al calor** para las hortalizas de clima frío (papa, cebolla, brócoli, lechuga): el simulador solo las castiga por agua y calendario; `tbase` de los cuatro cultivos nuevos y el Ky de brócoli y lechuga son sustitutos (sección de siete cultivos). El objetivo es solo rendimiento relativo por agua, por eso ajonjolí y lechuga aparecen tan seguido.
- **Sin precios ni costos, así que no se calcula el margen**, una de las tres medidas de Alex. Las medidas calculadas aquí son las pérdidas en años malos y la proporción de acciones ejecutables.
- **El suelo no conserva el agua del maíz perdido:** el cultivo resembrado se simula solo, desde un suelo seco al 1 de abril.
- **Las redes extrapolan:** se entrenaron con siembras 0, 15 y 30 días tras el inicio de lluvias y aquí reciben 45, 60 y 75.
- **Muestra pequeña:** 54 casos (3 sitios × 6 años × 3 momentos de pérdida), con los conteos junto a cada cifra y sin significancia estadística.
- **El v1 sigue siendo el modelo de la página.** El v2 se reproduce con `node scripts/emulator/generate_v2.mjs`, `python scripts/emulator/train_mlp_v2.py`, `node scripts/emulator/evaluate_v2.mjs` y `node scripts/compare/loss_decision.mjs`.

## Condiciones alineadas con el modelo de Alex (semillas 17, 29 y 43; años 2022–2024)

**Qué cambió.** Se reentrenó la red embudo v2 (receta base, mismos datos y particiones) con las semillas 17, 29 y 43, cada una en su archivo (`web/data/emulator_v2_mlp_seed17.json`, `…seed29.json`, `…seed43.json`), y la ELM v2 con las mismas tres semillas (la de su capa oculta aleatoria). Todo está en `web/data/aligned_eval.json`, escrito por `scripts/compare/aligned_eval.mjs`; los resultados de la semilla 42 (`emulator_v2_*.json`, `decision_loss_eval.json`) no cambian. Aquí no se compara con ningún otro modelo.

**Años.** Los años reservados son 2022–2025. El año agrícola 2025 (abril de 2025 a marzo de 2026) **no se puede medir**: la serie de clima termina el 2025-12-31 y no se inventó nada. Se miden 2022–2024: 27 casos (3 pilotos × 3 años × 3 momentos de pérdida). Las redes **no se reajustaron** con 2019–2021 añadidos: se ajustaron con 2019–2024 fuera, así que 2022–2024 es un subconjunto de años que nunca vieron. Se reporta también el conjunto de 2019–2024 (54 casos).

### Exactitud del emulador por semilla

**Años nuevos (2019–2024, puntos de entrenamiento)** — n = 12107 filas; R² (RMSE) por salida y F1 del ajuste. La exactitud del emulador se mide en los años de prueba con que se entrenó (2019–2024), no solo en 2022–2024.

| Modelo | Semilla | R² A | R² B | R² ajuste | RMSE A | RMSE B | RMSE ajuste | F1 ajuste |
|---|---|---|---|---|---|---|---|---|
| Red (MLP) | 17 | 0.595 | 0.911 | 0.906 | 0.093 | 0.095 | 0.139 | 0.983 |
| Red (MLP) | 29 | 0.622 | 0.899 | 0.894 | 0.090 | 0.102 | 0.148 | 0.979 |
| Red (MLP) | 43 | 0.632 | 0.906 | 0.902 | 0.089 | 0.098 | 0.142 | 0.982 |
| Red (MLP) | media (mín–máx) | 0.616 (0.595–0.632) | 0.905 (0.899–0.911) | 0.901 (0.894–0.906) | 0.091 (0.089–0.093) | 0.098 (0.095–0.102) | 0.143 (0.139–0.148) | 0.981 (0.979–0.983) |
| ELM | 17 | 0.519 | 0.850 | 0.735 | 0.102 | 0.124 | 0.234 | 0.971 |
| ELM | 29 | 0.509 | 0.853 | 0.728 | 0.103 | 0.122 | 0.237 | 0.971 |
| ELM | 43 | 0.520 | 0.855 | 0.730 | 0.102 | 0.122 | 0.236 | 0.970 |
| ELM | media (mín–máx) | 0.516 (0.509–0.520) | 0.853 (0.850–0.855) | 0.731 (0.728–0.735) | 0.102 (0.102–0.103) | 0.123 (0.122–0.124) | 0.236 (0.234–0.237) | 0.971 (0.970–0.971) |

**Puntos nuevos (puntos retenidos, otros años)** — n = 8824 filas; R² (RMSE) por salida y F1 del ajuste. La exactitud del emulador se mide en los años de prueba con que se entrenó (2019–2024), no solo en 2022–2024.

| Modelo | Semilla | R² A | R² B | R² ajuste | RMSE A | RMSE B | RMSE ajuste | F1 ajuste |
|---|---|---|---|---|---|---|---|---|
| Red (MLP) | 17 | 0.797 | 0.907 | 0.864 | 0.111 | 0.115 | 0.156 | 0.981 |
| Red (MLP) | 29 | 0.805 | 0.917 | 0.887 | 0.108 | 0.109 | 0.142 | 0.982 |
| Red (MLP) | 43 | 0.792 | 0.908 | 0.884 | 0.112 | 0.115 | 0.144 | 0.982 |
| Red (MLP) | media (mín–máx) | 0.798 (0.792–0.805) | 0.911 (0.907–0.917) | 0.878 (0.864–0.887) | 0.110 (0.108–0.112) | 0.113 (0.109–0.115) | 0.147 (0.142–0.156) | 0.982 (0.981–0.982) |
| ELM | 17 | 0.760 | 0.831 | 0.698 | 0.120 | 0.156 | 0.232 | 0.969 |
| ELM | 29 | 0.759 | 0.852 | 0.691 | 0.121 | 0.146 | 0.235 | 0.968 |
| ELM | 43 | 0.750 | 0.843 | 0.687 | 0.123 | 0.150 | 0.236 | 0.969 |
| ELM | media (mín–máx) | 0.756 (0.750–0.760) | 0.842 (0.831–0.852) | 0.692 (0.687–0.698) | 0.121 (0.120–0.123) | 0.151 (0.146–0.156) | 0.234 (0.232–0.236) | 0.969 (0.968–0.969) |

### Decisión tras perder el maíz, años reservados medibles 2022–2024 (n = 27 casos)

G / E / P = casos en que gana, empata o pierde contra la regla (tolerancia 0.001). Ejecutable = acciones cuyo ciclo termina en el año. Bajo 0.5 = casos con rendimiento relativo elegido menor que 0.5. Se aparta = casos en que la acción elegida difiere de la de la regla. Los conteos van de n = 27; no se hace prueba de significancia.

| Política | Prioridad | Semilla | Rendimiento medio elegido | Ganancia sobre la regla | G / E / P | Arrepentimiento medio | Percentil 10 | Peor caso | Ejecutable | Bajo 0.5 | Se aparta de la regla |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Regla agronómica | – | – | 0.856 | +0.000 | 0 / 27 / 0 | 0.123 | 0.607 | 0.000 | 26 / 27 | 2 / 27 | 0 / 27 |
| Simulador | típico | – | 0.947 | +0.091 | 10 / 16 / 1 | 0.032 | 0.907 | 0.462 | 27 / 27 | 1 / 27 | 15 / 27 |
| Simulador | cauto | – | 0.963 | +0.107 | 13 / 8 / 6 | 0.017 | 0.905 | 0.796 | 27 / 27 | 0 / 27 | 24 / 27 |
| Oráculo | – | – | 0.979 | – | – | 0 | – | – | 27 / 27 | 0 / 27 | 17 / 27 |
| Red (MLP) | típico | 17 | 0.953 | +0.097 | 13 / 8 / 6 | 0.027 | 0.851 | 0.711 | 27 / 27 | 0 / 27 | 27 / 27 |
| Red (MLP) | típico | 29 | 0.952 | +0.097 | 13 / 7 / 7 | 0.027 | 0.851 | 0.711 | 27 / 27 | 0 / 27 | 25 / 27 |
| Red (MLP) | típico | 43 | 0.957 | +0.101 | 12 / 10 / 5 | 0.022 | 0.851 | 0.752 | 27 / 27 | 0 / 27 | 22 / 27 |
| Red (MLP) | típico | media (mín–máx) | 0.954 (0.952–0.957) | 0.098 (0.097–0.101) | G 12.7 (12.0–13.0); E 8.3 (7.0–10.0); P 6.0 (5.0–7.0) | 0.025 (0.022–0.027) | 0.851 (0.851–0.851) | 0.725 (0.711–0.752) | 27.0 (27.0–27.0) | 0.0 (0.0–0.0) | 24.7 (22.0–27.0) |
| Red (MLP) | cauto | 17 | 0.953 | +0.097 | 13 / 8 / 6 | 0.027 | 0.851 | 0.711 | 27 / 27 | 0 / 27 | 27 / 27 |
| Red (MLP) | cauto | 29 | 0.952 | +0.096 | 13 / 6 / 8 | 0.027 | 0.851 | 0.711 | 27 / 27 | 0 / 27 | 27 / 27 |
| Red (MLP) | cauto | 43 | 0.952 | +0.096 | 12 / 9 / 6 | 0.027 | 0.851 | 0.711 | 27 / 27 | 0 / 27 | 24 / 27 |
| Red (MLP) | cauto | media (mín–máx) | 0.952 (0.952–0.953) | 0.096 (0.096–0.097) | G 12.7 (12.0–13.0); E 7.7 (6.0–9.0); P 6.7 (6.0–8.0) | 0.027 (0.027–0.027) | 0.851 (0.851–0.851) | 0.711 (0.711–0.711) | 27.0 (27.0–27.0) | 0.0 (0.0–0.0) | 26.0 (24.0–27.0) |
| ELM | típico | 17 | 0.928 | +0.072 | 12 / 7 / 8 | 0.052 | 0.761 | 0.422 | 27 / 27 | 1 / 27 | 25 / 27 |
| ELM | típico | 29 | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27 / 27 | 1 / 27 | 26 / 27 |
| ELM | típico | 43 | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27 / 27 | 1 / 27 | 26 / 27 |
| ELM | típico | media (mín–máx) | 0.933 (0.928–0.935) | 0.077 (0.072–0.079) | G 12.7 (12.0–13.0); E 6.3 (6.0–7.0); P 8.0 (8.0–8.0) | 0.047 (0.044–0.052) | 0.795 (0.761–0.811) | 0.422 (0.422–0.422) | 27.0 (27.0–27.0) | 1.0 (1.0–1.0) | 25.7 (25.0–26.0) |
| ELM | cauto | 17 | 0.917 | +0.061 | 12 / 6 / 9 | 0.062 | 0.718 | 0.422 | 27 / 27 | 1 / 27 | 27 / 27 |
| ELM | cauto | 29 | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27 / 27 | 1 / 27 | 27 / 27 |
| ELM | cauto | 43 | 0.952 | +0.096 | 13 / 6 / 8 | 0.027 | 0.851 | 0.711 | 27 / 27 | 0 / 27 | 27 / 27 |
| ELM | cauto | media (mín–máx) | 0.935 (0.917–0.952) | 0.079 (0.061–0.096) | G 12.7 (12.0–13.0); E 6.0 (6.0–6.0); P 8.3 (8.0–9.0) | 0.045 (0.027–0.062) | 0.793 (0.718–0.851) | 0.519 (0.422–0.711) | 27.0 (27.0–27.0) | 0.7 (0.0–1.0) | 27.0 (27.0–27.0) |

### Decisión tras perder el maíz, 2019–2024 (adicional) (n = 54 casos)

G / E / P = casos en que gana, empata o pierde contra la regla (tolerancia 0.001). Ejecutable = acciones cuyo ciclo termina en el año. Bajo 0.5 = casos con rendimiento relativo elegido menor que 0.5. Se aparta = casos en que la acción elegida difiere de la de la regla. Los conteos van de n = 54; no se hace prueba de significancia.

| Política | Prioridad | Semilla | Rendimiento medio elegido | Ganancia sobre la regla | G / E / P | Arrepentimiento medio | Percentil 10 | Peor caso | Ejecutable | Bajo 0.5 | Se aparta de la regla |
|---|---|---|---|---|---|---|---|---|---|---|---|
| Regla agronómica | – | – | 0.802 | +0.000 | 0 / 54 / 0 | 0.169 | 0.466 | 0.000 | 49 / 54 | 7 / 54 | 0 / 54 |
| Simulador | típico | – | 0.925 | +0.123 | 20 / 29 / 5 | 0.046 | 0.809 | 0.243 | 54 / 54 | 3 / 54 | 30 / 54 |
| Simulador | cauto | – | 0.945 | +0.143 | 26 / 17 / 11 | 0.026 | 0.837 | 0.711 | 54 / 54 | 0 / 54 | 48 / 54 |
| Oráculo | – | – | 0.971 | – | – | 0 | – | – | 54 / 54 | 0 / 54 | 33 / 54 |
| Red (MLP) | típico | 17 | 0.943 | +0.141 | 27 / 16 / 11 | 0.028 | 0.837 | 0.640 | 54 / 54 | 0 / 54 | 54 / 54 |
| Red (MLP) | típico | 29 | 0.943 | +0.141 | 26 / 17 / 11 | 0.028 | 0.837 | 0.640 | 54 / 54 | 0 / 54 | 44 / 54 |
| Red (MLP) | típico | 43 | 0.944 | +0.142 | 24 / 21 / 9 | 0.027 | 0.807 | 0.640 | 54 / 54 | 0 / 54 | 42 / 54 |
| Red (MLP) | típico | media (mín–máx) | 0.943 (0.943–0.944) | 0.141 (0.141–0.142) | G 25.7 (24.0–27.0); E 18.0 (16.0–21.0); P 10.3 (9.0–11.0) | 0.028 (0.027–0.028) | 0.827 (0.807–0.837) | 0.640 (0.640–0.640) | 54.0 (54.0–54.0) | 0.0 (0.0–0.0) | 46.7 (42.0–54.0) |
| Red (MLP) | cauto | 17 | 0.943 | +0.141 | 27 / 16 / 11 | 0.028 | 0.837 | 0.640 | 54 / 54 | 0 / 54 | 54 / 54 |
| Red (MLP) | cauto | 29 | 0.942 | +0.140 | 27 / 14 / 13 | 0.029 | 0.837 | 0.640 | 54 / 54 | 0 / 54 | 54 / 54 |
| Red (MLP) | cauto | 43 | 0.944 | +0.142 | 26 / 19 / 9 | 0.027 | 0.818 | 0.640 | 54 / 54 | 0 / 54 | 49 / 54 |
| Red (MLP) | cauto | media (mín–máx) | 0.943 (0.942–0.944) | 0.141 (0.140–0.142) | G 26.7 (26.0–27.0); E 16.3 (14.0–19.0); P 11.0 (9.0–13.0) | 0.028 (0.027–0.029) | 0.831 (0.818–0.837) | 0.640 (0.640–0.640) | 54.0 (54.0–54.0) | 0.0 (0.0–0.0) | 52.3 (49.0–54.0) |
| ELM | típico | 17 | 0.915 | +0.113 | 22 / 19 / 13 | 0.056 | 0.757 | 0.277 | 54 / 54 | 2 / 54 | 43 / 54 |
| ELM | típico | 29 | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54 / 54 | 2 / 54 | 47 / 54 |
| ELM | típico | 43 | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54 / 54 | 2 / 54 | 47 / 54 |
| ELM | típico | media (mín–máx) | 0.922 (0.915–0.925) | 0.120 (0.113–0.123) | G 24.0 (22.0–25.0); E 17.0 (16.0–19.0); P 13.0 (13.0–13.0) | 0.049 (0.046–0.056) | 0.798 (0.757–0.818) | 0.277 (0.277–0.277) | 54.0 (54.0–54.0) | 2.0 (2.0–2.0) | 45.7 (43.0–47.0) |
| ELM | cauto | 17 | 0.910 | +0.108 | 24 / 15 / 15 | 0.061 | 0.759 | 0.277 | 54 / 54 | 2 / 54 | 51 / 54 |
| ELM | cauto | 29 | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54 / 54 | 2 / 54 | 51 / 54 |
| ELM | cauto | 43 | 0.942 | +0.140 | 26 / 15 / 13 | 0.029 | 0.837 | 0.640 | 54 / 54 | 0 / 54 | 52 / 54 |
| ELM | cauto | media (mín–máx) | 0.926 (0.910–0.942) | 0.123 (0.108–0.140) | G 25.0 (24.0–26.0); E 15.3 (15.0–16.0); P 13.7 (13.0–15.0) | 0.046 (0.029–0.061) | 0.805 (0.759–0.837) | 0.398 (0.277–0.640) | 54.0 (54.0–54.0) | 1.3 (0.0–2.0) | 51.3 (51.0–52.0) |


### Lectura, sin rodeos

- **Pocos casos.** El conjunto de 2022–2024 tiene solo 27 casos (3 pilotos × 3 años × 3 momentos de pérdida). Cada caso pesa 1 de 27; diferencias de 1 a 3 casos entre semillas o entre políticas no son significativas y no se hizo ninguna prueba de significancia.
- **El año 2025 no está medido.** Faltan datos; nada se estimó ni se completó.
- **Red (MLP).** Entre las tres semillas, en 2022–2024 el rendimiento medio elegido va de 0.952 a 0.957 (típico) y de 0.952 a 0.953 (cauto); ninguna semilla da resultados por debajo de 0.5 en 27 casos. Lo que sí cambia entre semillas es en cuántos casos se aparta de la regla (22 a 27 de 27 en típico) y el conteo G / E / P (por ejemplo 13 / 8 / 6, 13 / 7 / 7 y 12 / 10 / 5 en típico).
- **ELM.** Es más variable entre semillas que la red, sobre todo con prioridad cauta en 2022–2024: rendimiento medio de 0.917 a 0.952, percentil 10 de 0.718 a 0.851, peor caso de 0.422 a 0.711, y un caso por debajo de 0.5 en las semillas 17 y 29 y ninguno en la 43. Con prioridad típica el peor caso es 0.422 en las tres semillas y hay un caso por debajo de 0.5 en cada una. La semilla 17 es la peor de la ELM en ambas prioridades y en ambos conjuntos de años.
- **Exactitud del emulador.** La salida más débil de la red es el rendimiento relativo del primer cultivo en años nuevos (R² de 0.595 a 0.632 entre semillas); la de la ELM también (0.509 a 0.520), y la ELM queda por debajo de la red en todas las salidas y semillas, en años nuevos y en puntos nuevos. Esa exactitud se mide en los años de prueba 2019–2024 con que se entrenó, no en 2022–2024 solamente.
- **Contra la regla.** En 2022–2024 la regla tiene peor caso 0 y un caso no ejecutable de 27; el simulador tiene peor caso 0.462 (típico) y 0.796 (cauto). Todo esto es del simulador como juez, sin precios ni costos, y no es una recomendación.

## Optimizaciones de entrenamiento (notas de Alex)

Alex listó lo que mejoró el entrenamiento de su CNN. Aplicamos a nuestra red embudo (unos 4,500 parámetros, entrena en segundos) lo que le cabe, eligiendo solo con validación (filas de entrenamiento de los años 2017-2018; ninguna fila de prueba se leyó: `nTestRowsRead` = 0 en `scripts/emulator/recipe_screening.json`).

| Ítem de las notas | Estado |
|---|---|
| Reducir la tasa de aprendizaje en meseta, paciencia 13 (`sched`) | Probado, no ganó (tabla abajo) |
| Residual sobre una estimación previa, capa de salida en cero (`resid`) | Probado, empeoró (tabla abajo) |
| Varias semillas, elegir en validación | Aplicado: semillas 42 y 43 por receta |
| No medir memoria del proceso dentro del bucle de lotes | Aplicado: ahora una vez por época (el ahorro medido es despreciable: 4,000 lecturas cuestan 0.01 s) |
| Precisión mixta (AMP) | No aplica: en esta red fue más lenta, 1.90 s contra 1.11 s por 5 épocas en CUDA |
| `channels_last`, `cudnn.benchmark` | No aplican: la red no tiene convoluciones |
| Datos ya en memoria del dispositivo | Ya era así (todo el conjunto de ajuste se sube a la GPU una vez) |
| Optimizador fusionado | No aplica: cuatro capas lineales; el cuello de botella son los lanzamientos de kernels pequeños (en CUDA entrena en 7.8 s contra 4.1 s en CPU) |

Las 8 corridas (v1, 27 entradas; MSE de validación con salidas estandarizadas, CUDA; el tiempo en CPU es de la misma corrida):

| Receta | Semilla | Épocas | s CUDA | s CPU | MSE validación |
|---|---|---|---|---|---|
| base | 42 | 38 | 7.84 | 4.05 | 0.0622 |
| base | 43 | 41 | 7.76 | 4.16 | 0.0616 |
| sched | 42 | 48 | 11.06 | 4.78 | 0.0637 |
| sched | 43 | 44 | 8.61 | 4.37 | 0.0616 |
| resid | 42 | 45 | 8.38 | 4.36 | 0.0870 |
| resid | 43 | 41 | 7.65 | 5.63 | 0.0889 |
| sched+resid | 42 | 48 | 9.38 | 4.88 | 0.0870 |
| sched+resid | 43 | 54 | 10.12 | 6.54 | 0.0878 |

Promedio de las dos semillas:

| Receta | MSE validación medio | Cambio frente a `base` |
|---|---|---|
| base | 0.0619 | +0.0 % |
| sched | 0.0627 | -1.2 % |
| resid | 0.0879 | -42.0 % |
| sched+resid | 0.0874 | -41.1 % |

Resultado: **ninguna receta mejora a `base` en 2 % o más, así que se queda `base` sin cambios** (la regla fijada de antemano). `sched` queda 1.2 % peor en promedio: con la semilla 43 la mejor época llega antes de la primera reducción y da el mismo número que `base`; con la 42 reduce la tasa y no mejora. `resid` empeora 42 %: la media por grupo de manejo sola da un MSE de validación de 0.605 y la red parte de ahí, pero termina en 0.088, peor que los 0.062 de la red entrenada desde cero (no medimos la causa). Por eso no se reentrenó ni se reevaluó v1 ni v2, y todas las tablas de este documento se mantienen. El código de `resid` (tabla `baseline` en el JSON y suma en `mlpPredict`, compatible con modelos sin tabla) queda probado por `tests/emulator.test.mjs` pero ningún modelo publicado lo usa.

## Limitaciones conocidas

- El modelo solo simula agua. No incluye plagas, fertilización, sombra, precios ni mano de obra.
- **Subsuelo corregido:** las raíces que crecen ya solo alcanzan el agua que la lluvia percoló hasta ahí (commit `4ea12c1`). Ya no "regala" agua.
- **Ky por etapa solo para maíz y frijol** (verificados en FAO-66 cap. 2 y en IAEA/FAO Water Reports 22). Sorgo, sandía y tomate usan el Ky estacional porque su Ky por etapa no se pudo verificar; ajonjolí y melón no tienen. La regla de multiplicar las fracciones de rendimiento de cada etapa está documentada en una fuente secundaria (ayuda de WEAP/SEI); no se pudo confirmar que sea la forma de Rao, Sarma y Chander (1988), así que no se cita como su fuente.
- **Lluvia:** el modelo usa ERA5 (Copernicus, por Open-Meteo). ClimateSERV ofrece dos conjuntos IMERG diarios y ninguno está completo en 2001–2024. **El conjunto 26** ("NASA-IMERG-V06-Late 1 Day" según la documentación de ClimateSERV) termina el 1 de junio de 2024 y le falta el 30 de junio de 2019, así que cubre 22 de los 24 años agrícolas (579 días faltantes de 2001–2025, `rain_compare.json`, `coverage.missingDays`). **El conjunto 226** ("NASA-IMERG-V07-Late 1 Day") llega hasta el 31 de diciembre de 2025, pero le faltan 40 días en los 3 pilotos (1–7 de junio de 2014, 31 de diciembre de 2023, 1 de enero de 2024 y mayo de 2024), así que cubre 21 de los 24 años agrícolas. Ninguno de los dos puede ser la única fuente sin rellenar huecos, y no se rellenó ninguno. El conjunto 226 solo se descargó en los 3 pilotos y es de la corrida Late, no de la Final. CHIRPS está completo, pero no se cambió de fuente. En los 3 pilotos ERA5 es el producto más seco: en los 21 años comunes con el conjunto 226, la lluvia media por año agrícola con ERA5 / CHIRPS / conjunto 226 es 1,103.0 / 1,316.4 / 1,565.9 mm en Chiquimula, 1,097.8 / 1,309.2 / 1,507.9 en Jutiapa y 1,095.7 / 1,164.1 / 1,701.9 en San Martín. En los 22 años comunes de las series anteriores (ERA5 / conjunto 26 / CHIRPS): Chiquimula 1,098.9 / 1,164.1 / 1,307.9; Jutiapa 1,084.2 / 1,313.1 / 1,302.5; San Martín 1,100.7 / 1,224.5 / 1,158.3. La lluvia de NASA POWER no se usa. Ver la sensibilidad a la lluvia arriba.
- **Suelo:** el simulador y el emulador usan 3 clases (arena, franco, arcilla). Los suelos de SoilGrids de los 3 pilotos solo entran en el simulador y en las pruebas de AquaCrop de arriba, no en el emulador. SoilGrids es una predicción global y necesita verificación local; en Jutiapa el agua disponible (0.056) es muy baja para una arcilla. `nearestTexture` se elige solo por el agua disponible y puede no coincidir con la clase más cercana en resultado (ver arriba).
- El número de curva del grupo hidrológico D con residuo es 85; la asignación de grupo según la textura es una aproximación.
- En cultivos traslapados (relevo) se usa el Kc mayor y la raíz mayor, sin competencia entre cultivos.
- **Temperatura a la elevación de la parcela (Tarea 22):** ya no se usa la temperatura de la celda tal cual: se mueve con un gradiente fijo de −0.0065 °C/m a la elevación del pueblo (modelo digital Copernicus GLO-90 de unos 90 m, un punto por municipio), con humedad relativa constante y presión barométrica de FAO-56. Lo que sigue sin corregirse: la lluvia (ERA5, malla de 0.25°) y la radiación y el viento (POWER, unos 0.5°) siguen a la escala de la celda; el gradiente fijo no capta inversiones ni diferencias de ladera; el segundo cultivo se siembra siempre el 1 de septiembre; y el traslape se trata como relevo sin competencia.
- **Celdas compartidas:** varios municipios comparten celda de NASA POWER (por ejemplo, Salamá, Rabinal, Cubulco y San Martín Jilotepeque, celda a 1,516 m; los tres valles de Baja Verapaz están a unos 950 m y San Martín a 1,787 m). Cada uno recibe su propia temperatura corregida (ΔT de −2.19 a +3.95 °C en los 20 puntos), pero comparten la radiación y el viento de la celda, y los de la misma celda parten de la misma humedad relativa; solo Chiquimula y Jocotán tienen también la misma lluvia.
- **Altura y ciclos:** con la corrección, la duración del ciclo en Chiquimula coincide con la citada (maíz 118 días, frijol 70) pero en Jutiapa sigue 20 % larga (maíz 144 días) y en San Martín (1,787 m, más alto que su celda) empeoró (maíz 273 días, rotación con ajonjolí incompleta en los 24 años). Los días por etapa son de tierras bajas y no se tocaron, así que arriba de 1,500 m el modelo no es confiable; el acuerdo con AquaCrop en San Martín se perdió (Spearman −0.09).
- El índice de agua promedia los cultivos de comida de cada rotación, así que no es comparable entre rotaciones con cultivos distintos.
- Un cultivo que no termina su ciclo dentro del año agrícola cuenta como rendimiento 0.
- **Empeoró con la corrección de temperatura:** el R² del índice de agua del emulador en años nuevos (los tres modelos) y el del suelo desnudo en todas las divisiones; el error del suelo desnudo en las nueve combinaciones de la diferencia entre rotaciones, y el signo correcto del índice de agua en 8 de ellas (lista completa en Medidas ligadas a la decisión); el acuerdo con AquaCrop en San Martín (Spearman 0.51 → −0.09); y la ganancia del índice del simulador por sembrar más tarde, que se debilita (la contradicción con AquaCrop no cambia). **Mejoró:** el agua en floración del emulador en años nuevos (los tres modelos), la detección de estrés, el acuerdo con AquaCrop en Chiquimula (0.851 → 0.886) y la duración del ciclo en Chiquimula.
- **Meta no cumplida del todo:** la ELM sigue bajo 0.8 en años nuevos en el índice de agua (0.739; el agua en floración sí cumple, 0.826) y la del navegador en los dos (0.687 y 0.719). La red embudo cumple las dos (0.819 y 0.897). Las entradas de agua antecedente se diseñaron después de conocer resultados de prueba anteriores y no se volvieron a cribar con la temperatura corregida.
- `storeProxy` usa un tope fijo de 150 mm para todo suelo: es un indicador sin suelo, no el balance del simulador.

## Cómo reproducir

```bash
npm test                                             # 231 pruebas (1 pendiente: la meta de R² de la ELM)
node scripts/data/fetch_site_elevation.mjs           # elevación de la parcela de los 20 puntos (única llamada de red de la corrección; usa scripts/data/site_elevation.json si existe)
node scripts/emulator/fetch_points.mjs               # arma los bundles con la temperatura corregida desde los cachés de NASA POWER + ERA5 (descarga solo lo que falta)
node scripts/emulator/generate.mjs                   # genera los 50,000 ejemplos (guarda commit, lluvia y fecha)
node scripts/emulator/build_screening_superset.mjs && python scripts/emulator/screen_features.py   # cribado de las entradas de agua antecedente (Tarea 19, antes de la corrección térmica; no se repitió)
python scripts/emulator/train_mlp.py --device cpu --out <tmp>/mlp_cpu.json                     # tiempo de CPU
python scripts/emulator/train_mlp.py --device cuda --cpu-timing <tmp>/mlp_cpu.json             # red embudo (pesos de esta corrida)
node --expose-gc scripts/emulator/evaluate.mjs       # barrido de la ELM y todas las métricas
# juez AquaCrop: ver scripts/referee/README.md
node scripts/referee/compare.mjs --aquacrop <resultados> --bundle web/data/snapshots/chiquimula.json --stage pre-subsoil=<d02febe> --stage subsoil=<4ea12c1> --stage stage-ky=<df4da88> --stage final=.
node scripts/data/cycle_lengths.mjs --before <raíz de e5a3d49: git archive e5a3d49 web | tar -x -C <raíz>>   # duración de ciclos antes y después de la corrección
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
