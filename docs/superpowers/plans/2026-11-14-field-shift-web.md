# Field Shift GT · Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** App web estática que compara la rotación actual de un finquero de Guatemala con 2–3 alternativas, simulando 24 años agrícolas de agua en raíces (FAO-56) con datos de NASA, Copernicus y MAGA. Para cada opción muestra "proteger", "ganar extra" y las listas "aprovechar / mitigar", e incluye un emulador de IA (red embudo vs. ELM sin backpropagation).

**Architecture:**
- **Modelo:** JavaScript puro en módulos ES (`web/js/model/`), sin dependencias. El mismo código corre en el navegador y en Node para las pruebas y para generar los datos del emulador.
- **Datos:** NASA POWER y ERA5 en vivo (CORS abierto), con un respaldo guardado (*snapshot*) por sitio piloto generado con Python (`scripts/`).
- **Interfaz:** una sola página (`web/index.html`) con Leaflet y Chart.js por CDN, publicada en GitHub Pages con un workflow de Actions.

**Tech Stack:**
- JavaScript ES2022 (módulos);
- Node ≥ 20 (solo pruebas, con `node --test`);
- Leaflet 1.9.4 y Chart.js 4.4.1 (cdnjs);
- Python 3.13 (stdlib + numpy + tifffile + torch) para precálculos y para entrenar la red embudo;
- GitHub Actions + Pages.

**Spec:** [docs/superpowers/specs/2026-11-14-field-shift-web-design.md](../specs/2026-11-14-field-shift-web-design.md) y [Brief2.md](../../../Brief2.md).

## Global Constraints

**Interfaz e idioma**
- La interfaz arranca en **inglés** y tiene un botón visible a **español**. Todo texto visible sale de `web/i18n/en.json` / `es.json`; si falta una clave en español se usa la inglesa.
- Sin backend, sin cuentas, sin base de datos: todo lo publicado vive en `web/`.
- Librerías con versión fija desde `https://cdnjs.cloudflare.com/ajax/libs/` (Leaflet 1.9.4, Chart.js 4.4.1). Nada de npm en el sitio.

**Unidades y fuentes**
- Unidades internas: mm, °C, MJ/m²/día, m/s, kPa.
- Dinero en **Q por manzana** (1 mz = 0.6987 ha), con opción a hectárea en la interfaz.
- Cada parámetro de cultivo, costo y precio lleva `source` (documento + página/cuadro). Un valor sin fuente no se usa: se muestra "sin dato" / "no data".
- Lluvia del balance: **IMERG en pilotos si existe; si no, ERA5**. **POWER nunca** se usa como lluvia del balance salvo de respaldo, y entonces con aviso visible.

**Simulación y respaldo**
- Año agrícola: del 1 de abril del año Y al 31 de marzo de Y+1. Se usan solo años completos (2001–2024 = 24 años); los textos dicen "en X de N años" con N real.
- Si una API no responde en **8 s**, se usa el snapshot del piloto más cercano y se muestra un aviso.

**Textos obligatorios**
- Leyenda fija: "Supports, does not replace, the farmer's judgment / Apoya, no reemplaza, el criterio del finquero".
- Los márgenes se rotulan como **estimados**, nunca como predicciones.
- Sin logos de NASA.
- Atribución visible de NASA GIBS, Copernicus/ESA (Sentinel-2 cloudless de EOX) y OpenStreetMap.

**Supuestos fijos del modelo** (documentados en Métodos)

| Supuesto | Valor |
|---|---|
| Temperatura de referencia para grados-día | `TREF = 26` °C |
| Umbral de estrés en floración | `KS_STRESS = 0.7` |
| Regla de inicio de lluvias | ≥ 20 mm en 3 días después del 1 de mayo |
| Siembra de respaldo si no llega el inicio | 15 de junio |
| Costo del agua de riego | `IRRIGATION_COST_Q_PER_M3 = 1.0` (editable) |
| Escala de "ganar extra" | `REF_EXTRA_Q = 5000` |
| Escala de "agua" | `REF_WATER_MM = 300` |

## Review Focus

1. **Un punto en el mar o fuera de Guatemala:** la app debe rechazarlo con un mensaje claro (caja de Guatemala: lat 13.6–17.9, lon −92.3 – −88.1) y no llamar a las APIs. Prueba en la Tarea 7.
2. **APIs lentas o caídas en pleno jurado:** en ≤ 8 s se usa el snapshot y aparece el aviso. Prueba con un `fetch` simulado que nunca responde (Tarea 7).
3. **Cultivo sin datos económicos** (sorgo o ajonjolí sin costo MAGA): margen `null`, se muestra "no data" (nunca NaN ni 0) y el componente "ganar extra" se excluye del puntaje. Prueba en la Tarea 6.
4. **Punto de altura (2,400 m):**
   - El ciclo por grados-día no cabe en el año agrícola: se marca `cycleIncomplete`, se avisa y no hay ciclos infinitos.
   - Arriba de 1,500 m aparece el aviso de altitud.
   - Pruebas en las Tareas 3 y 5.
5. **Año muy seco sin inicio de lluvias:** se siembra el 15 de junio con `onsetFallback: true`, y la lista "mitigar" lo menciona. Prueba en la Tarea 3.

---

### Task 1: Herramientas y ET₀ FAO-56

**Files:**
- Create: `package.json`, `web/js/model/et0.js`, `tests/et0.test.mjs`

**Interfaces:**
- Produces:
  - `et0PenmanMonteith({tmax, tmin, ea, tdew, rhMean, rs, u2, elevation, pressure, latDeg, doy}) -> number` (mm/día). Usa `ea` si viene; si no, la presión de vapor a `tdew`; si no, `rhMean`. Usa `pressure` (kPa) si viene; si no, ec. 7 con `elevation`.
  - `extraterrestrialRadiation(latDeg, doy) -> number` (MJ/m²/día).
  - `netLongwave({tmax, tmin, ea, rs, rso}) -> number`.
  - `satVaporPressure(tC) -> number` (kPa).

- [ ] **Step 1: Instalar Node LTS**

Run: `winget install -e --id OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements`. Después: `node --version`.
Expected: `v20` o superior.

- [ ] **Step 2: Crear `package.json`**

Contenido: `{"name":"field-shift-gt","private":true,"type":"module","scripts":{"test":"node --test tests/"}}`.

- [ ] **Step 3: Escribir la prueba que falla** (FAO-56, ejemplo 18: Bruselas, 6 de julio)

