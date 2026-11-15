# Revisión de las investigaciones recientes

Fecha: **15 de noviembre de 2026**. Revisión realizada por el asistente principal del chat, sin delegarla al asesor que redactó la investigación.

**La revisión encontró errores de criterio, clasificación y trazabilidad que requerían corrección.** El más importante fue convertir un subconjunto de registros locales en la única base del proyecto: así se ocultaba evidencia documental válida de papa y ajonjolí. La omisión no demuestra que carezcan de plagas. Reconocer este problema exige cambiar los datos y su presentación, además de aclararlo en el chat.

El expediente corregido conserva **13 relaciones locales documentadas**, con el tipo de vínculo indicado, y una **cobertura documental explícita de los siete cultivos**. No se presentan todas las entradas como diagnósticos. Ninguna implica infestación actual en Chiquimula. Las diez menciones pendientes siguen excluidas.

## Qué se revisó

- Las 82 entradas de trabajo: 72 relaciones documentales incluidas y diez pendientes. Se revisaron selección, tipo de fuente, referencias, taxonomía informada, lugar, período y límites; el contraste con originales se concentró en los pasajes citados y los casos dudosos.
- La entrega pública de plagas y la investigación de corroboración. Se mantuvo la indicación del usuario de trabajar con información pública disponible, sin contactos institucionales ni nuevos muestreos.
- Las salidas de las 42 sucesiones entre los siete cultivos y sus pruebas existentes. Se comprobó integridad de la matriz de 18 cultivos y se revisó el alcance declarado de los informes de botánica y actualización MAGA.

Hay 29 referencias en el expediente de plagas: **19 PDF originales disponibles y con hash comprobado, cinco páginas institucionales/taxonómicas y cinco referencias de acceso limitado**. Disponibilidad no significa lectura completa de cada obra. [El registro de fuentes](fuentes_verificadas.json) indica acceso y alcance. S17 y S22 se sostienen en pasajes/resumen originales indexados; su texto completo no se pudo descargar. S23 es una copia de tercero de un manual institucional, y S02/S12 tienen acceso limitado.

## Errores y decisiones corregidas

