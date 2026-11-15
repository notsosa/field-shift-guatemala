"""Genera ESTADISTICAS.md con cifras de los datos de entrenamiento del LLM.

Escribe en datos/lenguas_mayas/pretraining/ESTADISTICAS.md (repo privado, junto a los datos).
Cuenta tokens con el tokenizador del modelo base, que es lo que de verdad determina el tiempo de
entrenamiento; las lenguas mayas se parten en más tokens por palabra que el español.

Uso
  python estadisticas_datos.py
  python estadisticas_datos.py --modelo Qwen/Qwen2.5-1.5B-Instruct
"""
from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from datetime import date

from comun import CORPUS, DATOS_LLM, LENGUAS, MAYAS, MODELO_BASE, leer_jsonl
from construir_corpus_pretraining import PDFS

TIPO_PDF = {f: t.split(":")[0] for f, _, t, *_ in PDFS}
TOK_S_T4, TOK_S_CPU = 1500, 19     # tokens/s: T4 estimado; CPU medido en esta laptop (Qwen2.5-0.5B + LoRA)


def tipo_y_fuente(src: str):
    """(tipo de texto, nombre de fuente agrupado) de un documento del corpus."""
    if "|" in src:                                   # fineweb2|url, madlad|url
        return "webcorpus", src.split("|")[0]
    if src.endswith(".jsonl"):
        return "web", src
    if src.endswith("_usfm.zip"):
        return "biblia", "eBible " + src.replace("_usfm.zip", "")
    if "/" in src:                                    # p. ej. biblia_catolica/<archivo>.pdf
        return "biblia" if "biblia" in src else "texto", src.split("/")[0]
    return TIPO_PDF.get(src, "texto"), src


def horas(tokens: int, tok_s: float) -> str:
    h = tokens / tok_s / 3600
    return f"≈ {h * 60:.0f} min" if h < 1 else f"≈ {h:.1f} h" if h < 48 else f"≈ {h / 24:.0f} días"
NOMBRE_TIPO = {"texto": "Prosa (libros, leyes, revistas)", "biblia": "Biblia", "dicc": "Diccionarios en PDF",
               "webcorpus": "Páginas web (FineWeb-2, MADLAD-400)",
               "web": "Diccionarios web"}


def fmt(n) -> str:
    return f"{n:,}".replace(",", " ")


