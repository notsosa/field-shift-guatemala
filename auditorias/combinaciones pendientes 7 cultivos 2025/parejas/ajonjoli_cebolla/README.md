# Auditoría Ajonjolí ↔ Cebolla · Chiquimula · 2025

**Direcciones evaluadas:** Ajonjolí → Cebolla y Cebolla → Ajonjolí. Entrega del 15 de noviembre de 2026, punto **14.8250, −89.5312**. Sucesiones estrictas, sin coexistencia y sin repeticiones. [Volver a la cobertura de los siete cultivos](../../README.md).

**Dictamen:** En la referencia, la dirección directa acumula menor déficit con 1 de las cuatro lluvias y la inversa con 3. Esto describe ese calendario y no una superioridad general. La compatibilidad sanitaria, el rendimiento y la rentabilidad permanecen sin validar. Esta entrega no incorpora un ensayo local específico de esta pareja; compara agua/calendario y conserva las condiciones documentadas por mecanismo.

## Alcance y parámetros

**336 calendarios**; **48 completos** en 2025 y **288 inconclusos**, conservados solo como fechas. Se ejecutaron **6,912 corridas** y **3,456 comparaciones pareadas**. Ambos sentidos tienen la misma cantidad de escenarios.

| Cultivo/producto | Identidad y familia | Kc inicial / medio / final | Raíz | p | Duraciones (días) |
|---|---|---:|---:|---:|---|
| Ajonjolí | Sesamum indicum L. · Pedaliaceae | 0.35 / 1.1 / 0.25 | 1.0 m | 0.6 | 100, 110, 150, 180 |
| Cebolla | Allium cepa L. · Amaryllidaceae | 0.7 / 1.05 / 0.75 | 0.5 m | 0.3 | 150, 210 |

