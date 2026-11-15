"""API HTTP para la app del teléfono: traducir, generar y recibir feedback humano.

Cada respuesta devuelve 2 candidatos (muestreo con temperatura) para que el usuario pueda elegir
el mejor: esa elección es la señal más barata y útil para el aprendizaje continuo (pares DPO).

Endpoints
  GET  /v1/salud
  POST /v1/traducir      {"texto", "origen": "es", "destino": "kiche", "usuario_id", "n_candidatos": 2}
  POST /v1/generar       {"instruccion", "lengua": "mam", "usuario_id", "n_candidatos": 2}
  POST /v1/feedback      {"interaccion_id", "usuario_id", "tipo": "voto|preferencia|correccion", ...}
  POST /v1/feedback/lote [ ...feedback ]    (la app manda la cola acumulada sin conexión)
  GET  /v1/admin/resumen                       cabecera X-Admin-Token
  POST /v1/admin/usuarios/{usuario_id}/rol     {"rol": "hablante_verificado"}
  POST /v1/admin/recargar                      vuelve a leer modelos/ACTUAL (tras entrenar_hfrl.py)

Uso
  set FIELDSHIFT_ADMIN_TOKEN=un-secreto-largo
  python servidor_api.py --puerto 8000
  (documentación interactiva en http://localhost:8000/docs)
"""
from __future__ import annotations

import argparse
import hmac
import os
import threading
from pathlib import Path
from typing import Literal

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field

import feedback_db as fdb
from comun import LENGUAS, cargar_modelo, generar, modelo_actual, prompt_generar, prompt_traducir

Lengua = Literal["es", "kiche", "kaqchikel", "qeqchi", "mam"]


class Estado:
    lock = threading.Lock()      # un modelo, una generación a la vez (suficiente para un piloto)
    model = tok = None
    version = ""
    con = None


E = Estado()


def cargar(ruta: str | None = None):
    ruta = ruta or modelo_actual()
    model, tok = cargar_modelo(ruta)
    with E.lock:
        p = Path(ruta)
        version = (p.parent.name if p.name == "final" else p.name) if p.exists() else ruta   # sft | v0001 | ...
        E.model, E.tok, E.version = model, tok, version
    print(f"Modelo cargado: {ruta}")


app = FastAPI(title="Field Shift · LLM de lenguas mayas", version="1.0")


@app.on_event("startup")
def _inicio():
    E.con = fdb.conectar()
    if E.model is None:
        cargar(os.environ.get("FIELDSHIFT_MODELO"))


def _admin(token: str | None):
    esperado = os.environ.get("FIELDSHIFT_ADMIN_TOKEN")
    if not esperado or not hmac.compare_digest(token or "", esperado):
        raise HTTPException(401, "token de administrador inválido")


# ------------------------------------------------------------------ esquemas
class PedidoTraducir(BaseModel):
    texto: str = Field(min_length=1, max_length=1000)
    origen: Lengua = "es"
    destino: Lengua
    usuario_id: str | None = Field(default=None, max_length=64)
    n_candidatos: int = Field(default=2, ge=1, le=3)


class PedidoGenerar(BaseModel):
    instruccion: str = Field(min_length=1, max_length=1000)
    lengua: Lengua
    usuario_id: str | None = Field(default=None, max_length=64)
    n_candidatos: int = Field(default=2, ge=1, le=3)
    max_tokens: int = Field(default=200, ge=16, le=512)


class Feedback(BaseModel):
    interaccion_id: str
    usuario_id: str | None = Field(default=None, max_length=64)
    tipo: Literal["voto", "preferencia", "correccion"]
    candidato_id: str | None = None             # voto / corrección
    valor: Literal[-1, 1] | None = None         # voto
    preferido_id: str | None = None             # preferencia
    rechazado_id: str | None = None             # preferencia
    texto_corregido: str | None = Field(default=None, max_length=2000)
    comentario: str | None = Field(default=None, max_length=500)


class Rol(BaseModel):
    rol: Literal["usuario", "hablante_verificado", "revisor"]


