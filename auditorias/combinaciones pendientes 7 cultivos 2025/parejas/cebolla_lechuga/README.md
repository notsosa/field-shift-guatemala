# Auditoría Cebolla ↔ Lechuga · Chiquimula · 2025

**Direcciones evaluadas:** Cebolla → Lechuga y Lechuga → Cebolla. Entrega del 15 de noviembre de 2026, punto **14.8250, −89.5312**. Sucesiones estrictas, sin coexistencia y sin repeticiones. [Volver a la cobertura de los siete cultivos](../../README.md).

**Dictamen:** En la referencia, la dirección directa acumula menor déficit con 2 de las cuatro lluvias y la inversa con 2. Esto describe ese calendario y no una superioridad general. La adaptación al candidato cálido de Lechuga debe comprobarse antes de recomendar la sucesión. La compatibilidad sanitaria, el rendimiento y la rentabilidad permanecen sin validar. Esta entrega no incorpora un ensayo local específico de esta pareja; compara agua/calendario y conserva las condiciones documentadas por mecanismo.

## Alcance y parámetros

**168 calendarios**; **46 completos** en 2025 y **122 inconclusos**, conservados solo como fechas. Se ejecutaron **6,624 corridas** y **3,312 comparaciones pareadas**. Ambos sentidos tienen la misma cantidad de escenarios.

| Cultivo/producto | Identidad y familia | Kc inicial / medio / final | Raíz | p | Duraciones (días) |
|---|---|---:|---:|---:|---|
| Cebolla | Allium cepa L. · Amaryllidaceae | 0.7 / 1.05 / 0.75 | 0.5 m | 0.3 | 150, 210 |
| Lechuga | Lactuca sativa L. · Asteraceae | 0.7 / 1.0 / 0.95 | 0.4 m | 0.3 | 75, 105 |

