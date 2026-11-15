# Resultados · modelo-keu (simulador FAO-56 + emulador)

Actualizado el 14 de noviembre de 2026 (artefactos generados el 2026-11-15 UTC con el simulador del commit `b8179a4`). Rama `modelo-keu`. Los números salen de `web/data/emulator_eval.json`, `web/data/emulator_mlp.json` y `web/data/referee_aquacrop.json`, que se regeneran con los scripts de `scripts/emulator/` y `scripts/referee/`. Las columnas "antes" salen de la versión anterior de esos mismos archivos (commit `9d5b5f9`).

## Qué es este modelo

1. **Simulador** (`web/js/model/`, JavaScript sin dependencias): balance diario de agua en raíces FAO-56, ET₀ Penman-Monteith, etapas del cultivo por grados-día, respuesta del rendimiento al agua FAO-33 (Ky por etapa en maíz y frijol, Ky estacional en los demás) y rotaciones por año agrícola (abril–marzo). Clima: NASA POWER (temperatura, humedad, radiación, viento) y lluvia ERA5 de Copernicus tomada por Open-Meteo.
2. **Emulador**: dos redes que aprenden a imitar al simulador a partir de 25 entradas (clima del año, ventana de floración del maíz, suelo, pendiente, riego, rotación y desfase de siembra) y predicen 3 salidas:
   - **Red embudo** 25→64→32→16→3, entrenada con backpropagation en PyTorch.
   - **ELM** (Extreme Learning Machine), entrenada **sin backpropagation**: capa oculta aleatoria fija y una sola solución de mínimos cuadrados. Se puede entrenar en el navegador.
3. **Página** `web/emulator.html`: comparación red embudo vs ELM, mapa del Corredor Seco y prueba de fecha de siembra confirmada con el simulador.

El emulador **imita al simulador; no predice cosechas reales**.

## Qué cambió en el simulador desde el reporte anterior

1. **Reserva de agua del subsuelo.** Al crecer las raíces ya no aparece agua nueva a capacidad de campo (commit `4ea12c1`).
2. **Ky por etapa** (vegetativa, floración, formación, maduración) para maíz y frijol, combinadas multiplicando las fracciones de rendimiento (commit `df4da88`). Sorgo, sandía y tomate siguen con el Ky estacional porque no se pudo verificar su Ky por etapa.
3. **Suelo real en los pilotos** (SoilGrids) y lluvia comparada con IMERG y CHIRPS. El modelo sigue usando ERA5 (ver limitaciones).
4. **Corrección del número de curva** del grupo hidrológico D (clase `clay`) con residuo: 85 y no 87 (TR-55, cuadro 2-2b). Cambia un poco las corridas con `clay` y residuo.
5. Un solo lugar para calcular la ventana de floración (sin cambio numérico: diferencia 0 en 360 valores comprobados) y la fuente del Ky por etapa del frijol ahora cita solo el cuadro donde se verificó.

Todos los archivos derivados se regeneraron una vez con este modelo. Mismo diseño de muestreo, mismas semillas, mismas divisiones, mismas 25 entradas y 3 salidas, mismos hiperparámetros.

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
| Red embudo (4,323 parámetros) | 0.867 / 0.801 / 0.983 | **0.815 / 0.705 / 0.976** | 0.884 / 0.834 / 0.990 |
| ELM, 1,500 neuronas (43,500 parámetros) | 0.808 / 0.724 / 0.979 | 0.715 / 0.550 / 0.973 | 0.845 / 0.769 / 0.985 |
| ELM del navegador, 600 neuronas | 0.755 / 0.628 / 0.965 | 0.693 / 0.450 / 0.956 | 0.768 / 0.663 / 0.974 |
| Línea base (promedio por manejo, sin clima) | 0.251 / 0.137 / 0.490 | 0.189 / 0.036 / 0.492 | 0.218 / 0.129 / 0.519 |

**Antes → después** (R² en años nuevos, índice de agua / agua en floración):

| Modelo | Antes (simulador anterior) | Después (modelo final) |
|---|---|---|
| Red embudo | 0.847 / 0.665 | 0.815 / 0.705 |
| ELM, 1,500 neuronas | 0.759 / 0.514 | 0.715 / 0.550 |
| ELM del navegador | 0.734 / 0.349 | 0.693 / 0.450 |

- **El índice de agua se volvió más difícil de imitar** en todos los modelos (la red embudo bajó de 0.847 a 0.815; la ELM, de 0.759 a 0.715). El simulador ahora tiene más variación entre años y más interacción entre etapas, y las redes la siguen peor. **El agua en floración mejoró** en todos (la red embudo subió de 0.665 a 0.705).
- La ELM se eligió con un barrido en validación (neuronas, escala de los pesos aleatorios y regularización). Ganó otra vez 1,500 neuronas, escala 0.1 y λ 0.1, en el borde de la rejilla. Con 5 semillas distintas el R² casi no cambia (desviación ≤ 0.006).
- **Meta pendiente:** el equipo fijó R² > 0.8 en años nuevos para el índice de agua y el agua en floración.
  - La red embudo ahora cumple el índice de agua (0.815) y no la floración (0.705).
  - La ELM no la cumple en ninguna de las dos (0.715 y 0.550).
  - La meta no se bajó ni se tocó la prueba: sigue marcada como pendiente de decisión.

