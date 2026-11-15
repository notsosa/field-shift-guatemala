"""Construye el dataset de instrucciones (SFT) para el LLM a partir del corpus y los diccionarios.

Entradas (ya en el repo)
  datos/lenguas_mayas/pretraining/shards/<lengua>/*.jsonl   prosa y diccionarios en PDF
  datos/lenguas_mayas/pretraining/raw_web/*.jsonl          diccionarios web (pares palabra-glosa)
  diccionarios/*.md                                        tablas curadas (confianza Fuente/Contexto/Derivada)

Salida
  datos/lenguas_mayas/pretraining/llm/sft_train.jsonl   {"prompt": [...], "completion": [...], "tarea", "lang"}
  datos/lenguas_mayas/pretraining/llm/sft_eval.jsonl    pares de traducción reservados para medir chrF
  datos/lenguas_mayas/pretraining/llm/estadisticas_sft.json

Tareas generadas
  traducir_es_maya / traducir_maya_es   palabras y frases de los diccionarios (ambas direcciones)
  continuar_maya                        continuar un texto en lengua maya (prosa del corpus)
  parrafo_maya                          escribir un párrafo libre en una lengua maya
  explicar_es                           explicar en español qué significa una palabra maya
  identificar_lengua                    decir en qué lengua está un fragmento

Uso
  python scripts/traductor_lenguas_mayas/preparar_datos_llm.py
"""
from __future__ import annotations

import argparse
import hashlib
import json
import random
import re
from collections import Counter, defaultdict

from comun import (CORPUS, DATOS_LLM, LENGUAS, MAYAS, RAIZ, SISTEMA, asistente, escribir_jsonl,
                   leer_jsonl, prompt_traducir)
from construir_corpus_pretraining import PDFS, norm

WEB = {  # archivo -> lengua
    "webonary_kaqchikel.jsonl": "kaqchikel", "td_qeqchi.jsonl": "qeqchi", "td_mam.jsonl": "mam",
    "td_kiche.jsonl": "kiche", "td_kaqchikel.jsonl": "kaqchikel", "mam_comitancillo.jsonl": "mam",
}
TABLAS_MD = {"kiche.md": "kiche", "kaqchikel.md": "kaqchikel", "qeqchi.md": "qeqchi", "mam.md": "mam"}
CONFIANZA_OK = {"fuente", "contexto", "derivada"}
DICC_PDF = {f for f, _, tipo, *_ in PDFS if tipo == "dicc"}


def es_prosa(src: str) -> bool:
    """Todo lo que no es diccionario: libros, leyes, Biblias (PDF, eBible), páginas web (FineWeb-2, MADLAD)."""
    return bool(src) and not src.endswith(".jsonl") and src not in DICC_PDF

P_EXPLICAR = [
    "¿Qué significa la palabra «{w}» en {L}? Responde en español.",
    "Explica en español el significado de «{w}» ({L}).",
]
R_EXPLICAR = ["En {L}, «{w}» significa «{d}».", "«{w}» es una palabra del {L} que quiere decir «{d}»."]


def u(lang, txt):
    return [{"role": "system", "content": SISTEMA}, {"role": "user", "content": txt}]


def limpiar_palabra(w: str) -> str:
    w = norm(w)
    if len(w) > 1 and w[0].isupper() and w[1:].islower():      # "Wi'aj" -> "wi'aj" (no nombres propios largos)
        w = w[0].lower() + w[1:]
    return w


def limpiar_glosa(g: str) -> str:
    g = norm(g)
    g = re.sub(r"\s*\((véase|ver|cf\.)[^)]*\)", "", g, flags=re.I)
    return g.strip(" .;:,")


def en_eval(lang, w, frac):
    h = int(hashlib.md5(f"{lang}|{w}".encode()).hexdigest()[:8], 16)
    return h / 0xFFFFFFFF < frac


# ------------------------------------------------------------------ pares
def pares_web():
    """(lang, maya, español, fuente) desde los diccionarios web."""
    for fname, lang in WEB.items():
        ruta = CORPUS / "raw_web" / fname
        if not ruta.exists():
            continue
        for e in leer_jsonl(ruta):
            w = limpiar_palabra(e.get("headword", ""))
            if not w or w.startswith("-") or w.endswith("-"):
                continue                                             # afijos: no son traducibles solos
            glosas = []
            g = e.get("gloss")
            glosas += [g] if isinstance(g, str) else list(g or [])
            glosas += list(e.get("es_gloss") or [])
            for s in e.get("senses", []):
                if s.get("def"):
                    glosas.append(s["def"])
                for ex in s.get("examples", []):
                    m, es = norm(ex.get("maya", "")), norm(ex.get("es", ""))
                    if m and es:
                        yield lang, m, es, fname + ":ejemplo"
            glosas = [limpiar_glosa(x) for x in glosas]
            glosas = [x for x in dict.fromkeys(glosas) if x and len(x) <= 80]
            if glosas:
                yield lang, w, "; ".join(glosas[:3]), fname


def pares_md():
    """Pares verificados de diccionarios/*.md (se omite 'Por verificar' y 'Cognado')."""
    for fname, lang in TABLAS_MD.items():
        ruta = RAIZ / "diccionarios" / fname
        if not ruta.exists():
            continue
        cab = None
        for linea in ruta.read_text(encoding="utf-8").splitlines():
            if not linea.startswith("|"):
                cab = None
                continue
            celdas = [c.strip() for c in linea.strip().strip("|").split("|")]
            if cab is None:
                cab = [c.lower() for c in celdas]
                continue
            if set(linea) <= set("|-: "):
                continue
            if len(cab) < 2 or cab[1] != "español" or LENGUAS.get(lang, "").lower() != cab[0].replace("’", "'"):
                continue
            if "confianza" in cab:
                conf = celdas[cab.index("confianza")].lower() if len(celdas) > cab.index("confianza") else ""
                if conf not in CONFIANZA_OK:
                    continue
            maya, es = re.sub(r"[*_`]", "", celdas[0]), re.sub(r"[*_`]", "", celdas[1])
            es = limpiar_glosa(es)
            for variante in re.split(r"\s*[·/]\s*", maya):
                variante = limpiar_palabra(variante)
                if variante and es:
                    yield lang, variante, es, "diccionarios/" + fname


