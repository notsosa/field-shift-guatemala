# Decisiones · Field Shift Guatemala

Decisiones que el equipo debe tomar para la entrega del domingo 15 de noviembre de 2026, 11:59 p. m. Actualizado el 14 de noviembre de 2026.

**Estado:** *Abierta*, sin decidir · *Propuesta*, hay una recomendación que falta confirmar · *Decidida*, acordada por el equipo.
Al decidir, anotar la fecha y quién decidió, cambiar el estado y actualizar [tasks.md](tasks.md) y el [handoff](../conocimiento/datos-y-comparacion-de-rotaciones-guatemala.md) si cambia algo.

## Urgentes (bloquean el trabajo de hoy)

| ID | Decisión | Opciones | Recomendación | Bloquea | Estado | Decidido por / fecha |
|---|---|---|---|---|---|---|
| D01 | Parcela piloto (coordenada) | Cabecera de Chiquimula (provisional); otra parcela del Corredor Seco; La Plazuela, San Martín Jilotepeque (caso maíz–frijol de 2026); finca de uno de los cafetaleros entrevistados | **Mover el punto.** El provisional (14.80, −89.54) cae en zona urbana: ESA WorldCover 2021 lo clasifica «Construido» y solo el 1.4 % del recorte de ±0.1° es cultivo. Candidato: polígono de **granos básicos** de 102 ha del mapa MAGA de cobertura 2025, centroide **14.8250, −89.5312**, a 2.9 km de la cabecera, 373 m (AW3D30). Alternativa: polígono de 3 112 ha en 14.8475, −89.5875, a 844 m. WorldCover marca ambos como pastizal o arbusto: confunde las milpas pequeñas, así que se prefiere el mapa del MAGA. A ~400 m solo **ICTA Ligero** (50–1200 m) y **ICTA Patriarca** (50–1500 m) cubren la altitud entre los frijoles del cuadro 1. Al cambiar el punto, volver a correr los scripts de `scripts/` con `--lat --lon` | T01, T03–T07, todo el análisis | Propuesta | — |
| D02 | Secuencias a comparar | Práctica actual · maíz → frijol · frijol → maíz · incluir una cobertura (por ejemplo mucuna, ensayo CRIA) | Las tres primeras; la cobertura como extra | T08, T11, T12 | Propuesta | — |
| D03 | Variedades de referencia | Maíz (guía ICTA oriente 2015): B-1, HB-83 o Maya QPM (4 meses) · B-5 (3 meses) o B-7 (4 meses) para zonas con poca lluvia · Frijol: ICTA Ligero (64–70 días a cosecha), Altense (115 días) o Hunapú (95 o 120 días según la publicación) | Para el oriente bajo: maíz ICTA B-5 (3 meses) y B-1 (4 meses); frijol ICTA Ligero (64–70 días) y Patriarca (68–70 días). Parámetros en `datos/cultivos/maiz_frijol.json` | T08, T11 | Propuesta | — |
| D04 | Formato del prototipo | Web estática adaptable a celular · app móvil · web con backend | Web estática en GitHub Pages con datos precalculados en JSON | T02, T13–T17 | Propuesta | — |
| D05 | Lenguaje del motor de cálculo | Python offline que genera JSON · JavaScript en el navegador | Python para descargar y calcular; la web solo muestra los JSON | T09–T12 | Abierta | — |
| D06 | Fuente de lluvia del balance | POWER PRECTOTCORR (diaria, ya descargada) · CHIRPS v2 diario (0.05°, satélite + estaciones) · GPM IMERG diario · JAXA GSMaP (mensual descargado) | POWER sobreestima frente a GSMaP (≈ +25 % de media; hasta +85 % en 2024). **Usar CHIRPS diario** para el balance, porque integra estaciones de Centroamérica, y mostrar POWER e IMERG como contraste. Si no se logra descargar CHIRPS a tiempo: usar POWER diario reescalado mes a mes con GSMaP (factor = GSMaP/POWER de cada mes) y declararlo como supuesto | T07, T10 | Propuesta | — |
| D07 | Humedad del suelo NASA | MERRA-2 vía POWER (ya descargada, sin login) · SMAP L4 vía AppEEARS (necesita Earthdata y puede tardar horas) · ambas | Ambas: POWER para 2001–2014 y SMAP para 2015–2025 y para la demo | T03, T05 | Propuesta | — |
| D08 | Suelo de la parcela | SoilGrids vía WCS · suelo de referencia con supuesto explícito | SoilGrids ya descargado (`datos/suelo/`): franco arcillo-arenoso en superficie y franco arcilloso en profundidad (28–33 % arcilla, 41–46 % arena), θ a 33 kPa ≈ 0.32 y a 1500 kPa ≈ 0.17 m³/m³, **agua disponible total 0–100 cm ≈ 150 mm**. Usarlo como valor inicial editable; recalcular si se mueve la parcela (D01) | T06, T10 | Propuesta | — |
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