```js
import test from 'node:test'; import assert from 'node:assert/strict';
import { et0PenmanMonteith, extraterrestrialRadiation, netLongwave } from '../web/js/model/et0.js';
const ex18 = { tmax: 21.5, tmin: 12.3, ea: 1.409, rs: 22.07, u2: 2.078, elevation: 100, latDeg: 50.8, doy: 187 };
test('Ra FAO-56 ej.18', () => assert.ok(Math.abs(extraterrestrialRadiation(50.8, 187) - 41.09) < 0.1));
test('Rnl FAO-56 ej.18', () => assert.ok(Math.abs(netLongwave({ tmax: 21.5, tmin: 12.3, ea: 1.409, rs: 22.07, rso: 30.90 }) - 3.71) < 0.05));
test('ET0 FAO-56 ej.18 = 3.9 mm/d', () => assert.ok(Math.abs(et0PenmanMonteith(ex18) - 3.9) < 0.1));
test('ET0 nunca negativa', () => assert.ok(et0PenmanMonteith({ ...ex18, rs: 0, tmax: 5, tmin: 4 }) >= 0));
```

- [ ] **Step 4:** Run `npm test` → Expected: FAIL (módulo no existe).
- [ ] **Step 5: Implementar `web/js/model/et0.js`**
  - FAO-56: ecs. 6 (ET₀), 7 (presión), 8 (γ), 11–13 (presiones de vapor), 21 (Ra), 37 (Rso = (0.75 + 2e-5·z)·Ra), 38 (Rns, albedo 0.23), 39 (Rnl) y 40 (Rn). G = 0 para el paso diario.
  - El resultado se acota a ≥ 0.
- [ ] **Step 6:** Run `npm test` → Expected: PASS (4 pruebas).
- [ ] **Step 7: Commit:** `git add package.json web/js/model/et0.js tests/et0.test.mjs && git commit -m "feat(model): ET0 FAO-56 Penman-Monteith con prueba del ejemplo 18"`

### Task 2: Suelo, escorrentía y agua disponible

**Files:**
- Create: `web/js/model/soil.js`, `tests/soil.test.mjs`

**Interfaces:**
- Produces:
  - `SOILS`: objeto con las texturas `sand | loam | clay`. Valores (FAO-56 cuadro 19, punto medio):

    | Textura | `thetaFC` | `thetaWP` | Grupo hidrológico | CN cultivo / residuo / suelo desnudo |
    |---|---|---|---|---|
    | sand | 0.12 | 0.045 | A | 67 / 64 / 77 |
    | loam | 0.25 | 0.12 | B | 78 / 75 / 86 |
    | clay | 0.36 | 0.22 | D | 89 / 87 / 94 |

    Fuente del CN: USDA-NRCS TR-55, cuadro 2-2b.
  - `SLOPE_CLASSES = {flat: {pct: 2, erosionFactor: 0.5}, moderate: {pct: 8, erosionFactor: 1}, steep: {pct: 20, erosionFactor: 2}}`.
  - `totalAvailableWater(thetaFC, thetaWP, zrM) -> mm`.
  - `scsRunoff(pMm, cn) -> mm`.
  - `curveNumber(texture, cover: 'crop'|'residue'|'bare', slopeClass) -> number`: en `steep` suma +5 (tope 98); en `flat` resta 3.

- [ ] **Step 1: Escribir la prueba que falla**

```js
import { totalAvailableWater, scsRunoff, curveNumber } from '../web/js/model/soil.js';
test('TAW manual del equipo', () => { assert.equal(Math.round(totalAvailableWater(0.30, 0.15, 0.40)), 60); assert.equal(Math.round(totalAvailableWater(0.30, 0.15, 0.20)), 30); });
test('SCS: P=50, CN=80 -> 13.8 mm', () => assert.ok(Math.abs(scsRunoff(50, 80) - 13.80) < 0.05));
test('SCS: P menor que Ia -> 0', () => assert.equal(scsRunoff(10, 80), 0));
test('CN suelo desnudo > cultivo', () => assert.ok(curveNumber('loam', 'bare', 'moderate') > curveNumber('loam', 'crop', 'moderate')));
test('CN empinado <= 98', () => assert.ok(curveNumber('clay', 'bare', 'steep') <= 98));
```

- [ ] **Step 2:** Run `npm test` → FAIL.
- [ ] **Step 3: Implementar `soil.js`**
  - `S = 25400/CN − 254`.
  - `Ia = 0.2·S`.
  - `Q = (P − Ia)² / (P + 0.8·S)` si `P > Ia`; si no, 0.
- [ ] **Step 4:** Run `npm test` → PASS.
- [ ] **Step 5: Commit:** `feat(model): suelo, número de curva SCS y agua disponible`

### Task 3: Catálogo de cultivos, fenología por grados-día y regla de siembra

**Files:**
- Create: `web/data/crops.json`, `web/data/sequences.json`, `web/js/model/crops.js`, `web/js/model/phenology.js`, `tests/crops.test.mjs`, `tests/phenology.test.mjs`

**Interfaces:**
- Produces:
  - **`crops.json`:** un arreglo de objetos con esta forma:

    ```
    {id, name:{en,es}, family, legume:boolean, needsIrrigation:boolean, harvestRainSensitive:boolean,
     tbase, days:{ini,dev,mid,late}, kc:{ini,mid,end}, zrMax, p, ky,
     econ:{yieldRef, yieldUnit, price, priceUnit, cost, costUnit} | null,
     sources:{agro, days, econ}}
    ```

  - `loadCrops(json) -> Map<id, Crop>`. Valida que cada `Crop` tenga `sources.agro`; si `econ` no es `null`, también `sources.econ`.
  - `TREF = 26`.
  - `stageGdd(crop) -> {ini, dev, mid, late}` = `days × (TREF − tbase)`.
  - `buildPhase(crop, sowIdx, tmean[]) -> Phase`, con:

    ```
    Phase = {cropId, sowIdx, endIdx: {ini, dev, mid, late}, harvestIdx, floweringIdx: [a, b], cycleIncomplete: boolean}
    ```

    Floración = desde el inicio de `mid` hasta el inicio de `mid` + 0.4 × su duración. `harvestIdx` es el fin de `late`; si pasa del final de `tmean`, queda `cycleIncomplete = true` y `harvestIdx = tmean.length − 1`.
  - `kcOnDay(crop, phase, idx) -> number`: curva de FAO-56 por etapas, lineal en `dev` y `late`; 0 fuera del ciclo.
  - `onsetSowIdx(rain[], dates[], year) -> {idx, onsetFallback}`: primer día desde el 1 de mayo en que la lluvia de 3 días suma ≥ 20 mm; si no ocurre, el 15 de junio con `onsetFallback = true`.

