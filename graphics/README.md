# Motor Gráfico 2D/3D Multicapa (`graphics/`) · Field Shift Guatemala

Visor topográfico y agroclimático interactivo **2D ⟷ 3D en WebGL Ultra-HD (`220 × 220`)** diseñado para **Field Shift Guatemala** (*NASA Space Apps Challenge 2026 — Field Shift: Adapting Farms with NASA Data*).

Permite al agricultor y al equipo técnico evaluar cualquier parcela o valle de Guatemala en un **cuadro personalizable desde `0.5 × 0.5 km` hasta `10 × 10 km`**, combinando relieve satelital de alta resolución, datos observados en cuasi-tiempo real y climatología de 25 años de **NASA POWER**, curvas de escorrentía hidrográfica 3D y umbrales agronómicos de **ICTA / MAGA**.

---

## Tabla de contenidos

1. [Inicio rápido (Localhost y Web Estática)](#1-inicio-rápido-localhost-y-web-estática)
2. [Archivos de esta carpeta](#2-archivos-de-esta-carpeta)
3. [Características principales del visor](#3-características-principales-del-visor)
4. [Fuentes de datos satelitales y APIs en vivo](#4-fuentes-de-datos-satelitales-y-apis-en-vivo)
5. [Modelos matemáticos y de renderizado](#5-modelos-matemáticos-y-de-renderizado)
6. [Controles de interfaz](#6-controles-de-interfaz)
7. [Integración con App Móvil y Video de 30s](#7-integración-con-app-móvil-y-video-de-30s)

---

## 1. Inicio rápido (Localhost y Web Estática)

El motor gráfico no requiere instalar paquetes externos (`pip`) ni compiladores de Node.js. Funciona directamente con la librería estándar de Python 3.

```bash
# Desde la raíz del repositorio:
python graphics/servidor_topo3d.py --port 8090
```

Luego abre en el navegador:

👉 **`http://localhost:8090`**

> **Nota para despliegue estático (GitHub Pages / WebView móvil):**
> El archivo [`topo3d.html`](topo3d.html) es **100% autónomo (standalone)** cuando utiliza el motor principal (*Opción 1: NASA SRTM / AWS Terrarium + NASA POWER API*), por lo que puede alojarse directamente en **GitHub Pages**, **Netlify** o incrustarse dentro de un `WebView` en **Android / iOS** sin requerir un backend propio.

---

## 2. Archivos de esta carpeta

| Archivo | Propósito |
|---|---|
| [`topo3d.html`](topo3d.html) | Aplicación web interactiva completa: motor WebGL 2D/3D (`220 × 220` vértices = `95,922` triángulos), shaders GLSL de iluminación y curvas de nivel cartográficas, integración en vivo con NASA POWER API, trazador RK2 de curvas de escorrentía e interfaz de diagnóstico ICTA/MAGA. |
| [`servidor_topo3d.py`](servidor_topo3d.py) | Servidor HTTP ligero en Python puro (`http.server` + `struct` + `zlib`) que sirve `topo3d.html` en `http://localhost:8090` y expone el endpoint auxiliar `/api/aw3d30` para lectura local de GeoTIFF y descarga por bloques HTTP Range de JAXA ALOS AW3D30 COG. |
| [`HANDOFF.md`](HANDOFF.md) | Documento de handoff técnico y funcional del módulo gráfico: decisiones tomadas, evolución del prototipo, arquitectura de datos y pasos para conectarlo con el comparador de 18 cultivos. |
| [`README.md`](README.md) | Esta guía de referencia y documentación técnica. |

---

## 3. Características principales del visor

### 3.1. Cinco capas satelitales y agronómicas en tiempo real
1. **🌡️ Temperatura NASA (`°C`):**
   - Soporta tres variables seleccionables de NASA POWER:
     - `T2M_MAX`: Temperatura máxima diurna a 2 m (indicador clave de estrés térmico y aborto floral en frijol `> 30 °C` y café).
     - `T2M`: Temperatura media diaria a 2 m.
     - `T2M_MIN`: Temperatura mínima nocturna a 2 m.
   - Ajustada píxel por píxel según la altitud real del terreno mediante gradiente térmico vertical troposférico ($-6.5\,^\circ\text{C} / 1000\text{ m}$ respecto a la altitud media de la celda MERRA-2 de NASA POWER) e insolación topográfica por orientación de ladera (*aspect*).
2. **💧 Humedad del Suelo (`%`):**
   - Combina la humedad en zona radicular (`GWETROOT`, peso 65%) y capa superficial (`GWETTOP`, peso 35%) de NASA POWER, modulada espacialmente por acumulación hídrica en valles y drenaje por pendiente.
3. **⛰️ Elevación (`m s.n.m.`):**
   - Hipsometría continua de alta resolución a partir de NASA SRTM / Terrarium con interpolación bicúbica Catmull-Rom.
4. **📐 Pendiente y Escorrentía (`%`):**
   - Magnitud exacta del gradiente topográfico ($\sqrt{(\partial z/\partial x)^2 + (\partial z/\partial y)^2} \times 100$) para identificar zonas de mecanización/infiltración (`< 12%`), laderas que requieren curvas a nivel o barreras vivas (`12–25%`) y laderas de alta escorrentía (`> 25%`).
5. **🌱 Pisos Térmicos ICTA (`500 m s.n.m.`):**
   - Delimitación visual de la cota crítica de **`500 m s.n.m.`** documentada en los manuales del ICTA para selección varietal en el Corredor Seco Oriental (ej. *ICTA Ligero* / *ICTA Patriarca* bajo 500 m vs. *ICTA Chortí* / *ICTA Petén* / *ICTA Sayaxché* entre 500 y 1,500 m).

### 3.2. Selector Temporal Dual (Tiempo Real vs. Planificación de Siembra)
- **📡 Modo Verificación en Tiempo Real (Últimos días):**
  - Consulta el endpoint diario de NASA POWER (`/api/temporal/daily/point`), filtra automáticamente los días en tránsito satelital marcados con `-999` y se posiciona en el **último pase satelital válido disponible (`~hace 3 días`)**, permitiendo recorrer una ventana de los últimos 14 días observados.
- **📅 Modo Planificación de Siembra (Ciclo Anual):**
  - Permite recorrer los 12 meses del año agrícola (Siembra de Primera en mayo, Canícula en julio-agosto, Postrera en septiembre-octubre) diferenciando visualmente entre **meses ya transcurridos (`● Mes Observado`)** y **meses futuros (`◌ Proyección histórica NASA 2001–2025`)**.

### 3.3. Indicador de Punto de Interés (`📍`) en 2D y 3D
- Al mover el cursor sobre el terreno 3D aparece una **mira circular amarilla** adherida a la superficie con lectura instantánea de coordenadas, altitud, temperatura, humedad y pendiente.
- Al **hacer clic sobre cualquier punto del relieve 3D** (o del mapa 2D izquierdo), se coloca el **indicador `📍 Punto de Interés`**, actualizando todas las tarjetas diagnósticas y la recomendación agronómica ICTA para ese punto exacto.
- Incluye botón **`📌 Fijar`** para guardar múltiples puntos con nombre propio dentro de la finca y **`🎯 Centrar Cuadro`** para regenerar el bloque de terreno alrededor del punto elegido.

### 3.4. Cuadro de Dimensiones Personalizables (`0.5 km` a `10 km`)
- Dos cuadros de texto en la barra superior (`📐 Cuadro (0.5–10 km): [ Ancho ] × [ Largo ] km`) permiten definir cualquier área cuadrada o rectangular entre **`0.5 km` y `10.0 km`** por lado.
- El rectángulo verde en el mapa 2D y las proporciones físicas de la malla 3D se adaptan automáticamente.
- Para cuadros pequeños (`≤ 3.5 km`), el motor eleva automáticamente el nivel de zoom de teselas DEM a **`z = 14` (`~9.5 m/píxel`)** para ofrecer el doble de detalle en parcelas individuales.

### 3.5. Slider de Transición Continua `🗺️ 2D Plano ⟷ ⛰️ 3D Relieve`
- Permite transformar suavemente la vista entre:
  - **`2D Plano (0%)`:** Proyección cartográfica cenital (`90°`) orientada con el **Norte hacia arriba**, ideal para lectura de planos de parcela y trazado de curvas a nivel.
  - **`3D Relieve (100%)`:** Proyección volumétrica interactiva con rotación orbital libre (`360°`), inclinación y zoom.

---

## 4. Fuentes de datos satelitales y APIs en vivo

| Fuente / API | Endpoint / Ruta | Uso en el motor gráfico |
|---|---|---|
| **NASA SRTM / AWS Terrain Tiles (Terrarium)** | `https://s3.amazonaws.com/elevation-tiles-prod/terrarium/{z}/{x}/{y}.png` | Malla de elevación continua en `z=13` (`~19 m/px`) y `z=14` (`~9.5 m/px`). Decodificación en punto flotante: $\text{elev} = (R \cdot 256 + G + B/256) - 32768$. |
| **NASA POWER API — Daily** | `https://power.larc.nasa.gov/api/temporal/daily/point` | Verificación en cuasi-tiempo real (`T2M`, `T2M_MAX`, `T2M_MIN`, `RH2M`, `PRECTOTCORR`, `GWETTOP`, `GWETROOT`) de los últimos 14 días válidos. |
| **NASA POWER API — Climatology** | `https://power.larc.nasa.gov/api/temporal/climatology/point` | Climatología mensual multianual para el modo de Planificación de Siembra, combinada con la serie local 2001–2025 (`datos/power/chiquimula_power_diario_20010101_20251231.csv`). |
| **JAXA ALOS AW3D30 v4.1 (Respaldo Local/COG)** | `datos/relieve/chiquimula_aw3d30_dsm.tif` y `/api/aw3d30` | Modelo Digital de Superficie (30 m) disponible en `servidor_topo3d.py` para validación cruzada. |

---

## 5. Modelos matemáticos y de renderizado

1. **Interpolación Bicúbica Catmull-Rom ($4\times 4$):**
   Elimina las discontinuidades de derivada primera ($C^1$) entre píxeles de las teselas de elevación, logrando superficies y curvas de nivel suaves sin facetas poligonales.
2. **Curvas de Nivel Cartográficas en GLSL (`OES_standard_derivatives`):**
   El *fragment shader* calcula la derivada euclidiana en espacio de pantalla $\text{fw} = \sqrt{(\partial z/\partial x_{\text{px}})^2 + (\partial z/\partial y_{\text{px}})^2}$ para dibujar curvas secundarias cada `25 m`, estándar cada `50 m` e índices maestros cada `200 m` con grosor constante en píxeles y supresión automática de manchas en llanuras planas.
3. **Curvas de Escorrentía Hidrográfica 3D (Runge-Kutta 2):**
   Se integran líneas de corriente curvas de hasta 14 sub-pasos siguiendo el campo vectorial de máxima pendiente descendente $(-\partial z/\partial x, -\partial z/\partial y)$ con muestreo bilineal de altitud y normales. Se aplica *culling* por normal de cámara y un *Z-buffer* de horizonte en pantalla (`220 × 150`) para que las curvas nunca atraviesen montañas frontales.

---

## 6. Controles de interfaz

- **Clic izquierdo en el terreno 2D/3D:** Coloca el indicador **`📍 Punto de Interés`** en esa coordenada exacta.
- **Arrastrar con clic izquierdo (en modo 3D):** Rota e inclina la cámara 3D alrededor de la parcela.
- **Arrastrar con clic izquierdo (en modo 2D Plano):** Desliza el indicador `📍 Punto de Interés` de forma continua sobre el plano.
- **Rueda del mouse (Scroll):** Acerca o aleja el zoom (`0.65×` a `2.2×`).
- **Cuadros `📐 Cuadro (0.5–10 km)`:** Cambia el ancho (Este-Oeste) y largo (Norte-Sur) del bloque en kilómetros (`Enter` o botón `Aplicar`).
- **Slider `🗺️ 2D Plano ⟷ ⛰️ 3D Relieve`:** Transforma progresivamente la proyección entre plano 2D cenital y relieve 3D.

---

## 7. Integración con App Móvil y Video de 30s

- **Aplicación Móvil (Android / iOS / Web App):**
  - Al estar construido sobre **WebGL estándar + HTML5 Canvas** sin dependencias pesadas y consumiendo teselas ligeras (`256×256 PNG`) + JSON de NASA POWER, [`topo3d.html`](topo3d.html) corre a **60 FPS** en el `WebView` nativo de cualquier teléfono móvil moderno (Capacitor, React Native `react-native-webview`, Flutter `webview_flutter` o PWA).
- **Video de Demostración (NASA Space Apps — 30 segundos):**
  - El botón **`🗺️ 2D Plano` ⟷ `⛰️ 3D Relieve`** incluye una animación cúbica suave (`380 ms`) diseñada específicamente para mostrar en video cómo el plano tradicional de una finca cobra vida en 3D con datos térmicos e hídricos de la NASA.
