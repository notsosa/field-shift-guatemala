# Auditoría Frijol ↔ Lechuga · Chiquimula · 2025

**Direcciones evaluadas:** Frijol → Lechuga y Lechuga → Frijol. Entrega del 15 de noviembre de 2026, punto **14.8250, −89.5312**. Sucesiones estrictas, sin coexistencia y sin repeticiones. [Volver a la cobertura de los siete cultivos](../../README.md).

**Dictamen:** En la referencia, la dirección directa acumula menor déficit con 3 de las cuatro lluvias y la inversa con 1. Esto describe ese calendario y no una superioridad general. La adaptación al candidato cálido de Lechuga debe comprobarse antes de recomendar la sucesión. La compatibilidad sanitaria, el rendimiento y la rentabilidad permanecen sin validar. Esta entrega no incorpora un ensayo local específico de esta pareja; compara agua/calendario y conserva las condiciones documentadas por mecanismo.

## Alcance y parámetros

**168 calendarios**; **136 completos** en 2025 y **32 inconclusos**, conservados solo como fechas. Se ejecutaron **19,584 corridas** y **9,792 comparaciones pareadas**. Ambos sentidos tienen la misma cantidad de escenarios.

| Cultivo/producto | Identidad y familia | Kc inicial / medio / final | Raíz | p | Duraciones (días) |
|---|---|---:|---:|---:|---|
| Frijol | Phaseolus vulgaris L. · Fabaceae | 0.4 / 1.15 / 0.35 | 0.6 m | 0.45 | 70, 95 |
| Lechuga | Lactuca sativa L. · Asteraceae | 0.7 / 1.0 / 0.95 | 0.4 m | 0.3 | 75, 105 |