Los productos, etapas y notas se conservan en [parámetros](../../datos/cultivos/parametros_auditados.json). [FAO-56, tablas 11/12](https://www.fao.org/4/x0490e/x0490e0b.htm) y [tabla 22](https://www.fao.org/4/x0490e/x0490e0e.htm) son referencias sin calibración de parcela. Kc inicial puede proceder del grupo. El cambio de familia no genera premio, veto ni crédito de nitrógeno.

## Caso de referencia

Inicio común **1 de marzo de 2025**, duraciones de referencia Cebolla 150 días; Lechuga 75 días, **14 días completos** entre cultivos. Perfil de referencia, escorrentía supuesta 15%, reserva al 1 de enero 25%. El agua se conserva entre cultivos.

| Dirección | Primer cultivo | Segundo cultivo |
|---|---|---|
| Cebolla → Lechuga | 2025-03-01 a 2025-07-28 | 2025-08-12 a 2025-10-25 |
| Lechuga → Cebolla | 2025-03-01 a 2025-05-14 | 2025-05-29 a 2025-10-25 |

| Lluvia | Déficit directo secano (mm) | Déficit inverso secano (mm) | Días Ks<0.95 directo/inverso | Riego idealizado directo/inverso (mm netos) |
|---|---:|---:|---:|---:|
| IMERG V07 Late | 204.41 | 260.93 | 81 / 99 | 380 / 460 |
| CHIRPS v2 | 378.56 | 358.14 | 107 / 123 | 480 / 480 |
| ERA5 | 410.71 | 405.44 | 112 / 134 | 500 / 500 |
| POWER | 355.78 | 386.62 | 123 / 161 | 440 / 520 |

La última columna corresponde a corridas separadas con pulsos de 20 mm netos al superar RAW y suministro ilimitado; no es una dosis recomendada o agua confirmada. Ver el déficit residual de cada corrida en [referencia](referencia.csv). Un déficit de ET menor no equivale a mayor cosecha o calidad comercial.

![Comparación de referencia](comparacion_hidrica.png)

En los **1,656 pares de secano** de toda la malla, la inversa tiene mayor déficit en **293**, menor en **1,363** y diferencia absoluta de hasta 0.0001 mm en **0**. Estos conteos son escenarios diseñados, sin probabilidad de éxito ni representatividad estadística de fincas.

## Temperatura, establecimiento y operaciones

| Dirección y cultivo | Producto térmico | Media del período (°C) | Días media>24 / total | Días Tmax>30 / total |
|---|---|---:|---:|---:|
| Directa · Cebolla | POWER | 24.98 | 94 / 150 | 80 / 150 |
| Directa · Cebolla | ERA5 | 28.27 | 148 / 150 | 138 / 150 |
| Directa · Lechuga | POWER | 24.14 | 37 / 75 | 26 / 75 |
| Directa · Lechuga | ERA5 | 27.48 | 75 / 75 | 68 / 75 |
| Inversa · Lechuga | POWER | 25.12 | 49 / 75 | 58 / 75 |
| Inversa · Lechuga | ERA5 | 28.25 | 73 / 75 | 66 / 75 |
| Inversa · Cebolla | POWER | 24.15 | 75 / 150 | 37 / 150 |
| Inversa · Cebolla | ERA5 | 27.57 | 150 / 150 | 139 / 150 |

POWER T2M es media diaria del producto regional. ERA5 usa semisuma Tmax/Tmin, una aproximación diferente. Tmax no equivale a temperatura media ni de órgano. Los umbrales son indicadores descriptivos; no son una función de daño. El fotoperíodo está en [exposición de referencia](exposicion_referencia.csv); es duración astronómica del día, sin respuesta del cultivo ni nubosidad.

Lluvia durante los intervalos de retiro/preparación del caso de referencia:

| Dirección | Intervalo completo | Lluvia | Total (mm) |
|---|---|---|---:|
| Directa | 2025-07-29 a 2025-08-11 | IMERG V07 Late | 35.5 |
| Directa | 2025-07-29 a 2025-08-11 | CHIRPS v2 | 42.2 |
| Directa | 2025-07-29 a 2025-08-11 | ERA5 | 36.6 |
| Directa | 2025-07-29 a 2025-08-11 | POWER | 34.8 |
| Inversa | 2025-05-15 a 2025-05-28 | IMERG V07 Late | 54.9 |
| Inversa | 2025-05-15 a 2025-05-28 | CHIRPS v2 | 18.3 |
| Inversa | 2025-05-15 a 2025-05-28 | ERA5 | 16.9 |
| Inversa | 2025-05-15 a 2025-05-28 | POWER | 12.2 |

Reservar días no demuestra que permitan secado, curado, retiro o entrada de maquinaria. La lluvia acumulada tampoco demuestra anegamiento. El motor drena instantáneamente el exceso; es necesario observar drenaje y humedad reales.

## Condiciones documentales y sanitarias

- **Cebolla:** Variedad, fotoperíodo y trasplante condicionan bulbificación. Se calcula largo astronómico del día, sin respuesta del bulbo. Producto modelado: bulbo seco, con almácigo externo supuesto; curado y retiro sin verificar.
- **Lechuga:** Calor, tipo comercial y variedad condicionan espigado, amargor y formación de cabeza. La temperatura de inhibición de germinación no se aplica como pérdida a trasplantes. Una cosecha de hoja/cabeza fresca, sin cortes múltiples; almácigo externo supuesto.

**Alerta potencial por hospedaje compartido de *Meloidogyne incognita*.** Las fuentes por cultivo/grupo están en el registro común. Se necesita identificar organismo/población y susceptibilidad del material local; no demuestra infección en esta parcela. Para frijol la evidencia es de Dry Beans y para brócoli del grupo de coles. No se asigna una penalización ni un efecto sanitario del orden.

Fuentes primarias por cultivo y alcance:

- Cebolla: [fuente 1](https://www.jstage.jst.go.jp/article/hortj/89/4/89_UTD-155/_html/-char/en), [fuente 2](https://ipm.ucanr.edu/agriculture/onion-and-garlic/nematodes/). Alcance de lectura y límites en [criterios comunes](../../fuentes/criterios_7_cultivos.json).
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