- **Valores iniciales de `crops.json`.** Fuentes: Kc del cuadro 12 de FAO-56, Zr y p del cuadro 22, Ky de FAO-33 (estacional); días de ICTA o MAGA donde se indica. El responsable de agronomía confirma página por página y deja `"proxy": true` en los marcados.

  | id | Kc ini/mid/end | Zr (m) | p | Ky | tbase (°C) | Días ini/dev/mid/late | Otros |
  |---|---|---|---|---|---|---|---|
  | maiz | 0.30 / 1.20 / 0.35 | 1.2 | 0.55 | 1.25 | 10 | 20/35/40/25 | ICTA lowland ~120 d |
  | frijol | 0.40 / 1.15 / 0.35 | 0.7 | 0.45 | 1.15 | 10 | 12/18/22/15 | ICTA Ligero: 29–30 d a floración, 64–70 d a cosecha; legume, harvestRainSensitive |
  | sorgo | 0.30 / 1.05 / 0.55 | 1.2 | 0.55 | 0.9 | 10 | 20/35/40/30 | — |
  | ajonjoli | 0.35 / 1.10 / 0.25 | 1.0 | 0.60 | 1.0 | 12 | 20/30/40/20 | harvestRainSensitive; Ky `proxy` |
  | sandia | 0.40 / 1.00 / 0.75 | 1.0 | 0.40 | 1.1 | 12 | 10/20/20/30 | needsIrrigation |
  | melon | 0.50 / 0.85 / 0.60 | 1.0 | 0.45 | 1.1 | 12 | 10/20/25/20 | needsIrrigation; Ky `proxy` |
  | tomate | 0.60 / 1.15 / 0.80 | 1.0 | 0.40 | 1.05 | 10 | 30/40/40/25 | needsIrrigation |
  | mucuna | 0.40 / 1.15 / 0.50 | 1.0 | 0.50 | — | 10 | 15/30/60/15 | `proxy` de soya; legume; econ null |

  `econ` queda en `null` hasta la Tarea 6.

- **`sequences.json`.** Cada fase es `{cropId, sow}`, y `sow` puede ser:
  - `"onset"` (regla de inicio de lluvias);
  - `"MM-DD"` (fecha fija);
  - `{"relayOf": índice, "daysAfterSow": n}` (relevo dentro de otro cultivo).

  Secuencias:
  - `actual`: `[maiz@onset, frijol@09-01]`
  - `proteger`: `[maiz@onset, mucuna@{relayOf:0, daysAfterSow:60}]`
  - `extra_secano`: `[maiz@onset, ajonjoli@09-01]`
  - `extra_riego`: `[maiz@onset, frijol@09-01, sandia@11-20]`, con `requiresIrrigation: true`

- [ ] **Step 1: Escribir las pruebas que fallan**

```js
// phenology.test.mjs
const crop = { id:'t', tbase:10, days:{ini:20,dev:35,mid:40,late:25}, kc:{ini:0.3,mid:1.2,end:0.35} };
test('tmean = TREF: cosecha a los 120 días', () => { const ph = buildPhase(crop, 0, Array(400).fill(26)); assert.equal(ph.harvestIdx, 119); });
test('tmean 18 °C: ciclo el doble de largo', () => { const ph = buildPhase(crop, 0, Array(400).fill(18)); assert.ok(Math.abs(ph.harvestIdx - 239) <= 1); });
test('Kc: ini 0.3, mitad de dev 0.75, mid 1.2', () => { const ph = buildPhase(crop, 0, Array(400).fill(26));
  assert.equal(kcOnDay(crop, ph, 5), 0.3); assert.ok(Math.abs(kcOnDay(crop, ph, 37) - 0.75) < 0.03); assert.equal(kcOnDay(crop, ph, 70), 1.2); });
test('altura: ciclo incompleto marcado', () => { const ph = buildPhase(crop, 300, Array(365).fill(12)); assert.equal(ph.cycleIncomplete, true); });
test('inicio de lluvias: 7+7+7 mm desde el 10 de mayo', () => { /* fechas del año 2010, lluvia 0 salvo 10-12 de mayo = 7 mm */
  const r = onsetSowIdx(rain, dates, 2010); assert.equal(dates[r.idx], '2010-05-12'); assert.equal(r.onsetFallback, false); });
test('año sin inicio: 15 de junio con respaldo', () => { const r = onsetSowIdx(zeros, dates, 2010); assert.equal(dates[r.idx], '2010-06-15'); assert.equal(r.onsetFallback, true); });
// crops.test.mjs
test('todo cultivo tiene fuente agronómica', () => { for (const c of loadCrops(json).values()) assert.ok(c.sources.agro); });
test('cultivo con econ sin fuente es rechazado', () => assert.throws(() => loadCrops([{ ...base, econ: { yieldRef: 1 }, sources: { agro: 'x' } }])));
```

- [ ] **Step 2:** Run `npm test` → FAIL.
- [ ] **Step 3: Escribir `crops.json` y `sequences.json`** con los valores de arriba. En `sources.agro` va la cita exacta, por ejemplo `"FAO-56 cuadro 12 p.110; cuadro 22 p.163; FAO-33"`.
- [ ] **Step 4: Implementar `crops.js` y `phenology.js`.** Los grados-día acumulan `max(0, tmean − tbase)` por día.
- [ ] **Step 5:** Run `npm test` → PASS.
- [ ] **Step 6: Commit:** `feat(model): catálogo de cultivos con fuentes, fenología por grados-día y regla de siembra`

### Task 4: Balance hídrico diario en raíces

**Files:**
- Create: `web/js/model/waterBalance.js`, `tests/waterBalance.test.mjs`

**Interfaces:**
- Consumes: `kcOnDay`, `Phase` (Tarea 3); `scsRunoff`, `curveNumber`, `totalAvailableWater`, `SOILS` (Tarea 2).
- Produces:
  - `stepDepletion({drPrev, rain, runoff, irr, etcAdj, taw}) -> {dr, deepPerc}`: FAO-56 ec. 85. El agotamiento queda entre 0 y TAW; lo que sobra por debajo de 0 pasa a drenaje profundo.
  - `stressCoefficient(dr, taw, p) -> ks`: FAO-56 ec. 84.
  - `simulateDays({rain[], et0[], phases[], crops, texture, slopeClass, irrigation: 'none'|'limited'|'full'}) -> Daily`, donde:

    ```
    Daily = {dr[], ks[], kc[], etc[], eta[], irr[], runoff[], cover[]}   // cover: 'crop' | 'bare'
    ```

  - **Fases traslapadas:** se usan el Kc máximo y la Zr máxima de las fases activas.
  - **Zr que crece:** de 0.15 m al sembrar hasta `zrMax` al fin de `dev`, en forma lineal.
  - **Sin cultivo:** el Kc de suelo desnudo es 0.15 y Zr = 0.15 m.
  - **Riego:**
    - `full`: cuando `dr > RAW` se riega `dr` (se llena hasta capacidad de campo).
    - `limited`: igual, pero solo dentro de la ventana de floración de cada fase.
    - `none`: nunca.

