// GENERADO por tool/generar_plagas.dart. No editar a mano: edita la investigación y regenera.
// Fuente: investigacion/plagas-7-cultivos-guatemala/confirmadas/ del repositorio del equipo,
// commit f978adc, revisión 2026-11-15.
library;

import '../plagas_tipos.dart';

/// Commit del repositorio del equipo del que salen estos datos.
const plagasFuenteCommit = 'f978adc';

/// Fecha de revisión de la investigación.
const plagasFechaRevision = '2026-11-15';

/// SHA-256 de los archivos de la investigación (según su verificacion.json).
const plagasFuenteSha256 = <String, String>{
  'plagas_confirmadas.json': 'd6b77c1a07f4908d7b877fe1b1d9381bd33b46005a06c6406cb1c0361b1944fd',
  'fuentes.json': '78d47f8e9972342d488a5599aeceddad3e84437ee279836aee978ede12676af4',
};

const _s05 = FuentePlaga(
  id: 'S05',
  titulo: 'Memoria de Labores ICTA 2023',
  institucion: 'ICTA',
  fecha: '2023',
  url: 'https://www.icta.gob.gt/publicaciones/Memoriasicta/Memoria%20de%20Labores%20ICTA%202023.pdf',
);

const _s09 = FuentePlaga(
  id: 'S09',
  titulo: 'Una nueva plaga en el cultivo de frijol en Guatemala: Megalurothrips usitatus',
  institucion: 'ICTA',
  fecha: 'Muestreo 2022; página consultada 2026',
  url: 'https://icta.gob.gt/plagacultivofrijolGuatemala.html',
);

const _s16 = FuentePlaga(
  id: 'S16',
  titulo: 'Manual de ensayos de eficacia de plaguicidas',
  institucion: 'ICTA/JICA, Dardón y Sagayama',
  fecha: '2001; ensayo 2000',
  url: 'https://www.icta.gob.gt/publicaciones/Plaguicidas/Manual%20de%20ensayos%20eficacia%20plaguicidas%20ICTA%20JICA%20Dardon-Sagayama%202001.pdf',
);

const _s17 = FuentePlaga(
  id: 'S17',
  titulo: 'Diagnóstico entomológico y semilla de malezas como plagas endémicas y cuarentenarias para Guatemala',
  institucion: 'USAC, Edgar Arturo García Salas Cordón',
  fecha: 'Mayo 2009; muestras 2007',
  url: 'https://www.repositorio.usac.edu.gt/8989/1/Edgar%20Arturo%20Garc%C3%ADa%20Salas%20Cord%C3%B3n.pdf',
);

const _s20 = FuentePlaga(
  id: 'S20',
  titulo: 'La mosca que frena las exportaciones hortícolas del altiplano de Guatemala',
  institucion: 'UVG, Ronaldo Pérez, Arturo Méndez y Charles MacVean',
  fecha: 'Noviembre 1997, Revista UVG 7:10–16',
  url: 'https://repositorio.uvg.edu.gt/server/api/core/bitstreams/bbee17fe-bceb-41e7-b960-e7e1e383b219/content',
);

const _s21 = FuentePlaga(
  id: 'S21',
  titulo: 'Control de gallina ciega en el cultivo de brocoli',
  institucion: 'ICTA/IPM-CRSP, Carranza, Dardón, Calderón y Weller; Revista Agricultura',
  fecha: 'Ensayo agosto–noviembre 1998; fecha editorial no fijada',
  url: 'https://arcasavi.com/wp-content/uploads/2020/05/revistaagricultura2_23.pdf',
);

const _s22 = FuentePlaga(
  id: 'S22',
  titulo: 'Evaluación de productos contra Plutella xylostella en brócoli, trabajo de graduación',
  institucion: 'USAC, Elmer Tomás Aldana Ávila',
  fecha: 'EPS febrero–noviembre 2006; fecha editorial no fijada',
  url: 'https://www.repositorio.usac.edu.gt/6251/1/ELMER%20TOMAS%20ALDANA%20AVILA.pdf',
);

const _s24 = FuentePlaga(
  id: 'S24',
  titulo: 'Ensayo de lechuga hidropónica en Pachalí, trabajo de graduación',
  institucion: 'USAC, Nidia Barrios',
  fecha: '2004',
  url: 'https://biblioteca.usac.edu.gt/tesis/01/01_2071.pdf',
);

