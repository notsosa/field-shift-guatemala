# Traductor de lenguas mayas (español ↔ k'iche', kaqchikel, q'eqchi', mam) · v1-experimental

Adaptador LoRA para **Qwen/Qwen2.5-0.5B-Instruct**. Traduce palabras y frases cortas entre el
español y cuatro idiomas mayas de Guatemala. Parte de [Field Shift Guatemala](../README.md)
(NASA Space Apps Challenge). Código de entrenamiento: [scripts/traductor_lenguas_mayas/](../scripts/traductor_lenguas_mayas/).

> **Versión experimental.** Se entrenó solo en CPU, unas 17 h (≈ 89% de una época). Sus traducciones tienen errores
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

## Datos de entrenamiento

Solo **pares de traducción de diccionarios** (palabra o frase corta ↔ glosa), en ambas direcciones. No incluye la prosa del corpus (libros, Biblias, páginas web).

| Lengua | Ejemplos disponibles |
|---|---:|
| k'iche' | 1 174 |
| kaqchikel | 7 102 |
| q'eqchi' | 1 132 |
| mam | 4 866 |

Fuentes y autorías: [CREDITOS.md](CREDITOS.md). Los textos no se distribuyen en este repositorio.

## Entrenamiento

- Modelo base: `Qwen/Qwen2.5-0.5B-Instruct` · LoRA r=16, alpha=32, todas las capas lineales.
- Hardware: CPU de laptop (sin GPU), una noche.
- Pasos: 790 (0.89 épocas, ≈ 12,645 ejemplos vistos). Pérdida: 5.02 → 2.81.
- Detalles: [entrenamiento.json](entrenamiento.json).

## Evaluación

chrF++ sobre 60 pares reservados de los diccionarios (no vistos en el entrenamiento). Más alto es mejor (0–100).

| Dirección | chrF++ |
|---|---:|
| es->kaqchikel | 7.03 |
| es->kiche | 8.78 |
| es->mam | 12.17 |
| es->qeqchi | 0.0 |
| kaqchikel->es | 5.53 |
| mam->es | 6.3 |
| qeqchi->es | 13.14 |
| total | 7.01 |

Con tan pocos pares por dirección, estas cifras son orientativas.

## Limitaciones y uso responsable

- Aprendió de diccionarios: traduce mejor **palabras sueltas** que oraciones.
- K'iche' y q'eqchi' tienen pocos pares; mam y kaqchikel, más.
- Puede inventar palabras con apariencia maya. No lo uses para documentos oficiales, salud o temas legales sin revisión humana.
- Son lenguas de pueblos indígenas: cualquier uso público debería contar con la participación de sus
  hablantes y de la Academia de Lenguas Mayas de Guatemala (ALMG).

## Licencia

[CC BY-NC 4.0](LICENSE.md): uso libre con atribución, **sin fines comerciales**.