- [ ] **Step 1: Escribir la prueba que falla**

```js
test('ejemplo didáctico del manual: 18 − (12 − 4) + 3 = 13', () => assert.equal(stepDepletion({ drPrev:18, rain:12, runoff:4, irr:0, etcAdj:3, taw:60 }).dr, 13));
test('con escorrentía 8 mm queda en 17', () => assert.equal(stepDepletion({ drPrev:18, rain:12, runoff:8, irr:0, etcAdj:3, taw:60 }).dr, 17));
test('exceso de lluvia: dr = 0 y el resto drena', () => { const r = stepDepletion({ drPrev:5, rain:40, runoff:0, irr:0, etcAdj:2, taw:60 }); assert.equal(r.dr, 0); assert.equal(r.deepPerc, 33); });
test('Ks: TAW 60, p 0.5, Dr 45 -> 0.5', () => assert.equal(stressCoefficient(45, 60, 0.5), 0.5));
test('Ks = 1 si Dr <= RAW', () => assert.equal(stressCoefficient(20, 60, 0.5), 1));
test('riego full mantiene Ks = 1 en sequía', () => { const d = simulateDays({ rain: Array(150).fill(0), et0: Array(150).fill(5), phases:[ph], crops, texture:'loam', slopeClass:'flat', irrigation:'full' }); assert.ok(Math.min(...d.ks.slice(0,149)) >= 0.99); assert.ok(d.irr.reduce((a,b)=>a+b) > 0); });
test('sin riego en sequía Ks cae por debajo de 0.7', () => { const d = simulateDays({ ...same, irrigation:'none' }); assert.ok(Math.min(...d.ks) < 0.7); });
```

- [ ] **Step 2:** Run `npm test` → FAIL.
- [ ] **Step 3: Implementar `waterBalance.js`.** La escorrentía usa `curveNumber(texture, cover, slopeClass)`, con `cover = 'crop'` si hay una fase activa.
- [ ] **Step 4:** Run `npm test` → PASS.
- [ ] **Step 5: Commit:** `feat(model): balance hídrico diario FAO-56 con riego y fases traslapadas`

### Task 5: Simulación de secuencias por año agrícola

**Files:**
- Create: `web/js/model/simulate.js`, `tests/simulate.test.mjs`

**Interfaces:**
- Consumes: Tareas 1–4. También usa `ClimateBundle` (definido en la Tarea 7):

  ```
  {dates[], tmax[], tmin[], tdew[], rs[], u2[], pressure[], rain[], rainSource, elevation, lat, lon, sources[], fallback}
  ```

- Produces:
  - `computeEt0Series(bundle) -> number[]`.
  - `agriculturalYears(dates) -> [{year, startIdx, endIdx}]`: del 1 de abril al 31 de marzo; solo años completos.
  - `runSequence({sequence, bundle, et0, crops, texture, slopeClass, irrigation}) -> YearResult[]`, con:

    ```
    YearResult = {year, crops: CropYear[], bareDaysRainy, runoffBareMm, irrigationMm, onsetFallback, cycleIncomplete}
    CropYear   = {cropId, sowDate, harvestDate, etaOverEtc, ksFlowerMean, stressFlowering: boolean,
                  relYield, harvestRainEvent: boolean, irrigationMm, cycleIncomplete}
    ```

  - Definiciones:
    - `relYield = clamp(1 − ky·(1 − ΣETa/ΣETc), 0, 1)`; es `null` en cultivos sin `ky`.
    - `stressFlowering = ksFlowerMean < 0.7`.
    - `harvestRainEvent` = al menos 2 días con lluvia > 10 mm en los 10 días antes de la cosecha (solo cultivos `harvestRainSensitive`).
    - `bareDaysRainy` = días sin fase activa entre el 1 de mayo y el 30 de noviembre.
  - Si la secuencia exige riego (`requiresIrrigation`) y `irrigation === 'none'`, `runSequence` devuelve `[]`.

- [ ] **Step 1: Escribir la prueba que falla.** Clima sintético de 3 años agrícolas: lluvia de 8 mm/día de mayo a octubre y 0 el resto, ET₀ de 4 mm/día, tmean de 26 °C.

```js
test('3 años completos', () => assert.equal(agriculturalYears(dates).length, 3));
test('actual: maíz sin estrés con lluvia abundante', () => { const r = runSequence({ sequence: seq.actual, ... }); assert.equal(r[0].crops[0].stressFlowering, false); assert.ok(r[0].crops[0].relYield > 0.9); });
test('suelo desnudo: proteger < actual', () => assert.ok(run('proteger')[0].bareDaysRainy < run('actual')[0].bareDaysRainy));
test('extra_riego sin riego -> []', () => assert.deepEqual(runSequence({ sequence: seq.extra_riego, irrigation:'none', ... }), []));
test('altura: cycleIncomplete propagado', () => { /* tmean 12 °C */ assert.equal(r[0].cycleIncomplete, true); });
```

- [ ] **Step 2:** Run `npm test` → FAIL.
- [ ] **Step 3: Implementar `simulate.js`.** Las fechas `"MM-DD"` se resuelven dentro del año agrícola. `relayOf` usa `sowIdx` de la fase indicada + `daysAfterSow`.
- [ ] **Step 4:** Run `npm test` → PASS.
- [ ] **Step 5: Commit:** `feat(model): simulación de secuencias por año agrícola`

### Task 6: Economía, indicadores, puntaje y listas Aprovechar/Mitigar

**Files:**
- Modify: `web/data/crops.json` (llenar `econ` con las fichas agroeconómicas MAGA)
- Create: `web/js/model/economics.js`, `web/js/model/indicators.js`, `web/js/model/score.js`, `web/js/model/explain.js`, `tests/economics.test.mjs`, `tests/score.test.mjs`, `tests/explain.test.mjs`

