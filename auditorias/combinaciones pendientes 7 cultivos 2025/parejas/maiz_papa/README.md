# Auditoría Maíz ↔ Papa · Chiquimula · 2025

**Direcciones evaluadas:** Maíz → Papa y Papa → Maíz. Entrega del 15 de noviembre de 2026, punto **14.8250, −89.5312**. Sucesiones estrictas, sin coexistencia y sin repeticiones. [Volver a la cobertura de los siete cultivos](../../README.md).

**Dictamen:** En la referencia, la dirección directa acumula menor déficit con 0 de las cuatro lluvias y la inversa con 4. Esto describe ese calendario y no una superioridad general. La adaptación al candidato cálido de Papa debe comprobarse antes de recomendar la sucesión. La compatibilidad sanitaria, el rendimiento y la rentabilidad permanecen sin validar. Esta entrega no incorpora un ensayo local específico de esta pareja; compara agua/calendario y conserva las condiciones documentadas por mecanismo.

## Alcance y parámetros

**168 calendarios**; **70 completos** en 2025 y **98 inconclusos**, conservados solo como fechas. Se ejecutaron **10,080 corridas** y **5,040 comparaciones pareadas**. Ambos sentidos tienen la misma cantidad de escenarios.

| Cultivo/producto | Identidad y familia | Kc inicial / medio / final | Raíz | p | Duraciones (días) |
|---|---|---:|---:|---:|---|
| Maíz | Zea mays L. · Poaceae | 0.3 / 1.2 / 0.35 | 1.0 m | 0.55 | 90, 125 |
| Papa | Solanum tuberosum L. · Solanaceae | 0.5 / 1.15 / 0.75 | 0.5 m | 0.35 | 115, 130 |

