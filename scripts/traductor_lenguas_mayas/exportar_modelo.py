"""Arma la carpeta publicable del modelo: adaptador LoRA + ficha del modelo + licencia + créditos.

No incluye textos de entrenamiento (tienen licencias restringidas: están en el repo privado).
Toma el adaptador del último checkpoint del SFT (modelos/sft/checkpoints/checkpoint-N), que pesa
~17 MB y cabe en GitHub; el modelo fusionado (~2 GB) no.

Uso
  python exportar_modelo.py                       # -> modelo_lenguas_mayas/ en la raíz del repo
  python exportar_modelo.py --version v1 --checkpoint modelos/sft/checkpoints/checkpoint-300
"""
from __future__ import annotations

import argparse
import json
import shutil
from collections import Counter
from datetime import date
from pathlib import Path

from comun import CORPUS, DATOS_LLM, LENGUAS, MAYAS, MODELOS, RAIZ, leer_jsonl, ultimo_checkpoint

FUENTES_DICC = [  # fuentes de los pares de traducción (lo único que ve el entrenamiento en CPU)
    ("Diccionario Kaqchikel (Webonary, SIL International)", "https://www.webonary.org/kaqchikel/"),
    ("Talking Dictionaries de k'iche', kaqchikel, q'eqchi' y mam — Living Tongues Institute for Endangered "
     "Languages y Comunidades Lingüísticas de la ALMG", "https://talkingdictionary.swarthmore.edu/"),
    ("Diccionario Mam–Español de Comitancillo, San Marcos — Mitsuho Ikeda y Walter Orland Pérez Morales (2001)",
     "https://navymule9.sakura.ne.jp/Mam_Esp_Dic_Comitan.html"),
    ("Tablas verificadas del equipo Field Shift (`diccionarios/*.md`), con sus fuentes citadas por página",
     "../diccionarios/README.md"),
]

AVISO = {"cpu": "Se entrenó solo en CPU, unas 17 h (≈ {epoca:.0%} de una época).",
         "gpu": "Se entrenó en una GPU T4 de Google Colab (pre-entrenamiento con límite de horas + SFT)."}
DATOS = {
    "cpu": "Solo **pares de traducción de diccionarios** (palabra o frase corta ↔ glosa), en ambas direcciones. "
           "No incluye la prosa del corpus (libros, Biblias, páginas web).",
    "gpu": "1. **Pre-entrenamiento continuo** con el corpus del proyecto (≈ 34.6 M tokens: libros y leyes de la ALMG, "
           "Biblias, páginas web de FineWeb-2 y MADLAD-400, diccionarios), muestreado para equilibrar las lenguas.\n"
           "2. **Ajuste por instrucciones**: pares de traducción de diccionarios en ambas direcciones, continuar texto, "
           "escribir párrafos, explicar palabras e identificar la lengua.",
}
HARDWARE = {"cpu": "CPU de laptop (sin GPU), una noche", "gpu": "GPU NVIDIA T4 (Google Colab)"}


def combinar_y_guardar(sft_dir: Path, dest: Path) -> dict:
    """Guarda en dest un único LoRA (fp16) aplicable al modelo base de Hugging Face.

    Si el SFT se entrenó sobre el modelo pre-entrenado (modelos/cpt/final), concatena el LoRA del
    pre-entrenamiento y el del SFT (combination_type="cat"): las dos deltas de bajo rango se suman,
    así que el resultado equivale exactamente a aplicar ambos, con rango r_cpt + r_sft."""
    import torch
    from peft import PeftModel
    from safetensors.torch import load_file, save_file
    from transformers import AutoModelForCausalLM

    cfg = json.loads((sft_dir / "adapter_config.json").read_text(encoding="utf-8"))
    cpt_final = Path(cfg["base_model_name_or_path"])
    if cpt_final.exists():
        cpt_ad = cpt_final.parent / "adaptador"
        base = json.loads((cpt_ad / "adapter_config.json").read_text(encoding="utf-8"))["base_model_name_or_path"]
        print(f"Combinando LoRA de pre-entrenamiento ({cpt_ad}) + SFT ({sft_dir}) sobre {base}")
        m = AutoModelForCausalLM.from_pretrained(base, dtype=torch.float32)
        m = PeftModel.from_pretrained(m, str(cpt_ad), adapter_name="cpt")
        m.load_adapter(str(sft_dir), adapter_name="sft")
        m.add_weighted_adapter(["cpt", "sft"], [1.0, 1.0], adapter_name="combinado", combination_type="cat")
        m.set_adapter("combinado")
        m.delete_adapter("cpt")
        m.delete_adapter("sft")
        m.save_pretrained(str(dest), selected_adapters=["combinado"])
        sub = dest / "combinado"
        if sub.exists():                             # PEFT guarda los adaptadores con nombre en una subcarpeta
            for f in sub.iterdir():
                shutil.move(str(f), str(dest / f.name))
            sub.rmdir()
    else:
        for f in ("adapter_model.safetensors", "adapter_config.json"):
            shutil.copy2(sft_dir / f, dest / f)
    pesos = dest / "adapter_model.safetensors"
    tensores = {k: v.to(torch.float16).contiguous() for k, v in load_file(str(pesos)).items()}
    save_file(tensores, str(pesos))
    return json.loads((dest / "adapter_config.json").read_text(encoding="utf-8"))