**Interfaces:**
- Consumes: `YearResult[]` (Tarea 5).
- Produces:
  - `cropMargin(crop, relYield, irrigationMm, costPerM3 = 1.0) -> number | null`:
    - fórmula: `econ.yieldRef × relYield × econ.price − econ.cost − irrigationMm × 6.987 × costPerM3`;
    - es `null` si `econ` es `null` o si `relYield` es `null`.
  - `yearMargin(yearResult, crops) -> number | null`: suma de los cultivos; es `null` si alguno es `null`.
  - `summarize(yearResults, baselineYearResults, crops, slopeClass) -> Indicators`, con:

    ```
    Indicators = {n, medianMargin, p10Margin, medianExtra, p10Extra, p90Extra,
                  stressYears: {[cropId]: k}, harvestRainYears: {[cropId]: k},
                  coverFrac, legume: boolean, erosionIndex, irrigationMm, onsetFallbackYears, cycleIncompleteYears}
    ```

    - `erosionIndex = clamp(mediana(runoffBareMm) × erosionFactor / 100, 0, 1)`.
    - `coverFrac = 1 − mediana(bareDaysRainy) / 214`.
  - `score(ind, baseInd, weights: {protect, extra, soil, water}) -> {total, parts}`:
    - `protect = clamp(ind.p10Margin / baseInd.medianMargin, 0, 1)`
    - `extra = clamp(ind.medianExtra / 5000, 0, 1)`
    - `soil = mean(coverFrac, legume ? 1 : 0, 1 − erosionIndex)`
    - `water = clamp(1 − irrigationMm / 300, 0, 1)`
    - Una parte `null` se excluye de las dos sumas.
    - `total = 100 × Σ(w·x) / Σw`.
  - `buildLists(ind, n, lang, t) -> {aprovechar: string[], mitigar: [{risk, action}]}`. Las plantillas viven en i18n. Un riesgo se lista si afecta ≥ 20 % de los años.

    | Riesgo (clave) | Acción (clave) |
    |---|---|
    | `risk.floweringStress` | `action.sowEarlierOrShortVariety` |
    | `risk.harvestRain` | `action.shiftSowing` |
    | `risk.bareSoil` (> 30 días) | `action.coverCrop` |
    | `risk.noEcon` | `action.checkLocalPrices` |
    | `risk.cycleIncomplete` | `action.altitudeCheck` |
    | `risk.onsetFallback` | `action.waitForRains` |

    "Aprovechar": `opp.extraGain` (si `medianExtra > 0`), `opp.lowStress` (≤ 10 % de los años), `opp.legume` y `opp.irrigatedWindow`.

- [ ] **Step 1: Llenar `econ` desde las fichas MAGA.**
  - Descargar las fichas de maíz, frijol negro, sandía, melón y tomate desde SIEAGRO (`apps.maga.gob.gt/sieagro/Normativas?categoriaId=202&clasificacionId=21&tipoId=1`).
  - Copiar rendimiento por manzana, precio y costo total por manzana, cada uno con la página.
  - Sorgo, ajonjolí y mucuna: `econ: null`, salvo que aparezca una fuente.
- [ ] **Step 2: Escribir las pruebas que fallan**

```js
const maiz = { econ:{ yieldRef:40, price:200, cost:6000 } };
test('margen: 40 × 1 × 200 − 6000 = 2000', () => assert.equal(cropMargin(maiz, 1, 0), 2000));
test('margen con relYield 0.75 = 0', () => assert.equal(cropMargin(maiz, 0.75, 0), 0));
test('riego 100 mm cuesta 698.7 Q', () => assert.ok(Math.abs(cropMargin(maiz, 1, 100) - (2000 - 698.7)) < 0.01));
test('sin econ -> null', () => assert.equal(cropMargin({ econ:null }, 1, 0), null));
test('puntaje: partes 0.8/0.5/0.6/0.9 con pesos 1 = 70', () => assert.equal(Math.round(scoreFromParts({protect:.8,extra:.5,soil:.6,water:.9},{protect:1,extra:1,soil:1,water:1})), 70));
test('parte null se excluye', () => assert.equal(Math.round(scoreFromParts({protect:.8,extra:null,soil:.6,water:1},{protect:1,extra:1,soil:1,water:1})), 80));
test('mitigar: estrés en 9 de 24 años sale con acción', () => { const l = buildLists({ ...ind, stressYears:{maiz:9} }, 24, 'es', t); assert.ok(l.mitigar.some(m => m.risk.includes('9') && m.action)); });
test('estrés en 2 de 24 años no sale', () => { const l = buildLists({ ...ind, stressYears:{maiz:2} }, 24, 'es', t); assert.equal(l.mitigar.filter(m => m.risk.includes('2 de')).length, 0); });
```

- [ ] **Step 3:** Run `npm test` → FAIL.
- [ ] **Step 4: Implementar.** `score.js` exporta `score` y `scoreFromParts`.
- [ ] **Step 5:** Run `npm test` → PASS.
- [ ] **Step 6: Commit:** `feat(model): margen con fichas MAGA, indicadores, puntaje y listas aprovechar/mitigar`

### Task 7: Datos de clima en vivo con respaldo y snapshots de pilotos

**Files:**
- Create: `web/js/data/climate.js`, `tests/climate.test.mjs`, `scripts/build_snapshots.py`, `scripts/requirements.txt` (numpy, tifffile, torch), `web/data/sites.json`, `web/data/snapshots/{chiquimula,jutiapa,sanmartin}.json`, `web/data/rain_compare.json`

**Interfaces:**
- Produces:
  - `isInsideGuatemala(lat, lon) -> boolean`: caja lat 13.6–17.9, lon −92.3 – −88.1.
  - `fetchPowerDaily(lat, lon, fetchFn = fetch) -> Promise<Partial<ClimateBundle>>`:
    - parámetros `T2M_MAX, T2M_MIN, T2MDEW, ALLSKY_SFC_SW_DWN, WS2M, PS, PRECTOTCORR`; comunidad AG; 20010101–20251231;
    - el valor `-999` se convierte en `null`.
  - `fetchEra5Rain(lat, lon, fetchFn = fetch) -> Promise<{dates, rain}>`: archivo de Open-Meteo con `models=era5`, `daily=precipitation_sum`, `timezone=America/Guatemala`, 2001-01-01 a 2025-12-31.
  - `getClimate({lat, lon}, {fetchFn, timeoutMs: 8000, sites}) -> Promise<ClimateBundle>`:
    - si el punto está a menos de 3 km de un piloto, usa su snapshot (`rainSource: 'IMERG'` o `'ERA5'`);
    - si no, busca POWER y ERA5 en vivo;
    - si se pasan los 8 s o algo falla, usa el snapshot del piloto más cercano con `fallback: true`;
    - los días con valor `null` se rellenan interpolando entre vecinos (máximo 3 días seguidos); si el hueco es más largo, el año se descarta.
  - `sites.json`: `[{id, name, lat, lon, elevation, texture, slopeClass, slopePct, rainSource, sources}]`, con:
    - `chiquimula` 14.80, −89.54;
    - `jutiapa` 14.29, −89.90;
    - `sanmartin` 14.78, −90.79.
  - `build_snapshots.py`:
    - reutiliza `scripts/descargar_power.py` (stdlib) y llama a ERA5 de Open-Meteo para cada sitio;
    - textura: SoilGrids WCS (`maps.isric.org`, coberturas `sand_0-5cm_mean` y `clay_0-5cm_mean`, píxel único en EPSG:4326), leída con `tifffile`; clase por el triángulo USDA reducido a sand / loam / clay;
    - pendiente: elevación de Open-Meteo (Copernicus DEM) en el centro ± 0.001°; clase flat si < 4 %, moderate si < 12 %, steep en el resto. Se rotula "Copernicus DEM (replace with SRTM when AppEEARS arrives)";
    - `rain_compare.json`: `{[siteId]: {years[], power[], era5[], imerg[]|null}}` con la lluvia anual.

