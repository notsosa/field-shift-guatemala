# Anexo al plan · Prioridad al emulador (Tareas 13 y 14)

Fecha: 14 de noviembre de 2026. Plan base: [2026-11-14-field-shift-web.md](2026-11-14-field-shift-web.md); diseño: [§6b](../specs/2026-11-14-field-shift-web-design.md).

**Cambio de prioridad pedido por el equipo:**
- Se pausan las tareas de interfaz (9–12) y la Tarea 6.
- Después de la Tarea 5 se construye solo el emulador:
  - ELM sin backpropagation vs. red embudo 25→64→32→16→3;
  - mapa del Corredor Seco y mejor fecha de siembra.
- Sin publicar ni subir nada sin permiso.
- El margen se agrega después; por ahora los objetivos son agua, estrés y suelo desnudo.

**Decisiones del controlador**
- La Tarea 13 se divide en 13a–13d.
- 13a adelanta el núcleo de descarga de clima de la Tarea 7. El respaldo, los snapshots completos, SoilGrids y `rain_compare` siguen en la Tarea 7.
- El plan pedía 25 features pero listaba 21. Se agregan:
  - lluvia de mayo;
  - días con lluvia de mayo a octubre;
  - racha seca máxima de mayo a octubre;
  - radiación media de mayo a octubre.
- La Tarea 14 es una página independiente (`web/emulator.html`) mientras la interfaz principal está en pausa.

Restricciones globales: las del plan base. Ninguna API key; sin backend; textos visibles EN por defecto con botón ES.

---

### Task 13a: Núcleo de clima para el emulador

**Files:** Create `web/js/data/climate.js`, `tests/climate.test.mjs`

**Interfaces:**
- `isInsideGuatemala(lat, lon) -> boolean`: lat 13.6–17.9, lon −92.3 – −88.1.
- `fetchPowerDaily(lat, lon, fetchFn = fetch) -> Promise<{dates, tmax, tmin, tdew, rs, u2, pressure, elevation}>`:
  - API diaria de NASA POWER, comunidad AG, 20010101–20251231;
  - parámetros `T2M_MAX, T2M_MIN, T2MDEW, ALLSKY_SFC_SW_DWN, WS2M, PS`;
  - fechas en formato 'YYYY-MM-DD';
  - `-999` se convierte en `null`;
  - `elevation` = `geometry.coordinates[2]` de la respuesta.
- `fetchEra5Rain(lat, lon, fetchFn = fetch) -> Promise<{dates, rain}>`: archivo de Open-Meteo `https://archive-api.open-meteo.com/v1/archive` con `models=era5`, `daily=precipitation_sum`, `timezone=America/Guatemala`, del 2001-01-01 al 2025-12-31.
- `buildBundle(power, era5, {lat, lon}) -> ClimateBundle`:
  - alinea por fecha (intersección);
  - devuelve `rainSource: 'ERA5'` y `fallback: false`;
  - `sources`: cita de NASA POWER y de Copernicus ERA5 (Open-Meteo) con sus URLs;
  - interpola en forma lineal los `null` en tramos de ≤ 3 días;
  - con tramos más largos, `invalidYears` lista los años agrícolas (abril–marzo) que los contienen.

**Tests (TDD):**
- Pacífico (12.5, −91.0) da `false` y Chiquimula da `true`.
- `-999` se convierte en `null` (con `fetchFn` simulado).
- Un hueco de 2 días queda interpolado.
- Un hueco de 5 días en junio de 2010 marca 2010 en `invalidYears`.
- `rainSource === 'ERA5'`.
- Las fechas desalineadas se recortan a la intersección.
- Ninguna prueba usa la red.

**Commit:** `feat(data): descarga de clima POWER + ERA5 y armado del bundle`

### Task 13b: Núcleo del emulador en JS (ELM, red embudo, features, métricas)

**Files:** Create `web/js/model/emulator.js`, `tests/emulator.test.mjs`

**Interfaces:**
- **Features de clima.** `CLIMATE_FEATURE_NAMES` (11) y `climateFeatures(bundle, year, et0) -> number[11]`, calculadas sobre el año agrícola `year`:
  - `rainMJJ`, `rainASO`, `rainYear`, `rainMay`;
  - `rainyDaysMO` (lluvia ≥ 1 mm, mayo–octubre);
  - `maxDrySpellMO` (racha más larga con < 1 mm, mayo–octubre);
  - `caniculaDays` (racha más larga con < 1 mm, 1 de julio–31 de agosto);
  - `et0MeanMO`, `tmeanMO`, `rsMeanMO` (mayo–octubre);
  - `elevation`.
- **Codificación completa.** `FEATURE_NAMES` (25) y `encodeFeatures(climFeats, {texture, slopeClass, irrigation, sequenceId, sowOffsetDays}) -> number[25]`:
  - las 11 de clima;
  - one-hot de textura `[sand, loam, clay]`;
  - one-hot de pendiente `[flat, moderate, steep]`;
  - one-hot de riego `[none, limited, full]`;
  - one-hot de secuencia `[actual, proteger, extra_secano, extra_riego]`;
  - `sowOffsetDays / 30`.
