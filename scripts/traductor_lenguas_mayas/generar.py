"""Prueba el modelo desde la terminal: traducir o generar texto.

  python generar.py traducir --destino kiche "Mañana va a llover, no riegue la milpa."
  python generar.py traducir --origen qeqchi --destino es "ixim"
  python generar.py generar --lengua mam "un consejo para sembrar maíz" --n 2
"""
from __future__ import annotations

import argparse

from comun import LENGUAS, cargar_modelo, generar, modelo_actual, prompt_generar, prompt_traducir


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("tarea", choices=["traducir", "generar"])
    ap.add_argument("texto")
    ap.add_argument("--origen", default="es", choices=list(LENGUAS))
    ap.add_argument("--destino", default="kiche", choices=list(LENGUAS))
    ap.add_argument("--lengua", default="kiche", choices=list(LENGUAS))
    ap.add_argument("--modelo", default=None)
    ap.add_argument("--n", type=int, default=1)
    ap.add_argument("--temperatura", type=float, default=0.7)
    a = ap.parse_args()

    model, tok = cargar_modelo(a.modelo or modelo_actual())
    msgs = (prompt_traducir(a.texto, a.origen, a.destino) if a.tarea == "traducir"
            else prompt_generar(a.texto, a.lengua))
    for i, s in enumerate(generar(model, tok, msgs, n=a.n, temperatura=a.temperatura), 1):
        print(f"[{i}] {s}")


if __name__ == "__main__":
    main()
