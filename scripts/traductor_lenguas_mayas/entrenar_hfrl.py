"""Etapa 3 (continua): una ronda de aprendizaje con feedback humano (HFRL / RLHF).

Pensado para correr de forma periódica (cada noche o cada semana) en una máquina con GPU:

  1. Lee el feedback pendiente de modelos/feedback.db (lo escribe servidor_api.py).
  2. Lo convierte en datos de preferencia:
       KTO (por defecto): ejemplos sueltos "bueno/malo" -> sirve para 👍/👎, elecciones y correcciones.
       DPO: pares (elegido, rechazado)               -> solo elecciones y correcciones.
     Ambos son variantes de RLHF que no necesitan un modelo de recompensa ni PPO: optimizan la
     política directamente contra un modelo de referencia (el modelo actual congelado), con una
     penalización KL (beta) que evita que se aleje demasiado de lo que ya sabía.
  3. Mezcla ejemplos "de repaso" del SFT como deseables (--repaso) para no olvidar lo aprendido.
  4. Entrena un LoRA sobre el modelo en producción, lo fusiona y lo evalúa (chrF en sft_eval).
  5. Compuerta de calidad: si el chrF no cae más de --tolerancia puntos, guarda la versión nueva en
     modelos/hfrl/vNNNN, la registra en modelos/ACTUAL, marca el feedback como usado y, si se da
     --recargar-url, pide a la API que cargue el modelo nuevo. Si no pasa, nada cambia y el
     feedback queda pendiente para la próxima ronda.

Uso
  python entrenar_hfrl.py                              # KTO con todo el feedback pendiente
  python entrenar_hfrl.py --algoritmo dpo --min-ejemplos 200
  python entrenar_hfrl.py --recargar-url http://localhost:8000   (usa FIELDSHIFT_ADMIN_TOKEN)
Programarlo (Linux): crontab  0 2 * * *  cd repo && .venv/bin/python scripts/traductor_lenguas_mayas/entrenar_hfrl.py
"""
from __future__ import annotations

import argparse
import json
import os
import random
import urllib.request
from datetime import datetime
from pathlib import Path

import feedback_db as fdb
from comun import (DATOS_LLM, MODELOS, config_lora, dispositivo_y_dtype, fusionar_y_guardar, leer_jsonl,
                   modelo_actual, registrar_modelo)


def siguiente_version() -> Path:
    base = MODELOS / "hfrl"
    base.mkdir(parents=True, exist_ok=True)
    n = max([int(p.name[1:]) for p in base.glob("v[0-9]*") if p.name[1:].isdigit()] + [0]) + 1
    return base / f"v{n:04d}"


def repaso_sft(n: int, seed: int):
    """Ejemplos del SFT como 'deseables' (KTO): anclan al modelo en lo verificado."""
    ruta = DATOS_LLM / "sft_train.jsonl"
    if n <= 0 or not ruta.exists():
        return []
    filas = [r for r in leer_jsonl(ruta) if r["tarea"].startswith("traducir")]
    return [{"prompt": r["prompt"], "completion": r["completion"], "label": True}
            for r in random.Random(seed).sample(filas, min(n, len(filas)))]