## Medidas ligadas a la decisión

- **Detectar estrés en floración** (Ks < 0.7), en años nuevos. Ahora el 1.74 % de los casos tiene estrés real (antes 0.98 %: la tasa base casi se duplicó).

  | Modelo | Precisión | Recuperación | F1 (antes) | F1 (ahora) |
  |---|---|---|---|---|
  | Red embudo | 0.72 | 0.73 | 0.71 | 0.72 |
  | ELM | 0.75 | 0.59 | 0.57 | 0.66 |
  | ELM del navegador | 0.82 | 0.38 | 0.36 | 0.52 |

  La tasa base cambió, así que el F1 de antes y el de ahora no se miden sobre el mismo problema; la mejora es real pero no es una comparación exacta.

- **Diferencia "alternativa menos rotación actual"** (red embudo, años nuevos), antes → ahora:
  - índice de agua de "Proteger": error típico de ±4.5 → **±7.0 puntos** (peor), con el signo correcto en 77 % → **68 %** de los casos (peor);
  - índice de agua de "Extra (secano)": ±6.1 → ±7.3 puntos, signo correcto 91 % → 92 %;
  - índice de agua de "Extra (riego)": ±7.1 → ±7.8 puntos, signo correcto 91 % → 97 %;
  - suelo desnudo de "Proteger": ±2.7 → ±3.0 días (algo peor), signo correcto 93 % → 97 % (mejor).
- La diferencia de "Proteger" en el índice de agua es hoy la medida menos confiable del emulador: se equivoca de signo en 1 de cada 3 casos.
- El agua en floración del maíz es idéntica entre rotaciones por construcción (el maíz es el mismo), así que no sirve para compararlas.

## Costo

| | Red embudo | ELM (1,500) |
|---|---|---|
| Tiempo de entrenamiento | 9.9 s en GPU (RTX 4050, CUDA) · 4.9 s en CPU | 47 s en JavaScript puro (no comparable) |
| Memoria de entrenamiento (calculada) | 0.34 MB | 17.5 MB |
| Tiempo por predicción | 9.7 µs | 52.3 µs |
| Velocidad frente al simulador (321 µs por año) | 33× por predicción, 7.8× de punta a punta | 6× por predicción, 3.7× de punta a punta |

- Antes: 8.8 s GPU / 4.3 s CPU; ELM 51 s; 12.6 µs y 72.6 µs por predicción; simulador 384 µs por año. Los tiempos dependen de la máquina y de lo que estuviera corriendo: las diferencias pequeñas no son una mejora real. La memoria calculada no cambió.
- La GPU sigue siendo más lenta que la CPU para esta red tan pequeña. Los 4.9 s de CPU salen de una corrida aparte, con los mismos datos, cuyos pesos no se guardan.
- Para acercarse a la red embudo, la ELM necesita muchas más neuronas y unas 50 veces más memoria. Su ventaja es la sencillez: no usa backpropagation y la versión de 600 neuronas se entrena en el navegador en ~1 s.

## Juez independiente (AquaCrop)

AquaCrop-OSPy 3.1.0 en Chiquimula, mismo clima (ERA5 del bundle actual) y suelo seco al inicio, 2001–2024. **Una sola corrida de AquaCrop** se compara con cuatro versiones del simulador, así que solo cambia el modelo. Maíz sembrado el 20 de mayo (`maiz_0520`, suelo franco) y frijol el 1 de septiembre (`frijol_0901`).

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

Maíz sembrado el 20 de mayo, 2001–2024, clima propio de cada piloto (ERA5), tres suelos: franco, el suelo de SoilGrids del piloto (mismo θ en los dos modelos, CN del piloto en el simulador) y la clase `nearestTexture` del piloto, que es lo que recibiría el emulador.

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

(*) En las filas de arcilla y arena, AquaCrop usa **su propia** clase de suelo, que no tiene los mismos θ que la clase del simulador. Son comparaciones menos confiables; la de Chiquimula con arcilla (CV de AquaCrop de 1.15) no se debe leer como un fallo del simulador.

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

Maíz el 20 de mayo, suelo franco, modelo final, con cada producto de lluvia en el simulador **y** en AquaCrop. Solo los 22 años agrícolas completos en los tres productos (se excluyen 2019 y 2024, donde IMERG tiene huecos; no se rellenó ningún hueco). POWER no se usa nunca como lluvia. El modelo sigue usando ERA5: esto mide una brecha de información, no elige un producto.

| Producto | Lluvia media (mm por año agrícola) | Spearman simulador vs AquaCrop | Coincidencia 5 peores | CV del simulador | Años en 1.0 |
|---|---|---|---|---|---|
| ERA5 | 1,099 | 0.846 | 3 | 0.24 | 9 |
| IMERG | 1,164 | 0.602 | 4 | 0.21 | 6 |
| CHIRPS | 1,308 | 0.632 | 2 | 0.07 | 14 |