| Hallazgo | Corrección y respaldo verificable |
|---|---|
| Exclusión de papa y ajonjolí por un filtro excesivamente estrecho. | Se añade [cobertura de los siete cultivos](../../investigacion/plagas-7-cultivos-guatemala/confirmadas/cobertura_por_cultivo.json), con fuentes y valores desconocidos para ausencia, infestación de parcela y riesgo. El [manual ICTA de papa](https://www.icta.gob.gt/publicaciones/Papa/El%20cultivo%20de%20la%20papa%20en%20Guatemala%2C%202002.pdf), §5.5.2 pp.24–27, documenta plagas en guía institucional. El [diagnóstico USAC de Retalhuleu](https://biblioteca.usac.edu.gt/tesis/22/22_0252.pdf), p.31/PDF 50, recoge reportes de agricultores de ajonjolí. Son evidencias de distinto tipo. |
| La etiqueta «directo» ocultaba diferencias entre diagnóstico y captura. | El registro de *Frankliniella occidentalis* en lechuga queda como captura en trampas dentro de parcela. La [tesis USAC](https://biblioteca.usac.edu.gt/tesis/01/01_3159.pdf), pp.153–156/PDF 179–182, describe platos/trampas; no se encontró allí crianza o alimentación demostrada sobre lechuga ni determinación taxonómica independiente. Se conserva la asignación del autor con ese límite. |
| Confusión potencial entre fecha editorial y evento. | La [tesis de lechuga hidropónica](https://biblioteca.usac.edu.gt/tesis/01/01_2071.pdf), pp.32,36/PDF 45,49, sí observa *Aphis* sp.; agosto 2004 es su publicación. No se inventa fecha de ensayo. En los dos registros de la memoria ICTA 2023 se conserva el año del informe sin asignar una fecha individual de colecta. Los registros UVG distinguen estudio 1996 de publicación 1997. |
| Dos menciones de maíz estaban clasificadas como guía. | *Elasmopalpus lignosellus* y *Coptotermes* spp. pasan de G a M. El [informe de micotoxinas de la región Chortí](https://www.icta.gob.gt/publicaciones/Informes%20Finales%20IICA-CRIA%202020/9%20MA%C3%8DZ%20ORIENTE/Micotoxinas-Servio%20Villela-CUNORI/MICOTOXINAS%20EN%20MA%C3%8DZ%20REGION%20CHORT%C3%8D.pdf), §7.2.4 p.36/PDF 36, los menciona desde dobla hasta almacén; su cuadro de daño no diagnostica individualmente cada taxón. No se deduce persistencia del suelo o daño en plántulas. |
| La selección de registros locales era inconsistente. | *Phyllophaga* en maíz queda como reporte comunitario E, según [USAC, Cuadro 1.5 p.27/PDF 42](https://biblioteca.usac.edu.gt/tesis/01/01_2437.pdf); la colección taxonómica nacional no se usa como diagnóstico de esa relación. *Dalbulus maidis* se añade a la tabla local por el ensayo de maíz ICTAB-7 en CEPSUR descrito en [ICTA 2023 p.6/PDF 10](https://www.icta.gob.gt/publicaciones/Memoriasicta/Memoria%20de%20Labores%20ICTA%202023.pdf). Por esto la tabla pasa de 12 a 13 relaciones. |
| Localizadores y títulos descriptivos insuficientes. | Se añaden páginas precisas, título original de las tesis S24/S25 y limitaciones de lectura. S25 contiene el servicio de monitoreo de lechuga dentro de una tesis cuyo tema principal es col de Bruselas. No se presenta el título descriptivo como título literal de la obra. |
| «Verificado» podía interpretarse como garantía científica. | Se separan contraste documental, integridad informática y validación agronómica. Los manifiestos y este informe declaran qué comprobaron; ninguna prueba de software certifica la biología. |
| Las tres huellas SHA-256 anteriores no coincidían con los bytes publicados. | Se verificó el contenido del commit anterior: las huellas anunciadas correspondían al texto con LF, mientras los archivos tenían CRLF. Se fija LF al escribir y se calculan/contrastan huellas sobre los bytes guardados. [La evidencia](huellas_publicacion_anterior.json) conserva ambas huellas. No cambiaba los datos biológicos, pero el manifiesto anterior era incorrecto. |

Los detalles por registro, el antes/después y las limitaciones residuales están en [hallazgos.json](hallazgos.json). D/E/M/G/H describen **tipos de evidencia**, no una escala única de certeza o un ranking de frecuencia.

## Resultado de plagas que puede usarse

La [entrega corregida](../../investigacion/plagas-7-cultivos-guatemala/confirmadas/README.md) contiene 13 relaciones locales: **11 identificadas a especie y dos a género**, no 13 especies distintas. Incluye diagnósticos, ensayos, observaciones y capturas, diferenciados por registro. La tabla local cubre cinco cultivos; el archivo de cobertura conserva antecedentes de los siete.

| Cultivo | Entradas documentales de trabajo | Relaciones en tabla local |
|---|---:|---:|
| Maíz |16|2|
| Frijol común |20|3|
| Ajonjolí |7|0|
| Papa |11|0|
| Cebolla de bulbo |7|2|
| Brócoli |8|3|
| Lechuga |3|3|

Estos son conteos de relaciones con especies, géneros o grupos en las fuentes revisadas, **no prevalencia, riesgo, censo exhaustivo ni las diez plagas más comunes por cultivo**. Frijol y maíz incluyen entradas separadas de almacenamiento y poscosecha. Cero en la tabla local indica falta de una entrada seleccionada con ese método; no significa cero plagas.

La corroboración mantiene **cero promociones entre las diez menciones pendientes**: cuatro conflictos con el listado MAGA 2024, un hospedante histórico atípico y cinco vínculos locales no corroborados. El [listado oficial alojado por IPPC](https://assets.ippc.int/static/media/files/reportingobligation/2024/02/28/acuerdo-ministerial-No-3-2024_compressed.pdf), PDF 3 filas 33/36 y PDF 14 filas 400/403, permite comprobar los cuatro conflictos. Se conserva el año del documento; no se convierte en diagnóstico de la parcela ni en garantía de estatus posterior. Las consultas sin resultados en GBIF o EPPO tampoco prueban ausencia.

## Qué ocurrió con las auditorías de rotación

**Pasaron 58 pruebas existentes de software** en siete conjuntos. Incluyen continuidad del agua, límites numéricos, equivalencia de implementaciones, calendarios y cobertura de direcciones. Las salidas completas de 46 están archivadas; el resultado de las otras 12 se observó en la herramienta y se identifica como tal en [pruebas_software.json](pruebas_software.json).

La lectura independiente de resultados guardados comprobó **34 sucesiones nuevas + ocho anteriores = 42**, sin duplicaciones entre ambos grupos; 271,296 corridas nuevas; 4,200 calendarios, de los cuales 1,884 caben completos en 2025; y 49 hashes de entradas coincidentes. No se volvieron a ejecutar los 99,023,040 pasos diarios. [controles.json](controles.json) conserva alcance y resultados.

El control de la matriz de 18 cultivos dio 324 celdas coherentes: 18 repeticiones y 306 cambios; **cero celdas aprobadas para una parcela y cero ensayos locales validados en esa selección**. Tener todas las combinaciones representadas no significa tener todas sus compatibilidades científicamente comprobadas.

La búsqueda de referencias en los motores auditados y la lectura de su método no detectaron consumo de los JSON del inventario de plagas. **No se encontró propagación numérica de esta omisión al balance hídrico.** Los resultados de agua siguen siendo escenarios exploratorios, sin modelo de incidencia/daño de plagas, rendimiento o beneficio sanitario. El nuevo código de aplicación móvil añadido por otro trabajo no forma parte de esta revisión.

## Límites y criterio de uso

Esta revisión no reconstruye la infestación de 2025, no examina ejemplares, no repite ensayos agronómicos y no determina la sanidad actual del candidato de Chiquimula. Tampoco constituye una segunda auditoría exhaustiva de toda la bibliografía de 18 cultivos, de cada parámetro de FAO o de todas las descargas climáticas/suelo/precios. En esos apartados se comprobaron coherencia, resultados conservados y límites declarados. El informe MAGA distingue correctamente frecuencia de recolección, publicación y fecha interna del archivo; aquí no se establece una cadencia nueva.

Para usar una afirmación deben acompañarla **organismo y resolución taxonómica, cultivo/producto, localidad, período realmente conocido, método, fuente/pasaje y límite de inferencia**. Una guía institucional puede apoyar una alerta contextual; una captura no acredita por sí sola infestación del hospedante; una familia botánica distinta no garantiza ruptura de plagas. Lo desconocido permanece desconocido y no genera un beneficio en la comparación.

Se añadieron controles contra las regresiones concretas encontradas: siete cultivos siempre visibles con fuentes, ausencia/riesgo/infestación desconocidos, fecha editorial separada, captura etiquetada, conservación del nivel taxonómico y exclusión de pendientes. Estos controles ayudan a mantener coherencia; la veracidad de una afirmación sigue requiriendo lectura crítica de su fuente.

El control público se puede repetir desde una copia del repositorio con `python "auditorias/revision investigaciones 2026-11-15/verificar_publicacion.py"`. Comprueba bytes, cobertura, categorías y valores desconocidos; no verifica biología. Al clonar en Windows conviene conservar los finales de línea del repositorio para comparar exactamente los bytes publicados.
