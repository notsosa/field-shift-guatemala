// GENERADO por tool/generar_pesos_cafe.mjs. No editar a mano: se vuelve a generar.
//
// Fuente: web/data/coffee_sources.json
// Commit de la fuente: 62181509a051de476b52ab2e0cce71f59ada06e0
// SHA-256 del archivo fuente: f536f425df723b4f5cd96a00ed5a4fff8dc33baca2a60bc883305ebbeaa31c6f
// Textos, fuentes y confianza de los avisos de café. La clave es la `sourceKey` de web/js/model/coffee.js.
// Los textos están en español, como en el archivo fuente; `fuenteCorta` y `nivelConfianza` se usan en la pantalla.
library;

/// Commit del repositorio del equipo del que salen estos textos.
const fuentesCafeCommit = '62181509a051de476b52ab2e0cce71f59ada06e0';

/// SHA-256 del archivo fuente.
const fuentesCafeSha256 = 'f536f425df723b4f5cd96a00ed5a4fff8dc33baca2a60bc883305ebbeaa31c6f';

/// Un texto con su fuente y su nivel de confianza.
class FuenteCafe {
  const FuenteCafe({
    required this.texto,
    required this.fuente,
    required this.fuenteCorta,
    required this.url,
    required this.confianza,
    required this.nivelConfianza,
  });

  final String texto;
  final String fuente;
  final String fuenteCorta;
  final String url;
  final String confianza;

  /// «alta», «media-alta», «media», «baja-media», «baja», «orientativa» o el texto del archivo fuente.
  final String nivelConfianza;
}