Los productos, etapas y notas se conservan en [parámetros](../../datos/cultivos/parametros_auditados.json). [FAO-56, tablas 11/12](https://www.fao.org/4/x0490e/x0490e0b.htm) y [tabla 22](https://www.fao.org/4/x0490e/x0490e0e.htm) son referencias sin calibración de parcela. Kc inicial puede proceder del grupo. El cambio de familia no genera premio, veto ni crédito de nitrógeno.

## Caso de referencia

Inicio común **1 de marzo de 2025**, duraciones de referencia Ajonjolí 110 días; Cebolla 150 días, **14 días completos** entre cultivos. Perfil de referencia, escorrentía supuesta 15%, reserva al 1 de enero 25%. El agua se conserva entre cultivos.

| Dirección | Primer cultivo | Segundo cultivo |
|---|---|---|
| Ajonjolí → Cebolla | 2025-03-01 a 2025-06-18 | 2025-07-03 a 2025-11-29 |
| Cebolla → Ajonjolí | 2025-03-01 a 2025-07-28 | 2025-08-12 a 2025-11-29 |

| Lluvia | Déficit directo secano (mm) | Déficit inverso secano (mm) | Días Ks<0.95 directo/inverso | Riego idealizado directo/inverso (mm netos) |
|---|---:|---:|---:|---:|
| IMERG V07 Late | 163.60 | 201.24 | 103 / 78 | 300 / 360 |
| CHIRPS v2 | 385.45 | 379.29 | 165 / 112 | 500 / 480 |
| ERA5 | 412.14 | 409.58 | 174 / 110 | 520 / 480 |
| POWER | 402.58 | 345.62 | 197 / 105 | 480 / 420 |

La última columna corresponde a corridas separadas con pulsos de 20 mm netos al superar RAW y suministro ilimitado; no es una dosis recomendada o agua confirmada. Ver el déficit residual de cada corrida en [referencia](referencia.csv). Un déficit de ET menor no equivale a mayor cosecha o calidad comercial.

![Comparación de referencia](comparacion_hidrica.png)

En los **1,728 pares de secano** de toda la malla, la inversa tiene mayor déficit en **1,390**, menor en **338** y diferencia absoluta de hasta 0.0001 mm en **0**. Estos conteos son escenarios diseñados, sin probabilidad de éxito ni representatividad estadística de fincas.

## Temperatura, establecimiento y operaciones

| Dirección y cultivo | Producto térmico | Media del período (°C) | Días media>24 / total | Días Tmax>30 / total |
|---|---|---:|---:|---:|
| Directa · Ajonjolí | POWER | 25.42 | 80 / 110 | 79 / 110 |
| Directa · Ajonjolí | ERA5 | 28.65 | 108 / 110 | 101 / 110 |
| Directa · Cebolla | POWER | 23.60 | 58 / 150 | 33 / 150 |
| Directa · Cebolla | ERA5 | 26.86 | 143 / 150 | 117 / 150 |
| Inversa · Cebolla | POWER | 24.98 | 94 / 150 | 80 / 150 |
| Inversa · Cebolla | ERA5 | 28.27 | 148 / 150 | 138 / 150 |
| Inversa · Ajonjolí | POWER | 23.47 | 39 / 110 | 29 / 110 |
| Inversa · Ajonjolí | ERA5 | 26.71 | 103 / 110 | 79 / 110 |

POWER T2M es media diaria del producto regional. ERA5 usa semisuma Tmax/Tmin, una aproximación diferente. Tmax no equivale a temperatura media ni de órgano. Los umbrales son indicadores descriptivos; no son una función de daño. El fotoperíodo está en [exposición de referencia](exposicion_referencia.csv); es duración astronómica del día, sin respuesta del cultivo ni nubosidad.

Lluvia durante los intervalos de retiro/preparación del caso de referencia:

| Dirección | Intervalo completo | Lluvia | Total (mm) |
|---|---|---|---:|
| Directa | 2025-06-19 a 2025-07-02 | IMERG V07 Late | 229.9 |
| Directa | 2025-06-19 a 2025-07-02 | CHIRPS v2 | 165.7 |
| Directa | 2025-06-19 a 2025-07-02 | ERA5 | 95.6 |
| Directa | 2025-06-19 a 2025-07-02 | POWER | 79.5 |
| Inversa | 2025-07-29 a 2025-08-11 | IMERG V07 Late | 35.5 |
| Inversa | 2025-07-29 a 2025-08-11 | CHIRPS v2 | 42.2 |
| Inversa | 2025-07-29 a 2025-08-11 | ERA5 | 36.6 |
| Inversa | 2025-07-29 a 2025-08-11 | POWER | 34.8 |

Reservar días no demuestra que permitan secado, curado, retiro o entrada de maquinaria. La lluvia acumulada tampoco demuestra anegamiento. El motor drena instantáneamente el exceso; es necesario observar drenaje y humedad reales.

## Condiciones documentales y sanitarias

- **Ajonjolí:** La fila HTML FAO suma 110 días aunque su total dice 100. 100/150/180 son hipótesis reescaladas, sin cultivar local validado. La sensibilidad al anegamiento requiere observación de drenaje; el modelo drena instantáneamente el exceso. 7/14/21 días de intervalo no garantizan secado, cosecha o retiro. La resistencia a nematodos descrita para materiales de otra región no se generaliza a cualquier ajonjolí guatemalteco.
- **Cebolla:** Variedad, fotoperíodo y trasplante condicionan bulbificación. Se calcula largo astronómico del día, sin respuesta del bulbo. Producto modelado: bulbo seco, con almácigo externo supuesto; curado y retiro sin verificar.

**Sanidad sin resolver para esta pareja.** La revisión selectiva no incorpora una alerta de hospedaje compartido para ambos cultivos en su regla actual. Eso no acredita ausencia de organismos compartidos, inocuidad ni ruptura sanitaria. Ajonjolí y maíz no se clasifican como no hospedantes por falta de una alerta. Hace falta diagnóstico dirigido y comprobar el material.

Fuentes primarias por cultivo y alcance:

- Ajonjolí: [fuente 1](https://content.ces.ncsu.edu/sesame-production-fact-sheet), [fuente 2](https://www.maga.gob.gt/sitios/diplan/download/informacion_del_sector/fichasdemercado/Ajonjol%C3%AD%20de%20Primera%20Mayorista.pdf). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).
- Cebolla: [fuente 1](https://www.jstage.jst.go.jp/article/hortj/89/4/89_UTD-155/_html/-char/en), [fuente 2](https://ipm.ucanr.edu/agriculture/onion-and-garlic/nematodes/). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).

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