- **Objetivos.** `TARGET_NAMES = ['waterIndex', 'ksFlowerMain', 'bareFrac']` y `targetsOf(yearResult) -> number[3] | null`:
  - `waterIndex` = media de `relYield` de los cultivos con `relYield ≠ null`; si no hay ninguno, devuelve `null`;
  - `ksFlowerMain` = `crops[0].ksFlowerMean`;
  - `bareFrac` = `bareDaysRainy / 214`.
- **ELM.**
  - `mulberry32(seed) -> () => number` en [0, 1).
  - `trainELM(X, Y, {hidden = 300, lambda = 1e-2, seed = 42}) -> ElmModel`:
    - estandariza X con su media y desviación;
    - W y b ~ U(−1, 1) con `mulberry32(seed)`;
    - `H = tanh(W·x + b)`;
    - `β = (HᵀH + λI)⁻¹HᵀY` por Cholesky;
    - **sin backpropagation**.
  - `elmPredict(model, x) -> number[]`.
- **Red embudo.** `mlpPredict(net, x) -> number[]` con formato `net = {layers: [{W: number[][] (salida×entrada), b: number[]}], mean, std, yMean, yStd}`:
  - entrada estandarizada;
  - ReLU en las capas ocultas y salida lineal;
  - desestandarización con `yMean`/`yStd` si existen.
- **Métricas.** `r2(yTrue, yPred)` y `rmse(yTrue, yPred)` sobre arreglos 1-D.

**Tests (TDD):**
- La ELM aprende `y = 2x1 − x2` con R² > 0.99 (hidden 50, λ 1e-6).
- La misma semilla da la misma predicción.
- `mlpPredict` reproduce una red 2→2→1 escrita a mano (error < 1e-9).
- `climateFeatures` en un bundle sintético:
  - lluvia 0 del 1 de julio al 15 de agosto y 5 mm el resto de mayo–octubre → `caniculaDays = 46`;
  - `rainMay = 155`.
- `encodeFeatures` devuelve 25 valores, con el one-hot en las posiciones correctas.
- `targetsOf` devuelve `null` cuando todos los `relYield` son `null`.

**Commit:** `feat(si): núcleo del emulador — ELM sin backprop, forward de la red embudo, features y métricas`

### Task 13c: Puntos del Corredor Seco, desfase de siembra y generación de ejemplos

**Files:**
- Modify: `web/js/model/simulate.js` (parámetro `sowOffsetDays`), `tests/simulate.test.mjs`, `.gitignore` (`scripts/emulator/cache/`, `scripts/emulator/samples.json`)
- Create: `scripts/emulator/points.json`, `scripts/emulator/fetch_points.mjs`, `scripts/emulator/generate.mjs`, `web/data/grid_features.json`, `web/data/snapshots/{chiquimula,jutiapa,sanmartin}.json`

**Interfaces:**
- **Desfase de siembra.** `runSequence({..., sowOffsetDays = 0})` suma el desfase al `sowIdx` resuelto de la fase 0, acotado al año agrícola. Los relevos lo siguen solos.
- **Puntos.** `points.json` = `[{id, name, lat, lon, heldOut}]` con 20 cabeceras municipales del Corredor Seco, todas dentro de Guatemala:
  - incluye los 3 pilotos: `chiquimula` (14.80, −89.54), `jutiapa` (14.29, −89.90) y `sanmartin` (14.78, −90.79);
  - el resto sale de Chiquimula, Zacapa, El Progreso, Jutiapa, Jalapa, Baja Verapaz y Santa Rosa;
  - **4 puntos con `heldOut: true`** (ninguno es piloto).
- **`fetch_points.mjs`.**
  - Por punto: `fetchPowerDaily` + `fetchEra5Rain` + `buildBundle`, con caché en `scripts/emulator/cache/{id}.json`.
  - Pausa de 1 s entre puntos para no saturar las APIs.
  - Copia los 3 pilotos a `web/data/snapshots/{id}.json`, que es el formato de snapshot de la Tarea 7.
- **`generate.mjs`.**
  - Combinaciones por punto y año válido:
    - secuencias `actual`, `proteger` y `extra_secano` con los 3 modos de riego, y `extra_riego` solo con `limited`/`full`;
    - desfases de −20 a +30 cada 5 días;
    - 3 texturas y 3 pendientes.
  - Calcula `computeEt0Series` una vez por punto.
  - Submuestreo aleatorio con `mulberry32(42)` a **50,000 ejemplos**.
  - Escribe `scripts/emulator/samples.json` = `{featureNames, targetNames, X, Y, meta: [{pointId, year, sequenceId, texture, slopeClass, irrigation, sowOffsetDays}]}`.
  - Escribe `web/data/grid_features.json` = `{points: [...], years: [...], climate: {[pointId]: {[year]: number[11]}}}`.

**Tests (TDD):**
- `sowOffsetDays = 10` mueve la fecha de siembra del maíz exactamente 10 días en el bundle sintético.
- Un desfase que sale del año agrícola queda acotado.

