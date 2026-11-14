# Decisiones · Field Shift Guatemala

Decisiones que el equipo debe tomar para la entrega del domingo 15 de noviembre de 2026, 11:59 p. m. Actualizado el 14 de noviembre de 2026.

**Estado:** *Abierta*, sin decidir · *Propuesta*, hay una recomendación que falta confirmar · *Decidida*, acordada por el equipo.
Al decidir, anotar la fecha y quién decidió, cambiar el estado y actualizar [tasks.md](tasks.md) y el [handoff](conocimiento/datos-y-comparacion-de-rotaciones-guatemala.md) si cambia algo.

## Urgentes (bloquean el trabajo de hoy)

| ID | Decisión | Opciones | Recomendación | Bloquea | Estado | Decidido por / fecha |
|---|---|---|---|---|---|---|
| D01 | Parcela piloto (coordenada) | Cabecera de Chiquimula (provisional); otra parcela del Corredor Seco; La Plazuela, San Martín Jilotepeque (caso maíz–frijol de 2026); finca de uno de los cafetaleros entrevistados | Mantener Chiquimula para el MVP y cambiarla si alguien consigue una finca real con registros. Revisar con LGRIP30 que el punto caiga en cultivo de secano | T01, T03–T07, todo el análisis | Propuesta | — |
| D02 | Secuencias a comparar | Práctica actual · maíz → frijol · frijol → maíz · incluir una cobertura (por ejemplo mucuna, ensayo CRIA) | Las tres primeras; la cobertura como extra | T08, T11, T12 | Propuesta | — |
| D03 | Variedades de referencia | Maíz: variedad ICTA por elegir · Frijol: ICTA Ligero (64–70 días a cosecha), Altense (115 días) o Hunapú (95 o 120 días según la publicación) | Una variedad de ciclo corto y una de ciclo largo por cultivo, para mostrar la sensibilidad al calendario | T08, T11 | Abierta | — |
| D04 | Formato del prototipo | Web estática adaptable a celular · app móvil · web con backend | Web estática en GitHub Pages con datos precalculados en JSON | T02, T13–T17 | Propuesta | — |
| D05 | Lenguaje del motor de cálculo | Python offline que genera JSON · JavaScript en el navegador | Python para descargar y calcular; la web solo muestra los JSON | T09–T12 | Abierta | — |
| D06 | Fuente de lluvia del balance | POWER PRECTOTCORR (ya descargada, parece alta) · GPM IMERG Final diario · ambas, mostrando la diferencia | Usar IMERG si se descarga a tiempo y mostrar POWER como contraste; si no, POWER con la advertencia | T07, T10 | Abierta | — |
| D07 | Humedad del suelo NASA | MERRA-2 vía POWER (ya descargada, sin login) · SMAP L4 vía AppEEARS (necesita Earthdata y puede tardar horas) · ambas | Ambas: POWER para 2001–2014 y SMAP para 2015–2025 y para la demo | T03, T05 | Propuesta | — |
| D08 | Suelo de la parcela | SoilGrids vía WCS · suelo de referencia con supuesto explícito | Suelo de referencia si SoilGrids no responde a tiempo, mostrado como supuesto editable | T06, T10 | Abierta | — |
| D09 | Quién crea la cuenta Earthdata y pide AppEEARS | Cualquier integrante | Hacerlo ya; la extracción puede tardar horas | T03 | Abierta | — |

## Producto y presentación

| ID | Decisión | Opciones | Recomendación | Bloquea | Estado | Decidido por / fecha |
|---|---|---|---|---|---|---|
| D10 | Qué indicadores mostrar | Déficit hídrico en floración y llenado · lluvia en cosecha · días con suelo descubierto · calendario de cosecha · costo e ingreso | Los cuatro primeros; el económico solo con supuestos marcados | T12, T14 | Propuesta | — |
| D11 | Incluir el módulo de café | Sí, como pantalla aparte · solo mencionarlo en el pitch · dejarlo fuera | Mencionarlo como trabajo futuro, salvo que sobre tiempo | T21 | Abierta | — |
| D12 | Usar Meteomatics | Pronóstico a 10 días en la app · no usarlo | Solo si la organización da acceso gratuito para Space Apps 2026 (revisar Global Offers en el menú del avatar). No reemplaza POWER ni IMERG para el histórico | — | Abierta | — |
| D13 | Formato de la demo | Hasta 7 diapositivas · video de 30 s | Diapositivas, más fáciles de corregir a última hora | T18 | Abierta | — |
| D14 | Nombre y dominio | github.io gratis · dominio con la promoción GoDaddy/Porkbun | github.io para la entrega; el dominio es opcional | T17 | Abierta | — |
| D15 | Licencia del repositorio | MIT · Apache-2.0 · CC BY 4.0 para la documentación | MIT para el código y CC BY 4.0 para la documentación | T16 | Abierta | — |
| D16 | Quién presenta y en qué idioma | Integrante y español o inglés (materiales en inglés) | Materiales en inglés; narración según el jurado local | T18, T19 | Abierta | — |
| D17 | Rúbrica que se optimiza | Guía global (Impacto, Creatividad, Validez, Relevancia, Presentación) · imagen local (Impacto, Creatividad, Sostenibilidad, Producto, Presentación) | Confirmar con la organización local (T19) | T18 | Abierta | — |
