# Auditoría papa → cebolla · Chiquimula · 2025

**Fecha:** 15 de noviembre de 2026. Alternativa pendiente de la lista del usuario: **Papa → Cebolla**, con **Cebolla → Papa** como comparador. Se conserva el candidato **14.8250, −89.5312**, sus datos abiertos de 2025 y el motor hídrico publicado. Es una evaluación retrospectiva exploratoria de calendario, agua y exposición climática; requiere comprobación de finca.

**Dictamen:** La temperatura es una restricción que debe resolverse antes de recomendar papa en este candidato de 373 m. El caso de marzo supera ampliamente la referencia térmica del ICTA. La comparación hídrica tampoco favorece al mismo orden con todas las lluvias. Se mantienen variedad, sanidad, fotoperíodo de cebolla, riego y mercado como condiciones pendientes.

Se evaluaron **168 calendarios**: **32** completos dentro de 2025 y **136** inconclusos, conservados solo como fechas. Los completos generaron **4,608 corridas hídricas** y **2,304 comparaciones pareadas**, incluyendo ambos órdenes. La aprobación térmica, sanitaria, comercial y de rendimiento permanece pendiente.

## Evidencia y parámetros

El [registro de evidencia](fuentes/evidencia_bibliografica.json) declara fuente, localizador, nivel de lectura y límites. El [registro de acceso](fuentes/acceso_documentos.json) conserva descargas, errores y huellas de los documentos consultados.