- [ ] **Step 1: Escribir las pruebas que fallan** (sin red; `fetchFn` simulado)

```js
test('punto en el Pacífico se rechaza', () => assert.equal(isInsideGuatemala(12.5, -91.0), false));
test('Chiquimula está dentro', () => assert.equal(isInsideGuatemala(14.80, -89.54), true));
test('-999 se convierte en null', async () => { const b = await fetchPowerDaily(14.8, -89.5, fakeFetch(powerWith999)); assert.equal(b.tmax[1], null); });
test('API que nunca responde -> snapshot en <= 8.5 s con fallback', async () => {
  const t0 = Date.now(); const b = await getClimate({ lat:14.9, lon:-89.6 }, { fetchFn: () => new Promise(()=>{}), timeoutMs: 300, sites, loadSnapshot });
  assert.equal(b.fallback, true); assert.ok(Date.now() - t0 < 1000); });
test('lluvia del bundle en vivo viene de ERA5', async () => { const b = await getClimate({ lat:15.2, lon:-89.9 }, { fetchFn: fakeOk, timeoutMs: 1000, sites, loadSnapshot }); assert.equal(b.rainSource, 'ERA5'); });
```

- [ ] **Step 2:** Run `npm test` → FAIL.
- [ ] **Step 3: Implementar `climate.js`.** `loadSnapshot(id)` hace `fetch('data/snapshots/'+id+'.json')` en el navegador; en las pruebas se inyecta.
- [ ] **Step 4: Precalcular los pilotos.** Run: `py -m pip install -r scripts/requirements.txt` y luego `py scripts/build_snapshots.py`.
  Expected:
  - 3 archivos en `web/data/snapshots/` con 9,131 días cada uno;
  - `sites.json` con textura y pendiente;
  - `rain_compare.json` con la lluvia de POWER mayor que la de ERA5 en Chiquimula en 2021–2023.
- [ ] **Step 5:** Run `npm test` → PASS.
- [ ] **Step 6: Commit:** `feat(data): clima en vivo POWER+ERA5 con respaldo y snapshots de 3 pilotos`

### Task 8: Validación del modelo contra sequías documentadas

**Files:**
- Create: `scripts/validate.mjs`, `web/data/validation.json`, `tests/validation.test.mjs`

**Interfaces:**
- Consumes: el snapshot de `chiquimula`, `runSequence` y `summarize`.
- Produces: `validation.json` = `{site, droughtYears: [2013, 2014, 2018, 2019], meanKsFlowerDrought, meanKsFlowerOther, rankDrought: {[year]: rank}, sources: [FEWS NET/GEOGLAM URLs del informe]}`. 2025 queda fuera porque el año agrícola 2025 está incompleto.

- [ ] **Step 1: Escribir la prueba**

```js
test('Ks medio en floración del maíz: años de sequía < resto', () => { const v = JSON.parse(readFileSync('web/data/validation.json')); assert.ok(v.meanKsFlowerDrought < v.meanKsFlowerOther); });
```

- [ ] **Step 2:** Run `node scripts/validate.mjs` y luego `npm test`.
  - Si pasa, se sigue.
  - Si falla, se revisan la fuente de lluvia y la regla de siembra, y el resultado se informa al equipo. No se ajusta el modelo solo para que pase.
- [ ] **Step 3: Commit:** `test(validation): balance hídrico vs años de sequía FEWS NET en Chiquimula`

### Task 9: Interfaz · base, mapa, idioma y la parcela

**Files:**
- Create: `web/index.html`, `web/css/app.css`, `web/js/main.js`, `web/js/i18n.js`, `web/i18n/en.json`, `web/i18n/es.json`, `web/js/ui/map.js`, `web/js/ui/site.js`

**Interfaces:**
- Consumes: `getClimate`, `isInsideGuatemala` (Tarea 7) y `sites.json`.
- Produces:
  - `i18n.t(key, vars) -> string` y `i18n.setLang('en'|'es')`.
  - Estado global en `main.js`:

    ```
    state = {lang, site:{lat, lon, siteId|null}, texture, slopeClass, irrigation, bundle, weights, currentSequence}
    ```

  - Eventos: `document.dispatchEvent(new CustomEvent('fs:climate-ready'))` cuando hay `bundle`.
  - Mapa:
    - Leaflet centrado en Guatemala (15.5, −90.3), zoom 7.
    - Capa base OSM.
    - Capas conmutables:
      - NASA GIBS `MODIS_Terra_NDVI_8Day` (epsg3857, best, GoogleMapsCompatible_Level9);
      - NASA GIBS `IMERG_Precipitation_Rate`;
      - Sentinel-2 cloudless 2023 de EOX (`https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2023_3857/default/g/{z}/{y}/{x}.jpg`).
    - Marcadores de los pilotos. Un clic fuera de Guatemala muestra `i18n.t('error.outside')`.
  - Formulario de la parcela: textura (`sand`/`loam`/`clay`), pendiente (`flat`/`moderate`/`steep`) y riego (`none`/`limited`/`full`), precargados desde `sites.json` cuando es un piloto.
  - Avisos:
    - `notice.fallback` cuando `bundle.fallback`;
    - `notice.altitude` cuando `elevation > 1500`;
    - leyenda fija `legend.support`.

- [ ] **Step 1: Implementar.** Cuatro secciones con navegación por pasos: inicio, parcela, rotación y prioridades, comparar. Más la sección Métodos. Diseño para celular primero, contraste AA.
- [ ] **Step 2: Verificar** con un servidor local (`py -m http.server 8000 -d web`):
  - abre en inglés y el botón cambia a español;
  - elegir Chiquimula carga el snapshot en < 2 s;
  - un clic en el mar muestra el error;
  - las 3 capas cargan.
