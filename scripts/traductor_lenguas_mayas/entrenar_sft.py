"""Etapa 2: ajuste por instrucciones (SFT) para traducir y generar texto.

Parte del modelo de la etapa 1 (modelos/cpt/final) si existe; si no, del modelo base.
Entrena con datos/lenguas_mayas/pretraining/llm/sft_train.jsonl (formato prompt/completion conversacional de TRL,
así la pérdida solo cuenta los tokens de la respuesta). Al terminar:
  - fusiona el LoRA y guarda en modelos/sft/final
  - mide chrF en sft_eval.jsonl
  - registra el modelo en modelos/ACTUAL (lo que sirve servidor_api.py)

Uso
  python entrenar_sft.py
Prueba rápida en CPU
  python entrenar_sft.py --modelo HuggingFaceTB/SmolLM2-135M-Instruct --max-ejemplos 64 --max-pasos 3 --max-eval 6
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

from comun import (DATOS_LLM, MODELO_BASE, MODELOS, callback_limite_tiempo, config_lora, dispositivo_y_dtype,
                   evitar_suspension, fusionar_y_guardar, registrar_modelo, ultimo_checkpoint)


def main():
    cpt = MODELOS / "cpt" / "final"
    ap = argparse.ArgumentParser()
    ap.add_argument("--modelo", default=str(cpt) if cpt.exists() else MODELO_BASE)
    ap.add_argument("--salida", default=str(MODELOS / "sft"))
    ap.add_argument("--epocas", type=float, default=2.0)
    ap.add_argument("--max-pasos", type=int, default=-1)
    ap.add_argument("--lr", type=float, default=1e-4)
    ap.add_argument("--batch", type=int, default=16)
    ap.add_argument("--grad-accum", type=int, default=2)
    ap.add_argument("--max-len", type=int, default=512)
    ap.add_argument("--lora-r", type=int, default=32)
    ap.add_argument("--max-ejemplos", type=int, default=0)
    ap.add_argument("--max-eval", type=int, default=200)
    ap.add_argument("--max-horas", type=float, default=0, help="parar (guardando) tras N horas; 0 = sin límite")
    ap.add_argument("--save-pasos", type=int, default=500)
    ap.add_argument("--solo-tareas", nargs="*", default=None,
                    help="usar solo estas tareas (p. ej. traducir_es_maya traducir_maya_es) para entrenar más rápido en CPU")
    ap.add_argument("--no-registrar", action="store_true")
    a = ap.parse_args()

    import torch
    from datasets import load_dataset
    from transformers import AutoModelForCausalLM, AutoTokenizer
    from trl import SFTConfig, SFTTrainer

    from evaluar import cargar_eval, evaluar

    dev, dtype, bf16, fp16 = dispositivo_y_dtype()
    print(f"Modelo de partida: {a.modelo}  ({dev})")
    tok = AutoTokenizer.from_pretrained(a.modelo)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    model = AutoModelForCausalLM.from_pretrained(a.modelo, dtype=torch.float32 if dev == "cpu" else dtype)

    ds = load_dataset("json", data_files=str(DATOS_LLM / "sft_train.jsonl"), split="train")
    if a.solo_tareas:
        ds = ds.filter(lambda r: r["tarea"] in a.solo_tareas)
    ds = ds.remove_columns([c for c in ds.column_names if c not in ("prompt", "completion")])
    if a.max_ejemplos:
        ds = ds.shuffle(seed=42).select(range(min(a.max_ejemplos, len(ds))))
    print(f"Ejemplos SFT: {len(ds)}")

    salida = Path(a.salida)
    cfg = SFTConfig(
        output_dir=str(salida / "checkpoints"), num_train_epochs=a.epocas, max_steps=a.max_pasos,
        per_device_train_batch_size=a.batch, gradient_accumulation_steps=a.grad_accum,
        learning_rate=a.lr, lr_scheduler_type="cosine", warmup_steps=0.03, logging_steps=10,
        save_steps=a.save_pasos, save_total_limit=2, bf16=bf16, fp16=fp16, report_to="none",
        max_length=a.max_len, completion_only_loss=True, gradient_checkpointing=dev == "cuda",
    )
    trainer = SFTTrainer(model=model, args=cfg, train_dataset=ds, processing_class=tok,
                         peft_config=config_lora(r=a.lora_r, alpha=2 * a.lora_r))
    trainer.add_callback(callback_limite_tiempo(a.max_horas))
    reanudar = ultimo_checkpoint(salida / "checkpoints")
    if reanudar:
        print(f"Reanudando desde {reanudar}")
    evitar_suspension(True)
    trainer.train(resume_from_checkpoint=reanudar)

    final = salida / "final"
    model = fusionar_y_guardar(trainer.model, tok, final).eval()
    print(f"Modelo guardado en {final}")
    metricas = evaluar(model, tok, cargar_eval(a.max_eval))
    (final / "metricas.json").write_text(json.dumps({"chrf": metricas}, indent=2), encoding="utf-8")
    print("chrF++:", json.dumps(metricas, indent=2))
    if not a.no_registrar:
        registrar_modelo(final)
        print(f"Registrado como modelo en producción (modelos/ACTUAL -> {final})")


if __name__ == "__main__":
    main()
