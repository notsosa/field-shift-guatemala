"""Descarga diccionarios web de lenguas mayas y los guarda como JSONL crudo.

Fuentes:
  - Webonary Kaqchikel (API pública cloud-api.webonary.org)
  - Talking Dictionaries de Swarthmore / Living Tongues (q'eqchi', mam, k'iche', kaqchikel)
  - Diccionario Mam-Español de Comitancillo (Ikeda y Pérez Morales, 2001)

Uso:
  python -I scripts/web_scraping/descargar_diccionarios_web.py --out "C:/NASA Space Apps Challenge/Lenguas Mayas/pretraining/raw/web"

Usa urllib (certificados del sistema) en lugar de requests/certifi.
"""
import argparse
import html
import json
import re
import ssl
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) maya-corpus-research/1.0"
CTX = ssl.create_default_context()


def get(url, encoding="utf-8", retries=3):
    for i in range(retries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=40, context=CTX) as r:
                return r.read().decode(encoding, errors="replace")
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            time.sleep(2 * (i + 1))
        except Exception:
            time.sleep(2 * (i + 1))
    return None


def write_jsonl(path, rows):
    with open(path, "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    print(f"  -> {len(rows)} entradas en {path.name}")


# ---------------------------------------------------------------- Webonary
WEBONARY_HEADS = (
    "a ä b b' ch ch' e ë i ï j k k' l m n o ö p q q' r s t t' tz tz' u ü w x y z "
    "c d f g h v ' ’"
).split()


def _vals(node, lang=None):
    """Valores de una lista [{lang, value}] (filtrando por idioma si se pide)."""
    out = []
    for it in node or []:
        if isinstance(it, dict) and "value" in it and (lang is None or it.get("lang") == lang):
            v = re.sub(r"<[^>]+>", "", str(it["value"])).strip()
            if v:
                out.append(html.unescape(v))
    return out


def webonary(dict_id, vern_lang, out_dir):
    print(f"Webonary: {dict_id}")
    seen, rows = set(), []
    for head in WEBONARY_HEADS:
        page = 1
        while True:
            q = urllib.parse.urlencode({"text": head, "lang": vern_lang,
                                        "pageNumber": page, "pageLimit": 100})
            txt = get(f"https://cloud-api.webonary.org/v1/browse/entry/{dict_id}?{q}")
            if not txt:
                break
            try:
                data = json.loads(txt)
            except json.JSONDecodeError:
                break
            if not isinstance(data, list) or not data:
                break
            for e in data:
                if e.get("_id") in seen:
                    continue
                seen.add(e.get("_id"))
                senses = []
                for s in e.get("senses", []):
                    exs = []
                    for ex in s.get("examplescontents", []):
                        exs.append({
                            "maya": " ".join(_vals(ex.get("example"))),
                            "es": " ".join(" ".join(_vals(t.get("translation")))
                                           for t in ex.get("translationcontents", [])),
                        })
                    senses.append({
                        "def": "; ".join(dict.fromkeys(_vals(s.get("definitionorgloss"), "es"))),
                        "examples": [x for x in exs if x["maya"]],
                    })
                msa = e.get("morphosyntaxanalysis") or {}
                rows.append({
                    "headword": " ".join(_vals(e.get("mainheadword"))),
                    "pos": " ".join(_vals(msa.get("graminfoname"))),
                    "summary": " ".join(_vals(e.get("summarydefinition"))),
                    "senses": senses,
                })
            if len(data) < 100:
                break
            page += 1
            time.sleep(0.3)
    write_jsonl(out_dir / f"webonary_{dict_id}.jsonl", rows)


# ------------------------------------------------------ Talking Dictionaries
TD_ENTRY = re.compile(r'<div class="entry[^"]*" id="entry(\d+)">(.*?)<div style="clear:both;"></div>', re.S)


def _clean(s):
    return html.unescape(re.sub(r"<[^>]+>", " ", s)).replace("\xa0", " ").strip()


def _span(cls, block):
    return [" ".join(_clean(m).split()) for m in re.findall(rf'<span class="{cls}">(.*?)</span>', block, re.S)]


def parse_td(page):
    out = {}
    for eid, block in TD_ENTRY.findall(page or ""):
        hw = re.search(r"<h3[^>]*>(.*?)</h3>", block, re.S)
        out[int(eid)] = {
            "id": int(eid),
            "headword": " ".join(_clean(hw.group(1)).split()) if hw else "",
            "ipa": _span("ipa", block),
            "pos": _span("pos", block),
            "gloss": _span("gloss", block),
            "es_gloss": _span("es_gloss", block),
            "en_gloss": _span("en_gloss", block),
            "speaker": [s.replace("Hablante:", "").replace("Speaker:", "").strip()
                        for s in _span("authority", block)],
        }
    return out


def talking_dictionary(slug, out_dir, max_misses=200):
    print(f"Talking Dictionary: {slug}")
    base = f"https://talkingdictionary.swarthmore.edu/{slug}/"
    front = get(base + "?lang=es") or ""
    (out_dir / f"td_{slug}_portada.html").write_text(front, encoding="utf-8")
    entries = parse_td(front)
    hint = max(entries) if entries else 500

    def fetch(i):
        return parse_td(get(f"{base}?entry={i}&lang=es"))

    i, misses, step = 1, 0, 16
    with ThreadPoolExecutor(4) as pool:
        while misses < max_misses or i <= hint:
            ids = [k for k in range(i, i + step) if k not in entries]
            for res in pool.map(fetch, ids):
                if res:
                    entries.update(res)
            got = any(k in entries for k in range(i, i + step))
            misses = 0 if got else misses + step
            i += step
            time.sleep(0.2)
    rows = [entries[k] for k in sorted(entries)]
    write_jsonl(out_dir / f"td_{slug}.jsonl", rows)


# ------------------------------------------------------ Mam de Comitancillo
def mam_comitancillo(out_dir):
    print("Mam-Español Comitancillo")
    page = get("https://navymule9.sakura.ne.jp/Mam_Esp_Dic_Comitan.html", encoding="cp1252") or ""
    rows = []
    for pre in re.findall(r"<pre>(.*?)</pre>", page, re.S | re.I):
        for line in re.split(r"<br\s*/?>", pre, flags=re.I):
            line = _clean(line)
            if not line:
                continue
            parts = re.split(r"\t+| {2,}", line, maxsplit=1)
            if len(parts) == 2 and parts[0].strip() and parts[1].strip():
                rows.append({"headword": parts[0].strip(), "gloss": parts[1].strip()})
    write_jsonl(out_dir / "mam_comitancillo.jsonl", rows)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", required=True)
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    mam_comitancillo(out)
    webonary("kaqchikel", "qaa", out)
    for slug in ["qeqchi", "mam", "kiche", "kaqchikel"]:
        talking_dictionary(slug, out)