- [ ] **Step 3: Commit:** `feat(ui): base de la app, mapa con capas NASA/Copernicus, idioma EN/ES y datos de la parcela`

### Task 10: Interfaz · historia climática, rotación y prioridades

**Files:**
- Create: `web/js/ui/climateStory.js`, `web/js/ui/sequenceForm.js`, `web/js/ui/priorities.js`

**Interfaces:**
- Consumes: `bundle`, `computeEt0Series`, `agriculturalYears`, `onsetSowIdx` y `sequences.json`.
- Produces:
  - `climateStory(bundle)` dibuja tres gráficas Chart.js:
    - lluvia mensual promedio, con la fuente rotulada;
    - fecha de inicio de lluvias por año;
    - duración de la canícula por año: la racha más larga con lluvia < 1 mm/día entre el 1 de julio y el 31 de agosto.
  - `sequenceForm` muestra la rotación actual (editable: cultivo, fecha) y las alternativas. `extra_riego` se oculta si `irrigation === 'none'`.
  - `priorities` tiene cuatro deslizadores de 0 a 5, todos en 3 por defecto (`protect`, `extra`, `soil`, `water`), y dispara `fs:weights-changed`.

- [ ] **Step 1: Implementar.**
- [ ] **Step 2: Verificar** en el navegador con Chiquimula:
  - las 3 gráficas aparecen con datos 2001–2024;
  - cambiar el riego muestra u oculta la alternativa con riego.
- [ ] **Step 3: Commit:** `feat(ui): historia climática de la parcela, rotación y prioridades`

### Task 11: Interfaz · comparar, cómo se calcula, métodos y datos

**Files:**
- Create: `web/js/ui/compare.js`, `web/js/ui/methods.js`

**Interfaces:**
- Consumes: `runSequence`, `summarize`, `score`, `buildLists`, `rain_compare.json` y `validation.json`.
- Produces:
  - **Tarjetas.** La rotación actual va como línea base; luego cada alternativa, ordenada por puntaje. Cada tarjeta muestra:
    - puntaje y diferencia contra la actual;
    - "Proteger" (margen del año malo y años con estrés);
    - "Ganar extra" (mediana y rango P10–P90 en Q/mz, o "no data");
    - listas Aprovechar y Mitigar;
    - secciones desplegables: Evidencia (fuentes de datos y de parámetros), Qué falta saber, Revisar con un experto, ¿Cómo se calcula? (las partes del puntaje con sus valores).
  - **Gráfica año por año** del margen estimado de cada secuencia.
  - **Métodos y datos:**
    - tabla de fuentes con producto, versión, resolución y acceso;
    - ecuaciones y supuestos fijos;
    - gráfica de lluvia POWER vs ERA5 vs IMERG;
    - resultado de la validación;
    - referencias;
    - declaración de uso de SI (texto fijo en i18n: dónde se usó IA en código, investigación y textos).

- [ ] **Step 1: Implementar.**
- [ ] **Step 2: Verificar** en Chiquimula con riego `none`:
  - aparecen 3 tarjetas (actual, proteger, extra secano);
  - mover el deslizador "extra" a 5 cambia el orden o los puntajes;
  - un cultivo sin `econ` muestra "no data", nunca NaN.
- [ ] **Step 3: Commit:** `feat(ui): comparación con aprovechar/mitigar, cómo se calcula y página de métodos`

### Task 12: Publicación y documentación

**Files:**
- Create: `.github/workflows/pages.yml`, `LICENSE` (MIT, código), `LICENSE-docs` (CC BY 4.0)
- Modify: `README.md` (sección en inglés: qué es, cómo correrlo, datos, licencias, uso de SI)

**Interfaces:**
- Produces: el sitio público en `https://notsosa.github.io/field-shift-guatemala/`.

- [ ] **Step 1: Workflow.** `actions/configure-pages@v5` + `actions/upload-pages-artifact@v3` (`path: web`) + `actions/deploy-pages@v4`, disparado con cada push a `main`. Antes corre `npm test` con Node 20; si fallan las pruebas, no se publica.
- [ ] **Step 2:** El dueño del repo (Carlos) activa Settings → Pages → Source: **GitHub Actions**.
- [ ] **Step 3: Push y verificar:**
  - el workflow queda en verde;
  - la URL abre en una ventana privada, sin login, en celular y en escritorio;
  - Chiquimula carga y las tarjetas aparecen.
- [ ] **Step 4: Commit:** `ci: publicar web/ en GitHub Pages; docs: README y licencias`

### Task 13: Emulador · datos, red embudo y ELM sin backpropagation

**Files:**
- Create: `scripts/emulator/generate.mjs`, `scripts/emulator/train_mlp.py`, `scripts/emulator/evaluate.mjs`, `web/js/model/emulator.js`, `web/data/emulator_mlp.json`, `web/data/emulator_eval.json`, `web/data/grid_features.json`, `tests/emulator.test.mjs`

**Interfaces:**
- Consumes: el modelo completo (Tareas 1–6) y snapshots ERA5+POWER de una cuadrícula de unos 20 puntos del Corredor Seco (0.25°, dentro de los departamentos Chiquimula, Zacapa, El Progreso, Jutiapa, Jalapa y Baja Verapaz), descargados por `generate.mjs` y guardados en `scripts/emulator/cache/` (fuera de `web/`).
- Produces:
  - `featuresOf(bundleYear, site, sequenceId, sowOffsetDays, texture, slopeClass, irrigation) -> number[25]`:
    - lluvia de mayo a julio, de agosto a octubre y anual;
    - días de canícula;
    - ET₀ media de mayo a octubre y tmean de mayo a octubre;
    - elevación;
    - textura (one-hot de 3), pendiente (one-hot de 3), riego (one-hot de 3), secuencia (one-hot de 4);
    - `sowOffsetDays / 30`.
  - Objetivos: `[margen del año (Q/mz) / 10000, ksFlowerMean del primer cultivo, bareDaysRainy / 214]`.
  - `mlpPredict(weightsJson, x) -> number[3]`: capas densas con ReLU y salida lineal; normalización de entrada con `mean` y `std` del JSON.
  - `trainELM(X, Y, {hidden: 300, lambda: 1e-2, seed: 42}) -> ElmModel`:
    - capa oculta aleatoria `tanh(W·x + b)` con generador `mulberry32(seed)`;
    - salida `β = (HᵀH + λI)⁻¹ HᵀY` por Cholesky;
    - **sin backpropagation**.
  - `elmPredict(model, x) -> number[3]`.
  - `emulator_eval.json`:

    ```
    {mlp: {rmse[], r2[], trainSeconds, params, trainMemoryMB}, elm: {...igual}, nTrain, nTest,
     split: 'años 2019–2024 y 4 puntos de la cuadrícula fuera del entrenamiento'}
    ```

