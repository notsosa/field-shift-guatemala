# Handoff Técnico y Funcional · Motor Gráfico 2D/3D Multicapa (`graphics/`)

**Fecha de actualización:** 15 de noviembre de 2026  
**Proyecto:** Field Shift Guatemala — *NASA Space Apps Challenge 2026 (Field Shift: Adapting Farms with NASA Data)*  
**Módulo:** Visor Topográfico y Agroclimático 2D ⟷ 3D WebGL Ultra-HD ([`graphics/topo3d.html`](topo3d.html) y [`graphics/servidor_topo3d.py`](servidor_topo3d.py))

---

## 1. Resumen Ejecutivo de lo Construido

Durante esta fase de desarrollo se diseñó, validó y optimizó el **motor gráfico interactivo 2D/3D** para evaluar parcelas agrícolas en Guatemala con datos de observación de la Tierra de la NASA.

El módulo evolucionó desde una prueba comparativa de dos fuentes de elevación hasta convertirse en un **visor unificado de un solo punto de evaluación con soporte multicapa en vivo**, listo tanto para la **grabación del video oficial (30 s)** como para su **integración directa en la aplicación móvil y web**.

### Capacidades entregadas y verificadas:
1. **Motor WebGL Ultra-HD (`220 × 220` vértices = `95,922` triángulos)** con interpolación sub-píxel **Bicúbica Catmull-Rom ($4\times 4$)** sobre teselas de elevación NASA SRTM / AWS Terrarium (`z = 13` a `~19 m/px` y `z = 14` a `~9.5 m/px` para cuadros `≤ 3.5 km`).
2. **Cinco capas satelitales y agronómicas interactivas:**
   - `🌡️ Temperatura NASA (°C)` (`T2M_MAX`, `T2M`, `T2M_MIN` con corrección altitudinal de $-6.5\,^\circ\text{C}/1000\text{ m}$ e insolación por orientación de ladera).
   - `💧 Humedad del Suelo (%)` (`GWETROOT` y `GWETTOP` de NASA POWER modulados por acumulación topográfica en valles y drenaje por pendiente).
   - `⛰️ Elevación (m s.n.m.)`.
   - `📐 Pendiente y Escorrentía (%)`.
   - `🌱 Pisos Térmicos ICTA (Umbral 500 m s.n.m.)`.
3. **Selector Temporal Dual (*Slide Switch*):**
   - **📡 Modo Verificación en Tiempo Real (Últimos días):** Conectado al endpoint diario de NASA POWER (`/api/temporal/daily/point`), filtrando valores `-999` (en procesamiento) para mostrar automáticamente el **último pase satelital válido (`~hace 3 días`)** y una ventana deslizable de los últimos 14 días.
   - **📅 Modo Planificación de Siembra (Ciclo Anual):** Slider y botones para los 12 meses del año agrícola, diferenciando meses ya observados (`● Mes Observado`) de meses futuros (`◌ Proyección histórica NASA 2001–2025`).
4. **Indicador de Punto de Interés (`📍`) en 2D y 3D:**
   - Mira interactiva sobre la superficie 3D al mover el mouse y colocación directa del marcador `📍` con un clic sobre cualquier ladera o valle del modelo 3D (o en el mapa 2D), actualizando al instante el diagnóstico agroclimático y las variedades ICTA recomendadas para ese punto exacto.
   - Soporte para guardar múltiples puntos con nombre (`📌 Fijar`) y recentrar el área (`🎯 Centrar Cuadro`).
5. **Curvas de Escorrentía Hidrográfica 3D (Runge-Kutta 2) y Curvas de Nivel Cartográficas:**
   - Líneas de flujo curvas de 14 sub-pasos integradas con **RK2** sobre el gradiente real del terreno, adheridas al 100% a la superficie 3D, con degradado cian/blanco, punta de flecha direccional y oclusión por horizonte (`occGrid` + filtro de normal de cámara) para que nunca atraviesen cerros frontales.
   - Curvas de nivel anti-aliasadas por hardware (`OES_standard_derivatives`) cada `25 m`, `50 m` y `200 m` con supresión de manchas en llanuras planas.
