# Diseño · App web Field Shift Guatemala

Fecha: 14 de noviembre de 2026 · Estado: **borrador v2 para aprobación del equipo**
Reto: [Field Shift: Adapting Farms with NASA Data](https://www.spaceappschallenge.org/2026/challenges/adapting-farms-with-nasa-data/) · Equipo Feliz_cumpleaños, sede Guatemala.
Contexto agronómico y de productores: [handoff del proyecto](../../../conocimiento/datos-y-comparacion-de-rotaciones-guatemala.md) y documentos de apoyo.

## 1. Intención y porqué

Un finquero del Corredor Seco ya sabe producir. Lo que no tiene es una forma sencilla de responder dos preguntas **a la vez** para su parcela:

1. **¿Cómo protejo lo que ya produzco?** Con lluvias cada vez más irregulares (canícula, inicio tardío, El Niño), ¿qué tan seguido le habría fallado su rotación actual y qué ajuste la haría más estable?
2. **¿Qué más le puedo sacar a mi parcela?** ¿Qué cultivo puede agregar o cambiar en las ventanas del año (postrera, época seca con riego, tiempo en que la parcela queda vacía) y cuánto ganaría de más?

Para cada opción, la app separa lo que conviene **aprovechar** de lo que hay que **mitigar**: los riesgos, con una acción concreta para cada uno. Lo hace simulando día a día el agua en la zona de raíces en los **últimos 25 años de clima de su propia parcela**, con datos de NASA, de socios espaciales (Copernicus) y de Guatemala (MAGA, ICTA, INSIVUMEH). **Apoya la decisión del finquero; no la reemplaza.**

Por qué ahora:
- La entrega cierra el **domingo 15 de noviembre a las 11:59 p. m.**; la sede pide entregar antes porque el servidor se congestiona.
- La agenda local tiene una sesión virtual de evaluación el domingo de 5 a 6 p. m.
- El jurado local evalúa el **lunes temprano** con los criterios oficiales.

Queremos ganar en Guatemala y competir por el premio global *Local Impact*.

## 2. Metas, no-metas y anti-metas

**Metas**
1. App web pública, adaptable a celular, funcionando antes del domingo a las 2 p. m.
2. Para cualquier punto de Guatemala: clima diario 2001–2025, ET₀ (FAO-56 Penman-Monteith) y balance hídrico diario en raíces (FAO-56) para cada secuencia.
3. Comparar la rotación actual con al menos 2 alternativas. Para cada una:
   - qué protege;
   - cuánto extra puede ganar (rango en Q/manzana, año típico y año malo);
   - qué aprovechar y qué mitigar, con evidencia, beneficios, vacíos de información y lo que debe revisar con un experto.
4. Prioridades del finquero (deslizadores) que cambian el orden de las alternativas, con una fórmula visible.
5. Interfaz **en inglés por defecto (exigido para el jurado) con botón visible a español**; la conversación del equipo es en español.
6. **NASA como núcleo de los datos**, complementada con Copernicus y fuentes guatemaltecas, y un panel que compara fuentes (ver §8).
7. Paquete de entrega: textos en inglés para la página del proyecto, demo (7 diapositivas o video de 30 s), referencias y declaración de uso de SI.

**No-metas** (fuera del alcance de este fin de semana)
- **Predicción puntual de cosecha.** Sí se dan rangos de margen: rendimiento de referencia del MAGA × factor de agua FAO-33 de cada año, etiquetados como estimación.
- App nativa, cuentas de usuario, servidor propio, base de datos.
- Módulo de café (queda como "siguiente etapa" en el pitch, citando las entrevistas del equipo).
- Los 18 cultivos del catálogo: el demo usa 7.
- Pronóstico de los próximos días (se enlaza a INSIVUMEH / Nubis Bot).

**Anti-metas** (fracaso aunque "funcione")
- Que una opción se presente como certeza o como recomendación cerrada.
- Números sin fuente: cada parámetro de cultivo, costo y precio lleva su referencia (ICTA, FAO-56, FAO-33, MAGA, CRIA).
- Que la demo falle durante el jurado por una API caída o lenta.
- Una interfaz que un finquero o un juez no técnico no entienda en 30 segundos.

## 3. Restricciones

- **Tiempo:** ~24 horas de trabajo.
- **Idioma:** página del proyecto y materiales enlazados en inglés.
- **Reglas de datos:** se exige al menos un dato de NASA y se recomiendan los de socios espaciales (ESA es socio 2026). La Relevancia pide que NASA sea parte central de la solución.
- **Hosting estático gratuito:** GitHub Pages desde el repo del equipo. El dominio gratuito de la oferta GoDaddy Registry / Porkbun (spaceapps.earth) es opcional.
- **Sin paso de compilación:** HTML + JavaScript en módulos + librerías por CDN con versión fija. Node se instala solo para las pruebas.
- **Datos verificados el 14 de noviembre:** ver la tabla de §8.

## 4. Formas de construirlo (decidido: A)

| Opción | Qué es | A favor | En contra |
|---|---|---|---|
| **A. Web estática + cálculo en el navegador** ✅ | HTML/JS en GitHub Pages; clima en vivo; capas precalculadas para sitios piloto con Python | Gratis, nada que se caiga en el jurado, se ve bien en celular | Lo que exige cuenta Earthdata solo cubre los pilotos |
| B. Servidor Python + web | FastAPI en Render/Railway; descarga IMERG/SMAP bajo demanda | Cualquier punto con todos los datos | Más piezas; los servidores gratis "se duermen" en pleno jurado; credenciales en el servidor |
| C. Streamlit | Todo en Python | Lo más rápido para gente de datos | Aspecto genérico, torpe en celular, también se duerme |

El equipo eligió **A** el 14 de noviembre.

## 5. Experiencia del usuario

Cuatro pantallas en una sola página, navegación por pasos:

1. **Inicio:** el problema en una frase (lluvias irregulares en el Corredor Seco), qué hace la app, "Empezar", botón EN/ES.
2. **Tu parcela:**
   - Mapa Leaflet con capas conmutables: lluvia IMERG, NDVI MODIS y humedad SMAP (NASA GIBS), y Sentinel-2 color real (Copernicus).
   - Se toca el mapa o se elige un sitio piloto.
   - Tarjeta del sitio: altitud, pendiente, textura de suelo y **¿tiene riego? (no / limitado / sí)**.
   - **"Historia climática de tu parcela":** lluvia mensual 2001–2025, inicio típico de lluvias y duración de la canícula año por año.
3. **Lo que ya haces y lo que buscas:**
   - Rotación actual precargada y editable.
   - Cuatro deslizadores: **proteger lo que ya produzco, ganar extra, cuidar el suelo, usar menos agua**.
4. **Comparar:**
   - Tarjetas de la rotación actual (línea base) y de las alternativas, apiladas en celular.
   - Cada tarjeta muestra el puntaje, "Proteger", "Ganancia extra", y las listas **Aprovechar** y **Mitigar**, cada riesgo con su acción.
   - Gráfica año por año (2001–2025) del margen estimado de cada secuencia, para ver qué pasó en años secos (p. ej. El Niño 2015, 2023).

Además, una página **Métodos y datos**: fuentes, ecuaciones, supuestos, limitaciones, comparación de fuentes de lluvia, referencias y declaración de uso de SI.

Boceto de la tarjeta (pantalla 4):

```
┌ Alternativa B · Maíz → ajonjolí en postrera ──────── 74/100 ┐
│ Proteger:   año malo  Q 3,100/mz   (actual: Q 1,200)        │
│ Ganar extra: +Q 2,400/mz/año (rango +900 a +3,600)          │
│ ✔ Aprovechar                                                 │
│   · Ajonjolí aguanta la canícula: estrés en 4 de 25 años    │
│   · Precio de referencia MAGA estable 2021–2025              │
│ ⚠ Mitigar                                                    │
│   · Lluvia en cosecha en 7 de 25 años → sembrar antes del 5 sep │
│   · Suelo desnudo 40 días → cobertura de mucuna en relevo    │
│ ▸ Evidencia  ▸ Qué falta saber  ▸ Revisar con un experto     │
└──────────────────────────────────────────────────────────────┘
```
(Cifras ilustrativas; las reales salen del modelo. El ajonjolí entra solo si se consiguen costos y precios con fuente; ver §7.)

## 6. Modelo (núcleo científico)

Todo con referencias de FAO-56 (Allen et al., 1998) y FAO-33 (Doorenbos & Kassam, 1979).

**Pasos del cálculo**
1. **Entradas diarias.**
   - Temperatura, humedad, radiación y viento de **NASA POWER** (campos suaves que la cuadrícula de 0.5° representa bien).
   - Lluvia de la mejor fuente disponible para el punto (ver §8).
   - Elevación del punto.
2. **ET₀ diaria** con Penman-Monteith FAO-56 (ec. 6), radiación neta (ecs. 37–40) y presión de vapor real desde la humedad relativa media.
3. **Cultivo.**
   - Kc por etapa (FAO-56 cuadro 12).
   - Profundidad radicular y fracción p (cuadro 22).
   - Ky por etapa (FAO-33).
   - Etapas en **grados-día** calibrados con los días de ICTA a temperatura de tierras bajas: en tierras altas los ciclos se alargan solos. Arriba de 1,500 m aparece un aviso.
4. **Suelo.** TAW = 1000 (θCC − θPMP) Zr (ecs. 82–84). θ por clase textural (FAO-56 cuadro 19), a partir de SoilGrids en los pilotos o de la selección del usuario.
5. **Escorrentía:** número de curva SCS según textura, cobertura y pendiente.
6. **Balance diario** del agotamiento en raíces (ec. 85), Ks (ec. 84) y ETc ajustada = Ks · Kc · ET₀.
   - **Con riego:** la app agrega riego de auxilio cuando el agotamiento pasa el umbral RAW y contabiliza los mm aplicados.
   - **Sin riego:** el cultivo sufre el estrés.
7. **Cultivos traslapados** (relevo/asociación):
   - Una secuencia es una lista de fases en el tiempo sobre una sola zona de raíces.
   - Cuando dos fases se traslapan, se usan el Kc mayor y la Zr mayor (simplificación declarada en Métodos).
   - El estrés se evalúa por cultivo en sus propias etapas.
   - Los abonos verdes no tienen margen; cuentan en suelo y en mitigación.
8. **Simulación:** cada secuencia se corre en los 25 años con su calendario. Regla de siembra de primera: tras ≥20 mm en 3 días después del 1 de mayo (supuesto documentado).

**Economía**
- Margen por cultivo y año = rendimiento de referencia MAGA × factor de agua FAO-33 (1 − Ky·(1 − ETa/ETc)) × precio de referencia MAGA − costos MAGA − costo del riego aplicado (si aplica).
- Todo en **Q por manzana**, con opción a hectárea.
- Margen de la secuencia = suma de sus cultivos en el año.

**Indicadores por secuencia** (mediana y "año malo" = percentil 10):
- **Proteger:** margen y años con estrés en floración en el año malo.
- **Ganancia extra:** margen mediano de la alternativa − margen mediano de la rotación actual.
- **Cuidar el suelo:** fracción de la época lluviosa con suelo cubierto, presencia de leguminosa y exposición a erosión (escorrentía sobre suelo desnudo × factor de pendiente).
- **Agua:** mm de riego por año (si hay riego) o déficit hídrico (si no hay).
- **Listas Aprovechar / Mitigar:**
  - Se generan con plantillas a partir de los indicadores; por ejemplo, "lluvia en cosecha en X de 25 años", "canícula cae en floración en X años" o "suelo desnudo N días".
  - Cada riesgo trae su acción: sembrar antes o después, variedad más corta, riego de auxilio, cobertura, barreras vivas o venta a contrato.
  - Sin servicio de IA en vivo.

**Puntaje** (escalas fijas, sin normalizar entre opciones):
- Proteger = margen del año malo ÷ margen mediano de la rotación actual, acotado a 0–1.
- Ganar extra = ganancia extra ÷ escala de referencia (p. ej. Q 5,000/mz), acotado a 0–1.
- Suelo = promedio de cobertura, leguminosa (0/1) y 1 − erosión.
- Agua = 1 − riego (o déficit) ÷ escala de referencia.
- Total = Σ (peso × indicador) ÷ Σ pesos × 100.

La rotación actual se puntúa igual y se muestra como línea base ("+12 frente a tu rotación actual"). La fórmula se muestra al tocar "¿cómo se calcula?".

**Pruebas:** ET₀ contra el ejemplo resuelto de FAO-56 (ej. 18); balance contra el ejemplo didáctico del manual del equipo (18 − (12 − 4) + 3 = 13 mm); margen contra un cálculo a mano con una ficha MAGA.

## 7. Cultivos y secuencias del demo

Se eligen cultivos con **ficha agroeconómica MAGA** (costos, rendimiento y precio) y parámetros FAO-56:
- **Sin riego:** maíz, frijol negro, sorgo/maicillo y ajonjolí. Sorgo y ajonjolí entran solo si aparecen costos y precios con fuente; si no, su margen se marca "sin dato".
- **Con riego en época seca:** sandía, melón y tomate.
- **Mitigación:** mucuna o canavalia como cobertura (proxy de leguminosa en FAO-56, marcado como tal).

Secuencias por defecto (las afina el responsable de agronomía con el asesor agroclimático):
- **Actual:** maíz en primera → frijol en postrera → suelo desnudo en época seca.
- **Proteger:** maíz de ciclo corto + frijol ICTA Ligero sembrado según la regla de inicio de lluvias, con mucuna en relevo para cubrir el suelo.
- **Ganar extra (sin riego):** maíz → ajonjolí o sorgo en postrera.
- **Ganar extra (con riego):** maíz → frijol → sandía o melón en época seca.

El usuario puede editar cultivo, temporada y fecha. Claude redacta `crops.json` con referencias; el responsable de agronomía lo revisa antes del sábado 21:00.

## 8. Datos y arquitectura

**Fuentes verificadas (14 de noviembre)**

| Fuente | Tipo | Acceso | Uso en la app |
|---|---|---|---|
| NASA POWER (MERRA-2, CERES) | NASA | En vivo, sin cuenta, CORS | Temperatura, humedad, radiación y viento → ET₀ |
| NASA GPM IMERG V07 (0.1°) | NASA | Cuenta Earthdata; precalculado | Lluvia de los sitios piloto (fuente principal ahí) |
| NASA SMAP L4 (humedad en raíces) | NASA | Cuenta Earthdata (AppEEARS) | Contraste con el balance modelado en pilotos |
| NASA SRTM | NASA | Cuenta Earthdata (AppEEARS) | Pendiente de los pilotos |
| NASA GIBS (IMERG, MODIS NDVI, SMAP) | NASA | En vivo, sin cuenta | Capas del mapa |
| MODIS 13Q1 NDVI | NASA | Planetary Computer, sin cuenta | Suelo desnudo / ciclo de cultivo en pilotos |
| Copernicus ERA5 | Socio (ESA/ECMWF) | En vivo vía Open-Meteo, CORS | Lluvia de cualquier punto fuera de los pilotos + comparación |
| Copernicus Sentinel-2 L2A (10 m) | Socio (ESA) | Planetary Computer, sin cuenta (42 escenas sin nubes en 2025 sobre Chiquimula) | NDVI fino en pilotos y capa de color real |
| ISRIC SoilGrids (WCS) | Global | Sin cuenta; precalculado | Textura de suelo en pilotos |
| MAGA: fichas agroeconómicas, precios, calendario, boletines agroclimáticos con estaciones INSIVUMEH | Guatemala | Descarga | Costos, rendimientos, precios, fechas y validación de lluvia |
| ICTA: manuales y variedades | Guatemala | Descarga | Días a floración y cosecha |

**Hallazgo sobre la lluvia (valida el diseño):** en Chiquimula, NASA POWER (cuadrícula de 0.5°) da 1,500–2,900 mm al año en 2021–2025, mientras ERA5 da 900–1,600 mm. Chiquimula es de las zonas más secas del país (INSIVUMEH preveía 500–600 mm de acumulado en la temporada para el municipio). Por eso:
- la lluvia **no** sale de POWER;
- en los pilotos se usa IMERG (NASA, 0.1°);
- en otros puntos se usa ERA5;
- Métodos muestra la comparación POWER vs ERA5 vs IMERG vs estaciones (boletines MAGA/INSIVUMEH).

El equipo debe confirmar con datos de estación.

**Estructura**
```
web/                      ← se publica en GitHub Pages
  index.html, css/app.css
  js/main.js, ui/*.js
  js/data/climate.js      ← POWER + ERA5 en vivo, caché local, respaldo a snapshot
  js/model/et0.js, waterBalance.js, economics.js, indicators.js, score.js
  data/crops.json         ← parámetros, costos y precios con fuente por campo
  data/sites.json         ← pilotos: coords, suelo, pendiente, IMERG, SMAP, NDVI
  data/snapshots/*.json   ← clima guardado de los pilotos (respaldo si una API falla)
  i18n/en.json, es.json
scripts/                  ← Python para precalcular pilotos
tests/                    ← pruebas del modelo (node --test)
.github/workflows/pages.yml
```

**Sitios piloto** (coordenadas aproximadas de cabecera municipal; el equipo puede afinarlas): Chiquimula 14.80, −89.54; Jutiapa 14.29, −89.90; San Martín Jilotepeque 14.78, −90.79.

**Fuera de los pilotos:** el usuario elige pendiente (plano / moderado / empinado) y textura, y la app indica que son supuestos.

**Respaldo para el jurado:** si una API no responde en 8 s, se usa el snapshot del piloto más cercano con aviso visible.

## 9. Lo que queda a criterio de quien construye

- Librerías concretas y versiones fijas, estilo visual y paleta (contraste y lectura en celular).
- Estructura interna de los módulos y del formato de los JSON, siempre con un campo `source` por parámetro.
- Workflow de despliegue que publica `web/`.
- Nombre comercial de la app (provisional: *Field Shift GT*).

## 10. Hitos (hora de Guatemala)

| Hora | Hito |
|---|---|
| Sáb 20:00 | Modelo (ET₀ + balance + margen) pasa pruebas; `crops.json` v1 con fichas MAGA; cuenta Earthdata creada |
| Sáb 23:30 | Flujo completo con un sitio piloto y **primer despliegue público** |
| Dom 10:00 | 3 pilotos con IMERG/SMAP/NDVI, tarjetas Aprovechar/Mitigar, EN/ES, capas de mapa |
| Dom 14:00 | Congelar funciones; pulir textos; borrador del demo |
| Dom 15:00 | Llamada virtual de retos locales (alguien del equipo asiste) |
| Dom 16:00 | Página del proyecto llena en inglés; **primer Submit** (se puede reenviar) |
| Dom 17:00 | Sesión virtual de evaluación según la agenda local |
| Dom ≤21:00 | Envío final (antes de la congestión de medianoche; cierre 23:59) |
| Lun temprano | El jurado local evalúa con los criterios oficiales |

Pendientes administrativos (boletines 17–18 de la sede):
- la página del equipo debe tener foto y descripción;
- el equipo debe presentarse en inglés en [GitHub Discussions #1784](https://github.com/nasa/spaceapps/discussions/1784).

## 11. Decisiones y respuestas

**Respuestas del equipo (14 de noviembre)**
- Claude programa casi todo, con José Eduardo en la computadora; el resto del equipo se encarga de datos/Earthdata, revisión agronómica, historia y pitch.
- José Eduardo tiene permiso de escritura en el repo; los commits y el push se hacen con su visto bueno.
- Enfoque: **combinar** "proteger lo que ya produce" y "ganar extra", con riesgos a mitigar.
- "Comida para la casa" sale del puntaje.
- Se pueden usar datos que no son de NASA (Copernicus, MAGA, ICTA).

**Decisiones de Claude (revisables)**
- Manejo de cultivos traslapados.
- Fenología por grados-día y aviso de altitud.
- Abonos verdes con valores proxy.
- Pendiente y textura elegidas por el usuario fuera de los pilotos.
- Coordenadas aproximadas de los pilotos.
- Pregunta de riego con filtro de cultivos.
- Fuente de lluvia según el hallazgo de §8.
- Escalas fijas del puntaje.