Acuerdo entre productos:

| Par | Spearman del simulador | Coincidencia 5 peores del simulador | Diferencia media de `relYield` | Spearman de AquaCrop |
|---|---|---|---|---|
| ERA5–IMERG | 0.633 | 3 | 0.099 | 0.673 |
| ERA5–CHIRPS | 0.658 | 3 | 0.087 | 0.735 |
| IMERG–CHIRPS | 0.831 | 3 | 0.096 | 0.791 |

Con otro producto de lluvia el orden de los años del simulador cambia mucho (Spearman de 0.63 a 0.83) y AquaCrop se mueve parecido: la elección de la lluvia pesa tanto como los cambios de modelo de esta ronda. Que ERA5 concuerde mejor con AquaCrop no prueba que ERA5 esté más cerca de la realidad: en cada fila los dos modelos reciben la misma lluvia.

## Limitaciones conocidas

- El modelo solo simula agua. No incluye plagas, fertilización, sombra, precios ni mano de obra.
- **Subsuelo corregido:** las raíces que crecen ya solo alcanzan el agua que la lluvia percoló hasta ahí (commit `4ea12c1`). Ya no "regala" agua.
- **Ky por etapa solo para maíz y frijol** (verificados en FAO-66 cap. 2 y en IAEA/FAO Water Reports 22). Sorgo, sandía y tomate usan el Ky estacional porque su Ky por etapa no se pudo verificar; ajonjolí y melón no tienen. La regla de multiplicar las fracciones de rendimiento de cada etapa está documentada en una fuente secundaria (ayuda de WEAP/SEI); no se pudo confirmar que sea la forma de Rao, Sarma y Chander (1988), así que no se cita como su fuente.
- **Lluvia:** el modelo usa ERA5 (Copernicus, por Open-Meteo). IMERG de NASA (ClimateSERV) termina el 1 de junio de 2024 y le falta el 30 de junio de 2019, así que cubre 22 de los 24 años agrícolas y no puede ser la única fuente; no se rellenó ningún hueco. CHIRPS está completo, pero no se cambió de fuente. En los 3 pilotos ERA5 es el producto más seco (promedio de los 22 años comunes: Chiquimula 1,099 / 1,164 / 1,308 mm por año agrícola con ERA5 / IMERG / CHIRPS; Jutiapa 1,084 / 1,313 / 1,303; San Martín 1,101 / 1,224 / 1,158). La lluvia de NASA POWER no se usa. Ver la sensibilidad a la lluvia arriba.
- **Suelo:** el simulador y el emulador usan 3 clases (arena, franco, arcilla). Los suelos de SoilGrids de los 3 pilotos solo entran en el simulador y en las pruebas de AquaCrop de arriba, no en el emulador. SoilGrids es una predicción global y necesita verificación local; en Jutiapa el agua disponible (0.056) es muy baja para una arcilla. `nearestTexture` se elige solo por el agua disponible y puede no coincidir con la clase más cercana en resultado (ver arriba).
- El número de curva del grupo hidrológico D con residuo es 85; la asignación de grupo según la textura es una aproximación.
- En cultivos traslapados (relevo) se usa el Kc mayor y la raíz mayor, sin competencia entre cultivos.
- Varios municipios comparten celda de clima. Salamá, Rabinal, Cubulco y San Martín Jilotepeque usan una celda a 1,516 m; los tres valles de Baja Verapaz están a unos 950 m.
- El índice de agua promedia los cultivos de comida de cada rotación, así que no es comparable entre rotaciones con cultivos distintos.
- Un cultivo que no termina su ciclo dentro del año agrícola cuenta como rendimiento 0.
- **Empeoró:** el R² del índice de agua en años nuevos (todos los modelos) y el error de la diferencia "Proteger" en el índice de agua (ver arriba).

## Cómo reproducir

```bash
npm test                                             # 166 pruebas (1 pendiente: la meta de R²)
node scripts/emulator/fetch_points.mjs               # descarga clima de los 20 puntos (NASA POWER + ERA5); ya hecho, usa cachés
node scripts/emulator/generate.mjs                   # genera los 50,000 ejemplos (guarda commit, lluvia y fecha)
python scripts/emulator/train_mlp.py --device cpu --out <tmp>/mlp_cpu.json                     # tiempo de CPU
python scripts/emulator/train_mlp.py --device cuda --cpu-timing <tmp>/mlp_cpu.json             # red embudo (pesos de esta corrida)
node --expose-gc scripts/emulator/evaluate.mjs       # barrido de la ELM y todas las métricas
# juez AquaCrop: ver scripts/referee/README.md
node scripts/referee/compare.mjs --aquacrop <resultados> --bundle web/data/snapshots/chiquimula.json --stage pre-subsoil=<d02febe> --stage subsoil=<4ea12c1> --stage stage-ky=<df4da88> --stage final=.
node scripts/referee/pilots.mjs prepare --dir <tmp>  # pilotos y sensibilidad a la lluvia (luego AquaCrop y `score`)
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