LICENCIA = """# Licencia

Los pesos de este adaptador y su documentación se publican bajo
**Creative Commons Atribución-NoComercial 4.0 Internacional (CC BY-NC 4.0)**.

Texto legal completo: https://creativecommons.org/licenses/by-nc/4.0/legalcode.es

Puedes:
- **Compartir**: copiar y redistribuir el material en cualquier medio o formato.
- **Adaptar**: remezclar, transformar y construir a partir del material.

Bajo estas condiciones:
- **Atribución**: cita a Field Shift Guatemala y a las fuentes listadas en [CREDITOS.md](CREDITOS.md).
- **No comercial**: no puedes usarlo con fines comerciales.

El modelo base, Qwen2.5-0.5B-Instruct (Alibaba Cloud), tiene licencia Apache 2.0; la licencia NC
aplica a este adaptador por las condiciones de varias fuentes de entrenamiento.

Los textos de entrenamiento **no** se distribuyen aquí; pertenecen a sus autores e instituciones.
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--checkpoint", default=None, help="por defecto, el último de modelos/sft/checkpoints")
    ap.add_argument("--destino", default=str(RAIZ / "modelo_lenguas_mayas"))
    ap.add_argument("--version", default="v1-experimental")
    ap.add_argument("--plan", choices=["cpu", "gpu"], default="cpu",
                    help="cpu: una noche, solo traducción; gpu: pre-entrenamiento + SFT completo (Colab)")
    a = ap.parse_args()
    tareas = ["traducir_es_maya", "traducir_maya_es"] if a.plan == "cpu" else None

    ad_sft = MODELOS / "sft" / "adaptador"
    ck = Path(a.checkpoint) if a.checkpoint else (
        ad_sft if (ad_sft / "adapter_config.json").exists() else ultimo_checkpoint(MODELOS / "sft" / "checkpoints"))
    if not ck or not (Path(ck) / "adapter_config.json").exists():
        raise SystemExit("No encontré el adaptador del SFT (modelos/sft/adaptador ni checkpoints).")
    ck = Path(ck)
    dest = Path(a.destino)
    dest.mkdir(parents=True, exist_ok=True)
    cfg = combinar_y_guardar(ck, dest)
    tam_mb = (dest / "adapter_model.safetensors").stat().st_size / 1e6
    if tam_mb > 95:
        raise SystemExit(f"El adaptador pesa {tam_mb:.0f} MB: GitHub rechaza archivos de más de 100 MB.")

    ck_estado = ck if (ck / "trainer_state.json").exists() else ultimo_checkpoint(MODELOS / "sft" / "checkpoints")
    estado = (json.loads((Path(ck_estado) / "trainer_state.json").read_text(encoding="utf-8")) if ck_estado
              else {"global_step": 0, "log_history": []})
    pasos, epoca = estado["global_step"], estado.get("epoch", 0)
    perdidas = [round(h["loss"], 2) for h in estado["log_history"] if "loss" in h]
    metricas_f = MODELOS / "sft" / "final" / "metricas.json"
    chrf = json.loads(metricas_f.read_text(encoding="utf-8"))["chrf"] if metricas_f.exists() else {}

    filas = [r for r in leer_jsonl(DATOS_LLM / "sft_train.jsonl") if not tareas or r["tarea"] in tareas]
    por_lengua = Counter(r["lang"] for r in filas)
    vistos = int(epoca * len(filas))
    resumen = {"version": a.version, "fecha": date.today().isoformat(), "checkpoint": ck.name, "pasos": pasos,
               "epoca": round(epoca, 3), "ejemplos_vistos_aprox": vistos, "perdida_inicial": perdidas[:1],
               "perdida_final": perdidas[-1:], "chrf": chrf, "lora_r": cfg.get("r"), "lora_alpha": cfg.get("lora_alpha"),
               "modelo_base": cfg.get("base_model_name_or_path"), "plan": a.plan, "tareas": tareas or "todas",
               "ejemplos_por_lengua": dict(por_lengua)}
    (dest / "entrenamiento.json").write_text(json.dumps(resumen, indent=2, ensure_ascii=False), encoding="utf-8")
    (dest / "LICENSE.md").write_text(LICENCIA, encoding="utf-8")

    cred = CORPUS / "final" / "CREDITOS.md"
    txt = ("# Créditos\n\n## Fuentes de los pares de traducción usados en este adaptador\n\n"
           + "\n".join(f"- {n} — {u}" for n, u in FUENTES_DICC)
           + "\n\n## Créditos completos del corpus del proyecto\n\n"
             "Lista de todas las obras recopiladas para el corpus (incluye las que se usarán en versiones "
             "futuras con pre-entrenamiento). Los textos no se distribuyen.\n\n")
    if cred.exists():
        txt += cred.read_text(encoding="utf-8").split("\n", 1)[1]
    (dest / "CREDITOS.md").write_text(txt, encoding="utf-8")

    tabla_chrf = "\n".join(f"| {k} | {v} |" for k, v in chrf.items()) or "| (sin evaluar) | |"
    tabla_lenguas = "\n".join(f"| {LENGUAS[l]} | {por_lengua.get(l, 0):,} |".replace(",", " ") for l in MAYAS)
    ficha = f"""# Traductor de lenguas mayas (español ↔ k'iche', kaqchikel, q'eqchi', mam) · {a.version}

