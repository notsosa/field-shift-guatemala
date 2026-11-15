"""Almacén de interacciones y feedback humano (SQLite) para el aprendizaje continuo (HFRL).

Lo escribe servidor_api.py cada vez que la app pide una traducción/generación o el usuario califica,
elige o corrige una respuesta. Lo lee entrenar_hfrl.py para construir los datasets KTO/DPO.

Privacidad: `usuario_id` es un identificador seudónimo que genera la app (UUID del dispositivo);
no se guardan nombres, teléfonos ni ubicación. La base vive en modelos/ (fuera de git).

Tipos de feedback
  voto         👍/👎 sobre un candidato              valor = +1 / -1
  preferencia  el usuario elige el mejor de 2       preferido_id, rechazado_id
  correccion   el usuario reescribe la respuesta    candidato_id (el que corrigió), texto_corregido

Roles de usuario: 'usuario' (peso 0.5), 'hablante_verificado' y 'revisor' (peso 1.0).
Un revisor de la comunidad lingüística (ALMG, extensionistas) se marca con /v1/admin/usuarios/{id}/rol.
"""
from __future__ import annotations

import json
import sqlite3
import uuid
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

from comun import FEEDBACK_DB

PESOS = {"usuario": 0.5, "hablante_verificado": 1.0, "revisor": 1.0}

ESQUEMA = """
CREATE TABLE IF NOT EXISTS usuarios (
  id TEXT PRIMARY KEY, rol TEXT NOT NULL DEFAULT 'usuario', lengua TEXT, creado TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS interacciones (
  id TEXT PRIMARY KEY, ts TEXT NOT NULL, tarea TEXT NOT NULL, origen TEXT, destino TEXT,
  texto_entrada TEXT NOT NULL, prompt_json TEXT NOT NULL, modelo_version TEXT, usuario_id TEXT);
CREATE TABLE IF NOT EXISTS candidatos (
  id TEXT PRIMARY KEY, interaccion_id TEXT NOT NULL REFERENCES interacciones(id), idx INTEGER, texto TEXT NOT NULL);
CREATE TABLE IF NOT EXISTS feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT, ts TEXT NOT NULL, interaccion_id TEXT NOT NULL REFERENCES interacciones(id),
  usuario_id TEXT, tipo TEXT NOT NULL CHECK (tipo IN ('voto','preferencia','correccion')),
  candidato_id TEXT, valor INTEGER, preferido_id TEXT, rechazado_id TEXT, texto_corregido TEXT,
  comentario TEXT, usado_en TEXT);
CREATE INDEX IF NOT EXISTS ix_feedback_usado ON feedback(usado_en);
"""


def ahora() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def conectar(ruta: Path = FEEDBACK_DB) -> sqlite3.Connection:
    ruta.parent.mkdir(parents=True, exist_ok=True)
    con = sqlite3.connect(ruta, check_same_thread=False)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.executescript(ESQUEMA)
    return con


def asegurar_usuario(con, usuario_id: str | None, lengua: str | None = None):
    if usuario_id:
        con.execute("INSERT OR IGNORE INTO usuarios(id, lengua, creado) VALUES (?,?,?)", (usuario_id, lengua, ahora()))


def guardar_interaccion(con, tarea, origen, destino, texto, prompt, candidatos, version, usuario_id):
    iid = str(uuid.uuid4())
    with con:
        asegurar_usuario(con, usuario_id, destino)
        con.execute("INSERT INTO interacciones VALUES (?,?,?,?,?,?,?,?,?)",
                    (iid, ahora(), tarea, origen, destino, texto, json.dumps(prompt, ensure_ascii=False),
                     version, usuario_id))
        cands = []
        for i, t in enumerate(candidatos):
            cid = str(uuid.uuid4())
            con.execute("INSERT INTO candidatos VALUES (?,?,?,?)", (cid, iid, i, t))
            cands.append({"id": cid, "texto": t})
    return iid, cands


def guardar_feedback(con, **f) -> int:
    with con:
        asegurar_usuario(con, f.get("usuario_id"))
        cur = con.execute(
            "INSERT INTO feedback(ts, interaccion_id, usuario_id, tipo, candidato_id, valor, preferido_id, "
            "rechazado_id, texto_corregido, comentario) VALUES (?,?,?,?,?,?,?,?,?,?)",
            (ahora(), f["interaccion_id"], f.get("usuario_id"), f["tipo"], f.get("candidato_id"), f.get("valor"),
             f.get("preferido_id"), f.get("rechazado_id"), f.get("texto_corregido"), f.get("comentario")))
        return cur.lastrowid