- **Papa y temperatura.** El [manual ICTA para consumo de 2013](https://www.icta.gob.gt/publicaciones/Papa/manualpapaconsumo2013.pdf), página impresa 4, sitúa la mejor producción con media diaria de 18–20 °C. Se descargó el original y se inspeccionó la página renderizada. Es una referencia; la media regional, una máxima diaria y la temperatura del tubérculo son variables distintas. No se calcula pérdida de cosecha a partir de una máxima aislada.
- **Cebolla y fotoperíodo.** El [artículo original de Tanaka, Iritani y Araki, 2020](https://www.jstage.jst.go.jp/article/hortj/89/4/89_UTD-155/_html/-char/en) estudia siembra, trasplante y grupos varietales en Hokkaido. Confirma la importancia del material y del largo del día, sin validar una variedad para Guatemala. En nuestro calendario de cebolla después de papa la duración astronómica del día varía aproximadamente entre **11.16 y 12.84 horas**. Debe contrastarse con la variedad; el modelo no simula bulbificación.
- **Sanidad.** Las guías originales UC IPM de [papa](https://ipm.ucanr.edu/agriculture/potato/nematodes/) y [cebolla/ajo](https://ipm.ucanr.edu/agriculture/onion-and-garlic/nematodes/) documentan *Meloidogyne incognita*, *M. hapla* y *M. chitwoodi*. Justifican una alerta condicional; no prueban infección local ni susceptibilidad de cada material. El cambio de familia no acredita ruptura sanitaria.

Las identidades y familias se reconsultaron en POWO-Kew, con enlaces en los [parámetros auditados](datos/cultivos/parametros_auditados.json). La familia botánica se usa como descriptor, sin premio o veto de compatibilidad.

| Cultivo | Especie y familia | Kc inicial / medio / final | Raíz de referencia | p | Duraciones |
|---|---|---:|---:|---:|---|
| Papa | Solanum tuberosum L. · Solanaceae | 0.50 / 1.15 / 0.75 | 0.50 m | 0.35 | 115, 130 días |
| Cebolla | Allium cepa L. · Amaryllidaceae | 0.70 / 1.05 / 0.75 | 0.50 m | 0.30 | 150, 210 días |

Kc y etapas proceden de [FAO-56, tablas 11/12](https://www.fao.org/4/x0490e/x0490e0b.htm); raíces y p de la [tabla 22](https://www.fao.org/4/x0490e/x0490e0e.htm). Los Kc iniciales se heredan del grupo; las raíces son hipótesis escogidas dentro del rango FAO. No se ajustó Kc al clima ni se midieron raíces. Se usan las dos referencias FAO de papa de 115/130 días y cebolla de bulbo seco de 150/210 días. No se sustituyen por cebolla de verdeo, producción de semilla o papa temprana sin cambiar la ficha. Todas son ocupaciones de campo supuestas; variedad, madurez y retiro siguen sin confirmar.

## Sitio, fechas y continuidad

El punto tiene **373 m de elevación DSM** y pendiente local aproximada de 2.6%. SoilGrids estima **130.7 mm de agua disponible en 0–100 cm** y pH superficial aproximado de 7. Se conservan los mismos originales NASA POWER, IMERG V07 Late, CHIRPS v2, ERA5, SoilGrids, MAGA, JAXA y WorldCover de la auditoría anterior. Las API no se consultaron de nuevo. Son estimaciones espaciales, sin delimitación de finca ni medición de temperatura, nutrientes, sanidad o drenaje.

Se conserva la meteorología POWER para ET0 FAO-56, con presión estimada a 373 m. La temperatura regional no se corrige arbitrariamente por altitud. IMERG es Late, no Final. GWET, humedad volumétrica ERA5 y agua disponible simulada no se usan como magnitudes equivalentes.

Se mantienen los inicios del 1/15 de mayo y 1/15 de junio de las auditorías anteriores. Se añaden **15 de enero y 1 de marzo** para estudiar ciclos largos completos y **1 de septiembre** para hacer explícitos calendarios sin cobertura completa. No son ventanas recomendadas. Los intervalos son de 7/14/21 días completos; incluyen retiro, preparación y curado cuando corresponda, sin garantizar que ocurran. El almácigo se supone externo: su tiempo, agua y superficie no se modelan. Si ocupa el mismo sublote, hay que reconstruir el calendario.

| Inicio supuesto | Calendarios completos por dirección |
|---|---:|
| 2025-01-15 | 10 |
| 2025-03-01 | 6 |
| 2025-05-01 | 0 |
| 2025-05-15 | 0 |
| 2025-06-01 | 0 |
| 2025-06-15 | 0 |
| 2025-09-01 | 0 |

Que un ciclo termine antes del 31 de diciembre solo confirma cobertura temporal de los datos. No demuestra madurez comercial, secado/curado o liberación del suelo. Los calendarios que llegan a 2026 no se rellenaron con ceros ni con clima extrapolado.

![Calendarios y cobertura](resultados/calendarios_y_cobertura.png)

## Caso de referencia y comparación de agua

Inicio **2025-03-01**, Papa 115 días, Cebolla 150 días, intervalo de **14 días completos**. Secano, perfil de referencia, escorrentía supuesta 15%, reserva inicial al 1 de enero 25%.

| Orden | Primer cultivo | Segundo cultivo |
|---|---|---|
| Papa → Cebolla | 2025-03-01 a 2025-06-23 | 2025-07-08 a 2025-12-04 |
| Cebolla → Papa | 2025-03-01 a 2025-07-28 | 2025-08-12 a 2025-12-04 |

Cada par tiene el mismo inicio, número de días con cultivo, intervalo, fecha final e hipótesis de suelo/agua; cambia el orden y la exposición estacional. No se reinicia el agua al cambiar de cultivo.

| Lluvia | Déficit directo (mm) | Déficit inverso (mm) | Días Ks<0.95 directo/inverso | Riego idealizado directo/inverso (mm netos) |
|---|---:|---:|---:|---:|
| IMERG V07 Late | 258.61 | 253.24 | 136 / 113 | 440 / 460 |
| CHIRPS v2 | 427.96 | 445.23 | 168 / 143 | 580 / 580 |
| ERA5 | 450.20 | 470.41 | 178 / 148 | 560 / 580 |
| POWER | 436.47 | 390.46 | 210 / 143 | 520 / 500 |

Las primeras columnas corresponden a secano. La última corresponde a corridas separadas de riego hipotético: pulsos de 20 mm netos al superar RAW, suministro ilimitado. En la referencia esa regla lleva el déficit a cero; no acredita caudal, eficiencia, calidad de agua, presupuesto ni viabilidad operativa. No es una dosis recomendada.

En la referencia, papa→cebolla tiene menor déficit con CHIRPS y ERA5, mientras cebolla→papa tiene menor déficit con IMERG y POWER. La respuesta depende del producto de lluvia y del calendario. El déficit elevado muestra limitación de agua bajo secano; corregirla con riego idealizado no resuelve la adaptación térmica de la papa.

![Comparación hídrica condicional](resultados/comparacion_hidrica.png)

En toda la malla de secano hay **1,152 pares**: la inversa acumula mayor déficit en **767**, menor en **385** y diferencia absoluta de hasta 0.0001 mm en **0**. Son conteos de supuestos diseñados; no son probabilidades de éxito ni frecuencias de campo. No compararlos como un ranking de rentabilidad o rendimiento entre cultivos distintos.

## Exposición térmica y adaptación

Se calculan temperatura durante cada cultivo y exposiciones diarias descriptivas. POWER aporta T2M media diaria; para ERA5 se usa la **semisuma de Tmax/Tmin**, una aproximación diferente de la media diaria. Las máximas se conservan separadas. Ninguno de estos datos es temperatura medida en la planta o el tubérculo.

| Orden y cultivo de referencia | Producto | Temperatura media del período (°C) | Días media>24 °C / total | Días Tmax>30 °C / total |
|---|---|---:|---:|---:|
| Directa · Papa | POWER | 25.34 | 81 / 115 | 79 / 115 |
| Directa · Papa | ERA5 | 28.57 | 113 / 115 | 104 / 115 |
| Directa · Cebolla | POWER | 23.55 | 55 / 150 | 33 / 150 |
| Directa · Cebolla | ERA5 | 26.78 | 143 / 150 | 113 / 150 |
| Inversa · Cebolla | POWER | 24.98 | 94 / 150 | 80 / 150 |
| Inversa · Cebolla | ERA5 | 28.27 | 148 / 150 | 138 / 150 |
| Inversa · Papa | POWER | 23.42 | 39 / 115 | 29 / 115 |
| Inversa · Papa | ERA5 | 26.64 | 108 / 115 | 80 / 115 |

Los umbrales 18/20/24/30/35 °C publicados en la tabla de exposiciones permiten examinar las series; no constituyen una función de daño calibrada. Un día con Tmax>30 no equivale a media diaria>30 ni a determinada pérdida de rendimiento. La duración astronómica del día se calcula con la geometría solar FAO-56; no equivale a horas de sol sin nubes.

![Exposición térmica del candidato](resultados/exposicion_termica.png)

**El balance hídrico sigue siendo condicional:** temperatura y fotoperíodo no modifican la duración, Kc, crecimiento o rendimiento del cultivo en este motor. Se muestran las alertas para evitar interpretar déficit bajo como adaptación aprobada. No se declara una variedad inviable por un umbral aislado, ni se selecciona el producto térmico más conveniente.

## Método y controles

Por calendario completo se corren **144 combinaciones**: cuatro lluvias × tres hipótesis de suelo/raíces × tres escorrentías (0/15/30%) × dos reservas iniciales (25/75%) × secano/riego. Los casos de suelo son referencia, límite de raíces de **30 cm** y almacenamiento 25% menor. El límite de 30 cm hace visible una profundidad menor que la referencia FAO; son sensibilidades, no tres suelos muestreados.

El balance de cinco capas conserva el agua desde el 1 de enero. Usa Kc único, crecimiento radical por calendario, evaporación de suelo sin cultivo Kc=0.20 y drenaje instantáneo del exceso. No calcula anegamiento, flujo lateral, nivel freático, descomposición de residuos, patógenos, nutrientes, rendimiento o ingresos. El código es el motor del commit `0633f2f2d47562a4860c2904ef23049dd35bd9fa`; el nuevo script añade cultivos, calendarios y exposiciones sin cambiar su contabilidad.

Se procesaron **1,681,920 pasos diarios**; máximo residuo numérico **5.68e-14 mm**. Las **10 pruebas** comprueban parámetros, intervalos, pares, rechazo de ciclos incompletos, conservación sin flujos, ausencia de ET sin agua, drenaje del exceso, geometría solar, distinción media/máxima y reproducción de cuatro lluvias con dos modos de riego del caso previamente publicado. El error pequeño demuestra contabilidad; la exactitud agronómica requiere observaciones de campo.

## Archivos y reproducción

| Archivo | Contenido |
|---|---|
| [configuracion.json](configuracion.json) | Cultivos, fechas, intervalos, escenarios y referencia. |
| [Parámetros](datos/cultivos/parametros_auditados.json) | Producto, taxonomía, Kc, raíces, etapas y supuestos. |
| [Calendarios CSV](resultados/calendarios_evaluados.csv) / [JSON](resultados/calendarios_evaluados.json) | Todos los calendarios, incluidos los inconclusos. |
| [Resultados CSV.gz](resultados/resultados_escenarios.csv.gz) / [JSON.gz](resultados/resultados_escenarios.json.gz) | Todas las corridas; el JSON conserva los segmentos de cada cultivo. |
| [Comparaciones pareadas CSV.gz](resultados/comparacion_pareada.csv.gz) | Diferencia de déficit: inverso menos directo. |
| [Referencia CSV](resultados/comparacion_referencia.csv) / [JSON](resultados/comparacion_referencia.json) | 48 corridas: ambos órdenes, tres intervalos, cuatro lluvias y secano/riego. |
| [Balances diarios CSV.gz](resultados/balances_referencia.csv.gz) | 17,520 filas de las 48 corridas de referencia. |
| [Exposición climática CSV](resultados/exposicion_climatica.csv) | Temperaturas, duración astronómica del día y lluvia por cultivo; solo calendarios completos. |
| [Resumen](resultados/resumen_ejecutivo.json) / [Método](resultados/metodo_y_validacion.json) | Conteos, resultados, límites y hashes de entradas/código. |
| [Evidencia](fuentes/evidencia_bibliografica.json) / [Acceso](fuentes/acceso_documentos.json) | Procedencia y alcance de lectura. Los PDF consultados no se republican. |
| [Control](control_paquete.json) / [Inventario](inventario.json) | Pruebas, integridad, SHA-256 y SHA de objetos Git. |

En el resultado agregado, `P_mm` es la lluvia de todo el año; en cada segmento, `lluvia_mm` corresponde al cultivo. `deficit_ET_mm` acumula ETc−ETa solo durante los cultivos. Ks<0.95 es un indicador del modelo sin traducción validada a daño. Los datos de estas corridas son sintéticos, sin etiquetas observadas de éxito/fracaso para entrenar una red neuronal.

Con Python 3.12, desde esta carpeta:

```sh
python -m venv .venv
# Activar el entorno según el sistema operativo.
python -m pip install -r requirements-simulacion.txt
python scripts/auditar_hortalizas_2025.py
python scripts/verificar_paquete.py
```

La simulación usa los originales incluidos, sin credenciales ni nuevas descargas. `tmp/sim-deps` del workspace se incorpora si existe; en una copia independiente se usan las dependencias fijadas. Las fechas de ejecución y el inventario pueden cambiar. Los scripts de adquisición se conservan como referencia y su ejecución podría descargar revisiones posteriores.

## Antes de recomendar

Confirmar variedad/producto, fechas reales de almácigo/trasplante/cosecha/retiro y disponibilidad del sublote. Medir temperatura y humedad, profundidad física, infiltración y drenaje; hacer análisis de suelo y diagnóstico sanitario dirigido. Verificar agua entregable, trabajo, semilla o plantín sano, manejo de residuos, comprador, calidad y costos. Si se propone otra región más fresca o un sistema protegido, corresponde una nueva parcela y otra auditoría, sin cambiar silenciosamente este punto.
