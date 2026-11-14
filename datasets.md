# Datasets · Field Shift Guatemala

Datasets que usará o evaluará el proyecto. Actualizado el 14 de noviembre de 2026.

**Estado:** *En uso*, ya descargado · *Planificado*, se usará en el MVP · *Opcional*, si hay tiempo · *Por evaluar*, falta decidir (ver [decisions.md](decisions.md)).
Al usar un dataset, registrar producto, versión, fechas, resolución y cita en la página Project y en el README.

## Datos de NASA

| Dataset | Variables | Resolución y periodo | Propósito en el proyecto | Estado | Acceso |
|---|---|---|---|---|---|
| **NASA POWER, diario (comunidad AG)** | T2M, T2M_MAX, T2M_MIN, T2MDEW, RH2M, WS2M, ALLSKY/CLRSKY_SFC_SW_DWN, PRECTOTCORR, PS | Celda ~0.5° × 0.625° (meteorología MERRA-2) y ~1° (radiación CERES), 1981–presente | Calcular ET₀ (FAO-56 Penman-Monteith), la lluvia del balance hídrico y la exposición térmica de cada secuencia. Script `scripts/descargar_power.py` | En uso | [API diaria](https://power.larc.nasa.gov/docs/services/api/temporal/daily/) · [Data Access Viewer](https://power.larc.nasa.gov/data-access-viewer/) |
| **Humedad del suelo MERRA-2 vía POWER** | GWETTOP (0–5 cm), GWETROOT (0–100 cm), GWETPROF (perfil), EVLAND (mm/día) | Celda ~0.5° × 0.625°, 1981–presente | Humedad de raíces para los años sin SMAP (2001–2014) y referencia para el balance simulado. Es grado de saturación (0–1), no m³/m³ | En uso | [API diaria](https://power.larc.nasa.gov/docs/services/api/temporal/daily/) · [MERRA-2 M2T1NXLND](https://disc.gsfc.nasa.gov/datasets/M2T1NXLND_5.12.4/summary) |
| **SMAP L4 SPL4SMGP v8** | Humedad volumétrica superficial (0–5 cm) y radicular (0–100 cm), m³/m³ | 9 km, cada 3 h (diario en AppEEARS), 2015–presente | Contrastar el balance hídrico y calcular anomalías de años secos o húmedos. Es el dato NASA destacado para la demo | Planificado | [NSIDC, producto](https://nsidc.org/data/spl4smgp/versions/8) · [CMR](https://cmr.earthdata.nasa.gov/search/concepts/C3480440870-NSIDC_CPRD.html) · [AppEEARS](https://appeears.earthdatacloud.nasa.gov/) |
| **SRTM GL1 v3** | Elevación (m) | ~30 m, estático (2000) | Pendiente y posición en la ladera, como indicador de escorrentía | Planificado | [LP DAAC](https://lpdaac.usgs.gov/products/srtmgl1v003/) · [CMR](https://cmr.earthdata.nasa.gov/search/concepts/C2763266360-LPCLOUD.html) · [AppEEARS](https://appeears.earthdatacloud.nasa.gov/) |
| **GPM IMERG Final diario v07** | Precipitación (mm/día) | 0.1° (~11 km), 2000–presente | Contrastar la lluvia de POWER, que parece alta en Chiquimula (tarea T07), y como lluvia alternativa del balance | Planificado | [GPM, IMERG](https://gpm.nasa.gov/data/imerg) · [CMR](https://cmr.earthdata.nasa.gov/search/concepts/C2723754864-GES_DISC.html) · [Giovanni](https://giovanni.gsfc.nasa.gov/giovanni/) |
| **LGRIP30 L3 v2 (2020)** | Tierra de cultivo de secano o de riego | 30 m, 2020 | Ubicar parcelas de secano para elegir la piloto y mostrar un mapa de contexto | Planificado | [CMR](https://cmr.earthdata.nasa.gov/search/concepts/C3262817664-LPCLOUD.html) · [Earthdata Search](https://search.earthdata.nasa.gov/search?q=LGRIP30_L3) |
| **HLS L30/S30 VI v2.0** | NDVI y otros índices de vegetación con máscara de nubes | 30 m, cada 2–3 días combinando Landsat y Sentinel-2, 2013–presente | Contrastar el calendario de cobertura del lote (siembra, cosecha, suelo descubierto) | Opcional | [HLS](https://hls.gsfc.nasa.gov/data-products/) · [CMR L30](https://cmr.earthdata.nasa.gov/search/concepts/C3246892554-LPCLOUD.html) · [CMR S30](https://cmr.earthdata.nasa.gov/search/concepts/C3246894861-LPCLOUD.html) · [AppEEARS](https://appeears.earthdatacloud.nasa.gov/) |
| **GFSAD30 North America Cropland Extent** | Extensión de tierra de cultivo | 30 m, 2010 | Alternativa o complemento de LGRIP30 | Opcional | [CMR](https://cmr.earthdata.nasa.gov/search/concepts/C2763261670-LPCLOUD.html) |
| **ECOSTRESS L3T JET v2** | Evapotranspiración real | 70 m, pasadas irregulares desde la ISS, 2018–presente | Contrastar la ETc estimada, si hay pasadas sin nubes sobre la parcela | Opcional | [CMR](https://cmr.earthdata.nasa.gov/search/concepts/C2076106409-LPCLOUD.html) · [AppEEARS](https://appeears.earthdatacloud.nasa.gov/) |

Todas las descargas de AppEEARS, LP DAAC, NSIDC y GES DISC requieren una cuenta gratuita de [Earthdata Login](https://urs.earthdata.nasa.gov/users/new). POWER no la requiere.

## Datos que no son de NASA

| Dataset | Propósito en el proyecto | Estado | Acceso |
|---|---|---|---|
| **SoilGrids (ISRIC)** | Textura, densidad, carbono y retención de agua para estimar la capacidad de almacenamiento del suelo. La API REST está pausada: usar WCS o WebDAV | Planificado | [Documentación](https://docs.isric.org/globaldata/soilgrids/) · [Opciones de acceso](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_02.html) |
| **FAO-56** | Kc por etapa, profundidad radicular y ecuaciones de ET₀ y del balance hídrico | Planificado | [Kc por etapa](https://www.fao.org/4/x0490e/x0490e0b.htm) · [Balance radicular](https://www.fao.org/4/x0490e/x0490e0e.htm) |
| **Manuales y fichas ICTA y MAGA** | Variedades, días a floración y cosecha, y calendarios de los cultivos del catálogo | Planificado | [ICTA, frijol](https://www.icta.gob.gt/publicaciones/Frijol/Manual%20de%20producci%C3%B3n%20de%20frijol%20ICTA.pdf) · [ICTA, maíz](https://www.icta.gob.gt/publicacionesdemaiz) · [MAGA, calendario](https://www.maga.gob.gt/download/epoca-cultivo-nov14.pdf) |
| **INSIVUMEH, estaciones** | Validar la lluvia y la temperatura de POWER e IMERG con observaciones locales | Opcional | [Variables y estaciones](https://insivumeh.gob.gt/variables_clima/) |
| **MAGA, precios mayoristas** | Referencia de mercado para comparar el resultado económico | Opcional | [Informe mensual, enero de 2026](https://precios.maga.gob.gt/archivos/mensuales/2026/01%20Informe%20De%20Precios%20Agropecuarios%20Mensual%20Enero%202026.pdf) |
| **Meteomatics Weather API** | Pronóstico horario a 10 días para la decisión cercana (sembrar, regar, cosechar). No sirve para el histórico de rotaciones: el plan Free Basic que se ha anunciado solo daba 24 h hacia atrás. Al 14 de noviembre de 2026 sus páginas de registro dan error 404 y la página de precios no menciona un plan gratuito | Por evaluar | [Precios](https://www.meteomatics.com/en/pricing/) · [Primeros pasos](https://www.meteomatics.com/en/api/getting-started/) · [Parámetros](https://www.meteomatics.com/en/api/available-parameters/alphabetic-list/) |
