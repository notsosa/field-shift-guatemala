"""Construye corpus de pre-entrenamiento (un .txt por lengua maya) + shards JSONL + CREDITOS.md.

Entradas
  --pdfs   carpeta con los PDF descargados (Lenguas Mayas/)
  --web    carpeta con los JSONL de scripts/web_scraping/descargar_diccionarios_web.py
  --out    carpeta de salida (se crea extraido/, final/, shards/)

Salida
  final/<lengua>.txt              documentos separados por "\\n<|endoftext|>\\n"
  shards/<lengua>/train-000NN.jsonl   {"text", "lang", "source"} para datasets.load_dataset("json", ...)
  final/estadisticas.json, final/CREDITOS.md

Requiere pdftotext (poppler) en el PATH. Sin dependencias externas de Python.
"""
import argparse
import hashlib
import json
import random
import re
import subprocess
import unicodedata
import zipfile
from collections import Counter, defaultdict
from pathlib import Path

EOS = "<|endoftext|>"
LENGUAS = {"kiche": "k'iche'", "kaqchikel": "kaqchikel", "qeqchi": "q'eqchi'",
           "mam": "mam"}

# ------------------------------------------------------------------ FUENTES
# tipo: "texto" (prosa) | "dicc" (diccionario/vocabulario en PDF: se conservan las líneas)
ALMG = "Academia de Lenguas Mayas de Guatemala (ALMG)"
CNB = "Antología de cuentos en k'iche', CNB Guatemala (cnbguatemala.org)"
PDFS = [
    # --- K'iche'
    ("Alaj imul - CNB Guatemala.pdf", "kiche", "texto", "Alaj imul", "Lilian Maribel Calderón (Zunil, Quetzaltenango)", CNB, ""),
    ("Alaj kuk - CNB Guatemala.pdf", "kiche", "texto", "Alaj kuk", "Lilian Maribel Calderón (Zunil, Quetzaltenango)", CNB, ""),
    ("Jas uchakuxik kaxlanwa - CNB Guatemala.pdf", "kiche", "texto", "Jas uchakuxik kaxlanwa", "Manuel Hernández Pocol (Cantel, Quetzaltenango)", CNB, ""),
    ("Jun ajyuq’ - CNB Guatemala.pdf", "kiche", "texto", "Jun ajyuq'", "Herlindo Calel Vicente (San Carlos Sija, Quetzaltenango)", CNB, ""),
    ("Jun lol ketz’an ruk’ le ne’ - CNB Guatemala.pdf", "kiche", "texto", "Jun lol ketz'an ruk' le ne'", "Juan José Menchú Ordóñez (San Pedro Jocopilas, Quiché)", CNB, ""),
    ("Jupaj kapaj tzij - CNB Guatemala.pdf", "kiche", "texto", "Jupaj kapaj tzij (presentación de la antología)", "Docentes participantes de la antología (sin nombre individual en el texto)", CNB, ""),
    ("Keb’ ajyuq’ab’ - CNB Guatemala.pdf", "kiche", "texto", "Keb' ajyuq'ab'", "Rocita Lima Puac Yac (Cantel, Quetzaltenango)", CNB, ""),
    ("Texto-Avanzado-Kiche.pdf", "kiche", "texto", "Texto avanzado K'iche'", "Wel Raxulew", ALMG, ""),
    ("Antecedentes-Historicos-Kiche.pdf", "kiche", "texto", "Antecedentes históricos de la Comunidad Lingüística K'iche'", "Comunidad Lingüística K'iche' (sin autor individual identificado)", ALMG, ""),
    ("vocabulario-kiche-almg-2004.pdf", "kiche", "dicc", "Vocabulario K'iche' (2.ª ed.)", "Coordinación: Lic. Cecilio Tuyuc Sucuc; técnica encargada: Gloria Enoe Son Chonay (Programa de Estudios Lingüísticos)", ALMG + ", Comunidad Lingüística K'iche'", "2004"),
    ("BKiche_DiccioKE.pdf", "kiche", "dicc", "Diccionario K'iche' - Español (Ri Tyoxlaj Wuj)", "Autor no identificado en el documento", "", ""),
    # --- Kaqchikel
    ("kaqchikel_choltzij.pdf", "kaqchikel", "dicc", "Kaqchikel Choltzij: kolon chuqa' k'ak'a taq tzij", "Kaqchikel Cholchi' (dir. Lolmay Pedro Oscar García Matzar); recopilación: Rony Arnoldo Chipix Otzoy, Darwin Alvaro Bala; revisión: Rafael Hernández Huit, Victor Par; asesoría: Israel Raxjal; validación: Pedro Morejon Patzán, Maricela Marroquin, Juan Esteban Ajsivinac; diagramación: Fidel Calel Castro; colaboradores: Peter Rohloff, Robert Henderson", ALMG + ", Kaqchikel Cholchi'", "2008-2011"),
    ("Astronomia-Kaqchikel.pdf", "kaqchikel", "texto", "Astronomía Kaqchikel", "Investigador: Leonardo Enrique Teleguario Ajpatunayché; revisión: Pedro Morejon Patzán, Carlos Emilio Guarcax González, Rosalbina Sisimit Perén, Pablo Chex Curuchich, Juan Esteban Ajsivinac Sián, Alba Elizabeth Cutzal Calel", ALMG + ", Kaqchikel Cholchi'", "2009"),
    ("Filosofia-Kaqchikel.pdf", "kaqchikel", "texto", "Filosofía Kaqchikel", "Adolfo Chicol Gámez, María del Carmen Tuy Tococh, Cristina Nicolás Sirin", ALMG + ", Kaqchikel Cholchi'", "2008"),
    ("Milpa-Kaqchikel.pdf", "kaqchikel", "texto", "La milpa, sistema suelo y su uso medicinal, fase II", "Investigadora: Yesika María Karina Tucubal Sanahí; coordinación: Ana Luvia Mux Chuy", ALMG + ", Comunidad Lingüística Kaqchikel", "2023"),
    ("Variacion-Dialectal-Kaqchikel.pdf", "kaqchikel", "texto", "Variación dialectal en Kaqchikel", "Filiberto Patal Majzul, Lolmay Pedro Oscar García Matzar, Ixchel Carmelina Espantzay Serech; investigación de campo: Juana Sánchez Pérez y equipo OKMA", "Cholsamaj / OKMA", "2000"),
    ("208.pdf", "kaqchikel", "dicc", "Vocabulario Cakchiquel-Español para el médico y estudiante de medicina (tesis)", "Flora Cutzal Otzoy", "Facultad de Ciencias Médicas, Universidad de San Carlos de Guatemala", ""),
    ("Conversemos-en-Kaqchikel.pdf", "kaqchikel", "texto", "Conversemos en Kaqchikel", "No verificado (PDF escaneado)", "", ""),
    ("Matematicas-Neologismos-Kaqchikel.pdf", "kaqchikel", "texto", "Neologismos de matemáticas en Kaqchikel", "No verificado (PDF escaneado)", "", ""),
    ("Toponimia-Kaqchikel.pdf", "kaqchikel", "texto", "Toponimia Kaqchikel", "No verificado (PDF escaneado)", "", ""),
    ("Popol-Wuj-Kaqchikel.pdf", "kaqchikel", "texto", "Popol Wuj en Kaqchikel", "No verificado (PDF escaneado)", "", ""),
    # --- Q'eqchi'
    ("Cuidados-de-la-mujer-Qeqchi.pdf", "qeqchi", "texto", "Li xwanjik ut xch'oolaninkil li ixq naq wank sa' yu'am (cuidados de la mujer)", "Elena Violeta Quim Coc", ALMG + ", Comunidad Lingüística Q'eqchi'", ""),
    ("Cuidados-de-la-mujer-Qeqchi (1).pdf", "qeqchi", "texto", "(copia duplicada del anterior; eliminada por deduplicación)", "Elena Violeta Quim Coc", ALMG, ""),
    ("Fauna-Flora-Qeqchi.pdf", "qeqchi", "texto", "Fauna y flora Q'eqchi' (investigación 2018)", "Pedro Xol Pop", ALMG + ", Comunidad Lingüística Q'eqchi'", "2018"),
    ("Flora-Fauna-Qeqchi.pdf", "qeqchi", "texto", "Flora y fauna Q'eqchi' (investigación 2018)", "Hermelindo Quim Cuc", ALMG + ", Comunidad Lingüística Q'eqchi'", "2018"),
    ("Neologismos-Qeqchi.pdf", "qeqchi", "texto", "Neologismos Q'eqchi'", "María Teresa Ac Macz", ALMG + ", Comunidad Lingüística Q'eqchi'", ""),
    ("Popol-Hu-Qeqchi.pdf", "qeqchi", "texto", "Popol Hu en Q'eqchi'", "Traducción: María Teresa Ac Macz", ALMG + ", Comunidad Lingüística Q'eqchi'", ""),
    ("Sinonimias-Qeqchi.pdf", "qeqchi", "texto", "Sinonimias en Q'eqchi'", "Técnico investigador de la Comunidad Lingüística Q'eqchi' (nombre no legible en la extracción)", ALMG + ", Comunidad Lingüística Q'eqchi'", "2023"),
    ("Modulo-L2-1era-parte-Qeqchi.pdf", "qeqchi", "texto", "Módulo de aprendizaje del idioma Q'eqchi' como L2 (1.ª parte)", "Equipo de trabajo de la Comunidad Lingüística Q'eqchi'", ALMG + ", Comunidad Lingüística Q'eqchi'", "2009"),
    ("Monografia-Qeqchi.pdf", "qeqchi", "texto", "Monografía Q'eqchi'", "Autor no identificado en el documento", "", ""),
    ("vocabulario q'eqchi'.pdf", "qeqchi", "dicc", "Vocabulario Q'eqchi' (2.ª ed. revisada)", "Comunidad Lingüística Q'eqchi' (junta directiva presidida por Andrés Cuz Mucú)", ALMG, "2004"),
    ("qeqchi-espanol.pdf", "qeqchi", "dicc", "Diccionario Q'eqchi' - Español", "No verificado (PDF escaneado)", "", ""),
    # --- Mam
    ("20200214_Vocabulario_biocultural_mam.pdf", "mam", "dicc", "Vocabulario biocultural mam de Unión Juárez, Chiapas", "Responsable: Telma Angelina Can Pixabaj; investigadores: Fernando Guerrero Martínez, Juan Jesús Vázquez Álvarez; técnicos: Fausto Bolom Ton, Tomás Gómez López; Comunidad Lingüística Mam: José Reginaldo Pérez Vail, David Ramiro Tirado Romero; hablantes: Hermelindo González Verdugo, Juan de Dios Bartolo Ortiz, Benvenuto Ramos Bartolo, Hermenegildo Morales Verdugo, Nicolás Ventura y otros", "CIMSUR-UNAM y Comunidad Lingüística Mam (ALMG)", "2020"),
    ("Aprendiendo-L2-Mam.pdf", "mam", "texto", "Tu'jil qyol Mam te tkab'in yol: aprendiendo el idioma Mam como L2", "Producción: Saturnino Jíguan Berdúo, Samuel de Jesús Feliciano Orozco, Rodolfo García Marroquín, Santos Bladimiro de León Lorenzo, Mario Roberto Aguilón Crisóstomo; ilustración: Dagoberto Carlos Témaj Feliciano; validación: Avelino Ramírez López", "Ministerio de Educación, DIDEDUC San Marcos (STPEBI)", ""),
    ("Variantes-Dialectales-Mam.pdf", "mam", "texto", "Revisión del documento \"Variantes dialectales del idioma Mam\"", "Responsable: Lic. Miguel García Ortíz (metadatos del PDF: Elmer Geovanny Feliciano Cardona B'alam)", ALMG + ", Comunidad Lingüística Mam", "2013"),
    ("Pop-Uj-Mam.pdf", "mam", "texto", "Pop U'j, versión en idioma mam", "ALMG (PDF escaneado; traductores no verificados)", ALMG, ""),
    ("Revista-Ambil-toj-Kyxim-Qchman.pdf", "mam", "texto", "Revista Ambil toj kyxim qchman", "Comunidad Lingüística Mam (PDF escaneado)", ALMG, ""),
    ("Revista-Kyajlab_il-Qchman.pdf", "mam", "texto", "Revista Kyajlab'il qchman", "Comunidad Lingüística Mam (PDF escaneado)", ALMG, ""),
    ("Revista-Qyolb_il-Toj-Jaxnaq_tzb_il.pdf", "mam", "texto", "Revista Qyolb'il toj jaxnaq tzb'il", "Comunidad Lingüística Mam (PDF escaneado)", ALMG, ""),
    ("Mam, Gramática Pedagógica (B'aayil).pdf", "mam", "texto", "T-xnaq'tzaanjtz Ttxoolil Qyool: Gramática pedagógica Mam", "B'aayil Eduardo Gustavo Pérez Vail; dirección de la colección: Guillermina Herrera Peña", "Oxlajuuj Keej Maya' Ajtz'iib' (OKMA), Proyecto EDUMAYA, Universidad Rafael Landívar", "1999"),
    ("gramatica_mam.pdf", "mam", "texto", "U'jal te xhnaq'tsal ta t-ts'ib'enj te ta yol mam te Chiapas (Gramática de la lengua mam de Chiapas)", "Nicacio Ramos Ortíz", "Instituto Nacional de Lenguas Indígenas (INALI) y Secretaría de Educación de Chiapas, México", "2013"),
    ("norma_mam.pdf", "mam", "texto", "Txolil ta tsi'b'enj te ta yol mam: Norma de escritura de la lengua mam", "Instituto Nacional de Lenguas Indígenas (autoría individual no indicada en la extracción)", "INALI, México", ""),
    ("Mi_padre_el_sembrador_mam.pdf", "mam", "texto", "Nmana: Ajawal (Mi padre el sembrador), Colección Cuentos en familia", "Autoría: Juana Filomena Cuá García; traducción al mam: Luis Alfredo Aguilón Crisóstomo; editor: Juan Carlos Lemus; ilustraciones: Herman Montenegro", "Proyecto USAID Leer y Aprender; aval lingüístico de la Comunidad Lingüística Mam", "2016"),
    ("Ley-de-acceso-a-la-información-pública-en-idioma-mam.pdf", "mam", "texto", "Ley de Acceso a la Información Pública (Decreto 57-2008), versión Español/Mam", "Traducción coordinada con la Comunidad Lingüística Mam", "ALMG y COPRET, Gobierno de Guatemala", "2013"),
    ("mamNB-web.pdf", "mam", "biblia", "Las Sagradas Escrituras, Mam del norte de Guatemala", "Sociedad Bíblica de Guatemala (1.ª ed. 1993); edición web: La Asociación Educativa y Cultural Maya (2013). Licencia CC BY-NC-ND 4.0", "Sociedad Bíblica de Guatemala", "1993/2013"),
    ("Mam-Santos-(2012)-New-Testament.pdf", "mam", "excluir:la fuente del PDF codifica el texto; se usó la misma traducción en USFM desde eBible.org (mamNT)", "El Nuevo Testamento en Mam de Todos Santos (PDF)", "Wycliffe Bible Translators", "", "2012"),
    ("diccionario-del-mam-espac3b1ol-de-comitancillo-san-marcos-2001.pdf", "mam", "dicc", "Diccionario del Mam-Español de Comitancillo (PDF; repite la versión web)", "Mitsuho Ikeda y Walter Orland Pérez Morales", "", "2001"),
    ("Mam diccionario hablado.pdf", "mam", "dicc", "Mam diccionario parlante en línea (impresión PDF; repite la versión web)", "Comunidad Lingüística Mam y Living Tongues Institute", "", "2012"),
    # --- nuevos K'iche'
    ("popol-wuj-kiche.pdf", "kiche", "texto", "Popol Wuj, versión poética K'iche'", "Sam Colop (Luis Enrique Sam Colop)", "PEMBI-GTZ / Cholsamaj", ""),
    ("2.°_CyL_SKCH'_k'iche'.pdf", "kiche", "texto", "Kemom Ch'ab'al, 2.º grado primaria K'iche' (Programa de lectoescritura eficaz)", "Equipo de producción de PRODESSA: coordinación Federico Roncal Martínez; Yesenia Juárez, Edgar García Tax, Silvia Montepeque, Erwin Salazar, Edgar Daniel Morales, Héctor de León Alonzo", "Proyecto de Desarrollo Santiago (PRODESSA) y Ministerio de Educación", ""),
    ("13525 quc Sonrisas infantiles campesinas.pdf", "kiche", "texto", "Sonrisas infantiles campesinas (K'iche')", "No verificado (PDF escaneado)", "", ""),
    # --- nuevos Kaqchikel
    ("CAKSDS.pdf", "kaqchikel", "biblia", "Ri utzilaj rutzij ri Dios pa kach'abel (Nuevo Testamento, Kaqchikel Sur de Sacatepéquez)", "Wycliffe Bible Translators; edición digital: Digital Bible Society", "Wycliffe Bible Translators", "1993"),
    ("Full text of _Kikotemal taq tzij_ Antología de cuentos del área Kaqchiquel_.pdf", "kaqchikel", "texto", "Kikotemal taq tzij: Antología de cuentos del área Kaqchiquel (texto OCR de archive.org)", "Lucía Verdugo de Lima, Martín Chacach Cutzal, Mayra Fong Rodríguez", "", ""),
    ("Ley-de-Idiomas-Kaqchikel.pdf", "kaqchikel", "texto", "Ley de Idiomas Nacionales (Decreto 19-2003) en Kaqchikel", "Kaqchikel Cholchi' (Comunidad Lingüística Kaqchikel)", ALMG, ""),
    ("renap_kaqchikel.pdf", "kaqchikel", "texto", "Ley del Registro Nacional de las Personas (Decreto 90-2005) en Kaqchikel", "Traductor no indicado", "", ""),
    ("09-LAIPKAQCHIQUEL-ESPAÑOL.pdf", "kaqchikel", "texto", "Ley de Acceso a la Información Pública comentada (Decreto 57-2008), Español/Kaqchikel", "Traducción coordinada con la Comunidad Lingüística Kaqchikel (pres. Pedro Morejón Patzán)", ALMG, "2013"),
    ("Ley-de-acceso-a-la-información-pública-en-idioma-kaqchiquel.pdf", "kaqchikel", "texto", "Ley de Acceso a la Información Pública, versión Español/Kaqchikel (COPRET)", "Traducción coordinada con la Comunidad Lingüística Kaqchikel", "ALMG y COPRET", "2013"),
    ("00-WNTcki-web.pdf", "kaqchikel", "biblia", "Ri Cacac Testamento pa Kachabal: El Nuevo Testamento en Cakchiquel de Santa María de Jesús, Sacatepéquez (2.ª ed.)", "Wycliffe Bible Translators (1.ª ed. 2006, 2.ª ed. 2010), ScriptureEarth.org. Licencia CC BY-NC-ND 3.0", "Wycliffe Bible Translators", "2010"),
    ("26572 cakX OT stories.pdf", "kaqchikel", "texto", "Historias del Antiguo Testamento en Kaqchikel", "No verificado (PDF escaneado)", "", ""),
    ("ilide.info-cprg-en-idioma-mam-pr_7a979cf37c9fe22a06af56cd4452e67a.pdf", "mam", "texto", "Ttxu Kawb'il tuj Nintz Tnam te Tx'otx'ixin: Constitución Política de la República de Guatemala en idioma Mam", "Traductores no indicados en el documento", "Instituto de Justicia Constitucional, Corte de Constitucionalidad", "2013"),
    # --- nuevos Q'eqchi'
    ("kekB-web.pdf", "qeqchi", "biblia", "Li Santil Hu: La Santa Biblia en Q'eqchi' (ortografía tradicional)", "Wycliffe Bible Translators", "Wycliffe Bible Translators", "1988-2019"),
    ("Constitución.pdf", "qeqchi", "texto", "Xnimal Ruhil Chaq'rab' re Watemaal: Constitución Política de Guatemala, Q'eqchi'-Castellano", "Defensoría Q'eqchi' (PEM. Raúl Tacaj Xol, Adelso Romel Reyes Reyes, Robin Macloni Sicaján Jacinto, Angela Maribel Caal Ajtul y equipo)", "Defensoría Q'eqchi'; edición: Cholsamaj", "2014"),
    ("10.-GramaticaNormativa-2022 Q’eqchi’.pdf", "qeqchi", "texto", "Gramática Normativa Q'eqchi'", "Alfredo Alvarez Cabanal; coordinación: Luis Tiul Beb", ALMG + ", Comunidad Lingüística Q'eqchi'", "2022"),
    ("16-LAIP-QUEQCHI-ESPAÑOL.pdf", "qeqchi", "texto", "Ley de Acceso a la Información Pública comentada (Decreto 57-2008), Español/Q'eqchi'", "Traducción coordinada con la Comunidad Lingüística Q'eqchi'", ALMG, "2013"),
    ("8bn7q2.pdf", "qeqchi", "texto", "Guía de lectoescritura Q'eqchi' (Educación Bilingüe Intercultural)", "Edna Maribel Chaman, Edwin Armando Catún, Pedro Ical Choc", "DIGEBI / PROASE, Ministerio de Educación", "2004"),
    ("thmpzo_qechi.pdf", "qeqchi", "excluir:son sobre todo tablas calendáricas repetitivas, poco útiles para el modelo", "Cholwuj Cholna'oj: El Libro de la Cuenta de los Nawales", "Tito Medina", "Fundación CEDIM y Tzijolaj", "2000"),
]

