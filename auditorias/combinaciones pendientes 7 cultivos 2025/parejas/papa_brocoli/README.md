# Auditoría Papa ↔ Brócoli · Chiquimula · 2025

**Direcciones evaluadas:** Papa → Brócoli y Brócoli → Papa. Entrega del 15 de noviembre de 2026, punto **14.8250, −89.5312**. Sucesiones estrictas, sin coexistencia y sin repeticiones. [Volver a la cobertura de los siete cultivos](../../README.md).

**Dictamen:** En la referencia, la dirección directa acumula menor déficit con 4 de las cuatro lluvias y la inversa con 0. Esto describe ese calendario y no una superioridad general. La adaptación al candidato cálido de Brócoli, Papa debe comprobarse antes de recomendar la sucesión. La compatibilidad sanitaria, el rendimiento y la rentabilidad permanecen sin validar. Esta entrega no incorpora un ensayo local específico de esta pareja; compara agua/calendario y conserva las condiciones documentadas por mecanismo.

## Alcance y parámetros

**252 calendarios**; **128 completos** en 2025 y **124 inconclusos**, conservados solo como fechas. Se ejecutaron **18,432 corridas** y **9,216 comparaciones pareadas**. Ambos sentidos tienen la misma cantidad de escenarios.

| Cultivo/producto | Identidad y familia | Kc inicial / medio / final | Raíz | p | Duraciones (días) |
|---|---|---:|---:|---:|---|
| Papa | Solanum tuberosum L. · Solanaceae | 0.5 / 1.15 / 0.75 | 0.5 m | 0.35 | 115, 130 |
| Brócoli | Brassica oleracea L. (grupo brócoli) · Brassicaceae | 0.7 / 1.05 / 0.95 | 0.5 m | 0.45 | 75, 90, 135 |

