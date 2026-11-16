# Traductor de lenguas mayas (español ↔ k'iche', kaqchikel, q'eqchi', mam) · v2-experimental

Adaptador LoRA para **Qwen/Qwen2.5-0.5B-Instruct**. Traduce palabras y frases cortas entre el
español y cuatro idiomas mayas de Guatemala. Parte de [Field Shift Guatemala](../README.md)
(NASA Space Apps Challenge). Código de entrenamiento: [scripts/traductor_lenguas_mayas/](../scripts/traductor_lenguas_mayas/).

> **Versión experimental.** Se entrenó solo en CPU (una laptop sin GPU), con pocas horas de cómputo. Sus traducciones tienen errores
> frecuentes y **deben revisarlas hablantes nativos** antes de usarse con personas.

## Cómo usarlo

```python
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer

base = "Qwen/Qwen2.5-0.5B-Instruct"
tok = AutoTokenizer.from_pretrained(base)
model = AutoModelForCausalLM.from_pretrained(base)
model = PeftModel.from_pretrained(model, "modelo_lenguas_mayas").merge_and_unload()

msgs = [{"role": "system", "content": "Eres un asistente que escribe y traduce entre el español y los idiomas mayas k'iche', kaqchikel, q'eqchi' y mam de Guatemala. Usa la ortografía de la ALMG, con el saltillo escrito como '. Responde solo con el texto pedido."},
        {"role": "user", "content": "Traduce del español al k'iche':\nmaíz"}]
texto = tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)
ids = tok(texto, return_tensors="pt").input_ids
print(tok.decode(model.generate(ids, max_new_tokens=40)[0][ids.shape[1]:], skip_special_tokens=True))
```

O desde la consola del proyecto: `python scripts/traductor_lenguas_mayas/probar_modelo.py --modelo modelo_lenguas_mayas`.

El prompt debe seguir el formato de arriba (`Traduce del <lengua> al <lengua>:\n<texto>`), que es con el que se entrenó.

**Integración en la app del teléfono** (API, feedback y aprendizaje continuo): [USO_EN_LA_APP.md](USO_EN_LA_APP.md).

**Antecedentes y qué aporta este modelo frente a trabajos anteriores:** [ANTECEDENTES.md](ANTECEDENTES.md).

## Datos de entrenamiento

Solo **pares de traducción**, en ambas direcciones: palabras de diccionarios (palabra ↔ glosa) y, desde la v2, ~6 800 oraciones cortas del corpus **MayanV** (k'iche', q'eqchi', mam). No incluye la prosa del corpus (libros, Biblias, páginas web).

| Lengua | Ejemplos disponibles |
|---|---:|
| k'iche' | 7 662 |
| kaqchikel | 7 102 |
| q'eqchi' | 13 572 |
| mam | 13 070 |

Fuentes y autorías: [CREDITOS.md](CREDITOS.md). Los textos no se distribuyen en este repositorio.

## Entrenamiento

- Modelo base: `Qwen/Qwen2.5-0.5B-Instruct` · LoRA r=32, alpha=32, todas las capas lineales.
- Hardware: CPU de laptop (sin GPU).
- Dos etapas, ambas en CPU:
  - **v1:** 790 pasos (≈ 12 600 ejemplos) con palabras de diccionario. Pérdida 5.02 → 2.81.
  - **v2:** 75 pasos más (≈ 1 200 ejemplos) mezclando oraciones de MayanV y palabras de diccionario, sobre la v1. Pérdida 3.77 → 3.58.
  - El adaptador publicado reúne las dos etapas (LoRA r=16 + r=16 concatenados).
- Detalles: [entrenamiento.json](entrenamiento.json).

## Evaluación

chrF++ sobre una muestra de 120 pares reservados: palabras de diccionario y 38 oraciones de MayanV/test (no vistos en el entrenamiento). Más alto es mejor (0–100).

| Dirección | chrF++ |
|---|---:|
| es->kaqchikel | 6.13 |
| es->kiche | 13.8 |
| es->mam | 8.03 |
| es->qeqchi | 11.55 |
| kaqchikel->es | 3.64 |
| kiche->es | 8.51 |
| mam->es | 6.86 |
| qeqchi->es | 10.39 |
| total | 8.12 |

Comparación sobre la misma muestra:

| Versión | chrF++ total | Solo oraciones de MayanV |
|---|---:|---:|
| v1 (solo diccionarios) | 7.31 | 7.83 |
| **v2 (+ MayanV)** | **8.12** | **10.09** |

Con tan pocos pares por dirección, estas cifras son orientativas.

## Limitaciones y uso responsable

- Aprendió de diccionarios: traduce mejor **palabras sueltas** que oraciones.
- Kaqchikel no tiene oraciones de MayanV: solo aprendió palabras sueltas, y es la lengua más débil.
- Puede inventar palabras con apariencia maya. No lo uses para documentos oficiales, salud o temas legales sin revisión humana.
- Son lenguas de pueblos indígenas: cualquier uso público debería contar con la participación de sus
  hablantes y de la Academia de Lenguas Mayas de Guatemala (ALMG).

## Licencia

[CC BY-NC 4.0](LICENSE.md): uso libre con atribución, **sin fines comerciales**.
