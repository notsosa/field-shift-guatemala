"""Entrenamiento desatendido (de noche, en segundo plano), con límite de horas y reanudación.

Elige el plan según el hardware:
  GPU  -> etapa 1 (pre-entrenamiento continuo) + etapa 2 (SFT completo), sin límite de tiempo.
  CPU  -> solo SFT de traducción (`traducir_es_maya`, `traducir_maya_es`), secuencias cortas y
          límite de --horas. El pre-entrenamiento con 8 M de tokens no es viable en CPU.

Si la computadora se apaga o se suspende, vuelve a lanzarlo: cada etapa reanuda desde su último
checkpoint (modelos/<etapa>/checkpoints). Al terminar, evalúa, guarda y registra el modelo en
modelos/ACTUAL, así que `probar_modelo.py` lo usa directamente.

Mientras corre, pide a Windows que no se suspenda (sin cambiar la configuración). Aun así, deja la
computadora conectada a la corriente y con la tapa abierta.

Uso (normalmente desde iniciar_entrenamiento_noche.ps1, que lo deja en segundo plano)
  python entrenar_noche.py --horas 8
Progreso
  modelos/logs/ESTADO.txt   y   modelos/logs/noche-<fecha>.log
"""
from __future__ import annotations

import argparse
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from comun import DATOS_LLM, MODELO_BASE, MODELOS, evitar_suspension

AQUI = Path(__file__).resolve().parent
LOGS = MODELOS / "logs"


def estado(msg: str):
    LOGS.mkdir(parents=True, exist_ok=True)
    linea = f"[{datetime.now():%Y-%m-%d %H:%M}] {msg}"
    print(linea, flush=True)
    with open(LOGS / "ESTADO.txt", "a", encoding="utf-8") as f:
        f.write(linea + "\n")


def correr(args: list[str]) -> int:
    estado("$ python " + " ".join(args))
    return subprocess.call([sys.executable, "-u", *args], cwd=AQUI)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--horas", type=float, default=8.0, help="tiempo total disponible (solo se aplica en CPU)")
    ap.add_argument("--modelo", default=MODELO_BASE)
    a = ap.parse_args()

    import torch
    gpu = torch.cuda.is_available()
    t0 = time.time()
    evitar_suspension(True)
    estado(f"Inicio. Dispositivo: {'GPU ' + torch.cuda.get_device_name(0) if gpu else f'CPU ({torch.get_num_threads()} hilos)'}")

    if not (DATOS_LLM / "sft_train.jsonl").exists():
        if correr(["preparar_datos_llm.py"]):
            return estado("ERROR preparando los datos. Revisa el log.")

    if gpu:
        if correr(["entrenar_pretraining.py", "--modelo", a.modelo]):
            return estado("ERROR en la etapa 1. Revisa el log.")
        rc = correr(["entrenar_sft.py", "--modelo", str(MODELOS / "cpt" / "final")])
    else:
        # se reservan ~45 min para fusionar, evaluar y guardar
        horas_sft = max(0.25, a.horas - (time.time() - t0) / 3600 - 0.75)
        rc = correr(["entrenar_sft.py", "--modelo", a.modelo,
                     "--solo-tareas", "traducir_es_maya", "traducir_maya_es",
                     "--epocas", "1", "--max-len", "160", "--batch", "4", "--grad-accum", "4",
                     "--lr", "2e-4", "--lora-r", "16", "--save-pasos", "25",
                     "--max-horas", f"{horas_sft:.2f}", "--max-eval", "60"])
    evitar_suspension(False)
    h = (time.time() - t0) / 3600
    if rc:
        estado(f"ERROR en el SFT tras {h:.1f} h. Revisa el log. Si se interrumpió, vuelve a lanzarlo y se reanuda.")
    else:
        estado(f"TERMINADO en {h:.1f} h. Modelo registrado en modelos/ACTUAL. Pruébalo con: python probar_modelo.py")


if __name__ == "__main__":
    main()