def pesos_kto(filas):
    """KTO recomienda que (peso_d * n_deseables) / (peso_u * n_indeseables) esté entre 1 y 4/3."""
    d = sum(r["label"] for r in filas)
    u = len(filas) - d
    if not d or not u:
        return 1.0, 1.0
    return (1.0, round(d / u, 3)) if d >= u else (round(u / d, 3), 1.0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--algoritmo", choices=["kto", "dpo"], default="kto")
    ap.add_argument("--modelo", default=None, help="por defecto, el de modelos/ACTUAL")
    ap.add_argument("--min-ejemplos", type=int, default=50, help="no entrenar con menos señales que esto")
    ap.add_argument("--umbral-voto", type=float, default=1.0)
    ap.add_argument("--aceptar-correcciones-no-verificadas", action="store_true")
    ap.add_argument("--repaso", type=int, default=0, help="ejemplos SFT de repaso (por defecto = nº de señales, KTO)")
    ap.add_argument("--beta", type=float, default=0.1)
    ap.add_argument("--lr", type=float, default=5e-5)
    ap.add_argument("--epocas", type=float, default=1.0)
    ap.add_argument("--max-pasos", type=int, default=-1)
    ap.add_argument("--batch", type=int, default=4)
    ap.add_argument("--grad-accum", type=int, default=4)
    ap.add_argument("--max-eval", type=int, default=200)
    ap.add_argument("--tolerancia", type=float, default=1.0, help="caída máxima de chrF aceptada")
    ap.add_argument("--forzar", action="store_true", help="promover aunque no pase la compuerta")
    ap.add_argument("--recargar-url", default=None)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    con = fdb.conectar()
    kto, dpo, usados = fdb.construir_ejemplos(con, a.umbral_voto, not a.aceptar_correcciones_no_verificadas)
    filas = kto if a.algoritmo == "kto" else dpo
    print(f"Feedback pendiente -> KTO: {len(kto)} ejemplos, DPO: {len(dpo)} pares ({len(usados)} registros)")
    if len(filas) < a.min_ejemplos:
        print(f"Menos de {a.min_ejemplos} ejemplos para {a.algoritmo.upper()}: no se entrena en esta ronda.")
        return

    import torch
    from datasets import Dataset
    from transformers import AutoModelForCausalLM, AutoTokenizer

    from evaluar import cargar_eval, evaluar

    actual = a.modelo or modelo_actual()
    dev, dtype, bf16, fp16 = dispositivo_y_dtype()
    print(f"Modelo actual: {actual} ({dev})")
    tok = AutoTokenizer.from_pretrained(actual)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    model = AutoModelForCausalLM.from_pretrained(actual, dtype=torch.float32 if dev == "cpu" else dtype)

    # el modelo actual y el nuevo se miden sobre LA MISMA muestra para que la compuerta sea justa
    eval_filas = cargar_eval(a.max_eval, a.seed)
    base_chrf = evaluar(model.to(dev).eval(), tok, eval_filas)
    model.train()
    print("chrF antes:", base_chrf)

    salida = siguiente_version()
    comun = dict(output_dir=str(salida / "checkpoints"), num_train_epochs=a.epocas, max_steps=a.max_pasos,
                 per_device_train_batch_size=a.batch, gradient_accumulation_steps=a.grad_accum,
                 learning_rate=a.lr, lr_scheduler_type="cosine", warmup_steps=0.1, logging_steps=5,
                 save_strategy="no", bf16=bf16, fp16=fp16, report_to="none", beta=a.beta,
                 max_length=512, seed=a.seed)
    peft = config_lora(r=16, alpha=32)

    if a.algoritmo == "kto":
        from trl import KTOConfig, KTOTrainer
        filas = filas + repaso_sft(a.repaso or len(filas), a.seed)
        random.Random(a.seed).shuffle(filas)
        wd, wu = pesos_kto(filas)
        print(f"KTO: {sum(r['label'] for r in filas)} deseables / {sum(not r['label'] for r in filas)} indeseables "
              f"(pesos {wd}/{wu})")
        cfg = KTOConfig(**comun, desirable_weight=wd, undesirable_weight=wu)
        trainer = KTOTrainer(model=model, args=cfg, train_dataset=Dataset.from_list(filas),
                             processing_class=tok, peft_config=peft)
    else:
        from trl import DPOConfig, DPOTrainer
        cfg = DPOConfig(**comun)
        trainer = DPOTrainer(model=model, args=cfg, train_dataset=Dataset.from_list(filas),
                             processing_class=tok, peft_config=peft)
    trainer.train()

    nuevo = fusionar_y_guardar(trainer.model, tok, salida).eval()
    nuevo_chrf = evaluar(nuevo, tok, eval_filas)
    print("chrF después:", nuevo_chrf)
    caida = base_chrf["total"] - nuevo_chrf["total"]
    info = {"chrf": nuevo_chrf, "chrf_anterior": base_chrf, "modelo_anterior": actual,
            "algoritmo": a.algoritmo, "ejemplos": len(filas), "feedback_usado": len(usados),
            "fecha": datetime.now().isoformat(timespec="seconds"), "promovido": caida <= a.tolerancia or a.forzar}
    (salida / "metricas.json").write_text(json.dumps(info, indent=2, ensure_ascii=False), encoding="utf-8")

    if not info["promovido"]:
        print(f"RECHAZADO: el chrF bajó {caida:.2f} puntos (> {a.tolerancia}). Producción no cambia; "
              f"el feedback queda pendiente. Versión guardada para inspección en {salida}")
        return
    registrar_modelo(salida)
    fdb.marcar_usados(con, usados, salida.name)
    print(f"PROMOVIDO: {salida.name} es el nuevo modelo en producción.")
    if a.recargar_url:
        req = urllib.request.Request(a.recargar_url.rstrip("/") + "/v1/admin/recargar", method="POST",
                                     headers={"X-Admin-Token": os.environ.get("FIELDSHIFT_ADMIN_TOKEN", "")})
        print(urllib.request.urlopen(req, timeout=300).read().decode())


if __name__ == "__main__":
    main()