# ------------------------------------------------------------------ rutas
@app.get("/v1/salud")
def salud():
    return {"ok": E.model is not None, "modelo_version": E.version, "lenguas": LENGUAS}


def _responder(tarea, origen, destino, texto, mensajes, n, usuario_id, max_tokens=200):
    with E.lock:
        cands = generar(E.model, E.tok, mensajes, n=n, max_new_tokens=max_tokens, temperatura=0.8)
        version = E.version
    cands = list(dict.fromkeys(c for c in cands if c)) or [""]       # sin duplicados exactos
    iid, cands = fdb.guardar_interaccion(E.con, tarea, origen, destino, texto, mensajes, cands, version, usuario_id)
    return {"interaccion_id": iid, "modelo_version": version, "candidatos": cands,
            "aviso": "Texto generado automáticamente: debe revisarlo un hablante antes de publicarlo."}


@app.post("/v1/traducir")
def traducir(p: PedidoTraducir):
    if p.origen == p.destino or (p.origen != "es" and p.destino != "es"):
        raise HTTPException(422, "por ahora se traduce entre español y una lengua maya")
    return _responder("traducir", p.origen, p.destino, p.texto, prompt_traducir(p.texto, p.origen, p.destino),
                      p.n_candidatos, p.usuario_id)


@app.post("/v1/generar")
def generar_texto(p: PedidoGenerar):
    return _responder("generar", None, p.lengua, p.instruccion, prompt_generar(p.instruccion, p.lengua),
                      p.n_candidatos, p.usuario_id, p.max_tokens)


def _validar(f: Feedback):
    if not E.con.execute("SELECT 1 FROM interacciones WHERE id=?", (f.interaccion_id,)).fetchone():
        raise HTTPException(404, "interacción desconocida")
    ids = {r[0] for r in E.con.execute("SELECT id FROM candidatos WHERE interaccion_id=?", (f.interaccion_id,))}
    if f.tipo == "voto" and (f.candidato_id not in ids or f.valor is None):
        raise HTTPException(422, "voto requiere candidato_id válido y valor ±1")
    if f.tipo == "preferencia" and not ({f.preferido_id, f.rechazado_id} <= ids and f.preferido_id != f.rechazado_id):
        raise HTTPException(422, "preferencia requiere preferido_id y rechazado_id distintos de esta interacción")
    if f.tipo == "correccion" and not (f.texto_corregido and f.texto_corregido.strip()):
        raise HTTPException(422, "corrección requiere texto_corregido")


@app.post("/v1/feedback")
def feedback(f: Feedback):
    _validar(f)
    return {"ok": True, "feedback_id": fdb.guardar_feedback(E.con, **f.model_dump())}


@app.post("/v1/feedback/lote")
def feedback_lote(lote: list[Feedback]):
    res = []
    for f in lote[:500]:
        try:
            _validar(f)
            res.append({"ok": True, "feedback_id": fdb.guardar_feedback(E.con, **f.model_dump())})
        except HTTPException as e:
            res.append({"ok": False, "error": e.detail})
    return res


@app.get("/v1/admin/resumen")
def admin_resumen(x_admin_token: str | None = Header(default=None)):
    _admin(x_admin_token)
    return {"modelo_version": E.version, **fdb.resumen(E.con)}


@app.post("/v1/admin/usuarios/{usuario_id}/rol")
def admin_rol(usuario_id: str, r: Rol, x_admin_token: str | None = Header(default=None)):
    _admin(x_admin_token)
    fdb.cambiar_rol(E.con, usuario_id, r.rol)
    return {"ok": True}


@app.post("/v1/admin/recargar")
def admin_recargar(x_admin_token: str | None = Header(default=None)):
    _admin(x_admin_token)
    cargar()
    return {"ok": True, "modelo_version": E.version}


if __name__ == "__main__":
    import uvicorn
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--puerto", type=int, default=8000)
    ap.add_argument("--modelo", default=None, help="por defecto, el de modelos/ACTUAL")
    a = ap.parse_args()
    if a.modelo:
        os.environ["FIELDSHIFT_MODELO"] = a.modelo
    uvicorn.run(app, host=a.host, port=a.puerto)
