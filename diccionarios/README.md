# Diccionarios de idiomas mayas · Field Shift Guatemala

Vocabulario agrícola y gramática básica para que la aplicación pueda mostrar textos en **k'iche'**, **q'eqchi'**, **kaqchikel** y **mam**, además del español. Están escritos para que una persona del equipo o un agente de IA pueda consultarlos antes de traducir.

Actualizado el 14 de noviembre de 2026.

| Archivo | Idioma | Fuente principal | Estado |
|---|---|---|---|
| [kiche.md](kiche.md) | K'iche' | Vásquez García 2017, *Guía del Idioma K'iche'* (USAC, EPS) | Vocabulario y gramática verificados en la fuente |
| [qeqchi.md](qeqchi.md) | Q'eqchi' | Diccionario *Q'eqchi' – Español* (escaneado) | Vocabulario verificado en las páginas escaneadas; gramática parcial |
| [kaqchikel.md](kaqchikel.md) | Kaqchikel | Chacach Cutzal 1990, *Retamaxik ri ch'ab'äl kaqchikel* (URL) | Gramática verificada; poco vocabulario agrícola en la fuente |
| [mam.md](mam.md) | Mam | Sin fuente todavía | Plantilla por llenar |
| [palabras-por-buscar.md](palabras-por-buscar.md) | Todos | — | Palabras que faltan, para buscarlas con hablantes o diccionarios |

## Reglas para agentes que usen estos archivos

1. **Usa solo lo que está en las tablas.** Si una palabra no aparece, no la inventes ni la deduzcas de otro idioma maya: los cuatro idiomas son distintos aunque compartan raíces (por ejemplo, frijol es *kinaq'* en k'iche' y kaqchikel, pero no se puede suponer igual en mam). Deja el texto en español y anota la palabra en [palabras-por-buscar.md](palabras-por-buscar.md).
2. **Respeta la columna "Confianza".**
   - **Fuente**: aparece tal cual en el libro citado, con página.
   - **Derivada**: se obtuvo de una palabra compuesta o un ejemplo del mismo libro (se explica cómo).
   - **Por verificar**: conocimiento general, no confirmado en la fuente. No usar en la interfaz sin que la revise un hablante.
3. **Toda traducción para la app debe revisarla un hablante nativo** antes de publicarse. Estas listas sirven para borradores, no para textos finales.
4. **Glotal (saltillo).** En las fuentes aparece como `'`, `’`, `‟` o `‘`. Aquí se normaliza a `'`. Es un sonido (cierre de la garganta) y cambia el significado: *k'* ≠ *k*. Nunca lo omitas.
5. **Mayúsculas y nombres de idioma.** Se escribe k'iche', q'eqchi', kaqchikel y mam en minúscula dentro de una oración.
6. **Variantes.** Cada idioma tiene variantes regionales. Las fuentes de k'iche' son de Quetzaltenango; el diccionario q'eqchi' no indica región; el libro kaqchikel es de 1990. Si el hablante que revisa usa otra palabra, prevalece la del hablante de la región piloto.
7. **Lenguaje para la app.** Usa frases cortas, presente o futuro simple, y evita términos técnicos (por ejemplo, "agua en la tierra" en lugar de "humedad del suelo"). Muchas personas usuarias leerán poco o escucharán el texto: considera audio grabado por hablantes.

## Rasgos comunes de los cuatro idiomas (útil para entender las tablas)

Los cuatro pertenecen a la familia maya. Las fuentes de k'iche' y kaqchikel muestran estos rasgos; para q'eqchi' y mam hay que confirmarlos con su propia fuente.

- **Dos juegos de marcadores de persona.**
  - *Juego A* (prefijos posesivos): marcan al poseedor de un sustantivo ("mi", "tu", "su") y también al sujeto de un verbo transitivo.
  - *Juego B* (absolutivos): marcan al sujeto de un verbo intransitivo y al objeto de un verbo transitivo.
  - El juego A tiene formas distintas si la palabra empieza con vocal o con consonante.
- **Aspecto antes que tiempo.** El verbo lleva un prefijo que indica si la acción ocurre habitualmente o ahora (*k-* en k'iche', *n-/y-* en kaqchikel), si ya ocurrió (*x-*) o si ocurrirá (*xk-/xt-* en kaqchikel).
- **Plural opcional.** Muchas palabras no cambian en plural. El número se entiende por el contexto o por los marcadores de persona.
- **Usted de respeto.** K'iche' tiene formas de respeto (*la*, *alaq*) que van después del verbo o del sustantivo. Úsalas al dirigirse a personas adultas en la app.

## Fuentes

- Vásquez García, Diana Raquel (2017). *Guía del Idioma K'iche' dirigida a estudiantes y docentes de la EORM Cantón Chitay Las Rosas, Quetzaltenango*. Universidad de San Carlos de Guatemala, Facultad de Humanidades. PDF compartido por el equipo (`07_7642.pdf`).
- *Q'eqchi' – Kaxlan Aatin* (diccionario Q'eqchi'–Español), PDF escaneado compartido por el equipo (`qeqchi-espanol.pdf`). Faltan autor, editorial y año: completar desde la portada.
- Chacach Cutzal, Martín (1990). *Retamaxik ri ch'ab'äl kaqchikel. Ruka'n wuj*. Universidad Rafael Landívar, Instituto de Lingüística. [Ficha y PDF](https://www.url.edu.gt/publicacionesurl/pPublicacion.aspx?pb=651).
- IGER. *Kaqchikel 1. Básico*. ISBN 9789929766174. [Google Books](https://books.google.com.gt/books?id=-eSIDwAAQBAJ). Sin vista previa del texto; no se usó.

Los libros completos no se suben al repositorio por derechos de autor. Aquí solo hay listas breves con su cita.