Los productos, etapas y notas se conservan en [parámetros](../../datos/cultivos/parametros_auditados.json). [FAO-56, tablas 11/12](https://www.fao.org/4/x0490e/x0490e0b.htm) y [tabla 22](https://www.fao.org/4/x0490e/x0490e0e.htm) son referencias sin calibración de parcela. Kc inicial puede proceder del grupo. El cambio de familia no genera premio, veto ni crédito de nitrógeno.

## Caso de referencia

Inicio común **1 de marzo de 2025**, duraciones de referencia Maíz 90 días; Papa 115 días, **14 días completos** entre cultivos. Perfil de referencia, escorrentía supuesta 15%, reserva al 1 de enero 25%. El agua se conserva entre cultivos.

| Dirección | Primer cultivo | Segundo cultivo |
|---|---|---|
| Maíz → Papa | 2025-03-01 a 2025-05-29 | 2025-06-13 a 2025-10-05 |
| Papa → Maíz | 2025-03-01 a 2025-06-23 | 2025-07-08 a 2025-10-05 |

| Lluvia | Déficit directo secano (mm) | Déficit inverso secano (mm) | Días Ks<0.95 directo/inverso | Riego idealizado directo/inverso (mm netos) |
|---|---:|---:|---:|---:|
| IMERG V07 Late | 176.42 | 163.71 | 71 / 69 | 280 / 280 |
| CHIRPS v2 | 352.80 | 327.30 | 130 / 95 | 420 / 380 |
| ERA5 | 391.39 | 353.69 | 133 / 98 | 460 / 420 |
| POWER | 372.47 | 328.37 | 137 / 117 | 420 / 400 |

La última columna corresponde a corridas separadas con pulsos de 20 mm netos al superar RAW y suministro ilimitado; no es una dosis recomendada o agua confirmada. Ver el déficit residual de cada corrida en [referencia](referencia.csv). Un déficit de ET menor no equivale a mayor cosecha o calidad comercial.

![Comparación de referencia](comparacion_hidrica.png)

En los **2,520 pares de secano** de toda la malla, la inversa tiene mayor déficit en **1,856**, menor en **664** y diferencia absoluta de hasta 0.0001 mm en **0**. Estos conteos son escenarios diseñados, sin probabilidad de éxito ni representatividad estadística de fincas.

## Temperatura, establecimiento y operaciones

| Dirección y cultivo | Producto térmico | Media del período (°C) | Días media>24 / total | Días Tmax>30 / total |
|---|---|---:|---:|---:|
| Directa · Maíz | POWER | 25.55 | 64 / 90 | 73 / 90 |
| Directa · Maíz | ERA5 | 28.65 | 88 / 90 | 81 / 90 |
| Directa · Papa | POWER | 24.17 | 58 / 115 | 29 / 115 |
| Directa · Papa | ERA5 | 27.49 | 115 / 115 | 110 / 115 |
| Inversa · Papa | POWER | 25.34 | 81 / 115 | 79 / 115 |
| Inversa · Papa | ERA5 | 28.57 | 113 / 115 | 104 / 115 |
| Inversa · Maíz | POWER | 24.30 | 51 / 90 | 29 / 90 |
| Inversa · Maíz | ERA5 | 27.52 | 90 / 90 | 87 / 90 |

POWER T2M es media diaria del producto regional. ERA5 usa semisuma Tmax/Tmin, una aproximación diferente. Tmax no equivale a temperatura media ni de órgano. Los umbrales son indicadores descriptivos; no son una función de daño. El fotoperíodo está en [exposición de referencia](exposicion_referencia.csv); es duración astronómica del día, sin respuesta del cultivo ni nubosidad.

Lluvia durante los intervalos de retiro/preparación del caso de referencia:

| Dirección | Intervalo completo | Lluvia | Total (mm) |
|---|---|---|---:|
| Directa | 2025-05-30 a 2025-06-12 | IMERG V07 Late | 276.1 |
| Directa | 2025-05-30 a 2025-06-12 | CHIRPS v2 | 138.0 |
| Directa | 2025-05-30 a 2025-06-12 | ERA5 | 148.8 |
| Directa | 2025-05-30 a 2025-06-12 | POWER | 106.5 |
| Inversa | 2025-06-24 a 2025-07-07 | IMERG V07 Late | 235.2 |
| Inversa | 2025-06-24 a 2025-07-07 | CHIRPS v2 | 130.7 |
| Inversa | 2025-06-24 a 2025-07-07 | ERA5 | 93.2 |
| Inversa | 2025-06-24 a 2025-07-07 | POWER | 81.0 |

Reservar días no demuestra que permitan secado, curado, retiro o entrada de maquinaria. La lluvia acumulada tampoco demuestra anegamiento. El motor drena instantáneamente el exceso; es necesario observar drenaje y humedad reales.

## Condiciones documentales y sanitarias

- **Maíz:** 90 días es sensibilidad de ciclo corto con etapas prorrateadas; madurez no garantiza grano seco ni retiro. Si el cultivo siguiente se establece antes de retirar el maíz, corresponde evaluar relevo o coexistencia, fuera de este motor.
- **Papa:** Referencia de mejor producción con media diaria de 18–20 °C. La máxima del aire y temperatura del tubérculo son variables distintas. Se requiere verificar material adaptado al candidato cálido y sanidad del tubérculo-semilla. No se incorporan pérdidas por calor o pudrición al balance de agua.

**Sanidad sin resolver para esta pareja.** La revisión selectiva no incorpora una alerta de hospedaje compartido para ambos cultivos en su regla actual. Eso no acredita ausencia de organismos compartidos, inocuidad ni ruptura sanitaria. Ajonjolí y maíz no se clasifican como no hospedantes por falta de una alerta. Hace falta diagnóstico dirigido y comprobar el material.

Fuentes primarias por cultivo y alcance:

- Maíz: [fuente 1](https://www.icta.gob.gt/publicaciones/Maiz/Recomendaciones%20tecnicas%20para%20el%20cultivo%20de%20maiz%20en%20el%20oriente%20de%20Guatemala%202015.pdf). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).
- Papa: [fuente 1](https://www.icta.gob.gt/publicaciones/Papa/manualpapaconsumo2013.pdf), [fuente 2](https://ipm.ucanr.edu/agriculture/potato/nematodes/). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).

Los documentos de otra región, las fichas comerciales y la evidencia de grupo conservan sus límites. No se atribuye a esta pareja un efecto experimental no leído, una bonificación de N o un saneamiento automático. La [evidencia común](../../fuentes/criterios_7_cultivos.json) conserva antecedentes y vacíos.

## Archivos y reproducción

- [Resumen](resumen.json), [calendarios CSV](calendarios.csv) y [JSON](calendarios.json), incluidos los inconclusos.
- [Todas las corridas CSV.gz](escenarios.csv.gz) y [JSON.gz](escenarios.json.gz); este último conserva segmentos por cultivo.
- [Comparaciones pareadas](comparacion_pareada.csv.gz): diferencia de déficit inverso menos directo.
- [Referencia CSV](referencia.csv) y [JSON](referencia.json): 16 corridas, dos direcciones × cuatro lluvias × secano/riego.
- [Balances de referencia](balances_referencia.csv.gz): 5,840 registros diarios, con reserva y residuo de balance.
- [Exposición de todos los calendarios completos](exposicion_climatica.csv.gz), [exposición de referencia](exposicion_referencia.csv) e [intervalos](intervalos_referencia.csv).

La metodología, código, versiones, datos y reproducción están en el [README común](../../README.md). Cada calendario completo tiene **144 casos**: cuatro lluvias, tres hipótesis de suelo/raíces, tres escorrentías, dos reservas iniciales y secano/riego. Las fechas son supuestas; almácigo externo, cosecha y liberación real se deben comprobar. Los ciclos fuera de 2025 no se completan con lluvia cero.

El modelo no altera crecimiento o cosecha por estrés, temperatura o fotoperíodo. Tampoco calcula patógenos, residuos, nutrientes, rendimiento o ingresos. Estos resultados son sintéticos, sin etiquetas observadas de éxito/fracaso. El agua contablemente conservada y la equivalencia entre implementaciones no sustituyen validación de campo.
