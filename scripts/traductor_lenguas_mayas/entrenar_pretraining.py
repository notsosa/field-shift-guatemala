"""Etapa 1: pre-entrenamiento continuo del LLM con el texto crudo en lenguas mayas (LoRA).

El modelo base (Qwen2.5 por defecto) ya sabe español, pero casi no ha visto k'iche', kaqchikel,
q'eqchi' ni mam. Esta etapa le enseña vocabulario, ortografía y sintaxis prediciendo el siguiente
token sobre los shards de datos/lenguas_mayas/pretraining/shards/.

- Cada documento lleva una primera línea "Idioma: <lengua>" para que el modelo asocie texto y lengua.
- Balanceo de lenguas: muestreo con temperatura (alpha=0.5) para que el k'iche' (0.8 M caracteres)
  no quede ahogado por el q'eqchi' (7.3 M).
- Packing: los documentos tokenizados se concatenan y se cortan en bloques de --block-size tokens.
- Al final se fusiona el LoRA y se guarda un modelo completo en --salida.

Uso (GPU recomendada: Colab T4 tarda ~1-2 h por época con Qwen2.5-0.5B)
  python entrenar_pretraining.py --salida ../../modelos/cpt
Prueba rápida en CPU
  python entrenar_pretraining.py --modelo HuggingFaceTB/SmolLM2-135M-Instruct --max-docs 40 --max-pasos 3 --block-size 128
"""
from __future__ import annotations

import argparse
import math
import random
from itertools import chain
from pathlib import Path

from comun import (CORPUS, LENGUAS, MAYAS, MODELO_BASE, MODELOS, callback_limite_tiempo, config_lora,
                   dispositivo_y_dtype, evitar_suspension, fusionar_y_guardar, ultimo_checkpoint)


def cargar_docs(lenguas, max_docs, alpha, seed):
    from datasets import Dataset, load_dataset
    rng = random.Random(seed)
    por_lengua = {}
    for lang in lenguas:
        ds = load_dataset("json", data_files=str(CORPUS / "shards" / lang / "*.jsonl"), split="train")
        textos = [f"Idioma: {LENGUAS[lang]}\n{t}" for t in ds["text"]]
        rng.shuffle(textos)
        por_lengua[lang] = textos[:max_docs] if max_docs else textos
    tam = {k: sum(map(len, v)) for k, v in por_lengua.items()}
    total = sum(tam.values())
    pesos = {k: (n / total) ** alpha for k, n in tam.items()}
    z = sum(pesos.values())
    docs = []
    for lang, textos in por_lengua.items():
        factor = (pesos[lang] / z) / (tam[lang] / total)        # >1 sobremuestrea, <1 submuestrea
        entero, frac = int(factor), factor - int(factor)
        elegidos = textos * entero + [t for t in textos if rng.random() < frac]
        print(f"  {lang:10s} docs={len(textos):5d} caracteres={tam[lang]:>9,d} factor={factor:.2f} -> {len(elegidos)}")
        docs += elegidos
    rng.shuffle(docs)
    return Dataset.from_dict({"text": docs})


def empaquetar(ds, tok, block):
    def tokenizar(b):
        ids = tok(b["text"], add_special_tokens=False)["input_ids"]
        return {"input_ids": [x + [tok.eos_token_id] for x in ids]}

    def agrupar(b):
        todo = list(chain.from_iterable(b["input_ids"]))
        n = (len(todo) // block) * block
        bloques = [todo[i:i + block] for i in range(0, n, block)]
        return {"input_ids": bloques}          # el collator crea las etiquetas (labels = input_ids)

    ds = ds.map(tokenizar, batched=True, remove_columns=["text"], desc="tokenizando")
    return ds.map(agrupar, batched=True, batch_size=1000, desc="empaquetando")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--modelo", default=MODELO_BASE)
    ap.add_argument("--salida", default=str(MODELOS / "cpt"))
    ap.add_argument("--lenguas", nargs="+", default=MAYAS, choices=MAYAS)
    ap.add_argument("--block-size", type=int, default=1024)
    ap.add_argument("--epocas", type=float, default=1.0)
    ap.add_argument("--max-pasos", type=int, default=-1)
    ap.add_argument("--lr", type=float, default=2e-4)
    ap.add_argument("--batch", type=int, default=4)
    ap.add_argument("--grad-accum", type=int, default=8)
    ap.add_argument("--lora-r", type=int, default=64, help="rango alto: hay mucho vocabulario nuevo que aprender")
    ap.add_argument("--alpha-muestreo", type=float, default=0.5)
    ap.add_argument("--max-docs", type=int, default=0, help="limitar documentos por lengua (pruebas)")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--max-horas", type=float, default=0, help="parar (guardando) tras N horas; 0 = sin límite")
    ap.add_argument("--save-pasos", type=int, default=200, help="cada cuántos pasos evaluar y guardar checkpoint")
    a = ap.parse_args()

    import torch
    from peft import get_peft_model
    from transformers import (AutoModelForCausalLM, AutoTokenizer, DataCollatorForLanguageModeling, Trainer,
                              TrainingArguments)

    dev, dtype, bf16, fp16 = dispositivo_y_dtype()
    print(f"Dispositivo: {dev}  dtype: {dtype}")
    tok = AutoTokenizer.from_pretrained(a.modelo)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token

    print("Cargando corpus:")
    ds = empaquetar(cargar_docs(a.lenguas, a.max_docs, a.alpha_muestreo, a.seed), tok, a.block_size)
    ds = ds.train_test_split(test_size=max(1, int(0.01 * len(ds))), seed=a.seed)
    print(f"Bloques de {a.block_size} tokens: train={len(ds['train'])} eval={len(ds['test'])}")

    model = AutoModelForCausalLM.from_pretrained(a.modelo, dtype=torch.float32 if dev == "cpu" else dtype)
    if dev == "cuda":
        model.gradient_checkpointing_enable()
        model.enable_input_require_grads()
    model = get_peft_model(model, config_lora(r=a.lora_r, alpha=2 * a.lora_r))
    model.print_trainable_parameters()

    salida = Path(a.salida)
    args = TrainingArguments(
        output_dir=str(salida / "checkpoints"), num_train_epochs=a.epocas, max_steps=a.max_pasos,
        per_device_train_batch_size=a.batch, per_device_eval_batch_size=a.batch,
        gradient_accumulation_steps=a.grad_accum, learning_rate=a.lr, lr_scheduler_type="cosine",
        warmup_steps=0.03, weight_decay=0.0, logging_steps=10, eval_strategy="steps", eval_steps=a.save_pasos,
        save_steps=a.save_pasos, save_total_limit=2, bf16=bf16, fp16=fp16, report_to="none", seed=a.seed,
    )
    trainer = Trainer(model=model, args=args, train_dataset=ds["train"], eval_dataset=ds["test"],
                      data_collator=DataCollatorForLanguageModeling(tok, mlm=False))
    trainer.add_callback(callback_limite_tiempo(a.max_horas))
    reanudar = ultimo_checkpoint(salida / "checkpoints")
    if reanudar:
        print(f"Reanudando desde {reanudar}")
    evitar_suspension(True)
    trainer.train(resume_from_checkpoint=reanudar)
    m = trainer.evaluate()
    print(f"Perplejidad en eval: {math.exp(m['eval_loss']):.2f}")
    fusionar_y_guardar(trainer.model, tok, salida / "final")   # la etapa 2 parte de aquí
    print(f"Modelo guardado en {salida / 'final'}")


if __name__ == "__main__":
    main()
