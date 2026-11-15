# Auditoría Ajonjolí ↔ Lechuga · Chiquimula · 2025

**Direcciones evaluadas:** Ajonjolí → Lechuga y Lechuga → Ajonjolí. Entrega del 15 de noviembre de 2026, punto **14.8250, −89.5312**. Sucesiones estrictas, sin coexistencia y sin repeticiones. [Volver a la cobertura de los siete cultivos](../../README.md).

**Dictamen:** En la referencia, la dirección directa acumula menor déficit con 1 de las cuatro lluvias y la inversa con 3. Esto describe ese calendario y no una superioridad general. La adaptación al candidato cálido de Lechuga debe comprobarse antes de recomendar la sucesión. La compatibilidad sanitaria, el rendimiento y la rentabilidad permanecen sin validar. Esta entrega no incorpora un ensayo local específico de esta pareja; compara agua/calendario y conserva las condiciones documentadas por mecanismo.

## Alcance y parámetros

**336 calendarios**; **170 completos** en 2025 y **166 inconclusos**, conservados solo como fechas. Se ejecutaron **24,480 corridas** y **12,240 comparaciones pareadas**. Ambos sentidos tienen la misma cantidad de escenarios.

| Cultivo/producto | Identidad y familia | Kc inicial / medio / final | Raíz | p | Duraciones (días) |
|---|---|---:|---:|---:|---|
| Ajonjolí | Sesamum indicum L. · Pedaliaceae | 0.35 / 1.1 / 0.25 | 1.0 m | 0.6 | 100, 110, 150, 180 |
| Lechuga | Lactuca sativa L. · Asteraceae | 0.7 / 1.0 / 0.95 | 0.4 m | 0.3 | 75, 105 |

