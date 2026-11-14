# Brief 2 · Field Shift Guatemala

Versión combinada de dos documentos del equipo:
- El [Brief](Brief.md): problemática, evidencia y propuesta de valor.
- El [documento de diseño v2](docs/superpowers/specs/2026-11-14-field-shift-web-design.md): enfoque, datos verificados, modelo y app.

Reto: **Field Shift: Adapting Farms with NASA Data** (NASA Space Apps Challenge 2026 · sede Guatemala). Actualizado el 14 de noviembre de 2026.

---

## 1. El problema central

Cuando un finquero termina un ciclo, o pierde su siembra a mitad de temporada por sequía o exceso de lluvia, decide qué sembrar después en su parcela. Hoy esa decisión se toma **a ciegas frente a un clima errático**. No existe un puente práctico entre los datos satelitales y agroclimáticos y las condiciones reales de la finca: agua en la raíz, calendario de lluvias, riego disponible, semilla, costos y mercado.

El finquero ya sabe producir. Lo que le falta es responder **dos preguntas a la vez**:

1. **¿Cómo protejo lo que ya produzco?** ¿Qué tan seguido le habría fallado su rotación actual con las lluvias de los últimos años, y qué ajuste la haría más estable?
2. **¿Qué más le puedo sacar a mi parcela?** ¿Qué cultivo agregar o cambiar en las ventanas del año (postrera, época seca con riego, tiempo en que la parcela queda vacía) y cuánto ganaría de más?

Para cada opción hay que separar lo que conviene **aprovechar** de lo que hay que **mitigar**.

> **Caso documentado (octubre de 2026):** en La Plazuela, Chimaltenango, el agricultor Santos Zet perdió su maíz por sequía. Cuando la lluvia regresó tarde, apostó por sembrar frijol y vender una parte ([productores-guatemala.md](investigacion/productores-guatemala.md)). Es el tipo de decisión tardía y riesgosa que la herramienta quiere anticipar.

## 2. Dimensiones del problema en Guatemala

### A. Riesgo hídrico por etapa del cultivo (el promedio de lluvia engaña)
- El **70 %** de 1,008 productores de maíz y frijol encuestados en oriente y occidente sufrió eventos climáticos adversos en 2023 ([productores-guatemala.md](investigacion/productores-guatemala.md)).
- En Chiquimula, el **85 %** de los productores que percibían cambios en la lluvia dijo que llovía menos (encuesta de 2014 sobre 2004–2014) ([productores-guatemala.md](investigacion/productores-guatemala.md)).
- Un acumulado "normal" puede esconder:
  - una **canícula en plena floración o llenado de grano**;
  - aguaceros que **escurren por la ladera** sin llegar a las raíces;
  - **lluvia en la cosecha** que pudre el frijol ([manual-agroclimatico.md](conocimiento/manual-agroclimatico.md)).

### B. Brecha entre datos y decisión
- En el Corredor Seco (Chiquimula, El Progreso y Zacapa), solo **165 de 330** hogares agrícolas accede a información climática, casi toda de corto plazo y por radio. Apenas **8 de 330** reciben perspectivas estacionales ([productores-guatemala.md](investigacion/productores-guatemala.md)).
- Existen datos de NASA y canales locales (*Nubis Bot* del INSIVUMEH, *ZARC* del MAGA). Pero una probabilidad de lluvia o un mapa de 9 km no dicen **cuánta agua queda en la zona de raíces** ni **cuánto cambian el riesgo y la ganancia** si se atrasa la siembra, se cambia de variedad o se agrega un cultivo.

### C. Restricciones económicas, de insumos, de mercado y de tenencia
- **Inversión y liquidez:** el ICTA encuestó a 351 productores de frijol en 14 departamentos y encontró insumos caros y poca capacidad de inversión ([productores-guatemala.md](investigacion/productores-guatemala.md)).
- **Costo de oportunidad de las coberturas:** en el ensayo CRIA–ICTA, la mucuna antes del maíz subió el rendimiento de 2,578 a 3,617 kg/ha. A cambio, exigió más jornales y ocupó la tierra 120 días sin vender grano ([manual-agroclimatico.md](conocimiento/manual-agroclimatico.md)).
- **Semilla y mercado:**
  - Las variedades mejoradas (p. ej. *ICTA Grano de Oro*) enfrentan escasez local de semilla.
  - Hay intermediarios.
  - Las empacadoras hortícolas rechazan entre 30 y 45 % del producto ([productores-guatemala.md](investigacion/productores-guatemala.md)).