Adaptador LoRA para **{cfg.get('base_model_name_or_path')}**. Traduce palabras y frases cortas entre el
español y cuatro idiomas mayas de Guatemala. Parte de [Field Shift Guatemala](../README.md)
(NASA Space Apps Challenge). Código de entrenamiento: [scripts/traductor_lenguas_mayas/](../scripts/traductor_lenguas_mayas/).

> **Versión experimental.** {AVISO[a.plan].format(epoca=epoca)} Sus traducciones tienen errores
> frecuentes y **deben revisarlas hablantes nativos** antes de usarse con personas.

## Cómo usarlo

```python
from peft import PeftModel
from transformers import AutoModelForCausalLM, AutoTokenizer

base = "{cfg.get('base_model_name_or_path')}"
tok = AutoTokenizer.from_pretrained(base)
model = AutoModelForCausalLM.from_pretrained(base)
model = PeftModel.from_pretrained(model, "modelo_lenguas_mayas").merge_and_unload()

msgs = [{{"role": "system", "content": "Eres un asistente que escribe y traduce entre el español y los idiomas mayas k'iche', kaqchikel, q'eqchi' y mam de Guatemala. Usa la ortografía de la ALMG, con el saltillo escrito como '. Responde solo con el texto pedido."}},
        {{"role": "user", "content": "Traduce del español al k'iche':\\nmaíz"}}]
texto = tok.apply_chat_template(msgs, tokenize=False, add_generation_prompt=True)
ids = tok(texto, return_tensors="pt").input_ids
print(tok.decode(model.generate(ids, max_new_tokens=40)[0][ids.shape[1]:], skip_special_tokens=True))
```

O desde la consola del proyecto: `python scripts/traductor_lenguas_mayas/probar_modelo.py --modelo modelo_lenguas_mayas`.

El prompt debe seguir el formato de arriba (`Traduce del <lengua> al <lengua>:\\n<texto>`), que es con el que se entrenó.

**Integración en la app del teléfono** (API, feedback y aprendizaje continuo): [USO_EN_LA_APP.md](USO_EN_LA_APP.md).

**Antecedentes y qué aporta este modelo frente a trabajos anteriores:** [ANTECEDENTES.md](ANTECEDENTES.md).

## Datos de entrenamiento

{DATOS[a.plan]}

| Lengua | Ejemplos disponibles |
|---|---:|
{tabla_lenguas}

Fuentes y autorías: [CREDITOS.md](CREDITOS.md). Los textos no se distribuyen en este repositorio.

## Entrenamiento

- Modelo base: `{cfg.get('base_model_name_or_path')}` · LoRA r={cfg.get('r')}, alpha={cfg.get('lora_alpha')}, todas las capas lineales.
- Hardware: {HARDWARE[a.plan]}.
- Pasos: {pasos} ({epoca:.2f} épocas, ≈ {vistos:,} ejemplos vistos). Pérdida: {perdidas[0] if perdidas else '?'} → {perdidas[-1] if perdidas else '?'}.
- Detalles: [entrenamiento.json](entrenamiento.json).

## Evaluación

chrF++ sobre 60 pares reservados de los diccionarios (no vistos en el entrenamiento). Más alto es mejor (0–100).

| Dirección | chrF++ |
|---|---:|
{tabla_chrf}

Con tan pocos pares por dirección, estas cifras son orientativas.

## Limitaciones y uso responsable

- Aprendió de diccionarios: traduce mejor **palabras sueltas** que oraciones.
- K'iche' y q'eqchi' tienen pocos pares; mam y kaqchikel, más.
- Puede inventar palabras con apariencia maya. No lo uses para documentos oficiales, salud o temas legales sin revisión humana.
- Son lenguas de pueblos indígenas: cualquier uso público debería contar con la participación de sus
  hablantes y de la Academia de Lenguas Mayas de Guatemala (ALMG).

## Licencia

[CC BY-NC 4.0](LICENSE.md): uso libre con atribución, **sin fines comerciales**.
"""
    (dest / "README.md").write_text(ficha, encoding="utf-8")
    print(f"Listo: {dest}  (adaptador {tam_mb:.1f} MB, checkpoint {ck.name}, {pasos} pasos)")


if __name__ == "__main__":
    main()
