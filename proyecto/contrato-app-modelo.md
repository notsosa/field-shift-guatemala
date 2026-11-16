# Contrato entre la app de Carlos y el modelo de Keu

15 de noviembre de 2026. Este documento dice qué entra y qué sale en cada lado, en qué se diferencian y cómo se enchufaría la red alineada con la app en la función `recomendar(...)` de `app/V01/lib/motor/recomendador.dart` (commit `0990e9d` de `origin/main`). **La red no está conectada a la app en esta tarea.** Todo número sale del código de la app, del código del modelo o de un archivo generado; cuando no se midió, la celda lo dice.

Archivos de la app leídos: `motor/fao56.dart`, `motor/recomendador.dart`, `modelos.dart`, `datos/clima.dart`, `estado.dart` (función `sincronizar`) y `HANDOFF.md`. Archivos del modelo: `web/data/crops.json`, `web/js/model/soil.js`, `web/js/model/waterBalance.js`, `web/js/data/climate.js`, `scripts/emulator/points.json`, `web/data/rain_compare.json`, `web/data/app_eval.json`, `web/data/app_mlp.json`.

## 1. Entradas: lo que tiene la app y lo que usa el modelo

| Entrada de la app | Entrada equivalente del modelo | Diferencia |
|---|---|---|
| Latitud y longitud de la finca (`Parcela`) | `lat`, `lon` del punto (`points.json`) | Ninguna: el mismo punto. |
| Elevación de la **celda de NASA POWER** (`geometry.coordinates[2]` de la respuesta; 500 m si falta) | `elevation` = elevación de la **parcela** (`siteElevation`, Copernicus DEM vía Open-Meteo); la de la celda queda aparte como `cellElevation` | La app usa la altura de la celda para la presión y para la radiación de cielo despejado; el modelo usa la de la parcela y además baja o sube la temperatura (ver sección 2). |
| Clima diario de NASA POWER: `T2M_MAX, T2M_MIN, RH2M, WS2M, ALLSKY_SFC_SW_DWN, PRECTOTCORR`, comunidad AG, `time-standard LST` | POWER: `T2M_MAX, T2M_MIN, T2MDEW, ALLSKY_SFC_SW_DWN, WS2M, PS, PRECTOTCORR` (`web/js/data/climate.js`) y lluvia de ERA5 | `RH2M` no existe en el modelo (usa `T2MDEW`); `T2MDEW` y `PS` no existen en la app (usa `RH2M` y la presión por la altura). La lluvia del modelo es ERA5; la de la app es la de POWER. |
| Ventana de clima: desde la siembra más antigua, con mínimo 60 y máximo 240 días atrás, hasta hoy | Año agrícola completo (1 de abril a 31 de marzo) y años anteriores completos | La app no tiene historia de varios años ni pronóstico. Una entrada del modelo como `rainYear` o `caniculaDays` necesita el año completo y la app no lo tiene el día de hoy. |
| Cultivo: `maiz`, `frijol`, `tomate`, `cafe` | 13 cultivos en `crops.json` | Los 9 restantes no existen en la app. El café existe en la app **sin Ky**: no hay `factorRendimiento` para él y por eso queda fuera de la red de esta tarea. |
| Fecha de siembra | Fecha de siembra por la regla de inicio de lluvias más un desfase | En la app la fecha la pone el productor; en el modelo la fija una regla. |
| Ciclo elegido por el productor (maíz 90/120, frijol 67/80/90, tomate 120/145 días) | Ciclo por grados-día (`tbase` 10 °C; días por etapa a temperatura de referencia en `crops.json`) | Ciclo fijo en la app, variable con la temperatura en el modelo. |
| Suelo: arenoso 100, franco 150, arcilloso 180 mm de agua disponible por metro | Suelo de SoilGrids por piloto (θFC − θWP) o las clases `sand`, `loam`, `clay` | Ver sección 2. |
| Riego: tipo (manual 4, goteo 6, aspersión 12, gravedad 30 mm por riego) y conteo semanal de riegos | `irrigation`: `none`, `limited`, `full` | La red de esta tarea es **a secano**: no usa riego. En el modelo no hay conteos semanales. |
| Plaga y fertilizante (notas y avisos) | No existe en el modelo | En la app solo generan avisos; no cambian el balance de agua. |
| Estado que la app calcula: reserva, agotamiento, Ks, etapa, días desde siembra, días a cosecha, días de estrés de los últimos 7, lluvia y necesidad de cultivo de los últimos 7, `factorRendimiento` hasta hoy | El modelo no usa estas cantidades como entrada (v3 usa solo clima, parámetros y fecha) | La red alineada sí las usa como entrada: son lo más informativo que la app ya tiene. |

## 2. Diferencias que cambian los resultados

La columna "Dirección" dice qué se sabe y de dónde. Cuando no se midió, dice "no medida".