- **Tierra alquilada:** algunas familias evitan mejorar el suelo por temor a que suba la renta ([productores-guatemala.md](investigacion/productores-guatemala.md)).

### D. Café: agua en laderas y floración (fuera del alcance de esta entrega)
Los cafetaleros entrevistados priorizan el "poder hídrico" y la humedad para la floración ([testimonios-2026-11-11.md](investigacion/testimonios-2026-11-11.md)). Queda como **siguiente módulo** y se menciona en el pitch.

## 3. Qué resuelve Field Shift Guatemala

Un **comparador de secuencias de cultivos en web, adaptado a celular** que:

1. **Parte de la situación real del finquero:**
   - su parcela (en el mapa);
   - su rotación actual;
   - si tiene riego (no / limitado / sí);
   - sus prioridades, con cuatro deslizadores: **proteger lo que ya produzco, ganar extra, cuidar el suelo, usar menos agua**.
2. **Simula día a día el agua en la zona de raíces (FAO-56) en los últimos 25 años (2001–2025)** del clima de su propia parcela, para la rotación actual y al menos 2 alternativas.
3. **Calcula la ganancia** de cada opción con números con fuente:
   - margen = rendimiento de referencia MAGA × factor de agua de cada año (FAO-33) × precio MAGA − costos MAGA − costo del riego;
   - se da en Q por manzana, como **rango** entre año típico y año malo, no como predicción exacta.
4. **Explica en lenguaje claro**, para cada opción:
   - **Proteger:** cuánto gana en un año malo y cuántos años le falló la lluvia en floración.
   - **Ganar extra:** cuánto más gana que con su rotación actual.
   - **Aprovechar / Mitigar:** cada riesgo con su acción concreta, por ejemplo: "lluvia en cosecha en 7 de 25 años → sembrar antes del 5 de septiembre"; "suelo desnudo 40 días → cobertura en relevo".
   - Qué falta saber y qué revisar con un extensionista. **La herramienta apoya la decisión; no la reemplaza.**

Opciones según el riego:
- **Sin riego:** el extra viene de la postrera (frijol para la venta, sorgo o ajonjolí).
- **Con riego:** se abre la época seca (sandía, melón o tomate).

## 4. Datos: NASA como núcleo, más Copernicus y Guatemala

Verificados el 14 de noviembre de 2026.