- [ ] **Step 1: Escribir las pruebas que fallan**

```js
test('ELM aprende y = 2x1 − x2 con R2 > 0.99', () => { const m = trainELM(X, Y, { hidden: 50, lambda: 1e-6, seed: 1 }); assert.ok(r2(Y, X.map(x => elmPredict(m, x))) > 0.99); });
test('ELM es determinista con la misma semilla', () => assert.deepEqual(elmPredict(trainELM(X,Y,{hidden:20,lambda:1e-3,seed:7}), X[0]), elmPredict(trainELM(X,Y,{hidden:20,lambda:1e-3,seed:7}), X[0])));
test('mlpPredict reproduce una red 2→2→1 escrita a mano', () => assert.ok(Math.abs(mlpPredict(tinyNet, [1, 2])[0] - expected) < 1e-9));
test('emulator_eval tiene ambos modelos con R2 de margen > 0.8', () => { const e = JSON.parse(readFileSync('web/data/emulator_eval.json')); assert.ok(e.mlp.r2[0] > 0.8 && e.elm.r2[0] > 0.8); });
```

- [ ] **Step 2:** Run `npm test` → FAIL.
- [ ] **Step 3: Implementar `emulator.js`.**
- [ ] **Step 4: Generar datos.** Run: `node scripts/emulator/generate.mjs`.
  Expected: unas 50,000 muestras (submuestreo aleatorio con semilla 42) en `scripts/emulator/samples.json`, y `web/data/grid_features.json` con las features por punto y año.
- [ ] **Step 5: Entrenar la red embudo.** Run: `py scripts/emulator/train_mlp.py`.
  - Red 25→64→32→16→3, Adam con lr 1e-3, lote 256, parada temprana con paciencia 10, PyTorch en CPU.
  - Exporta `web/data/emulator_mlp.json` con pesos, `mean`, `std`, tiempo y memoria pico.
- [ ] **Step 6: Evaluar.** Run: `node scripts/emulator/evaluate.mjs`. Entrena la ELM en Node, mide ambos modelos en el conjunto de prueba y escribe `emulator_eval.json`.
- [ ] **Step 7:** Run `npm test` → PASS. Si un R² queda ≤ 0.8, se informa el valor real y se ajustan las features; no se baja el umbral sin avisar al equipo.
- [ ] **Step 8: Commit:** `feat(si): emulador del simulador FAO-56, red embudo (backprop) vs ELM (sin backprop)`

### Task 14: Interfaz del emulador · mapa del Corredor Seco y mejor fecha de siembra

**Files:**
- Create: `web/js/ui/emulatorMap.js`, `web/js/ui/bestSowing.js`

**Interfaces:**
- Consumes: `mlpPredict`, `trainELM`, `elmPredict`, `grid_features.json`, `emulator_eval.json`, `state.weights`, `state.irrigation`.
- Produces:
  - **Mapa "¿Dónde conviene cada alternativa?"**
    - Círculos en los puntos de la cuadrícula, coloreados por la ganancia extra mediana de la alternativa elegida frente a `actual`, según el emulador.
    - Un selector MLP/ELM.
    - La ELM se entrena en el navegador al abrir la sección, y se muestran su tiempo de entrenamiento y memoria aproximada.
    - Leyenda con el error del `emulator_eval.json`.
  - **Mejor fecha de siembra**
    - Para el sitio actual prueba desfases de −20 a +30 días cada 2 días con el emulador.
    - Propone el mejor y **lo confirma corriendo el simulador real** con esa fecha.
    - Muestra ambos valores lado a lado.
  - **Texto fijo:** "AI learns our physical model; it does not predict real harvests" / "La IA aprende nuestro modelo físico; no predice cosechas reales".

- [ ] **Step 1: Implementar.**
- [ ] **Step 2: Verificar** en el navegador:
  - el mapa se dibuja en < 1 s;
  - la ELM entrena en < 5 s;
  - la fecha propuesta y la confirmada por el simulador aparecen juntas.
- [ ] **Step 3: Commit:** `feat(ui): mapa de oportunidades del Corredor Seco y mejor fecha de siembra con el emulador`

### Task 15: Paquete de entrega (equipo)

**Files:**
- Create: `entrega/project_page_en.md` (textos en inglés para cada campo del formulario), `entrega/demo/` (7 diapositivas)

- [ ] **Step 1: Llenar los textos de la página Project en inglés:**
  - Project Name y High-Level Summary;
  - Link to Demo y Link to Final Project (URL de Pages);
  - Detailed Description, Use of SI, NASA Data y Space Agency Partner & Other Data, con todas las fuentes y licencias.
- [ ] **Step 2: Demo de 7 diapositivas**, incluidas la portada y la de introducción. Debe incluir:
  - equipo, reto, problema, cómo funciona, datos NASA/Copernicus/MAGA, validación, IA y futuro;
  - nombres del equipo y del reto.
  - Las imágenes generadas con IA llevan marca de agua.
- [ ] **Step 3: Revisar** que todos los enlaces abran en una ventana privada.
- [ ] **Step 4: Submit for Judging** antes del domingo a las 4 p. m. (se puede reenviar hasta las 11:59 p. m.).
- [ ] **Step 5: Commit:** `docs(entrega): textos de la página Project y demo`

### Tareas opcionales (dependen de la cuenta Earthdata del equipo)

- **IMERG en pilotos:** `scripts/imerg_points.py` con `earthaccess` (token en una variable de entorno, nunca en el repo) llena `rain` de los snapshots de pilotos con `rainSource: 'IMERG'` y `rain_compare.json.imerg`. Prueba: la lluvia anual de IMERG en Chiquimula queda dentro de ±40 % de ERA5 o se reporta la diferencia.
- **NDVI de los pilotos** (sin cuenta): series de MODIS 13Q1 y Sentinel-2 L2A por Microsoft Planetary Computer (STAC + token SAS anónimo). Se usan para comparar en Métodos los días de suelo desnudo del modelo con la caída de NDVI.
- **SMAP L4 y SRTM** (AppEEARS, tareas T03/T05 de `tasks.md`):
  - la humedad radicular SMAP 2015–2024 se compara con `1 − dr/TAW` del balance en Métodos;
  - SRTM reemplaza la pendiente de Copernicus DEM en `sites.json`.
