# Dashboard Topográfico y Agroclimático 2D/3D · Field Shift Guatemala (`graphics/dashboard/`)

Paquete completo y consolidado del visor web interactivo **2D ⟷ 3D en WebGL Ultra-HD (`220 × 220`)** alineado con el sistema de diseño Cupertino de **`app/V01`** (*Field Shift: Adapting Farms with NASA Data*).

Combina relieve satelital **NASA SRTM / AWS Terrarium** (`z=13–14`), variables climáticas en vivo y climatología histórica de **NASA POWER**, evaluación hidrológica de **precipitación (`PRECTOTCORR`)**, selector explícito de **Riego Natural (Secano)** vs **Riego por Goteo**, y detección de **cuerpos de agua cercanos** (OpenStreetMap Overpass API + vaguadas topográficas SRTM).

---

## 1. Contenido de esta carpeta

| Archivo | Descripción |
|---|---|
| [`index.html`](index.html) | Dashboard web autocontenido (`HTML + CSS + WebGL 1.0 + Canvas 2D`): 6 capas satelitales/agronómicas, modos claro/oscuro y tarjeta móvil `app/V01`, anillos y barras interactivas de 14 días, mapa Leaflet 2D sincronizado, escorrentía 3D RK2, selector Tiempo Real / Planificación y análisis hídrico natural/goteo. |
| [`servidor_dashboard.py`](servidor_dashboard.py) | Servidor HTTP local sin dependencias externas (`Python 3` stdlib) que sirve `index.html` en `http://localhost:8090` (sin caché) y reutiliza [`../servidor_topo3d.py`](../servidor_topo3d.py) para el endpoint auxiliar `/api/aw3d30`. |
| [`DOCUMENTACION_TECNICA.md`](DOCUMENTACION_TECNICA.md) | Arquitectura de bloques, fuentes satelitales y APIs, modelos matemáticos/GLSL, sistema de diseño Cupertino (`app/V01/lib/ui/tema.dart` y `graficos.dart`) y supuestos hidrológicos. |
| [`BITACORA_Y_AUDITORIA.md`](BITACORA_Y_AUDITORIA.md) | Historial completo de decisiones (Opción 1 vs Opción 2, transición WebGL, integración NASA POWER y cuerpos de agua), más el reporte de auditoría y verificación headless. |
| [`verificar_dashboard.py`](verificar_dashboard.py) | Script automatizado de validación de contratos DOM/JS, sintaxis Python, paridad con [`../topo3d.html`](../topo3d.html) y prueba opcional WebGL en Chrome headless. |

---

## 2. Inicio rápido en `localhost`

No requiere `npm` ni instalar paquetes `pip` adicionales. Desde la raíz del repositorio:

```bash
python graphics/dashboard/servidor_dashboard.py --port 8090
```

Luego abre en el navegador: **`http://localhost:8090`**

### Despliegue estático (GitHub Pages / App móvil `WebView`)
El archivo [`index.html`](index.html) ejecuta todo el motor DEM, NASA POWER, Overpass y WebGL directamente en el navegador del cliente (sin requerir backend para las funciones principales), por lo que puede publicarse en GitHub Pages o incrustarse en un `WebView` móvil.

---

## 3. Funcionalidades del Dashboard

1. **Seis capas interactivas en 2D y 3D:**
   - `💧 Agua Suelo (%)`: humedad espacializada desde `GWETROOT` y `GWETTOP`.
   - `🌧️ Precipitación (mm/día)`: variable `PRECTOTCORR` de NASA POWER con escala dedicada en el *fragment shader* WebGL (`uLayerMode == 5`) y acumulado de 14 días.
   - `🌡️ Temperatura (°C)`: `T2M_MAX`, `T2M` o `T2M_MIN` con ajuste altitudinal ($-6.5\,^\circ\text{C}/1000\text{ m}$) e insolación por orientación de ladera.
   - `⛰️ Elevación (m s.n.m.)`: hipsometría dinámica ajustada al mínimo y máximo real del bloque DEM.
   - `📐 Pendiente / Escorrentía (%)`: gradiente porcentual y umbrales de infiltración/curvas a nivel.
   - `🌱 Pisos ICTA (500 m)`: cota crítica de `500 m s.n.m.` para selección de variedades de frijol y maíz.
2. **Selector de régimen de agua (`Secano` vs `Goteo`):**
   - **🌧️ Riego Natural (por defecto):** evalúa lluvia de NASA POWER, porcentaje de infiltración topográfica en función de la pendiente y déficit pluvial sin asumir infraestructura instalada.
   - **💧 Riego por Goteo:** calcula lámina faltante en turnos de referencia de `6 mm` y evalúa captación desde el cuerpo de agua más cercano (gravedad vs bombeo según `ΔZ`).
3. **Cuerpos de agua cercanos y distancia de captación:**
   - Consulta vías de agua y reservorios en **OpenStreetMap Overpass API** (`river`, `stream`, `canal`, `water`) y extrae automáticamente vaguadas principales del relieve SRTM (`extractTopographicWaterChannels`), dibujándolas en 2D, 3D y calculando distancia horizontal y desnivel `ΔZ` respecto al punto seleccionado (`📍`).
4. **Selector temporal dual:**
   - **📡 Tiempo Real (últimos 14 días):** último pase válido de NASA POWER (~3 días de rezago) con barra deslizable y gráfica interactiva `BarrasAgua`.
   - **📅 Planificación (12 meses):** ciclo mensual multianual distinguiendo meses observados y proyección climatológica.
5. **Vista `2D Plano ⟷ 3D Relieve`, POIs y cuadro personalizable (`0.5–10 km`):**
   - Permite alternar entre modo **Expandido**, **Tarjeta App Móvil (`V01`)**, tema **Claro (`#F4F4F1`) / Oscuro (`#0B0C0B`)**, fijar múltiples POIs y definir ancho × largo del área analizada.

---

## 4. Verificación local

```bash
python graphics/dashboard/verificar_dashboard.py
```