Los productos, etapas y notas se conservan en [parámetros](../../datos/cultivos/parametros_auditados.json). [FAO-56, tablas 11/12](https://www.fao.org/4/x0490e/x0490e0b.htm) y [tabla 22](https://www.fao.org/4/x0490e/x0490e0e.htm) son referencias sin calibración de parcela. Kc inicial puede proceder del grupo. El cambio de familia no genera premio, veto ni crédito de nitrógeno.

## Caso de referencia

Inicio común **1 de marzo de 2025**, duraciones de referencia Papa 115 días; Brócoli 90 días, **14 días completos** entre cultivos. Perfil de referencia, escorrentía supuesta 15%, reserva al 1 de enero 25%. El agua se conserva entre cultivos.

| Dirección | Primer cultivo | Segundo cultivo |
|---|---|---|
| Papa → Brócoli | 2025-03-01 a 2025-06-23 | 2025-07-08 a 2025-10-05 |
| Brócoli → Papa | 2025-03-01 a 2025-05-29 | 2025-06-13 a 2025-10-05 |

| Lluvia | Déficit directo secano (mm) | Déficit inverso secano (mm) | Días Ks<0.95 directo/inverso | Riego idealizado directo/inverso (mm netos) |
|---|---:|---:|---:|---:|
| IMERG V07 Late | 203.57 | 234.14 | 97 / 95 | 340 / 340 |
| CHIRPS v2 | 358.69 | 383.80 | 117 / 130 | 440 / 460 |
| ERA5 | 382.90 | 425.57 | 131 / 133 | 460 / 500 |
| POWER | 358.37 | 405.38 | 146 / 146 | 420 / 460 |

La última columna corresponde a corridas separadas con pulsos de 20 mm netos al superar RAW y suministro ilimitado; no es una dosis recomendada o agua confirmada. Ver el déficit residual de cada corrida en [referencia](referencia.csv). Un déficit de ET menor no equivale a mayor cosecha o calidad comercial.

![Comparación de referencia](comparacion_hidrica.png)

En los **4,608 pares de secano** de toda la malla, la inversa tiene mayor déficit en **1,433**, menor en **3,175** y diferencia absoluta de hasta 0.0001 mm en **0**. Estos conteos son escenarios diseñados, sin probabilidad de éxito ni representatividad estadística de fincas.

## Temperatura, establecimiento y operaciones

| Dirección y cultivo | Producto térmico | Media del período (°C) | Días media>24 / total | Días Tmax>30 / total |
|---|---|---:|---:|---:|
| Directa · Papa | POWER | 25.34 | 81 / 115 | 79 / 115 |
| Directa · Papa | ERA5 | 28.57 | 113 / 115 | 104 / 115 |
| Directa · Brócoli | POWER | 24.30 | 51 / 90 | 29 / 90 |
| Directa · Brócoli | ERA5 | 27.52 | 90 / 90 | 87 / 90 |
| Inversa · Brócoli | POWER | 25.55 | 64 / 90 | 73 / 90 |
| Inversa · Brócoli | ERA5 | 28.65 | 88 / 90 | 81 / 90 |
| Inversa · Papa | POWER | 24.17 | 58 / 115 | 29 / 115 |
| Inversa · Papa | ERA5 | 27.49 | 115 / 115 | 110 / 115 |

POWER T2M es media diaria del producto regional. ERA5 usa semisuma Tmax/Tmin, una aproximación diferente. Tmax no equivale a temperatura media ni de órgano. Los umbrales son indicadores descriptivos; no son una función de daño. El fotoperíodo está en [exposición de referencia](exposicion_referencia.csv); es duración astronómica del día, sin respuesta del cultivo ni nubosidad.

Lluvia durante los intervalos de retiro/preparación del caso de referencia:

| Dirección | Intervalo completo | Lluvia | Total (mm) |
|---|---|---|---:|
| Directa | 2025-06-24 a 2025-07-07 | IMERG V07 Late | 235.2 |
| Directa | 2025-06-24 a 2025-07-07 | CHIRPS v2 | 130.7 |
| Directa | 2025-06-24 a 2025-07-07 | ERA5 | 93.2 |
| Directa | 2025-06-24 a 2025-07-07 | POWER | 81.0 |
| Inversa | 2025-05-30 a 2025-06-12 | IMERG V07 Late | 276.1 |
| Inversa | 2025-05-30 a 2025-06-12 | CHIRPS v2 | 138.0 |
| Inversa | 2025-05-30 a 2025-06-12 | ERA5 | 148.8 |
| Inversa | 2025-05-30 a 2025-06-12 | POWER | 106.5 |

Reservar días no demuestra que permitan secado, curado, retiro o entrada de maquinaria. La lluvia acumulada tampoco demuestra anegamiento. El motor drena instantáneamente el exceso; es necesario observar drenaje y humedad reales.

## Condiciones documentales y sanitarias

- **Papa:** Referencia de mejor producción con media diaria de 18–20 °C. La máxima del aire y temperatura del tubérculo son variables distintas. Se requiere verificar material adaptado al candidato cálido y sanidad del tubérculo-semilla. No se incorporan pérdidas por calor o pudrición al balance de agua.
- **Brócoli:** Cosecha principal: 75–90 días después del trasplante; etapas prorrateadas. Los 135 días FAO son referencia extranjera separada. El ciclo general que incluye laterales/semilla no se usa como cosecha principal de 120 días. MAGA describe óptimo 16–18 °C y raíz de 30 cm; esta última difiere del rango FAO 0.4–0.6 m. Se prueban hipótesis radicales sin validarlas.

**Alerta potencial por hospedaje compartido de *Meloidogyne incognita*.** Las fuentes por cultivo/grupo están en el registro común. Se necesita identificar organismo/población y susceptibilidad del material local; no demuestra infección en esta parcela. Para frijol la evidencia es de Dry Beans y para brócoli del grupo de coles. No se asigna una penalización ni un efecto sanitario del orden.

Fuentes primarias por cultivo y alcance:

- Papa: [fuente 1](https://www.icta.gob.gt/publicaciones/Papa/manualpapaconsumo2013.pdf), [fuente 2](https://ipm.ucanr.edu/agriculture/potato/nematodes/). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).
- Brócoli: [fuente 1](https://guatemalanosedetiene.gt/wp-content/uploads/2024/06/FICHA-TECNICA-AGROCLIMATICA-BROCOLI.pdf), [fuente 2](https://ipm.ucanr.edu/agriculture/cole-crops/nematodes/). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).

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