const _s25 = FuentePlaga(
  id: 'S25',
  titulo: 'Servicios de monitoreo de trips en lechuga en finca Bejo, trabajo de graduación',
  institucion: 'USAC, Mucía Sipac',
  fecha: '2017; trabajo de campo 2016',
  url: 'https://biblioteca.usac.edu.gt/tesis/01/01_3159.pdf',
);

/// Plagas por cultivo según la investigación del equipo, sin "otra" al final.
const plagasInvestigacion = <String, List<TipoPlaga>>{
  'maiz': [
    TipoPlaga(
      'acaro-del-maiz', 'Ácaro del maíz', 'Maize mite',
      registros: [
        RegistroPlaga(
          id: 'maiz-06',
          taxon: 'Oligonychus pratensis',
          resolucion: 'especie',
          danio: TextoBi('Hojas', 'Leaves'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Quetzaltenango y Totonicapán', 'Quetzaltenango and Totonicapán'),
          periodo: TextoBi('2023', '2023'),
          limite: TextoBi('Diagnóstico ICTA/VISAR; no inferir presencia en Chiquimula.', 'ICTA/VISAR diagnosis; do not infer presence in Chiquimula.'),
          referencias: [
            ReferenciaPlaga(_s05, 'Diagnóstico del daño ocasionado por el ácaro del maíz'),
          ],
        ),
      ],
    ),
    otraPlaga,
  ],
  'frijol': [
    TipoPlaga(
      'trips-de-las-flores', 'Trips de las flores', 'Flower thrips',
      registros: [
        RegistroPlaga(
          id: 'frijol-01',
          taxon: 'Megalurothrips usitatus',
          resolucion: 'especie',
          danio: TextoBi('Flores y vainas', 'Flowers and pods'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Petén, El Progreso, Zacapa y Chimaltenango (muestreos 2022); San Jerónimo, Baja Verapaz (estudio descrito por ICTA)', 'Petén, El Progreso, Zacapa and Chimaltenango (2022 sampling); San Jerónimo, Baja Verapaz (study described by ICTA)'),
          periodo: TextoBi('2022', '2022'),
          limite: TextoBi('La página ICTA describe muestreos 2022 y observaciones en frijol. No se extrapolan sus porcentajes de daño a otras localidades.', 'The ICTA page describes 2022 sampling and observations in beans. Its damage percentages are not extrapolated to other localities.'),
          referencias: [
            ReferenciaPlaga(_s09, 'Distribución y síntomas'),
          ],
        ),
      ],
    ),
    TipoPlaga(
      'mosca-minadora', 'Mosca minadora', 'Leaf miner fly',
      registros: [
        RegistroPlaga(
          id: 'frijol-08',
          taxon: 'Liriomyza huidobrensis',
          resolucion: 'especie',
          danio: TextoBi('Minas foliares', 'Leaf mines'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Departamento de Guatemala', 'Guatemala department'),
          periodo: TextoBi('Muestreo descrito en 1996; publicación 1997', 'Sampling described in 1996; published 1997'),
          limite: TextoBi('Registro taxonómico histórico en Phaseolus vulgaris; departamento de Guatemala. Se conserva el nombre de la identificación de la época.', 'Historical taxonomic record on Phaseolus vulgaris; Guatemala department. The name from the identification of that time is kept.'),
          referencias: [
            ReferenciaPlaga(_s20, 'p.13 y Cuadro 1, p.14/PDF 5'),
          ],
        ),
        RegistroPlaga(
          id: 'frijol-20',
          taxon: 'Liriomyza sabaziae',
          resolucion: 'especie',
          danio: TextoBi('Minas foliares', 'Leaf mines'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Departamento de Guatemala', 'Guatemala department'),
          periodo: TextoBi('Muestreo descrito en 1996; publicación 1997', 'Sampling described in 1996; published 1997'),
          limite: TextoBi('Registro histórico en Phaseolus vulgaris; nombre usado en el artículo, sin revisión molecular actual.', 'Historical record on Phaseolus vulgaris; name used in the article, without current molecular review.'),
          referencias: [
            ReferenciaPlaga(_s20, 'Cuadro 2, p.14/PDF 5, bloqueC'),
          ],
        ),
      ],
    ),
    otraPlaga,
  ],
  'cebolla': [
    TipoPlaga(
      'trips-de-la-cebolla', 'Trips de la cebolla', 'Onion thrips',
      registros: [
        RegistroPlaga(
          id: 'cebolla-01',
          taxon: 'Thrips tabaci',
          resolucion: 'especie',
          danio: TextoBi('Hojas', 'Leaves'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Jutiapa, Jalapa y Huehuetenango', 'Jutiapa, Jalapa and Huehuetenango'),
          periodo: TextoBi('Enero de 2007', 'January 2007'),
          limite: TextoBi('19 muestras de cebolla, 11 destinadas a entomología. No equivale a 11 fincas ni estima prevalencia.', '19 onion samples, 11 of them for entomology. This does not equal 11 farms and does not estimate prevalence.'),
          referencias: [
            ReferenciaPlaga(_s17, 'p.65, cultivo de cebolla'),
          ],
        ),
      ],
    ),
    TipoPlaga(
      'mosca-minadora', 'Mosca minadora', 'Leaf miner fly',
      registros: [
        RegistroPlaga(
          id: 'cebolla-02',
          taxon: 'Liriomyza huidobrensis',
          resolucion: 'especie',
          danio: TextoBi('Minas foliares', 'Leaf mines'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Chimaltenango (ensayo 2000); Chimaltenango, Sololá y Quetzaltenango (tablaUVG 1997)', 'Chimaltenango (2000 trial); Chimaltenango, Sololá and Quetzaltenango (UVG table, 1997)'),
          periodo: TextoBi('Muestreo UVG descrito en 1996, publicación 1997; ensayo ICTA 2000', 'UVG sampling described in 1996, published 1997; ICTA trial 2000'),
          limite: TextoBi('Dos fuentes locales: identificación histórica UVG y ensayo ICTA/JICA. Una relación cultivo–taxón, sin duplicar registros.', 'Two local sources: a historical UVG identification and an ICTA/JICA trial. One crop–taxon relationship, without duplicating records.'),
          referencias: [
            ReferenciaPlaga(_s16, 'pp.34–35/PDF 39–40'),
            ReferenciaPlaga(_s20, 'p.13 y Cuadro 1, p.14/PDF 5'),
          ],
        ),
      ],
    ),
    otraPlaga,
  ],
  'brocoli': [
    TipoPlaga(
      'palomilla-dorso-de-diamante', 'Palomilla dorso de diamante', 'Diamondback moth',
      registros: [
        RegistroPlaga(
          id: 'brocoli-01',
          taxon: 'Plutella xylostella',
          resolucion: 'especie',
          danio: TextoBi('Hojas e inflorescencia', 'Leaves and inflorescence'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Altiplano central y occidental de Guatemala; precisión regional, sin fijar aquí el sitio individual del ensayo', 'Central and western highlands of Guatemala; regional precision, without fixing the individual trial site here'),
          periodo: TextoBi('Febrero–noviembre de 2006, período del EPS', 'February–November 2006, EPS period'),
          limite: TextoBi('Resumen original describe evaluación contra esta especie en brócoli. Acceso al texto íntegro limitado; no se asigna cada localidad del EPS al ensayo.', 'The original abstract describes an evaluation against this species in broccoli. Access to the full text is limited; each EPS locality is not assigned to the trial.'),
          referencias: [
            ReferenciaPlaga(_s22, 'Resumen, p.xxiii'),
          ],
        ),
      ],
    ),
    TipoPlaga(
      'gallina-ciega', 'Gallina ciega', 'White grub',
      registros: [
        RegistroPlaga(
          id: 'brocoli-02',
          taxon: 'Phyllophaga spp.',
          resolucion: 'grupo',
          danio: TextoBi('Raíces', 'Roots'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Xecoíl, Santa Apolonia, Chimaltenango', 'Xecoíl, Santa Apolonia, Chimaltenango'),
          periodo: TextoBi('Agosto–noviembre 1998', 'August–November 1998'),
          limite: TextoBi('Registro histórico con muestreo previo en las parcelas. P.obsoleta y P.menetriesi quedan como detalle del complejo, sin sumar entradas.', 'Historical record with prior sampling in the plots. P. obsoleta and P. menetriesi remain as detail of the complex, without adding entries.'),
          referencias: [
            ReferenciaPlaga(_s21, 'PDF 20–22, métodos PDF 21'),
          ],
        ),
      ],
    ),
    TipoPlaga(
      'mosca-minadora', 'Mosca minadora', 'Leaf miner fly',
      registros: [
        RegistroPlaga(
          id: 'brocoli-04',
          taxon: 'Liriomyza huidobrensis',
          resolucion: 'especie',
          danio: TextoBi('Minas foliares', 'Leaf mines'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Chimaltenango', 'Chimaltenango'),
          periodo: TextoBi('Muestreo descrito en 1996; publicación 1997', 'Sampling described in 1996; published 1997'),
          limite: TextoBi('Registro histórico; nombre de la identificación de la época. Tabla original inspeccionada visualmente.', 'Historical record; name from the identification of that time. Original table inspected visually.'),
          referencias: [
            ReferenciaPlaga(_s20, 'p.13 y Cuadro 1, p.14/PDF 5'),
          ],
        ),
      ],
    ),
    otraPlaga,
  ],
  'lechuga': [
    TipoPlaga(
      'pulgon', 'Pulgón', 'Aphid',
      registros: [
        RegistroPlaga(
          id: 'lechuga-01',
          taxon: 'Aphis sp.',
          resolucion: 'grupo',
          danio: TextoBi('Plantas del ensayo', 'Trial plants'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Pachalí, San Juan Sacatepéquez', 'Pachalí, San Juan Sacatepéquez'),
          periodo: TextoBi('2004', '2004'),
          limite: TextoBi('Observación durante ensayo hidropónico; sin identificación a especie.', 'Observation during a hydroponic trial; not identified to species.'),
          referencias: [
            ReferenciaPlaga(_s24, '6.7.3, p.32/PDF 45 y p.36/PDF 49'),
          ],
        ),
      ],
    ),
    TipoPlaga(
      'trips', 'Trips', 'Thrips',
      registros: [
        RegistroPlaga(
          id: 'lechuga-02',
          taxon: 'Frankliniella occidentalis',
          resolucion: 'especie',
          danio: TextoBi('Capturas en monitoreo de lechuga', 'Catches in lettuce monitoring'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Finca Bejo, Parramos, Chimaltenango', 'Finca Bejo, Parramos, Chimaltenango'),
          periodo: TextoBi('Trabajo de campo 2016; tesis 2017', 'Fieldwork 2016; thesis 2017'),
          limite: TextoBi('Resultados de monitoreo; el autor asigna especie, sin detalle localizado de claves ni ejemplares de referencia.', 'Monitoring results; the author assigns the species, with no located detail of keys or reference specimens.'),
          referencias: [
            ReferenciaPlaga(_s25, '3.3, pp.148–156/PDF 174–182'),
          ],
        ),
      ],
    ),
    TipoPlaga(
      'mosca-minadora', 'Mosca minadora', 'Leaf miner fly',
      registros: [
        RegistroPlaga(
          id: 'lechuga-03',
          taxon: 'Liriomyza huidobrensis',
          resolucion: 'especie',
          danio: TextoBi('Minas foliares', 'Leaf mines'),
          etapa: TextoBi('campo', 'field'),
          lugar: TextoBi('Chimaltenango', 'Chimaltenango'),
          periodo: TextoBi('Muestreo descrito en 1996; publicación 1997', 'Sampling described in 1996; published 1997'),
          limite: TextoBi('Registro histórico con identificación taxonómica; no demuestra frecuencia actual ni presencia en Chiquimula.', 'Historical record with taxonomic identification; it does not show current frequency or presence in Chiquimula.'),
          referencias: [
            ReferenciaPlaga(_s20, 'p.13 y Cuadro 1, p.14/PDF 5'),
          ],
        ),
      ],
    ),
    otraPlaga,
  ],
};

/// Cultivos con plagas documentadas por la revisión del equipo fuera de la tabla de
/// registros confirmados. No son registros ni plagas elegibles.
const plagasCobertura = <String, CoberturaPlaga>{
  'papa': CoberturaPlaga(
    entradas: 11,
    tipos: [
      TextoBi('guías ICTA', 'ICTA guides'),
      TextoBi('reporte mixto', 'mixed report'),
    ],
    interpretacion: TextoBi('Papa y ajonjolí tienen plagas documentadas. Su omisión de esta tabla no representa ausencia de plagas ni riesgo cero.', 'Potato and sesame have documented pests. Their omission from this table does not mean an absence of pests or zero risk.'),
  ),
  'ajonjoli': CoberturaPlaga(
    entradas: 7,
    tipos: [
      TextoBi('reportes de productores', 'producer reports'),
      TextoBi('reporte mixto', 'mixed report'),
      TextoBi('inventario histórico', 'historical inventory'),
    ],
    interpretacion: TextoBi('Papa y ajonjolí tienen plagas documentadas. Su omisión de esta tabla no representa ausencia de plagas ni riesgo cero.', 'Potato and sesame have documented pests. Their omission from this table does not mean an absence of pests or zero risk.'),
  ),
};