EBIBLE = [  # raw/ebible/<zip> (descargados de https://ebible.org/Scriptures/)
    ("mamNT_usfm.zip", "mam", "Ac'aj testamento: El Nuevo Testamento en Mam de Todos Santos", "Wycliffe Bible Translators (© 2000). Licencia CC BY-NC-ND", "https://ebible.org/mamNT/"),
    ("qucNNT_usfm.zip", "kiche", "Ru Loq' Pixab' Ri Dios: Nuevo Testamento en K'iche' de Cantel (ortografía nueva)", "Wycliffe Bible Translators (© 2011)", "https://ebible.org/qucNNT/"),
    ("quctt_usfm.zip", "kiche", "Ri K'ak' Testamento pa Tzijob'al K'iche' (Totonicapán)", "Pioneer Bible Translators (© 2022)", "https://ebible.org/quctt/"),
]

# Carpetas con fuentes.jsonl (escrito por scripts/web_scraping/descargar_textos_kiche.py)
EXTRA = [("kiche", "kiche", {"biblia_catolica": "biblia"})]   # (subcarpeta raw/, lengua, {colección: tipo})

WEB = {  # archivo jsonl -> (lengua, título, autores, url)
    "webonary_kaqchikel.jsonl": ("kaqchikel", "Diccionario Kaqchikel (Webonary)", "Contribuyentes del diccionario Kaqchikel publicado en Webonary (SIL International)", "https://www.webonary.org/kaqchikel/"),
    "td_qeqchi.jsonl": ("qeqchi", "Q'eqchi' Talking Dictionary", "{prod}; hablantes: {spk}", "https://talkingdictionary.swarthmore.edu/qeqchi/"),
    "td_mam.jsonl": ("mam", "Mam Talking Dictionary", "{prod}; hablantes: {spk}", "https://talkingdictionary.swarthmore.edu/mam/"),
    "td_kiche.jsonl": ("kiche", "K'iche' Talking Dictionary", "{prod}; hablantes: {spk}", "https://talkingdictionary.swarthmore.edu/kiche/"),
    "td_kaqchikel.jsonl": ("kaqchikel", "Kaqchikel Talking Dictionary", "{prod}; hablantes: {spk}", "https://talkingdictionary.swarthmore.edu/kaqchikel/"),
    "mam_comitancillo.jsonl": ("mam", "Diccionario del Mam-Español de Comitancillo, San Marcos", "Mitsuho Ikeda (Mitzub'ixi Quq Chi'j) y Walter Orland Pérez Morales (2001)", "https://navymule9.sakura.ne.jp/Mam_Esp_Dic_Comitan.html"),
}