| Diferencia | App | Modelo | Dirección |
|---|---|---|---|
| Lluvia | POWER (`PRECTOTCORR`) | ERA5 | Promedio anual de los 20 años en común (`web/data/rain_compare.json`): Chiquimula 1 551.0 mm POWER frente a 1 110.3 ERA5; Jutiapa 1 252.1 frente a 1 102.6; San Martín Jilotepeque 1 409.3 frente a 1 103.3. Días secos seguidos entre el 1 de julio y el 31 de agosto (canícula): 3.4, 3.2 y 2.9 días en POWER frente a 4.2, 5.6 y 5.3 en ERA5. POWER da **más lluvia y menos canícula** que ERA5 en los tres pilotos. El efecto sobre el estrés de la app no está medido aquí. |
| Temperatura y elevación | Temperatura de la celda sin corregir; elevación de la celda | Temperatura llevada a la elevación de la parcela con −0.0065 °C/m | Corrección del modelo respecto de la celda (`scripts/emulator/cache/*.json`): Chiquimula (parcela 403 m, celda 762.46 m) +2.34 °C; Jutiapa (903 m, 1 040.48 m) +0.89 °C; San Martín Jilotepeque (1 787 m, 1 515.75 m) −1.76 °C. Es decir, la app ve la temperatura de la celda: más fría que la parcela en Chiquimula y Jutiapa, más cálida en San Martín. El efecto sobre la ET₀ no está medido aquí. |
| Duración del ciclo | Días fijos que elige el productor | Grados-día: el ciclo se acorta con calor y se alarga con frío | No medida. |
| Almacenes de agua | Un solo almacén (zona de raíces) que **empieza al 50 % de agotamiento** el día de la siembra (`agotamientoInicial = 0.5`) | Dos almacenes (zona de raíces y subsuelo); a secano todo el perfil **arranca seco** el 1 de abril | La app parte de un suelo medio lleno el día de la siembra; el modelo, de un suelo seco en abril. No medida su diferencia en el factor de rendimiento. |
| Escorrentía | Número de curva fijo 78 | Por grupo hidrológico: arena 67, franco 78, arcilla 89 (cultivo; `soil.js`), y con pendiente | La app coincide con el franco del modelo; en suelos arcillosos el modelo escurre más y en arenosos menos. No medida. |
| Agua disponible | 100 / 150 / 180 mm/m (tabla 19 de FAO-56) | Clases del modelo: 75 (`sand`), 130 (`loam`), 140 (`clay`) mm/m; SoilGrids: Chiquimula 150.1, Jutiapa 55.7, San Martín Jilotepeque 130.5 mm/m (θFC − θWP de `points.json`) | La clase arcillosa de la app (180) supera a la del modelo (140). En Jutiapa SoilGrids da 55.7 mm/m y la app solo ofrece 100 como mínimo, así que ahí la app sobrestima el agua disponible; en Chiquimula (150.1) coincide con el franco de la app y en San Martín Jilotepeque (130.5) queda entre las clases del modelo y la franca de la app. |
| Rendimiento por agua | Ky estacional de FAO-33, una sola vez con la ETa/ETc de todos los días hasta hoy | Ky por etapa de FAO-66 (maíz: vegetativa 0.4, floración 1.5, formación 0.5, maduración 0.2; frijol: 0.2, 1.1, 0.75, 0.2), multiplicando las etapas, y también Ky estacional | Con el mismo estrés, el Ky por etapa pesa más la floración que el estacional. No medida la diferencia. |
| Cultivos | 4 (`maiz`, `frijol`, `tomate`, `cafe`) | 13 | Ver los parámetros de maíz y frijol abajo. |

**Parámetros de maíz, frijol y tomate en los dos catálogos** (`modelos.dart` frente a `web/data/crops.json`):

| Parámetro | Maíz app | Maíz modelo | Frijol app | Frijol modelo | Tomate app | Tomate modelo |
|---|---|---|---|---|---|---|
| Kc inicial / medio / final | 0.30 / 1.20 / 0.35 | 0.30 / 1.20 / 0.35 | 0.40 / 1.15 / 0.35 | 0.40 / 1.15 / 0.35 | 0.60 / 1.15 / 0.80 | 0.60 / 1.15 / 0.80 |
| Raíz máxima (m) | 1.0 | 1.2 | 0.6 | 0.7 | 1.0 | 1.0 |
| p | 0.55 | 0.55 | 0.45 | 0.45 | 0.40 | 0.40 |
| Ky estacional | 1.25 | 1.25 | 1.15 | 1.15 | 1.05 | 1.05 |
| Ky por etapa | No existe | 0.4 / 1.5 / 0.5 / 0.2 | No existe | 0.2 / 1.1 / 0.75 / 0.2 | No existe | No existe |
| Etapas (inicial, desarrollo, media, final) | proporción 20 / 35 / 40 / 30 del ciclo elegido | 20 / 35 / 40 / 25 días a temperatura de referencia | proporción 15 / 25 / 35 / 20 | 12 / 18 / 22 / 15 días | proporción 30 / 40 / 45 / 30 | 30 / 40 / 40 / 25 días |
| Ciclos | 90 y 120 días | 120 días de referencia (grados-día) | 67, 80 y 90 días | 67 días de referencia | 120 y 145 días | 135 días de referencia |
| Raíz mínima al sembrar | 0.20 m | 0.15 m | 0.20 m | 0.15 m | 0.20 m | 0.15 m |

