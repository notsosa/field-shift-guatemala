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

## Red que recomienda (prioridad del agricultor, estado del lote, entrenada por el resultado de la decisión)

15 de noviembre de 2026. Es la tarea de la pérdida del maíz de las condiciones comunes (`proyecto/condiciones-comunes.md`), pero ahora una red elige directamente la acción en vez de predecir y luego elegir. Todo es aditivo: el simulador, las redes v2 y sus resultados no cambian. Los números salen de `web/data/recommender_eval.json` (commit del simulador `929a05e`); las filas de las políticas de "predecir y elegir" están copiadas de `web/data/aligned_eval.json`, no recalculadas. **Desde la Tarea 33 la red se entrena en GPU (otro flujo aleatorio que la versión en JS de la Tarea 31); los números de esta sección son los del reentrenamiento y la comparación con los anteriores está en la sección "Entrenamiento en GPU y más datos y entradas".**

**Qué hace.** Para cada una de las 8 acciones (resembrar uno de siete cultivos o dejar el terreno) la red da una corrección; el puntaje es 1 si la acción es la de la regla agronómica (0 si no) más tanh(corrección), y se recomienda el mayor puntaje (empate: la acción de la regla). Al inicio la corrección vale 0 y la red recomienda exactamente lo que la regla (hay una prueba). Tres ideas tomadas del diseño del compañero: la **prioridad del agricultor** como entrada (0 = rendir más en un año típico, 1 = no perder en un año malo), el entrenamiento por **cómo salió la decisión**, y **más información del lote** el día de la decisión.

**Diseño (fijado antes de ver los casos de prueba).**
- Entradas (32): día del año, días desde el inicio de lluvias (la siembra), días al 15 de noviembre y al fin del año agrícola, día de la pérdida, lluvia y ET₀ de los últimos 7 y 28 días y desde el 1 de abril, racha seca más larga de los últimos 28 días, temperatura media de los últimos 28 días, balance antecedente acotado a 150 mm (la lógica de `storeProxy` del emulador, con Kc del maíz hasta el día de la pérdida y suelo desnudo, Kc = kc.ini del maíz, después), agua disponible del suelo (mm por m), número de curva del cultivo, altitud; la prioridad; y por acción: one-hot de 8, ciclo nominal en días, Kc medio, profundidad de raíz, p, Ky y si el ciclo nominal cabe antes del fin del año agrícola. Solo se usa el clima hasta el día de la decisión (el día de la pérdida, con el clima de ese día); una prueba altera todo lo posterior y ninguna entrada cambia.
- **No hay entradas de finanzas ni de historial de plagas o fertilizante: el proyecto no tiene esos datos y no se inventaron.**
- Red: 32 → 64 → 32 → 16 → 1 (tanh en las ocultas, salida en cero al inicio), 4737 parámetros.
- Entrenamiento sin retropropagación: estrategia de evolución (μ, λ), población 32, 8 padres, mutación gaussiana σ = 0.05, elitismo 1, 150 generaciones; en cada generación 512 escenarios de entrenamiento (sorteados con el generador de torch) con las dos prioridades. Aptitud: prioridad 0 = media de y; prioridad 1 = media de y − max(0, 0.5 − y); la aptitud es el promedio de las dos. El mejor de cada generación se puntúa con toda la validación y se guarda el mejor. Semillas 17, 29, 43. Código: `scripts/gpu/train_recommender.py` sobre el núcleo `scripts/gpu/es_core.py` (una operación por lotes por generación: 32 individuos × 512 escenarios × 2 prioridades × 8 acciones).
- Datos: tabla de escenarios calculada una vez con el simulador: entrenamiento 2592 (20 puntos × años 2001–2016 × pérdida 30/45/60; arena, franco y arcilla en los puntos que no son piloto y el suelo del sitio en los pilotos), validación 324 (2017–2018), prueba 54 (los 3 pilotos, 2019–2024). Tiempo de la tabla: 17.5 s.
- Comprobación entre JS y PyTorch (`jsVsTorchCheck` en el artefacto): semilla 17, 62 filas, diferencia máxima de puntaje 4.8e-15, misma recomendación en 62/62; semilla 29, 62 filas, diferencia máxima de puntaje 4.1e-15, misma recomendación en 62/62; semilla 43, 62 filas, diferencia máxima de puntaje 4.4e-15, misma recomendación en 62/62.

### Aprendizaje y tiempos

| Semilla | Validación primera / mejor / última | Mejor generación | Aptitud de entrenamiento primera / última | Tiempo (s) | Evaluaciones de escenario por s |
|---|---|---|---|---|---|
| 17 | 0.923 / 0.957 / 0.954 | 128 | 0.885 / 0.931 | 5.6 | 870582 |
| 29 | 0.923 / 0.961 / 0.951 | 146 | 0.881 / 0.937 | 5.3 | 929478 |
| 43 | 0.923 / 0.959 / 0.950 | 129 | 0.898 / 0.932 | 5.5 | 888602 |

La aptitud de validación de la red inicial (igual a la regla) es 0.923; "primera" es la del mejor de la generación 0. Las tres semillas corrieron una tras otra en la GPU (NVIDIA GeForce RTX 4050 Laptop GPU, torch 2.11.0+cu128). Una evaluación de escenario = un individuo decidiendo un escenario con una prioridad. El checkpoint guardado en `web/data/recommender_mlp.json` es el de la semilla 29 (generación 146, aptitud de validación 0.961), la mejor en validación. Tiempo por recomendación (8 acciones, JS): 0.134 ms.

### Años reservados 2022–2024 (n = 27 casos)

Columnas: rendimiento relativo medio de lo elegido; ganancia media sobre la regla; casos ganados / empatados / perdidos (tolerancia 0.001); arrepentimiento medio frente a la mejor opción; percentil 10; peor caso; recomendaciones ejecutables; resultados por debajo de 0.5; casos en que se aparta de la regla.

| Política | Media | Ganancia | G / E / P | Arrepent. | P10 | Peor | Ejecut. | < 0.5 | Se aparta |
|---|---|---|---|---|---|---|---|---|---|
| Regla agronómica | 0.856 | +0.000 | 0 / 27 / 0 | 0.123 | 0.607 | 0.000 | 26/27 | 2/27 | 0/27 |
| Mejor opción en retrospectiva (techo) | 0.979 | | | 0.000 | | | 27/27 | 0/27 | 17/27 |
| Simulador como política (típico) | 0.947 | +0.091 | 10 / 16 / 1 | 0.032 | 0.907 | 0.462 | 27/27 | 1/27 | 15/27 |
| Simulador como política (cauto) | 0.963 | +0.107 | 13 / 8 / 6 | 0.017 | 0.905 | 0.796 | 27/27 | 0/27 | 24/27 |
| **Red que recomienda**, semilla 17, típico | 0.881 | +0.025 | 4 / 17 / 6 | 0.099 | 0.652 | 0.462 | 27/27 | 1/27 | 10/27 |
| **Red que recomienda**, semilla 17, cauto | 0.828 | -0.027 | 1 / 22 / 4 | 0.151 | 0.524 | 0.000 | 25/27 | 3/27 | 5/27 |
| **Red que recomienda**, semilla 29, típico | 0.944 | +0.088 | 7 / 20 / 0 | 0.035 | 0.902 | 0.462 | 27/27 | 1/27 | 9/27 |
| **Red que recomienda**, semilla 29, cauto | 0.928 | +0.072 | 5 / 19 / 3 | 0.051 | 0.781 | 0.462 | 27/27 | 1/27 | 10/27 |
| **Red que recomienda**, semilla 43, típico | 0.838 | -0.018 | 3 / 21 / 3 | 0.141 | 0.524 | 0.000 | 26/27 | 3/27 | 9/27 |
| **Red que recomienda**, semilla 43, cauto | 0.895 | +0.040 | 4 / 20 / 3 | 0.084 | 0.619 | 0.462 | 27/27 | 1/27 | 10/27 |
| Predecir y elegir: red v2, semilla 17, típico (copiado) | 0.953 | +0.097 | 13 / 8 / 6 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 27/27 |
| Predecir y elegir: red v2, semilla 17, cauto (copiado) | 0.953 | +0.097 | 13 / 8 / 6 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 27/27 |
| Predecir y elegir: red v2, semilla 29, típico (copiado) | 0.952 | +0.097 | 13 / 7 / 7 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 25/27 |
| Predecir y elegir: red v2, semilla 29, cauto (copiado) | 0.952 | +0.096 | 13 / 6 / 8 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 27/27 |
| Predecir y elegir: red v2, semilla 43, típico (copiado) | 0.957 | +0.101 | 12 / 10 / 5 | 0.022 | 0.851 | 0.752 | 27/27 | 0/27 | 22/27 |
| Predecir y elegir: red v2, semilla 43, cauto (copiado) | 0.952 | +0.096 | 12 / 9 / 6 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 24/27 |
| Predecir y elegir: ELM v2, semilla 17, típico (copiado) | 0.928 | +0.072 | 12 / 7 / 8 | 0.052 | 0.761 | 0.422 | 27/27 | 1/27 | 25/27 |
| Predecir y elegir: ELM v2, semilla 17, cauto (copiado) | 0.917 | +0.061 | 12 / 6 / 9 | 0.062 | 0.718 | 0.422 | 27/27 | 1/27 | 27/27 |
| Predecir y elegir: ELM v2, semilla 29, típico (copiado) | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27/27 | 1/27 | 26/27 |
| Predecir y elegir: ELM v2, semilla 29, cauto (copiado) | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27/27 | 1/27 | 27/27 |
| Predecir y elegir: ELM v2, semilla 43, típico (copiado) | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27/27 | 1/27 | 26/27 |
| Predecir y elegir: ELM v2, semilla 43, cauto (copiado) | 0.952 | +0.096 | 13 / 6 / 8 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 27/27 |

Resumen de la red que recomienda entre las 3 semillas (media, mínimo y máximo de la media de lo elegido): típico 0.888 (0.838–0.944); cauto 0.884 (0.828–0.928).

### Adicional 2019–2024 (n = 54 casos)

Mismas columnas.

| Política | Media | Ganancia | G / E / P | Arrepent. | P10 | Peor | Ejecut. | < 0.5 | Se aparta |
|---|---|---|---|---|---|---|---|---|---|
| Regla agronómica | 0.802 | +0.000 | 0 / 54 / 0 | 0.169 | 0.466 | 0.000 | 49/54 | 7/54 | 0/54 |
| Mejor opción en retrospectiva (techo) | 0.971 | | | 0.000 | | | 54/54 | 0/54 | 33/54 |
| Simulador como política (típico) | 0.925 | +0.123 | 20 / 29 / 5 | 0.046 | 0.809 | 0.243 | 54/54 | 3/54 | 30/54 |
| Simulador como política (cauto) | 0.945 | +0.143 | 26 / 17 / 11 | 0.026 | 0.837 | 0.711 | 54/54 | 0/54 | 48/54 |
| **Red que recomienda**, semilla 17, típico | 0.816 | +0.014 | 12 / 34 / 8 | 0.155 | 0.139 | 0.000 | 48/54 | 7/54 | 28/54 |
| **Red que recomienda**, semilla 17, cauto | 0.796 | -0.006 | 8 / 39 / 7 | 0.175 | 0.000 | 0.000 | 47/54 | 8/54 | 21/54 |
| **Red que recomienda**, semilla 29, típico | 0.915 | +0.113 | 19 / 33 / 2 | 0.056 | 0.827 | 0.000 | 52/54 | 3/54 | 29/54 |
| **Red que recomienda**, semilla 29, cauto | 0.896 | +0.094 | 15 / 32 / 7 | 0.075 | 0.687 | 0.000 | 52/54 | 3/54 | 30/54 |
| **Red que recomienda**, semilla 43, típico | 0.855 | +0.053 | 14 / 35 / 5 | 0.116 | 0.513 | 0.000 | 51/54 | 6/54 | 30/54 |
| **Red que recomienda**, semilla 43, cauto | 0.856 | +0.054 | 13 / 34 / 7 | 0.115 | 0.513 | 0.000 | 52/54 | 6/54 | 30/54 |
| Predecir y elegir: red v2, semilla 17, típico (copiado) | 0.943 | +0.141 | 27 / 16 / 11 | 0.028 | 0.837 | 0.640 | 54/54 | 0/54 | 54/54 |
| Predecir y elegir: red v2, semilla 17, cauto (copiado) | 0.943 | +0.141 | 27 / 16 / 11 | 0.028 | 0.837 | 0.640 | 54/54 | 0/54 | 54/54 |
| Predecir y elegir: red v2, semilla 29, típico (copiado) | 0.943 | +0.141 | 26 / 17 / 11 | 0.028 | 0.837 | 0.640 | 54/54 | 0/54 | 44/54 |
| Predecir y elegir: red v2, semilla 29, cauto (copiado) | 0.942 | +0.140 | 27 / 14 / 13 | 0.029 | 0.837 | 0.640 | 54/54 | 0/54 | 54/54 |
| Predecir y elegir: red v2, semilla 43, típico (copiado) | 0.944 | +0.142 | 24 / 21 / 9 | 0.027 | 0.807 | 0.640 | 54/54 | 0/54 | 42/54 |
| Predecir y elegir: red v2, semilla 43, cauto (copiado) | 0.944 | +0.142 | 26 / 19 / 9 | 0.027 | 0.818 | 0.640 | 54/54 | 0/54 | 49/54 |
| Predecir y elegir: ELM v2, semilla 17, típico (copiado) | 0.915 | +0.113 | 22 / 19 / 13 | 0.056 | 0.757 | 0.277 | 54/54 | 2/54 | 43/54 |
| Predecir y elegir: ELM v2, semilla 17, cauto (copiado) | 0.910 | +0.108 | 24 / 15 / 15 | 0.061 | 0.759 | 0.277 | 54/54 | 2/54 | 51/54 |
| Predecir y elegir: ELM v2, semilla 29, típico (copiado) | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54/54 | 2/54 | 47/54 |
| Predecir y elegir: ELM v2, semilla 29, cauto (copiado) | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54/54 | 2/54 | 51/54 |
| Predecir y elegir: ELM v2, semilla 43, típico (copiado) | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54/54 | 2/54 | 47/54 |
| Predecir y elegir: ELM v2, semilla 43, cauto (copiado) | 0.942 | +0.140 | 26 / 15 / 13 | 0.029 | 0.837 | 0.640 | 54/54 | 0/54 | 52/54 |

Resumen de la red que recomienda entre las 3 semillas (media, mínimo y máximo de la media de lo elegido): típico 0.862 (0.816–0.915); cauto 0.849 (0.796–0.896).

### En qué casos se aparta de la regla (semilla 17, 54 casos)

La lista completa, con lo que eligió en lugar de la regla y los rendimientos de cada una, está en `recommender_eval.json` (`decision.perSeed.years2019_2024.17.*.departures`). Resumen:

| Prioridad | Regla → elegido (casos) |
|---|---|
| típico | maiz → ajonjoli: 19; frijol → ajonjoli: 4; maiz → frijol: 2; frijol → brocoli: 1; maiz → brocoli: 1; maiz → papa: 1 |
| cauto | maiz → ajonjoli: 16; maiz → brocoli: 2; frijol → ajonjoli: 1; maiz → frijol: 1; maiz → lechuga: 1 |

### Lectura, sin rodeos

- Años reservados 2022–2024 (n = 27 casos): la red que recomienda queda entre 0.828 y 0.944 de rendimiento relativo medio, frente a 0.856 de la regla y 0.979 del techo; mejora la media de la regla en 4 de las 6 combinaciones de semilla y prioridad, y tiene más casos ganados que perdidos en 3 de 6. Las políticas de predecir y elegir (red v2 y ELM v2) van de 0.917 a 0.957: la red que recomienda no alcanza a las más altas (0.957); la mejor semilla (0.944) queda dentro de su rango.
- Adicional 2019–2024 (n = 54 casos): la red que recomienda queda entre 0.796 y 0.915 de rendimiento relativo medio, frente a 0.802 de la regla y 0.971 del techo; mejora la media de la regla en 5 de las 6 combinaciones de semilla y prioridad, y tiene más casos ganados que perdidos en 6 de 6. Las políticas de predecir y elegir (red v2 y ELM v2) van de 0.910 a 0.944: la red que recomienda no alcanza a las más altas (0.944); la mejor semilla (0.915) queda dentro de su rango.
- **Cambio frente a la versión en JS (Tarea 31):** con el flujo aleatorio de la GPU la red ya **no** mejora a la regla en las seis combinaciones (en la versión en JS sí lo hacía): ver la tabla "antes y ahora" de la sección de GPU. Es una variación entre corridas del mismo diseño, no un cambio de diseño; el resultado depende de la semilla.
- Con 27 y 54 casos (muchos casi iguales entre sí porque comparten sitio y año), los conteos ganados / empatados / perdidos son descriptivos; no se calculó significancia. Las semillas difieren entre sí, así que la diferencia entre prioridades no se puede ordenar con firmeza. (Mejora en 4 de 6 con 27 casos y en 5 de 6 con 54.)

### Límites

- **El juez es nuestro simulador**: "lo mejor" es lo que el simulador califica más alto, no una cosecha medida. Un segundo juez (AquaCrop) no se aplicó a estas recomendaciones.
- **Una decisión por caso** (la pérdida a los 30, 45 o 60 días y una resiembra 14 días después); no vuelve a decidir en cada fecha.
- **Sin finanzas, plagas ni fertilizante** como entradas: no hay esos datos en el proyecto. **El margen no se calcula** (no hay precios ni costos en el juez).
- 54 y 27 casos de tres pilotos. La red que recomienda se entrenó con 2001–2016 y se validó con 2017–2018; las redes de predecir y elegir se entrenaron sin 2019–2024. El año agrícola 2025 no se puede medir (la serie termina el 2025-12-31).
- Los escenarios de entrenamiento usan arena, franco y arcilla en 17 puntos y el suelo del sitio solo en los pilotos; la prueba usa el suelo del sitio.
- El diseño (tamaños, σ, generaciones, entradas, regla) no se tocó después de ver los números de prueba.

## Contraste con decisiones documentadas de agricultores

Es descriptivo y **no ajusta nada**: pone lo que las fuentes dicen que hicieron algunos agricultores junto a lo que recomiendan la regla y la red, y a lo que el simulador dice que habría pasado. Los números salen de `web/data/historical_check.json`. Las fuentes se abrieron y se verificó cada cita (fragmentos cortos; el contexto está resumido):