const fuentesCafe = <String, FuenteCafe>{
  'roya_favorable': FuenteCafe(
    texto: 'Condiciones favorables para roya: temperatura media de 21–25 °C (óptimo de germinación) con rango diurno menor al normal del sitio en ese mes; el rango diurno estrecho es el factor de campo más consistente de las epidemias fuertes.',
    fuente: 'Avelino et al. 2015, Food Security 7:303-321 (crisis de roya en Colombia y América Central, 2008-2013; Guatemala 2012, 1,224 fincas)',
    fuenteCorta: 'Avelino et al. 2015',
    url: 'https://link.springer.com/article/10.1007/s12571-015-0446-9',
    confianza: 'media-alta; correlación de campo, no un modelo (los autores dicen que no hay un modelo reconocido que prediga la epidemia)',
    nivelConfianza: 'media-alta',
  ),
  'roya_posible': FuenteCafe(
    texto: 'Rango amplio de germinación de la roya: 16–28 °C, con agua líquida en el envés de la hoja y poca luz.',
    fuente: 'Anacafe/Cedicafe, boletín técnico abril 2015, "Manejo integrado de la roya anaranjada"',
    fuenteCorta: 'Anacafé/Cedicafé 2015',
    url: 'https://www.anacafe.org/uploads/file/a0782d43ce214d408c7077394059f17f/17-situacion-roya.pdf',
    confianza: 'orientativa; condición necesaria, no suficiente',
    nivelConfianza: 'orientativa',
  ),
  'roya_latencia': FuenteCafe(
    texto: 'Periodo de latencia (de la infección a la esporulación): 34–37 días al sol y 31–35 días bajo sombra ("reportes indican"); se resume como 31–37 días, unas 5 semanas.',
    fuente: 'Anacafe/Cedicafe, boletín técnico abril 2015',
    fuenteCorta: 'Anacafé/Cedicafé 2015',
    url: 'https://www.anacafe.org/uploads/file/a0782d43ce214d408c7077394059f17f/17-situacion-roya.pdf',
    confianza: 'media',
    nivelConfianza: 'media',
  ),
  'minador': FuenteCafe(
    texto: 'Minador: poblaciones más frecuentes con temperaturas altas, poca humedad relativa y periodos secos prolongados (Costa Rica 2019); el boletín de Anacafe de El Niño 2026 dice que el calor acelera su reproducción. En Chiapas la incidencia fue mayor en la época lluviosa: la evidencia se contradice, por eso es "probable".',
    fuente: 'Ramírez-Valerio y García-Jiménez 2021, Agronomía Costarricense 45(2):143-153; Anacafe, boletín meteorológico especial ENOS 2026; Lomelí-Flores 2009 (Chiapas, solo resumen)',
    fuenteCorta: 'Ramírez-Valerio y García-Jiménez 2021; Anacafé 2026',
    url: 'https://www.scielo.sa.cr/pdf/ac/v45n2/0377-9424-ac-45-02-143.pdf',
    confianza: 'baja-media',
    nivelConfianza: 'baja-media',
  ),
  'antracnosis': FuenteCafe(
    texto: 'Antracnosis: oportunista en plantas debilitadas (roya, estrés, mala nutrición); en una finca de Patulul (870 m, 2017-18) la incidencia en hojas subió de abril a agosto. Aviso ligado al estrés de la planta, no una predicción.',
    fuente: 'Campos-Almengor (Cedicafe), epidemiología de la antracnosis, finca Los Tarrales, Patulul; Anacafe, manejo integrado de plagas y enfermedades emergentes',
    fuenteCorta: 'Campos-Almengor (Cedicafé); Anacafé',
    url: 'https://www.anacafe.org/uploads/file/53becfe77b6f4528b94db9589bb54117/Manejo-de-plagas-y-enfermedades-2021-2016.pdf',
    confianza: 'baja-media; referencia de una finca (Patulul), un año',
    nivelConfianza: 'baja-media',
  ),
  'abono_ventanas': FuenteCafe(
    texto: 'Ventanas de fertilización de Anacafe: mayo–junio (inicio del invierno), agosto–septiembre y octubre–noviembre (antes de que finalicen las lluvias); abonar con humedad en el suelo.',
    fuente: 'Guía Técnica Anacafe 2014 (citada en Pons, Pronósticos estacionales de clima); Anacafe, boletines meteorológicos julio y agosto 2026',
    fuenteCorta: 'Anacafé, Guía Técnica 2014',
    url: 'https://www.anacafe.org/uploads/file/71c6dd5da5634c16acc79c8a92c3bbbb/02__Pronosticos_estacionales.pdf',
    confianza: 'alta; la regla de humedad (Dr menor que RAW y 10 mm en 7 días) es una convención de este modelo',
    nivelConfianza: 'alta',
  ),
  'abono_suelo_seco': FuenteCafe(
    texto: 'No aplique abono si el suelo está completamente seco, porque la planta no lo absorbe.',
    fuente: 'Anacafe, boletín meteorológico especial ENOS 2026',
    fuenteCorta: 'Anacafé, boletín ENOS 2026',
    url: 'https://www.anacafe.org/uploads/file/df18983079ea425395bdd94f654a97ad/02._Boletin_meteorologico_especial_ENOS_2026.pdf',
    confianza: 'alta',
    nivelConfianza: 'alta',
  ),
  'fao56_cafe': FuenteCafe(
    texto: 'Kc 0.90/0.95/0.95 (suelo desnudo; con malezas 1.05/1.10/1.10), raíz 0.9–1.5 m, p = 0.40. FAO no da Ky para café.',
    fuente: 'FAO-56 (Allen et al. 1998), cuadros 12 y 22',
    fuenteCorta: 'FAO-56 (Allen et al. 1998)',
    url: 'https://www.fao.org/4/x0490e/x0490e0b.htm',
    confianza: 'alta',
    nivelConfianza: 'alta',
  ),
  'sombra_padovan': FuenteCafe(
    texto: 'Con sombra: evaporación del suelo 1.98 contra 2.50 mm/día en el periodo húmedo, sin diferencia en el seco; transpiración de árboles: siempreverde 0.2 mm/día, decidua 0.06–1.2 mm/día. Un solo sitio de Nicaragua.',
    fuente: 'Padovan et al. 2018, Agric. For. Meteorol. 248:1-14 (Nicaragua, 455 m, 1470 mm/año, copa 57 % de irradiancia)',
    fuenteCorta: 'Padovan et al. 2018',
    url: 'https://doi.org/10.1016/j.agrformet.2017.08.036',
    confianza: 'una referencia, un sitio',
    nivelConfianza: 'una referencia, un sitio',
  ),
  'floracion': FuenteCafe(
    texto: 'Lluvias desde 10 mm disparan la floración; las flores abren 8–10 días después de la lluvia o el riego tras un periodo seco. Ventanas sensibles: 0–90 días (cuajado y expansión del fruto) y 91–120 días (llenado del grano).',
    fuente: 'Anacafe, Guía Técnica 2014 vía Pons; Guía de variedades Anacafe 2020; Anzueto, Revista El Cafetal No. 44 (2016)',
    fuenteCorta: 'Anacafé, Guía Técnica 2014',
    url: 'https://www.anacafe.org/uploads/file/42eb19c97ee84fd28314481d13a0f8b4/El-Cafetal-05.pdf',
    confianza: 'media; el 9 de mayo sin disparo y el día exacto son convenciones de este modelo',
    nivelConfianza: 'media',
  ),
  'riego_20mm': FuenteCafe(
    texto: 'Lámina de riego complementario de 20 mm (entre 0, 10, 20 y 30 mm): favoreció crecimiento y productividad en un ensayo. Es la única lámina con ensayo centroamericano en las notas.',
    fuente: 'Duarte-Canales et al. 2016, Calera 16(27):69-74 (Carazo, Nicaragua, 2013-14; una finca)',
    fuenteCorta: 'Duarte-Canales et al. 2016',
    url: 'https://repositorio.una.edu.ni/3980/1/ppf06d812r.pdf',
    confianza: 'baja; una finca',
    nivelConfianza: 'baja',
  ),
};