def cambiar_rol(con, usuario_id: str, rol: str):
    if rol not in PESOS:
        raise ValueError(f"rol desconocido: {rol}")
    with con:
        asegurar_usuario(con, usuario_id)
        con.execute("UPDATE usuarios SET rol=? WHERE id=?", (rol, usuario_id))


# --------------------------------------------------------- feedback -> datasets
def _pendiente(con):
    return con.execute("""
        SELECT f.*, i.prompt_json, COALESCE(u.rol, 'usuario') AS rol
        FROM feedback f JOIN interacciones i ON i.id = f.interaccion_id
        LEFT JOIN usuarios u ON u.id = f.usuario_id
        WHERE f.usado_en IS NULL ORDER BY f.id""").fetchall()


def construir_ejemplos(con, umbral_voto: float = 1.0, correcciones_solo_verificadas: bool = True):
    """Devuelve (kto, dpo, ids_feedback).

    kto: [{"prompt", "completion", "label"}]   para KTOTrainer (señales no pareadas)
    dpo: [{"prompt", "chosen", "rejected"}]    para DPOTrainer (pares)

    - Votos: se suman por candidato con el peso del rol; entra como bueno si suma >= umbral_voto,
      como malo si suma <= -umbral_voto. Así un solo voto de un usuario no verificado (0.5) no basta.
    - Preferencias: par directo (preferido > rechazado) si el peso del usuario es >= 0.5.
    - Correcciones: el texto corregido > el candidato original. Por defecto solo de hablantes
      verificados o revisores, porque una corrección mala enseña errores con mucha fuerza.
    """
    texto_cand = {r["id"]: r["texto"] for r in con.execute("SELECT id, texto FROM candidatos")}
    filas = _pendiente(con)
    votos = defaultdict(float)
    ids_voto = defaultdict(list)
    prompts = {}
    kto, dpo, usados = [], [], []
    asistente = lambda t: [{"role": "assistant", "content": t}]

    for f in filas:
        prompt = json.loads(f["prompt_json"])
        peso = PESOS.get(f["rol"], 0.5)
        if f["tipo"] == "voto" and f["candidato_id"] in texto_cand:
            votos[f["candidato_id"]] += peso * (1 if (f["valor"] or 0) > 0 else -1)
            prompts[f["candidato_id"]] = prompt
            ids_voto[f["candidato_id"]].append(f["id"])
        elif f["tipo"] == "preferencia" and f["preferido_id"] in texto_cand and f["rechazado_id"] in texto_cand:
            a, b = texto_cand[f["preferido_id"]], texto_cand[f["rechazado_id"]]
            if a.strip() != b.strip():
                dpo.append({"prompt": prompt, "chosen": asistente(a), "rejected": asistente(b)})
                kto += [{"prompt": prompt, "completion": asistente(a), "label": True},
                        {"prompt": prompt, "completion": asistente(b), "label": False}]
            usados.append(f["id"])
        elif f["tipo"] == "correccion" and f["texto_corregido"]:
            if correcciones_solo_verificadas and peso < 1.0:
                continue                                    # queda pendiente hasta que un revisor la confirme
            corr = f["texto_corregido"].strip()
            kto.append({"prompt": prompt, "completion": asistente(corr), "label": True})
            orig = texto_cand.get(f["candidato_id"])
            if orig and orig.strip() != corr:
                dpo.append({"prompt": prompt, "chosen": asistente(corr), "rejected": asistente(orig)})
                kto.append({"prompt": prompt, "completion": asistente(orig), "label": False})
            usados.append(f["id"])

    for cid, s in votos.items():
        if abs(s) >= umbral_voto:          # los votos sin consenso quedan pendientes para la próxima ronda
            kto.append({"prompt": prompts[cid], "completion": asistente(texto_cand[cid]), "label": s > 0})
            usados += ids_voto[cid]
    return kto, dpo, usados


def marcar_usados(con, ids, version: str):
    with con:
        con.executemany("UPDATE feedback SET usado_en=? WHERE id=?", [(version, i) for i in ids])


def resumen(con) -> dict:
    q = lambda s: con.execute(s).fetchone()[0]
    return {
        "interacciones": q("SELECT COUNT(*) FROM interacciones"),
        "feedback_total": q("SELECT COUNT(*) FROM feedback"),
        "feedback_pendiente": q("SELECT COUNT(*) FROM feedback WHERE usado_en IS NULL"),
        "por_tipo": dict(con.execute("SELECT tipo, COUNT(*) FROM feedback GROUP BY tipo").fetchall()),
        "usuarios_verificados": q("SELECT COUNT(*) FROM usuarios WHERE rol != 'usuario'"),
    }