# ------------------------------------------------------------ NORMALIZACIÓN
APOS = dict.fromkeys(map(ord, "’‘ʼ`´′ꞌ"), "'")
LIGS = {"ﬁ": "fi", "ﬂ": "fl", "ﬀ": "ff", "ﬃ": "ffi", "ﬄ": "ffl", "­": ""}
ES_STOP = set("de la que el en los del las por con para una un se es al como más pero sus le ya o fue este ha sí porque esta son entre cuando muy sin sobre también me hasta hay donde quien desde todo nos durante todos uno les ni contra otros ese eso ante ellos e esto mí antes algunos qué unos yo otro otras otra él tanto esa estos mucho quienes nada muchos cual poco ella estar estas algunas algo nosotros".split())
MAYA_RE = re.compile(r"[bkqtw]'|ch'|tz|ä|ë|ï|ö|ü|aa|ee|ii|oo|uu")


def norm(s):
    s = unicodedata.normalize("NFC", s).translate(APOS)
    for a, b in LIGS.items():
        s = s.replace(a, b)
    s = re.sub(r"[\u0000-\u0008\u000b\u000e-\u001f​﻿]", "", s)
    return re.sub(r"[ \t]+", " ", s).strip()


EN_STOP = set("the of and to in is that it was for with his he they them their this which from by be are were on as at who not but have had there when".split())