**Verificación:** Run `node scripts/emulator/fetch_points.mjs` y luego `node scripts/emulator/generate.mjs`. Expected:
- 20 caches;
- 3 snapshots;
- `samples.json` con 50,000 filas de 25 features y 3 objetivos, sin NaN;
- en la consola, la cuenta de ejemplos de entrenamiento y de prueba según la división de 13d.

**Commit:** `feat(si): puntos del Corredor Seco, desfase de siembra y generación de ejemplos del emulador`

### Task 13d: Entrenar la red embudo, evaluar ambos modelos

**Files:** Create `scripts/emulator/train_mlp.py`, `scripts/emulator/evaluate.mjs`, `scripts/requirements.txt` (numpy, torch), `web/data/emulator_mlp.json`, `web/data/emulator_eval.json`, `web/data/emulator_train_subset.json`, `tests/emulator_eval.test.mjs`

**Interfaces:**
- **División (idéntica en Python y en Node):**
  - prueba = ejemplos con `year ∈ 2019–2024` **o** con un `pointId` marcado `heldOut`;
  - entrenamiento = el resto.
- **`train_mlp.py`** (PyTorch en CPU):
  - red 25→64→32→16→3, ReLU, `torch.manual_seed(42)`;
  - X y Y estandarizados con estadísticas de entrenamiento;
  - Adam con lr 1e-3, lote 256, hasta 200 épocas, parada temprana con paciencia 10 sobre un 10 % de validación tomado del entrenamiento;
  - exporta `emulator_mlp.json` (formato de `mlpPredict`) con `trainSeconds`, `params` (= 4,323) y `trainMemoryMB`, indicando cómo se midió la memoria.
- **`evaluate.mjs`:**
  - métricas de la red embudo **con el forward en JS** (`mlpPredict`), lo que valida la exportación;
  - entrena la ELM en Node sobre el conjunto de entrenamiento (hidden 300, λ 1e-2, semilla 42);
  - mide tiempo con `performance.now()` y memoria (bytes de H y HᵀH, y `heapUsed`);
  - mide µs por predicción de cada modelo y µs por año simulado con `runSequence` (para el factor de aceleración);
  - escribe `emulator_eval.json` = `{targets, mlp: {rmse[], r2[], trainSeconds, params, trainMemoryMB, predictMicros}, elm: {...}, simulatorMicrosPerYear, nTrain, nTest, split}`;
  - escribe `emulator_train_subset.json` con 5,000 ejemplos de entrenamiento (`mulberry32(7)`) para entrenar la ELM en el navegador.

**Tests:**
- Para ambos modelos, `r2[0]` (waterIndex) > 0.8 y `r2[1]` (ksFlowerMain) > 0.8.
- `mlp.params === 4323`.
- Si un R² queda ≤ 0.8: se informa el valor real, se intenta mejorar las features, y **no** se baja el umbral sin avisar.

**Commit:** `feat(si): entrenamiento de la red embudo y evaluación contra la ELM sin backprop`

### Task 14: Página del emulador · mapa del Corredor Seco y mejor fecha de siembra

**Files:** Create `web/emulator.html`, `web/css/emulator.css`, `web/js/ui/emulatorStrings.js` (EN/ES), `web/js/ui/emulatorMap.js`, `web/js/ui/bestSowing.js`, `web/js/emulatorPage.js`

**Interfaces:**
- **Arranque.**
  - Carga `emulator_mlp.json`, `emulator_train_subset.json`, `grid_features.json`, `emulator_eval.json`, `crops.json` y `sequences.json`.
  - Entrena la ELM en el navegador y muestra su tiempo de entrenamiento.
- **Mapa** (Leaflet 1.9.4 de cdnjs, base OSM, atribuciones):
  - un círculo por punto de `grid_features.json`;
  - color = mediana 2001–2024 de la diferencia del objetivo elegido (waterIndex, ksFlowerMain o bareFrac) entre la alternativa elegida y `actual`, según el emulador;
  - selectores de alternativa, modelo (MLP/ELM), riego, textura y pendiente;
  - leyenda con el R² y el RMSE de `emulator_eval.json`.
- **Mejor fecha de siembra.**
  - Para un piloto (snapshot) y una secuencia, prueba desfases de −20 a +30 cada 2 días con el emulador.
  - Elige el que maximiza la mediana de `waterIndex`.
  - **Lo confirma con `runSequence`** sobre el snapshot y muestra lado a lado: el valor del emulador y el del simulador para la fecha propuesta y para el desfase 0, y el tiempo de cada uno.
- **Texto fijo** EN/ES: "AI learns our physical model; it does not predict real harvests" / "La IA aprende nuestro modelo físico; no predice cosechas reales".

**Verificación** (Ruling 1 del ledger):
- Instalar Playwright para Python (`py -m pip install playwright` y `py -m playwright install chromium`).
- Servir `web/` con `py -m http.server`.
- Tomar capturas de escritorio y celular en el workspace (`ui-shots/`) sin errores de consola.
- Verificar que el mapa se dibuja, la ELM entrena en < 5 s, y la fecha propuesta y la confirmada aparecen juntas.

**Commit:** `feat(ui): página del emulador — mapa del Corredor Seco y mejor fecha de siembra`
