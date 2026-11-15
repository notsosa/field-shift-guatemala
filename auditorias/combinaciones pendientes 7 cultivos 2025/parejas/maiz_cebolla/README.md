# Auditoría Maíz ↔ Cebolla · Chiquimula · 2025

**Direcciones evaluadas:** Maíz → Cebolla y Cebolla → Maíz. Entrega del 15 de noviembre de 2026, punto **14.8250, −89.5312**. Sucesiones estrictas, sin coexistencia y sin repeticiones. [Volver a la cobertura de los siete cultivos](../../README.md).

**Dictamen:** En la referencia, la dirección directa acumula menor déficit con 2 de las cuatro lluvias y la inversa con 2. Esto describe ese calendario y no una superioridad general. La compatibilidad sanitaria, el rendimiento y la rentabilidad permanecen sin validar. Esta entrega no incorpora un ensayo local específico de esta pareja; compara agua/calendario y conserva las condiciones documentadas por mecanismo.

## Alcance y parámetros

**168 calendarios**; **34 completos** en 2025 y **134 inconclusos**, conservados solo como fechas. Se ejecutaron **4,896 corridas** y **2,448 comparaciones pareadas**. Ambos sentidos tienen la misma cantidad de escenarios.

| Cultivo/producto | Identidad y familia | Kc inicial / medio / final | Raíz | p | Duraciones (días) |
|---|---|---:|---:|---:|---|
| Maíz | Zea mays L. · Poaceae | 0.3 / 1.2 / 0.35 | 1.0 m | 0.55 | 90, 125 |
| Cebolla | Allium cepa L. · Amaryllidaceae | 0.7 / 1.05 / 0.75 | 0.5 m | 0.3 | 150, 210 |

