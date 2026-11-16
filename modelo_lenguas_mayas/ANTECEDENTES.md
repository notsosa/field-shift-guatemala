# Antecedentes: qué hay de nuevo en este modelo

## Lo que aporta este proyecto

No conocemos otro proyecto anterior que reúna todo lo siguiente para los idiomas mayas de Guatemala:

1. **Un modelo de lenguaje abierto** (pesos publicados, código de entrenamiento incluido) ajustado
   específicamente para **k'iche', kaqchikel, q'eqchi' y mam**, que traduce desde y hacia el español y además
   genera texto en esas lenguas.
2. **Aprendizaje continuo con retroalimentación humana (HFRL/RLHF):** las correcciones y elecciones de los
   hablantes, recogidas desde una aplicación de teléfono, se convierten en nuevas rondas de entrenamiento
   (KTO/DPO). Una versión nueva solo entra en uso si no empeora en la evaluación.
3. **Pensado para un uso concreto en el campo:** forma parte de una herramienta de información agrícola y
   climática para comunidades de Guatemala (NASA Space Apps Challenge), no de un traductor general.
4. **Entrenado con recursos modestos** (una computadora personal, sin GPU) y con un corpus reunido y
   documentado por estudiantes guatemaltecos. Se publican las fuentes y sus licencias, no los textos.

Hasta donde sabemos, es **uno de los primeros intentos de este tipo**. No es, sin embargo, el primer trabajo
de traducción automática para estas lenguas: hay antecedentes importantes, listados abajo. La afirmación
es honesta solo si se enuncia con este matiz («hasta donde sabemos», «que reúna estas características»).

## Trabajos anteriores que conviene reconocer

| Trabajo | Año | Qué hizo | Lenguas de este proyecto |
|---|---|---|---|
| [Google Traductor, ampliación a 110 idiomas](https://support.google.com/translate/answer/15139004) | 2024 | Traducción automática comercial (modelo PaLM 2). Google advierte que la calidad en estos idiomas sigue lejos de la de los idiomas grandes. | K'iche', q'eqchi', mam |
| [MayanV](https://preview.aclanthology.org/info-author-pages/2024.naacl-long.156.pdf), Universitat d'Alacant (NAACL) | 2024 | Corpus y modelos neuronales de traducción entre variedades coloquiales de idiomas mayas y del español. | K'iche', q'eqchi', mam y otros |
| [FLORES+ Mayas](https://aclanthology.org/2025.mtsummit-2.15.pdf) (MT Summit) | 2025 | Conjunto de evaluación estándar traducido a idiomas mayas, para medir sistemas de traducción. | K'iche', kaqchikel, mam, q'eqchi' y otros |
| [Traducción con pivote entre idiomas mayas de Guatemala](https://www.ebsco.com/articles/language-and-linguistics/4c673a01-7493-5b04-92e9-f324fafbb5db/theorizing-sustainable-low-resource-mt-in-development-settings-pivot-based-mt-between-guatemala-s-indigenous-mayan-languages) (*Translation Spaces*) | 2023 | Propuesta de traducción automática sostenible usando el español como pivote. | K'iche', q'eqchi', mam |
| [LLM en español para maya yucateco y ch'ol](https://aclanthology.org/2024.americasnlp-1.16.pdf) (AmericasNLP) | 2024 | Modelos de lenguaje entrenados en español adaptados a traducción. | Otras lenguas mayas (de México) |
| MADLAD-400 y FineWeb-2 | 2023–2024 | Corpus web multilingües que incluyen textos en estas lenguas (los usamos en el pre-entrenamiento; ver [CREDITOS.md](CREDITOS.md)). | Las cuatro |
| [Recursos de PLN para el k'iche'](https://tato30.github.io/posts/2026/05/collection-of-nlp-resources-for-kiche) | 2026 | Recopilación de corpus, modelos y herramientas para el k'iche'. | K'iche' |

Detrás de todo esto está, sobre todo, el trabajo de la **Academia de Lenguas Mayas de Guatemala (ALMG)**,
de traductores y lingüistas, y de las comunidades que hablan y escriben estas lenguas. Sin sus diccionarios
y textos, este modelo no existiría.

## Cómo describirlo al presentarlo

- ✅ «Hasta donde sabemos, es uno de los primeros modelos de lenguaje abiertos para k'iche', kaqchikel, q'eqchi'
  y mam que aprende de forma continua con las correcciones de sus hablantes.»
- ✅ «Un primer paso experimental, construido por estudiantes guatemaltecos con recursos modestos.»
- ❌ «El primer traductor de lenguas mayas»: Google Traductor y MayanV ya traducen algunas de estas lenguas.
- ❌ «No existe nada parecido»: hay investigación previa y conviene citarla.

Si alguien conoce otro trabajo anterior que reúna estas características, agradecemos que nos lo diga para
corregir este documento.

*Revisado en noviembre de 2026. La búsqueda no fue exhaustiva.*