6. **Cuadro de Dimensiones Personalizables (`0.5 km` a `10 km`):**
   - Dos cuadros de texto (`Ancho Este-Oeste` × `Largo Norte-Sur`) que aceptan cualquier valor entre **`0.5 km` y `10.0 km`**, actualizando tanto el rectángulo en el mapa 2D como la proporción física rectangular de la malla 3D.
7. **Slider de Transición Continua `🗺️ 2D Plano ⟷ ⛰️ 3D Relieve`:**
   - Transforma suavemente la cámara desde una proyección cartográfica 2D cenital (`90°`, **Norte arriba**, relieve plano) hasta la vista 3D volumétrica inclinada.

---

## 2. Decisiones Técnicas Acordadas con el Usuario

| Decisión | Opciones evaluadas | Elección final y justificación |
|---|---|---|
| **Motor de elevación principal** | **Opción 1:** NASA SRTM / AWS Terrarium (`z=13–14` vía API de teselas PNG)<br>**Opción 2:** JAXA ALOS AW3D30 GeoTIFF local / COG | **Opción 1 (NASA SRTM / Terrarium)** como motor principal en el frontend. Funciona en cualquier coordenada sin requerir gigabytes de archivos GeoTIFF locales, carga en `< 0.5 s` en aplicaciones móviles y permite superponer múltiples capas climáticas en WebGL. Se conserva `servidor_topo3d.py` con soporte JAXA AW3D30 COG bajo demanda como respaldo técnico. |
| **Disposición visual de pantalla** | Comparador doble (Punto A vs. Punto B) vs. **Visor único de alta resolución** | **Visor único a pantalla completa** con panel lateral izquierdo (mapa 2D de ubicación + tarjetas de métricas + recomendación ICTA) para evaluar un punto de interés con máxima claridad visual. |
| **Manejo de fechas futuras (ej. Diciembre)** | Mostrar solo promedios climáticos sin distinción vs. **Separar Tiempo Real y Planificación** | **Slide Switch de 2 modos:** Modo *Verificación en Tiempo Real* (acotado estrictamente a fechas pasadas observadas hasta hace ~3 días) y Modo *Planificación de Siembra* (12 meses con etiqueta explícita de proyección histórica 2001–2025 para meses futuros). |
| **Corrección de `T2M_MAX` mensual en NASA POWER** | Usar `T2M_MAX` crudo del endpoint `/climatology/point` vs. **Media de máximas diarias** | El endpoint `/climatology/point` de NASA POWER reporta en `T2M_MAX` el récord extremo absoluto de 30 años (ej. `33.6 °C` en diciembre) en vez del promedio mensual de máximas diarias (`24.7 °C`). Se corrigió calculando la máxima diurna media mensual a partir de `T2M` + los desplazamientos diurnos reales (`DIURNAL_MAX_OFFSET`) extraídos de la serie diaria local 2001–2025 de Chiquimula. |
| **Oclusión y opacidad 3D** | Proyección con `+z2` y tarjetas translúcidas vs. **Z-buffer `-z2` sólido + horizonte 2D** | En clip-space de WebGL (`gl.LESS`), los puntos más cercanos a la cámara (`z2 > 0`) deben mapearse a valores negativos (`gl_Position.z = -z2 * 0.25`) para ocluir al 100% las laderas traseras. Además, se añadió una malla de horizonte (`occGrid` de `220 × 150`) para ocultar curvas de escorrentía y etiquetas cardinales detrás de las montañas. |

---

## 3. Cómo Ejecutar el Entorno Local

```bash
# Desde la raíz del repositorio:
python graphics/servidor_topo3d.py --port 8090
```

Abrir en el navegador: **`http://localhost:8090`**

- Cualquier edición realizada sobre [`graphics/topo3d.html`](topo3d.html) se refleja inmediatamente al recargar el navegador (`Ctrl + F5`), sin necesidad de reiniciar el proceso de Python.

---

## 4. Arquitectura Interna de `graphics/topo3d.html`

El archivo [`graphics/topo3d.html`](topo3d.html) está estructurado en 8 bloques modulares claramente comentados para facilitar su mantenimiento o extracción a componentes (React / Vue / Flutter WebView):

1. **Bloque 1 — Configuración y Datos Base Embebidos (`DEFAULT_NASA_CLIM` y `FALLBACK_RECENT_DAYS`):**
   - Contiene la serie climática mensual 2001–2025 y los últimos 14 días observados de la parcela piloto en Chiquimula (`datos/power/chiquimula_power_diario_20010101_20251231.csv`), garantizando que el visor funcione incluso **sin conexión a internet (modo offline en campo)**.
