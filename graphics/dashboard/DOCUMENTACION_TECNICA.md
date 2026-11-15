# Documentación Técnica y Arquitectura · Dashboard Field Shift (`graphics/dashboard/`)

## 1. Arquitectura General del Frontend ([`index.html`](index.html))

El archivo está organizado en bloques autocontenidos dentro de un único documento web sin bundler externo:

1. **Sistema de diseño Cupertino (`app/V01`):**
   - Variables CSS para tema claro (`#F4F4F1` fondo, `#FFFFFF` tarjeta, `#1D7A4C` verde acento, `#2F6FB5` azul, `#B26A00` ámbar, `#C2392B` rojo) y oscuro (`#0B0C0B`, `#191B1A`, `#3DD68C`, `#6CB0FF`, `#FFB84D`, `#FF7A6B`), alineadas con `app/V01/lib/ui/tema.dart` y tipografía `Inter`.
   - Dos disposiciones responsivas (`data-layout="split"` escritorio y `data-layout="mobile"` simulador móvil).
2. **Datos base embebidos (`DEFAULT_NASA_CLIM`, `FALLBACK_RECENT_DAYS`):**
   - Serie climática de respaldo de Chiquimula (`2001–2025`) para mostrar valores válidos si la consulta en vivo a NASA POWER falla o tarda.
3. **Mapa 2D (`Leaflet`) + Resguardo offline:**
   - Sincroniza el rectángulo del cuadro (`boxRect2D`), punto central (`centerDot`), marcador activo (`poiMarker2D`), POIs fijados (`savedMarkersGroup`) y cuerpos de agua (`waterBodiesGroup2D`).
   - Si el CDN de `unpkg.com` no está disponible, se activa un *shim* seguro en `#map2d` para evitar `ReferenceError: L is not defined` y mantener operativo el motor WebGL.
4. **Cuerpos de agua (`extractTopographicWaterChannels` + `fetchWaterBodiesForBox`):**
   - Consulta `https://overpass-api.de/api/interpreter` (`out geom 12` dentro del bounding box) para `waterway~"river|stream|canal"` y `natural="water"`.
   - Extrae cauces/vaguadas principales del propio DEM (`extractTopographicWaterChannels`) y los combina como respaldo o complemento (`evaluateClosestWaterBody()`).
   - Calcula distancia euclidiana local en metros (`distMeters`) y desnivel `deltaZ = round(poiElev - waterElev)` para clasificar factibilidad por gravedad (`deltaZ <= 2` / `<= 3`) frente a bombeo.
5. **Cliente NASA POWER (`fetchNasaPowerData`):**
   - Petición en paralelo a `/api/temporal/climatology/point` y `/api/temporal/daily/point` con parámetros `T2M`, `T2M_MAX`, `T2M_MIN`, `RH2M`, `PRECTOTCORR`, `GWETTOP` y `GWETROOT`.
   - En climatología mensual aplica los desplazamientos diurnos `DIURNAL_MAX_OFFSET` / `DIURNAL_MIN_OFFSET` sobre `T2M` para evitar usar récords extremos absolutos multianuales como máxima diaria promedio.
   - Incluye caché en memoria por celda redondeada a `0.01°` y tope superior de año `2025` para alinearse con el escenario de evaluación del proyecto.
6. **Motor DEM WebGL `220 × 220` (`fetchHighResTerrariumBox`):**
   - Descarga teselas RGB **Terrarium** desde `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png` usando `z = 14` (`~9.5 m/px`) cuando el lado máximo del cuadro es `<= 3.5 km` y `z = 13` (`~19 m/px`) hasta `10 km`.
   - Decodificación por canal:
     $$\text{elev} = \left(R \cdot 256 + G + \frac{B}{256}\right) - 32768$$
   - Remuestreo bicúbico **Catmull-Rom $4\times 4$** y 2 pasadas de suavizado gaussiano separable (`0.24 / 0.52 / 0.24`) para eliminar artefactos de compresión.
   - Cálculo de gradientes ($\partial z/\partial x$, $\partial z/\partial y$), pendiente porcentual, normales unitarias e insolación por orientación (`aspect`).