- **Misión FAO/PMA de evaluación de cosecha y seguridad alimentaria en Guatemala, informe especial, 23 de febrero de 2010** (https://www.fao.org/4/ak344s/ak344s00.htm). Anexo 1, "Región Oriente (departamentos de Jalapa, Chiquimula, El Progreso, Jutiapa, Baja Verapaz, Zacapa y Quiché)", párrafo 3. Dice: "se sembró maíz también en el segundo ciclo productivo"; "perdiéndose nuevamente todas las plantaciones". Contexto de la fuente: por pérdidas en el primer ciclo y por el uso de semilla de maíz del Ministerio de Agricultura, en 2009 se sembró maíz también en el segundo ciclo; la sequía se prolongó y se perdieron de nuevo todas las plantaciones.
- **MAGA/PMA Informe SMC No. 06, junio 2023** (https://precios.maga.gob.gt/archivos/smc/2023/06%20Informe%20SMC%20-%20Junio%20-%202023.pdf). p. 10, sección de monitoreo de cultivos (PMA), región Nororiente. Dice: "han tenido que realizar resiembra". Lo dicen los agricultores entrevistados de San Juan Ermita (Chiquimula), que sembraron el ciclo de primera del 10 al 18 de mayo. El cultivo que se resembró no se indica en la frase.
- **MAGA/PMA Informe SMC No. 07, julio 2023** (https://precios.maga.gob.gt/archivos/smc/2023/07%20Informe%20SMC%20-%20Julio%20-%202023.pdf). p. 11, sección VI, región Nororiente. Dice: "del municipio de Olopa realizaron resiembra debido a las condiciones climáticas desfavorables". Dice "algunos de los agricultores entrevistados"; no indica el cultivo resembrado ni la fecha de la pérdida o de la resiembra.
- **FEWS NET, Guatemala, Perspectiva de seguridad alimentaria, febrero 2024** (https://fews.net/es/latin-america-and-caribbean/guatemala/perspectiva-de-seguridad-alimentaria/febrero-2024). sección Situación actual, producción de granos básicos 2023 (nacional). Dice: "Algunos agricultores decidieron esperar que las lluvias mejoraran"; "muchos pequeños agricultores no pudieron resembrar". Es una descripción nacional del ciclo de primera de 2023 (siembras retrasadas uno o dos meses); nombra Chiquimula solo entre los departamentos con daños por sequía. Dice que la mayoría de medianos, excedentarios y comerciales sí resembró, con "capacidades productivas" mayores (extensión, capital, mecanización). La frase "no tenían recursos" no aparece tal cual.

**Evento solo mencionado:** San Martín Jilotepeque 2026 (farmers sowed local beans after losing maize): Outside the weather data (ends 2025-12-31) and not among the sources the brief asked to open; mentioned only, not evaluated. Las otras tres fuentes se abrieron y apoyan su evento, con estas precisiones: la de 2009 habla de una siembra del *segundo ciclo*, no de una resiembra 14 días después de la pérdida; las de 2023 no dicen qué cultivo se resembró; FEWS NET habla del país (Chiquimula aparece solo entre los departamentos con daños por sequía) y no dice textualmente que faltaran recursos, solo que muchos pequeños agricultores no pudieron resembrar mientras la mayoría de medianos y comerciales sí.

### Oriente de Guatemala (departamentos de Jalapa, Chiquimula, El Progreso, Jutiapa, Baja Verapaz, Zacapa y Quiché), año agrícola 2009

**Documentado:** Tras perder el primer ciclo de maíz, los agricultores resembraron maíz en el segundo ciclo con semilla del MAGA; la sequía siguió y se perdió de nuevo todo. Resultado documentado: perdida (segunda siembra perdida). **Puntos:** El informe describe una región; se usan los puntos de nuestros 20 que llevan el nombre de departamentos citados (distancia 0 a ese punto por construcción; no hay coordenada de parcela). **Cuidado:** El "segundo ciclo" del informe es una siembra de segunda (después de la cosecha o pérdida de la primera, calendario de segunda), no una resiembra 14 días después de perder el maíz a los 30, 45 o 60 días: el calendario de la decisión de nuestro simulador no es el mismo.

| Punto (suelo), distancia | Pérdida (día) | Fecha de resiembra | Partición del año | Regla (rend.) | Red típica (rend.) | Red cauta (rend.) | Maíz resembrado (rend.) | Mejor (rend.) |
|---|---|---|---|---|---|---|---|---|
| chiquimula (site), 0 km | 30 | 2009-06-17 | train | maiz (0.995) | ajonjoli (1.000) | ajonjoli (1.000) | 0.995 | ajonjoli (1.000) |
| chiquimula (site), 0 km | 45 | 2009-07-02 | train | maiz (0.997) | ajonjoli (1.000) | ajonjoli (1.000) | 0.997 | ajonjoli (1.000) |
| chiquimula (site), 0 km | 60 | 2009-07-17 | train | maiz (0.978) | ajonjoli (0.997) | ajonjoli (0.997) | 0.978 | frijol (1.000) |
| jutiapa (site), 0 km | 30 | 2009-06-23 | train | maiz (0.460) | ajonjoli (0.822) | ajonjoli (0.822) | 0.460 | ajonjoli (0.822) |
| jutiapa (site), 0 km | 45 | 2009-07-08 | train | maiz (0.763) | frijol (0.430) | ajonjoli (0.895) | 0.763 | ajonjoli (0.895) |
| jutiapa (site), 0 km | 60 | 2009-07-23 | train | frijol (0.487) | frijol (0.487) | frijol (0.487) | 0.677 | ajonjoli (0.828) |
| zacapa (loam), 0 km | 30 | 2009-06-22 | train | maiz (1.000) | ajonjoli (1.000) | ajonjoli (1.000) | 1.000 | maiz (1.000) |
| zacapa (loam), 0 km | 45 | 2009-07-07 | train | maiz (1.000) | ajonjoli (1.000) | ajonjoli (1.000) | 1.000 | maiz (1.000) |
| zacapa (loam), 0 km | 60 | 2009-07-22 | train | frijol (1.000) | frijol (1.000) | frijol (1.000) | 1.000 | maiz (1.000) |
| jalapa (loam), 0 km | 30 | 2009-06-22 | train | maiz (0.813) | ajonjoli (0.868) | ajonjoli (0.868) | 0.813 | ajonjoli (0.868) |
| jalapa (loam), 0 km | 45 | 2009-07-07 | train | maiz (0.692) | frijol (0.755) | frijol (0.755) | 0.692 | ajonjoli (0.806) |
| jalapa (loam), 0 km | 60 | 2009-07-22 | train | frijol (0.667) | frijol (0.667) | frijol (0.667) | 0.727 | lechuga (0.790) |

### Olopa y San Juan Ermita, Chiquimula, año agrícola 2023

**Documentado:** Agricultores entrevistados de Olopa y San Juan Ermita resembraron (cultivo no indicado); en el país algunos esperaron la lluvia y muchos pequeños no pudieron resembrar (FEWS NET, nacional). Resultado documentado: sin dato en las fuentes. **Puntos:** Olopa es uno de los 20 puntos (distancia 0: el punto lleva el nombre del municipio). San Juan Ermita no tiene punto propio y no se verificó una coordenada para él. Chiquimula (departamento) se añade por ser piloto. **Cuidado:** No hay rendimiento, fechas ni cultivo por parcela. Las fuentes describen municipios o el país.

| Punto (suelo), distancia | Pérdida (día) | Fecha de resiembra | Partición del año | Regla (rend.) | Red típica (rend.) | Red cauta (rend.) | Maíz resembrado (rend.) | Mejor (rend.) |
|---|---|---|---|---|---|---|---|---|
| olopa (loam), 0 km | 30 | 2023-06-17 | not used (test years are only scored at the pilots) | maiz (1.000) | ajonjoli (1.000) | ajonjoli (1.000) | 1.000 | maiz (1.000) |
| olopa (loam), 0 km | 45 | 2023-07-02 | not used (test years are only scored at the pilots) | maiz (1.000) | ajonjoli (1.000) | ajonjoli (1.000) | 1.000 | maiz (1.000) |
| olopa (loam), 0 km | 60 | 2023-07-17 | not used (test years are only scored at the pilots) | maiz (1.000) | lechuga (1.000) | frijol (1.000) | 1.000 | maiz (1.000) |
| chiquimula (site), 25.31 km | 30 | 2023-07-30 | test | frijol (1.000) | ajonjoli (1.000) | ajonjoli (1.000) | 1.000 | maiz (1.000) |
| chiquimula (site), 25.31 km | 45 | 2023-08-14 | test | frijol (0.935) | frijol (0.935) | frijol (0.935) | 1.000 | maiz (1.000) |
| chiquimula (site), 25.31 km | 60 | 2023-08-29 | test | frijol (1.000) | frijol (1.000) | frijol (1.000) | 0.984 | frijol (1.000) |

### Qué muestra y qué no

- **No es una prueba con datos retenidos**: Illustrative, not a held-out test: 2009 is a training year at every point; 2023 is not used for training or validation (at the pilots it is a test year). Nothing is fitted to these events.
- Las fuentes describen regiones o comunidades, no una parcela; no hay rendimientos ni fechas por parcela, así que nada se calibró con estos eventos.
- **Resultado documentado de 2009** (la segunda siembra de maíz se perdió): el simulador **no lo reproduce** para el maíz resembrado a los 30, 45 o 60 días de la pérdida: su rendimiento relativo va de 0.460 a 1.000 en los cuatro puntos; es menor de 0.5 solo en jutiapa a los 30 días, y en Chiquimula y Zacapa da casi 1. El calendario tampoco es el mismo (el informe habla de una siembra del segundo ciclo, más tarde), así que la discrepancia no prueba que el simulador falle ese año, pero tampoco lo confirma. **Diagnóstico posterior (Tarea 35):** el calendario de esta tabla (resembrar 14 días después de una pérdida) no es el de la segunda siembra del informe y la lluvia de ERA5 es la más húmeda en Zacapa; con CHIRPS y la siembra de segunda de agosto a septiembre, Zacapa sí muestra 2009 entre los peores años, aunque sin pérdida total. Ver "¿Coincide el simulador con lo que pasó de verdad?", más abajo, y `web/data/diagnosis_2009.json`.
- Lo documentado en 2009 (resembrar maíz) coincide con la acción de la regla en casi todas las filas, pero el único resultado documentado es la pérdida y el simulador no la reproduce; por eso no se puede decir que la red o la regla habrían decidido mejor que los agricultores.
- Para 2023 no hay resultado documentado; solo que se resembró (cultivo no indicado). No se puede comparar con lo que el agricultor realmente sembró.

## ¿Coincide el simulador con lo que pasó de verdad?

El dueño del proyecto preguntó qué tan fiel es el simulador a la realidad. El único caso con desenlace conocido, el oriente de Guatemala en 2009 (los agricultores resembraron maíz en el segundo ciclo y lo perdieron otra vez por la sequía, ver "Contraste con decisiones documentadas de agricultores"), **no se reproducía**. Aquí se busca por qué, se corrige lo que tiene una causa justificada (la fuente de lluvia y el calendario del cultivo) y se mide la coincidencia con los eventos de sequía documentados de 2001 a 2024. **No se tocó ningún parámetro del modelo** para que 2009 saliera mal; las reglas de elección se fijaron antes de ver los resultados.

### En breve

- **2009 sigue sin reproducirse como pérdida total, pero la causa no es una sola.** Con la lluvia de CHIRPS y el calendario de segunda (siembra de agosto a septiembre), Zacapa sí muestra 2009 entre los peores años para el maíz (percentil 0.15 a 0.23 en las cuatro fechas; rendimiento relativo de 0.94 a 0.39). Con ERA5, la fuente del modelo, Zacapa sale sin estrés (1.000 el 15 de agosto). En Chiquimula el maíz de 2009 no pierde más de 0.35 en ninguna fuente ni fecha (mínimo 0.651). Ninguna combinación llega a "se perdieron todas las plantaciones" (el mínimo de maíz, salvo siembras tardías de Jutiapa que dan 0 en casi todos los años, es 0.387).
- **Eventos documentados (16 eventos, 3 sin departamento y por eso no puntuados).** Con ERA5, 144/331 (44 %) de los sitios-año de evento caen en el peor tercio de los años de su sitio, contra 25/228 (11 %) de los sitios-año que las fuentes describen como normales o buenos. AUC 0.68 contra esos años y 0.64 contra todos los demás (0.5 es no distinguir). POWER: 113/331 (34 %), AUC 0.65 y 0.56. CHIRPS (solo 8 de los 20 puntos): 51/139 (37 %), AUC 0.73 y 0.58. **La coincidencia es modesta**: mejor que el azar, lejos de reproducir los eventos.
- **Regla fijada de antemano para elegir la fuente de lluvia:** con los eventos de 2001–2016 ninguna fuente supera a ERA5 por 0.05 de AUC (ERA5 0.576, POWER 0.504, CHIRPS 0.526), así que **ERA5 se queda**. No se cambió la fuente del modelo ni se reentrenó ninguna red.
- Los eventos son reportes regionales, no parcelas; el simulador solo ve agua. Con tan pocos eventos no se afirma significancia.

### Lluvia: tres fuentes para los mismos puntos y años

Fuentes diarias 2001–2024 para los 20 puntos de `scripts/emulator/points.json`: **ERA5** (Open-Meteo, `scripts/emulator/cache`), **NASA POWER `PRECTOTCORR`** (`scripts/emulator/cache_power_app`, bajada en la Tarea 34) y **CHIRPS** v2.0 vía ClimateSERV (dataset 0, promedio de una caja de ±0.03°, servicio oficial sin cuenta ni clave; descarga con `scripts/data/fetch_chirps_node.mjs`, que hace las mismas peticiones que `fetch_rain_climateserv.py` sin necesitar Python). ClimateSERV respondió a unas 7 a 10 peticiones por minuto sin importar cuántas se lanzaran a la vez, y con unas 20 en paralelo devolvió errores HTTP 503. Dentro del tope de tiempo (unos 17 minutos en total, contando un primer intento interrumpido) se bajaron los 25 años de **8 puntos**: Chiquimula, Jutiapa, San Martín Jilotepeque, Esquipulas, Olopa, Zacapa, Asunción Mita, Jalpatagua. Los otros 12 puntos no se bajaron y quedan sin CHIRPS (null en el artefacto); una descarga a medias de Santa Catarina Mita, Jalapa y Guastatoya no se usa.

**Cobertura:** en ERA5 y POWER (20 puntos) y en CHIRPS (8 puntos) no falta ningún día de 2001-01-01 a 2025-12-31, así que no se excluyó ningún año-fuente y no se rellenó nada. Si faltara un día, el año agrícola que lo contiene (1 abr a 31 mar) queda fuera para ese sitio y fuente. Artefacto: `web/data/rain_sources.json`, por punto y fuente, por año: total anual, total mayo–octubre, total julio–agosto (la canícula) y racha seca más larga (menos de 1 mm) de junio a septiembre.

Las tres fuentes no coinciden en el nivel. Media 2001–2024 en los puntos con CHIRPS:

| Punto | ERA5 anual (mm) | POWER anual (mm) | CHIRPS anual (mm) | ERA5 may–oct (mm) | POWER may–oct (mm) | CHIRPS may–oct (mm) |
|---|---|---|---|---|---|---|
| Chiquimula | 1095 | 1542 | 1297 | 984 | 1132 | 1206 |
| Jutiapa | 1093 | 1249 | 1313 | 1014 | 1079 | 1243 |
| San Martín Jilotepeque | 1102 | 1412 | 1155 | 973 | 1233 | 1076 |
| Esquipulas | 2016 | 1391 | 1590 | 1798 | 1121 | 1457 |
| Olopa | 1706 | 1391 | 1612 | 1374 | 1121 | 1481 |
| Zacapa | 1464 | 1542 | 1024 | 1211 | 1132 | 946 |
| Asunción Mita | 612 | 1249 | 1462 | 565 | 1079 | 1372 |
| Jalpatagua | 1973 | 1352 | 1650 | 1844 | 1207 | 1560 |

En Chiquimula y Zacapa, POWER da exactamente la misma serie: ambos puntos caen en la misma celda de POWER (unos 0.5°), mientras que ERA5 y CHIRPS los distinguen.

### Por qué falla 2009

Se simuló, con el simulador existente, en secano, con el suelo del sitio (Chiquimula y Jutiapa) o franco (Zacapa), para cada fuente: **(a)** lo que hacía `historical_check`: maíz resembrado 14 días después de una pérdida a los 30, 45 y 60 días de la siembra, contados desde la regla de inicio de lluvias; **(b)** el calendario documentado: maíz de primera sembrado en la fecha de la regla de inicio (lo que se perdió primero) y maíz y frijol de segunda sembrados el 1 y 15 de agosto y el 1 y 15 de septiembre de 2009. Cada celda trae el rendimiento relativo, los días de estrés (coeficiente de estrés Ks < 0.7 durante el ciclo) y el puesto y percentil de 2009 entre los 24 años 2001–2024 del mismo sitio, fuente y calendario (puesto 1 = el peor; percentil 0 = el peor; "peor tercio" = percentil de 0.33 o menos). El ciclo termina antes del 31 de marzo en todas las celdas. Artefacto: `web/data/diagnosis_2009.json`; script `scripts/compare/diagnosis_2009.mjs`.

**La lluvia de 2009, por fuente:**

| Sitio | Fuente | Anual abr–mar (mm) | May–oct (mm) | Jul–ago (mm) | Racha seca máx. jun–sep (días) | Percentil may–oct | Percentil jul–ago | Inicio de lluvias |
|---|---|---|---|---|---|---|---|---|
| Chiquimula | ERA5 | 942.9 | 801.3 | 269.4 | 6 | 0.19 | 0.31 | 2009-05-03 |
| Chiquimula | POWER | 1253 | 940.1 | 403.2 | 6 | 0.27 | 0.60 | 2009-05-03 |
| Chiquimula | CHIRPS | 1127.2 | 1057.6 | 340.6 | 10 | 0.27 | 0.48 | 2009-05-03 |
| Jutiapa | ERA5 | 922.5 | 790.9 | 158.6 | 9 | 0.27 | 0.31 | 2009-05-09 |
| Jutiapa | POWER | 1080 | 892.2 | 366.9 | 4 | 0.23 | 0.44 | 2009-05-03 |
| Jutiapa | CHIRPS | 1148.9 | 1052 | 386.1 | 5 | 0.15 | 0.52 | 2009-05-05 |
| Zacapa | ERA5 | 1262 | 1023.5 | 354.8 | 5 | 0.15 | 0.31 | 2009-05-08 |
| Zacapa | POWER | 1253 | 940.1 | 403.2 | 6 | 0.27 | 0.60 | 2009-05-03 |
| Zacapa | CHIRPS | 837.2 | 794.6 | 238.8 | 12 | 0.27 | 0.44 | 2009-05-04 |

**Chiquimula:**

| Calendario | ERA5: rend. (días estrés; puesto de 24; percentil) | POWER: rend. (días estrés; puesto de 24; percentil) | CHIRPS: rend. (días estrés; puesto de 24; percentil) |
|---|---|---|---|
| a) Maíz resembrado tras pérdida a los 30 días (como historical_check) | 0.995 (0 d; #4; 0.15 **peor tercio**) | 1.000 (0 d; #2, 23 empatados; 0.52) | 1.000 (0 d; #1, 24 empatados; 0.50) |
| a) Maíz resembrado tras pérdida a los 45 días | 0.997 (0 d; #5; 0.19 **peor tercio**) | 1.000 (0 d; #4, 21 empatados; 0.56) | 1.000 (0 d; #5, 20 empatados; 0.58) |
| a) Maíz resembrado tras pérdida a los 60 días | 0.978 (1 d; #10; 0.40) | 0.999 (0 d; #2; 0.06 **peor tercio**) | 1.000 (0 d; #14, 11 empatados; 0.77) |
| b) Maíz de primera, siembra en la regla de inicio | 0.993 (0 d; #12; 0.48) | 1.000 (0 d; #11, 14 empatados; 0.71) | 1.000 (0 d; #14, 11 empatados; 0.77) |
| b) Maíz de segunda, siembra 1 ago | 0.988 (0 d; #11; 0.44) | 1.000 (0 d; #4, 21 empatados; 0.56) | 0.987 (1 d; #9; 0.35) |
| b) Maíz de segunda, siembra 15 ago | 0.972 (8 d; #15; 0.60) | 0.996 (0 d; #6; 0.23 **peor tercio**) | 0.904 (24 d; #9; 0.35) |
| b) Maíz de segunda, siembra 1 sep | 0.914 (28 d; #19; 0.77) | 0.963 (3 d; #7; 0.27 **peor tercio**) | 0.765 (43 d; #13; 0.52) |
| b) Maíz de segunda, siembra 15 sep | 0.789 (45 d; #19; 0.77) | 0.905 (7 d; #9; 0.35) | 0.651 (56 d; #16; 0.65) |
| b) Frijol de segunda, siembra 1 ago | 0.994 (0 d; #3; 0.10 **peor tercio**) | 0.956 (0 d; #2; 0.06 **peor tercio**) | 0.924 (1 d; #1; 0.02 **peor tercio**) |
| b) Frijol de segunda, siembra 15 ago | 0.971 (0 d; #4; 0.15 **peor tercio**) | 1.000 (0 d; #4, 21 empatados; 0.56) | 0.962 (0 d; #3; 0.10 **peor tercio**) |
| b) Frijol de segunda, siembra 1 sep | 0.917 (5 d; #4; 0.15 **peor tercio**) | 0.959 (1 d; #2; 0.06 **peor tercio**) | 0.977 (1 d; #7; 0.27 **peor tercio**) |
| b) Frijol de segunda, siembra 15 sep | 0.913 (1 d; #12; 0.48) | 0.974 (0 d; #7; 0.27 **peor tercio**) | 0.910 (8 d; #14; 0.56) |

**Jutiapa** (suelo arcilloso con poca agua disponible: el maíz rinde poco casi todos los años, y por eso 2009 no destaca):

| Calendario | ERA5: rend. (días estrés; puesto de 24; percentil) | POWER: rend. (días estrés; puesto de 24; percentil) | CHIRPS: rend. (días estrés; puesto de 24; percentil) |
|---|---|---|---|
| a) Maíz resembrado tras pérdida a los 30 días (como historical_check) | 0.460 (33 d; #4; 0.15 **peor tercio**) | 0.944 (9 d; #11; 0.44) | 0.981 (5 d; #14; 0.56) |
| a) Maíz resembrado tras pérdida a los 45 días | 0.763 (27 d; #17; 0.69) | 0.822 (14 d; #10; 0.40) | 0.923 (9 d; #17; 0.69) |
| a) Maíz resembrado tras pérdida a los 60 días | 0.677 (46 d; #18; 0.73) | 0.817 (36 d; #15; 0.60) | 0.813 (34 d; #18; 0.73) |
| b) Maíz de primera, siembra en la regla de inicio | 0.350 (44 d; #9; 0.35) | 0.993 (0 d; #12; 0.48) | 0.941 (1 d; #9; 0.35) |
| b) Maíz de segunda, siembra 1 ago | 0.405 (55 d; #5; 0.19 **peor tercio**) | 0.500 (52 d; #5; 0.19 **peor tercio**) | 0.517 (51 d; #11; 0.44) |
| b) Maíz de segunda, siembra 15 ago | 0.423 (67 d; #17; 0.69) | 0.377 (64 d; #10; 0.40) | 0.378 (70 d; #12; 0.48) |
| b) Maíz de segunda, siembra 1 sep | 0.231 (78 d; #20; 0.81) | 0.297 (79 d; #18; 0.73) | 0.205 (82 d; #17; 0.69) |
| b) Maíz de segunda, siembra 15 sep | 0.000 (92 d; #1, 20 empatados; 0.42) | 0.000 (91 d; #1, 15 empatados; 0.31 **peor tercio**) | 0.000 (92 d; #1, 19 empatados; 0.40) |
| b) Frijol de segunda, siembra 1 ago | 0.799 (11 d; #7; 0.27 **peor tercio**) | 0.620 (6 d; #1; 0.02 **peor tercio**) | 0.941 (1 d; #7; 0.27 **peor tercio**) |
| b) Frijol de segunda, siembra 15 ago | 0.730 (17 d; #6; 0.23 **peor tercio**) | 0.835 (14 d; #5; 0.19 **peor tercio**) | 0.880 (11 d; #8; 0.31 **peor tercio**) |
| b) Frijol de segunda, siembra 1 sep | 0.416 (22 d; #5; 0.19 **peor tercio**) | 0.463 (21 d; #4; 0.15 **peor tercio**) | 0.538 (19 d; #9; 0.35) |
| b) Frijol de segunda, siembra 15 sep | 0.428 (34 d; #17; 0.69) | 0.309 (38 d; #10; 0.40) | 0.281 (36 d; #11; 0.44) |

**Zacapa:**

| Calendario | ERA5: rend. (días estrés; puesto de 24; percentil) | POWER: rend. (días estrés; puesto de 24; percentil) | CHIRPS: rend. (días estrés; puesto de 24; percentil) |
|---|---|---|---|
| a) Maíz resembrado tras pérdida a los 30 días (como historical_check) | 1.000 (0 d; #2, 23 empatados; 0.52) | 1.000 (0 d; #2, 23 empatados; 0.52) | 0.867 (8 d; #2; 0.06 **peor tercio**) |
| a) Maíz resembrado tras pérdida a los 45 días | 1.000 (0 d; #3, 22 empatados; 0.54) | 1.000 (0 d; #5, 20 empatados; 0.58) | 1.000 (0 d; #9, 16 empatados; 0.67) |
| a) Maíz resembrado tras pérdida a los 60 días | 1.000 (0 d; #7, 18 empatados; 0.63) | 0.991 (0 d; #2; 0.06 **peor tercio**) | 0.988 (0 d; #12; 0.48) |
| b) Maíz de primera, siembra en la regla de inicio | 1.000 (0 d; #7, 18 empatados; 0.63) | 1.000 (0 d; #12, 13 empatados; 0.73) | 0.980 (0 d; #14; 0.56) |
| b) Maíz de segunda, siembra 1 ago | 1.000 (0 d; #6, 19 empatados; 0.60) | 0.999 (0 d; #2; 0.06 **peor tercio**) | 0.940 (14 d; #4; 0.15 **peor tercio**) |
| b) Maíz de segunda, siembra 15 ago | 1.000 (0 d; #12, 13 empatados; 0.73) | 1.000 (0 d; #7, 18 empatados; 0.63) | 0.824 (28 d; #6; 0.23 **peor tercio**) |
| b) Maíz de segunda, siembra 1 sep | 0.971 (4 d; #16; 0.65) | 0.953 (10 d; #7; 0.27 **peor tercio**) | 0.588 (46 d; #4; 0.15 **peor tercio**) |
| b) Maíz de segunda, siembra 15 sep | 0.882 (15 d; #14; 0.56) | 0.861 (17 d; #7; 0.27 **peor tercio**) | 0.387 (61 d; #5; 0.19 **peor tercio**) |
| b) Frijol de segunda, siembra 1 ago | 1.000 (0 d; #3, 22 empatados; 0.54) | 0.917 (2 d; #2; 0.06 **peor tercio**) | 0.937 (2 d; #4; 0.15 **peor tercio**) |
| b) Frijol de segunda, siembra 15 ago | 1.000 (0 d; #3, 22 empatados; 0.54) | 0.957 (0 d; #2; 0.06 **peor tercio**) | 0.913 (0 d; #4; 0.15 **peor tercio**) |
| b) Frijol de segunda, siembra 1 sep | 1.000 (0 d; #7, 18 empatados; 0.63) | 0.934 (3 d; #2; 0.06 **peor tercio**) | 0.952 (8 d; #10; 0.40) |
| b) Frijol de segunda, siembra 15 sep | 0.992 (0 d; #13; 0.52) | 0.924 (1 d; #5; 0.19 **peor tercio**) | 0.624 (25 d; #5; 0.19 **peor tercio**) |

#### Diagnóstico, sin rodeos

- **La lluvia de 2009 no es extrema en ninguna fuente.** Mayo–octubre queda en el tercio más seco de los años (percentil 0.15 a 0.27) en las nueve combinaciones sitio-fuente, pero julio–agosto no (0.31 a 0.60), y la racha seca más larga de junio a septiembre va de 4 a 12 días.
- **Con el calendario de `historical_check` el simulador no ve pérdida:** el rendimiento del maíz resembrado va de 0.460 a 1.000, y solo baja de 0.5 en Jutiapa con ERA5 a los 30 días. Resembrar en junio o julio es sembrar en plena lluvia.
- **Con el calendario documentado cambia, pero poco:** el maíz de primera da 0.98 a 1.00 en Chiquimula y Zacapa con las tres fuentes. En Jutiapa da 0.350 con ERA5, 0.993 con POWER y 0.941 con CHIRPS: con ERA5 es un año malo, pero ese maíz da una mediana de 0.49 en ese sitio (2009 queda en el percentil 0.35), no es excepcional.
- **La única combinación que muestra 2009 como año malo de segunda es Zacapa con CHIRPS:** el maíz sembrado el 1 ago, 15 ago, 1 sep y 15 sep rinde 0.940, 0.824, 0.588 y 0.387 (14 a 61 días de estrés), y 2009 queda entre los 6 peores años de 24 en las cuatro fechas. Con ERA5, el mismo sitio y fechas rinden 1.000, 1.000, 0.971 y 0.882. Con POWER, 0.999, 1.000, 0.953 y 0.861; ahí el "peor tercio" es una diferencia de centésimas, no una pérdida.
- **En Chiquimula no hay una pérdida de maíz notable con ninguna fuente:** el maíz de segunda sembrado el 15 de agosto rinde 0.972 (ERA5), 0.996 (POWER) y 0.904 (CHIRPS), con percentiles 0.60, 0.23 y 0.35; el mínimo en todas las fechas y fuentes es 0.651 (CHIRPS, 15 de septiembre, percentil 0.65: un año típico para esa fecha). POWER lo pone en el peor tercio el 15 de agosto y el 1 de septiembre, con 0.996 y 0.963, diferencias de centésimas.
- **Ninguna combinación reproduce "se perdieron todas las plantaciones".** Fuera de las siembras tardías de Jutiapa (15 de septiembre da 0 en 20, 15 y 19 de 24 años según la fuente, o sea que no es 2009), el rendimiento mínimo del maíz es 0.387.

**Veredicto:** el fallo no viene de una sola cosa. (1) **El calendario**: resembrar 14 días después de una pérdida de junio o julio no es la segunda siembra de agosto a septiembre del informe, y con la de agosto a septiembre el maíz sufre más. (2) **La fuente de lluvia**: ERA5 es la más húmeda en Zacapa en 2009 (1262 mm contra 837 mm en CHIRPS; medias de 1464 y 1024 mm) y con ella no hay estrés; con CHIRPS sí. No se probó con estaciones, así que no se sabe cuál está más cerca de lo que llovió. (3) **Ni una ni otra bastan** para reproducir una pérdida total: queda lo que este simulador no ve (plagas, semilla, calor, fertilidad, la lluvia local que las celdas de 0.05° a 0.5° no capturan) o una falta de sensibilidad del modelo a la sequía en suelos francos. No se ajustó nada para cerrar esa distancia.

### Los eventos documentados 2001–2024

Otro agente compiló, **sin ver salidas del simulador**, una tabla de eventos de sequía documentados en el Corredor Seco de Guatemala (`research_notes/eventos-sequia-documentados.json`, fuera del repositorio; el artefacto guarda su huella SHA-256 y copia las citas). Son 16 eventos y 6 años que las fuentes describen como normales o buenos (`noEventYears`). Tres eventos no nombran departamentos (E01 2001 primera, E09 2015 primera, E10 2016 primera) y no se pueden ubicar en puntos: no se puntúan, y su año queda fuera de los años de control de ese ciclo. Los eventos E05 y E06 (2014 primera) son dos fuentes del mismo evento y comparten sitios-año, y E15 (2023, Olopa) cuenta todos los puntos del departamento de Chiquimula, como pide la regla de asignación por departamento.

| Id | Año | Ciclo | Cultivo | Departamentos | Lo reportado (resumen) | Fuente | Confianza | Sitios-año puntuados | Aciertos ERA5 | Aciertos POWER | Aciertos CHIRPS |
|---|---|---|---|---|---|---|---|---|---|---|---|
| E01 | 2001 | primera | ambos | (ninguno nombrado) | Perdida de ~8 % del area sembrada de maiz y frijol en los departamentos centrales y orientales; unas 13 000 fincas de subsistencia con perdidas de al menos 80 % de los cultivos de primera en zonas localizadas; produccion de cereales 2001 prevista -9 %. | [FAO/GIEWS 2001-09-03](https://www.fao.org/4/y1913e/pays/gua0109e.htm) | media | 0 | no puntuado | no puntuado | no puntuado |
| E02 | 2009 | ambas | ambos | Chiquimula, Zacapa, El Progreso, Baja Verapaz, Jalapa, Jutiapa | Perdidas localizadas hasta 100 % en el Corredor Seco; rendimiento de maiz de primera de 20 a 4 qq/mz (~80 %); frijol de postrera esperado ~5 qq/mz frente a 20 normales (-75 %), algunos agricultores perdieron todo el frijol negro; ~10 % del area nacional de maiz perdida (calculo de la mision con sus cuadros). | [FAO/PMA 2010-02-23](https://www.fao.org/4/ak344s/ak344s00.htm) | alta | 72 | 27/72 | 19/72 | 9/28 |
| E03 | 2012 | primera | ambos | Jutiapa, El Progreso, Chiquimula, Zacapa, Baja Verapaz | Perdidas significativas, hasta 70 %, en maiz y frijol de agricultores de subsistencia e infra-subsistencia en algunas regiones de los departamentos citados. | [SESAN (Comité de Pronóstico SAN) 2012-10](https://portal.siinsan.gob.gt/wp-content/uploads/Monitoreo_y_Evaluacion/Pronostico/INFORMES 2012/a65e36ed41f8994215dda2c7af408ab6.pdf) | alta | 32 | 11/32 | 8/32 | 0/14 |
| E04 | 2013 | primera | maiz | El Progreso, Zacapa, Chiquimula, Baja Verapaz | Perdidas de 60 a 100 % de maiz de primera en agricultores pobres del Corredor Seco oriental; 87 % de los hogares afectados viven en los cuatro departamentos; segun MAGA, 31 224 hogares afectados por el periodo seco de julio-agosto. | [FEWS NET 2013-09](https://fews.net/latin-america-and-caribbean/guatemala/food-security-outlook-update/september-2013) | media | 12 | 2/12 | 5/12 | 0/4 |
| E05 | 2014 | primera | ambos | Baja Verapaz, Chiquimula, El Progreso, Jutiapa, Zacapa, Santa Rosa, Jalapa | Encuesta en 3 814 comunidades de 208 municipios: 168 278 familias con perdidas; perdidas en quintales de 80 % maiz y 63 % frijol (nivel nacional, familias de infra y subsistencia); Q450 millones. INSIVUMEH listo como mas impactados: Baja Verapaz, Chiquimula, El Progreso, Jutiapa, Zacapa, Quiche, Santa Rosa, Retalhuleu, Jalapa y Suchitepequez. | [SESAN / MAGA / INSIVUMEH 2014-08 (encuesta 1-6 agosto 2014)](https://portal.siinsan.gob.gt/wp-content/uploads/cedesan/InformeCaniculaProlongada2014_13Ago14.pdf) | alta | 38 | 25/38 | 24/38 | 8/14 |
| E06 | 2014 | primera | ambos | Chiquimula, El Progreso, Baja Verapaz, Jutiapa, Zacapa, Santa Rosa, Jalapa | Reduccion de produccion de maiz de cerca de 1.9 millones de quintales y mas de 650 mil quintales de frijol; mas de 168 mil familias; Q450 339 649. Hasta 3 decadas sin lluvia en El Progreso, Jalapa, Chiquimula y Jutiapa; acumulados de 0 a 40 % de lo normal. | [MAGA / SMC (INSIVUMEH, MARN, SESAN, FEWS NET, FAO, PMA) 2014-08](https://precios.maga.gob.gt/archivos/smc/2014/08%20Bolet%c3%adn%20SMC%20-%20Agosto%20-%202014.pdf) | alta | 38 | 25/38 | 24/38 | 8/14 |
| E07 | 2014 | postrera | ambos | Jutiapa, Chiquimula, Santa Rosa | Solo 1 664 comunidades (44 %) reportaron posibilidad de sembrar la postrera de maiz y frijol; las mayores cantidades en Jutiapa, Chiquimula y Santa Rosa; MAGA: de las comunidades afectadas con posibilidad, 44 % podria sembrar y 56 % no. | [SESAN / MAGA / INSIVUMEH 2014-08](https://portal.siinsan.gob.gt/wp-content/uploads/cedesan/InformeCaniculaProlongada2014_13Ago14.pdf) | media | 20 | 0/20 | 0/20 | 0/12 |
| E08 | 2015 | primera | maiz | Baja Verapaz, Chiquimula, El Progreso, Zacapa, Jalapa | Perdidas de 75 a 100 % del maiz de primera en productores de subsistencia del Corredor Seco occidental y oriental; deficit de lluvia de hasta 75 % bajo lo normal; en agosto deficit de hasta 95 % en departamentos del oriente y hasta 27 dias sin lluvia; mas de 70 000 hogares afectados (cifra preliminar de agosto). | [FEWS NET 2015-12](https://fews.net/latin-america-and-caribbean/guatemala/food-security-outlook-update/december-2015) | alta | 14 | 10/14 | 14/14 | 3/4 |
| E09 | 2015 | primera | ambos | (ninguno nombrado) | Fuertes perdidas de maiz y frijol para muchos productores de subsistencia del Corredor Seco centroamericano; reduccion considerable de reservas. | [FEWS NET 2016-05](https://fews.net/sites/default/files/documents/reports/AMERICA%20CENTRAL%20Informe%20Especial%20-%20sector%20cafetalero%20-%202016.pdf) | media | 0 | no puntuado | no puntuado | no puntuado |
| E10 | 2016 | primera | ambos | (ninguno nombrado) | A nivel nacional la cosecha de primera dentro de parametros normales, pero con danos en el corredor seco bajo 700 msnm y perdidas totales en algunas areas; cosecha con 15-30 dias de retraso. | [FEWS NET 2016-10](https://fews.net/latin-america-and-caribbean/guatemala/food-security-outlook/october-2016) | media | 0 | no puntuado | no puntuado | no puntuado |
| E11 | 2016 | postrera | frijol | Chiquimula, Zacapa, Jutiapa | Menores rendimientos de frijol en las areas bajas del corredor seco oriental; el oct-2016 menciona danos al frijol de postrera en Chiquimula, Zacapa y Jutiapa. | [FEWS NET 2016-11](https://fews.net/es/central-america-and-caribbean/guatemala/key-message-update/november-2016) | media | 11 | 7/11 | 1/11 | 5/7 |
| E12 | 2018 | primera | ambos | Chiquimula, Jutiapa, Zacapa, El Progreso, Jalapa | Danos importantes a mas de 291 mil familias, principalmente en los departamentos citados (tambien Huehuetenango); algunas familias reportan perdidas totales de la primera de maiz y frijol; cultivos en crecimiento vegetativo. | [MAGA / SMC 2018-08](https://precios.maga.gob.gt/archivos/smc/2018/08%20Bolet%C3%ADn%20SMC%20-%20Agosto%20-%202018.pdf) | alta | 30 | 18/30 | 22/30 | 9/14 |
| E13 | 2018 | primera | ambos | Zacapa, Chiquimula, Baja Verapaz, El Progreso, Jutiapa, Jalapa | Segun MAGA, 201 692 agricultores de subsistencia perdieron casi la totalidad de sus cultivos de primera (zona de medios de vida del oriente); reservas de maiz minimas o inexistentes; precio del maiz hasta Q170-180/qq. | [FEWS NET 2018-12](https://fews.net/es/latin-america-and-caribbean/guatemala/perspectiva-de-seguridad-alimentaria/diciembre-2018/print) | alta | 36 | 24/36 | 25/36 | 9/14 |
| E14 | 2019 | primera | ambos | El Progreso, Jutiapa, Zacapa, Chiquimula, Baja Verapaz | En el Corredor Seco perdidas de mas de 50 % y rendimientos 50 % menores a lo usual (tambien Quiche). FEWS oct-2019: perdidas ~5 % en algunas areas excedentarias; hogares pobres del este perdieron su primera por segundo ano. | [FEWS NET 2019-08](https://fews.net/latin-america-and-caribbean/guatemala/food-security-outlook-update/august-2019) | media | 32 | 21/32 | 3/32 | 4/14 |
| E15 | 2023 | primera | maiz | Chiquimula | Resiembra por condiciones climaticas desfavorables en Olopa; en la region nororiente 62.9 % de los agricultores entrevistados presento dano en maiz por gusano cogollero y principalmente sequia (101 cuerdas); en algunas comunidades mas de ocho dias consecutivos sin lluvia en Crecimiento I; las zonas mas afectadas no permitieron siembra ni resiembra. | [MAGA / SMC con datos PMA e INSIVUMEH 2023-07](https://precios.maga.gob.gt/archivos/smc/2023/07%20Informe%20SMC%20-%20Julio%20-%202023.pdf) | alta | 5 | 2/5 | 0/5 | 3/3 |
| E16 | 2023 | ambas | ambos | Baja Verapaz, Chiquimula, El Progreso, Zacapa, Jutiapa | Perdidas de maiz de primera de agricultores de subsistencia 'alrededor de 25 a 30 %' en conjunto; en diferentes regiones perdidas de frijol de 60 % a totales; siembra de primera retrasada 1-2 meses; postrera sembrada y cosechada tarde; algunos resembraron con semilla de reserva. | [FEWS NET 2024-02](https://fews.net/latin-america-and-caribbean/guatemala/food-security-outlook/february-2024) | media | 64 | 17/64 | 14/64 | 13/28 |

**Cómo se puntuó (fijado antes de ver resultados):**

- **Unidad** = un sitio-año: un punto cuyo departamento nombra el evento × año agrícola × ciclo × cultivo. Primera = siembra en la fecha de la regla de inicio de lluvias; postrera = siembra el 15 de agosto; un evento "ambas" cuenta los dos ciclos y "ambos" cultivos cuenta maíz y frijol por separado. Total: 331 unidades de evento, 228 unidades de años normales (en los mismos puntos, cultivos y ciclos) y 1330 de "otros años".
- **Valor** = rendimiento relativo del simulador (secano, suelo del sitio en los pilotos y franco en el resto) con la lluvia de cada fuente; **percentil** = rango medio entre los años usables del mismo sitio, ciclo, cultivo y fuente.
- **Acierto** = percentil de 1/3 o menos (el peor tercio de los años de ese sitio). Umbral fijo, no se cambia.
- **Separación (AUC)** = probabilidad de que una unidad de evento tenga peor percentil que una de control (empate cuenta 1/2), contra (a) los `noEventYears` y (b) todos los demás años de esos puntos sin ningún evento listado de ese ciclo y cultivo. Un AUC de 0.5 no distingue nada.
- CHIRPS solo existe en 8 puntos, así que sus unidades son menos; para comparar fuentes sobre lo mismo hay una segunda tabla con el **soporte común** (solo las unidades que las tres fuentes pueden evaluar).

**Resultados por fuente** (todas las unidades que cada fuente puede evaluar; entre paréntesis, eventos contra controles):

| Fuente | Periodo | Aciertos (peor tercio) | Falsas alarmas en noEventYears | Otros años en el peor tercio | AUC contra noEventYears | AUC contra otros años |
|---|---|---|---|---|---|---|
| ERA5 | 2001–2016 | 82/199 (41 %) | 4/38 (11 %) | 228/874 (26 %) | 0.76 (199 contra 38) | 0.61 (199 contra 874) |
| ERA5 | 2017–2024 | 62/132 (47 %) | 21/190 (11 %) | 67/456 (15 %) | 0.66 (132 contra 190) | 0.68 (132 contra 456) |
| ERA5 | todos | 144/331 (44 %) | 25/228 (11 %) | 295/1330 (22 %) | 0.68 (331 contra 228) | 0.64 (331 contra 1330) |
| POWER | 2001–2016 | 71/199 (36 %) | 0/38 (0 %) | 270/874 (31 %) | 0.79 (199 contra 38) | 0.53 (199 contra 874) |
| POWER | 2017–2024 | 42/132 (32 %) | 25/190 (13 %) | 38/456 (8 %) | 0.59 (132 contra 190) | 0.64 (132 contra 456) |
| POWER | todos | 113/331 (34 %) | 25/228 (11 %) | 308/1330 (23 %) | 0.65 (331 contra 228) | 0.56 (331 contra 1330) |
| CHIRPS | 2001–2016 | 25/83 (30 %) | 0/14 (0 %) | 112/322 (35 %) | 0.80 (83 contra 14) | 0.53 (83 contra 322) |
| CHIRPS | 2017–2024 | 26/56 (46 %) | 4/70 (6 %) | 21/168 (13 %) | 0.71 (56 contra 70) | 0.67 (56 contra 168) |
| CHIRPS | todos | 51/139 (37 %) | 4/84 (5 %) | 133/490 (27 %) | 0.73 (139 contra 84) | 0.58 (139 contra 490) |

**Sobre el soporte común** (las mismas unidades para las tres fuentes):

| Fuente | Periodo | Aciertos | AUC contra noEventYears | AUC contra otros años |
|---|---|---|---|---|
| ERA5 | 2001–2016 | 28/83 (34 %) | 0.75 (83 contra 14) | 0.58 (83 contra 322) |
| ERA5 | 2017–2024 | 23/56 (41 %) | 0.60 (56 contra 70) | 0.63 (56 contra 168) |
| ERA5 | todos | 51/139 (37 %) | 0.63 (139 contra 84) | 0.60 (139 contra 490) |
| POWER | 2001–2016 | 28/83 (34 %) | 0.77 (83 contra 14) | 0.50 (83 contra 322) |
| POWER | 2017–2024 | 17/56 (30 %) | 0.60 (56 contra 70) | 0.64 (56 contra 168) |
| POWER | todos | 45/139 (32 %) | 0.66 (139 contra 84) | 0.55 (139 contra 490) |
| CHIRPS | 2001–2016 | 25/83 (30 %) | 0.80 (83 contra 14) | 0.53 (83 contra 322) |
| CHIRPS | 2017–2024 | 26/56 (46 %) | 0.71 (56 contra 70) | 0.67 (56 contra 168) |
| CHIRPS | todos | 51/139 (37 %) | 0.73 (139 contra 84) | 0.58 (139 contra 490) |

Lectura:

- **ERA5** acierta 82/199 (41 %) en 2001–2016 y 62/132 (47 %) en 2017–2024. Las falsas alarmas (años descritos como normales que caen en el peor tercio) son 25/228 (11 %). Es mejor que el azar (que daría un tercio de aciertos y AUC 0.5) pero está lejos de reproducir los eventos: más de la mitad de los sitios-año de evento no salen entre los peores de su sitio.
- **POWER** está en el nivel del azar en aciertos (113/331 (34 %)); su AUC contra los años normales parece alto en 2001–2016 (0.79) pero se apoya en 38 controles de un solo año (2015 postrera) y contra los otros años es 0.53.
- **CHIRPS** (8 puntos) acierta 25/83 (30 %) en 2001–2016 y 26/56 (46 %) en 2017–2024. Con tan pocos puntos, vecinos entre sí y correlacionados, no se puede decir más.
- **Dónde acierta y dónde no (ERA5):** acierta sobre todo 2014 primera (25/38 sitios-año), 2015 primera maíz (10/14), 2018 primera (18/30 y 24/36) y 2019 primera (21/32). Falla en la **postrera de 2014 (0/20 con las tres fuentes)**: el reporte habla de comunidades que no pudieron sembrar la postrera (solo el 44 % pudo), y el simulador siempre siembra el 15 de agosto, así que no ve esa pérdida. También falla en 2013 primera maíz (2/12), en 2023 primera Olopa (2/5) y en 2009 (27/72).
- **Fallos de ERA5 por nombre** (puntos que no cayeron en el peor tercio, por evento, ciclo y cultivo; el detalle de las tres fuentes está en `web/data/real_events_check.json`, `misses`): 2009 primera maiz: Chiquimula, Esquipulas, Jocotán, Quetzaltepeque, Olopa, Zacapa, Gualán, Guastatoya, Rabinal, Cubulco, Monjas, Jutiapa, Asunción Mita, Jalpatagua, Santa Catarina Mita; 2009 primera frijol: Esquipulas, Olopa, Guastatoya, Salamá, Rabinal, Cubulco, Jalapa, Jutiapa, Asunción Mita, Jalpatagua, Santa Catarina Mita; 2009 postrera maiz: Chiquimula, Esquipulas, Jocotán, Quetzaltepeque, Zacapa, Gualán, Guastatoya, Sanarate, Salamá, Rabinal, Cubulco, Jalapa, Monjas, Jutiapa, Jalpatagua; 2009 postrera frijol: Olopa, Zacapa, Gualán, Jalpatagua; 2012 primera maiz: Asunción Mita, Jalpatagua, Santa Catarina Mita, Esquipulas, Olopa, Zacapa, Gualán, Salamá, Rabinal, Cubulco; 2012 primera frijol: Asunción Mita, Jalpatagua, Santa Catarina Mita, Guastatoya, Sanarate, Chiquimula, Esquipulas, Zacapa, Gualán, Rabinal, Cubulco; 2013 primera maiz: Guastatoya, Sanarate, Zacapa, Chiquimula, Esquipulas, Jocotán, Quetzaltepeque, Olopa, Salamá, Rabinal; 2014 primera maiz: Gualán; 2014 primera frijol: Salamá, Rabinal, Cubulco, Esquipulas, Quetzaltepeque, Guastatoya, Sanarate, Jutiapa, Jalpatagua, Santa Catarina Mita, Zacapa, Gualán; 2014 postrera maiz: Jutiapa, Asunción Mita, Jalpatagua, Santa Catarina Mita, Chiquimula, Esquipulas, Jocotán, Quetzaltepeque, Olopa, Cuilapa; 2014 postrera frijol: Jutiapa, Asunción Mita, Jalpatagua, Santa Catarina Mita, Chiquimula, Esquipulas, Jocotán, Quetzaltepeque, Olopa, Cuilapa; 2015 primera maiz: Esquipulas, Olopa, Gualán, Monjas; 2016 postrera frijol: Esquipulas, Zacapa, Gualán, Jalpatagua; 2018 primera maiz: Esquipulas, Olopa, Asunción Mita, Santa Catarina Mita, Zacapa, Gualán; 2018 primera frijol: Jutiapa, Asunción Mita, Jalpatagua, Santa Catarina Mita, Zacapa, Gualán; 2019 primera maiz: Jalpatagua, Gualán, Esquipulas, Olopa, Cubulco; 2019 primera frijol: Jutiapa, Asunción Mita, Jalpatagua, Zacapa, Gualán, Esquipulas; 2023 primera maiz: Chiquimula, Jocotán, Quetzaltepeque, Salamá, Rabinal, Cubulco, Guastatoya, Sanarate, Jutiapa, Asunción Mita, Santa Catarina Mita; 2023 primera frijol: Salamá, Rabinal, Cubulco, Chiquimula, Jocotán, Quetzaltepeque, Guastatoya, Sanarate, Jutiapa, Asunción Mita, Santa Catarina Mita; 2023 postrera maiz: Salamá, Rabinal, Cubulco, Chiquimula, Esquipulas, Jocotán, Quetzaltepeque, Olopa, Guastatoya, Sanarate, Zacapa, Gualán, Jutiapa, Asunción Mita, Jalpatagua, Santa Catarina Mita; 2023 postrera frijol: Salamá, Rabinal, Cubulco, Esquipulas, Olopa, Zacapa, Gualán, Jalpatagua, Santa Catarina Mita.
- **Falsas alarmas por nombre** (años descritos como normales en que el simulador pone al sitio en el peor tercio). ERA5: 2015 postrera frijol: Jocotán, Quetzaltepeque, Salamá, Asunción Mita; 2017 primera frijol: Asunción Mita; 2017 postrera maiz: Chiquimula, Esquipulas, Jocotán, Quetzaltepeque, Jutiapa, Jalpatagua, Santa Catarina Mita; 2018 postrera maiz: Esquipulas, Olopa, Zacapa, Salamá, Cubulco, Jalapa, Monjas, Cuilapa; 2018 postrera frijol: Olopa, Guastatoya, Sanarate, Jutiapa; 2020 primera frijol: Gualán. POWER: 2017 postrera maiz: Esquipulas, Jocotán, Quetzaltepeque, Olopa, Guastatoya, Sanarate, Salamá, Rabinal, Cubulco, Jalapa, Monjas, Jutiapa, Asunción Mita, Jalpatagua, Santa Catarina Mita, Cuilapa; 2018 postrera maiz: Chiquimula, Esquipulas, Jocotán, Quetzaltepeque, Olopa, Zacapa, Gualán, Guastatoya, Sanarate. CHIRPS: 2018 postrera maiz: Zacapa; 2018 postrera frijol: Chiquimula, Zacapa; 2020 primera frijol: Jutiapa.

**La regla preregistrada para elegir la fuente.** Con los eventos de 2001–2016 solamente, gana la fuente de mayor AUC y reemplaza a ERA5 solo si lo supera por al menos 0.05. Como en 2001–2016 el archivo trae un solo año normal (2015 postrera), el AUC de la regla usa los "otros años" como controles y el soporte común (esto también se fijó antes de calcular). Resultado: **ERA5 0.576, POWER 0.504, CHIRPS 0.526. ERA5 tiene el AUC más alto, así que ERA5 se queda como fuente recomendada.** Comprobación fuera de muestra con los eventos de 2017–2024 (soporte común, 56 unidades de evento): contra los otros años, ERA5 0.633, POWER 0.636, CHIRPS 0.666; contra los años normales, ERA5 0.601, POWER 0.596, CHIRPS 0.713; aciertos 23/56 (41 %), 17/56 (30 %) y 26/56 (46 %). En esos años CHIRPS queda por encima de ERA5, pero la regla no se decide con ellos, son 8 puntos y pocos eventos, y no se cambia la decisión. **No se cambió la fuente de lluvia del modelo ni se reentrenó ninguna red.** Si algún día se cambiara, habría que regenerar los paquetes de clima de los 20 puntos (`scripts/emulator/cache` y los `web/data/snapshots`), las muestras de entrenamiento del emulador y del recomendador, reentrenar las redes (emulador, recomendador, red alineada, red de la app y las de café que usen lluvia), y repetir las evaluaciones en `web/data`. Además CHIRPS solo se bajó para 8 de los 20 puntos.

**Límites de esta comparación**

- **Los eventos son reportes regionales** (departamentos, familias, área sembrada), no parcelas: cada punto de un departamento nombrado cuenta como un sitio-año aunque la pérdida haya sido local. No hay rendimientos medidos por parcela.
- **El simulador solo ve agua.** No ve plagas, semilla (incluida la entregada por el MAGA), dinero, calor ni fertilidad del suelo, ni la imposibilidad de sembrar por falta de lluvia a tiempo (caso de la postrera de 2014).
- **Pocos eventos y muy correlacionados:** los puntos vecinos comparten clima y un mismo evento aporta muchos sitios-año. Se dan conteos junto a cada tasa y no se afirma significancia.
- **Los años de control son pocos y desiguales:** la lista de años normales es corta (2015 postrera, 2017, 2018 postrera, 2019 postrera, 2020 primera), algunas entradas son regionales y las de 2017 no mencionan Guatemala; los "otros años" no están verificados como buenos.
- El percentil por rango puede marcar como "peor tercio" una diferencia de centésimas cuando casi todos los años dan 1.000.
- El año agrícola 2025 no se puede medir; la serie termina el 2025-12-31.
- CHIRPS solo cubre 8 de los 20 puntos y se comparó en esos; ERA5 y POWER cubren los 20.

**Archivos:** `web/data/rain_sources.json`, `web/data/diagnosis_2009.json`, `web/data/real_events_check.json`; scripts `scripts/data/fetch_chirps_node.mjs`, `scripts/compare/rain_sources.mjs`, `scripts/compare/diagnosis_2009.mjs`, `scripts/compare/real_events_check.mjs` y `scripts/compare/rain_sources_lib.mjs`; pruebas a mano en `tests/real_events_check.test.mjs`. Para repetir: `node scripts/compare/rain_sources.mjs && node scripts/compare/diagnosis_2009.mjs && node scripts/compare/real_events_check.mjs` (los cachés de lluvia de CHIRPS están fuera del repositorio; se bajan con `node scripts/data/fetch_chirps_node.mjs`).

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

## Café: cultivo perenne, sombra, avisos y recomendación de riego

Tarea 32. Simulador en el commit `41070c2` (más los cambios de esta tarea), 2026-11-15. Todo lo de abajo sale de `web/data/coffee_eval.json`, `web/data/coffee_recommender.json`, `web/data/coffee_sources.json` y `web/data/crops.json`. Nada cambia en los demás cultivos, redes o artefactos: una prueba fija el resultado de las cuatro rotaciones en un piloto (Jutiapa, 3 niveles de riego) y comprueba que sale igual que antes.

### Qué entró al modelo con número y fuente

| Parte | Valor | Fuente |
|---|---|---|
| Kc del café | 0.9 / 0.95 / 0.95 (suelo desnudo). Se usa un solo Kc todo el año, 0.95 (el de la etapa media). Alternativa documentada, no usada: con malezas 1.05 / 1.1 / 1.1 | FAO-56, cuadro 12 |
| Raíz y agotamiento | profundidad 1.2 m constante (rango FAO 0.9–1.5 m); p = 0.4 | FAO-56, cuadro 22 |
| Ky | ninguno (null): **FAO no da Ky para café, así que no hay estimación de rendimiento**; solo medidas de estrés hídrico | FAO-56 (el cuadro 24 no incluye café) |
| Floración | primer día entre el 15 de febrero y el 30 de abril con lluvia ≥ 10 mm, más 9 días; si no hay, 09 de mayo con la marca `noTrigger` | Anacafe (guía 2014 vía Pons; guía de variedades 2020). El 9 es el centro de "8 a 10 días"; el 9 de mayo es una convención nuestra |
| Ventanas sensibles | días 0–90 tras la floración (cuajado y expansión del fruto) y 91–120 (llenado del grano) | Anzueto, El Cafetal 44 (2016), Anacafe |
| Sombra, efecto 1 | la evaporación del suelo baja: se resta 0.52 mm/día a la demanda del lote de mayo a octubre (no por debajo de cero) y nada en la estación seca | Padovan et al. 2018 (Nicaragua, 455 m, 57 % de copa; un solo sitio): 1.98 contra 2.50 mm/día en lo húmedo, sin diferencia en lo seco |
| Sombra, efecto 2 | transpiración de los árboles sumada al uso de agua: siempreverde 0.2 mm/día todo el año; decidua 1.2 mm/día en lluvias y 0.06 en seca | Padovan et al. 2018, el mismo sitio |
| Riego | 20 mm; efecto medido en los 30 días siguientes | Duarte-Canales et al. 2016 (Carazo, Nicaragua; una finca): la única lámina con ensayo centroamericano en las notas |

Todos los textos y enlaces están en `web/data/coffee_sources.json`. Entrada "sombra": `shade` ∈ {ninguna, árboles} y `treeType` ∈ {siempreverde, decidua}. No se cambia el Kc del café por la sombra ni se modela temperatura (no hay número con fuente para ninguna de las dos cosas).

### Lo que solo se registra, sin número en el modelo

- Fracción de sombra óptima: la nota solo trae citas secundarias o resultados de buscador (48–55 % sin penalidad); no se usa. Anacafe da un indicador de campo (al menos 8 nudos productivos en la primera bandola), no un porcentaje.
- Efecto de la sombra sobre la temperatura del aire o de la hoja y sobre la intercepción de lluvia: las fuentes no se pudieron abrir o no dan número.
- Ky del café, pérdida porcentual por déficit en el llenado del fruto, bienalidad, umbral de humedad para abonar en mm: no encontrados.
- Lluvia de más de 40 mm en floración y la frase sobre pérdida de rendimiento: sin verificar, no se usa.
- Umbrales de plaga con porcentaje de daño: no existen en las fuentes leídas; por eso los avisos no predicen ni dan porcentajes.

### Avisos con fuente (funciones puras en `web/js/model/coffee.js`)

Cada aviso devuelve su nivel, los números que lo activaron, la clave de su fuente y su confianza. El "normal" del sitio es la mediana del mes calendario en los años anteriores al de hoy.

| Aviso | Condición | Fuente y confianza |
|---|---|---|
| Roya, "condiciones favorables" | de junio a diciembre, media de los últimos 14 días entre 21 y 25 °C y rango diurno (tmax − tmin) menor que la mediana del sitio para ese mes. Añade "los síntomas aparecerían en unas 5 semanas" (latencia 31–37 días) | Avelino et al. 2015; latencia, Anacafe/Cedicafe 2015. Media-alta: correlación de campo, no un modelo |
| Roya, "posible" | de junio a diciembre, media de 14 días entre 16 y 28 °C sin cumplir lo anterior | Anacafe/Cedicafe 2015. Orientativa |
| Minador, "condiciones probables" | últimos 28 días con lluvia total menor que 10 mm y tmax media sobre la mediana del mes del sitio | Costa Rica 2019 y Anacafe ENOS 2026 a favor; Chiapas en contra: por eso "probable". Baja-media |
| Antracnosis | Ks < 1 en más de la mitad de los últimos 28 días, o un aviso de roya "favorable" en los 60 días previos | "Referencia de una finca (Patulul)". Baja-media |
| Abono | "abonar ahora" solo en mayo–junio, agosto–septiembre u octubre–noviembre y con suelo húmedo (agotamiento menor que la lámina fácilmente disponible y al menos 10 mm de lluvia en 7 días); si no, "abono en espera: suelo seco" | Ventanas y frase de Anacafe; la regla de humedad es una convención nuestra |

Una prueba por aviso fija cada umbral con casos hechos a mano y comprueba que alterar los datos posteriores a hoy no cambia nada. Los avisos no se evalúan contra lo ocurrido en fincas (no hay datos de parcela); solo se comprueba que cumplen la regla.

### Medidas de estrés por año cafetalero, con y sin sombra

Año cafetalero Y = del 1 de noviembre de Y al 31 de octubre de Y+1 (la floración cae en febrero–mayo de Y+1). Sin lluvia disparadora entre el 15 de febrero y el 30 de abril, la floración se fija el 9 de mayo y se marca: pasó en 100 de 240 años de sitio y suelo franco (42 %). Medias sobre los 10 sitios, 3 suelos y 24 años (n = 720 por fila); días con Ks < 1 y ETa/ETc:

| Sombra | Días con estrés, cuajado (0–90 d) | ETa/ETc cuajado | Días con estrés, llenado (91–120 d) | ETa/ETc llenado | Días con estrés, estación seca (nov–abr) | ETa/ETc seca |
|---|---|---|---|---|---|---|
| ninguna | 41.3 | 0.741 | 6.6 | 0.934 | 153.9 | 0.334 |
| árboles siempreverdes | 39.3 | 0.742 | 5.3 | 0.951 | 155.0 | 0.323 |
| árboles deciduos | 46.0 | 0.725 | 9.6 | 0.893 | 157.3 | 0.319 |

Con los dos efectos de Padovan, la sombra siempreverde baja un poco el estrés en lluvias y la decidua lo sube (su transpiración de 1.2 mm/día pesa más que los 0.52 mm/día que ahorra). En la estación seca la sombra no cambia nada de importancia, porque ahí solo suma la transpiración de los árboles. Son efectos de un solo sitio de Nicaragua trasladados a Guatemala; no son una medida de campo.

### Sitios de café

Los puntos de `scripts/emulator/points.json` con `siteElevation` ≥ 900 m (10 de 20). Temperatura media de la serie 2001–2025 contra el óptimo del arábica, 18–21 °C (DaMatta et al. 2007, en las notas):

| Sitio | Altitud (m) | Temperatura media (°C) | ¿En 18–21 °C? | Lluvia (mm/año) |
|---|---|---|---|---|
| San Martín Jilotepeque | 1787 | 17.6 | no, más frío | 1096 |
| Jalapa | 1374 | 20.1 | sí | 1056 |
| Olopa | 1240 | 20.7 | sí | 1706 |
| Cubulco | 997 | 22.8 | no, más cálido | 1100 |
| Rabinal | 967 | 23.0 | no, más cálido | 819 |
| Monjas | 961 | 22.8 | no, más cálido | 1418 |
| Salamá | 946 | 23.1 | no, más cálido | 1111 |
| Esquipulas | 933 | 22.7 | no, más cálido | 2017 |
| Cuilapa | 929 | 23.0 | no, más cálido | 1776 |
| Jutiapa | 903 | 23.1 | no, más cálido | 1089 |

Solo Olopa y Jalapa caen dentro del óptimo. Los demás están más cálidos (arriba de 21 °C) o, en el caso de San Martín Jilotepeque, más fríos. **La mayoría de los puntos del Corredor Seco son tierra donde el café no es lo habitual**; sirven para probar el método, no para decir dónde sembrar café.

### La recomendación de riego

**Decisión.** A 30, 60, 90 días de la floración: regar 20 mm ahora o no. Las dos acciones se simulan desde el mismo estado y se puntúan en los 30 días siguientes. Verdad = días de estrés (Ks < 1) sin riego menos con riego (`stressDaysAvoided`). Utilidad de regar = evitados − precio; de no regar = 0. Precio: 3 días de estrés con la prioridad "ahorrar agua y trabajo" y 1 día con "proteger el cultivo". El monto de 20 mm y el precio son convenciones.

**Casos.** Un caso = sitio × suelo (arena, franco, arcilla) × año cafetalero × día de decisión × configuración de sombra (ninguna, siempreverde, decidua). Entrenamiento 2001–2016 (4320 casos), validación 2017–2018 (540), prueba 2019–2024 (1620); subconjunto reservado 2022–2024 (810). Los casos con distinta sombra o suelo del mismo sitio y año comparten el clima, así que no son independientes. Entradas del día de la decisión (16): daysSinceFlowering, doy, rain7, et0_7, rain28, et0_28, rainSinceNov1, et0SinceNov1, dryspell28, tmean28, tmaxMax28, runningDepletion, soilAWmm, elevation, shadeTrees, deciduous; más la prioridad. Una prueba corrompe los datos posteriores al día de la decisión y comprueba que nada cambia.

**Balance corrido de la regla.** D = 0 el 1 de noviembre (suelo a capacidad de campo) y cada día D ← mín(TAW, máx(0, D + 0.95·ET₀ − lluvia)); sin escorrentía, sin sombra, sin riego pasado. **La regla** riega si D > p·TAW con p = 0.40 (FAO-56).

**Políticas.** (1) la regla; (2) la red que recomienda, embudo 18 → 64 → 32 → 16 → 1, puntaje = regla + tanh(corrección) con la capa de salida en cero (al inicio recomienda exactamente la regla), entrenada por estrategia de evolución sin retropropagación (población 32, 8 padres, σ 0.05, elitismo 1, 150 generaciones, 512 escenarios por generación, mejor punto de validación); (3) predecir y luego elegir: una red embudo 16 → 64 → 32 → 16 → 1 entrenada con retropropagación en PyTorch y un ELM (1500 ocultas, escala 0.1, λ 0.1) predicen `stressDaysAvoided`; se riega si la predicción supera el precio; (4) el oráculo (riega si evitados > precio). Se añaden "nunca regar" y "siempre regar" como referencias. Semillas 17, 29 y 43.

**Flujo aleatorio.** La red que recomienda se entrenó con la estrategia de evolución escrita en PyTorch en GPU (`scripts/coffee/train_es.py`, NVIDIA GeForce RTX 4050 Laptop GPU). Su flujo aleatorio es el generador CUDA de torch con las semillas 17, 29 y 43, no el mulberry32 de la versión en JS: el diseño y las distribuciones son los mismos, los números no. El ELM se ajustó en JS (no en GPU).

#### Prueba 2019–2024, todas las configuraciones (n = 1620)

Prioridad "ahorrar agua y trabajo" (precio 3 días de estrés). Sin riego quedan en promedio 6.29 días de estrés en los 30 días.

| Política | Utilidad media | Ganancia sobre la regla (ganados/empates/perdidos) | Arrepentimiento | Riegos desperdiciados | Riegos necesarios omitidos | Días de estrés que quedan | Riegos | Se aparta de la regla |
|---|---|---|---|---|---|---|---|---|
| regla | 0.036 | 0.000 (0/1620/0) | 1.009 | 70 % (444/633) | 35 % (104/293) | 5.08 | 633 | 0 |
| nunca regar | 0.000 | -0.036 (400/1031/189) | 1.046 | — (0/0) | 100 % (293/293) | 6.29 | 0 | 633 |
| siempre regar | -1.110 | -1.147 (104/642/874) | 2.156 | 82 % (1327/1620) | 0 % (0/293) | 4.40 | 1620 | 987 |
| oráculo | 1.046 | 1.009 (504/1116/0) | 0.000 | 0 % (0/293) | 0 % (0/293) | 4.70 | 293 | 548 |
| red que recomienda, semilla 17 | 0.155 | 0.119 (69/1491/60) | 0.891 | 68 % (470/694) | 24 % (69/293) | 4.85 | 694 | 131 |
| red que recomienda, semilla 29 | 0.118 | 0.081 (108/1478/34) | 0.928 | 68 % (330/486) | 47 % (137/293) | 5.27 | 486 | 149 |
| red que recomienda, semilla 43 | 0.032 | -0.004 (7/1591/22) | 1.014 | 71 % (464/658) | 34 % (99/293) | 5.04 | 658 | 29 |
| predecir y elegir, MLP, semilla 17 | 0.479 | 0.443 (267/1251/102) | 0.567 | 58 % (302/517) | 27 % (78/293) | 4.85 | 517 | 382 |
| predecir y elegir, MLP, semilla 29 | 0.523 | 0.487 (313/1195/112) | 0.522 | 55 % (253/457) | 30 % (89/293) | 4.92 | 457 | 440 |
| predecir y elegir, MLP, semilla 43 | 0.420 | 0.383 (297/1218/105) | 0.626 | 56 % (198/355) | 46 % (136/293) | 5.21 | 355 | 430 |
| predecir y elegir, ELM, semilla 17 | 0.275 | 0.239 (221/1224/175) | 0.770 | 66 % (409/618) | 29 % (84/293) | 4.87 | 618 | 413 |
| predecir y elegir, ELM, semilla 29 | 0.256 | 0.219 (220/1225/175) | 0.790 | 67 % (411/618) | 29 % (86/293) | 4.89 | 618 | 409 |
| predecir y elegir, ELM, semilla 43 | 0.307 | 0.270 (230/1226/164) | 0.739 | 65 % (393/604) | 28 % (82/293) | 4.87 | 604 | 411 |

Prioridad "proteger el cultivo" (precio 1 día de estrés).

| Política | Utilidad media | Ganancia sobre la regla (ganados/empates/perdidos) | Arrepentimiento | Riegos desperdiciados | Riegos necesarios omitidos | Días de estrés que quedan | Riegos | Se aparta de la regla |
|---|---|---|---|---|---|---|---|---|
| regla | 0.818 | 0.000 (0/1620/0) | 0.720 | 49 % (312/633) | 29 % (130/451) | 5.08 | 633 | 0 |
| nunca regar | 0.000 | -0.818 (213/1086/321) | 1.538 | — (0/0) | 100 % (451/451) | 6.29 | 0 | 633 |
| siempre regar | 0.890 | 0.072 (130/653/837) | 0.648 | 72 % (1169/1620) | 0 % (0/451) | 4.40 | 1620 | 987 |
| oráculo | 1.538 | 0.720 (343/1277/0) | 0.000 | 0 % (0/451) | 0 % (0/451) | 4.48 | 451 | 442 |
| red que recomienda, semilla 17 | 1.104 | 0.286 (77/1414/129) | 0.434 | 53 % (436/826) | 14 % (61/451) | 4.68 | 826 | 219 |
| red que recomienda, semilla 29 | 0.785 | -0.033 (36/1564/20) | 0.753 | 47 % (266/567) | 33 % (150/451) | 5.16 | 567 | 66 |
| red que recomienda, semilla 43 | 0.864 | 0.046 (11/1600/9) | 0.674 | 49 % (320/651) | 27 % (120/451) | 5.03 | 651 | 20 |
| predecir y elegir, MLP, semilla 17 | 1.276 | 0.458 (152/1329/139) | 0.262 | 49 % (407/826) | 7 % (32/451) | 4.51 | 826 | 305 |
| predecir y elegir, MLP, semilla 29 | 1.223 | 0.405 (177/1286/157) | 0.315 | 48 % (352/739) | 14 % (64/451) | 4.61 | 739 | 360 |
| predecir y elegir, MLP, semilla 43 | 1.022 | 0.204 (139/855/626) | 0.515 | 68 % (940/1386) | 1 % (5/451) | 4.41 | 1386 | 785 |
| predecir y elegir, ELM, semilla 17 | 1.142 | 0.324 (156/1107/357) | 0.396 | 60 % (626/1048) | 6 % (29/451) | 4.50 | 1048 | 533 |
| predecir y elegir, ELM, semilla 29 | 1.178 | 0.360 (158/1127/335) | 0.360 | 59 % (609/1038) | 5 % (22/451) | 4.47 | 1038 | 511 |
| predecir y elegir, ELM, semilla 43 | 1.136 | 0.318 (163/1094/363) | 0.402 | 60 % (621/1040) | 7 % (32/451) | 4.51 | 1040 | 545 |

"Riegos desperdiciados" = riegos recomendados que evitaron menos días que el precio (o los mismos). "Omitidos" = casos en que el oráculo riega y la política no. Conteos entre paréntesis; no se hace ninguna afirmación de significancia.

#### Subconjunto reservado 2022–2024 (n = 810), todas las configuraciones

Prioridad "ahorrar agua y trabajo".

| Política | Utilidad media | Ganancia sobre la regla (ganados/empates/perdidos) | Arrepentimiento | Riegos desperdiciados | Riegos necesarios omitidos | Días de estrés que quedan | Riegos | Se aparta de la regla |
|---|---|---|---|---|---|---|---|---|
| regla | -0.177 | 0.000 (0/810/0) | 1.288 | 76 % (301/396) | 39 % (60/155) | 6.92 | 396 | 0 |
| nunca regar | 0.000 | 0.177 (264/451/95) | 1.111 | — (0/0) | 100 % (155/155) | 8.21 | 0 | 396 |
| siempre regar | -0.943 | -0.767 (60/400/350) | 2.054 | 81 % (655/810) | 0 % (0/155) | 6.16 | 810 | 414 |
| oráculo | 1.111 | 1.288 (324/486/0) | 0.000 | 0 % (0/155) | 0 % (0/155) | 6.53 | 155 | 361 |
| red que recomienda, semilla 17 | -0.059 | 0.117 (35/747/28) | 1.170 | 74 % (311/423) | 28 % (43/155) | 6.71 | 423 | 65 |
| red que recomienda, semilla 29 | 0.011 | 0.188 (74/720/16) | 1.100 | 74 % (223/303) | 48 % (75/155) | 7.08 | 303 | 95 |
| red que recomienda, semilla 43 | -0.200 | -0.023 (3/790/17) | 1.311 | 77 % (316/412) | 38 % (59/155) | 6.89 | 412 | 20 |
| predecir y elegir, MLP, semilla 17 | 0.520 | 0.696 (175/603/32) | 0.591 | 60 % (174/289) | 26 % (40/155) | 6.62 | 289 | 217 |
| predecir y elegir, MLP, semilla 29 | 0.565 | 0.742 (203/568/39) | 0.546 | 58 % (137/238) | 35 % (54/155) | 6.77 | 238 | 254 |
| predecir y elegir, MLP, semilla 43 | 0.415 | 0.591 (197/564/49) | 0.696 | 60 % (118/198) | 48 % (75/155) | 7.07 | 198 | 272 |
| predecir y elegir, ELM, semilla 17 | 0.381 | 0.558 (145/624/41) | 0.730 | 65 % (203/314) | 28 % (44/155) | 6.67 | 314 | 200 |
| predecir y elegir, ELM, semilla 29 | 0.351 | 0.527 (144/624/42) | 0.760 | 65 % (207/318) | 28 % (44/155) | 6.69 | 318 | 198 |
| predecir y elegir, ELM, semilla 43 | 0.383 | 0.559 (152/613/45) | 0.728 | 64 % (203/315) | 28 % (43/155) | 6.67 | 315 | 211 |

Prioridad "proteger el cultivo".

| Política | Utilidad media | Ganancia sobre la regla (ganados/empates/perdidos) | Arrepentimiento | Riegos desperdiciados | Riegos necesarios omitidos | Días de estrés que quedan | Riegos | Se aparta de la regla |
|---|---|---|---|---|---|---|---|---|
| regla | 0.801 | 0.000 (0/810/0) | 0.860 | 54 % (214/396) | 27 % (68/250) | 6.92 | 396 | 0 |
| nunca regar | 0.000 | -0.801 (150/478/182) | 1.662 | — (0/0) | 100 % (250/250) | 8.21 | 0 | 396 |
| siempre regar | 1.057 | 0.256 (68/402/340) | 0.605 | 69 % (560/810) | 0 % (0/250) | 6.16 | 810 | 414 |
| oráculo | 1.662 | 0.860 (218/592/0) | 0.000 | 0 % (0/250) | 0 % (0/250) | 6.24 | 250 | 282 |
| red que recomienda, semilla 17 | 1.168 | 0.367 (44/713/53) | 0.494 | 54 % (260/480) | 12 % (30/250) | 6.45 | 480 | 102 |
| red que recomienda, semilla 29 | 0.775 | -0.026 (26/770/14) | 0.886 | 52 % (181/349) | 33 % (82/250) | 7.01 | 349 | 47 |
| red que recomienda, semilla 43 | 0.817 | 0.016 (3/801/6) | 0.844 | 54 % (219/403) | 26 % (66/250) | 6.90 | 403 | 9 |
| predecir y elegir, MLP, semilla 17 | 1.393 | 0.591 (97/669/44) | 0.269 | 48 % (220/460) | 4 % (10/250) | 6.25 | 460 | 146 |
| predecir y elegir, MLP, semilla 29 | 1.367 | 0.565 (117/645/48) | 0.295 | 45 % (184/411) | 9 % (23/250) | 6.34 | 411 | 175 |
| predecir y elegir, MLP, semilla 43 | 1.173 | 0.372 (79/474/257) | 0.489 | 65 % (463/712) | 0 % (1/250) | 6.16 | 712 | 344 |
| predecir y elegir, ELM, semilla 17 | 1.302 | 0.501 (93/581/136) | 0.359 | 57 % (316/557) | 4 % (9/250) | 6.22 | 557 | 237 |
| predecir y elegir, ELM, semilla 29 | 1.363 | 0.562 (97/598/115) | 0.299 | 55 % (295/539) | 2 % (6/250) | 6.19 | 539 | 219 |
| predecir y elegir, ELM, semilla 43 | 1.309 | 0.507 (104/566/140) | 0.353 | 56 % (309/549) | 4 % (10/250) | 6.23 | 549 | 253 |

#### Con y sin sombra (prueba 2019–2024), media de las tres semillas

| Política | Prioridad | Sin sombra: utilidad (ganancia sobre la regla) | Con árboles: utilidad (ganancia sobre la regla) |
|---|---|---|---|
| regla | ahorrar | 0.096 (0) | 0.006 (0) |
| oráculo | ahorrar | 0.943 (0.846) | 1.097 (1.091) |
| red que recomienda | ahorrar | 0.123 (0.027) | 0.091 (0.085) |
| predecir y elegir, MLP | ahorrar | 0.419 (0.322) | 0.502 (0.495) |
| predecir y elegir, ELM | ahorrar | 0.199 (0.103) | 0.319 (0.313) |
| regla | proteger | 0.878 (0) | 0.788 (0) |
| oráculo | proteger | 1.411 (0.533) | 1.601 (0.813) |
| red que recomienda | proteger | 0.917 (0.040) | 0.917 (0.129) |
| predecir y elegir, MLP | proteger | 1.066 (0.188) | 1.227 (0.440) |
| predecir y elegir, ELM | proteger | 1.010 (0.132) | 1.223 (0.435) |

Sin sombra 540 casos de prueba; con árboles 1080 (siempreverde y decidua juntas; por separado están en `coffee_eval.json`, grupos `evergreen` y `deciduous`).

#### Regresión de predecir y luego elegir (días de estrés evitados)

| Red | Semilla | R² validación 2017–2018 | R² prueba 2019–2024 | R² 2022–2024 | RMSE prueba (días) |
|---|---|---|---|---|---|
| MLP embudo | 17 | 0.125 | 0.277 | 0.250 | 3.21 |
| MLP embudo | 29 | 0.152 | 0.240 | 0.246 | 3.29 |
| MLP embudo | 43 | 0.047 | 0.165 | 0.143 | 3.45 |
| ELM | 17 | -0.038 | 0.096 | 0.136 | 3.59 |
| ELM | 29 | -0.022 | 0.084 | 0.148 | 3.61 |
| ELM | 43 | -0.020 | 0.097 | 0.137 | 3.59 |

#### Tiempos

| Qué | Tiempo | Evaluaciones de escenario por segundo |
|---|---|---|
| Evolución en GPU, semilla 17 (150 generaciones) | 1.7 s | 2,966,694 |
| Evolución en GPU, semilla 29 (150 generaciones) | 1.5 s | 3,246,666 |
| Evolución en GPU, semilla 43 (150 generaciones) | 1.5 s | 3,221,983 |
| Evolución en JS (recommender.js), medida con 5 generaciones y proyectada a 150 | 76 s | 64,619 |
| Predecir y elegir, MLP, semilla 17 (GPU) | 0.9 s (22 épocas) | |
| Predecir y elegir, MLP, semilla 29 (GPU) | 1.0 s (31 épocas) | |
| Predecir y elegir, MLP, semilla 43 (GPU) | 0.4 s (13 épocas) | |
| Predecir y elegir, ELM, semilla 17 (JS) | 8.3 s | |
| Predecir y elegir, ELM, semilla 29 (JS) | 8.3 s | |
| Predecir y elegir, ELM, semilla 43 (JS) | 11.1 s | |
| Una recomendación de la red (4 filas, JS) | 0.020 ms | |

La versión por lotes en GPU evalúa los 32 individuos en los 512 escenarios, con las dos prioridades y las dos acciones, en una sola operación por generación: unas 46 veces más evaluaciones por segundo que el JS en un hilo (misma tabla, mismo diseño). Equipo: NVIDIA GeForce RTX 4050 Laptop GPU, PyTorch 2.11.0+cu128.
Comprobación cruzada: el pase hacia adelante en JS y en PyTorch dan los mismos puntajes (diferencia máxima 2.6e-15) y la misma recomendación en 1290 de 1290 filas muestreadas (3 semillas).

#### Lectura, sin rodeos

- **La regla no es superada de forma consistente por la red que recomienda.** Ganancia media sobre la regla en la prueba: 0.065 (de -0.004 a 0.119) con precio 3 y 0.099 (de -0.033 a 0.286) con precio 1 (media y rango de las tres semillas). No todas las semillas ganan con precio 3 y no todas ganan con precio 1. La red se aparta de la regla en pocos casos (103 (de 29 a 149) de 1620 con precio 3): con el diseño fijado de antemano (150 generaciones, nada ajustado tras ver la prueba) la evolución encontró poco que corregir en la regla.
- **Predecir y luego elegir gana más que la red evolutiva** en este problema: MLP 0.438 (de 0.383 a 0.487) y ELM 0.243 (de 0.219 a 0.270) con precio 3; MLP 0.356 (de 0.204 a 0.458) y ELM 0.334 (de 0.318 a 0.360) con precio 1. El MLP supera a la red evolutiva de su misma semilla en las dos prioridades. Una explicación posible es que la red evolutiva parte de la regla y muta a ciegas mientras que la regresión usa la verdad numérica de cada caso; no se probó.
- **Nadie alcanza al oráculo:** ganancia del oráculo sobre la regla 1.009 (precio 3) y 0.720 (precio 1). La mejor semilla de predecir y elegir con MLP deja un arrepentimiento de 0.522 con precio 3.
- **Regar de más es lo común:** con precio 3 la regla riega 633 veces y 70 % (444/633) de esos riegos evitaron 3 días de estrés o menos; 35 % (104/293) de los riegos necesarios se omiten. "Siempre regar" tiene utilidad media -1.110 con precio 3 y 0.890 con precio 1, que es **mayor que la de la regla (0.818)**: con el precio bajo, la regla es peor que regar siempre.
- **Regresión débil.** R² en años nuevos (prueba): MLP 0.277, 0.240, 0.165 y ELM 0.096, 0.084, 0.097 (semillas 17, 29, 43). Predicen mal el valor exacto de los días evitados; elegir con el precio funciona mejor que predecir el valor. En validación 2017–2018 el R² es menor aún (0.125, 0.152, 0.047 para el MLP). No hay compuerta de R² para esta tarea.
- **Sombra.** En el estrés por año (tabla de arriba) la sombra siempreverde cambia poco y la decidua lo empeora en lluvias. En la decisión de riego, con precio 3 el oráculo gana 0.846 sobre la regla sin sombra y 1.091 con árboles; la red evolutiva gana 0.027 sin sombra y 0.085 con árboles, y el MLP 0.322 y 0.495. La regla no sabe de la sombra; que las políticas con la sombra como entrada ganen más o menos con ella no demuestra un efecto real de la sombra, solo cómo reacciona nuestro simulador a los dos efectos de un solo sitio.

#### Límites

- **No hay rendimiento de café.** FAO no da Ky para café; las medidas son días de estrés y ETa/ETc, no kilos. Un día de estrés evitado no se traduce a dinero ni a cosecha.
- **Los efectos de la sombra vienen de un solo sitio de Nicaragua** (Padovan et al. 2018, 455 m, 57 % de copa, dos especies de árbol). No hay efecto de temperatura ni del Kc.
- **El juez es nuestro simulador.** "Mejor riego" quiere decir "evita más días con Ks < 1 en el simulador", no "da más cosecha". El simulador no se ha comparado con un balance medido en una finca.
- **Casi todos los puntos del Corredor Seco no son tierra de café** (tabla de sitios): el análisis prueba el método con clima de esos puntos, no dice dónde sembrar café.
- **No hay datos de parcelas** de café en Guatemala (manejo, plagas, rendimiento) para validar nada de esto. Los avisos solo se comprueban contra la regla escrita.
- **Las plagas son avisos, no predicciones.** No hay umbral ni porcentaje de daño con fuente; el aviso de minador es "probable" porque la evidencia se contradice, y el de antracnosis se apoya en una finca de Patulul.
- **Convenciones nuestras:** la lámina de 20 mm (una finca, Nicaragua), el precio de 3 y 1 días de estrés, los días 30/60/90, el 9 de mayo sin lluvia disparadora (100 de 240 años de franco sin disparo), el Kc de 0.95 todo el año, el balance corrido desde el 1 de noviembre con suelo lleno, el año cafetalero del 1 de noviembre al 31 de octubre y que el estado del lote es la historia sin riegos pasados.
- **Los casos no son independientes** (mismo clima en los tres suelos y las tres configuraciones de sombra) y los sitios de entrenamiento y prueba son los mismos: la prueba separa años, no sitios.
- **La red evolutiva se entrenó en GPU con otro flujo aleatorio** que el de la versión en JS; solo se comprobó que el pase hacia adelante coincide, no que un entrenamiento en JS daría los mismos pesos.

Comandos para reproducir el café:

```
node scripts/coffee/scenarios.mjs                                  # tabla de escenarios (1 s)
C:/Users/velas/venv_lab4/Scripts/python.exe scripts/coffee/train_es.py          # red que recomienda, 3 semillas, GPU
PYTHONPATH=scripts/emulator C:/Users/velas/venv_lab4/Scripts/python.exe scripts/coffee/ptc_mlp.py   # predecir y elegir, MLP, 3 semillas, GPU
node scripts/coffee/bench_js.mjs 5 17                             # velocidad de la evolución en JS
node scripts/coffee/evaluate.mjs                                  # ELM, métricas y artefactos
```

## Entrenamiento en GPU y más datos y entradas

15 de noviembre de 2026 (Tarea 33). Tres cosas: (1) el entrenamiento que faltaba pasó a lotes en la GPU; (2) con ello se reentrenó el recomendador de pérdida de cultivo y se midió cuánto cambia; (3) se probó si **más datos y más entradas** mejoran el emulador de siete cultivos (v2), juzgando solo con validación. Todos los números salen de artefactos: `web/data/recommender_eval.json`, `web/data/gpu_checks.json`, `web/data/aligned_eval.json` y `aligned_eval_v3.json`, `web/data/coffee_eval.json`, `scripts/emulator/v2_screening.json`. Seeds 17, 29 y 43; las condiciones son las de `proyecto/condiciones-comunes.md` (entrenamiento 2001–2016, validación 2017–2018, prueba 2019–2024 y puntos reservados); ninguna fila de prueba se usó para elegir nada y la prueba se evaluó una sola vez.

### 1. Entrenamiento por lotes en GPU

- **Núcleo compartido** `scripts/gpu/es_core.py`: la estrategia de evolución del café (Tarea 32), generalizada. Una generación evalúa los 32 individuos sobre 512 escenarios en una sola operación por lotes (pesos apilados, `bmm`), sin bucles de Python por individuo ni por escenario y sin `.item()` dentro de la generación. Lo usan el café (`scripts/coffee/train_es.py`, ya refactorizado: los pesos de las tres semillas salen idénticos a los de la Tarea 32, `coffee_recommender.json` no cambió) y el recomendador de pérdida de cultivo (`scripts/gpu/train_recommender.py`; el JS `scripts/compare/train_recommender.mjs` arma la tabla, evalúa y escribe los artefactos, y su entrenamiento en JS se conserva como referencia). Mismo diseño: población 32, 8 padres, σ 0.05, elitismo 1, 150 generaciones, 512 escenarios compartidos, las dos prioridades, mejor punto de control en validación, semillas 17/29/43, mismo formato de `recommender_mlp.json`. **El flujo aleatorio es el de torch (CUDA), no el de mulberry32 de JS: los números se mueven** (abajo).
- **Comprobación JS contra PyTorch** (puntajes de las 8 acciones con la regla, `jsVsTorchCheck` en `recommender_eval.json`): semilla 17: 62 filas, diferencia máxima 4.8e-15, misma recomendación en 62/62; semilla 29: 62 filas, diferencia máxima 4.1e-15, misma recomendación en 62/62; semilla 43: 62 filas, diferencia máxima 4.4e-15, misma recomendación en 62/62 (tolerancia 1e-5).
- **ELM en GPU** (`scripts/gpu/elm_gpu.py`): la misma ELM de `trainELM` con la solución de ridge por `torch.linalg` (Cholesky, float64), por bloques de filas. Los pesos ocultos salen del mismo generador mulberry32 (portado de forma vectorizada), de modo que con la misma semilla el modelo es el mismo. Comprobación (`gpu_checks.json`, `scripts/gpu/check_gpu_training.mjs`): ajuste con 4000 filas de v2 y semilla 42; en 300 filas la diferencia máxima entre las predicciones de JS y de la GPU es 5.0e-12 (tolerancia 0.0001). Se usa donde el ELM se repite por semilla: la evaluación alineada de v2 y de v3 y el café. Los artefactos de v1 no se regeneraron. La evaluación alineada de v2 con los ELM de la GPU da las mismas decisiones que antes (los números cambian solo en el redondeo, del orden de 1e-11).

**Tiempos, medidos** (equipo: NVIDIA GeForce RTX 4050 Laptop GPU, torch 2.11.0+cu128; el JS "antes" es el de los artefactos previos; la primera semilla de la GPU incluye el arranque de CUDA):

| Entrenamiento | JS antes (s) | GPU ahora (s) | Cómo se midió |
|---|---|---|---|
| Recomendador de pérdida de cultivo, evolución, 150 generaciones, semillas 17 / 29 / 43 | 539.49 / 540.59 / 540.07 (3 procesos a la vez, 559 s en total) | 5.65 / 5.29 / 5.53 (una tras otra, 16.5 s en total) | JS: `recommender_eval.json` de la Tarea 31 (commit 4778afc), medido; GPU: `recommender_eval.json` actual |
| Recomendador de riego del café, evolución, 150 generaciones | 76.1 por semilla (proyectado: 5 generaciones medidas y escaladas a 150) | 1.66 / 1.51 / 1.53 | `coffee_eval.json` (`timing.jsEsBenchmark` y `timing.gpuEs`); el JS de 150 generaciones no se corrió completo |
| ELM del emulador v2 (1500 ocultas; filas de ajuste de v2) | 56.6 (semilla 42, `emulator_v2_eval.json`) | 1.08 / 0.92 / 0.92 | JS: medido en la Tarea 26 con las mismas filas y configuración; GPU: `aligned_eval.json` (`meta.networks.elm.trainSecondsGpu`) |
| ELM del café (1500 ocultas) | 8.26 / 8.34 / 11.13 | 0.29 / 0.13 / 0.13 | `coffee_eval.json` (`timing.elmSecondsJs` y `timing.elmSeconds`) |
| ELM en una muestra de 4000 filas de v2 (comprobación) | 9.5 | 0.40 | `gpu_checks.json` |

En el recomendador de pérdida de cultivo el JS corría las tres semillas a la vez (competencia entre procesos); en la GPU corren una tras otra.

### 2. El recomendador de pérdida de cultivo, antes y ahora

Mismo diseño, otro flujo aleatorio. Las semillas dan resultados distintos entre sí y distintos de la corrida en JS; esta es la variación entre corridas, no un cambio de diseño. Antes = `recommender_eval.json` de la Tarea 31 (commit 4778afc); ahora = el actual.

**Años reservados 2022–2024 (27 casos).** Media de lo elegido (ganancia sobre la regla; ganados / empatados / perdidos; se aparta de la regla). Regla: 0.856; techo: 0.979.

| Semilla | Prioridad | Antes (JS) | Ahora (GPU) |
|---|---|---|---|
| 17 | típico | 0.936 (+0.080; 9/16/2; 13/27) | 0.881 (+0.025; 4/17/6; 10/27) |
| 17 | cauto | 0.932 (+0.076; 8/18/1; 10/27) | 0.828 (-0.027; 1/22/4; 5/27) |
| 29 | típico | 0.944 (+0.088; 8/19/0; 9/27) | 0.944 (+0.088; 7/20/0; 9/27) |
| 29 | cauto | 0.937 (+0.081; 8/18/1; 11/27) | 0.928 (+0.072; 5/19/3; 10/27) |
| 43 | típico | 0.897 (+0.041; 6/19/2; 10/27) | 0.838 (-0.018; 3/21/3; 9/27) |
| 43 | cauto | 0.905 (+0.049; 5/19/3; 10/27) | 0.895 (+0.040; 4/20/3; 10/27) |

**Adicional 2019–2024 (54 casos).** Media de lo elegido (ganancia sobre la regla; ganados / empatados / perdidos; se aparta de la regla). Regla: 0.802; techo: 0.971.

| Semilla | Prioridad | Antes (JS) | Ahora (GPU) |
|---|---|---|---|
| 17 | típico | 0.885 (+0.083; 20/30/4; 34/54) | 0.816 (+0.014; 12/34/8; 28/54) |
| 17 | cauto | 0.899 (+0.097; 19/30/5; 30/54) | 0.796 (-0.006; 8/39/7; 21/54) |
| 29 | típico | 0.890 (+0.088; 17/35/2; 25/54) | 0.915 (+0.113; 19/33/2; 29/54) |
| 29 | cauto | 0.927 (+0.125; 21/31/2; 30/54) | 0.896 (+0.094; 15/32/7; 30/54) |
| 43 | típico | 0.871 (+0.068; 16/34/4; 29/54) | 0.855 (+0.053; 14/35/5; 30/54) |
| 43 | cauto | 0.928 (+0.126; 17/33/4; 29/54) | 0.856 (+0.054; 13/34/7; 30/54) |

**¿Cambian las conclusiones?** Sí, en una (la de la regla); la otra se mantiene:
- 27 casos de 2022–2024: la red que recomienda mejoraba la media de la regla en 6 de las 6 combinaciones (semilla × prioridad) con el entrenamiento en JS y la mejora en 4 de 6 con el de la GPU; tenía más casos ganados que perdidos en 6 de 6 y ahora en 3 de 6. Rango de la media de lo elegido: 0.897–0.944 antes y 0.828–0.944 ahora; predecir y elegir (red v2 y ELM v2, 12 combinaciones): 0.917–0.957.
- 54 casos de 2019–2024: la red que recomienda mejoraba la media de la regla en 6 de las 6 combinaciones (semilla × prioridad) con el entrenamiento en JS y la mejora en 5 de 6 con el de la GPU; tenía más casos ganados que perdidos en 6 de 6 y ahora en 6 de 6. Rango de la media de lo elegido: 0.871–0.928 antes y 0.796–0.915 ahora; predecir y elegir (red v2 y ELM v2, 12 combinaciones): 0.910–0.944.
- **Ya no se puede decir que la red que recomienda mejora a la regla en las seis combinaciones**: con el entrenamiento de la GPU, las combinaciones con ganancia media sobre la regla de cero o menos son 27 casos, semilla 17, cauto (-0.027); 27 casos, semilla 43, típico (-0.018); 54 casos, semilla 17, cauto (-0.006) (ver las tablas). El resultado depende de la semilla.
- **Sigue sin superar a predecir y elegir**: la mejor combinación de la red que recomienda (0.944 con 27 casos y 0.915 con 54) queda por debajo de la mejor de predecir y elegir (0.957 y 0.944).
- El punto de control que guarda `recommender_mlp.json` es ahora el de la semilla 29 (generación 146, aptitud de validación 0.961); `historical_check.json` se regeneró con esa red (semilla 29, generación 146) y las tablas de la sección de contraste con agricultores son las nuevas; siguen siendo ilustrativas, no una prueba.

### 3. Más datos y más entradas para el emulador de siete cultivos

**Por qué.** La primera salida de v2 (`relYieldA`) tenía R² de unos 0.6 en años nuevos y una prueba de tamaño mostró que más parámetros no ayudan. La palanca es más datos o más entradas.

**Candidatos (fijados de antemano), tres semillas cada uno, solo validación 2017–2018.**
- `base`: v2 de hoy, 60 000 muestras (reservorio), 31 entradas.
- `data`: todas las muestras que produce el generador (211680), mismas 31 entradas.
- `inputs`: las 60 000 + 16 entradas nuevas: para el cultivo A y, con la misma definición, para B (ceros si no hay B, si A no termina en el año o si B ya no cabe): lluvia y ET₀ de los 30 días antes de que empiece la ventana de floración, el índice de lluvia antecedente y el balance corrido acotado a 150 mm al día anterior (la lógica de `apiFlower` y `storeProxy` de v1 con el Kc del propio cultivo), lluvia y déficit climático dentro de la ventana de floración, los días del ciclo simulado por grados-día y los días que quedan al fin del año agrícola en la siembra (`web/js/model/emulatorV3.js`).
- `data+inputs`: las dos cosas.

**Qué período cubre cada entrada nueva** (importante). Son entradas de una **temporada conocida** (retrospectiva), igual que `rainYear` o `caniculaDays` de v2: usan el clima diario del año agrícola (1 de abril a 31 de marzo) del paquete de datos, la ET₀ calculada de ese clima, los parámetros del cultivo y el día de siembra. La lluvia y la ET₀ se leen del 1 de abril hasta el último día de la ventana de floración (la de antes de la floración, la de dentro de ella); la temperatura diaria, que fija la duración del ciclo y por tanto la ventana, se lee de la siembra a la cosecha. **No usan ninguna salida del simulador** (ni balance de agua del suelo, ni Ks, ni rendimiento) ni nada posterior al 31 de marzo del año agrícola; `storeProxy` es el indicador sin suelo de v1, no el balance del simulador. Hay pruebas hechas a mano (`tests/emulator_v3.test.mjs`) que alteran la lluvia y la ET₀ posteriores a la floración, la temperatura posterior a la cosecha y todo lo posterior al 31 de marzo, y las entradas no cambian. En la decisión tras perder el maíz estas entradas se calculan sobre años pasados completos (como ya hacían las de v2), así que el modelo no ve la temporada que decide.

**Resultado del cribado** (solo validación; MSE de las salidas estandarizadas sobre las mismas filas de validación para todos):

| Candidato | Entradas | Filas de entrenamiento | MSE de validación por semilla 17 / 29 / 43 | MSE medio | R² de validación medio: relYieldA / relYieldB / fit |
|---|---|---|---|---|---|
| base (v2 de hoy) | 31 | 36055 | 0.1576 / 0.1588 / 0.1593 | 0.1586 | 0.731 / 0.935 / 0.890 |
| data (todos los candidatos) | 31 | 127008 | 0.1607 / 0.1567 / 0.1559 | 0.1578 | 0.725 / 0.937 / 0.898 |
| inputs (60 000 + 16 entradas) | 47 | 36055 | 0.0735 / 0.0726 / 0.0716 | 0.0726 | 0.902 / 0.967 / 0.923 |
| data+inputs | 47 | 127008 | 0.0601 / 0.0622 / 0.0623 | 0.0615 | 0.919 / 0.974 / 0.931 |

Regla fijada antes de correr: gana el menor MSE de validación medio de las tres semillas; se adopta solo si mejora a `base` en al menos 2 % y ninguna salida empeora su R² de validación en más de 0.01 (medias de las tres semillas); si no, se conserva `base`. Resultado: gana **data+inputs** con un MSE medio de 0.0615 frente a 0.1586 de `base` (mejora de 61.2 %); el menor cambio del R² de validación de una salida frente a `base` es +0.039 (ninguna empeora). **Se adopta: sí.**

Métrica: error cuadrático medio de las salidas estandarizadas (con la desviación del entrenamiento de `base`) sobre las mismas filas de validación para todos los candidatos: las filas de 2017–2018 del reservorio de 60 000 (n = 3924). Receta: la de siempre (`fit_network`: embudo n → 64 → 32 → 16 → 3, ReLU, Adam 1e-3, lotes de 256, parada temprana con paciencia 10 sobre 2017–2018). Ninguna fila de prueba (años 2019–2024 y puntos reservados) se usó (`testRowsUsed`: false). Épocas y tiempos de cada corrida: `scripts/emulator/v2_screening.json` (`runs`); las corridas más largas duran hasta 44 s en CUDA.

Lectura: más filas sin más entradas (`data`) cambia el MSE de validación 0.5 % frente a `base` (reducción; un valor negativo sería un empeoramiento); las entradas nuevas con las mismas 60 000 filas (`inputs`) lo reducen 54.2 %; las dos juntas lo reducen 61.2 %.

**Adoptado: `data+inputs` (v3).** Se regeneraron las muestras (`scripts/emulator/generate_v3.mjs`: todos los candidatos, con las 47 entradas), se entrenaron las tres semillas en CUDA (`scripts/emulator/train_mlp_v3.py`; no se instaló nada en el entorno de CUDA) y se escribieron `web/data/emulator_v3_mlp_seed{17,29,43}.json` (y `emulator_v3_mlp.json`, semilla 42) junto a los de v2, que no se tocaron. La red es la misma receta con 47 entradas (47 entradas, 5731 parámetros; la de v2, 31 entradas y 4707). Evaluación de prueba, una sola vez (`aligned_eval_v3.json`):

**Exactitud del emulador v2 → v3 por semilla**, sobre **las mismas filas de prueba** (las del reservorio de v2, para que la comparación sea directa). R² de relYieldA / relYieldB / fit; entre paréntesis, el RMSE de relYieldA.

| División (n) | Modelo | Semilla | v2 | v3 |
|---|---|---|---|---|
| años nuevos (12107) | red embudo | 17 | 0.595 / 0.911 / 0.906 (0.093) | 0.824 / 0.961 / 0.917 (0.061) |
| años nuevos (12107) | red embudo | 29 | 0.622 / 0.899 / 0.894 (0.090) | 0.840 / 0.965 / 0.925 (0.059) |
| años nuevos (12107) | red embudo | 43 | 0.632 / 0.906 / 0.902 (0.089) | 0.835 / 0.963 / 0.924 (0.059) |
| años nuevos (12107) | ELM | 17 | 0.519 / 0.850 / 0.735 (0.102) | 0.675 / 0.914 / 0.778 (0.084) |
| años nuevos (12107) | ELM | 29 | 0.509 / 0.853 / 0.728 (0.103) | 0.675 / 0.913 / 0.779 (0.084) |
| años nuevos (12107) | ELM | 43 | 0.520 / 0.855 / 0.730 (0.102) | 0.676 / 0.916 / 0.774 (0.083) |
| puntos nuevos (8824) | red embudo | 17 | 0.797 / 0.907 / 0.864 (0.111) | 0.929 / 0.962 / 0.923 (0.066) |
| puntos nuevos (8824) | red embudo | 29 | 0.805 / 0.917 / 0.887 (0.108) | 0.916 / 0.969 / 0.924 (0.071) |
| puntos nuevos (8824) | red embudo | 43 | 0.792 / 0.908 / 0.884 (0.112) | 0.913 / 0.963 / 0.938 (0.072) |
| puntos nuevos (8824) | ELM | 17 | 0.760 / 0.831 / 0.698 (0.120) | 0.838 / 0.915 / 0.745 (0.099) |
| puntos nuevos (8824) | ELM | 29 | 0.759 / 0.852 / 0.691 (0.121) | 0.842 / 0.906 / 0.732 (0.098) |
| puntos nuevos (8824) | ELM | 43 | 0.750 / 0.843 / 0.687 (0.123) | 0.832 / 0.916 / 0.736 (0.101) |

En las filas de prueba **de todos los candidatos** (v3 se entrena con todos; 42336 filas en años nuevos y 31752 en puntos nuevos; los del reservorio son un subconjunto) la red embudo da, en años nuevos, R² de relYieldA 0.822 / 0.838 / 0.833 y en puntos nuevos 0.935 / 0.924 / 0.922 (semillas 17 / 29 / 43).

**Decisión tras perder el maíz con las redes v3 (predecir y elegir)**, mismas columnas que las demás tablas. Las filas de v2 se copian de `aligned_eval.json`, las de v3 vienen de `aligned_eval_v3.json`; regla, techo y simulador no cambian.

*Años reservados 2022–2024 (27 casos)*

| Política | Media | Ganancia | G / E / P | Arrepent. | P10 | Peor | Ejecut. | < 0.5 | Se aparta |
|---|---|---|---|---|---|---|---|---|---|
| Regla agronómica | 0.856 | +0.000 | 0 / 27 / 0 | 0.123 | 0.607 | 0.000 | 26/27 | 2/27 | 0/27 |
| Mejor opción en retrospectiva (techo) | 0.979 | | | 0.000 | | | 27/27 | 0/27 | 17/27 |
| Simulador como política (típico) | 0.947 | +0.091 | 10 / 16 / 1 | 0.032 | 0.907 | 0.462 | 27/27 | 1/27 | 15/27 |
| Simulador como política (cauto) | 0.963 | +0.107 | 13 / 8 / 6 | 0.017 | 0.905 | 0.796 | 27/27 | 0/27 | 24/27 |
| Predecir y elegir: red v2, semilla 17, típico | 0.953 | +0.097 | 13 / 8 / 6 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 27/27 |
| Predecir y elegir: red v2, semilla 17, cauto | 0.953 | +0.097 | 13 / 8 / 6 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 27/27 |
| Predecir y elegir: red v2, semilla 29, típico | 0.952 | +0.097 | 13 / 7 / 7 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 25/27 |
| Predecir y elegir: red v2, semilla 29, cauto | 0.952 | +0.096 | 13 / 6 / 8 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 27/27 |
| Predecir y elegir: red v2, semilla 43, típico | 0.957 | +0.101 | 12 / 10 / 5 | 0.022 | 0.851 | 0.752 | 27/27 | 0/27 | 22/27 |
| Predecir y elegir: red v2, semilla 43, cauto | 0.952 | +0.096 | 12 / 9 / 6 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 24/27 |
| Predecir y elegir: ELM v2, semilla 17, típico | 0.928 | +0.072 | 12 / 7 / 8 | 0.052 | 0.761 | 0.422 | 27/27 | 1/27 | 25/27 |
| Predecir y elegir: ELM v2, semilla 17, cauto | 0.917 | +0.061 | 12 / 6 / 9 | 0.062 | 0.718 | 0.422 | 27/27 | 1/27 | 27/27 |
| Predecir y elegir: ELM v2, semilla 29, típico | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27/27 | 1/27 | 26/27 |
| Predecir y elegir: ELM v2, semilla 29, cauto | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27/27 | 1/27 | 27/27 |
| Predecir y elegir: ELM v2, semilla 43, típico | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27/27 | 1/27 | 26/27 |
| Predecir y elegir: ELM v2, semilla 43, cauto | 0.952 | +0.096 | 13 / 6 / 8 | 0.027 | 0.851 | 0.711 | 27/27 | 0/27 | 27/27 |
| Predecir y elegir: red v3, semilla 17, típico | 0.960 | +0.104 | 12 / 14 / 1 | 0.020 | 0.907 | 0.565 | 27/27 | 0/27 | 21/27 |
| Predecir y elegir: red v3, semilla 17, cauto | 0.965 | +0.109 | 13 / 9 / 5 | 0.015 | 0.905 | 0.796 | 27/27 | 0/27 | 26/27 |
| Predecir y elegir: red v3, semilla 29, típico | 0.942 | +0.086 | 10 / 16 / 1 | 0.038 | 0.871 | 0.462 | 27/27 | 1/27 | 18/27 |
| Predecir y elegir: red v3, semilla 29, cauto | 0.955 | +0.099 | 13 / 9 / 5 | 0.025 | 0.851 | 0.711 | 27/27 | 0/27 | 24/27 |
| Predecir y elegir: red v3, semilla 43, típico | 0.959 | +0.103 | 11 / 15 / 1 | 0.021 | 0.907 | 0.565 | 27/27 | 0/27 | 16/27 |
| Predecir y elegir: red v3, semilla 43, cauto | 0.964 | +0.108 | 12 / 12 / 3 | 0.016 | 0.896 | 0.796 | 27/27 | 0/27 | 20/27 |
| Predecir y elegir: ELM v3, semilla 17, típico | 0.958 | +0.102 | 12 / 11 / 4 | 0.022 | 0.916 | 0.565 | 27/27 | 0/27 | 21/27 |
| Predecir y elegir: ELM v3, semilla 17, cauto | 0.958 | +0.102 | 12 / 11 / 4 | 0.022 | 0.916 | 0.565 | 27/27 | 0/27 | 21/27 |
| Predecir y elegir: ELM v3, semilla 29, típico | 0.939 | +0.083 | 7 / 16 / 4 | 0.041 | 0.813 | 0.565 | 27/27 | 0/27 | 16/27 |
| Predecir y elegir: ELM v3, semilla 29, cauto | 0.928 | +0.072 | 12 / 7 / 8 | 0.052 | 0.761 | 0.422 | 27/27 | 1/27 | 25/27 |
| Predecir y elegir: ELM v3, semilla 43, típico | 0.938 | +0.082 | 8 / 12 / 7 | 0.041 | 0.813 | 0.565 | 27/27 | 0/27 | 20/27 |
| Predecir y elegir: ELM v3, semilla 43, cauto | 0.935 | +0.079 | 13 / 6 / 8 | 0.044 | 0.811 | 0.422 | 27/27 | 1/27 | 26/27 |

Resumen entre semillas (media, mínimo–máximo de la media de lo elegido): red típico: v2 0.954 (0.952–0.957) → v3 0.953 (0.942–0.960); red cauto: v2 0.952 (0.952–0.953) → v3 0.961 (0.955–0.965); ELM típico: v2 0.933 (0.928–0.935) → v3 0.945 (0.938–0.958); ELM cauto: v2 0.935 (0.917–0.952) → v3 0.940 (0.928–0.958).

*Adicional 2019–2024 (54 casos)*

| Política | Media | Ganancia | G / E / P | Arrepent. | P10 | Peor | Ejecut. | < 0.5 | Se aparta |
|---|---|---|---|---|---|---|---|---|---|
| Regla agronómica | 0.802 | +0.000 | 0 / 54 / 0 | 0.169 | 0.466 | 0.000 | 49/54 | 7/54 | 0/54 |
| Mejor opción en retrospectiva (techo) | 0.971 | | | 0.000 | | | 54/54 | 0/54 | 33/54 |
| Simulador como política (típico) | 0.925 | +0.123 | 20 / 29 / 5 | 0.046 | 0.809 | 0.243 | 54/54 | 3/54 | 30/54 |
| Simulador como política (cauto) | 0.945 | +0.143 | 26 / 17 / 11 | 0.026 | 0.837 | 0.711 | 54/54 | 0/54 | 48/54 |
| Predecir y elegir: red v2, semilla 17, típico | 0.943 | +0.141 | 27 / 16 / 11 | 0.028 | 0.837 | 0.640 | 54/54 | 0/54 | 54/54 |
| Predecir y elegir: red v2, semilla 17, cauto | 0.943 | +0.141 | 27 / 16 / 11 | 0.028 | 0.837 | 0.640 | 54/54 | 0/54 | 54/54 |
| Predecir y elegir: red v2, semilla 29, típico | 0.943 | +0.141 | 26 / 17 / 11 | 0.028 | 0.837 | 0.640 | 54/54 | 0/54 | 44/54 |
| Predecir y elegir: red v2, semilla 29, cauto | 0.942 | +0.140 | 27 / 14 / 13 | 0.029 | 0.837 | 0.640 | 54/54 | 0/54 | 54/54 |
| Predecir y elegir: red v2, semilla 43, típico | 0.944 | +0.142 | 24 / 21 / 9 | 0.027 | 0.807 | 0.640 | 54/54 | 0/54 | 42/54 |
| Predecir y elegir: red v2, semilla 43, cauto | 0.944 | +0.142 | 26 / 19 / 9 | 0.027 | 0.818 | 0.640 | 54/54 | 0/54 | 49/54 |
| Predecir y elegir: ELM v2, semilla 17, típico | 0.915 | +0.113 | 22 / 19 / 13 | 0.056 | 0.757 | 0.277 | 54/54 | 2/54 | 43/54 |
| Predecir y elegir: ELM v2, semilla 17, cauto | 0.910 | +0.108 | 24 / 15 / 15 | 0.061 | 0.759 | 0.277 | 54/54 | 2/54 | 51/54 |
| Predecir y elegir: ELM v2, semilla 29, típico | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54/54 | 2/54 | 47/54 |
| Predecir y elegir: ELM v2, semilla 29, cauto | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54/54 | 2/54 | 51/54 |
| Predecir y elegir: ELM v2, semilla 43, típico | 0.925 | +0.123 | 25 / 16 / 13 | 0.046 | 0.818 | 0.277 | 54/54 | 2/54 | 47/54 |
| Predecir y elegir: ELM v2, semilla 43, cauto | 0.942 | +0.140 | 26 / 15 / 13 | 0.029 | 0.837 | 0.640 | 54/54 | 0/54 | 52/54 |
| Predecir y elegir: red v3, semilla 17, típico | 0.950 | +0.148 | 25 / 24 / 5 | 0.021 | 0.858 | 0.491 | 54/54 | 1/54 | 46/54 |
| Predecir y elegir: red v3, semilla 17, cauto | 0.949 | +0.147 | 26 / 17 / 11 | 0.022 | 0.837 | 0.711 | 54/54 | 0/54 | 53/54 |
| Predecir y elegir: red v3, semilla 29, típico | 0.925 | +0.123 | 22 / 27 / 5 | 0.046 | 0.809 | 0.243 | 54/54 | 3/54 | 38/54 |
| Predecir y elegir: red v3, semilla 29, cauto | 0.945 | +0.143 | 27 / 17 / 10 | 0.026 | 0.837 | 0.640 | 54/54 | 0/54 | 51/54 |
| Predecir y elegir: red v3, semilla 43, típico | 0.952 | +0.150 | 23 / 29 / 2 | 0.019 | 0.881 | 0.491 | 54/54 | 1/54 | 31/54 |
| Predecir y elegir: red v3, semilla 43, cauto | 0.954 | +0.152 | 25 / 23 / 6 | 0.017 | 0.845 | 0.711 | 54/54 | 0/54 | 42/54 |
| Predecir y elegir: ELM v3, semilla 17, típico | 0.942 | +0.140 | 25 / 22 / 7 | 0.029 | 0.845 | 0.491 | 54/54 | 1/54 | 44/54 |
| Predecir y elegir: ELM v3, semilla 17, cauto | 0.942 | +0.140 | 25 / 22 / 7 | 0.029 | 0.845 | 0.491 | 54/54 | 1/54 | 43/54 |
| Predecir y elegir: ELM v3, semilla 29, típico | 0.925 | +0.123 | 15 / 33 / 6 | 0.046 | 0.742 | 0.491 | 54/54 | 1/54 | 29/54 |
| Predecir y elegir: ELM v3, semilla 29, cauto | 0.915 | +0.113 | 22 / 19 / 13 | 0.056 | 0.757 | 0.277 | 54/54 | 2/54 | 43/54 |
| Predecir y elegir: ELM v3, semilla 43, típico | 0.925 | +0.123 | 18 / 25 / 11 | 0.046 | 0.768 | 0.491 | 54/54 | 1/54 | 37/54 |
| Predecir y elegir: ELM v3, semilla 43, cauto | 0.922 | +0.120 | 25 / 15 / 14 | 0.049 | 0.791 | 0.277 | 54/54 | 2/54 | 49/54 |

Resumen entre semillas (media, mínimo–máximo de la media de lo elegido): red típico: v2 0.943 (0.943–0.944) → v3 0.942 (0.925–0.952); red cauto: v2 0.943 (0.942–0.944) → v3 0.949 (0.945–0.954); ELM típico: v2 0.922 (0.915–0.925) → v3 0.931 (0.925–0.942); ELM cauto: v2 0.926 (0.910–0.942) → v3 0.926 (0.915–0.942).

De las 12 combinaciones (semilla × modelo × prioridad), v3 sube la media de lo elegido en 9 y la baja en 3 con 27 casos, y la sube en 8 y la baja en 4 con 54 casos.

La red que recomienda (reentrenada en GPU) llega, en la mejor de sus seis combinaciones, a 0.944 (27 casos) y 0.915 (54 casos); las políticas de predecir y elegir con v3, a 0.965 y 0.954.

### 4. Qué empeoró, qué no se adoptó y límites

- **La red que recomienda ya no gana a la regla en las seis combinaciones** (sección 2): es lo único que empeoró de una conclusión anterior, por el cambio de flujo aleatorio y no por un cambio de diseño.
- **Con v3 la decisión no mejora de forma pareja.** La exactitud del emulador mejora claramente en las tres salidas y en las cuatro divisiones, pero la media de lo elegido por las políticas de predecir y elegir sube en unas combinaciones y baja en otras (ver el conteo arriba y las filas por semilla): la decisión elige el mejor de siete cultivos y no depende solo del error medio. No se afirma que v3 decida mejor.
- **No se adoptó** `data` solo (no mejora la validación) ni `inputs` solo (mejora mucho, pero `data+inputs` mejora más).
- **v3 no está conectado a la aplicación web**: la interfaz usa el simulador y el emulador v1; v2 y v3 son para la comparación de decisiones. Los artefactos v1 y v2 no se modificaron.
- **No se hizo:** AquaCrop como segundo juez de las recomendaciones; el margen económico (no hay precios y costos en el juez); el año agrícola 2025 (la serie termina el 2025-12-31); un reentrenamiento con 2019–2021 añadidos; ajustar el diseño del recomendador tras ver la prueba.
- El juez sigue siendo nuestro simulador y la prueba usa 3 pilotos con 27 y 54 casos casi repetidos entre sí; los conteos son descriptivos, no se calculó significancia.

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
node scripts/compare/train_recommender.mjs --dump    # Tarea 33: tabla de escenarios del recomendador de pérdida de cultivo
C:/Users/velas/venv_lab4/Scripts/python.exe scripts/gpu/train_recommender.py          # evolución por lotes en GPU, 3 semillas (~5 s cada una)
node scripts/emulator/generate_v3.mjs                # todos los candidatos con las 47 entradas (samples_v3_all.json, ignorado por git)
PYTHONPATH=scripts/emulator C:/Users/velas/venv_lab4/Scripts/python.exe scripts/emulator/screen_v2_data_inputs.py   # cribado de datos y entradas (v2_screening.json)
PYTHONPATH=scripts/emulator C:/Users/velas/venv_lab4/Scripts/python.exe scripts/emulator/train_mlp_v3.py --device cuda --seed 17 --out web/data/emulator_v3_mlp_seed17.json   # idem 29 y 43
C:/Users/velas/venv_lab4/Scripts/python.exe scripts/gpu/elm_gpu.py v2     # ELM de v2 en GPU; con --samples scripts/emulator/samples_v3_all.json --tag v3 para v3; `coffee` para el café; `check` + node scripts/gpu/check_gpu_training.mjs
node scripts/compare/aligned_eval.mjs ; node scripts/compare/aligned_eval.mjs --v3     # evaluación alineada v2 y v3
node scripts/compare/train_recommender.mjs ; node scripts/compare/historical_check.mjs   # evaluación del recomendador y contraste histórico
node scripts/gpu/doc_tables.mjs gpu                  # las tablas de la sección de GPU, desde los artefactos
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

## Red alineada con la app (solo datos que la app tiene)

15 de noviembre de 2026 (Tarea 34). Todos los números de esta sección salen de `web/data/app_eval.json`, y las tablas se generan con `scripts/app/doc_tables.mjs`. El contrato con la app está en `proyecto/contrato-app-modelo.md`. **La red no está conectada a la app**: el contrato dice cómo se haría.

### Qué predice y por qué esos tres valores

La app de Carlos muestra cómo le fue a la plantación **hasta hoy** (reserva, estrés de la última semana, `factorRendimiento` desde la siembra). No dice qué viene. La red recibe solo lo que la app tiene un día cualquiera del ciclo y predice tres valores hacia adelante:

- `factorFinal`: el `factorRendimiento` de la app al cosechar (último día del ciclo). Es la versión "hacia adelante" del número que la app ya muestra.
- `estres7`: días con Ks < 1 en los 7 días siguientes a hoy.
- `estres14`: lo mismo en los 14 días siguientes.

Se eligieron porque usan **la misma medida que la app ya muestra** (Ks < 1 y `factorRendimiento`), y así la verdad se calcula con el propio motor de la app y no hay que inventar otra escala. Los días de estrés de la semana próxima son lo que un productor con riego podría usar.

### Datos y escenarios

- **Juez:** el motor de la app portado a JS (`web/js/model/appEngine.js`), probado contra el código Dart real a 1e-9 en 3 casos fijos (`tests/fixtures/app_engine_dart.json`; diferencia máxima 7.1e-15). Corre con el clima real de NASA POWER de todo el ciclo. **No** está validado en el campo y **no** es AquaCrop.
- **Clima:** NASA POWER tal como lo descarga la app (mismos parámetros, comunidad AG, lluvia `PRECTOTCORR`, temperatura sin corregir a la parcela, elevación de la celda), 2001-01-01 a 2025-12-31, 20 puntos (`scripts/app/fetch_power_app.mjs`; `web/data/app_power_coverage.json`). Días sin dato en los 20 puntos: 0 en las seis variables, así que la regla de huecos de la app no se usó con datos reales.
- **Escenario:** punto × año de siembra × fecha de siembra (cada 10 días desde el 1 de mayo hasta el 28 de septiembre, 16 fechas) × cultivo y ciclo (maíz 90 y 120; frijol 67, 80 y 90; tomate 120 y 145) × suelo (100, 150 y 180 mm/m) × "hoy" en el 20, 35, 50, 65 y 80 % del ciclo (`hoy` = siembra + redondeo de la fracción por el ciclo). A secano. Solo escenarios cuyo ciclo termina el 2025-12-31 o antes (220 combinaciones de siembra omitidas por eso). El café no entra: la app no le da Ky.
- **Conteos:** 836 700 filas en total; entrenamiento disponible 537 600 (usadas 150 000), validación 67 200, prueba 201 600 (reservados 2022–2024: 100 800; pilotos: 30 240), sin usar (siembra 2025) 30 300.
- **Entradas (40):** las de `APP_INPUT_NAMES` en `web/js/model/appInputs.js`: lat, lon, elevación de la celda, día del año de siembra y de hoy (seno y coseno), cultivo, ciclo, fracción transcurrida, días a cosecha, agua del suelo, Kc medio, raíz, p, Ky, el estado que la app calcula hoy (reserva, agotamiento/TAW, Ks, etapa, `factorRendimiento` hasta hoy, días de estrés de los últimos 7 y desde la siembra), lluvia y ET₀ de los últimos 7, 14 y 28 días y desde la siembra, racha seca más larga de los últimos 28 días, Tmax y Tmin medias de los últimos 14 y necesidad del cultivo de los últimos 7. Una prueba (`tests/appInputs.test.mjs`) demuestra que cambiar el clima posterior a hoy, o el de más de 240 días atrás, no cambia ninguna entrada ni las referencias; las funciones de entrada tienen además pruebas calculadas a mano.
- **Partición por año de siembra:** entrenamiento 2001–2016, validación 2017–2018 (parada temprana y elección de la mejor semilla), prueba 2019–2024, de los cuales 2022–2024 se reportan aparte como años reservados, y los tres pilotos (Chiquimula, Jutiapa, San Martín Jilotepeque) como otro subconjunto. El año de siembra 2025 no se usa. El conjunto de entrenamiento se submuestreó a 150 000 filas con semilla 17.
- **Modelos, semillas 17, 29 y 43:** la red embudo 40 → 64 → 32 → 16 → 3 con la receta base (Adam 1e-3, lotes de 256, paciencia 10) en PyTorch con CUDA (NVIDIA GeForce RTX 4050 Laptop GPU) y el ELM en GPU (1 500 neuronas ocultas, escala 0.1, λ 0.1). Se exportó la semilla con menor pérdida de validación (semilla 17) como `web/data/app_mlp.json`; su pase hacia adelante en JS coincide con PyTorch a 1e-5 (`tests/app_mlp.test.mjs`).
- **Tiempos:** red en CUDA 31.5, 36.77 y 26.26 s (semillas 17, 29, 43; 21, 23 y 13 épocas; 5283 parámetros); ELM en GPU 4.71, 4.43 y 4.38 s. Generar las 836 700 muestras con el motor de la app en JS: 38 s.
- **Referencias que la red debe superar:** (a) *lo que la app muestra hoy*: `factorFinal` ≈ `factorRendimiento` hasta hoy, `estres7` ≈ días de estrés de los últimos 7 y `estres14` ≈ el doble, con tope de 14; (b) *adelanto en seco*: el motor de la app seguido desde hoy hasta la cosecha sin lluvia y con la ET₀ media de los últimos 7 días (la misma regla de huecos de la app); se calcula en la app sin red.
- **Reglas fijadas antes de ver la prueba:** "gana" quiere decir menor MAE (error absoluto medio) en cada una de las 3 semillas; también se reportan R² y, para el estrés, la clase "habrá estrés" (`estres ≥ 1` día): el modelo la predice si su valor es ≥ 0.5 y las referencias, que son conteos enteros, si es ≥ 1. Nada se ajustó con las filas de prueba.

### Resultados en la prueba (años de siembra 2019–2024)

| Modelo | factorFinal R² | factorFinal MAE | estres7 R² | estres7 MAE | estres7 precisión / recall / F1 | estres14 R² | estres14 MAE | estres14 precisión / recall / F1 |
|---|---|---|---|---|---|---|---|---|
| Red (backprop) s17 | 0.590 | 0.0226 | 0.884 | 0.198 | 0.790 / 0.937 / 0.857 | 0.805 | 0.539 | 0.603 / 0.912 / 0.726 |
| Red (backprop) s29 | 0.656 | 0.0210 | 0.878 | 0.177 | 0.818 / 0.920 / 0.866 | 0.805 | 0.539 | 0.591 / 0.913 / 0.717 |
| Red (backprop) s43 | 0.599 | 0.0238 | 0.881 | 0.205 | 0.791 / 0.936 / 0.857 | 0.802 | 0.571 | 0.547 / 0.936 / 0.690 |
| ELM s17 | 0.500 | 0.0313 | 0.794 | 0.420 | 0.491 / 0.971 / 0.652 | 0.713 | 0.982 | 0.340 / 0.943 / 0.500 |
| ELM s29 | 0.493 | 0.0315 | 0.781 | 0.443 | 0.457 / 0.974 / 0.622 | 0.704 | 1.006 | 0.324 / 0.944 / 0.482 |
| ELM s43 | 0.494 | 0.0312 | 0.753 | 0.434 | 0.484 / 0.970 / 0.646 | 0.686 | 0.987 | 0.343 / 0.937 / 0.502 |
| Referencia: lo que muestra la app | 0.160 | 0.0254 | 0.583 | 0.268 | 0.717 / 0.670 / 0.693 | 0.462 | 0.679 | 0.755 / 0.528 / 0.622 |
| Referencia: adelanto en seco | -32.642 | 0.3102 | 0.560 | 0.359 | 0.445 / 0.995 / 0.615 | -1.061 | 3.123 | 0.188 / 0.997 / 0.316 |

Filas: 201600. Con estrés en los próximos 7 días: 18839 (9.3 %); en los próximos 14: 25192 (12.5 %).

### Años reservados (años de siembra 2022–2024)

| Modelo | factorFinal R² | factorFinal MAE | estres7 R² | estres7 MAE | estres7 precisión / recall / F1 | estres14 R² | estres14 MAE | estres14 precisión / recall / F1 |
|---|---|---|---|---|---|---|---|---|
| Red (backprop) s17 | 0.453 | 0.0253 | 0.855 | 0.250 | 0.808 / 0.944 / 0.870 | 0.728 | 0.699 | 0.653 / 0.911 / 0.761 |
| Red (backprop) s29 | 0.557 | 0.0227 | 0.843 | 0.236 | 0.838 / 0.922 / 0.878 | 0.730 | 0.695 | 0.659 / 0.907 / 0.763 |
| Red (backprop) s43 | 0.422 | 0.0272 | 0.851 | 0.261 | 0.793 / 0.950 / 0.865 | 0.730 | 0.746 | 0.578 / 0.942 / 0.716 |
| ELM s17 | 0.360 | 0.0335 | 0.786 | 0.476 | 0.543 / 0.981 / 0.699 | 0.651 | 1.136 | 0.411 / 0.948 / 0.573 |
| ELM s29 | 0.340 | 0.0342 | 0.771 | 0.505 | 0.507 / 0.982 / 0.669 | 0.646 | 1.175 | 0.398 / 0.943 / 0.560 |
| ELM s43 | 0.360 | 0.0337 | 0.760 | 0.494 | 0.515 / 0.973 / 0.674 | 0.640 | 1.150 | 0.400 / 0.929 / 0.559 |
| Referencia: lo que muestra la app | 0.094 | 0.0285 | 0.495 | 0.381 | 0.695 / 0.693 / 0.694 | 0.313 | 0.949 | 0.745 / 0.565 / 0.642 |
| Referencia: adelanto en seco | -34.294 | 0.3104 | 0.557 | 0.410 | 0.510 / 0.995 / 0.674 | -0.929 | 3.168 | 0.234 / 0.996 / 0.379 |

Filas: 100800. Con estrés en los próximos 7 días: 11993 (11.9 %); en los próximos 14: 15788 (15.7 %).

### Solo los tres pilotos (años de siembra 2019–2024)

| Modelo | factorFinal R² | factorFinal MAE | estres7 R² | estres7 MAE | estres7 precisión / recall / F1 | estres14 R² | estres14 MAE | estres14 precisión / recall / F1 |
|---|---|---|---|---|---|---|---|---|
| Red (backprop) s17 | 0.595 | 0.0220 | 0.882 | 0.194 | 0.775 / 0.938 / 0.849 | 0.807 | 0.530 | 0.582 / 0.912 / 0.711 |
| Red (backprop) s29 | 0.618 | 0.0214 | 0.876 | 0.175 | 0.809 / 0.926 / 0.863 | 0.808 | 0.533 | 0.574 / 0.917 / 0.706 |
| Red (backprop) s43 | 0.524 | 0.0240 | 0.877 | 0.204 | 0.785 / 0.936 / 0.854 | 0.807 | 0.553 | 0.540 / 0.932 / 0.684 |
| ELM s17 | 0.440 | 0.0317 | 0.791 | 0.415 | 0.488 / 0.967 / 0.648 | 0.719 | 0.967 | 0.325 / 0.942 / 0.484 |
| ELM s29 | 0.432 | 0.0319 | 0.769 | 0.447 | 0.464 / 0.973 / 0.629 | 0.697 | 0.998 | 0.322 / 0.944 / 0.481 |
| ELM s43 | 0.431 | 0.0317 | 0.736 | 0.436 | 0.486 / 0.968 / 0.647 | 0.675 | 0.993 | 0.332 / 0.933 / 0.490 |
| Referencia: lo que muestra la app | 0.147 | 0.0244 | 0.603 | 0.251 | 0.727 / 0.672 / 0.698 | 0.487 | 0.639 | 0.766 / 0.530 / 0.627 |
| Referencia: adelanto en seco | -35.565 | 0.3104 | 0.543 | 0.359 | 0.445 / 0.995 / 0.615 | -1.093 | 3.102 | 0.185 / 0.998 / 0.312 |

Filas: 30240. Con estrés en los próximos 7 días: 2768 (9.2 %); en los próximos 14: 3694 (12.2 %).

### ¿Gana a las referencias?

Prueba (2019–2024):

| Objetivo | Modelo frente a | Semillas que ganan en MAE (de 3) | MAE medio del modelo | MAE de la referencia | Semillas que ganan en R² | R² medio del modelo | R² de la referencia | Semillas que ganan en F1 |
|---|---|---|---|---|---|---|---|---|
| factorFinal | Red frente a lo que muestra la app | 3 | 0.0225 | 0.0254 | 3 | 0.615 | 0.160 | — |
| factorFinal | Red frente a adelanto en seco | 3 | 0.0225 | 0.3102 | 3 | 0.615 | -32.642 | — |
| factorFinal | ELM frente a lo que muestra la app | 0 | 0.0313 | 0.0254 | 3 | 0.495 | 0.160 | — |
| factorFinal | ELM frente a adelanto en seco | 3 | 0.0313 | 0.3102 | 3 | 0.495 | -32.642 | — |
| estres7 | Red frente a lo que muestra la app | 3 | 0.1932 | 0.2683 | 3 | 0.881 | 0.583 | 3 |
| estres7 | Red frente a adelanto en seco | 3 | 0.1932 | 0.3586 | 3 | 0.881 | 0.560 | 3 |
| estres7 | ELM frente a lo que muestra la app | 0 | 0.4322 | 0.2683 | 3 | 0.776 | 0.583 | 0 |
| estres7 | ELM frente a adelanto en seco | 0 | 0.4322 | 0.3586 | 3 | 0.776 | 0.560 | 3 |
| estres14 | Red frente a lo que muestra la app | 3 | 0.5497 | 0.6793 | 3 | 0.804 | 0.462 | 3 |
| estres14 | Red frente a adelanto en seco | 3 | 0.5497 | 3.1232 | 3 | 0.804 | -1.061 | 3 |
| estres14 | ELM frente a lo que muestra la app | 0 | 0.9917 | 0.6793 | 3 | 0.701 | 0.462 | 0 |
| estres14 | ELM frente a adelanto en seco | 3 | 0.9917 | 3.1232 | 3 | 0.701 | -1.061 | 3 |

Años reservados (2022–2024):

| Objetivo | Modelo frente a | Semillas que ganan en MAE (de 3) | MAE medio del modelo | MAE de la referencia | Semillas que ganan en R² | R² medio del modelo | R² de la referencia | Semillas que ganan en F1 |
|---|---|---|---|---|---|---|---|---|
| factorFinal | Red frente a lo que muestra la app | 3 | 0.0251 | 0.0285 | 3 | 0.477 | 0.094 | — |
| factorFinal | Red frente a adelanto en seco | 3 | 0.0251 | 0.3104 | 3 | 0.477 | -34.294 | — |
| factorFinal | ELM frente a lo que muestra la app | 0 | 0.0338 | 0.0285 | 3 | 0.353 | 0.094 | — |
| factorFinal | ELM frente a adelanto en seco | 3 | 0.0338 | 0.3104 | 3 | 0.353 | -34.294 | — |
| estres7 | Red frente a lo que muestra la app | 3 | 0.2488 | 0.3809 | 3 | 0.850 | 0.495 | 3 |
| estres7 | Red frente a adelanto en seco | 3 | 0.2488 | 0.4104 | 3 | 0.850 | 0.557 | 3 |
| estres7 | ELM frente a lo que muestra la app | 0 | 0.4917 | 0.3809 | 3 | 0.773 | 0.495 | 1 |
| estres7 | ELM frente a adelanto en seco | 0 | 0.4917 | 0.4104 | 3 | 0.773 | 0.557 | 1 |
| estres14 | Red frente a lo que muestra la app | 3 | 0.7134 | 0.9494 | 3 | 0.730 | 0.313 | 3 |
| estres14 | Red frente a adelanto en seco | 3 | 0.7134 | 3.1676 | 3 | 0.730 | -0.929 | 3 |
| estres14 | ELM frente a lo que muestra la app | 0 | 1.1536 | 0.9494 | 3 | 0.645 | 0.313 | 0 |
| estres14 | ELM frente a adelanto en seco | 3 | 1.1536 | 3.1676 | 3 | 0.645 | -0.929 | 3 |

Pilotos:

| Objetivo | Modelo frente a | Semillas que ganan en MAE (de 3) | MAE medio del modelo | MAE de la referencia | Semillas que ganan en R² | R² medio del modelo | R² de la referencia | Semillas que ganan en F1 |
|---|---|---|---|---|---|---|---|---|
| factorFinal | Red frente a lo que muestra la app | 3 | 0.0225 | 0.0244 | 3 | 0.579 | 0.147 | — |
| factorFinal | Red frente a adelanto en seco | 3 | 0.0225 | 0.3104 | 3 | 0.579 | -35.565 | — |
| factorFinal | ELM frente a lo que muestra la app | 0 | 0.0318 | 0.0244 | 3 | 0.434 | 0.147 | — |
| factorFinal | ELM frente a adelanto en seco | 3 | 0.0318 | 0.3104 | 3 | 0.434 | -35.565 | — |
| estres7 | Red frente a lo que muestra la app | 3 | 0.1912 | 0.2511 | 3 | 0.878 | 0.603 | 3 |
| estres7 | Red frente a adelanto en seco | 3 | 0.1912 | 0.3587 | 3 | 0.878 | 0.543 | 3 |
| estres7 | ELM frente a lo que muestra la app | 0 | 0.4324 | 0.2511 | 3 | 0.765 | 0.603 | 0 |
| estres7 | ELM frente a adelanto en seco | 0 | 0.4324 | 0.3587 | 3 | 0.765 | 0.543 | 3 |
| estres14 | Red frente a lo que muestra la app | 3 | 0.5390 | 0.6387 | 3 | 0.807 | 0.487 | 3 |
| estres14 | Red frente a adelanto en seco | 3 | 0.5390 | 3.1021 | 3 | 0.807 | -1.093 | 3 |
| estres14 | ELM frente a lo que muestra la app | 0 | 0.9860 | 0.6387 | 3 | 0.697 | 0.487 | 0 |
| estres14 | ELM frente a adelanto en seco | 3 | 0.9860 | 3.1021 | 3 | 0.697 | -1.093 | 3 |

### Por fracción del ciclo transcurrida y por cultivo (prueba)

Se muestra la red de la semilla 17 (la exportada), las otras dos y el ELM de la semilla 17 junto a las dos referencias; los demás ELM están en `web/data/app_eval.json`.

**`factorFinal` por fracción del ciclo:**

| Fracción del ciclo | Modelo | MAE | R² |
|---|---|---|---|
| 0.2 | Red (backprop) s17 | 0.0351 | 0.218 |
| 0.2 | Red (backprop) s29 | 0.0317 | 0.382 |
| 0.2 | Red (backprop) s43 | 0.0404 | 0.198 |
| 0.2 | ELM s17 | 0.0459 | 0.037 |
| 0.2 | Referencia: lo que muestra la app | 0.0390 | -0.403 |
| 0.2 | Referencia: adelanto en seco | 0.6819 | -95.254 |
| 0.35 | Red (backprop) s17 | 0.0290 | 0.411 |
| 0.35 | Red (backprop) s29 | 0.0295 | 0.437 |
| 0.35 | Red (backprop) s43 | 0.0321 | 0.385 |
| 0.35 | ELM s17 | 0.0370 | 0.336 |
| 0.35 | Referencia: lo que muestra la app | 0.0307 | -0.120 |
| 0.35 | Referencia: adelanto en seco | 0.4920 | -50.972 |
| 0.5 | Red (backprop) s17 | 0.0232 | 0.583 |
| 0.5 | Red (backprop) s29 | 0.0214 | 0.667 |
| 0.5 | Red (backprop) s43 | 0.0225 | 0.642 |
| 0.5 | ELM s17 | 0.0289 | 0.578 |
| 0.5 | Referencia: lo que muestra la app | 0.0259 | 0.073 |
| 0.5 | Referencia: adelanto en seco | 0.2676 | -16.022 |
| 0.65 | Red (backprop) s17 | 0.0161 | 0.800 |
| 0.65 | Red (backprop) s29 | 0.0142 | 0.840 |
| 0.65 | Red (backprop) s43 | 0.0147 | 0.824 |
| 0.65 | ELM s17 | 0.0243 | 0.724 |
| 0.65 | Referencia: lo que muestra la app | 0.0201 | 0.424 |
| 0.65 | Referencia: adelanto en seco | 0.0973 | -1.850 |
| 0.8 | Red (backprop) s17 | 0.0097 | 0.940 |
| 0.8 | Red (backprop) s29 | 0.0084 | 0.953 |
| 0.8 | Red (backprop) s43 | 0.0091 | 0.947 |
| 0.8 | ELM s17 | 0.0203 | 0.825 |
| 0.8 | Referencia: lo que muestra la app | 0.0112 | 0.824 |
| 0.8 | Referencia: adelanto en seco | 0.0124 | 0.890 |

**`factorFinal` por cultivo:**

| Cultivo | Modelo | MAE | R² |
|---|---|---|---|
| maiz | Red (backprop) s17 | 0.0187 | 0.494 |
| maiz | Red (backprop) s29 | 0.0171 | 0.599 |
| maiz | Red (backprop) s43 | 0.0230 | 0.362 |
| maiz | ELM s17 | 0.0284 | 0.355 |
| maiz | Referencia: lo que muestra la app | 0.0149 | 0.176 |
| maiz | Referencia: adelanto en seco | 0.3059 | -50.425 |
| frijol | Red (backprop) s17 | 0.0208 | 0.428 |
| frijol | Red (backprop) s29 | 0.0196 | 0.521 |
| frijol | Red (backprop) s43 | 0.0214 | 0.488 |
| frijol | ELM s17 | 0.0293 | 0.260 |
| frijol | Referencia: lo que muestra la app | 0.0184 | 0.299 |
| frijol | Referencia: adelanto en seco | 0.3269 | -59.139 |
| tomate | Red (backprop) s17 | 0.0293 | 0.676 |
| tomate | Red (backprop) s29 | 0.0271 | 0.717 |
| tomate | Red (backprop) s43 | 0.0281 | 0.715 |
| tomate | ELM s17 | 0.0370 | 0.636 |
| tomate | Referencia: lo que muestra la app | 0.0464 | 0.010 |
| tomate | Referencia: adelanto en seco | 0.2897 | -15.007 |

**`estres7` por fracción del ciclo:**

| Fracción del ciclo | Modelo | MAE | R² | F1 |
|---|---|---|---|---|
| 0.2 | Red (backprop) s17 | 0.155 | 0.748 | 0.813 |
| 0.2 | Red (backprop) s29 | 0.145 | 0.727 | 0.822 |
| 0.2 | Red (backprop) s43 | 0.159 | 0.733 | 0.801 |
| 0.2 | ELM s17 | 0.380 | 0.461 | 0.473 |
| 0.2 | Referencia: lo que muestra la app | 0.167 | 0.306 | 0.613 |
| 0.2 | Referencia: adelanto en seco | 0.238 | 0.160 | 0.503 |
| 0.35 | Red (backprop) s17 | 0.166 | 0.798 | 0.763 |
| 0.35 | Red (backprop) s29 | 0.149 | 0.731 | 0.775 |
| 0.35 | Red (backprop) s43 | 0.165 | 0.802 | 0.757 |
| 0.35 | ELM s17 | 0.361 | 0.560 | 0.482 |
| 0.35 | Referencia: lo que muestra la app | 0.156 | 0.392 | 0.548 |
| 0.35 | Referencia: adelanto en seco | 0.367 | -0.009 | 0.365 |
| 0.5 | Red (backprop) s17 | 0.208 | 0.844 | 0.814 |
| 0.5 | Red (backprop) s29 | 0.183 | 0.845 | 0.821 |
| 0.5 | Red (backprop) s43 | 0.216 | 0.831 | 0.821 |
| 0.5 | ELM s17 | 0.412 | 0.748 | 0.639 |
| 0.5 | Referencia: lo que muestra la app | 0.271 | 0.447 | 0.610 |
| 0.5 | Referencia: adelanto en seco | 0.448 | 0.253 | 0.542 |
| 0.65 | Red (backprop) s17 | 0.227 | 0.879 | 0.864 |
| 0.65 | Red (backprop) s29 | 0.209 | 0.878 | 0.871 |
| 0.65 | Red (backprop) s43 | 0.232 | 0.876 | 0.866 |
| 0.65 | ELM s17 | 0.466 | 0.808 | 0.704 |
| 0.65 | Referencia: lo que muestra la app | 0.358 | 0.558 | 0.700 |
| 0.65 | Referencia: adelanto en seco | 0.429 | 0.572 | 0.661 |
| 0.8 | Red (backprop) s17 | 0.235 | 0.932 | 0.911 |
| 0.8 | Red (backprop) s29 | 0.200 | 0.933 | 0.921 |
| 0.8 | Red (backprop) s43 | 0.251 | 0.932 | 0.911 |
| 0.8 | ELM s17 | 0.479 | 0.888 | 0.747 |
| 0.8 | Referencia: lo que muestra la app | 0.389 | 0.700 | 0.786 |
| 0.8 | Referencia: adelanto en seco | 0.311 | 0.806 | 0.814 |

**`estres7` por cultivo:**

| Cultivo | Modelo | MAE | R² | F1 |
|---|---|---|---|---|
| maiz | Red (backprop) s17 | 0.130 | 0.887 | 0.892 |
| maiz | Red (backprop) s29 | 0.105 | 0.882 | 0.912 |
| maiz | Red (backprop) s43 | 0.145 | 0.875 | 0.884 |
| maiz | ELM s17 | 0.347 | 0.755 | 0.595 |
| maiz | Referencia: lo que muestra la app | 0.140 | 0.605 | 0.739 |
| maiz | Referencia: adelanto en seco | 0.107 | 0.761 | 0.792 |
| frijol | Red (backprop) s17 | 0.249 | 0.821 | 0.790 |
| frijol | Red (backprop) s29 | 0.225 | 0.808 | 0.799 |
| frijol | Red (backprop) s43 | 0.249 | 0.813 | 0.791 |
| frijol | ELM s17 | 0.451 | 0.709 | 0.629 |
| frijol | Referencia: lo que muestra la app | 0.329 | 0.413 | 0.599 |
| frijol | Referencia: adelanto en seco | 0.601 | 0.123 | 0.480 |
| tomate | Red (backprop) s17 | 0.190 | 0.928 | 0.919 |
| tomate | Red (backprop) s29 | 0.176 | 0.926 | 0.926 |
| tomate | Red (backprop) s43 | 0.198 | 0.931 | 0.920 |
| tomate | ELM s17 | 0.444 | 0.869 | 0.703 |
| tomate | Referencia: lo que muestra la app | 0.306 | 0.695 | 0.780 |
| tomate | Referencia: adelanto en seco | 0.247 | 0.814 | 0.782 |

**`estres14` por fracción del ciclo:**

| Fracción del ciclo | Modelo | MAE | R² | F1 |
|---|---|---|---|---|
| 0.2 | Red (backprop) s17 | 0.375 | 0.556 | 0.602 |
| 0.2 | Red (backprop) s29 | 0.386 | 0.549 | 0.589 |
| 0.2 | Red (backprop) s43 | 0.401 | 0.592 | 0.540 |
| 0.2 | ELM s17 | 0.817 | 0.228 | 0.284 |
| 0.2 | Referencia: lo que muestra la app | 0.368 | 0.121 | 0.592 |
| 0.2 | Referencia: adelanto en seco | 3.312 | -5.293 | 0.131 |
| 0.35 | Red (backprop) s17 | 0.472 | 0.585 | 0.566 |
| 0.35 | Red (backprop) s29 | 0.484 | 0.566 | 0.539 |
| 0.35 | Red (backprop) s43 | 0.492 | 0.622 | 0.524 |
| 0.35 | ELM s17 | 0.888 | 0.338 | 0.323 |
| 0.35 | Referencia: lo que muestra la app | 0.377 | 0.289 | 0.446 |
| 0.35 | Referencia: adelanto en seco | 3.774 | -5.661 | 0.184 |
| 0.5 | Red (backprop) s17 | 0.584 | 0.736 | 0.664 |
| 0.5 | Red (backprop) s29 | 0.579 | 0.751 | 0.648 |
| 0.5 | Red (backprop) s43 | 0.647 | 0.711 | 0.612 |
| 0.5 | ELM s17 | 0.997 | 0.629 | 0.490 |
| 0.5 | Referencia: lo que muestra la app | 0.723 | 0.244 | 0.516 |
| 0.5 | Referencia: adelanto en seco | 3.468 | -2.213 | 0.307 |
| 0.65 | Red (backprop) s17 | 0.643 | 0.818 | 0.759 |
| 0.65 | Red (backprop) s29 | 0.649 | 0.816 | 0.753 |
| 0.65 | Red (backprop) s43 | 0.673 | 0.809 | 0.742 |
| 0.65 | ELM s17 | 1.105 | 0.744 | 0.594 |
| 0.65 | Referencia: lo que muestra la app | 0.949 | 0.422 | 0.613 |
| 0.65 | Referencia: adelanto en seco | 3.174 | -0.615 | 0.403 |
| 0.8 | Red (backprop) s17 | 0.621 | 0.882 | 0.852 |
| 0.8 | Red (backprop) s29 | 0.599 | 0.882 | 0.866 |
| 0.8 | Red (backprop) s43 | 0.640 | 0.877 | 0.849 |
| 0.8 | ELM s17 | 1.104 | 0.839 | 0.651 |
| 0.8 | Referencia: lo que muestra la app | 0.980 | 0.599 | 0.749 |
| 0.8 | Referencia: adelanto en seco | 1.888 | 0.360 | 0.584 |

**`estres14` por cultivo:**

| Cultivo | Modelo | MAE | R² | F1 |
|---|---|---|---|---|
| maiz | Red (backprop) s17 | 0.307 | 0.815 | 0.804 |
| maiz | Red (backprop) s29 | 0.306 | 0.829 | 0.797 |
| maiz | Red (backprop) s43 | 0.338 | 0.809 | 0.746 |
| maiz | ELM s17 | 0.770 | 0.692 | 0.407 |
| maiz | Referencia: lo que muestra la app | 0.370 | 0.491 | 0.645 |
| maiz | Referencia: adelanto en seco | 1.055 | 0.015 | 0.351 |
| frijol | Red (backprop) s17 | 0.673 | 0.689 | 0.643 |
| frijol | Red (backprop) s29 | 0.669 | 0.682 | 0.631 |
| frijol | Red (backprop) s43 | 0.712 | 0.682 | 0.608 |
| frijol | ELM s17 | 1.086 | 0.553 | 0.480 |
| frijol | Referencia: lo que muestra la app | 0.787 | 0.235 | 0.540 |
| frijol | Referencia: adelanto en seco | 4.848 | -3.376 | 0.261 |
| tomate | Red (backprop) s17 | 0.571 | 0.875 | 0.802 |
| tomate | Red (backprop) s29 | 0.578 | 0.873 | 0.800 |
| tomate | Red (backprop) s43 | 0.591 | 0.875 | 0.782 |
| tomate | ELM s17 | 1.038 | 0.820 | 0.579 |
| tomate | Referencia: lo que muestra la app | 0.826 | 0.587 | 0.709 |
| tomate | Referencia: adelanto en seco | 2.605 | 0.064 | 0.400 |

### Lectura, sin rodeos

- **Estrés (`estres7` y `estres14`):** la red entrenada con retropropagación gana a las dos referencias en las tres semillas, en MAE, R² y F1, en la prueba, en los años reservados y en los pilotos. Para `estres7` en la prueba, el F1 va de 0.857 a 0.866 frente a 0.693 de lo que muestra la app; la red mejora a la vez la precisión (0.79–0.82 frente a 0.72) y el recall (0.92–0.94 frente a 0.67). Para `estres14` el recall sube a 0.91–0.94 (la app: 0.53) pero **la precisión baja** a 0.55–0.60 (la app: 0.76): la red avisa de más estrés, y parte de esos avisos son falsos.
- **`factorFinal`:** la red gana en MAE en las tres semillas en los tres subconjuntos, pero por poco (0.0225 frente a 0.0254 en la prueba), y la ventaja no es pareja. **Por cultivo, en maíz y en frijol el MAE de la red (0.017–0.023 y 0.020–0.021) es mayor que el de lo que ya muestra la app (0.015 y 0.018);** la ventaja viene del tomate (0.027–0.029 frente a 0.046). En R² la red gana en los tres cultivos. Por fracción, a partir del 50 % la red gana en MAE con las tres semillas; en el 20 % y en el 35 % gana solo con dos semillas de tres (la semilla 43 queda peor que la referencia). El R² de la red en la prueba (0.59–0.66) es mucho menor que en validación (0.85–0.86); no se investigó la causa.
- **El ELM no vale la pena aquí:** no gana en MAE a lo que muestra la app en ningún objetivo ni subconjunto (peor en las tres semillas) y en `estres7` su F1 es menor (0.62–0.65 frente a 0.693) en la prueba y en los pilotos; en los años reservados una semilla del ELM (la 17) supera por poco el F1 de la referencia (0.699 frente a 0.694) y las otras dos no. Gana a la referencia de adelanto en seco en MAE de `factorFinal` y `estres14`, pero no en `estres7`. Tiene mejor R² que la referencia (a) en los tres objetivos y un recall alto (0.94–0.97) con precisión baja.
- **Adelanto en seco:** es una cota, no una predicción. En `factorFinal` falla mucho (MAE 0.31) porque supone cero lluvia el resto del ciclo; en `estres7` en el 80 % del ciclo se acerca (F1 0.814) pero la red lo supera (0.911–0.921). Casi nunca deja de avisar (recall 0.995) a costa de la precisión (0.445).
- **Sobre qué sí se puede decir:** en `estres7` y `estres14` la red mejora lo que la app puede calcular hoy sin red, en datos de años que no vio. Sobre `factorFinal`, la mejora existe pero es chica y no vale para maíz y frijol medida por MAE.

### Límites

- El juez es **el motor de la app**, no el campo: la verdad es lo que la app calcularía con el clima real. La red aprende la respuesta de ese motor, no la de un cultivo. No hay validación en campo ni con AquaCrop.
- **La lluvia es la de POWER**, que es la de la app, y difiere de la ERA5 con que se entrenaron los demás modelos de este documento: en los tres pilotos POWER da más lluvia anual (por ejemplo, Chiquimula 1 551.0 mm frente a 1 110.3 de ERA5 en los 20 años en común) y menos días secos seguidos en la canícula; ver `web/data/rain_compare.json`. Los números de esta sección no se comparan con los de las otras secciones.
- A secano. Sin riego, sin plaga ni fertilizante. Tres cultivos (maíz, frijol, tomate); el café queda fuera porque la app no le da Ky. "Hoy" entre el 20 y el 80 % del ciclo.
- Se usa el clima de POWER del propio día de hoy; en la práctica el último dato de POWER puede tardar unos días, y la regla de huecos de la app lo completaría con promedios. Ese caso no se probó.
- El 2025 no se usó para entrenar ni para probar, y se entrenó con 150 000 de 537 600 filas disponibles.
- Una sola partición por año; sin intervalos de confianza. Con 3 semillas, la diferencia entre semillas es chica frente a la diferencia con las referencias, salvo en `factorFinal` por cultivo.
- La red **no está conectada a la app**; `proyecto/contrato-app-modelo.md` explica cómo.

## Más que agua: calor, abono, plagas, dinero y capacidad de resembrar

**Regla de esta sección.** Un factor entra al rendimiento **solo si tiene un número publicado, leído en la fuente misma** (el PDF o la página, no un resumen de búsqueda). Lo que no tiene número queda como aviso o como dato que el usuario declara, y aquí se dice. No se ajustó nada a los eventos de sequía documentados. Todo es opcional y apagado por defecto: sin la opción `factors` el simulador da exactamente los mismos resultados de antes (los artefactos anteriores no cambiaron; se comprobó que `real_events_check.json` se reproduce igual). Los números salen de `web/data/factors_eval.json`, `web/data/factors_real_events_check.json`, `web/data/prices.json` y de las salidas parciales en `scripts/factors/out/`; el código está en `web/js/model/factors.js` y `scripts/factors/`. Las fuentes de los números están en `research_notes/factores-rendimiento.json` (fuera del repositorio).

**Un solo método de decisión.** El equipo conserva **un** método: **predecir y luego elegir** (la red de embudo, entrenada con retropropagación, predice el resultado de cada opción; la elección aplica la prioridad del agricultor y sus restricciones). El recomendador evolutivo queda **archivado tal como está**: no se entrenó ni se extendió aquí.

### Qué entra y qué no

| Factor | ¿Número publicado? | Cómo entra | Fuente |
|---|---|---|---|
| Calor en la floración, maíz y tomate | Sí: la polinización empieza a fallar sobre Tmax 40 °C y bajo Tmin 10 °C (ambos "Estimate"); el coeficiente cae de 1 a 0 en 5 °C más allá del umbral, con forma logística | **Rendimiento** (opcional): el coeficiente diario medio sobre la ventana de floración multiplica el rendimiento relativo limitado por agua | AquaCrop v7.3 (FAO), Annex I (I.2 maíz 4.2, p. 11; I.9 tomate 4.2) y cap. 3, 3.12.5, Fig. 3.12k (p. 3-147), leídos en el PDF |
| Calor en frijol, café y los demás cultivos | **No**: la tabla 15 de frijol no trae umbrales de polinización; para el café arábica solo hay un óptimo de 18–21 °C de temperatura media anual y pérdida de calidad sobre 23 °C, sin pérdida de rendimiento por grado | **Nada** (sin factor) | AquaCrop Annex I; DaMatta y Ramalho 2006 |
| Sensibilidad al calor del maíz (Lobell et al. 2011) | Sí, pero de África: 1 % por grado-día sobre 30 °C (1.7 % bajo sequía) | **Solo como sensibilidad**, apagada, nunca en decisiones | Lobell et al. 2011, Nature Climate Change 1:42–45 (resumen leído; texto completo no) |
| Fertilidad del suelo | Sí, como clase genérica: casi óptima 0.80, moderada 0.60, la mitad 0.50, pobre 0.40, muy pobre 0.25; no declarada = 1 | **Dato que el usuario declara** (opcional): multiplica el rendimiento | AquaCrop cap. 2, tabla 2.13a (p. 2-188) |
| Qué clase corresponde a "abonado / no abonado" | **No** hay fuente | No se inventa la correspondencia | — |
| Plagas | **No** hay función de daño. La caída de 16 % de la producción de café de Centroamérica en 2013 es un agregado regional con estimaciones inciertas | **Aviso**: los avisos de café que ya existían, y el nivel de plaga que observa el agricultor (`ninguna`, `baja`, `media`, `alta`) como dato declarado que se lleva y se muestra. **No cambia el rendimiento** | Avelino et al. 2015, Food Security 7:303–321 |
| Dinero | Precios mayoristas MAGA 2023: maíz blanco Q224.53/qq, frijol negro Q639.28/qq (serie 2019–2023 en `web/data/prices.json`) | **Solo registrado**. **No se calcula margen** | MAGA, El Agro en Cifras 2023, tablas 22 y 26 |
| Poder actuar: `canResow` (hay semilla y dinero para resembrar) y `hasIrrigation` (y su tipo) | No hace falta | **Restricciones declaradas** que se aplican al elegir, no predicciones: con `canResow = false` solo queda dejar el campo | — |

**Cómo es el coeficiente de calor (exacto).** Por día: `Kspol_h` baja de 1 a 0 entre Tmax = 40 °C y 45 °C; `Kspol_c` baja de 1 a 0 entre Tmin = 10 °C y 5 °C; el coeficiente del día es el menor de los dos. La caída es una logística normalizada, `Ks(x) = (s(1) − s(x)) / (s(1) − s(0))` con `s(v) = 1/(1 + exp(−k (v − 0.5)))` y `x` la fracción de los 5 °C ya recorrida, de modo que vale exactamente 1 en el umbral y 0 a 5 °C. **La pendiente `k = 10` es nuestra elección**: la fuente da la forma y los extremos, no la pendiente. **Simplificación nuestra:** AquaCrop aplica el coeficiente al índice de cosecha de referencia; aquí la media del coeficiente sobre la ventana de floración multiplica el rendimiento relativo limitado por agua. La ventana es la que ya usa el simulador para `ksFlower` (el 40 % de la etapa media que sigue al desarrollo). El **ancho de 5 °C** y los umbrales son los publicados.

### El calor, contado antes de reentrenar nada

Se midió con el clima de los 20 puntos, 2001–2024 (ERA5 con Tmax y Tmin corregidas por altitud), en maíz, en primera (siembra por la regla de inicio de lluvias) y en postrera (siembra el 15 de agosto), solo en los años con el ciclo completo. **Regla fijada antes de ver el resultado:** si el calor cambia el rendimiento relativo en más de 0.01 en menos del 1 % de los sitios-año, **no se reentrena nada**.

Por punto (años = sitios-año con el ciclo completo; "coef. < 1" = años con al menos un día de la floración bajo el umbral; "cambio > 0.01" = años en que el rendimiento baja más de 0.01; "mínimo" = menor media de la ventana):

| Punto | Altitud (m) | Primera: años | Primera: coef. < 1 | Primera: cambio > 0.01 | Primera: mínimo | Postrera: años | Postrera: coef. < 1 | Postrera: cambio > 0.01 | Postrera: mínimo |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Chiquimula | 403 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Jutiapa | 903 | 24 | 0 | 0 | 1.000 | 24 | 1 | 0 | 1.000 |
| San Martín Jilotepeque | 1787 | 24 | 4 | 0 | 0.989 | 0 | 0 | 0 | - |
| Esquipulas | 933 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Jocotán | 459 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Quetzaltepeque | 757 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Olopa | 1240 | 24 | 0 | 0 | 1.000 | 24 | 7 | 3 | 0.961 |
| Zacapa | 222 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Gualán | 155 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Guastatoya | 527 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Sanarate | 849 | 24 | 0 | 0 | 1.000 | 24 | 1 | 0 | 0.998 |
| Asunción Mita | 472 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Jalpatagua | 545 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Santa Catarina Mita | 670 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Jalapa | 1374 | 24 | 0 | 0 | 1.000 | 23 | 12 | 2 | 0.829 |
| Monjas | 961 | 24 | 0 | 0 | 1.000 | 24 | 1 | 0 | 1.000 |
| Salamá | 946 | 24 | 0 | 0 | 1.000 | 24 | 0 | 0 | 1.000 |
| Rabinal | 967 | 24 | 0 | 0 | 1.000 | 24 | 1 | 0 | 1.000 |
| Cubulco | 997 | 24 | 0 | 0 | 1.000 | 24 | 1 | 0 | 1.000 |
| Cuilapa | 929 | 24 | 0 | 0 | 1.000 | 24 | 1 | 0 | 1.000 |
| **Total** | | 480 | 4 | 0 | 0.989 | 455 | 25 | 5 | 0.829 |

Distribución del multiplicador (media del coeficiente sobre la floración):

| Calendario | Sitios-año | Mínimo | Percentil 1 | Percentil 5 | Mediana | Media | Mayor caída del rendimiento | Años con cambio > 0.01 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Total | 935 | 0.8293 | 0.9896 | 1 | 1 | 0.99944 | 0.0497 | 5 (0.53 %) |
| Primera | 480 | 0.9891 | 1 | 1 | 1 | 0.99996 | 0.0079 | 0 (0.00 %) |
| Postrera | 455 | 0.8293 | 0.9715 | 0.9999 | 1 | 0.9989 | 0.0497 | 5 (1.10 %) |

**Resultado: no se reentrenó nada.** 5 de 935 sitios-año (0.53 %) cambian en más de 0.01, menos del 1 %. Hay más: **en ningún día de ninguna floración de los 20 puntos y los 24 años llega Tmax a 40 °C** (0 días de calor). Los 29 sitios-año donde el coeficiente baja de 1 son **noches frías** (Tmin bajo 10 °C, 92 días en total), todos en puntos de 849 m o más: San Martín Jilotepeque (1 787 m; 4 años, en primera, con la floración en agosto), Olopa (7 años) y Jalapa (12 años) en postrera, y un solo año con 1 o 2 días fríos en Jutiapa, Sanarate, Monjas, Rabinal, Cubulco y Cuilapa; 25 de los 29 están en postrera, cuando la floración cae entre mediados de noviembre y diciembre. Así que **en esta región y en estos años el umbral publicado de calor casi nunca se alcanza; el factor está implementado pero inactivo para el calor**, y el poco efecto que aparece viene del frío en la altura. La red v3 de siete cultivos **no se reentrenó** (no hay `emulator_v4_*`).

**Sensibilidad de Lobell (solo informativa).** Con los grados-día sobre 30 °C aproximados con la Tmax diaria en todo el ciclo, la sensibilidad de otro continente daría una caída media de 0.20 del rendimiento relativo del maíz (en primera 0.28, en postrera 0.11; 616 de 935 sitios-año cambiarían en más de 0.01). Es una extrapolación lineal de África fuera de su rango y **no se usa en ninguna decisión**; sirve para decir que si esa sensibilidad valiera aquí, el calor sí importaría mucho más que el umbral de AquaCrop, y que no hay forma de saberlo con lo que hay publicado para Guatemala.

### Eventos reales: antes y después del calor

Mismo comprobador de la sección de eventos de sequía documentados (ERA5; acierto = el sitio-año cae en el peor tercio de sus años; mismos umbrales fijos, **nada ajustado**), con el factor de calor del maíz encendido. La fertilidad queda "no declarada" (no hay dato por evento) y el frijol no cambia (sin umbral):

| Periodo | Variante | Aciertos / eventos | Tasa | Falsas alarmas (años sin evento) | AUC contra años sin evento | AUC contra otros años |
|---|---|---:|---:|---:|---:|---:|
| 2001–2016 | Solo agua | 82 / 199 | 0.412 | 4 / 38 | 0.762 | 0.611 |
| 2001–2016 | Agua y calor | 81 / 199 | 0.407 | 4 / 38 | 0.762 | 0.611 |
| 2017–2024 (reservado) | Solo agua | 62 / 132 | 0.470 | 21 / 190 | 0.661 | 0.676 |
| 2017–2024 (reservado) | Agua y calor | 62 / 132 | 0.470 | 22 / 190 | 0.661 | 0.676 |
| Todos | Solo agua | 144 / 331 | 0.435 | 25 / 228 | 0.680 | 0.636 |
| Todos | Agua y calor | 143 / 331 | 0.432 | 26 / 228 | 0.680 | 0.635 |

El calor **no cambia la lectura**: en todos los eventos 144 de 331 aciertos pasan a 143, el AUC contra los años sin evento queda en 0.680 y contra los otros años pasa de 0.636 a 0.635. Es lo esperable con el conteo de arriba.

### La decisión con la información nueva (predecir y luego elegir)

Se usa la red v3 de embudo que ya existía (semillas 17, 29 y 43; la tabla da la media de las tres), porque no se reentrenó. Los casos son los de siempre: **54** (3 pilotos × años 2019–2024 × pérdida del maíz a los 30, 45 o 60 días) y los **27** reservados (2022–2024). La verdad es el simulador en el año Y, solo agua. Las columnas son la media de las tres semillas (por eso hay decimales en los conteos). Rendimiento relativo, sin dinero ni margen. "Típica" elige por la mediana de los años pasados; "cauta", por el percentil 20.

**Pérdida del maíz, 54 casos.** Regla agronómica simple: 0.802; mejor posible (oráculo): 0.971.

| Escenario | Prioridad | Rendimiento relativo medio | Ganancia media sobre la regla | Gana / empata / pierde | p10 | Peor | Casos bajo 0.5 | Acciones (semilla 17) |
|---|---|---:|---:|---:|---:|---:|---:|---|
| Puede resembrar (no declarada fertilidad) | típica | 0.942 | 0.140 | 23.3 / 26.7 / 4.0 | 0.849 | 0.408 | 1.7 | {ajonjolí: 30, frijol: 21, lechuga: 3} |
| Puede resembrar (no declarada fertilidad) | cauta | 0.949 | 0.147 | 26.0 / 19.0 / 9.0 | 0.840 | 0.688 | 0.0 | {ajonjolí: 30, lechuga: 18, frijol: 6} |
| No puede resembrar | típica | 0.000 | 0.000 | 0.0 / 54.0 / 0.0 | 0.000 | 0.000 | 54.0 | {campo libre: 54} |
| No puede resembrar | cauta | 0.000 | 0.000 | 0.0 / 54.0 / 0.0 | 0.000 | 0.000 | 54.0 | {campo libre: 54} |
| Fertilidad: casi óptima | típica | 0.754 | 0.112 | 23.3 / 26.7 / 4.0 | 0.679 | 0.327 | 2.7 | {ajonjolí: 30, frijol: 21, lechuga: 3} |
| Fertilidad: casi óptima | cauta | 0.759 | 0.118 | 26.0 / 19.0 / 9.0 | 0.672 | 0.550 | 0.0 | {ajonjolí: 30, lechuga: 18, frijol: 6} |
| Fertilidad: moderada | típica | 0.565 | 0.084 | 23.3 / 26.7 / 4.0 | 0.510 | 0.245 | 5.0 | {ajonjolí: 30, frijol: 21, lechuga: 3} |
| Fertilidad: moderada | cauta | 0.569 | 0.088 | 26.0 / 19.0 / 9.0 | 0.504 | 0.413 | 5.0 | {ajonjolí: 30, lechuga: 18, frijol: 6} |
| Fertilidad: la mitad | típica | 0.471 | 0.070 | 23.3 / 26.7 / 4.0 | 0.425 | 0.204 | 24.7 | {ajonjolí: 30, frijol: 21, lechuga: 3} |
| Fertilidad: la mitad | cauta | 0.475 | 0.074 | 26.0 / 19.0 / 9.0 | 0.420 | 0.344 | 28.7 | {ajonjolí: 30, lechuga: 18, frijol: 6} |
| Fertilidad: pobre | típica | 0.377 | 0.056 | 23.3 / 26.7 / 4.0 | 0.340 | 0.163 | 54.0 | {ajonjolí: 30, frijol: 21, lechuga: 3} |
| Fertilidad: pobre | cauta | 0.380 | 0.059 | 26.0 / 19.0 / 9.0 | 0.336 | 0.275 | 54.0 | {ajonjolí: 30, lechuga: 18, frijol: 6} |
| Fertilidad: muy pobre | típica | 0.236 | 0.035 | 22.7 / 27.7 / 3.7 | 0.212 | 0.102 | 54.0 | {ajonjolí: 30, frijol: 21, lechuga: 3} |
| Fertilidad: muy pobre | cauta | 0.237 | 0.037 | 25.0 / 20.7 / 8.3 | 0.210 | 0.172 | 54.0 | {ajonjolí: 30, lechuga: 18, frijol: 6} |

**Pérdida del maíz, 27 casos reservados.** Regla agronómica simple: 0.856; oráculo: 0.979.

| Escenario | Prioridad | Rendimiento relativo medio | Ganancia media sobre la regla | Gana / empata / pierde | p10 | Peor | Casos bajo 0.5 | Acciones (semilla 17) |
|---|---|---:|---:|---:|---:|---:|---:|---|
| Puede resembrar (no declarada fertilidad) | típica | 0.953 | 0.097 | 11.0 / 15.0 / 1.0 | 0.895 | 0.531 | 0.3 | {ajonjolí: 15, frijol: 11, lechuga: 1} |
| Puede resembrar (no declarada fertilidad) | cauta | 0.961 | 0.105 | 12.7 / 10.0 / 4.3 | 0.884 | 0.768 | 0.0 | {ajonjolí: 15, lechuga: 9, frijol: 3} |
| No puede resembrar | típica | 0.000 | 0.000 | 0.0 / 27.0 / 0.0 | 0.000 | 0.000 | 27.0 | {campo libre: 27} |
| No puede resembrar | cauta | 0.000 | 0.000 | 0.0 / 27.0 / 0.0 | 0.000 | 0.000 | 27.0 | {campo libre: 27} |
| Fertilidad: casi óptima | típica | 0.763 | 0.078 | 11.0 / 15.0 / 1.0 | 0.716 | 0.425 | 1.3 | {ajonjolí: 15, frijol: 11, lechuga: 1} |
| Fertilidad: casi óptima | cauta | 0.769 | 0.084 | 12.7 / 10.0 / 4.3 | 0.707 | 0.614 | 0.0 | {ajonjolí: 15, lechuga: 9, frijol: 3} |
| Fertilidad: moderada | típica | 0.572 | 0.058 | 11.0 / 15.0 / 1.0 | 0.537 | 0.318 | 1.3 | {ajonjolí: 15, frijol: 11, lechuga: 1} |
| Fertilidad: moderada | cauta | 0.577 | 0.063 | 12.7 / 10.0 / 4.3 | 0.530 | 0.461 | 1.3 | {ajonjolí: 15, lechuga: 9, frijol: 3} |
| Fertilidad: la mitad | típica | 0.477 | 0.049 | 11.0 / 15.0 / 1.0 | 0.447 | 0.265 | 10.0 | {ajonjolí: 15, frijol: 11, lechuga: 1} |
| Fertilidad: la mitad | cauta | 0.481 | 0.053 | 12.7 / 10.0 / 4.3 | 0.442 | 0.384 | 13.7 | {ajonjolí: 15, lechuga: 9, frijol: 3} |
| Fertilidad: pobre | típica | 0.381 | 0.039 | 11.0 / 15.0 / 1.0 | 0.358 | 0.212 | 27.0 | {ajonjolí: 15, frijol: 11, lechuga: 1} |
| Fertilidad: pobre | cauta | 0.384 | 0.042 | 12.7 / 10.0 / 4.3 | 0.353 | 0.307 | 27.0 | {ajonjolí: 15, lechuga: 9, frijol: 3} |
| Fertilidad: muy pobre | típica | 0.238 | 0.024 | 11.0 / 15.0 / 1.0 | 0.224 | 0.133 | 27.0 | {ajonjolí: 15, frijol: 11, lechuga: 1} |
| Fertilidad: muy pobre | cauta | 0.240 | 0.026 | 12.7 / 10.0 / 4.3 | 0.221 | 0.192 | 27.0 | {ajonjolí: 15, lechuga: 9, frijol: 3} |

Lectura:

- **Con `canResow = false` todas las políticas dejan el campo** (valor 0 en los 54 y en los 27 casos). No es una predicción: es la restricción, y por eso "ganancia sobre la regla" y "gana/empata/pierde" no significan nada en esas filas (la regla también da 0 porque nada se puede sembrar). Lo útil es saber que, sin semilla o sin dinero, el modelo no tiene otra opción que decirlo así.
- **La fertilidad cambia el nivel, no la elección.** El multiplicador es el mismo para todos los cultivos resembrados, así que no cambia cuál es el mejor: en las cinco clases la red elige **la misma acción en los 54 casos y en los 27, con las tres semillas** (comprobado volviendo a decidir con las predicciones multiplicadas, no supuesto). Lo que baja es el rendimiento esperado (0.942 → 0.754, 0.565, 0.471, 0.377 y 0.236 en los 54 casos con prioridad típica) y cuántos casos quedan bajo 0.5. Dejar el campo (valor 0) tampoco se vuelve la mejor opción en ninguna clase: la fertilidad más baja aún deja los cultivos por encima de 0. Los conteos "gana/empata/pierde" frente a la regla cambian apenas porque la tolerancia de empate (0.001) no escala con el multiplicador.
- Estas filas de fertilidad son un **qué pasaría si**: las clases son genéricas de AquaCrop, sin calibrar para Guatemala, y no hay fuente que diga a qué clase corresponde "abonado" o "no abonado".

### Café: el aviso de antracnosis por estrés sube la prioridad a "proteger el cultivo"

**Regla (aprobada en principio por el dueño):** si el aviso de antracnosis está activo **por estrés hídrico** (Ks < 1 en más de la mitad de los últimos 28 días), la prioridad del riego pasa a "proteger el cultivo" (precio 1 día de estrés evitado), diga lo que diga el agricultor. Si el aviso está activo solo por roya o no está activo, la prioridad no cambia. Está en `effectivePriority` de `web/js/model/coffee.js`.

Medida en los escenarios de prueba (café, sitios de al menos 900 m; 1 620 escenarios de los años 2019–2024 y, aparte, los 810 de 2022–2024), con la red exportada de predecir y luego elegir (`web/data/coffee_ptc_mlp.json`, semilla 29) y con la regla FAO-56 (riega si la merma corrida pasa de 0.40 del agua disponible). "Días de aviso" = días, entre los 30 siguientes al de la decisión, con el aviso de antracnosis por estrés activo, recalculados día a día con el balance de agua, sin riego y con el riego de 20 mm recomendado. Utilidad = días de estrés evitados menos el precio (3 o 1); no regar vale 0.

**1 620 escenarios (2019–2024).** El aviso por estrés está activo el día de la decisión en 685; la regla del aviso cambia la decisión de la red en 170 (todas agregan un riego).

| Política | Prioridad | Riegos | Utilidad (ahorrar agua) | Utilidad (proteger) | Días de aviso por estrés, sin riego | Días de aviso, con el riego recomendado | Escenarios con algún día, sin / con |
|---|---|---:|---:|---:|---:|---:|---|
| Regla FAO-56 | no usa prioridad | 633 | 0.036 | 0.818 | 8.56 | 7.67 | 765 / 755 |
| Red (predecir y elegir) | ahorrar agua | 457 | 0.523 | 1.088 | 8.56 | 7.62 | 765 / 728 |
| Red (predecir y elegir) | proteger el cultivo | 739 | 0.310 | 1.223 | 8.56 | 7.47 | 765 / 719 |
| Red (predecir y elegir) | ahorrar agua + regla del aviso | 627 | 0.402 | 1.177 | 8.56 | 7.52 | 765 / 728 |

**810 escenarios reservados (2022–2024).** El aviso está activo en 413; la regla cambia 121 decisiones de la red (todas agregan un riego).

| Política | Prioridad | Riegos | Utilidad (ahorrar agua) | Utilidad (proteger) | Días de aviso por estrés, sin riego | Días de aviso, con el riego recomendado | Escenarios con algún día, sin / con |
|---|---|---:|---:|---:|---:|---:|---|
| Regla FAO-56 | no usa prioridad | 396 | -0.177 | 0.801 | 10.97 | 10.03 | 468 / 463 |
| Red (predecir y elegir) | ahorrar agua | 238 | 0.565 | 1.153 | 10.97 | 9.94 | 468 / 450 |
| Red (predecir y elegir) | proteger el cultivo | 411 | 0.352 | 1.367 | 10.97 | 9.78 | 468 / 443 |
| Red (predecir y elegir) | ahorrar agua + regla del aviso | 359 | 0.373 | 1.259 | 10.97 | 9.84 | 468 / 450 |

Lectura:

- **La regla del aviso hace lo que dice y cuesta lo que cuesta.** Con el agricultor pidiendo ahorrar agua, la red pasa de 457 a 627 riegos (1 620 escenarios), la utilidad con prioridad "proteger" sube de 1.088 a 1.177 y la de "ahorrar" baja de 0.523 a 0.402. Es un cambio de prioridad, no una mejora gratis.
- **El riego recomendado quita pocos días de aviso:** de 8.56 a 7.52 días en promedio en los 30 siguientes (la red con la regla del aviso) frente a 7.62 (sin la regla) y 7.47 (siempre "proteger"). Un solo riego de 20 mm no apaga una racha de estrés de semanas, y el número de escenarios con algún día de aviso baja de 765 a 728. El aviso mide estrés de agua, no enfermedad.
- **La regla FAO-56 no usa la prioridad**, así que la regla del aviso no puede cambiar lo que decide (633 riegos en las tres filas). Su utilidad es 0.036 con "ahorrar" y 0.818 con "proteger", peor que la red en ambas.
- **Roya y minador se reportan al lado y no cambian la decisión** (ninguna fuente los enlaza con el riego): en los 30 días siguientes hay en promedio 9.8 días de roya "favorable" por escenario (6.4 en 2022–2024) y **0 días de minador "probable"** en estos escenarios.
- Las cifras de la red exportada coinciden con las de `coffee_eval.json` para las políticas sin aviso (verificado en las pruebas).

### Qué queda fuera y por qué

- **Plagas:** ninguna fuente da una función de daño (el 16 % de 2013 es un agregado regional con estimaciones inciertas, y los porcentajes del cogollero solo salieron de resúmenes de búsqueda, sin verificar). Las plagas **no cambian el rendimiento**; entran como aviso y como el nivel que declara el agricultor.
- **Respuesta al abono en Guatemala:** no hay un número publicado verificado de con y sin fertilizante (ICTA, CIMMYT, Anacafe); solo las clases genéricas de AquaCrop, que el usuario declara.
- **Margen:** no hay costos de producción por manzana (maíz, frijol, café), ni costo de semilla, ni rendimientos alcanzables usables; los precios MAGA son **mayoristas** (La Terminal, zona 4), no los que recibe el agricultor. Se registran en `web/data/prices.json` y **no se calcula margen**.
- **Calor en frijol y café:** no hay umbral ni pérdida por grado en las fuentes leídas.
- **Qué no se hizo:** no se reentrenó la red de siete cultivos (el calor casi nunca actúa); no se probó la regla del aviso con una red entrenada con ella; el nivel de plaga declarado y `hasIrrigation` se llevan y se muestran, pero solo `canResow` y la fertilidad se midieron en las decisiones; y el cambio de calor del maíz en los 20 puntos se midió con ERA5 solamente.

**Cómo reproducir esta sección.**

```bash
node scripts/factors/heat_counts.mjs                 # conteo del calor en los 20 puntos (scripts/factors/out/factors_heat_counts.json)
node scripts/compare/real_events_check.mjs --heat    # eventos reales con calor (web/data/factors_real_events_check.json; sin --heat reproduce real_events_check.json)
node scripts/factors/loss_constraints.mjs            # pérdida del maíz: canResow y fertilidad (~1.5 min)
node scripts/factors/coffee_notices.mjs              # café: regla del aviso de antracnosis (~20 s)
node scripts/factors/build_eval.mjs                  # junta todo en web/data/factors_eval.json
```


## Sombra de banano (supuesto provisional) y paridad entre algoritmo y simulador

> **Versión archivada.** Esta sección describe la fórmula por cobertura de la tarea 38 y su revisión de la tarea 40. El banano se corrigió en la tarea 41 con las clases de sistema de la auditoría del asesor: ver más abajo «Banano corregido según el asesor del equipo». Los archivos `_v2` y `banana_audit_check.json` siguen sin cambios.

**Aviso por delante.** La sombra de banano que sigue es un **supuesto provisional**. No hay ninguna medida del uso de agua del banano disperso como sombra del café que pudiéramos usar (en las notas, `research_notes/sombra-banano.md`, ningún artículo se leyó completo). Los números de esta sección dicen qué hace **el supuesto** dentro del simulador y de la red; no dicen qué hace un platanar de verdad en un cafetal. Todo es opcional: sin banano, el simulador da lo mismo que antes y `coffee_eval.json`, `coffee_ptc_mlp.json` y `coffee_recommender.json` no cambiaron (las filas de las tres sombras originales de la tabla nueva salen idénticas a las de la anterior: 6,480 filas, diferencia máxima 0). Los números salen de `web/data/coffee_eval_v2.json`, `web/data/coffee_ptc_mlp_v2.json` y `web/data/parity.json`.

### Los dos supuestos y de dónde salen

La entrada que declara el agricultor es `bananaCover`: la fracción del suelo del lote cubierta por la copa del banano (0 a 1). **0.15 y 0.30 son convenciones de los escenarios**, no medidas.

1. **Menos evaporación del suelo.** Igual que los otros árboles: 0.52 mm/día menos en la estación de lluvias (mayo a octubre) y nada en la seca (Padovan et al. 2018, Nicaragua, un solo sitio). Con `bananaCover = 0` no hay banano y no hay recorte. El recorte **no** crece con la cobertura: es el mismo valor para 0.15 y 0.30 (una sola medida, con una sombra de 57 % de la irradiancia). **Es un proxy de sombra de árboles, no un efecto del mulch de banano**: el asesor ata la menor evaporación del suelo al mulch de pseudotallos y hojas de *Musa* y a reemplazar las malezas vivas (`conocimiento/cafe-ciclo-y-asocio-banano.md`, §3.3 y §7.1), y el modelo no sabe si hay mulch.
2. **Agua que gasta el banano.** Cada día se suma al lote `bananaCover × 1.10 × ET0 × KsBanana`. El 1.10 es el Kc de FAO-56 Tabla 12 para banano de segundo año (retoño) al final de temporada (la tabla da 1.00, 1.20 y 1.10; elegir el 1.10 es convención). `KsBanana` es el coeficiente de estrés de FAO-56 con **la p propia del banano, 0.35** (Tabla 22): vale 1 mientras el agotamiento de la zona radicular no pase de 0.35 del agua disponible y baja en línea recta hasta 0 cuando el suelo se agota. La idea del dueño, que esto codifica: el banano guarda agua en sus tejidos y se apaga pronto cuando el suelo se seca, así que en una sequía deja de gastar en vez de competir con el café (la p del café es 0.40, el banano se retira primero). **No** se modela que el banano le dé agua al café (no hay fuente), solo que deja de consumir. Estas cifras son de plantación completa de banano, no de plantas dispersas como sombra.

Como el gasto depende del estado del suelo de ese día, se calcula **dentro** del bucle diario (`simulateDays`, opción `plotAdjust.addFn`; los arreglos constantes de antes siguen funcionando). Como en los otros árboles, el Ks del café se aplica a la demanda completa del lote, banano incluido; y la razón ETa/ETc de las tablas usa el ETc del lote, que con banano incluye el gasto del banano.

**Lo que dice el único estudio de campo que leímos, y lo que dice el asesor.** Sarmiento-Soler et al. 2019 (Monte Elgón, Uganda; solo se leyó el resumen) vieron que la humedad del suelo bajó **6 %** bajo banano frente a **59 %** bajo árboles de *Cordia*. Ese dato es de otro país y otra densidad (no la encontramos) y solo lo leímos en resumen: **no alcanza para decir que nuestro supuesto sobreestima el consumo del banano**. La base de conocimiento del asesor agroclimático del equipo cita ese mismo artículo para lo contrario: que con densidad alta, estación seca larga o suelo somero el banano compite por agua (`conocimiento/cafe-ciclo-y-asocio-banano.md`, §3.3), y la auditoría numérica del asesor da que, **a igual manejo del suelo, el café con banano tiene más déficit hídrico que el café solo en 3,240 de 3,240 pares de secano** (`auditorias/prueba cafe banano 2025/`, véase la subsección siguiente). Con el supuesto, el estrés con banano 0.30 es prácticamente el del deciduo (abajo); eso es coherente con la auditoría, no una tensión.

### Variante sin KsBanana (sensibilidad)

Para ver qué pone en el resultado la elección de que el banano se apague, se corrió también la variante en que el banano gasta igual con el suelo seco. Va aparte, con la misma red v2 juzgada por ese simulador. En días de estrés casi no cambia (abajo), porque en la estación seca el café ya está en estrés casi todos los días; donde sí se nota es en ETa/ETc.

### Resultados por tipo de sombra

Casos de prueba 2019–2024: 540 por tipo de sombra (10 sitios de 900 m o más × 3 suelos × 6 años × 3 días de decisión). Utilidad media de la red v2 (media de las semillas 17, 29 y 43) y de la regla FAO-56; más alto es mejor. La regla riega en 211 de 540 casos en todos los tipos, porque su balance corrido no ve la sombra.

**Años nuevos 2019–2024**

| Sombra | Ahorrar agua: red / regla / riegos de 540 | Proteger el cultivo: red / regla / riegos de 540 |
|---|---|---|
| Ninguna | 0.402 / 0.096 / 157 | 1.133 / 0.878 / 245 |
| Siempreverde | 0.190 / −0.087 / 145 | 0.882 / 0.694 / 226 |
| Deciduo | 0.790 / 0.100 / 193 | 1.681 / 0.881 / 289 |
| Banano 0.15 | 0.448 / 0.081 / 170 | 1.204 / 0.863 / 262 |
| Banano 0.30 | 0.771 / 0.128 / 188 | 1.656 / 0.909 / 285 |
| Banano 0.15, sin KsBanana | 0.413 / 0.122 / 193 | 1.230 / 0.904 / 268 |
| Banano 0.30, sin KsBanana | 0.700 / −0.011 / 215 | 1.613 / 0.770 / 292 |

**Años reservados 2022–2024** (270 por tipo)

| Sombra | Ahorrar agua: red / regla / riegos de 270 | Proteger el cultivo: red / regla / riegos de 270 |
|---|---|---|
| Ninguna | 0.438 / −0.085 / 85 | 1.311 / 0.893 / 142 |
| Siempreverde | 0.101 / −0.300 / 85 | 0.977 / 0.678 / 131 |
| Deciduo | 0.859 / −0.144 / 104 | 1.778 / 0.833 / 162 |
| Banano 0.15 | 0.547 / −0.081 / 95 | 1.426 / 0.896 / 151 |
| Banano 0.30 | 0.832 / −0.093 / 103 | 1.821 / 0.885 / 162 |
| Banano 0.15, sin KsBanana | 0.522 / −0.044 / 110 | 1.448 / 0.933 / 154 |
| Banano 0.30, sin KsBanana | 0.704 / −0.263 / 123 | 1.704 / 0.715 / 164 |

Lo que se ve: con banano, la red sigue ganándole a la regla en todos los tipos y en ambas prioridades. Pero **esa utilidad es del supuesto**: la red aprendió lo que el simulador dice del banano, y el simulador dice lo que el supuesto le manda. Que la red "funcione con banano" no valida el banano. Con 0.30 la red se parece a la del deciduo; con 0.15, a la de sin sombra con un poco más de estrés.

**Estrés del simulador sin riego** (días con Ks < 1; media sobre sitios, suelos y años cafetaleros). Cuajado = 90 días tras la floración; llenado = días 91 a 120; seca = noviembre a abril (181 días).

2001–2024 (720 combinaciones por tipo)

| Sombra | Días de estrés: cuajado | llenado de grano | estación seca | ETa/ETc: cuajado | llenado | seca |
|---|---|---|---|---|---|---|
| Ninguna | 41.3 | 6.6 | 153.9 | 0.741 | 0.934 | 0.334 |
| Siempreverde | 39.3 | 5.3 | 155.0 | 0.742 | 0.951 | 0.323 |
| Deciduo | 46.0 | 9.6 | 157.3 | 0.725 | 0.893 | 0.319 |
| Banano 0.15 | 41.8 | 7.1 | 158.8 | 0.746 | 0.933 | 0.320 |
| Banano 0.30 | 45.9 | 9.7 | 163.6 | 0.739 | 0.902 | 0.302 |
| Banano 0.15, sin KsBanana | 42.7 | 7.3 | 158.9 | 0.720 | 0.925 | 0.290 |
| Banano 0.30, sin KsBanana | 47.4 | 10.2 | 163.8 | 0.690 | 0.883 | 0.250 |

2019–2024 (los mismos, solo años de prueba; 180 por tipo)

| Sombra | Días de estrés: cuajado | llenado de grano | estación seca | ETa/ETc: cuajado | llenado | seca |
|---|---|---|---|---|---|---|
| Ninguna | 39.5 | 3.8 | 145.1 | 0.751 | 0.973 | 0.366 |
| Siempreverde | 37.7 | 2.5 | 146.8 | 0.752 | 0.984 | 0.353 |
| Deciduo | 44.3 | 7.8 | 148.0 | 0.734 | 0.938 | 0.354 |
| Banano 0.15 | 40.0 | 4.4 | 150.6 | 0.759 | 0.971 | 0.351 |
| Banano 0.30 | 44.3 | 8.0 | 156.0 | 0.754 | 0.943 | 0.335 |
| Banano 0.15, sin KsBanana | 40.8 | 4.6 | 150.7 | 0.732 | 0.967 | 0.319 |
| Banano 0.30, sin KsBanana | 45.8 | 8.5 | 156.2 | 0.704 | 0.930 | 0.279 |

Los días de estrés evitables por un riego de 20 mm (media de los 540 casos de prueba por tipo, 30 días siguientes sin riego): ninguna 1.75, siempreverde 1.44, deciduo 2.47, banano 0.15 1.86, banano 0.30 2.48, y sin KsBanana 1.91 y 2.44.

Dos cosas honestas sobre estas tablas. (1) La estación seca sale con 145 a 164 días de estrés de 181 aun sin sombra: el simulador del café no tiene riego ni agua de fondo, así que el banano casi no puede empeorar eso, y `KsBanana` casi no se nota en días de estrés (cuajado 45.9 con él y 47.4 sin él, a 0.30). (2) La diferencia entre tipos es pequeña frente a esa base; no se calculó incertidumbre entre sitios o suelos más allá de lo mostrado.

### Red v1 contra red v2 en los escenarios originales

Mismas 1,620 filas de prueba (sin banano: ninguna, siempreverde, deciduo); v1 es `coffee_eval.json`. Media de las tres semillas; entre paréntesis, el mínimo y el máximo entre semillas.

| Prioridad | v1 | v2 | Diferencia | Riegos de 1,620: v1 → v2 |
|---|---|---|---|---|
| Ahorrar agua (años 2019–2024) | 0.474 (0.420 a 0.523) | 0.460 (0.450 a 0.478) | −0.014 | 443 → 495 |
| Proteger el cultivo (2019–2024) | 1.174 (1.022 a 1.276) | 1.232 (1.217 a 1.246) | +0.058 | 984 → 760 |
| Ahorrar agua (reservados 2022–2024, 810) | 0.500 | 0.466 | −0.034 | 242 → 273 |
| Proteger el cultivo (reservados) | 1.311 | 1.355 | +0.044 | 528 → 435 |

Por sombra, en 2019–2024 (ahorrar agua / proteger): ninguna 0.419 → 0.402 / 1.066 → 1.133; siempreverde 0.193 → 0.190 / 0.794 → 0.882; deciduo 0.810 → 0.790 / 1.661 → 1.681. **Agregar banano no cambió nada que se distinga de la variación entre semillas**: las diferencias (−0.014 y +0.058) caen dentro del rango entre semillas de v1. El cambio de cuántas veces riega (más con ahorrar agua, menos con proteger) podría ser también variación entre entrenamientos; no se probó con más semillas.

La red v2 exportada (semilla 29, la de menor pérdida de validación) tiene utilidad media sobre las cinco sombras de 0.503 (ahorrar) y 1.300 (proteger) en 2,700 casos de prueba, y 0.544 y 1.445 en 1,350 reservados. Para comparar con v1 hay que usar las tablas por sombra, no estos agregados, porque v2 incluye casos de banano. `mlpPredict` reproduce a PyTorch con diferencia menor de 1e-5 en 50 casos guardados (`tests/coffee_ptc_v2.test.mjs`).

### Paridad: qué toma cada red y si el simulador responde

Cada entrada de las tres redes que el equipo conserva se clasificó leyendo el código. Clase 1: mueve el simulador directamente (clima, suelo, cultivo, fechas, sombra). Clase 2: resumen derivado de cosas que mueven el simulador, o salida del propio simulador hasta hoy. Clase 3: no tiene efecto en el simulador. La lista completa, entrada por entrada con su razón, está en `web/data/parity.json` (el guion `scripts/parity/build_parity.mjs` falla si falta o sobra una).

| Red | Entradas | Clase 1 | Clase 2 | Clase 3 |
|---|---|---|---|---|
| Predictor de siete cultivos v3 (`emulator_v3_mlp.json`) | 47 | 21 | 26 | 0 |
| Café predecir-y-elegir v2 (`coffee_ptc_mlp_v2.json`) | 18 | 6 | 12 | 0 |
| Red alineada con la app (`app_mlp.json`) | 40 | 15 | 24 | 1 |

- **Siete cultivos v3.** Clase 1: `sowDoyA`, `offset30` (siembra), `A_*` y `B_*` de cultivo (incluida `B_none`), `soil_*` y `elevation`. Clase 2: las sumas de lluvia y ET0 (`rainMJJ`, `rainASO`, `rainYear`, `caniculaDays`, `et0MeanMO`, `tmeanMO`, `rain0to60`, `et0_0to60`, `rain61to150`, `et0_61to150`) y las ocho por cultivo (`rainPre30`, `et0Pre30`, `apiFlower`, `storeProxy`, `rainFlower`, `deficitFlower`, `cycleDays`, `daysLeft`) para A y B. Ninguna sin efecto. El archivo `emulator_v3_mlp.json` no trae `inputNames`; los nombres son los de `FEATURE_NAMES_V3`, el orden con que se generaron las muestras.
- **Café v2.** Clase 1: `doy`, `shadeTrees`, `deciduous`, `banana`, `bananaCover` (estas dos, por el supuesto provisional) y `elevation` (solo por la ET0). Clase 2: las sumas y medias de clima, `daysSinceFlowering`, `runningDepletion` (una cuenta acotada simple, no el Dr del simulador) y `soilAWmm` (TAW). Ninguna sin efecto.
- **Red alineada con la app.** Clase 1: `lat`, `cellElevation`, fecha de siembra y de hoy (seno y coseno), cultivo, `cycleDays`, `soilAvailableWater`, `kcMid`, `rootDepth`, `p`, `ky`. Clase 2: etapa, fracción del ciclo, `reserve`, `depletionOverTaw`, `ks`, `factorSoFar`, días de estrés, sumas de lluvia y ET0, `longestDrySpell28`, temperaturas, `cropNeed7` (varias son salidas del propio motor de la app hasta hoy). **Clase 3: `lon`.** El motor de la app calcula la ET0 solo con latitud y elevación y el clima ya viene descargado: la longitud no mueve nada; solo identifica el punto de donde se bajó el clima.
- **`elevation`, `lat` y `cellElevation`** mueven el simulador solo por la ET0 y poco: subir 900 m la elevación de Jutiapa sube la ET0 media 0.7 %. Y con la ET0 ya calculada, cambiar solo la elevación no mueve el balance.

**Información que el algoritmo usa al decidir y que no es entrada de la red**

| Dato | Cómo actúa | ¿Responde el simulador? |
|---|---|---|
| Prioridad (ahorrar agua / proteger; café) | Criterio de elección: fija el precio de regar (3 o 1 días de estrés). La regla del aviso de antracnosis por estrés la sube a "proteger" | No: el simulador solo da los días de estrés evitados; la prioridad solo cambia el precio con que se juzga |
| `canResow` (puedo resembrar) | Restricción declarada: con falso solo queda dejar el campo | No: se aplica al elegir |
| `hasIrrigation` / tipo de riego | Restricción declarada | No: se declara y se muestra; el simulador tiene modos de riego, pero esta bandera no los cambia |
| Clase de fertilidad | Multiplicador declarado del rendimiento (AquaCrop tabla 2.13a) | Sí, con la opción `factors.fertilityClass` (apagada por defecto); la red no la ve y no se reentrenó: la decisión multiplica las predicciones |
| Calor en floración (maíz, tomate) | Opción del simulador | Sí, con `factors.heat` (apagada por defecto); ninguna red lo toma como entrada |
| Nivel de plaga declarado y avisos de roya, minador, antracnosis | Solo aviso | No: no hay función de daño con fuente |
| Momento del abono | Solo aviso (ventanas de Anacafe y suelo húmedo) | No |
| Precios MAGA | Solo registro | No: no se calcula margen |
| Pendiente, modo de riego, tipo de sucesión | Entradas del simulador que el predictor v3 no toma (se entrenó con pendiente plana y sin riego) | Sí, pero la red no las ve |

**Lo que el algoritmo muestra y el simulador no responde, dicho sin rodeos:** `lon` de la red de la app; la prioridad (cambia la decisión, no el simulador); `canResow` y `hasIrrigation` declarados; el nivel de plaga y los avisos de plagas; el aviso de abono; y los precios. Además, `banana` y `bananaCover` hacen responder al simulador, pero solo por el supuesto provisional. Entre las entradas de las tres redes, solo `lon` no mueve el simulador.

### Nuestro modelo frente a la auditoría del asesor (tarea 40)

Un compañero publicó (rama `origin/main`, commit `ac37f1b`) el asesor agroclimático (`.codex/agents/asesor_agroclimatico.toml`), su base de conocimiento (`conocimiento/cafe-ciclo-y-asocio-banano.md`) y una auditoría numérica de café solo contra café + banano en Chiquimula, 2025 (`auditorias/prueba cafe banano 2025/`). Se revisó nuestra implementación contra ellos y se corrió nuestro simulador en el escenario de la auditoría: `node scripts/coffee/verify_banana_audit.mjs` escribe `web/data/banana_audit_check.json` (las cifras de la auditoría están copiadas, sin cambios, en `scripts/coffee/banana_audit_reference.json`; `tests/banana_audit.test.mjs` las fija).

**Lo que la auditoría dice.** Sitio 14.8250, −89.5312 (373 m), 2025, TAW 130.7 mm (0–100 cm), escorrentía 15 %, reserva inicial 25 %, secano. Café solo con suelo limpio (Kc 0.90/0.95/0.95, p 0.40): ETc 1,404.76 mm. Café + banano con sombra regulada y mulch de *Musa* (Kc 0.95/1.05/1.00, p 0.38): ETc 1,525.49 mm. Bananal denso sin deshije (Kc 1.00/1.20/1.10, p 0.35): ETc 1,699.12 mm. En los 3,240 pares de secano el café con banano tiene **más** déficit que el café solo en todos. El sistema con banano tiene **menos** déficit (77 a 101 mm) solo frente a café al sol **con malezas vivas** (Kc 1.05/1.10/1.10), gracias al mulch de *Musa* y a quitar la maleza; el bananal denso es el peor. La luz y el microclima (el banano amortigua la temperatura máxima 1.5 a 3 °C) no entran al balance de agua de la auditoría, que usa un Kc compuesto por variante.

**Qué se corrió** (2025, secano; demanda = Σ ETc del lote, déficit = demanda − ETa; días de estrés con Ks < 0.95, la definición de la auditoría, y con Ks < 1):

- **Corrida A**, el simulador como lo usa la app: clima del snapshot `web/data/snapshots/chiquimula.json` (lluvia ERA5, 1,020.5 mm en 2025, la misma suma que la fila ERA5 de la auditoría; temperaturas de NASA POWER llevadas a 403 m; ET0 de 2025 = 1,594 mm), suelo SoilGrids del piloto (TAW 180 mm sobre Zr 1.2 m), escorrentía SCS-CN, serie continua 2001–2025.
- **Corrida B**, lo más cerca de la auditoría que permite nuestro código sin cambiarlo: solo 2025 desde el 1 de enero, TAW 130.7 mm sobre la zona radicular (misma θWP del piloto, θFC ajustada), reserva inicial 25 % (Dr = 75 % de TAW), escorrentía fija 15 % (nuestro código usa SCS-CN diario y no admite una fracción fija: se entró con lluvia efectiva 0.85·P y CN mínimo, escorrentía cero en el modelo). No se pudo igualar: el Kc del café por etapas (nosotros 0.95 constante), la profundidad radicular (nosotros 1.2 m, la auditoría 1.0 m; se igualó TAW, no Zr), la p del lote (nosotros 0.40 para todo el lote; la auditoría 0.38 y 0.35 según la variante), la fórmula del banano (la nuestra suma el gasto del banano; la auditoría usa un Kc compuesto) y el suelo de cinco capas.
- **Corrida C**: como B pero con las entradas diarias congeladas de la auditoría (ET0 FAO-56 de NASA POWER, 1,502 mm, y lluvia ERA5 de su CSV), para separar lo que viene del clima de lo que viene de la fórmula.

| Cantidad, 2025, secano | Auditoría (fila ERA5) | Nuestro, B | Nuestro, C |
|---|---:|---:|---:|
| Demanda, café solo (mm) | 1,404.76 | 1,514.56 | 1,426.96 |
| Demanda, banano menos solo (mm) | regulado +120.73 (+8.6 %); denso +294.36 (+21.0 %) | cobertura 0.15: +29.10 (+1.9 %); 0.30: +139.66 (+9.2 %) | 0.15: +26.03 (+1.8 %); 0.30: +134.28 (+9.4 %) |
| Déficit, café solo (mm) | 648.26 | 749.39 | 681.80 |
| Déficit, banano menos solo (mm) | regulado +96.36; denso +238.74 | 0.15: +20.42; 0.30: +91.02 | 0.15: +18.15; 0.30: +84.90 |
| Días con Ks < 0.95, café solo | 249 | 264 | 257 |
| Días con Ks < 0.95, banano menos solo | regulado +15; denso +27 | 0.15: +5; 0.30: +12 | 0.15: +6; 0.30: +16 |
| Días con Ks < 1, banano menos solo (la auditoría no lo da) | — | 0.15: +2; 0.30: +9 | 0.15: +5; 0.30: +11 |

La corrida A, la de la app tal cual, da déficit +51.21 mm (0.15) y +136.37 mm (0.30) y +15 y +26 días con Ks < 0.95: más grande que B porque su suelo guarda más agua (TAW 180 mm) y arranca seco.

**Veredicto de la comparación** (tolerancias fijadas antes de calcular; no se ajustó nada):

- **Signo y orden: congruentes en las tres corridas.** El banano sube la demanda, el déficit y los días de estrés respecto del café solo, y el orden es solo < banano 0.15 < banano 0.30, igual que solo < regulado < denso en la auditoría.
- **Magnitud, cobertura 0.15: no cercana** en la comparación equivalente (B +20.4 y C +18.2 mm, fuera de 40–240 mm; la corrida A, +51.2, cae dentro solo por su suelo distinto). El 0.15 es una convención nuestra y queda por debajo de lo que la auditoría llama regulado.
- **Magnitud, cobertura 0.30: cercana** en el intervalo ancho fijado (39.6 a 585.6 mm: B +91.0, C +84.9), y apenas por debajo del déficit regulado de la fila ERA5 (96.36 mm), que era el límite inferior del intervalo estricto.
- **Qué cobertura corresponde al «regulado» y al «denso» de la auditoría.** Se buscó la `bananaCover` de nuestra fórmula que reproduce el aumento de ETc (+120.73 mm y +294.36 mm) en el mismo clima: **regulado ≈ 0.27 a 0.28 y denso ≈ 0.54 a 0.55** (B 0.273 y 0.541; C 0.280 y 0.554; con el clima de la corrida A, 0.237 y 0.476). Con esas coberturas el déficit sale +79 y +195 mm (B) y +76 y +189 mm (C), cerca del 80 % del +96 y +239 de la auditoría, y los días de estrés +11 y +22 (B) y +15 y +26 (C) contra +15 y +27. Solo el gasto del banano, sin el recorte de evaporación de 0.52 mm/día, daría 0.15 y 0.41 (B). Es una equivalencia de demanda de agua, **no** de sombra: la «sombra regulada 35–45 %» del asesor es luz interceptada y no una fracción de suelo cubierta por copa, y no hay en ningún archivo la conversión a macollas por hectárea. La app solo ofrece 0.15 y 0.30 (los valores con que se entrenó la red), así que el «denso» no se puede mostrar.

**Revisión punto por punto con el criterio del asesor.** Detalle completo en `.superpowers/sdd/2026-11-14-field-shift-web/task-40-report.md`. Lo que no es congruente y se corrigió aquí:

1. **«Choca con la única medición» y «lo más probable es que el supuesto sobrestime»**: no es congruente con la auditoría (más déficit con banano en 3,240 de 3,240 pares) ni con la propia base del asesor, que cita el mismo estudio para la competencia por agua. Se quitó (esta sección, `proyecto/README-cafe-para-la-app.md`, `app/V01-red/RED.md`).
2. **La reducción de evaporación de 0.52 mm/día** es un proxy de sombra de árboles (Padovan 2018, Nicaragua) que se aplica con cualquier cobertura mayor que cero y sin mulch. El asesor la ata al mulch de pseudotallos y hojas de *Musa* y a reemplazar malezas vivas (17 a 45 %, §3.3). El modelo no sabe si hay mulch.
3. **Lo que el modelo no representa**: la luz que llega al café (eje 1), el microclima bajo el dosel (eje 2; la temperatura y el viento no cambian con el banano) y la redistribución de lluvia por el pseudotallo (impluvio y escurrimiento caulinar). Solo el eje 3 (agua en la zona radicular) está, y de forma parcial: una sola zona radicular para todo el lote y un Ks de café sobre toda la demanda (el banano se descuenta dos veces por estrés: `KsBanana` y el Ks del café). El beneficio que sí encuentra la auditoría, frente a café al sol con malezas, no se puede mostrar: nuestra base de comparación es café con suelo limpio (el Kc con malezas de `crops.json` no lo usa `coffee.js`).
4. Se mantiene la etiqueta **provisional**: el propio asesor dice que los parámetros necesitan confirmación de campo (`auditorias/.../fuentes/evidencia_bibliografica.json`, «faltantes»).

**Cómo reproducir.** `node scripts/coffee/verify_banana_audit.mjs` (menos de 2 s; escribe `web/data/banana_audit_check.json`).

### Qué haría falta para cambiar el supuesto por una medida

1. El **texto completo** de Sarmiento-Soler et al. 2019 (Agric. For. Meteorol. 266-267:231-242, doi:10.1016/j.agrformet.2018.12.006): transpiración del banano por planta, estacionalidad y densidad de banano de las parcelas. Hoy solo hay el resumen, y la conversión de litros por planta a milímetros no se puede hacer sin la densidad (con 250 plantas/ha, 3.1 L/planta/día serían 0.078 mm/día; con 1,000, 0.31, según la cuenta ilustrativa de las notas; la unidad del resumen no está confirmada). Si fuera así, estarían muy por debajo de lo que el supuesto da con cobertura 0.15 o 0.30 (con ET0 de 4 mm/día: 0.66 y 1.32 mm/día en suelo húmedo). Esa cuenta, con una unidad sin confirmar, no basta para concluir que el supuesto está alto: la auditoría del asesor (subsección anterior) encuentra un aumento de demanda parecido al nuestro con cobertura 0.27 a 0.28 para el banano regulado.
2. La **densidad de banano** en cafetales de Guatemala o Centroamérica (plantas por manzana y qué cobertura de copa da). No se encontró en Anacafé ni en CATIE; solo Cenicafé (Colombia) da 250 a 350 plantas por hectárea de plátano.
3. Cualquier **medición centroamericana** de humedad del suelo, flujo de savia o rendimiento bajo banano en café, y de cuánto reduce la evaporación del suelo (el recorte de 0.52 mm/día es de un cafetal con árboles en Nicaragua, no de banano).
4. Una medida de si el banano **se apaga** con el suelo seco en condiciones de cafetal (la p de 0.35 es de plantación completa).

**Cómo reproducir esta sección.**

```bash
node scripts/coffee/scenarios_v2.mjs                                   # tabla con banano (2 s; no toca coffee_table.json)
PYTHONPATH=scripts/emulator C:/Users/velas/venv_lab4/Scripts/python.exe scripts/coffee/ptc_mlp_v2.py   # entrena 17, 29, 43 y exporta coffee_ptc_mlp_v2.json
node scripts/coffee/evaluate_v2.mjs                                    # coffee_eval_v2.json
node scripts/parity/build_parity.mjs                                   # parity.json
```


---

## Banano corregido según el asesor del equipo (tarea 41)

La tarea 40 comparó nuestro banano provisional con el asesor agroclimático del equipo (`origin/main`, commit `ac37f1b`: `conocimiento/cafe-ciclo-y-asocio-banano.md` y `auditorias/prueba cafe banano 2025/`). El signo y el orden coincidían, pero se encontraron tres defectos. El dueño pidió corregir el banano. Esta sección dice qué estaba mal, cómo quedó, y qué números salen ahora. Todas las cifras vienen de `web/data/banana_audit_check_v3.json`, `web/data/coffee_eval_v3.json` y `web/data/coffee_ptc_mlp_v3.json` (generados por `scripts/coffee/verify_banana_audit.mjs`, `scripts/coffee/evaluate_v3.mjs` y `scripts/coffee/ptc_mlp_v3.py`).

### Qué estaba mal

1. **El estrés del banano se contaba dos veces.** La fórmula de la tarea 38 sumaba un gasto de banano con su propio coeficiente de estrés (p = 0.35) y después el Ks del café (p = 0.40) se aplicaba a toda la demanda del lote.
2. **El recorte de evaporación del suelo era un proxy de sombra de árboles.** Los 0.52 mm/día en lluvias (Padovan 2018, Nicaragua) se aplicaban con cualquier cobertura de banano mayor que cero y sin mulch. El asesor ata el beneficio del banano al mulch de *Musa* y a reemplazar las malezas vivas.
3. **Faltaba la línea base donde el banano sí ayuda.** La auditoría encuentra menos déficit con banano regulado y mulch solo frente a café al sol con malezas vivas. Nuestra comparación era siempre contra café con suelo limpio, y esa base no existía en el simulador.

### Cómo quedó: las clases de la auditoría

Se reemplazó la fórmula por cobertura por las cuatro clases de sistema de la auditoría. Cada una tiene un Kc compuesto y una p únicos para todo el lote (no hay un término de banano aparte, así que nada se cuenta dos veces; el efecto del mulch y el de las malezas están dentro del Kc auditado). Los valores se tomaron de `auditorias/prueba cafe banano 2025/datos/cultivos/parametros_auditados.json` y se verificaron uno por uno:

| Sistema | Kc inicial / medio / final | p | Origen |
|---|---|---|---|
| Café solo, suelo limpio o con mulch | 0.90 / 0.95 / 0.95 | 0.40 | FAO-56 Tabla 12 (suelo limpio) |
| Café solo con cobertura viva o malezas | 1.05 / 1.10 / 1.10 | 0.40 | FAO-56 Tabla 12 (con malezas) |
| Café + banano regulado (35–45 % de sombra) con mulch de *Musa* | 0.95 / 1.05 / 1.00 | 0.38 | compuesto de la auditoría |
| Café + banano denso sin deshije | 1.00 / 1.20 / 1.10 | 0.35 | FAO-56 Tabla 12 (banano de segundo año) y Tabla 22 |

**Calendario de los tres Kc.** El archivo de parámetros da etapas de 365 días: inicial 60 días, desarrollo 90 días, media 125 días y final 90 días. Se copió ese calendario sin cambios: el Kc inicial vale los primeros 60 días del año, sube linealmente al Kc medio durante los 90 días siguientes, se queda en el Kc medio 125 días y baja linealmente al Kc final en los últimos 90 días (los días del año cuentan desde el 1 de enero). Como el café es perenne, el mismo calendario se repite cada año civil por día del año. Con la ET0 diaria de la propia auditoría, este calendario reproduce las cuatro ETc anuales de la auditoría con diferencia de 0.00 mm (1,404.76; 1,525.49; 1,630.07; 1,699.12 mm; `calendar_check` en `banana_audit_check_v3.json`).

**Dos datos del agricultor reemplazan a `bananaCover`.** `suelo` (entre los surcos): `limpio` o `malezas`. `banano`: `ninguno`, `regulado` o `denso`. Con banano, el suelo es el de la auditoría (con mulch de *Musa*) y `suelo` se ignora. Sin banano y con suelo limpio no se usa ninguna clase: es el café de siempre (Kc 0.95 constante, p 0.40).

Lo que no cambia: la sombra de árboles (hoja perenne o caduca, Padovan 2018) queda exactamente igual y **no se combina** con banano ni con la opción de malezas (el simulador lanza un error). La profundidad de raíz es la nuestra, 1.2 m; la auditoría usa 1.0 m (no se cambió). Todo es aditivo: la opción es un parámetro nuevo `system` de `simulateCoffee`, `counterfactual` y `coffeeDecisionStateV3`; sin ella el resultado es idéntico al de antes (hay una prueba que lo comprueba con `deepEqual`).

**Una diferencia que hay que decir.** La red usa como "café limpio" el café de siempre (Kc 0.95 constante), no el calendario de la auditoría (0.90 al inicio del año). Es para que los escenarios originales salgan idénticos a los de la versión 1. En la corrida C esa línea base queda 22.20 mm por encima de la demanda del limpio con calendario y 22.15 mm por encima en déficit (1,426.96 contra 1,404.76 mm). Las tres clases nuevas sí usan el calendario. La comparación de congruencia de abajo usa el calendario en las cuatro.

### Congruencia con la auditoría, antes y después

Misma corrida C de la tarea 40: ET0 FAO-56 y lluvia ERA5 de la auditoría (2025, secano), TAW 130.7 mm sobre la zona radicular del simulador (Zr 1.2 m), reserva inicial 25 %, escorrentía 15 %. Tolerancias fijadas antes de calcular (las de la tarea 40, aplicadas a las clases; más la comparación con malezas):

- Signo y orden iguales a los de la auditoría: demanda y déficit con limpio < regulado < malezas < denso.
- Déficit regulado menos limpio entre 39.6 y 240.5 mm; denso menos limpio entre 39.6 y 585.6 mm.
- Déficit regulado menor que el de malezas; magnitud cercana entre 38.5 y 201.7 mm menos (el rango de la auditoría entre sus cuatro fuentes de lluvia, dividido entre 2 y multiplicado por 2).

| Cantidad, 2025, secano | Auditoría (fila ERA5) | Tarea 40, cobertura 0.15 / 0.30 (corrida C) | Ahora (v3, corrida C) |
|---|---:|---:|---:|
| Demanda, café solo limpio (mm) | 1404.76 | 1426.96 | 1404.76 |
| Demanda, regulado menos limpio (mm) | +120.73 | +26.03 / +134.28 | +120.73 |
| Demanda, denso menos limpio (mm) | +294.36 | no se podía mostrar | +294.36 |
| Déficit, café solo limpio (mm) | 648.26 | 681.8 | 659.65 |
| Déficit, regulado menos limpio (mm) | +96.36 | +18.15 / +84.90 | +93.12 |
| Déficit, denso menos limpio (mm) | +238.74 | no se podía mostrar | +231.09 |
| Déficit, regulado menos café con malezas (mm) | −87.16 (rango entre las 4 fuentes de lluvia: −100.83 a −77.01) | no se podía mostrar | −85.19 |
| Días con Ks < 0.95, café solo limpio | 249 | 257 | 257 |
| Días con Ks < 0.95, regulado menos limpio | +15 | +6 / +16 | +12 |
| Días con Ks < 0.95, denso menos limpio | +27 | no se podía mostrar | +20 |
| Días con Ks < 0.95, regulado menos café con malezas | −2 | no se podía mostrar | −1 |

**Cuatro sistemas contra las filas ERA5 de la auditoría (corrida C, 2025):**

| Sistema | Demanda: auditoría / nuestro | ETa: auditoría / nuestro | Déficit: auditoría / nuestro | Días con Ks < 0.95: auditoría / nuestro |
|---|---|---|---|---|
| limpio | 1404.76 / 1404.76 | 756.49 / 745.1 | 648.26 / 659.65 | 249 / 257 |
| regulado | 1525.49 / 1525.49 | 780.87 / 772.72 | 744.62 / 752.77 | 264 / 269 |
| malezas | 1630.07 / 1630.07 | 798.29 / 792.11 | 831.78 / 837.96 | 266 / 270 |
| denso | 1699.12 / 1699.12 | 812.13 / 808.39 | 887 / 890.74 | 276 / 277 |

**Veredicto, sin ajustar nada para acercarse:**

- **Signo y orden: congruentes.** Demanda y déficit salen limpio < regulado < malezas < denso, como en la auditoría. La demanda coincide con la de la auditoría al centésimo (el calendario es el suyo), así que la diferencia está toda en la parte del suelo.
- **Magnitud: cercana, y más cerca que antes.** Regulado menos limpio: +93.12 mm de déficit (auditoría +96.36 mm; en la tarea 40, con cobertura 0.15 y 0.30, +18.15 y +84.90). Denso menos limpio: +231.09 mm (auditoría +238.74 mm; antes no se podía mostrar). Los dos caen dentro de los intervalos fijados y a unos 3 % de la fila ERA5.
- **El banano regulado con mulch tiene menos déficit que el café al sol con malezas: se reproduce.** Nuestro −85.19 mm contra −87.16 mm de la fila ERA5 y −100.83 a −77.01 mm entre las cuatro fuentes de lluvia de la auditoría. Cae dentro de ese rango. Esto no se podía mostrar antes.
- **Lo desfavorable.** Nuestro déficit está entre 3.74 y 11.39 mm por encima del de la auditoría en los cuatro sistemas (ETa menor), y los días con Ks < 0.95 salen 1 a 8 por encima; en regulado menos limpio salen +12 días contra +15, y en denso menos limpio +20 contra +27 (la corrida C no iguala la profundidad de raíz, 1.2 m contra 1.0 m, ni el suelo de cinco capas). Contra el café con malezas, los días con Ks < 0.95 del regulado salen 1 menos (auditoría: 2 menos): la ventaja de regulado sobre malezas está en la demanda y el déficit, apenas en los días de estrés.

### Resultados por sistema (la red v3 y la regla FAO-56)

La red v3 tiene 19 entradas: las 16 de siempre más `weeds`, `bananaRegulated` y `bananaDense` (0 o 1; `shadeTrees` y `deciduous` valen 0 con una clase de sistema). Misma arquitectura y receta que las redes anteriores (predecir y luego elegir; 19 → 64 → 32 → 16 → 1; semillas 17, 29, 43; la semilla exportada es la de menor pérdida de validación 2017–2018: la semilla 29). Mismos sitios, suelos, años, días de decisión y cortes: 10 sitios de 900 m o más × 3 suelos × 24 años cafeteros × 3 días de decisión × 6 sistemas = 12,960 escenarios (prueba 2019–2024: 3,240; reservado 2022–2024: 1,620). Utilidad media de la red (media de las tres semillas) y de la regla FAO-56; más alto es mejor. La regla es la misma para todos los sistemas: el balance corrido del café (Kc 0.95, p 0.40), que es lo que el agricultor puede observar; no conoce el Kc ni la p del sistema. Por eso riega en los mismos 211 de 540 casos en todos los sistemas.

**Años nuevos 2019–2024** (540 casos por sistema)

| Sistema | Ahorrar agua: red / regla / riegos de 540 | Proteger el cultivo: red / regla / riegos de 540 |
|---|---|---|
| Ninguna (café de siempre) | 0.388 / 0.096 / 176 | 1.138 / 0.878 / 259 |
| Árboles de hoja perenne | 0.227 / −0.087 / 157 | 0.885 / 0.694 / 230 |
| Árboles de hoja caduca | 0.822 / 0.100 / 208 | 1.730 / 0.881 / 302 |
| Café con malezas | 0.788 / 0.120 / 201 | 1.652 / 0.902 / 284 |
| Banano regulado con mulch | 0.780 / 0.172 / 199 | 1.650 / 0.954 / 285 |
| Banano denso sin deshije | 0.894 / −0.217 / 217 | 1.844 / 0.565 / 334 |

**Años reservados 2022–2024** (270 casos por sistema)

| Sistema | Ahorrar agua: red / regla / riegos de 270 | Proteger el cultivo: red / regla / riegos de 270 |
|---|---|---|
| Ninguna (café de siempre) | 0.465 / −0.085 / 98 | 1.354 / 0.893 / 148 |
| Árboles de hoja perenne | 0.204 / −0.300 / 90 | 1.000 / 0.678 / 130 |
| Árboles de hoja caduca | 0.925 / −0.144 / 112 | 1.810 / 0.833 / 163 |
| Café con malezas | 0.925 / −0.111 / 111 | 1.843 / 0.867 / 158 |
| Banano regulado con mulch | 1.059 / 0.019 / 112 | 1.938 / 0.996 / 160 |
| Banano denso sin deshije | 0.652 / −0.511 / 112 | 1.598 / 0.467 / 182 |

Lo que se ve: la red le gana a la regla en todos los sistemas y en ambas prioridades. La regla FAO-56 queda peor justamente en el banano denso (utilidad −0.217 al ahorrar agua en la prueba y −0.511 en los años reservados): ahí el estrés llega antes que lo que su umbral de 0.40 anticipa. **Esa utilidad es la del simulador con parámetros de referencia de FAO-56:** la red aprendió lo que el simulador dice de cada clase, no una medida de campo.

**Estrés del simulador sin riego** (días con Ks < 1 del lote, con la p del sistema; media sobre sitios, suelos y años cafeteros). Cuajado = 90 días tras la floración; llenado = días 91 a 120; seca = noviembre a abril (181 días).

2001–2024 (720 combinaciones por sistema)

| Sistema | Días de estrés: cuajado | llenado de grano | estación seca | ETa/ETc: cuajado | llenado | seca |
|---|---|---|---|---|---|---|
| Ninguna (café de siempre) | 41.3 | 6.6 | 153.9 | 0.741 | 0.934 | 0.334 |
| Árboles de hoja perenne | 39.3 | 5.3 | 155.0 | 0.742 | 0.951 | 0.323 |
| Árboles de hoja caduca | 46.0 | 9.6 | 157.3 | 0.725 | 0.893 | 0.319 |
| Café con malezas | 45.6 | 9.2 | 160.0 | 0.715 | 0.897 | 0.295 |
| Banano regulado con mulch | 44.8 | 8.6 | 158.4 | 0.726 | 0.908 | 0.321 |
| Banano denso sin deshije | 50.2 | 11.9 | 164.3 | 0.697 | 0.866 | 0.293 |

2019–2024 (solo años de prueba; 180 por sistema)

| Sistema | Días de estrés: cuajado | llenado de grano | estación seca | ETa/ETc: cuajado | llenado | seca |
|---|---|---|---|---|---|---|
| Ninguna (café de siempre) | 39.5 | 3.8 | 145.1 | 0.751 | 0.973 | 0.366 |
| Árboles de hoja perenne | 37.7 | 2.5 | 146.8 | 0.752 | 0.984 | 0.353 |
| Árboles de hoja caduca | 44.3 | 7.8 | 148.0 | 0.734 | 0.938 | 0.354 |
| Café con malezas | 43.9 | 7.3 | 151.5 | 0.726 | 0.943 | 0.327 |
| Banano regulado con mulch | 43.0 | 6.5 | 149.7 | 0.735 | 0.952 | 0.354 |
| Banano denso sin deshije | 48.6 | 10.7 | 156.2 | 0.707 | 0.911 | 0.327 |

Días de estrés evitables por un riego de 20 mm (media de los 540 casos de prueba por sistema, 30 días siguientes sin riego): ninguna (café de siempre) 1.75, árboles de hoja perenne 1.44, árboles de hoja caduca 2.47, café con malezas 2.41, banano regulado con mulch 2.37, banano denso sin deshije 2.62.

Días de estrés en los 30 días siguientes sin riego (misma muestra): ninguna (café de siempre) 5.67, árboles de hoja perenne 4.76, árboles de hoja caduca 8.44, café con malezas 8.14, banano regulado con mulch 7.61, banano denso sin deshije 10.65.

Lectura: con la corrección, el banano regulado con mulch queda **entre** el café limpio y el café con malezas, como dice la auditoría (cuajado 44.8 días de estrés contra 41.3 del limpio y 45.6 con malezas; seca 158.4 contra 153.9 y 160.0; ETa/ETc de la estación seca 0.321 contra 0.334 y 0.295). El banano denso es el peor en todas las medidas. En la estación seca todos los sistemas tienen entre 145 y 164 de 181 días con estrés: el simulador del café no tiene riego ni agua de fondo, así que las diferencias entre sistemas son pequeñas en esa estación.

**Red v1 contra red v3 en los escenarios originales** (las mismas 1,620 filas de prueba sin banano ni malezas; v1 es `coffee_eval.json`; media de las tres semillas)

| Sombra | Ahorrar agua: v1 / v3 | Proteger el cultivo: v1 / v3 |
|---|---|---|
| Las tres juntas (prueba) | 0.474 / 0.479 | 1.174 / 1.251 |
| Las tres juntas (reservado) | 0.500 / 0.531 | 1.311 / 1.388 |
| Ninguna (café de siempre) (prueba) | 0.419 / 0.388 | 1.066 / 1.138 |
| Ninguna (café de siempre) (reservado) | 0.472 / 0.465 | 1.272 / 1.354 |
| Árboles de hoja perenne (prueba) | 0.193 / 0.227 | 0.794 / 0.885 |
| Árboles de hoja perenne (reservado) | 0.165 / 0.204 | 0.902 / 1.000 |
| Árboles de hoja caduca (prueba) | 0.810 / 0.822 | 1.661 / 1.730 |
| Árboles de hoja caduca (reservado) | 0.863 / 0.925 | 1.758 / 1.810 |

Los escenarios originales son los mismos de siempre (6,480 filas con entradas y resultados idénticos a `coffee_table.json`; la prueba lo comprueba). Pero la red v3 es una red nueva entrenada con seis sistemas y no la v1: en esas filas gana un poco al proteger el cultivo y al ahorrar agua con los dos tipos de árboles, y pierde un poco en el café sin sombra al ahorrar agua (0.388 contra 0.419 en la prueba; entre las tres semillas de la v3 ese valor va de 0.337 a 0.446). La diferencia es de la red, no de los escenarios.

### Lo que el modelo sigue sin representar

- **La luz** que llega al café bajo el dosel del banano (eje 1 del asesor) y el **microclima** (eje 2; la temperatura y el viento no cambian con el banano en el simulador). El asesor habla de que el banano amortigua la temperatura máxima 1.5 a 3 °C; eso no entra.
- La **redistribución de lluvia por el pseudotallo** (impluvio y escurrimiento caulinar).
- El **flujo de caja** del banano (venta de racimos), que es parte de la razón por la que se asocia.
- La **profundidad de raíz**: 1.2 m en el simulador contra 1.0 m en la auditoría. Se igualó el agua disponible (TAW 130.7 mm) en la comparación, no la profundidad.
- Los **parámetros** (Kc compuesto y p de las clases) son valores de referencia de FAO-56 que el propio asesor dice que necesitan confirmación de campo (`auditorias/.../fuentes/evidencia_bibliografica.json`, «faltantes»). La etiqueta **provisional** se mantiene en el sentido de que no hay una medición en cafetales de Guatemala.
- La clase «regulado» es una clase de manejo con mulch, **no una fracción de cobertura**: la «sombra 35–45 %» es luz interceptada y no se convierte a macollas por hectárea (no hay esa conversión en ningún archivo).

### La versión anterior queda archivada

La fórmula por cobertura (la tarea 38 y su verificación de la tarea 40) no se borró ni se cambió: `bananaCover`, `web/data/coffee_eval_v2.json`, `web/data/coffee_ptc_mlp_v2.json` y `web/data/banana_audit_check.json` siguen byte por byte como estaban, como versión provisional archivada. Lo nuevo es todo `_v3`. La app debe usar la v3.

**Cómo reproducir esta sección.**

```bash
node scripts/coffee/verify_banana_audit.mjs                            # congruencia: escribe banana_audit_check.json (igual que antes) y banana_audit_check_v3.json
node scripts/coffee/scenarios_v3.mjs                                   # tabla con los seis sistemas (3 s; no toca coffee_table.json ni coffee_table_v2.json)
PYTHONPATH=scripts/emulator C:/Users/velas/venv_lab4/Scripts/python.exe scripts/coffee/ptc_mlp_v3.py   # entrena 17, 29, 43 y exporta coffee_ptc_mlp_v3.json
node scripts/coffee/evaluate_v3.mjs                                    # coffee_eval_v3.json
```
