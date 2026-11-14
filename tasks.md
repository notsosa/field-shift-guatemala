# Tareas · Field Shift Guatemala

Plan de trabajo para la entrega de NASA Space Apps Challenge 2026. **Cierre del envío: domingo 15 de noviembre, 11:59 p. m. (hora local).** Evaluación virtual el mismo día de 5 a 6 p. m.

Actualizado el 14 de noviembre de 2026.

**Estatus:** *No comenzada*, nadie la ha empezado · *Pendiente*, iniciada pero falta terminarla, validarla o decidirla · *Finalizada*, completa.
Al tomar una tarea, escribir tu nombre en **Responsable** y cambiar el estatus.

## A. Decisiones

| ID | Tarea | Descripción | Estatus | Responsable |
|---|---|---|---|---|
| T01 | Fijar parcela piloto y secuencias | Elegir la coordenada de la parcela piloto y las 3 secuencias a comparar: práctica actual, maíz → frijol y frijol → maíz. Hoy se usa una coordenada **provisional**: cabecera de Chiquimula (14.80, −89.54). | Pendiente | — |
| T02 | Definir stack técnico | Propuesta: web estática adaptable a celular en GitHub Pages, con datos pre-descargados en JSON y sin backend. Confirmar con el equipo. | No comenzada | — |
| T03 | Cuenta Earthdata y solicitud AppEEARS | Crear cuenta en Earthdata Login y enviar solicitud de extracción por punto en AppEEARS: SMAP L4 `SPL4SMGP.008` (2015–2025) y SRTM `SRTMGL1_NC.003`. La solicitud puede tardar horas: enviarla pronto. | No comenzada | — |

## B. Datos

| ID | Tarea | Descripción | Estatus | Responsable |
|---|---|---|---|---|
| T04 | Descargar NASA POWER diario | Serie diaria 2001–2025 (9 131 días, 0 faltantes) para la parcela piloto: temperatura, punto de rocío, humedad, viento, radiación, lluvia, presión y humedad del suelo de MERRA-2 (GWETTOP, GWETROOT, GWETPROF, EVLAND). Script `scripts/descargar_power.py`; salida en `datos/power/` (JSON original, CSV limpio y metadatos). | Finalizada | mariobet23440 con Claude (IA) |
| T05 | Procesar SMAP L4 y SRTM | Convertir la salida de AppEEARS en series de humedad superficial y radicular y en pendiente de la parcela. Depende de T03. | No comenzada | — |
| T06 | Propiedades de suelo | Obtener de SoilGrids (WCS) la textura y la retención de agua (capacidad de campo y punto de marchitez), o fijar un suelo de referencia con su supuesto explícito. | No comenzada | — |
| T07 | Contrastar lluvia de POWER | La lluvia anual de la celda de POWER (≈ 900–2 900 mm; 2022 = 2 931 mm) parece alta para el valle de Chiquimula, y la celda está a 762 m de elevación. Comparar con una estación de INSIVUMEH o con GPM IMERG antes de usarla en el balance. | No comenzada | — |

## C. Catálogo de cultivos

| ID | Tarea | Descripción | Estatus | Responsable |
|---|---|---|---|---|
| T08 | Fichas de maíz y frijol | Fichas JSON con variedades ICTA (días a floración y cosecha), Kc por etapa y profundidad radicular de FAO-56. Cada valor lleva fuente, página y unidad. | No comenzada | — |

## D. Motor de comparación

| ID | Tarea | Descripción | Estatus | Responsable |
|---|---|---|---|---|
| T09 | Calcular ET₀ | Evapotranspiración de referencia FAO-56 Penman-Monteith a partir de POWER. | No comenzada | — |
| T10 | Balance hídrico diario | Balance FAO-56 en la zona de raíces: lluvia, escorrentía, ETc = Kc × ET₀, drenaje y agotamiento. | No comenzada | — |
| T11 | Fases sensibles por año | Ubicar emergencia, floración, llenado y cosecha de cada secuencia en cada año histórico. | No comenzada | — |
| T12 | Indicadores por secuencia | Déficit en floración y llenado, lluvia en cosecha, días con suelo descubierto y su variación entre años secos y húmedos. | No comenzada | — |

## E. Interfaz (en inglés, móvil)

| ID | Tarea | Descripción | Estatus | Responsable |
|---|---|---|---|---|
| T13 | Formulario del finquero | Entradas: parcela, cultivo previo, alternativas y prioridad (producción, agua, costo, conservación). | No comenzada | — |
| T14 | Vista de comparación | Secuencias lado a lado con línea de tiempo, riesgo por fase y explicación del tipo «B depende de que la lluvia no termine antes…». | No comenzada | — |
| T15 | Panel de fuentes | Producto, versión, resolución, fechas y limitaciones de cada dataset usado. | No comenzada | — |

## F. Entrega

| ID | Tarea | Descripción | Estatus | Responsable |
|---|---|---|---|---|
| T16 | Repositorio público | README con instrucciones, fuentes, licencias de los datos y declaración de uso de IA. | No comenzada | — |
| T17 | Publicar la web | Desplegar en GitHub Pages y comprobar que abre sin registro ni permisos. | No comenzada | — |
| T18 | Demo y página Project | Hasta 7 diapositivas o un video de 30 s, y la página Project en inglés: resumen, descripción, enlace, datos NASA y uso de IA. | No comenzada | — |
| T19 | Confirmar rúbrica y pitch | Preguntar a la organización local qué rúbrica usa el jurado y cuánto dura el pitch. | No comenzada | — |
| T20 | Submit for Judging | Enviar antes del domingo 15 de noviembre a las 11:59 p. m. | No comenzada | — |

## G. Extras si sobra tiempo

| ID | Tarea | Descripción | Estatus | Responsable |
|---|---|---|---|---|
| T21 | Módulo de café | Consulta de humedad (SMAP) y floración para cafetal establecido. | No comenzada | — |
| T22 | Validación con productores | Mostrar el prototipo a uno de los cafetaleros entrevistados o a un finquero y registrar sus comentarios. | No comenzada | — |