Los productos, etapas y notas se conservan en [parámetros](../../datos/cultivos/parametros_auditados.json). [FAO-56, tablas 11/12](https://www.fao.org/4/x0490e/x0490e0b.htm) y [tabla 22](https://www.fao.org/4/x0490e/x0490e0e.htm) son referencias sin calibración de parcela. Kc inicial puede proceder del grupo. El cambio de familia no genera premio, veto ni crédito de nitrógeno.

## Caso de referencia

Inicio común **1 de marzo de 2025**, duraciones de referencia Maíz 90 días; Cebolla 150 días, **14 días completos** entre cultivos. Perfil de referencia, escorrentía supuesta 15%, reserva al 1 de enero 25%. El agua se conserva entre cultivos.

| Dirección | Primer cultivo | Segundo cultivo |
|---|---|---|
| Maíz → Cebolla | 2025-03-01 a 2025-05-29 | 2025-06-13 a 2025-11-09 |
| Cebolla → Maíz | 2025-03-01 a 2025-07-28 | 2025-08-12 a 2025-11-09 |

| Lluvia | Déficit directo secano (mm) | Déficit inverso secano (mm) | Días Ks<0.95 directo/inverso | Riego idealizado directo/inverso (mm netos) |
|---|---:|---:|---:|---:|
| IMERG V07 Late | 194.64 | 201.24 | 79 / 78 | 320 / 360 |
| CHIRPS v2 | 374.78 | 378.29 | 141 / 106 | 480 / 460 |
| ERA5 | 417.40 | 409.58 | 149 / 110 | 500 / 480 |
| POWER | 414.33 | 345.62 | 181 / 105 | 480 / 420 |

La última columna corresponde a corridas separadas con pulsos de 20 mm netos al superar RAW y suministro ilimitado; no es una dosis recomendada o agua confirmada. Ver el déficit residual de cada corrida en [referencia](referencia.csv). Un déficit de ET menor no equivale a mayor cosecha o calidad comercial.

![Comparación de referencia](comparacion_hidrica.png)

En los **1,224 pares de secano** de toda la malla, la inversa tiene mayor déficit en **972**, menor en **252** y diferencia absoluta de hasta 0.0001 mm en **0**. Estos conteos son escenarios diseñados, sin probabilidad de éxito ni representatividad estadística de fincas.

## Temperatura, establecimiento y operaciones

| Dirección y cultivo | Producto térmico | Media del período (°C) | Días media>24 / total | Días Tmax>30 / total |
|---|---|---:|---:|---:|
| Directa · Maíz | POWER | 25.55 | 64 / 90 | 73 / 90 |
| Directa · Maíz | ERA5 | 28.65 | 88 / 90 | 81 / 90 |
| Directa · Cebolla | POWER | 23.88 | 62 / 150 | 33 / 150 |
| Directa · Cebolla | ERA5 | 27.21 | 148 / 150 | 131 / 150 |
| Inversa · Cebolla | POWER | 24.98 | 94 / 150 | 80 / 150 |
| Inversa · Cebolla | ERA5 | 28.27 | 148 / 150 | 138 / 150 |
| Inversa · Maíz | POWER | 23.88 | 39 / 90 | 29 / 90 |
| Inversa · Maíz | ERA5 | 27.15 | 88 / 90 | 75 / 90 |

POWER T2M es media diaria del producto regional. ERA5 usa semisuma Tmax/Tmin, una aproximación diferente. Tmax no equivale a temperatura media ni de órgano. Los umbrales son indicadores descriptivos; no son una función de daño. El fotoperíodo está en [exposición de referencia](exposicion_referencia.csv); es duración astronómica del día, sin respuesta del cultivo ni nubosidad.

Lluvia durante los intervalos de retiro/preparación del caso de referencia:

| Dirección | Intervalo completo | Lluvia | Total (mm) |
|---|---|---|---:|
| Directa | 2025-05-30 a 2025-06-12 | IMERG V07 Late | 276.1 |
| Directa | 2025-05-30 a 2025-06-12 | CHIRPS v2 | 138.0 |
| Directa | 2025-05-30 a 2025-06-12 | ERA5 | 148.8 |
| Directa | 2025-05-30 a 2025-06-12 | POWER | 106.5 |
| Inversa | 2025-07-29 a 2025-08-11 | IMERG V07 Late | 35.5 |
| Inversa | 2025-07-29 a 2025-08-11 | CHIRPS v2 | 42.2 |
| Inversa | 2025-07-29 a 2025-08-11 | ERA5 | 36.6 |
| Inversa | 2025-07-29 a 2025-08-11 | POWER | 34.8 |

Reservar días no demuestra que permitan secado, curado, retiro o entrada de maquinaria. La lluvia acumulada tampoco demuestra anegamiento. El motor drena instantáneamente el exceso; es necesario observar drenaje y humedad reales.

## Condiciones documentales y sanitarias

- **Maíz:** 90 días es sensibilidad de ciclo corto con etapas prorrateadas; madurez no garantiza grano seco ni retiro. Si el cultivo siguiente se establece antes de retirar el maíz, corresponde evaluar relevo o coexistencia, fuera de este motor.
- **Cebolla:** Variedad, fotoperíodo y trasplante condicionan bulbificación. Se calcula largo astronómico del día, sin respuesta del bulbo. Producto modelado: bulbo seco, con almácigo externo supuesto; curado y retiro sin verificar.

**Sanidad sin resolver para esta pareja.** La revisión selectiva no incorpora una alerta de hospedaje compartido para ambos cultivos en su regla actual. Eso no acredita ausencia de organismos compartidos, inocuidad ni ruptura sanitaria. Ajonjolí y maíz no se clasifican como no hospedantes por falta de una alerta. Hace falta diagnóstico dirigido y comprobar el material.

Fuentes primarias por cultivo y alcance:

- Maíz: [fuente 1](https://www.icta.gob.gt/publicaciones/Maiz/Recomendaciones%20tecnicas%20para%20el%20cultivo%20de%20maiz%20en%20el%20oriente%20de%20Guatemala%202015.pdf). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).
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