# ------------------------------------------------------------------ prosa
def fragmentos_prosa(lang, rng, max_chars=700):
    docs = []
    for ruta in sorted((CORPUS / "shards" / lang).glob("*.jsonl")):
        docs += [d["text"] for d in leer_jsonl(ruta) if es_prosa(d.get("source", ""))]
    rng.shuffle(docs)
    for d in docs:
        ps = [p.strip() for p in d.split("\n\n") if len(p.strip()) > 80]
        for p in ps:
            yield p[:max_chars].rsplit(" ", 1)[0] if len(p) > max_chars else p


def partir(p):
    """Divide un párrafo en (inicio, continuación) por una frase."""
    frases = re.split(r"(?<=[.!?])\s+", p)
    if len(frases) >= 3:
        k = max(1, len(frases) // 3)
        return " ".join(frases[:k]), " ".join(frases[k:])
    pal = p.split()
    k = max(5, len(pal) // 3)
    return " ".join(pal[:k]), " ".join(pal[k:])


# ------------------------------------------------------------------ main
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frac-eval", type=float, default=0.05)
    ap.add_argument("--max-eval-por-lengua", type=int, default=150)
    ap.add_argument("--continuar-por-lengua", type=int, default=2500)
    ap.add_argument("--parrafo-por-lengua", type=int, default=400)
    ap.add_argument("--identificar-por-lengua", type=int, default=300)
    ap.add_argument("--repetir-md", type=int, default=3, help="sobremuestreo de los pares verificados")
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    rng = random.Random(a.seed)

    train, evalset, stats = [], [], Counter()
    vistos = set()
    n_eval = Counter()

    def agregar_par(lang, maya, es, fuente, peso=1):
        k = (lang, maya.lower(), es.lower())
        if k in vistos:
            return
        vistos.add(k)
        L = LENGUAS[lang]
        if not fuente.startswith("diccionarios/"):            # los pares verificados siempre van a train
            if en_eval(lang, maya.lower(), a.frac_eval) and n_eval[lang] < a.max_eval_por_lengua:
                n_eval[lang] += 1
                evalset.append({"origen": "es", "destino": lang, "texto": es, "referencia": maya, "fuente": fuente})
                evalset.append({"origen": lang, "destino": "es", "texto": maya, "referencia": es, "fuente": fuente})
                return
        for _ in range(peso):
            train.append({"prompt": prompt_traducir(es, "es", lang), "completion": asistente(maya),
                          "tarea": "traducir_es_maya", "lang": lang})
            train.append({"prompt": prompt_traducir(maya, lang, "es"), "completion": asistente(es),
                          "tarea": "traducir_maya_es", "lang": lang})
            stats[f"{lang}:pares"] += 1
        if fuente.endswith(".jsonl") and rng.random() < 0.3:
            train.append({"prompt": u(lang, rng.choice(P_EXPLICAR).format(w=maya, L=L)),
                          "completion": asistente(rng.choice(R_EXPLICAR).format(w=maya, L=L, d=es)),
                          "tarea": "explicar_es", "lang": lang})

    for lang, maya, es, fuente in pares_md():
        agregar_par(lang, maya, es, fuente, peso=a.repetir_md)
    for lang, maya, es, fuente in pares_web():
        agregar_par(lang, maya, es, fuente)

    for lang in MAYAS:
        L = LENGUAS[lang]
        frags = list(fragmentos_prosa(lang, rng))
        # reparto proporcional: las lenguas con poca prosa (k'iche') también reciben las tres tareas
        n_id = min(a.identificar_por_lengua, len(frags) // 10)
        n_par = min(a.parrafo_por_lengua, len(frags) // 7)
        n_cont = min(a.continuar_por_lengua, len(frags) - n_id - n_par)
        for p in frags[:n_id]:
            trozo = " ".join(p.split()[:25])
            train.append({"prompt": u(lang, f"¿En qué idioma está este texto?\n{trozo}"),
                          "completion": asistente(f"Está en {L}."), "tarea": "identificar_lengua", "lang": lang})
        for p in frags[n_id:n_id + n_par]:
            train.append({"prompt": u(lang, f"Escribe un párrafo en {L}."), "completion": asistente(p),
                          "tarea": "parrafo_maya", "lang": lang})
        for p in frags[n_id + n_par:n_id + n_par + n_cont]:
            ini, cont = partir(p)
            if len(cont) >= 40:
                train.append({"prompt": u(lang, f"Continúa este texto en {L}:\n{ini}"), "completion": asistente(cont),
                              "tarea": "continuar_maya", "lang": lang})

    rng.shuffle(train)
    n_tr = escribir_jsonl(DATOS_LLM / "sft_train.jsonl", train)
    n_ev = escribir_jsonl(DATOS_LLM / "sft_eval.jsonl", evalset)
    por_tarea = Counter(f"{r['lang']}:{r['tarea']}" for r in train)
    resumen = {"train": n_tr, "eval": n_ev, "por_tarea": dict(sorted(por_tarea.items())),
               "eval_por_lengua": dict(n_eval)}
    (DATOS_LLM / "estadisticas_sft.json").write_text(json.dumps(resumen, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(resumen, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