def es_espanol(p):
    """True si el párrafo es predominantemente español o inglés (se descarta de la prosa)."""
    toks = re.findall(r"[a-zA-ZáéíóúñäëïöüÁÉÍÓÚÑ']+", p.lower())
    if len(toks) < 6:
        return False
    es = max(sum(t in ES_STOP for t in toks), sum(t in EN_STOP for t in toks)) / len(toks)
    maya = sum(bool(MAYA_RE.search(t)) for t in toks) / len(toks)
    return es > 0.18 and maya < 0.25


def es_basura(line):
    if not line or re.fullmatch(r"[\divxlcIVXLC\-–.\s]+", line):
        return True                                    # números de página
    if re.search(r"\.{5,}|(\. ){4,}|_{5,}", line):
        return True                                    # índices / líneas de relleno
    letras = sum(c.isalpha() for c in line)
    return letras < 0.5 * len(line.replace(" ", ""))


def clave(s):
    return hashlib.md5(re.sub(r"\W+", "", s.lower()).encode()).hexdigest()


# --------------------------------------------------------------- PDF → docs
def extraer(pdf, cache):
    out = cache / (pdf.stem + ".txt")
    if not out.exists():
        subprocess.run(["pdftotext", "-enc", "UTF-8", str(pdf), str(out)], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return out.read_text(encoding="utf-8", errors="replace") if out.exists() else ""


def paginas_limpias(raw):
    raw = re.sub(r"­[ \t]*\r?\n[ \t]*", "", raw)        # guion suave a fin de línea
    pages = [[norm(l) for l in p.splitlines()] for p in raw.split("\f")]
    # encabezados/pies repetidos: líneas que aparecen en >=30 % de las páginas
    cnt = Counter(l for p in pages for l in set(p) if l)
    umbral = max(3, 0.3 * len(pages))
    rep = {l for l, c in cnt.items() if c >= umbral and len(l) < 120}
    return [[l for l in p if l not in rep] for p in pages]


BIBLIA_REF = re.compile(r"\d+\s*[:.]\s*\d+.*\d+\s*[:.]\s*\d+|[α-ω]")   # notas y referencias cruzadas


def parrafos(pages, tipo):
    if tipo == "biblia":
        pages = [[l for l in p if not BIBLIA_REF.search(l)] for p in pages]
        ps = parrafos(pages, "texto")
        return [re.sub(r"\s+", " ", re.sub(r"\d+", " ", x)).strip() for x in ps]  # números de versículo
    out = []
    for p in pages:
        if tipo == "dicc":                       # cada línea útil = entrada
            out += [l for l in p if not es_basura(l) and len(l) > 3]
            continue
        buf = []
        for l in p + [""]:
            if not l:
                if buf:
                    out.append(" ".join(buf))
                buf = []
                continue
            if es_basura(l):
                continue
            if buf and buf[-1].endswith("-") and l[:1].islower():
                buf[-1] = buf[-1][:-1] + l       # desguionado de fin de línea
            else:
                buf.append(l)
    return [re.sub(r"\s+", " ", x).strip() for x in out]


def agrupar(items, max_chars, sep):
    docs, cur, n = [], [], 0
    for it in items:
        if cur and n + len(it) > max_chars:
            docs.append(sep.join(cur))
            cur, n = [], 0
        cur.append(it)
        n += len(it) + 1
    if cur:
        docs.append(sep.join(cur))
    return docs


# ------------------------------------------------------------ eBible (USFM)
def usfm_capitulos(t):
    """Un documento por capítulo; quita notas (\\f..\\f*), referencias (\\x..\\x*) y marcadores."""
    t = re.sub(r"\\(f|x|fe)\s.*?\\\1\*", " ", t, flags=re.S)
    t = re.sub(r"\\w\s+([^|\\]*)(\|[^\\]*)?\\w\*", r"\1", t)
    caps, cur = [], []
    for l in t.splitlines():
        m = re.match(r"\\(\w+)\s*(.*)", l.strip())
        if not m:
            continue
        tag, rest = m.groups()
        if tag == "c":
            if cur:
                caps.append(" ".join(cur))
            cur = []
        elif tag == "v":
            cur.append(re.sub(r"^\d+\S*\s*", "", rest))
        elif tag in ("p", "m", "q", "q1", "q2", "pi", "li", "nb") and rest:
            cur.append(rest)
    if cur:
        caps.append(" ".join(cur))
    return [norm(re.sub(r"\\\+?\w+\*?", " ", c)) for c in caps if c.strip()]


# --------------------------------------------------------- Diccionarios web
PLANTILLAS = [
    "En {L}, «{w}»{pos} significa «{d}».",
    "La palabra {L} «{w}»{pos} se traduce al español como «{d}».",
    "{w}{pos}: {d}.",
    "«{w}» es una palabra del idioma {L}{pos} que quiere decir «{d}».",
]


def entrada_a_texto(e, L, rng):
    w = norm(e.get("headword", ""))
    if not w:
        return None
    pos = norm(e.get("pos") if isinstance(e.get("pos"), str) else ", ".join(e.get("pos") or []))
    pos = f" ({pos.lower()})" if pos else ""
    defs, ejemplos = [], []
    for s in e.get("senses", []):                          # Webonary
        if s.get("def"):
            defs.append(norm(s["def"]))
        for ex in s.get("examples", []):
            m, es = norm(ex.get("maya", "")), norm(ex.get("es", ""))
            ejemplos.append(f"{m} ({es})" if es else m)
    defs += [norm(g) for k in ("gloss", "es_gloss") for g in (e.get(k) or [])] if not isinstance(e.get("gloss"), str) else [norm(e["gloss"])]
    defs = [d for d in dict.fromkeys(defs) if d]
    if not defs and e.get("summary"):
        defs = [norm(e["summary"])]
    if not defs:
        return None
    txt = rng.choice(PLANTILLAS).format(L=L, w=w, pos=pos, d="; ".join(defs).rstrip("."))
    if ejemplos:
        txt += " Ejemplo: " + " ".join(ejemplos[:3])
    return txt


# --------------------------------------------------------------------- MAIN
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--pdfs", required=True)
    ap.add_argument("--web", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--max-chars", type=int, default=4000, help="tamaño máx. de documento")
    ap.add_argument("--entradas-por-doc", type=int, default=25)
    ap.add_argument("--docs-por-shard", type=int, default=2000)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    pdfs, web, out = Path(a.pdfs), Path(a.web), Path(a.out)
    cache, final = out / "extraido", out / "final"
    for d in (cache, final):
        d.mkdir(parents=True, exist_ok=True)
    rng = random.Random(a.seed)

    docs = defaultdict(list)                    # lengua -> [(texto, fuente)]
    vistos = defaultdict(set)
    stats = defaultdict(Counter)
    creditos = []

    def dedup(lang, items, st):
        res = []
        for it in items:
            k = clave(it)
            if len(it) < 15 or k in vistos[lang]:
                st["duplicados_o_cortos"] += 1
                continue
            vistos[lang].add(k)
            res.append(it)
        return res

    for fname, lang, tipo, titulo, autores, inst, anio in PDFS:
        st = stats[f"{lang}:{fname}"]
        if tipo.startswith("excluir:"):
            creditos.append((lang, titulo, autores, inst, anio, fname, "no incluido: " + tipo[8:]))
            continue
        raw = extraer(pdfs / fname, cache) if (pdfs / fname).exists() else ""
        incluido = len(raw.strip()) > 500
        if incluido:
            ps = parrafos(paginas_limpias(raw), tipo)
            if tipo in ("texto", "biblia"):
                n0 = len(ps)
                ps = [p for p in ps if not es_espanol(p)]
                st["parrafos_espanol_descartados"] = n0 - len(ps)
            ps = dedup(lang, ps, st)
            sep = "\n" if tipo == "dicc" else "\n\n"
            for d in agrupar(ps, a.max_chars, sep):
                docs[lang].append((d, fname))
            st["unidades"] = len(ps)
            incluido = bool(ps)
        estado = "incluido" if incluido else ("no incluido: PDF escaneado sin capa de texto (requiere OCR)" if (pdfs / fname).exists() else "no encontrado")
        creditos.append((lang, titulo, autores, inst, anio, fname, estado))

    for sub, lang, tipos in EXTRA:
        base = web.parent / sub
        meta = base / "fuentes.jsonl"
        if not meta.exists():
            continue
        agrupado = defaultdict(lambda: [0, 0, None])       # colección -> [archivos, unidades, fuente]
        for f in (json.loads(l) for l in meta.read_text(encoding="utf-8").splitlines() if l.strip()):
            tipo = tipos.get(f["coleccion"], "texto")
            st = stats[f"{lang}:{f['archivo']}"]
            raw = extraer(base / f["archivo"], cache)
            ps = parrafos(paginas_limpias(raw), tipo) if len(raw.strip()) > 500 else []
            n0 = len(ps)
            ps = [p for p in ps if not es_espanol(p)]
            st["parrafos_espanol_descartados"] = n0 - len(ps)
            ps = dedup(lang, ps, st)
            for d in agrupar(ps, a.max_chars, "\n\n"):
                docs[lang].append((d, f["archivo"]))
            st["unidades"] = len(ps)
            if f["coleccion"] == "biblia_catolica":          # una sola obra: un solo crédito
                g = agrupado["biblia_catolica"]
                g[0] += 1; g[1] += len(ps); g[2] = f
                continue
            estado = "incluido" if ps else "no incluido: sin texto extraíble (escaneado) o solo español/inglés"
            creditos.append((lang, f["titulo"], f["autor"], f["url"], "", f["archivo"], estado))
        for col, (n, u, f) in agrupado.items():
            creditos.append((lang, "Ri Tyoxlaj Wuj: Biblia católica en K'iche' (Antiguo y Nuevo Testamento)", f["autor"],
                             "https://www.iglesiacatolica.org.gt/bibliakiche/", "", f"{sub}/{col}/ ({n} PDF)",
                             f"incluido ({u} párrafos)" if u else "no incluido"))

    for zf, lang, titulo, autores, url in EBIBLE:
        p = web.parent / "ebible" / zf
        if not p.exists():
            creditos.append((lang, titulo, autores, url, "", zf, "no incluido: no descargado"))
            continue
        st = stats[f"{lang}:{zf}"]
        caps = []
        with zipfile.ZipFile(p) as z:
            for n in sorted(z.namelist()):
                if n.endswith(".usfm"):
                    caps += usfm_capitulos(z.read(n).decode("utf-8", errors="replace"))
        caps = dedup(lang, caps, st)
        for c in caps:
            docs[lang].append((c, zf))
        st["unidades"] = len(caps)
        creditos.append((lang, titulo, autores, url, "", zf, f"incluido ({len(caps)} capítulos)"))

    for jf, (lang, titulo, autores, url) in WEB.items():
        p = web / jf
        if not p.exists():
            creditos.append((lang, titulo, autores.replace("{prod}", "ver sitio").replace("{spk}", "ver sitio"), url, "", jf, "no incluido: no descargado"))
            continue
        filas = [json.loads(l) for l in p.read_text(encoding="utf-8").splitlines() if l.strip()]
        spk = sorted({norm(s) for f in filas for s in f.get("speaker", []) if s},
                     key=lambda x: unicodedata.normalize("NFD", x))
        spk = [x for i, x in enumerate(spk)            # quita variantes solo por tildes
               if not any(clave(unicodedata.normalize("NFD", x).encode("ascii", "ignore").decode())
                          == clave(unicodedata.normalize("NFD", y).encode("ascii", "ignore").decode()) for y in spk[:i])]
        prod = "Living Tongues Institute for Endangered Languages y ALMG"
        portada = web / jf.replace(".jsonl", "_portada.html")
        if portada.exists():
            plano = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", portada.read_text(encoding="utf-8")))
            m = re.search(r"Diccionario producido por (.+?\(\d{4}[^)]*\))", plano)
            c = re.search(r"copyright de la (Comunidad Ling\S+ [^(]+\(\d{4}\))", plano)
            prod = "; ".join(x for x in [m and "Producido por " + norm(m.group(1)),
                                          "K'ulb'il Yol Twitz Paxil / ALMG y Living Tongues Institute for Endangered Languages",
                                          c and "© " + norm(c.group(1))] if x)
        ents = [t for t in (entrada_a_texto(f, LENGUAS[lang], rng) for f in filas) if t]
        st = stats[f"{lang}:{jf}"]
        ents = dedup(lang, ents, st)
        rng.shuffle(ents)
        for i in range(0, len(ents), a.entradas_por_doc):
            docs[lang].append(("\n".join(ents[i:i + a.entradas_por_doc]), jf))
        st["unidades"] = len(ents)
        creditos.append((lang, titulo, autores.replace("{prod}", prod).replace("{spk}", ", ".join(spk) or "no indicados"),
                         url, "", jf, f"incluido ({len(ents)} entradas)" if ents else "no incluido: 0 entradas"))

    # ---- mezcla, escritura .txt y shards
    resumen = {}
    for lang, ds in docs.items():
        rng.shuffle(ds)
        txt = f"\n{EOS}\n".join(d for d, _ in ds) + f"\n{EOS}\n"
        (final / f"{lang}.txt").write_text(txt, encoding="utf-8")
        sd = out / "shards" / lang
        sd.mkdir(parents=True, exist_ok=True)
        for old in sd.glob("*.jsonl"):
            old.unlink()
        for i in range(0, len(ds), a.docs_por_shard):
            with open(sd / f"train-{i // a.docs_por_shard:05d}.jsonl", "w", encoding="utf-8") as f:
                for d, src in ds[i:i + a.docs_por_shard]:
                    f.write(json.dumps({"text": d, "lang": lang, "source": src}, ensure_ascii=False) + "\n")
        resumen[lang] = {"documentos": len(ds), "caracteres": sum(len(d) for d, _ in ds),
                         "palabras_aprox": sum(len(d.split()) for d, _ in ds)}
    (final / "estadisticas.json").write_text(
        json.dumps({"resumen": resumen, "por_fuente": stats}, ensure_ascii=False, indent=2), encoding="utf-8")

    # ---- créditos
    L = ["# Créditos del corpus de pre-entrenamiento en lenguas mayas", "",
         "Todos los textos pertenecen a sus autores e instituciones. Este corpus se usa con fines de "
         "investigación educativa (NASA Space Apps Challenge, Field Shift Guatemala). Verifique la licencia "
         "de cada obra antes de redistribuir el corpus o un modelo entrenado con él.", ""]
    for lang in LENGUAS:
        filas = [c for c in creditos if c[0] == lang]
        if not filas:
            continue
        L += [f"## {LENGUAS[lang].capitalize()}", ""]
        for _, titulo, autores, inst, anio, fname, estado in filas:
            L.append(f"- **{titulo}**{f' ({anio})' if anio else ''}")
            L.append(f"  - Autoría: {autores}")
            if inst:
                L.append(f"  - Institución / fuente: {inst}")
            L.append(f"  - Archivo: `{fname}` — {estado}")
        L.append("")
    (final / "CREDITOS.md").write_text("\n".join(L), encoding="utf-8")
    print(json.dumps(resumen, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
