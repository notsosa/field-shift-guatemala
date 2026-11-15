"""Consola interactiva para probar el LLM: escribes texto y ves la traducción o el texto generado.

Uso
  python probar_modelo.py                      # usa el modelo de modelos/ACTUAL (o el base si aún no entrenas)
  python probar_modelo.py --modelo modelos/sft/final --n 2

Dentro de la consola
  Escribe cualquier texto y presiona Enter.
  /traducir es kiche     modo traducción (origen destino). Ej.: /traducir mam es
  /generar qeqchi        modo generación en esa lengua (también: /generar es)
  /n 2                   cuántas opciones mostrar (1-3)
  /temp 0.7              temperatura (0 = siempre la misma respuesta)
  /max 200               máximo de tokens nuevos
  /ayuda                 muestra esta ayuda
  /salir                 termina

Lenguas: es (español), kiche (k'iche'), kaqchikel, qeqchi (q'eqchi'), mam.
"""
from __future__ import annotations

import argparse
import sys
import time
import unicodedata

from comun import LENGUAS, MODELO_BASE, REGISTRO, cargar_modelo, generar, modelo_actual, prompt_generar, prompt_traducir

ALIAS = {
    "es": "es", "espanol": "es", "castellano": "es", "spanish": "es",
    "kiche": "kiche", "quiche": "kiche", "quc": "kiche",
    "kaqchikel": "kaqchikel", "cakchiquel": "kaqchikel", "kaq": "kaqchikel", "cak": "kaqchikel",
    "qeqchi": "qeqchi", "kekchi": "qeqchi", "kek": "qeqchi",
    "mam": "mam",
}


def lengua(txt: str) -> str | None:
    t = unicodedata.normalize("NFD", txt.lower())
    t = "".join(c for c in t if c.isalpha())          # quita tildes, apóstrofos y espacios
    return ALIAS.get(t)


class Sesion:
    def __init__(self, a):
        self.modo, self.origen, self.destino, self.lengua = "traducir", "es", "kiche", "kiche"
        self.n, self.temp, self.max = a.n, a.temperatura, a.max_tokens

    def etiqueta(self):
        if self.modo == "traducir":
            return f"traducir {LENGUAS[self.origen]} → {LENGUAS[self.destino]}"
        return f"generar en {LENGUAS[self.lengua]}"

    def comando(self, linea: str) -> bool:
        """Procesa /comandos. Devuelve False si hay que salir."""
        partes = linea[1:].split()
        cmd, args = (partes[0].lower(), partes[1:]) if partes else ("", [])
        if cmd in ("salir", "exit", "quit", "q"):
            return False
        if cmd in ("ayuda", "help", "h", "?"):
            print(__doc__.split("Dentro de la consola")[1])
        elif cmd == "traducir" and len(args) == 2:
            o, d = lengua(args[0]), lengua(args[1])
            if not (o and d) or o == d or "es" not in (o, d):
                print("  Usa español y una lengua maya, p. ej. /traducir es mam  o  /traducir qeqchi es")
                return True
            else:
                self.modo, self.origen, self.destino = "traducir", o, d
        elif cmd == "generar" and len(args) == 1 and lengua(args[0]):
            self.modo, self.lengua = "generar", lengua(args[0])
        elif cmd == "n" and args and args[0].isdigit():
            self.n = max(1, min(3, int(args[0])))
        elif cmd == "temp" and args:
            try:
                self.temp = max(0.0, min(2.0, float(args[0])))
            except ValueError:
                print("  /temp necesita un número, p. ej. /temp 0.7")
                return True
        elif cmd == "max" and args and args[0].isdigit():
            self.max = max(8, min(1024, int(args[0])))
        else:
            print("  Comando no reconocido. Escribe /ayuda")
            return True
        print(f"  ✓ {self.etiqueta()} · opciones={self.n} · temperatura={self.temp} · max={self.max}")
        return True


def main():
    ap = argparse.ArgumentParser(description="Consola interactiva del LLM de lenguas mayas")
    ap.add_argument("--modelo", default=None, help="ruta o nombre del modelo (por defecto modelos/ACTUAL)")
    ap.add_argument("--n", type=int, default=1)
    ap.add_argument("--temperatura", type=float, default=0.3)
    ap.add_argument("--max-tokens", type=int, default=200)
    a = ap.parse_args()

    for flujo in (sys.stdout, sys.stdin):            # tildes y saltillos en la consola de Windows
        if hasattr(flujo, "reconfigure"):
            flujo.reconfigure(encoding="utf-8")

    ruta = a.modelo or modelo_actual(defecto=MODELO_BASE)
    if not a.modelo and not REGISTRO.exists():
        print(f"⚠ Aún no hay modelo entrenado (falta {REGISTRO}). Uso el modelo base {MODELO_BASE},\n"
              "  que NO conoce las lenguas mayas: sirve solo para probar que todo funciona.\n")
    print(f"Cargando {ruta} ...")
    model, tok = cargar_modelo(ruta)
    s = Sesion(a)
    print(f"Listo ({model.device}). Escribe texto y presiona Enter. /ayuda para ver los comandos.\n")

    while True:
        try:
            linea = input(f"[{s.etiqueta()}] > ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not linea:
            continue
        if linea.startswith("/"):
            if not s.comando(linea):
                break
            continue
        msgs = (prompt_traducir(linea, s.origen, s.destino) if s.modo == "traducir"
                else prompt_generar(linea, s.lengua))
        t0 = time.time()
        salidas = generar(model, tok, msgs, n=s.n, max_new_tokens=s.max, temperatura=s.temp)
        for i, txt in enumerate(salidas, 1):
            print(f"  {f'[{i}] ' if s.n > 1 else ''}{txt}")
        print(f"  ({time.time() - t0:.1f} s)\n")
    print("¡Hasta luego! · Toda salida debe revisarla un hablante antes de usarse en la app.")


if __name__ == "__main__":
    main()