Los parámetros de Kc, p y Ky de maíz, frijol y tomate son iguales; cambian la raíz máxima de maíz (1.0 frente a 1.2 m) y de frijol (0.6 frente a 0.7 m), la forma de repartir las etapas y la raíz inicial.

## 3. Salidas: lo que muestra la app y lo que mide el modelo

| Salida de la app (`Recomendacion`) | Medida del modelo | Cómo se corresponden |
|---|---|---|
| `factorRendimiento` (FAO-33, de la siembra **hasta hoy**) | `relYield` del simulador (por etapas) | Misma idea, distinta ventana: la app lo calcula con los días que ya pasaron; el modelo lo calcula con el ciclo completo. En el 50 % del ciclo, el de la app mide el pasado. |
| `diasACosecha` (`ciclo − días desde siembra`) | Si el ciclo termina dentro del año agrícola (ejecutable) y los días del ciclo por grados-día | La app resta días fijos; el modelo dice si el ciclo cabe en el año. |
| `diasEstres` (días de los últimos 7 con Ks < 1) | Días con Ks < 1 del simulador (`ksFlowerMain` es el Ks medio de la floración) | Mismo criterio de Ks < 1; el modelo lo promedia en floración, la app lo cuenta en la última semana. |
| `riegoSugerido` y `riegosSugeridos` (agotamiento menos la mitad de RAW; solo con riego) | No existe como salida del emulador (el modelo decide riego en `none`/`limited`/`full`) | La red alineada es a secano y no lo predice. |
| `nivel` (bien, atención, estrés), `reserva`, `agotamiento`, `lluviaSemana`, `necesidadSemana` | Sin equivalente directo | Se calculan en la app sin red. |

**Lo que la app no puede mostrar hoy y una red podría agregar:** un valor hacia adelante. La app dice cómo le fue a la plantación hasta hoy; no dice cuántos días de estrés vendrán ni cuánto rendirá al cosechar. La red alineada predice tres valores a partir de lo que la app tiene: `factorFinal` (el `factorRendimiento` al cosechar), `estres7` y `estres14` (días con Ks < 1 en los 7 y 14 días siguientes).

**Lo que se midió sobre esa interfaz** (todo de `web/data/app_eval.json`; detalle en la sección "Red alineada con la app" de `proyecto/resultados-modelo-keu.md`). Prueba = años de siembra 2019–2024, 201600 filas; red con retropropagación, semillas 17, 29 y 43; referencia = lo que la app muestra hoy:

| Objetivo | Medida | Red (3 semillas) | ELM (3 semillas) | Lo que muestra la app |
|---|---|---|---|---|
| `factorFinal` | MAE | 0.0226 / 0.0210 / 0.0238 | 0.0313 / 0.0315 / 0.0312 | 0.0254 |
| `factorFinal` | R² | 0.590 / 0.656 / 0.599 | 0.500 / 0.493 / 0.494 | 0.160 |
| `estres7` | MAE (días) | 0.198 / 0.177 / 0.205 | 0.420 / 0.443 / 0.434 | 0.268 |
| `estres7` | F1 de "habrá estrés la próxima semana" | 0.857 / 0.866 / 0.857 | 0.652 / 0.622 / 0.646 | 0.693 |
| `estres14` | MAE (días) | 0.539 / 0.539 / 0.571 | 0.982 / 1.006 / 0.987 | 0.679 |
| `estres14` | F1 | 0.726 / 0.717 / 0.690 | 0.500 / 0.482 / 0.502 | 0.622 |

**Lectura:** la red con retropropagación mejora a lo que la app muestra hoy en los tres valores y en las tres semillas, pero en `factorFinal` la mejora es chica y en maíz y frijol el MAE de la red es mayor que el de la app (ver la sección de resultados); el ELM no la mejora en MAE. Con estos números, **el valor hacia adelante que más justifica enchufar la red es el aviso de estrés de los próximos 7 y 14 días**, no el rendimiento final. Con un aviso de 14 días la red gana recall (0.91–0.94 frente a 0.53) y pierde precisión (0.55–0.60 frente a 0.76). El juez es el motor de la app y no el campo, y la lluvia es la de POWER; estos números no están validados en campo.

