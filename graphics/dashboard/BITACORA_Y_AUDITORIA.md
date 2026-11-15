# Bitácora de Desarrollo y Auditoría · Dashboard Field Shift

## 1. Evolución Cronológica del Dashboard

1. **Arquitectura de relieve y comparador inicial (`localhost:8090`):**
   - Se evaluaron dos vías de obtención de elevación: **Opción 1** (100% cliente sobre teselas **AWS Mapzen Terrarium / NASA SRTM**) frente a **Opción 2** (servidor local Python con lectura de `chiquimula_aw3d30_dsm.tif` y descarga HTTP Range de **JAXA ALOS AW3D30 v4.1 COG**).
   - Se eligió **Opción 1** como motor principal por su portabilidad en WebView móvil, publicación estática sin backend obligatorio y fluidez para demostración en video, conservando `/api/aw3d30` en Python como respaldo técnico.
2. **Motor WebGL Ultra-HD (`220 × 220`) e integración NASA POWER en vivo:**
   - Se escaló la malla hasta `220 × 220` (`48,400` vértices), con remuestreo bicúbico **Catmull-Rom**, suavizado gaussiano en dos pasadas, curvas de nivel por derivadas GLSL (`25 m / 50 m / 200 m`), corrección del Z-buffer (`-z2 * 0.25`) y líneas de escorrentía 3D **RK2** de 14 pasos con oclusión por horizonte (`occGrid`).
   - Se unificó la pantalla en un solo punto de interés interactivo (`📍`) con cuadro configurable (`0.5–10 km`), transición continua `2D Plano ⟷ 3D Relieve`, modo **Tiempo Real (14d)** y modo **Planificación (12 meses)** con corrección de máximas diurnas (`DIURNAL_MAX_OFFSET`).
3. **Alineación con `app/V01`, Riego Natural vs Goteo, Lluvia y Cuerpos de Agua:**
   - Se adoptó la paleta Cupertino claro/oscuro de `app/V01/lib/ui/tema.dart`, el modo tarjeta móvil y los gráficos `AnilloAgua` / `BarrasAgua` de `graficos.dart`.
   - Tras revisar el supuesto inicial de turnos de `6 mm` de riego por goteo, se incorporó el conmutador explícito **🌧️ Riego Natural (Secano)** vs **💧 Riego por Goteo**, la capa WebGL de **Precipitación (`PRECTOTCORR`)** y la detección combinada de **cuerpos de agua cercanos** (OpenStreetMap Overpass + vaguadas SRTM) con distancia horizontal y desnivel `ΔZ`.

---

## 2. Resumen de Auditoría Estática y de Runtime (`2026-11-15`)

Se ejecutó inspección de código, verificación estática de contratos DOM/JS y pruebas de ejecución en **Chrome Headless con WebGL SwiftShader** tanto en modo offline puro como con simulación de teselas Terrarium, NASA POWER y Overpass API *(necesario en entorno sandbox sin salida a internet)*.

### Hallazgos corregidos antes del push a `graphics/dashboard/`

| Severidad | Hallazgo detectado | Corrección aplicada |
|---|---|---|
| **ALTO** | `evaluateClosestWaterBody()` guardaba `state.closestWater` con propiedades planas (`name`, `source`, `distMeters`, `deltaZ`, `pt`), pero `updateSidebarMetrics()` y `renderAppV01Charts()` buscaban `state.closestWater.wb`. En consecuencia, la tarjeta `#m-water-dist` mostraba `"Sin cauce"` y `#v01-water-detail` mostraba `"Cauce estacional"` aunque el río existiera en el mapa 2D y 3D. | Lectura directa de `cw.name`, `cw.source`, `cw.distMeters` y `cw.deltaZ` en `renderAppV01Charts()` y `updateSidebarMetrics()`. |
| **MEDIO** | `renderAppV01Charts()` buscaba el ID inexistente `v01-crop-subtitle` en lugar de `v01-mode-subtitle`, congelando el subtítulo al alternar entre Secano y Riego por Goteo. | Actualizado a `document.getElementById("v01-mode-subtitle")` con texto dinámico para ambos modos. |
| **MEDIO** | `#v01-bars-sub` permanecía fijo en `"🌧️ Lluvia 14d: — mm"` porque no se actualizaba desde JS. | Actualizado en `renderAppV01Charts()` con `rain14d.toFixed(1)` mm. |
| **MEDIO** | `renderScene()` evaluaba `wb.type === "river" ...` (siempre `undefined`), impidiendo destacar ríos principales en 3D. | Cambiado a `Boolean(wb.isPermanent)` acorde con el esquema real de `waterBodies`. |
| **MEDIO** | Sin conexión al CDN de Leaflet (`unpkg.com`), `L.map(...)` lanzaba `ReferenceError: L is not defined` y detenía toda la carga inicial; además `loadTileImage()` rechazaba un `Event` provocando `"Error al cargar datos: undefined"`. | Añadido *shim* offline seguro para Leaflet en `#map2d` y rechazo explícito con `new Error(...)` en `loadTileImage()`. |
| **BAJO** | `updateLegendForLayer("elev")` mostraba etiquetas estáticas `"300 m"` / `"1,350 m"` aunque el shader sí normaliza sobre `[uMinElev, uMaxElev]`. | Sincronizado con `state.dem.min_elev` y `state.dem.max_elev` al cambiar de capa y al cargar el DEM. |

### Estado verificado tras las correcciones
- Verificación estática (`verificar_dashboard.py`): **0 IDs rotos**, **0 referencias a `.wb` o `wb.type`**, paridad exacta con `graphics/topo3d.html`, compilación limpia de `servidor_dashboard.py`.
- Ejecución offline cruda en Chrome Headless: **0 errores JS no capturados**, aviso limpio en `#map2d` y mensaje legible de error DEM cuando no hay internet.
- Ejecución interactiva con DEM sintético + mocks POWER/Overpass en Chrome Headless + SwiftShader: **0 errores JS**, enlace GLSL válido (`glError: 0`), actualización real de `#m-water-dist` (`873 m` → `68 m` al mover POI), subtítulo dinámico de Secano/Goteo y acumulado de `49.0 mm` en `#v01-bars-sub`.