7. **Hidrología superficial y shaders GLSL (`VS_SRC`, `FS_SRC`, `renderScene`):**
   - Integración **Runge-Kutta de orden 2 (RK2)** de `14` pasos sobre el campo descendente del DEM (`sampleSurfaceUV`) para generar curvas de escorrentía 3D (`streamlines`).
   - *Vertex shader* con proyección continua `2D Plano ⟷ 3D Relieve` (`uMorph3D`) y mapeo `gl_Position.z = -z2 * 0.25` para oclusión correcta en `gl.LESS`.
   - *Fragment shader* con extensión `GL_OES_standard_derivatives` para dibujar curvas de nivel cada `25 m`, `50 m` y `200 m` con ancho constante en pantalla, más 6 rampas de color (`rampTemp`, `rampMoist`, `rampElev`, `rampSlope`, `rampIcta`, `rampRain`).
   - *Canvas* 2D superpuesto (`#hud-main`) con *Z-grid* de oclusión por horizonte (`occGrid`), línea de captación punteada, etiqueta flotante de POI y rosa de rumbos.
8. **Gráficos `app/V01` y diagnóstico agronómico (`renderAppV01Charts`, `updateSidebarMetrics`):**
   - Redibuja los componentes visuales `AnilloAgua` (`#v01-ring-canvas`) y `BarrasAgua` (`#v01-bars-canvas`, últimos 14 días con gota azul cuando `PRECTOTCORR >= 1.0 mm`), inspirados en `app/V01/lib/ui/graficos.dart`.

---

## 2. Fórmulas Agronómicas y Supuestos del Visor

- **Temperatura por píxel (`computeClimateFields`):**
  $$T_{\text{píxel}} = T_{\text{NASA}} - 0.0065 \cdot (\text{elev} - \text{elev}_{\text{ref}}) + \text{insolación} \cdot 1.65$$
- **Precipitación espacializada (`rainField`):**
  $$P_{\text{píxel}} = \max\big(0,\; P_{\text{NASA}} \cdot (1 + (\text{elev} - \text{elev}_{\text{ref}}) \cdot 0.00022)\big)$$
- **Infiltración topográfica heurística (`renderAppV01Charts`):**
  $$\eta_{\text{infil}} = \text{clamp}(0.92 - 0.011 \cdot \text{pendiente}(\%),\; 0.35,\; 0.95)$$
- **Reserva visual de agua disponible (`reserva`):**
  $$\text{reserva} = \text{clamp}\left(\frac{\text{humedad}(\%) - 15}{65},\; 0.05,\; 1.0\right)$$
  *(Aproximación espacial visual para respuesta inmediata en WebGL/Canvas sobre un bloque de 48,400 nodos; el balance hídrico diario formal ET₀/K_c por cultivo se ejecuta en la app Flutter `app/V01/` y en `auditorias/`).*

---

## 3. Servidor Auxiliar Python ([`servidor_dashboard.py`](servidor_dashboard.py))

- Utiliza únicamente librería estándar (`http.server`, `struct`, `zlib`, `urllib`, `concurrent.futures`).
- Reutiliza [`../servidor_topo3d.py`](../servidor_topo3d.py) para exponer `/api/aw3d30`, leyendo directo desde `datos/relieve/chiquimula_aw3d30_dsm.tif` o bajo demanda desde bloques 256×256 de JAXA ALOS AW3D30 v4.1 COG cacheados en `datos/relieve/jaxa_cog_cache/`.

---

## 4. Limitaciones Conocidas a Considerar

- La consulta Overpass limita `out geom 12` y descarta vértices fuera del recorte rectangular antes de verificar `pts.length >= 2`, por lo que cauces con menos de dos nodos internos en el cuadro pueden omitirse del resultado OSM (quedando cubiertos por las vaguadas topográficas SRTM).
- `fetchNasaPowerData` fija como techo el año `2025` para mantener consistencia con las auditorías del proyecto.
- En modo **Planificación**, el campo `rain14dMm` y las 14 barras siguen mostrando la serie reciente de 14 días reales mientras la superficie 3D proyecta el mes seleccionado.