| Fuente | Tipo | Uso |
|---|---|---|
| NASA POWER (MERRA-2, CERES) | NASA | Temperatura, humedad, radiación y viento para ET₀ (ya descargado por el equipo: `datos/power/`) |
| NASA GPM IMERG V07 (0.1°) | NASA | **Lluvia** de los sitios piloto (Earthdata) |
| NASA SMAP L4 y SRTM | NASA | Humedad en raíces (contraste del balance) y pendiente (Earthdata/AppEEARS) |
| NASA GIBS, MODIS NDVI | NASA | Capas del mapa y ciclo del cultivo |
| Copernicus ERA5 | Socio (ESA/ECMWF) | Lluvia en vivo para cualquier punto fuera de los pilotos |
| Copernicus Sentinel-2 (10 m) | Socio (ESA) | NDVI fino y color real en pilotos; 42 escenas sin nubes en 2025 sobre Chiquimula, vía Microsoft Planetary Computer |
| SoilGrids (WCS) | Global | Textura del suelo; el WCS funciona aunque la API REST devuelve vacíos |
| MAGA: [fichas agroeconómicas](https://apps.maga.gob.gt/sieagro/Normativas?categoriaId=202&clasificacionId=21&tipoId=1), precios, calendarios, boletines con estaciones INSIVUMEH | Guatemala | Costos, rendimientos y precios (maíz, frijol negro, sandía, melón, tomate, pepino, ejote…), fechas y validación de lluvia |
| ICTA | Guatemala | Variedades, días a floración y cosecha |

**Hallazgo clave sobre la lluvia (tarea T07):**
- En Chiquimula, la lluvia de NASA POWER (celda de ~0.5°) da 1,500–2,900 mm al año en 2021–2025 (2022 = 2,931 mm).
- Copernicus ERA5 da 900–1,600 mm (2022 = 1,589 mm).
- El INSIVUMEH preveía 500–600 mm de acumulado en la temporada para el municipio.

Por eso la lluvia del balance **no** sale de POWER: viene de IMERG en los pilotos y de ERA5 en el resto, y la app muestra la comparación entre fuentes. Falta confirmar con datos de estación.

## 5. Componente de SI (en evaluación)

El equipo quiere una red neuronal densa y profunda tipo embudo, y explorar una arquitectura sin *backpropagation* que "cambia los ángulos de los perceptrones". Hay una investigación en curso (informe en `reports/` fuera del repo). Conclusiones preliminares:

- La descripción encaja sobre todo con:
  - **circuitos cuánticos variacionales** ("perceptrón cuántico": los parámetros son ángulos de rotación y se entrenan sin backpropagation);
  - el algoritmo **Forward-Forward** de Hinton (cada capa solo pasa la orientación de su actividad).
- **En una red pequeña, la memoria no es un problema:** entrenar una red embudo de unos 60 mil parámetros con backpropagation usa menos de 1 MB. Los métodos por perturbación fueron más lentos y menos precisos en una prueba en la laptop del equipo.
- **Hay muy pocos datos reales de rendimiento por departamento** (unos 75 departamento-año en el mejor caso). Una red profunda que prediga cosechas se sobreajustaría.
- **Donde sí tiene sentido una red es como emulador del simulador FAO-56,** que genera todos los ejemplos de entrenamiento que haga falta. Una variante sin backpropagation (Extreme Learning Machine) se puede entrenar en el navegador.

La decisión final se toma con el informe completo.

## 6. Cómo encaja con [decisions.md](decisions.md) y [tasks.md](tasks.md)

Propuestas para actualizar las decisiones (las confirma el equipo):

| ID | Propuesta combinada |
|---|---|
| D01 | Chiquimula (14.80, −89.54) como piloto principal, más Jutiapa (14.29, −89.90) y San Martín Jilotepeque (14.78, −90.79, caso La Plazuela) si da tiempo |
| D02 | Rotación actual (maíz → frijol) + alternativa **Proteger** (ciclo corto, siembra según inicio de lluvias, cobertura en relevo) + alternativa **Ganar extra** (sin riego: ajonjolí o sorgo en postrera; con riego: sandía o melón en época seca) |
| D04 | Web estática en GitHub Pages ✅ (elegida) |
| D05 | Híbrido: Python precalcula los pilotos (IMERG, SMAP, suelo, NDVI) en JSON; el navegador calcula ET₀ y el balance para cualquier punto, con un respaldo guardado por si una API falla |
| D06 | IMERG en pilotos; ERA5 en el resto; POWER solo como contraste (ver §4) |
| D07 | Se mantiene la propuesta: MERRA-2 vía POWER para 2001–2014 y SMAP para 2015–2025 |
| D08 | SoilGrids vía WCS (verificado que funciona); suelo editable como respaldo |
| D10 | Agregar los indicadores económicos (margen, ganancia extra) con fuentes MAGA |
| D11 | Café fuera; se menciona como siguiente módulo |
| D17 | Resuelta por el boletín 18 de la sede: el jurado local evalúa el **lunes temprano** con los criterios oficiales (Impacto, Creatividad, Validez, Relevancia, Presentación) |

## 7. Fechas clave (sede Guatemala)

- **Domingo 15, 3 p. m.:** llamada virtual de retos locales.
- **Domingo 15, 5–6 p. m.:** sesión virtual de evaluación (agenda local).
- **Domingo 15, 11:59 p. m.:** cierre del Submit. La sede pide entregar antes por congestión del servidor. Hay que subir el proyecto aunque esté incompleto, porque sin entrega no hay diploma.
- **Lunes 16, temprano:** evalúa el jurado local.
- **3 de diciembre:** premiación en el Congreso de la República.

Pendientes administrativos:
- La página del equipo debe tener foto y descripción.
- El equipo debe presentarse en inglés en [GitHub Discussions #1784](https://github.com/nasa/spaceapps/discussions/1784).
