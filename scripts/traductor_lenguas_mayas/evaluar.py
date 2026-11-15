"""Mide la calidad de traducción (chrF++) del modelo sobre datos/lenguas_mayas/llm/sft_eval.jsonl.

chrF compara n-gramas de caracteres; es más justo que BLEU para lenguas aglutinantes como las mayas.
Lo usan entrenar_sft.py (reporte) y entrenar_hfrl.py (compuerta: un modelo nuevo solo entra a
producción si no empeora).

Uso
  python evaluar.py                       # evalúa el modelo registrado en modelos/ACTUAL
  python evaluar.py --modelo ruta --max 50
"""
from __future__ import annotations

import argparse
import json
import random
from collections import defaultdict

from comun import DATOS_LLM, cargar_modelo, generar, leer_jsonl, modelo_actual, prompt_traducir


def cargar_eval(max_n: int = 0, seed: int = 0):
    filas = list(leer_jsonl(DATOS_LLM / "sft_eval.jsonl"))
    if max_n and len(filas) > max_n:
        filas = random.Random(seed).sample(filas, max_n)
    return filas


def evaluar(model, tok, filas, verbose: bool = False) -> dict:
    from sacrebleu.metrics import CHRF
    chrf = CHRF(word_order=2)
    hip, ref = defaultdict(list), defaultdict(list)
    for f in filas:
        salida = generar(model, tok, prompt_traducir(f["texto"], f["origen"], f["destino"]),
                         n=1, max_new_tokens=48, temperatura=0)[0]
        salida = salida.splitlines()[0] if salida else ""
        clave = f"{f['origen']}->{f['destino']}"
        hip[clave].append(salida)
        ref[clave].append(f["referencia"])
        hip["total"].append(salida)
        ref["total"].append(f["referencia"])
        if verbose:
            print(f"[{clave}] {f['texto']!r} -> {salida!r}  (ref: {f['referencia']!r})")
    return {k: round(chrf.corpus_score(hip[k], [ref[k]]).score, 2) for k in sorted(hip)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--modelo", default=None)
    ap.add_argument("--max", type=int, default=200)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    model, tok = cargar_modelo(a.modelo or modelo_actual())
    print(json.dumps(evaluar(model, tok, cargar_eval(a.max), a.verbose), indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()