2. **Bloque 2 — Mapa 2D Leaflet (`boxRect2D` + `poiMarker2D`):**
   - Sincroniza el rectángulo verde de dimensiones `widthKm × heightKm` y el marcador naranja del Punto de Interés con la malla 3D.
3. **Bloque 3 — Cliente en Vivo de NASA POWER API (`fetchNasaPowerData`):**
   - Consulta en paralelo `/api/temporal/climatology/point` y `/api/temporal/daily/point` para cualquier coordenada seleccionada, con caché en memoria por celda (`0.01°`).
4. **Bloque 4 — Motor DEM de Súper-Resolución y Trazador Hidrológico RK2 (`fetchHighResTerrariumBox`):**
   - Descarga teselas Terrarium (`z=13` o `z=14`), aplica interpolación bicúbica Catmull-Rom, suavizado gaussiano separable en 2 pasos, cálculo exacto de derivadas parciales (`dz/dx`, `dz/dy` ajustadas por `cellMX` y `cellMY`) e integración Runge-Kutta de 2.º orden para generar las curvas de escorrentía 3D (`streamlines`).
5. **Bloque 5 — Modelo Agroclimático Espacial (`computeClimateFields`):**
   - Combina la serie temporal activa (día observado o mes de planificación) con la topografía 3D para generar los campos `tempField` y `moistField` sobre los `48,400` vértices (`220 × 220`).
6. **Bloque 6 — Motor WebGL y Shaders GLSL (`VS_SRC`, `FS_SRC`, `getViewTransform`, `renderScene`):**
   - Renderiza los `95,922` triángulos por GPU con iluminación difusa + hemisférica, curvas de nivel cartográficas de 3 niveles (`25 m`, `50 m`, `200 m`), interpolación continua `2D ⟷ 3D` (`state.morph3D`) y el HUD 2D con oclusión por horizonte.
7. **Bloque 7 — Diagnóstico Agronómico por Punto de Interés (`updateSidebarMetrics`):**
   - Evalúa las condiciones exactas en `state.poiRow, state.poiCol` y genera la recomendación de variedades ICTA y prácticas de conservación de suelo.
8. **Bloque 8 — Interacción 2D/3D y Controles (`pickNearestVertex`, dimensiones de cuadro y slider `2D ⟷ 3D`):**
   - Selección de vértices en 3D con prioridad de superficie frontal (`score = d2 - pt.depth * 180`), validación de dimensiones (`0.5` a `10.0 km`) y animación `easeInOutCubic` entre vista 2D y 3D.

---

## 5. Próximos Pasos Sugeridos para Integración Final

1. **Conectar el Punto de Interés (`📍`) con el Comparador de Rotaciones (18 cultivos):**
   - Cuando el finquero coloca el indicador `📍` en su lote dentro del visor 2D/3D, el objeto `state` ya expone en tiempo real:
     - `state.poiLat`, `state.poiLon`
     - `elev` (`m s.n.m.`), `slope` (`%`), `tempField` (`°C` mensual y diaria), `moistField` (`%`)
   - Estos valores pueden pasarse directamente al motor de puntuación de rotaciones ([`conocimiento/datos-y-comparacion-de-rotaciones-guatemala.md`](../conocimiento/datos-y-comparacion-de-rotaciones-guatemala.md)) para filtrar qué secuencias de los 18 cultivos cumplen los umbrales térmicos, hídricos y de pendiente en ese lote específico.
2. **Traducción de etiquetas clave a idiomas mayas (`diccionarios/`):**
   - Incorporar un selector de idioma en el encabezado para alternar los diagnósticos entre Español, Inglés (requerido para los jueces globales de Space Apps) y términos agrícolas en `k'iche'`, `q'eqchi'`, `kaqchikel` y `mam`.
3. **Publicación en GitHub Pages:**
   - Al ser [`graphics/topo3d.html`](topo3d.html) un archivo estático autocontenido, puede publicarse directamente desde la rama `main` en GitHub Pages (`https://notsosa.github.io/field-shift-guatemala/graphics/topo3d.html`) para incluir el enlace público en la página oficial de entrega del proyecto.