Los productos, etapas y notas se conservan en [parámetros](../../datos/cultivos/parametros_auditados.json). [FAO-56, tablas 11/12](https://www.fao.org/4/x0490e/x0490e0b.htm) y [tabla 22](https://www.fao.org/4/x0490e/x0490e0e.htm) son referencias sin calibración de parcela. Kc inicial puede proceder del grupo. El cambio de familia no genera premio, veto ni crédito de nitrógeno.

## Caso de referencia

Inicio común **1 de marzo de 2025**, duraciones de referencia Ajonjolí 110 días; Lechuga 75 días, **14 días completos** entre cultivos. Perfil de referencia, escorrentía supuesta 15%, reserva al 1 de enero 25%. El agua se conserva entre cultivos.

| Dirección | Primer cultivo | Segundo cultivo |
|---|---|---|
| Ajonjolí → Lechuga | 2025-03-01 a 2025-06-18 | 2025-07-03 a 2025-09-15 |
| Lechuga → Ajonjolí | 2025-03-01 a 2025-05-14 | 2025-05-29 a 2025-09-15 |

| Lluvia | Déficit directo secano (mm) | Déficit inverso secano (mm) | Días Ks<0.95 directo/inverso | Riego idealizado directo/inverso (mm netos) |
|---|---:|---:|---:|---:|
| IMERG V07 Late | 133.53 | 219.12 | 73 / 85 | 260 / 380 |
| CHIRPS v2 | 340.19 | 309.49 | 130 / 103 | 440 / 400 |
| ERA5 | 367.64 | 343.22 | 141 / 103 | 440 / 420 |
| POWER | 323.66 | 294.43 | 132 / 111 | 400 / 400 |

La última columna corresponde a corridas separadas con pulsos de 20 mm netos al superar RAW y suministro ilimitado; no es una dosis recomendada o agua confirmada. Ver el déficit residual de cada corrida en [referencia](referencia.csv). Un déficit de ET menor no equivale a mayor cosecha o calidad comercial.

![Comparación de referencia](comparacion_hidrica.png)

En los **6,120 pares de secano** de toda la malla, la inversa tiene mayor déficit en **3,069**, menor en **3,051** y diferencia absoluta de hasta 0.0001 mm en **0**. Estos conteos son escenarios diseñados, sin probabilidad de éxito ni representatividad estadística de fincas.

## Temperatura, establecimiento y operaciones

| Dirección y cultivo | Producto térmico | Media del período (°C) | Días media>24 / total | Días Tmax>30 / total |
|---|---|---:|---:|---:|
| Directa · Ajonjolí | POWER | 25.42 | 80 / 110 | 79 / 110 |
| Directa · Ajonjolí | ERA5 | 28.65 | 108 / 110 | 101 / 110 |
| Directa · Lechuga | POWER | 24.34 | 46 / 75 | 26 / 75 |
| Directa · Lechuga | ERA5 | 27.49 | 75 / 75 | 72 / 75 |
| Inversa · Lechuga | POWER | 25.12 | 49 / 75 | 58 / 75 |
| Inversa · Lechuga | ERA5 | 28.25 | 73 / 75 | 66 / 75 |
| Inversa · Ajonjolí | POWER | 24.36 | 65 / 110 | 33 / 110 |
| Inversa · Ajonjolí | ERA5 | 27.68 | 110 / 110 | 105 / 110 |

POWER T2M es media diaria del producto regional. ERA5 usa semisuma Tmax/Tmin, una aproximación diferente. Tmax no equivale a temperatura media ni de órgano. Los umbrales son indicadores descriptivos; no son una función de daño. El fotoperíodo está en [exposición de referencia](exposicion_referencia.csv); es duración astronómica del día, sin respuesta del cultivo ni nubosidad.

Lluvia durante los intervalos de retiro/preparación del caso de referencia:

| Dirección | Intervalo completo | Lluvia | Total (mm) |
|---|---|---|---:|
| Directa | 2025-06-19 a 2025-07-02 | IMERG V07 Late | 229.9 |
| Directa | 2025-06-19 a 2025-07-02 | CHIRPS v2 | 165.7 |
| Directa | 2025-06-19 a 2025-07-02 | ERA5 | 95.6 |
| Directa | 2025-06-19 a 2025-07-02 | POWER | 79.5 |
| Inversa | 2025-05-15 a 2025-05-28 | IMERG V07 Late | 54.9 |
| Inversa | 2025-05-15 a 2025-05-28 | CHIRPS v2 | 18.3 |
| Inversa | 2025-05-15 a 2025-05-28 | ERA5 | 16.9 |
| Inversa | 2025-05-15 a 2025-05-28 | POWER | 12.2 |

Reservar días no demuestra que permitan secado, curado, retiro o entrada de maquinaria. La lluvia acumulada tampoco demuestra anegamiento. El motor drena instantáneamente el exceso; es necesario observar drenaje y humedad reales.

## Condiciones documentales y sanitarias

- **Ajonjolí:** La fila HTML FAO suma 110 días aunque su total dice 100. 100/150/180 son hipótesis reescaladas, sin cultivar local validado. La sensibilidad al anegamiento requiere observación de drenaje; el modelo drena instantáneamente el exceso. 7/14/21 días de intervalo no garantizan secado, cosecha o retiro. La resistencia a nematodos descrita para materiales de otra región no se generaliza a cualquier ajonjolí guatemalteco.
- **Lechuga:** Calor, tipo comercial y variedad condicionan espigado, amargor y formación de cabeza. La temperatura de inhibición de germinación no se aplica como pérdida a trasplantes. Una cosecha de hoja/cabeza fresca, sin cortes múltiples; almácigo externo supuesto.

**Sanidad sin resolver para esta pareja.** La revisión selectiva no incorpora una alerta de hospedaje compartido para ambos cultivos en su regla actual. Eso no acredita ausencia de organismos compartidos, inocuidad ni ruptura sanitaria. Ajonjolí y maíz no se clasifican como no hospedantes por falta de una alerta. Hace falta diagnóstico dirigido y comprobar el material.

Fuentes primarias por cultivo y alcance:

- Ajonjolí: [fuente 1](https://content.ces.ncsu.edu/sesame-production-fact-sheet), [fuente 2](https://www.maga.gob.gt/sitios/diplan/download/informacion_del_sector/fichasdemercado/Ajonjol%C3%AD%20de%20Primera%20Mayorista.pdf). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).
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