Los productos, etapas y notas se conservan en [parámetros](../../datos/cultivos/parametros_auditados.json). [FAO-56, tablas 11/12](https://www.fao.org/4/x0490e/x0490e0b.htm) y [tabla 22](https://www.fao.org/4/x0490e/x0490e0e.htm) son referencias sin calibración de parcela. Kc inicial puede proceder del grupo. El cambio de familia no genera premio, veto ni crédito de nitrógeno.

## Caso de referencia

Inicio común **1 de marzo de 2025**, duraciones de referencia Frijol 70 días; Lechuga 75 días, **14 días completos** entre cultivos. Perfil de referencia, escorrentía supuesta 15%, reserva al 1 de enero 25%. El agua se conserva entre cultivos.

| Dirección | Primer cultivo | Segundo cultivo |
|---|---|---|
| Frijol → Lechuga | 2025-03-01 a 2025-05-09 | 2025-05-24 a 2025-08-06 |
| Lechuga → Frijol | 2025-03-01 a 2025-05-14 | 2025-05-29 a 2025-08-06 |

| Lluvia | Déficit directo secano (mm) | Déficit inverso secano (mm) | Días Ks<0.95 directo/inverso | Riego idealizado directo/inverso (mm netos) |
|---|---:|---:|---:|---:|
| IMERG V07 Late | 183.41 | 204.71 | 74 / 77 | 340 / 360 |
| CHIRPS v2 | 319.90 | 311.84 | 100 / 98 | 420 / 400 |
| ERA5 | 330.21 | 338.14 | 104 / 101 | 440 / 420 |
| POWER | 269.97 | 275.92 | 97 / 99 | 340 / 380 |

La última columna corresponde a corridas separadas con pulsos de 20 mm netos al superar RAW y suministro ilimitado; no es una dosis recomendada o agua confirmada. Ver el déficit residual de cada corrida en [referencia](referencia.csv). Un déficit de ET menor no equivale a mayor cosecha o calidad comercial.

![Comparación de referencia](comparacion_hidrica.png)

En los **4,896 pares de secano** de toda la malla, la inversa tiene mayor déficit en **2,649**, menor en **2,247** y diferencia absoluta de hasta 0.0001 mm en **0**. Estos conteos son escenarios diseñados, sin probabilidad de éxito ni representatividad estadística de fincas.

## Temperatura, establecimiento y operaciones

| Dirección y cultivo | Producto térmico | Media del período (°C) | Días media>24 / total | Días Tmax>30 / total |
|---|---|---:|---:|---:|
| Directa · Frijol | POWER | 25.12 | 46 / 70 | 55 / 70 |
| Directa · Frijol | ERA5 | 28.23 | 68 / 70 | 61 / 70 |
| Directa · Lechuga | POWER | 24.33 | 38 / 75 | 13 / 75 |
| Directa · Lechuga | ERA5 | 27.80 | 75 / 75 | 71 / 75 |
| Inversa · Lechuga | POWER | 25.12 | 49 / 75 | 58 / 75 |
| Inversa · Lechuga | ERA5 | 28.25 | 73 / 75 | 66 / 75 |
| Inversa · Frijol | POWER | 24.12 | 33 / 70 | 8 / 70 |
| Inversa · Frijol | ERA5 | 27.66 | 70 / 70 | 66 / 70 |

POWER T2M es media diaria del producto regional. ERA5 usa semisuma Tmax/Tmin, una aproximación diferente. Tmax no equivale a temperatura media ni de órgano. Los umbrales son indicadores descriptivos; no son una función de daño. El fotoperíodo está en [exposición de referencia](exposicion_referencia.csv); es duración astronómica del día, sin respuesta del cultivo ni nubosidad.

Lluvia durante los intervalos de retiro/preparación del caso de referencia:

| Dirección | Intervalo completo | Lluvia | Total (mm) |
|---|---|---|---:|
| Directa | 2025-05-10 a 2025-05-23 | IMERG V07 Late | 115.6 |
| Directa | 2025-05-10 a 2025-05-23 | CHIRPS v2 | 42.9 |
| Directa | 2025-05-10 a 2025-05-23 | ERA5 | 27.5 |
| Directa | 2025-05-10 a 2025-05-23 | POWER | 39.9 |
| Inversa | 2025-05-15 a 2025-05-28 | IMERG V07 Late | 54.9 |
| Inversa | 2025-05-15 a 2025-05-28 | CHIRPS v2 | 18.3 |
| Inversa | 2025-05-15 a 2025-05-28 | ERA5 | 16.9 |
| Inversa | 2025-05-15 a 2025-05-28 | POWER | 12.2 |

Reservar días no demuestra que permitan secado, curado, retiro o entrada de maquinaria. La lluvia acumulada tampoco demuestra anegamiento. El motor drena instantáneamente el exceso; es necesario observar drenaje y humedad reales.

## Condiciones documentales y sanitarias

- **Frijol:** 70 días es sensibilidad prorrateada; no duración universal de una variedad. No se asigna crédito fijo de nitrógeno ni se simula fijación o mineralización. La guía Dry Beans reúne distintos tipos de frijol: hospedaje de grupo no acredita susceptibilidad de cada material guatemalteco.
- **Lechuga:** Calor, tipo comercial y variedad condicionan espigado, amargor y formación de cabeza. La temperatura de inhibición de germinación no se aplica como pérdida a trasplantes. Una cosecha de hoja/cabeza fresca, sin cortes múltiples; almácigo externo supuesto.

**Alerta potencial por hospedaje compartido de *Meloidogyne incognita*.** Las fuentes por cultivo/grupo están en el registro común. Se necesita identificar organismo/población y susceptibilidad del material local; no demuestra infección en esta parcela. Para frijol la evidencia es de Dry Beans y para brócoli del grupo de coles. No se asigna una penalización ni un efecto sanitario del orden.

Fuentes primarias por cultivo y alcance:

- Frijol: [fuente 1](https://www.icta.gob.gt/publicaciones/Frijol/Manual%20de%20producci%C3%B3n%20de%20frijol%20ICTA.pdf), [fuente 2](https://ipm.ucanr.edu/agriculture/dry-beans/nematodes/). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).
- Lechuga: [fuente 1](https://ipm.ucanr.edu/home-and-landscape/cultural-tips-for-growing-lettuce/), [fuente 2](https://ipm.ucanr.edu/agriculture/lettuce/nematodes/). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).

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