## 4. Interfaz para enchufar la red en `recomendar`

**Entradas** (40, en este orden; los nombres y el orden están en `web/data/app_mlp.json`, campo `inputNames`, y en `web/js/model/appInputs.js`, `APP_INPUT_NAMES`). Todo se calcula con lo que `recomendar` ya tiene: `parcela`, `plantacion`, los `dias` de `prepararClima`, los `estados` de `simularBalance` y `hoy`.

| # | Nombre | Unidad y definición |
|---|---|---|
| 0–2 | `lat`, `lon`, `cellElevation` | grados; grados; m (de la celda de POWER; si falta, 500 como en `prepararClima`) |
| 3–6 | `sowSin`, `sowCos`, `todaySin`, `todayCos` | sen y cos de 2π·día del año/365 de la siembra y de hoy |
| 7–9 | `crop_maiz`, `crop_frijol`, `crop_tomate` | 1 o 0 |
| 10–13 | `cycleDays`, `fractionElapsed`, `daysToHarvest`, `soilAvailableWater` | días; días desde siembra / ciclo; ciclo − días desde siembra; mm/m (100, 150 o 180) |
| 14–17 | `kcMid`, `rootDepth`, `p`, `ky` | del catálogo de la app (raíz máxima en m) |
| 18–20 | `reserve`, `depletionOverTaw`, `ks` | `actual.reserva`, `actual.agotamiento / actual.aguaTotal`, `actual.ks` |
| 21–24 | `stage_inicial`, `stage_desarrollo`, `stage_media`, `stage_finalCiclo` | 1 o 0 según `actual.etapa` |
| 25–27 | `factorSoFar`, `stressDays7`, `stressDaysSinceSowing` | `factorRendimiento(estados, ky)`; `diasEstres`; días con Ks < 1 desde la siembra |
| 28–31 | `rain7`, `rain14`, `rain28`, `rainSinceSowing` | mm, suma de `dias[].lluvia` |
| 32–35 | `et0Sum7`, `et0Sum14`, `et0Sum28`, `et0SumSinceSowing` | mm, suma de `dias[].et0` (con la regla de huecos de la app) |
| 36 | `longestDrySpell28` | días seguidos con lluvia < 1 mm en los últimos 28 días |
| 37–38 | `tmaxMean14`, `tminMean14` | °C, promedio de los días observados de los últimos 14 (en la app: de `clima`, ignorando los nulos) |
| 39 | `cropNeed7` | mm, suma de `estados[].etc` de los últimos 7 días (igual que `necesidadSemana`) |

**Estandarización:** `x_std = (x − mean) / std` por entrada con `mean` y `std` de `app_mlp.json` (si `std` es 0 se usa 1). **Salidas** (3, en este orden): `factorFinal` (0 a 1), `estres7` (días, 0 a 7), `estres14` (días, 0 a 14); la salida es `red(x_std) · yStd + yMean`, y conviene recortarla a esos rangos.

**Formato de pesos (`web/data/app_mlp.json`):** `layers` es una lista de 4 capas, cada una con `W` (filas = neuronas de salida, columnas = entradas) y `b`; la arquitectura es 40 → 64 → 32 → 16 → 3 (`architecture`); ReLU en las tres capas ocultas y lineal en la última; `mean`, `std`, `yMean`, `yStd`, `inputNames`, `targetNames`. El pase hacia adelante es el mismo de `mlpPredict` de `web/js/model/emulator.js` (probado contra PyTorch a 1e-5 en `tests/app_mlp.test.mjs`) y se puede escribir en Dart sobre `List<double>` sin dependencias (no se escribió ni se probó en esta tarea).

**Dónde va en `recomendar`:** después de calcular `actual`, `semana`, `factorRendimiento` y `diasEstres`, y antes de construir `Recomendacion`. Con esos valores se arma el vector de 40 entradas y se corre la red. No cambia el tipo `Recomendacion`: los campos existentes se calculan igual. Dos usos posibles sin tocarlo: elevar `nivel` de `bien` a `atencion` cuando `estres7 ≥ 0.5`, y poner el valor hacia adelante en campos opcionales nuevos (`factorFinalEsperado`, `diasEstresProximos`), con valor nulo por omisión, que la pantalla `hoy.dart` muestra solo si existen. **Si no hay clima o la plantación es de café, la red no se llama** (`Recomendacion.vacia` o el flujo actual).

**Límites de la interfaz:** la red se entrenó con "hoy" entre el 20 % y el 80 % del ciclo, a secano y con los tres cultivos con Ky; fuera de eso (cosecha, café, riego) no está validada. Entrena con clima de POWER completo hasta hoy; en la app el último dato de POWER puede tener unos días de retraso y la regla de huecos de la app lo completa con el promedio de la ET₀ y lluvia 0: ese caso no se probó.