def tabla(cab, filas) -> list[str]:
    out = ["| " + " | ".join(cab) + " |", "|" + "|".join("---:" if i else "---" for i in range(len(cab))) + "|"]
    out += ["| " + " | ".join(str(c) for c in f) + " |" for f in filas]
    return out + [""]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--modelo", default=MODELO_BASE, help="tokenizador con el que se cuentan los tokens")
    a = ap.parse_args()
    from transformers import AutoTokenizer
    tok = AutoTokenizer.from_pretrained(a.modelo)
    ntok = lambda textos: sum(len(x) for x in tok(textos, add_special_tokens=False)["input_ids"]) if textos else 0

    # ---------------------------------------------------------------- corpus
    corpus, por_tipo, por_fuente = {}, defaultdict(Counter), defaultdict(Counter)
    for lang in MAYAS:
        docs = [d for r in sorted((CORPUS / "shards" / lang).glob("*.jsonl")) for d in leer_jsonl(r)]
        textos = [d["text"] for d in docs]
        palabras = sum(len(t.split()) for t in textos)
        tokens = ntok(textos)
        corpus[lang] = dict(docs=len(docs), chars=sum(map(len, textos)), palabras=palabras, tokens=tokens)
        for d in docs:
            src = d["source"]
            tipo, fuente = tipo_y_fuente(src)
            por_tipo[lang][tipo] += len(d["text"])
            por_fuente[lang][fuente] += len(d["text"])
    tot = {k: sum(c[k] for c in corpus.values()) for k in ("docs", "chars", "palabras", "tokens")}

    # ---------------------------------------------------------------- SFT
    sft = list(leer_jsonl(DATOS_LLM / "sft_train.jsonl"))
    ev = list(leer_jsonl(DATOS_LLM / "sft_eval.jsonl"))
    tareas = sorted({r["tarea"] for r in sft})
    cuenta = Counter((r["lang"], r["tarea"]) for r in sft)
    tok_resp = defaultdict(int)
    for r in sft:
        tok_resp[r["tarea"]] += len(r["completion"][0]["content"])
    # tokens totales por ejemplo (prompt con plantilla de chat + respuesta), sobre una muestra
    muestra = sft[:: max(1, len(sft) // 2000)]
    largos = [len(tok(tok.apply_chat_template(r["prompt"] + r["completion"], tokenize=False),
                      add_special_tokens=False)["input_ids"]) for r in muestra]
    largo_medio = sum(largos) / len(largos)
    tok_sft = int(largo_medio * len(sft))

    # ---------------------------------------------------------------- markdown
    L = ["# Estadísticas de los datos de entrenamiento del LLM", "",
         f"Generado el {date.today().isoformat()} con `scripts/traductor_lenguas_mayas/estadisticas_datos.py`. "
         f"Los tokens se cuentan con el tokenizador de `{a.modelo}`.", "",
         "## Resumen", "",
         f"- **Corpus de pre-entrenamiento:** {fmt(tot['docs'])} documentos, {fmt(tot['palabras'])} palabras, "
         f"**{fmt(tot['tokens'])} tokens** en 4 lenguas.",
         f"- **Dataset de instrucciones (SFT):** {fmt(len(sft))} ejemplos, unos **{fmt(tok_sft)} tokens** "
         f"(promedio {largo_medio:.0f} tokens por ejemplo, contando el prompt).",
         f"- **Evaluación:** {fmt(len(ev))} pares de traducción reservados (no se usan para entrenar).", "",
         "## 1. Corpus de pre-entrenamiento por lengua", ""]
    filas = []
    for lang in MAYAS:
        c = corpus[lang]
        filas.append([LENGUAS[lang], fmt(c["docs"]), fmt(c["chars"]), fmt(c["palabras"]), fmt(c["tokens"]),
                      f"{100 * c['tokens'] / tot['tokens']:.1f} %", f"{c['tokens'] / max(1, c['palabras']):.2f}"])
    filas.append(["**Total**", fmt(tot["docs"]), fmt(tot["chars"]), fmt(tot["palabras"]), fmt(tot["tokens"]), "100 %",
                  f"{tot['tokens'] / tot['palabras']:.2f}"])
    L += tabla(["Lengua", "Documentos", "Caracteres", "Palabras", "Tokens", "% tokens", "Tokens/palabra"], filas)
    L += ["*Tokens/palabra* indica cuánto le cuesta al tokenizador cada lengua: el español anda por 1.3–1.5. "
          "Un valor alto significa que el modelo ve las palabras mayas partidas en muchos pedazos.", "",
          "Para equilibrar las lenguas, `entrenar_pretraining.py` muestrea con temperatura (α = 0.5): "
          "el k'iche' se repite más y el q'eqchi' se recorta.", "",
          "## 2. Tipo de texto por lengua (caracteres)", ""]
    tipos = ["texto", "biblia", "webcorpus", "dicc", "web"]
    filas = []
    for lang in MAYAS:
        t = sum(por_tipo[lang].values())
        filas.append([LENGUAS[lang]] + [f"{fmt(por_tipo[lang][k])} ({100 * por_tipo[lang][k] / t:.0f} %)" for k in tipos])
    L += tabla(["Lengua"] + [NOMBRE_TIPO[k] for k in tipos], filas)
    L += ["## 3. Fuentes principales por lengua", ""]
    for lang in MAYAS:
        L += [f"**{LENGUAS[lang]}**", ""]
        t = sum(por_fuente[lang].values())
        L += tabla(["Fuente", "Caracteres", "%"],
                   [[f"`{s}`", fmt(n), f"{100 * n / t:.1f} %"] for s, n in por_fuente[lang].most_common(6)])
    L += ["Autorías y licencias de cada fuente: [final/CREDITOS.md](final/CREDITOS.md).", "",
          "## 4. Dataset de instrucciones (SFT) por tarea y lengua", ""]
    filas = [[t] + [fmt(cuenta[(l, t)]) for l in MAYAS] + [fmt(sum(cuenta[(l, t)] for l in MAYAS))] for t in tareas]
    filas.append(["**Total**"] + [fmt(sum(cuenta[(l, t)] for t in tareas)) for l in MAYAS] + [fmt(len(sft))])
    L += tabla(["Tarea"] + [LENGUAS[l] for l in MAYAS] + ["Total"], filas)
    L += ["- `traducir_*`: pares de los diccionarios web y de `diccionarios/*.md` (los verificados se repiten ×3). "
          "Casi todos son **palabras sueltas**, no oraciones.",
          "- `continuar_maya` / `parrafo_maya`: prosa del corpus (libros, leyes, Biblias).",
          "- `explicar_es`: respuesta en español sobre el significado de una palabra maya.",
          "- `identificar_lengua`: reconocer en qué lengua está un fragmento.", "",
          "## 5. Evaluación (pares reservados)", ""]
    dirs = Counter(f"{LENGUAS[r['origen']]} → {LENGUAS[r['destino']]}" for r in ev)
    L += tabla(["Dirección", "Pares"], [[k, v] for k, v in sorted(dirs.items())])
    L += ["Q'eqchi' y k'iche' tienen pocos pares de evaluación porque sus diccionarios web son pequeños; "
          "sus cifras de chrF van a variar mucho de una evaluación a otra.", "",
          "## 6. ¿Cuánto tarda en entrenarse?", "",
          "Estimación aproximada para una época con `Qwen2.5-0.5B-Instruct` y LoRA:", ""]
    tok_trad = int(largo_medio * sum(v for (l, t), v in cuenta.items() if t.startswith("traducir")))
    L += tabla(["Etapa", "Tokens", "GPU T4 (Colab)", "CPU de 8 núcleos"],
               [["1. Pre-entrenamiento continuo", fmt(tot["tokens"]), horas(tot["tokens"], TOK_S_T4), horas(tot["tokens"], TOK_S_CPU)],
                ["2. SFT completo", fmt(tok_sft), horas(tok_sft, TOK_S_T4), horas(tok_sft, TOK_S_CPU)],
                ["2. SFT solo traducción (`--solo-tareas`)", fmt(tok_trad), horas(tok_trad, TOK_S_T4), horas(tok_trad, TOK_S_CPU)]])
    L += [f"Supuestos: {TOK_S_T4} tokens/s en una T4 (estimado) y {TOK_S_CPU} tokens/s en CPU (medido en la laptop del equipo). "
          "El pre-entrenamiento usa muestreo con temperatura, así que el número real de tokens vistos por época es menor.", ""]
    (CORPUS / "ESTADISTICAS.md").write_text("\n".join(L), encoding="utf-8")
    print(f"Escrito {CORPUS / 'ESTADISTICAS.md'}")
    print(json.dumps({"corpus_tokens": tot["tokens"], "sft_ejemplos": len(sft), "sft_tokens": tok_sft}, indent=2))


if __name__ == "__main__":
    main()
