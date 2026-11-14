# Field Shift Guatemala · Handoff del proyecto y comparación de rotaciones

Actualizado el 14 de noviembre de 2026. Este documento conserva el contexto, las decisiones y el estado de la investigación para continuar el proyecto en otros chats. La propuesta técnica se elabora con el asesor agroclimático.

## Contexto y decisiones acordadas

- El equipo participa en la sede de Ciudad de Guatemala de NASA Space Apps Challenge 2026 y eligió Field Shift: Adapting Farms with NASA Data.
- El reto pide una herramienta de apoyo para explorar rotaciones que combine observaciones de la Tierra de NASA, información local de suelos, características de cultivos y prioridades del agricultor. [Enunciado oficial](https://www.spaceappschallenge.org/2026/challenges/field-shift-adapting-farms-with-nasa-data/)
- El usuario principal es el finquero. Sus objetivos de producción, rentabilidad, uso del agua, suelo y operación de la finca guían la comparación.
- El equipo plantea una aplicación móvil y una aplicación web. La arquitectura y el alcance de implementación siguen pendientes de decisión.
- El núcleo del reto será la comparación de cultivos sucesivos en la misma parcela. El equipo también quiere ayudar a cafetaleros con decisiones de agua y manejo del cafetal establecido.
- En los criterios compartidos por el usuario, impacto, creatividad, sostenibilidad, producto y presentación tienen igual peso. Esta rúbrica proviene de su imagen adjunta.
- Los dos contactos entrevistados informalmente son cafetaleros. Mencionaron curvas de nivel, escorrentía, retención de agua, floración, humedad y «riego solar». El significado de esta última expresión queda por precisar. El usuario confirmó que el servicio de pronóstico al que se referían era Nubis Bot. [Apuntes de las conversaciones](../investigacion/testimonios-2026-11-11.md)

## Estado al retomar

Se seleccionaron 18 candidatos para construir el catálogo de cultivos. La lista es una propuesta de trabajo que amplía el ejemplo inicial de maíz y frijol. La región, la finca piloto, las variedades y las transiciones que se evaluarán se decidirán con registros y objetivos concretos. Chiquimula y Zacapa fueron propuestas de investigación.

Hay documentación y fuentes identificadas. Siguen pendientes el catálogo de parámetros estructurados, las series ambientales de la parcela elegida, la evaluación de transiciones y la validación de resultados en campo. Las referencias y ejemplos actuales permiten diseñar la comparación.

Los agentes reutilizables del proyecto son `asesor_agroclimatico` e `investigador_de_productores`. Sus perfiles están en `.codex/agents/`. Los documentos de consulta incluyen el [manual agroclimático](manual-agroclimatico.md), la [guía de datos NASA](observaciones-nasa.md) y la [investigación sobre productores](../investigacion/productores-guatemala.md).

Al continuar, actualizar las decisiones con lo que indique el usuario. Registrar para cada dato su fuente, fecha, alcance y validación pendiente. Una propuesta del equipo se mantiene identificada como tal hasta que se adopte.

## Entrega del evento · verificación del 14 de noviembre

Se consultaron directamente la página y la agenda de Guatemala y la guía oficial de entrega fechada el 13 de noviembre de 2026.

La agenda local programa evaluación virtual el domingo 15 de noviembre de 5 a 6 p. m. La página publica el contacto de María Zaghi, info@mzaghi.com. Quedan por confirmar duración del pitch y cualquier corte de recepción de materiales para esa evaluación. [Agenda local de Guatemala](https://www.spaceappschallenge.org/2026/local-events/guatemala/?tab=schedule) · [Información local](https://www.spaceappschallenge.org/2026/local-events/guatemala/)

La guía global solicita completar la página Project del equipo con resumen, descripción, enlace público al proyecto final, uso de datos NASA y referencias, y declaración del uso de herramientas de inteligencia artificial. La demo admite hasta siete diapositivas, incluida la portada, o un video de hasta 30 segundos. La página y los materiales enlazados deben estar en inglés. El video puede narrarse en español con subtítulos en inglés. Los enlaces deben poder abrirse sin permisos ni registro. Una web es un formato expresamente admitido para enlazar el proyecto final. La entrega se completa mediante Submit for Judging hasta el domingo 15 de noviembre a las 11:59 p. m., hora del evento local. [Guía oficial de entrega 2026](https://www.spaceappschallenge.org/resources/project-submission-guide/)

Para el prototipo de software del equipo, se propone web adaptable a celular, repositorio público con instrucciones y fuentes, y una demo en uno de los formatos admitidos. Esta es una propuesta de implementación. La elección final de formato técnico sigue pendiente del equipo.

Los términos oficiales exigen referencias y documentación de licencia de los materiales originales. Preparar estos elementos junto con el código. [Términos 2026, propiedad intelectual](https://www.spaceappschallenge.org/legal/)

La guía global enumera Impacto, Creatividad, Validez, Relevancia y Presentación. El usuario compartió una imagen con Impacto, Creatividad, Sostenibilidad, Producto y Presentación. Hay que confirmar con la organización qué rúbrica usa el jurado local. [Guía oficial, criterios referidos para evaluación](https://www.spaceappschallenge.org/resources/project-submission-guide/#tips-for-creating-a-project-demo)

### Opciones de publicación y dominio

El dominio es el nombre de la dirección y el alojamiento sirve los archivos de la aplicación. GoDaddy figura entre los colaboradores globales de 2026. El equipo organizador indica que los participantes encuentran sus beneficios en el menú del avatar, Global Offers, y pueden consultar cada oferta. Su disponibilidad para la cuenta se verifica allí. [Colaboradores 2026](https://www.spaceappschallenge.org/2026/) · [Respuesta del equipo organizador sobre acceso a ofertas](https://github.com/nasa/spaceapps/discussions/2035)

Se verificó el sitio promocional SpaceApps + GoDaddy Registry. Sus términos ofrecen registro de dominio por 12 meses para participantes, mediante código promocional y disponibilidad durante el evento. La renovación tiene el precio vigente del registrador. La página remite a Porkbun para completar el registro. Queda pendiente consultar el beneficio y código de la cuenta del participante. [Promoción](https://www.spaceapps.earth/) · [Condiciones del programa](https://www.spaceapps.earth/scholarship-terms)

Para una web estática, GitHub Pages permite alojamiento con un repositorio público en GitHub Free y proporciona una dirección del tipo usuario.github.io/proyecto. Es una vía gratuita para publicar el frontend de una demo. El alojamiento de servicios del backend se determinará con la arquitectura elegida. [Documentación de GitHub Pages](https://docs.github.com/en/pages/getting-started-with-github-pages/what-is-github-pages)

## Catálogo inicial de 18 cultivos

Se eligieron cultivos documentados por instituciones guatemaltecas y manejables con fechas de establecimiento y terminación que permitan estudiar el siguiente ciclo. La lista abarca diez familias botánicas. La presencia en el catálogo habilita su estudio; la selección para una parcela depende de variedad, ambiente, manejo y objetivos.

La columna de evaluación contiene preguntas propuestas para desarrollar las fichas. Los enlaces de cada fila respaldan la documentación del cultivo en Guatemala.

| ID | Cultivo y producto de referencia | Familia botánica | Qué evaluar para encadenarlo con otro cultivo | Documentación local de partida |
|---|---|---|---|---|
| C01 | Maíz para grano | Poaceae | Fecha efectiva de liberación del lote, agua en floración y destino del rastrojo. | [ICTA, maíz](https://www.icta.gob.gt/publicacionesdemaiz) |
| C02 | Frijol común para grano | Fabaceae | Ciclo por variedad, drenaje, enfermedades de raíz y destino de residuos. | [ICTA, manual de frijol](https://www.icta.gob.gt/publicaciones/Frijol/Manual%20de%20producci%C3%B3n%20de%20frijol%20ICTA.pdf) |
| C03 | Sorgo o maicillo para grano | Poaceae | Uso de grano o forraje, permanencia de rebrotes y calendario de cortes o cosecha. | [ICTA, programa de sorgo](https://www.icta.gob.gt/sorgo) |
| C04 | Arroz para grano | Poaceae | Secano o inundación, disponibilidad de agua y drenaje para el cultivo siguiente. | [ICTA, programas de granos básicos](https://www.icta.gob.gt/granosbasicos.html) |
| C05 | Trigo para grano | Poaceae | Adaptación de variedad al sitio, calendario, sanidad y manejo de paja. | [ICTA, programa y publicaciones de trigo](https://www.icta.gob.gt/granosbasicos.html) |
| C06 | Ajonjolí para semilla | Pedaliaceae | Establecimiento, drenaje, oportunidad de cosecha y comprador. | [ICTA, programa y publicaciones de ajonjolí](https://www.icta.gob.gt/granosbasicos.html) |
| C07 | Papa para consumo | Solanaceae | Calidad del material de siembra, historial sanitario, cosecha y preparación del lote. | [ICTA, papa y otras hortalizas](https://www.icta.gob.gt/publicacioneshortalizas) |
| C08 | Tomate para fruto | Solanaceae | Campo abierto o protegido, suelo o sustrato, varios cortes y fecha de terminación. | [ICTA, manual de tomate](https://www.icta.gob.gt/publicaciones/Tomate/Manual%20Tomate%202024%20Div..pdf) |
| C09 | Chile pimiento para fruto | Solanaceae | Sistema de cultivo, duración de cosecha, agua y problemas sanitarios previos. | [ICTA, chile pimiento](https://www.icta.gob.gt/publicacioneshortalizas) |
| C10 | Cebolla para bulbo | Amaryllidaceae | Variedad, trasplante o siembra directa, maduración, curado y fecha de entrega. | [MAGA, calendario de cultivos](https://www.maga.gob.gt/download/epoca-cultivo-nov14.pdf) |
| C11 | Zanahoria para raíz | Apiaceae | Condición física del suelo, establecimiento y fecha de cosecha comercial. | [MAGA, fichas agroclimáticas](https://apps.maga.gob.gt/sieagro/Normativas?clasificacionId=21&page=3&sortOrder=Descripcion&tipoId=1) |
| C12 | Lechuga para hoja o cabeza | Asteraceae | Variedad, fecha de corte, agua, temperatura y salida comercial. | [MAGA, calendario de cultivos](https://www.maga.gob.gt/download/epoca-cultivo-nov14.pdf) |
| C13 | Arveja china para vaina tierna | Fabaceae | Variedad, tutorado, varios cortes, trabajo requerido y terminación del cultivo. | [ICTA, arveja china](https://www.icta.gob.gt/publicacioneshortalizas) |
| C14 | Brócoli para inflorescencia | Brassicaceae | Adaptación al sitio, cosecha, residuos y antecedentes de otras brásicas. | [MAGA, fichas agroeconómicas](https://apps.maga.gob.gt/sieagro/Normativas?clasificacionId=21&page=3&sortOrder=Descripcion&tipoId=1) |
| C15 | Pepino para fruto | Cucurbitaceae | Sistema de conducción, período de recolección y sanidad del lote. | [MAGA, fichas agroeconómicas](https://apps.maga.gob.gt/sieagro/Normativas?clasificacionId=21&page=5&tipoId=1) |
| C16 | Melón para fruto | Cucurbitaceae | Ventana climática, riego, cosecha comercial y obligaciones de entrega. | [MAGA, fichas agroeconómicas](https://apps.maga.gob.gt/sieagro/Normativas?clasificacionId=21&page=5&tipoId=1) |
| C17 | Sandía para fruto | Cucurbitaceae | Disponibilidad de agua, duración real del lote, cosecha y comprador. | [MAGA, ficha agroeconómica de sandía](https://apps.maga.gob.gt/sieagro/Normativas?categoriaId=202&clasificacionId=21&page=2&sortOrder=Descripcion_desc&tipoId=1) |
| C18 | Camote para raíz reservante | Convolvulaceae | Material de propagación, variedad, cosecha y manejo de guías y rebrotes. | [ICTA, manual de camote](https://www.icta.gob.gt/publicaciones/Camote/Manual%20Camote%20ICTA.pdf) |

### Particularidades que debe conservar el catálogo

En arroz, distinguir el manejo de secano y el de inundación. El sistema de agua y la posibilidad de drenar el lote afectan el cultivo posterior. [ICTA, manual de arroz en inundación](https://www.icta.gob.gt/publicaciones/Arroz/Manual%20de%20recomendaciones%20para%20cultivar%20arroz%20en%20condiciones%20de%20inundacion.pdf)

En tomate, pimiento y otros cultivos de varias recolecciones, registrar primera cosecha, última cosecha y fecha de terminación. En camote, registrar también qué ocurre con guías y rebrotes al terminar el ciclo. Para cebolla y zanahoria, las fichas aquí propuestas corresponden a bulbo y raíz comerciales. Una operación de producción de semilla requiere su propio calendario. [ICTA, manual de tomate, manejo y cosecha](https://www.icta.gob.gt/publicaciones/Tomate/Manual%20Tomate%202024%20Div..pdf) · [ICTA, manual de camote](https://www.icta.gob.gt/publicaciones/Camote/Manual%20Camote%20ICTA.pdf)

La familia sirve para orientar preguntas sanitarias. Papa, tomate y pimiento comparten Solanaceae; pepino, melón y sandía comparten Cucurbitaceae; maíz, sorgo, arroz y trigo comparten Poaceae. Para valorar la transición se debe identificar el organismo de interés y sus hospedantes, además del agua, los residuos y las labores. Al ampliar el catálogo, registrar especie y producto comercial: frijol de grano y ejote pueden pertenecer a la misma especie, al igual que arveja china y arveja para grano. [FAO, función fitosanitaria de la rotación](https://www.fao.org/conservation-agriculture/in-practice/species-diversification/en/) · [ICTA, descripción del frijol y sus productos](https://www.icta.gob.gt/publicaciones/Frijol/Manual%20de%20producci%C3%B3n%20de%20frijol%20ICTA.pdf)

Los enlaces a catálogos oficiales verifican que existe documentación del cultivo. Para establecer rangos y reglas, hace falta abrir y extraer la ficha o el manual completo y contrastarlo con el sistema productivo del piloto. Los enlaces y calendarios históricos conservan el año del documento al utilizarlos.

## Qué representa la compatibilidad

La unidad a comparar es una secuencia de cultivos y variedades en una parcela, con fechas y manejo definidos. Maíz seguido de frijol puede encajar con una ventana de lluvias y quedar expuesto a sequía en otra. Invertir el orden cambia las fechas, los residuos y las reservas disponibles. El horizonte de comparación se acuerda con el finquero; registrar el cultivo previo permite interpretar el inicio de cada alternativa.

La familia botánica ayuda a identificar relaciones posibles. La evaluación sanitaria requiere conocer la plaga o patógeno, sus hospedantes y su persistencia. Para la fertilidad, registrar cosecha y destino de los residuos permite distinguir nutrientes que salen del terreno de los que pueden reciclarse. La fijación biológica del frijol depende de su simbiosis y manejo. Un aporte de nitrógeno al cultivo siguiente exige una estimación local. [FAO, diversificación y rotación](https://www.fao.org/conservation-agriculture/in-practice/species-diversification/en/) · [ICTA, manual de frijol y manejo sanitario](https://www.icta.gob.gt/publicaciones/Frijol/Manual%20de%20producci%C3%B3n%20de%20frijol%20ICTA.pdf)

## Inventario que se puede construir

| Datos | Forma de obtenerlos | Qué permiten decidir | Qué falta comprobar en la parcela |
|---|---|---|---|
| Especie, variedad, hábito, altitud de adaptación y días a floración/cosecha | Manuales y fichas del ICTA. Transcripción de tablas y verificación por documento. | Qué variedades considerar y cuándo ocurre su etapa sensible. | Disponibilidad de semilla, fechas observadas y definición de madurez frente a cosecha. |
| Demanda de agua por etapa, profundidad radicular y sensibilidad al estrés | Parámetros de referencia de FAO 56, ajustados a cultivo, etapa y suelo. | Comparar exposición a déficit durante floración y llenado. | Profundidad efectiva, cobertura, agotamiento inicial y respuesta local. |
| Lluvia histórica diaria y eventos | GPM IMERG. Serie satelital, cuadrícula de 0.1°, productos de media hora y acumulados según selección. | Comparar ventanas y años secos/húmedos. | Acumulado del pluviómetro, completitud y correspondencia de fechas. |
| Temperatura, humedad, radiación y viento | NASA POWER, servicio diario por coordenadas en CSV/JSON. | Estimar demanda atmosférica y exposición térmica durante cada secuencia. | Representatividad de la celda, unidades por parámetro, exposición y registros locales. |
| Pronóstico y observaciones guatemaltecas | INSIVUMEH, estaciones, boletines y Nubis Bot. El portal de estaciones ofrece descarga reciente y un canal para solicitar históricos. | Actualizar la decisión cercana a la siembra o al riego. | Área de vigencia, horizonte y desempeño para ese sitio. |
| Textura, pH, carbono, densidad y retención estimada | SoilGrids, cuadrícula de 250 m y seis intervalos de profundidad, más cartografía del MAGA. | Situar condiciones iniciales y explorar escenarios de reserva de agua. | Análisis de suelo, profundidad útil, compactación y drenaje. |
| Elevación, pendiente y posición en la ladera | SRTM de aproximadamente 30 m, complementado con recorrido y nivelación. | Reconocer áreas para investigar erosión y concentración de agua. | Surcos, caminos, aportes externos, terrazas e infiltración. |
| Cultivos previos, plagas, residuos, riego y labores | Registro del productor y observación. | Evaluar efectos de la transición y recursos requeridos. | Identificación sanitaria y cantidades cuando afecten la decisión. |
| Costos, precios y disponibilidad de recursos | Cotizaciones locales, registros de la finca y publicaciones del MAGA como referencia de mercado. | Comparar inversión, fechas de gasto y resultado anual con incertidumbre. | Precio pagado al productor, transporte, comprador, salarios y semilla disponible. |
| Objetivos productivos, comerciales y de conservación | Conversación con el finquero y registros de operación. | Determinar qué secuencias cumplen sus prioridades y compromisos. | Volumen y calidad requeridos, fechas de entrega, presupuesto, disponibilidad de trabajadores y tiempo de uso de cada lote. |

Fuentes para extraer las fichas y calcular agua: [ICTA, manual de frijol](https://www.icta.gob.gt/publicaciones/Frijol/Manual%20de%20producci%C3%B3n%20de%20frijol%20ICTA.pdf) · [ICTA, publicaciones de maíz](https://www.icta.gob.gt/publicacionesdemaiz) · [FAO 56, coeficientes por etapa](https://www.fao.org/4/x0490e/x0490e0b.htm) · [FAO 56, agua disponible y raíces](https://www.fao.org/4/x0490e/x0490e0e.htm).

Fuentes ambientales y su acceso: [NASA, IMERG](https://gpm.nasa.gov/data/imerg) · [NASA POWER, API diaria](https://power.larc.nasa.gov/docs/services/api/temporal/daily/) · [NASA POWER, procedencia y resolución](https://power.larc.nasa.gov/docs/methodology/) · [INSIVUMEH, estaciones y solicitud de información](https://insivumeh.gob.gt/variables_clima/) · [ISRIC, propiedades y profundidad de SoilGrids](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html) · [ISRIC, resolución de SoilGrids](https://docs.isric.org/globaldata/soilgrids/) · [MAGA, cartografía de suelos](https://geoportal.maga.gob.gt/casos-exito) · [USGS, SRTM](https://www.usgs.gov/centers/eros/science/usgs-eros-archive-digital-elevation-shuttle-radar-topography-mission-srtm).

Para mercado, los precios de La Terminal describen transacciones mayoristas. El precio de finca depende también de calidad, transporte y condiciones de compra. Preservar producto, unidad, mercado y mes al extraer una cifra. [MAGA, informe mensual de enero de 2026](https://precios.maga.gob.gt/archivos/mensuales/2026/01%20Informe%20De%20Precios%20Agropecuarios%20Mensual%20Enero%202026.pdf)

### Calidad y acceso que condicionan el uso

- Guardar cada parámetro junto con fuente, fecha, página, región, variedad, unidad, definición de etapa y rango. En el manual ICTA 2022, cuadro 1 de p. 8, Ligero figura con 29–30 días a floración y 64–70 a cosecha, mientras Altense figura con 55–60 y 115, respectivamente. Los valores representan referencias que se contrastan con la finca. [ICTA, cuadro de variedades](https://www.icta.gob.gt/publicaciones/Frijol/Manual%20de%20producci%C3%B3n%20de%20frijol%20ICTA.pdf)
- Conservar discrepancias entre publicaciones. El asesor encontró 95 días a cosecha para Hunapú en el manual 2022 y 120 en el boletín de julio de 2024. Para resolver el calendario, pedir la observación de esa variedad en la zona y consultar al ICTA. Un rango altitudinal publicado también describe adaptación observada y exige interpretación cuando el sitio queda cerca de un extremo. [ICTA, boletín de julio de 2024](https://www.icta.gob.gt/publicaciones%202024/boletines/Bolet%C3%ADn%20Julio%202024.pdf)
- Los modelos regionales aportan contexto. En la cordillera y las pequeñas parcelas, una medición a distinta profundidad o exposición puede justificar otro escenario. SoilGrids publica incertidumbre por propiedad. Sus estimaciones de nitrógeno total describen una reserva distinta del nitrógeno mineral disponible para una planta en una fecha. Registrar esta distinción al valorar fertilización. [ISRIC, propiedades e incertidumbre](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_01.html)
- La documentación de ISRIC declara pausada temporalmente su API REST. Para preparar datos de un piloto, usar recortes mediante WCS o archivos WebDAV según las vías documentadas y comprobar la descarga elegida. [ISRIC, opciones de acceso y estado del servicio](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_02.html)
- El proyecto contiene fuentes y conocimiento documental. En esta consulta se verificó documentación pública. Siguen pendientes la extracción completa del catálogo, la descarga de series para una parcela concreta y el contraste con registros de campo.

## Cómo comparar las secuencias

1. **Reconstruir la práctica actual.** Registrar fechas reales de los ciclos previos, variedades, rendimiento, costos, plagas y destino de residuos. Esa secuencia será la referencia para las alternativas.
2. **Generar alternativas realizables.** Proponer cultivos y variedades que el finquero pueda obtener y manejar en el tiempo que tiene acceso al terreno. Incluir una cobertura o un descanso cuando sea viable y tenga una función identificada.
3. **Comprobar condiciones de ejecución.** Contrastar calendario, adaptación regional, agua o riego, disponibilidad de semilla, presupuesto, trabajo y compromisos comerciales. Si falta un dato determinante, marcar la alternativa pendiente y explicar qué lo resolvería.
4. **Simular escenarios comparables.** Para el mismo lote y horizonte, ubicar emergencia, floración, llenado y cosecha en años históricos. Con parámetros suficientemente respaldados, llevar un balance diario del agua en raíces que considere lluvia, escorrentía, riego, evapotranspiración y drenaje. Mostrar sensibilidad a fechas y propiedades de suelo inciertas. [FAO 56, balance radicular](https://www.fao.org/4/x0490e/x0490e0e.htm)
5. **Explicar el resultado por dimensión.** Mostrar calendario de cosecha e ingresos, inversión, margen esperado con sus supuestos, exposición al déficit en etapas sensibles, intervalos con suelo descubierto y riesgos sanitarios respaldados. El finquero indica qué prioriza. Para proyectar rendimientos se requiere validar una relación entre agua, manejo y cosecha; un indicador de exposición por sí solo permite comparar riesgos.
6. **Evaluar después del ciclo.** Comparar lo previsto con siembra real, lluvia, floración y cosecha. Anotar si el productor cambió una decisión y cuál. Usar el resultado para revisar fechas, parámetros y supuestos.

Una salida hipotética sería «La alternativa B llega antes a cosecha y requiere menos inversión inicial. La alternativa A permite cumplir la fecha de entrega que acordó con su comprador. El riesgo de B cambia si las lluvias terminan antes o si su variedad tarda más de lo previsto». Las cifras se incorporarían al disponer de la parcela, las variedades y la serie verificadas.

## Cómo buscar impacto en Guatemala

Empezaría con un finquero que deba decidir el siguiente cultivo de una parcela y pueda aportar registros de los ciclos anteriores. La secuencia de maíz y frijol es una candidata para validar con él, acompañados de un extensionista si está disponible. Para escoger el primer caso importan el problema que quiere resolver, el margen de decisión y los datos de su finca. La investigación documental aporta contexto sobre dificultades de agua, semilla, inversión y comercialización en distintas poblaciones. [Investigación de productores del proyecto](../investigacion/productores-guatemala.md)

Para el primer caso, comparar la secuencia real con dos alternativas concretas, como ajustar variedad y ventana del frijol posterior al maíz o cambiar el orden de los cultivos en el horizonte acordado. Si el finquero ya cosechó el maíz, las opciones parten de esa situación real. Evaluar el uso de la tierra durante todo el horizonte, la disponibilidad de capital, el calendario de cosecha y la salida comercial.

Hay un antecedente guatemalteco con el cual coordinar: el MAGA comunica resultados de ZARC, que combina historia climática y suelos para analizar cultivos y ventanas de siembra, evaluado en 45 parcelas. La contribución propuesta del equipo sería hacer explícita la comparación de secuencias con el historial del lote, los objetivos del finquero, las restricciones de recursos y la incertidumbre de los datos. Conviene contrastarla con lo que ya entregan los extensionistas en el municipio elegido. [MAGA, resultados de ZARC, abril de 2026](https://guatemala.gob.gt/presentan-resultados-y-aporte-a-la-agricultura-familiar-de-la-herramienta-zarc/)

Antes de afirmar un beneficio, comprobar comprensión y posibilidad de actuar. Durante el piloto medir cosecha comercializable, costos y margen neto, agua de riego utilizada cuando corresponda y cobertura del suelo en puntos comparables. Registrar también pérdidas productivas y cumplimiento del calendario. Atribuir una mejora a la herramienta requiere además una comparación de campo que tenga en cuenta clima, suelo y manejo. La magnitud del impacto quedará abierta hasta esa evaluación.

Para café, conservar una consulta propia sobre humedad, floración y escorrentía, apoyada en los contactos del equipo. Su validación agronómica puede alimentar el conocimiento de agua del sistema. [Manual agroclimático del proyecto](manual-agroclimatico.md)
