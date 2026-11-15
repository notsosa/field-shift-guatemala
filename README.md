# Field Shift Guatemala

Documentación de trabajo del equipo de Ciudad de Guatemala para el reto **Field Shift: Adapting Farms with NASA Data**, de NASA Space Apps Challenge 2026.

El proyecto busca ayudar al finquero a comparar secuencias de cultivos en una misma parcela mediante observaciones de la Tierra de NASA, información del suelo, características de los cultivos y sus objetivos de producción, rentabilidad, agua y conservación.

**Empezá por el [handoff del proyecto](conocimiento/datos-y-comparacion-de-rotaciones-guatemala.md).** Reúne las decisiones acordadas, el catálogo inicial de 18 cultivos, las fuentes de datos, los requisitos de entrega verificados y las preguntas pendientes.

## Documentos de apoyo

| Documento | Contenido |
|---|---|
| [Manual agroclimático](conocimiento/manual-agroclimatico.md) | Agua, suelo, clima, rotaciones y manejo del café, con referencias y ejemplos. |
| [Observaciones NASA](conocimiento/observaciones-nasa.md) | Interpretación de lluvia, humedad, relieve y vegetación, con resolución y límites de los productos. |
| [Investigación de productores](investigacion/productores-guatemala.md) | Dificultades documentadas en Guatemala, población estudiada, metodología y alcance. |
| [Conversaciones con cafetaleros](investigacion/testimonios-2026-11-11.md) | Apuntes anónimos compartidos por el equipo y preguntas por aclarar. |

## Gestión del proyecto

| Documento | Contenido |
|---|---|
| [Brief](proyecto/Brief.md) · [Brief 2](proyecto/Brief2.md) | Problemática, evidencia y propuesta de valor. |
| [Diseño de la app v2](docs/superpowers/specs/2026-11-14-field-shift-web-design.md) | Enfoque, datos, modelo y app. |
| [Tareas](proyecto/tasks.md) | Tablero de tareas para la entrega, con estatus y responsable. |
| [Decisiones](proyecto/decisions.md) | Decisiones pendientes, opciones y recomendación. |
| [Datasets](proyecto/datasets.md) | Datos que usa el proyecto, propósito, estado y enlace de acceso. |
| [Motor gráfico 2D/3D](graphics/README.md) · [Handoff gráfico](graphics/HANDOFF.md) | Visor topográfico y agroclimático WebGL Ultra-HD (`localhost:8090`), servidor local y guía de handoff. |
| [Diccionarios](diccionarios/README.md) | Vocabulario agrícola y gramática básica de k'iche', q'eqchi', kaqchikel y mam para traducir la app. |

## Estructura del repositorio

| Carpeta | Contenido |
|---|---|
| `conocimiento/`, `investigacion/` | Documentación agronómica, de datos NASA y de productores. |
| `proyecto/` | Brief, tareas, decisiones y catálogo de datasets. |
| `docs/` | Documentos de diseño de la app. |
| `diccionarios/` | Idiomas mayas para la interfaz. |
| `scripts/` | Descarga de datos: NASA POWER, CHIRPS/IMERG (ClimateSERV), JAXA (GSMaP, AW3D30), SoilGrids, ESA WorldCover y MAGA. |
| `graphics/` | Motor gráfico interactivo 2D ⟷ 3D WebGL Ultra-HD (`topo3d.html`), servidor local (`servidor_topo3d.py`), documentación (`README.md`) y handoff (`HANDOFF.md`). |
| `app/` | App Android en Flutter, una carpeta por versión. `app/V01/`: registro de parcela y plantación, registro semanal y recomendación de riego sin conexión (ver `app/V01/README.md`). |
| `datos/` | Datos descargados para la parcela piloto provisional, cada uno con su `.meta.json` de procedencia. |

Para correr los scripts: `py -3.12 -m venv .venv`, `.venv/Scripts/python -m pip install -r requirements.txt` y luego `.venv/Scripts/python scripts/<script>.py --lat <lat> --lon <lon> --nombre <parcela>`. `descargar_power.py` funciona sin instalar nada.

## Estado del trabajo

La documentación define una propuesta de comparación de rotaciones y un catálogo de candidatos. Queda pendiente seleccionar la finca piloto, precisar variedades y calendarios, reunir los datos de la parcela, implementar el prototipo y validar sus resultados. El equipo también quiere explorar decisiones de agua y manejo con cafetaleros.

Las cifras conservan sus fuentes y poblaciones de referencia. Los ejemplos hipotéticos se identifican en el texto.

## Continuar el proyecto

Para incorporar a un compañero o retomar en otro chat, compartir el handoff y pedir que se lean las secciones pertinentes de los documentos de apoyo. Al tomar una decisión, actualizar el handoff y registrar los supuestos, las fuentes y los pendientes que cambien.

El proyecto incluye dos perfiles reutilizables de Codex en [.codex/agents](.codex/agents): [asesor agroclimático](.codex/agents/asesor_agroclimatico.toml) e [investigador de productores](.codex/agents/investigador_de_productores.toml).

Actualizado el 14 de noviembre de 2026.
