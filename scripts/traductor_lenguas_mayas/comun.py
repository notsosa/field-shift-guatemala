"""Configuración y utilidades compartidas por los scripts del LLM de lenguas mayas.

Flujo completo (ver README.md de esta carpeta):
  1. preparar_datos_llm.py   corpus + diccionarios  ->  datos/lenguas_mayas/llm/*.jsonl
  2. entrenar_pretraining.py pre-entrenamiento continuo (texto maya crudo, LoRA)
  3. entrenar_sft.py         ajuste por instrucciones (traducir / generar)
  4. servidor_api.py         API para la app del teléfono + registro de feedback
  5. entrenar_hfrl.py        ronda de aprendizaje continuo con el feedback humano (KTO/DPO)
"""
from __future__ import annotations

import json
from pathlib import Path

import os

RAIZ = Path(__file__).resolve().parents[2]
DATOS = RAIZ / "datos" / "lenguas_mayas"
# El corpus está en el repo PRIVADO mariobet23440/lenguas-mayas-corpus (licencias restringidas):
#   git clone https://github.com/mariobet23440/lenguas-mayas-corpus datos/lenguas_mayas/pretraining
CORPUS = Path(os.environ.get("FIELDSHIFT_CORPUS", DATOS / "pretraining"))
DATOS_LLM = DATOS / "llm"
MODELOS = RAIZ / "modelos"            # en .gitignore: pesos y feedback de usuarios
REGISTRO = MODELOS / "ACTUAL"         # texto con la ruta del modelo en producción
FEEDBACK_DB = Path(os.environ.get("FIELDSHIFT_FEEDBACK_DB", MODELOS / "feedback.db"))

MODELO_BASE = "Qwen/Qwen2.5-0.5B-Instruct"

# código interno -> nombre que se usa en los prompts
LENGUAS = {
    "es": "español",
    "kiche": "k'iche'",
    "kaqchikel": "kaqchikel",
    "qeqchi": "q'eqchi'",
    "mam": "mam",
}
MAYAS = [k for k in LENGUAS if k != "es"]

SISTEMA = (
    "Eres un asistente que escribe y traduce entre el español y los idiomas mayas "
    "k'iche', kaqchikel, q'eqchi' y mam de Guatemala. Usa la ortografía de la ALMG, "
    "con el saltillo escrito como '. Responde solo con el texto pedido."
)


# --------------------------------------------------------------- prompts
def prompt_traducir(texto: str, origen: str, destino: str) -> list[dict]:
    return [
        {"role": "system", "content": SISTEMA},
        {"role": "user", "content": f"Traduce del {LENGUAS[origen]} al {LENGUAS[destino]}:\n{texto}"},
    ]


def prompt_generar(instruccion: str, lengua: str) -> list[dict]:
    return [
        {"role": "system", "content": SISTEMA},
        {"role": "user", "content": f"Escribe en {LENGUAS[lengua]}: {instruccion}"},
    ]


def asistente(texto: str) -> list[dict]:
    return [{"role": "assistant", "content": texto}]


# --------------------------------------------------------------- utilidades
def leer_jsonl(ruta: Path):
    with open(ruta, encoding="utf-8") as f:
        for linea in f:
            if linea.strip():
                yield json.loads(linea)


def escribir_jsonl(ruta: Path, filas) -> int:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    n = 0
    with open(ruta, "w", encoding="utf-8") as f:
        for fila in filas:
            f.write(json.dumps(fila, ensure_ascii=False) + "\n")
            n += 1
    return n


def modelo_actual(defecto: str | None = None) -> str:
    """Ruta del modelo en producción (escrita por entrenar_sft.py / entrenar_hfrl.py)."""
    if REGISTRO.exists():
        ruta = REGISTRO.read_text(encoding="utf-8").strip()
        if ruta:
            return ruta
    if defecto:
        return defecto
    raise SystemExit(f"No hay modelo registrado en {REGISTRO}. Entrena primero con entrenar_sft.py.")


def registrar_modelo(ruta: Path) -> None:
    REGISTRO.parent.mkdir(parents=True, exist_ok=True)
    REGISTRO.write_text(str(Path(ruta).resolve()), encoding="utf-8")


def dispositivo_y_dtype():
    import torch
    if torch.cuda.is_available():
        bf16 = torch.cuda.is_bf16_supported()
        return "cuda", (torch.bfloat16 if bf16 else torch.float16), bf16, not bf16
    return "cpu", torch.float32, False, False


def cargar_modelo(ruta: str, para_entrenar: bool = False):
    from transformers import AutoModelForCausalLM, AutoTokenizer
    dev, dtype, _, _ = dispositivo_y_dtype()
    tok = AutoTokenizer.from_pretrained(ruta)
    if tok.pad_token is None:
        tok.pad_token = tok.eos_token
    model = AutoModelForCausalLM.from_pretrained(ruta, dtype=dtype)
    if not para_entrenar:
        model.to(dev).eval()
    return model, tok


def config_lora(r: int = 16, alpha: int = 32):
    from peft import LoraConfig
    return LoraConfig(
        r=r, lora_alpha=alpha, lora_dropout=0.05, bias="none", task_type="CAUSAL_LM",
        target_modules="all-linear",
    )


def fusionar_y_guardar(model, tok, destino: Path):
    """Fusiona el adaptador LoRA en los pesos y guarda un modelo completo (fácil de servir o convertir a GGUF).
    Devuelve el modelo fusionado."""
    if hasattr(model, "merge_and_unload"):
        model = model.merge_and_unload()
    destino.mkdir(parents=True, exist_ok=True)
    model.save_pretrained(destino, safe_serialization=True)
    tok.save_pretrained(destino)
    return model


def generar(model, tok, mensajes: list[dict], n: int = 1, max_new_tokens: int = 200,
            temperatura: float = 0.7, top_p: float = 0.9) -> list[str]:
    import torch
    texto = tok.apply_chat_template(mensajes, tokenize=False, add_generation_prompt=True)
    enc = tok(texto, return_tensors="pt").to(model.device)
    muestrear = n > 1 or temperatura > 0
    with torch.no_grad():
        out = model.generate(
            **enc, max_new_tokens=max_new_tokens, num_return_sequences=n,
            do_sample=muestrear, temperature=temperatura if muestrear else None,
            top_p=top_p if muestrear else None, repetition_penalty=1.1,
            pad_token_id=tok.pad_token_id,
        )
    largo = enc["input_ids"].shape[1]
    return [tok.decode(o[largo:], skip_special_tokens=True).strip() for o in out]
