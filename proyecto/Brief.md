# Brief · Field Shift Guatemala

Síntesis de la problemática, evidencia documental y propuesta de valor para el reto **Field Shift: Adapting Farms with NASA Data** (NASA Space Apps Challenge 2026 · Ciudad de Guatemala).

---

## 1. El problema central: decidir el siguiente ciclo «a ciegas» frente a un clima errático

Cuando un productor guatemalteco termina un ciclo agrícola —o pierde su siembra a mitad de temporada por sequía o exceso de lluvia— debe tomar una decisión crítica en su parcela: **¿qué secuencia sembrar ahora?** (por ejemplo, repetir maíz, rotar maíz → frijol, invertir a frijol → maíz, cambiar a una variedad de ciclo corto o establecer una cobertura).

Hoy esa decisión se toma con alta incertidumbre porque **no existe un puente práctico entre los datos satelitales/agroclimáticos y las restricciones reales de la finca** (agua en la raíz, calendario de lluvias, semilla disponible, presupuesto y necesidad de alimento o venta).

> **Caso real documentado (octubre 2026):** En La Plazuela, Chimaltenango, el agricultor Santos Zet perdió su maíz por sequía; cuando la lluvia regresó tarde, apostó por sembrar frijol criollo con la esperanza de vender una parte para volver a comprar maíz para su casa ([productores-guatemala.md](../investigacion/productores-guatemala.md)).

---

## 2. Las 4 dimensiones del problema en Guatemala

### A. Riesgo hídrico por etapa fenológica (no basta el promedio de lluvia)

* **Alta exposición climática:** El **70 %** de 1,008 productores de maíz y frijol encuestados en oriente y occidente sufrió eventos climáticos adversos recientes; en Chiquimula, el **85 %** reporta disminución de lluvias ([productores-guatemala.md](../investigacion/productores-guatemala.md)).
* **El promedio engaña:** Un acumulado mensual «normal» puede esconder una **canícula prolongada justo durante la floración o el llenado de grano/vaina** (las fases más sensibles al déficit hídrico), aguaceros intensos que escurren por la ladera sin infiltrar a las raíces, o **lluvias tardías durante la cosecha** que pudren el frijol ([manual-agroclimatico.md](../conocimiento/manual-agroclimatico.md)).

### B. Brecha entre los datos satelitales y la decisión en parcela

* **Bajo alcance de pronósticos estacionales:** En el Corredor Seco (Chiquimula, El Progreso y Zacapa), solo el **50 %** de los hogares agrícolas (165 de 330) accede a información climática, casi toda de corto plazo por radio; apenas **8 de 330 hogares** reciben perspectivas estacionales que les permitan planificar una rotación ([productores-guatemala.md](../investigacion/productores-guatemala.md)).
* **Señales desconectadas del suelo:** Aunque existen datos de NASA (POWER, GPM IMERG, SMAP L4, SRTM, HLS) y canales locales como *Nubis Bot* (INSIVUMEH en Telegram) o *ZARC* (MAGA), una «probabilidad de lluvia» o un mapa regional de 9 km no le dice al productor **cuánta agua queda realmente disponible en la zona radicular** ni cómo cambia el riesgo si atrasa 15 días la siembra o cambia de variedad ([observaciones-nasa.md](../conocimiento/observaciones-nasa.md)).

### C. Restricciones socioeconómicas, de insumos y de tenencia de la tierra

Una rotación agronómicamente ideal fracasa si ignora la economía del hogar rural ([investigador_de_productores.toml](../.codex/agents/investigador_de_productores.toml)):

* **Competencia entre comida, semilla y liquidez:** En 14 departamentos (351 frijoleros encuestados por ICTA), el mismo quintal cosechado debe repartirse entre **consumo familiar, reserva de semilla y venta** ([productores-guatemala.md](../investigacion/productores-guatemala.md)).
* **Costo de oportunidad de las coberturas:** En Alta Verapaz y Quiché (CRIA–ICTA), usar abono verde (*Mucuna* → maíz) subió el rendimiento de maíz de 2,578 a 3,617 kg/ha, pero exige más jornales y ocupa la tierra 120 días sin producir grano comestible ([manual-agroclimatico.md](../conocimiento/manual-agroclimatico.md)).
* **Tierra alquilada y aversión al riesgo:** En parcelas arrendadas (ej. San Martín Jilotepeque), las familias evitan inversiones de mejora de suelo a mediano plazo por temor a que el propietario suba la renta o no renueve el alquiler ([productores-guatemala.md](../investigacion/productores-guatemala.md)).
* **Acceso real a semillas y mercado:** Variedades mejoradas (como *ICTA Grano de Oro*) enfrentan escasez local de semilla, fertilizantes caros, falta de mano de obra y riesgos comerciales (intermediarios o 30–45 % de rechazo en empacadoras hortícolas).

### D. Retención de agua en laderas y floración en cafetales establecidos

* En las conversaciones del equipo con cafetaleros ([testimonios-2026-11-11.md](../investigacion/testimonios-2026-11-11.md)), la prioridad se centra en el **«poder hídrico»**: frenar la escorrentía en laderas mediante curvas de nivel y coberturas, y saber si la humedad en raíces tras la época seca es suficiente para activar y sostener la **floración del café** o si conviene regar antes de esperar la lluvia.

---

## 3. ¿Qué resuelve exactamente *Field Shift Guatemala*?

En lugar de prescribir una «receta única» o pedir decenas de parámetros técnicos que el agricultor desconoce, el proyecto propone un **comparador de secuencias de cultivos adaptado a móvil** ([datos-y-comparacion-de-rotaciones-guatemala.md](../conocimiento/datos-y-comparacion-de-rotaciones-guatemala.md)) que:

1. **Parte de la situación real del finquero:** su parcela, qué cultivo acaba de salir, qué alternativas considera (ej. práctica actual vs. maíz → frijol vs. frijol → maíz) y cuál es su prioridad (asegurar grano, cuidar agua, minimizar inversión o proteger el suelo).
2. **Simula el balance hídrico diario en raíces (FAO-56) sobre series históricas de NASA (2001–2025):** cruza demanda atmosférica ($ET_0$ con NASA POWER), lluvia (POWER / GPM IMERG), humedad y pendiente (SMAP L4 / SRTM) y fichas locales del ICTA ($K_c$, profundidad radicular y días a floración/cosecha).
3. **Explica el riesgo por fase en lenguaje claro:** muestra lado a lado qué pasa en años secos y húmedos durante las ventanas sensibles (*floración*, *llenado* y *cosecha*), cuántos días queda el suelo descubierto y bajo qué supuestos una secuencia supera a otra (ej. *«La opción B llega antes a cosecha y requiere menos inversión, pero su riesgo aumenta si la lluvia se corta antes de la floración»*).

---

Actualizado el 14 de noviembre de 2026.
