# Cómo usar el modelo en la aplicación del teléfono

Guía para quien integre este modelo en la app de Field Shift Guatemala. El modelo es **experimental**:
la app debe tratarlo como un *asistente de sugerencias* que aprende de los usuarios, no como un traductor fiable.

## 1. Arquitectura

```
 App (Android / iOS)                     Servidor (Python)                           Entrenamiento periódico
 ───────────────────                     ─────────────────                           ───────────────────────
 pantalla traducir/escribir ──HTTPS──▶  servidor_api.py  ──▶ modelo (este adaptador)
 muestra 2 candidatos      ◀──────────  guarda la interacción en feedback.db
 👍 / 👎 · elegir · corregir ──HTTPS──▶  /v1/feedback  ──▶ feedback.db ──▶ entrenar_hfrl.py (KTO/DPO)
 cola sin conexión ─────────────────▶  /v1/feedback/lote                        │ si el chrF no empeora
                                         /v1/admin/recargar ◀─────────────────────┘ nueva versión en producción
```

- **El modelo corre en el servidor, no en el teléfono.** Ocupa ~1 GB en memoria (0.5 B parámetros) y necesita
  Python + PyTorch. Un servidor con 2–4 GB de RAM basta para un piloto. Con GPU las respuestas tardan menos de
  1 s; en CPU, unos 2–5 s por petición.
- El aprendizaje continuo (HFRL) también ocurre en el servidor: el teléfono solo envía las reacciones del usuario.
- *Modo sin conexión (no implementado):* se podría fusionar el adaptador, convertirlo a GGUF y cuantizarlo
  (~400 MB) para correrlo en el teléfono con llama.cpp. El teléfono no aprendería por sí mismo: tendría que
  descargar cada versión nueva.

## 2. Levantar el servidor

```bash
pip install -r scripts/traductor_lenguas_mayas/requirements-llm.txt
export FIELDSHIFT_ADMIN_TOKEN="un-secreto-largo"        # solo en el servidor, nunca en la app
python scripts/traductor_lenguas_mayas/servidor_api.py --modelo modelo_lenguas_mayas --host 127.0.0.1 --puerto 8000
```

- La API escucha en `127.0.0.1`. Publícala detrás de un proxy con **HTTPS** (nginx, Caddy, Cloud Run…).
- La documentación interactiva está en `http://localhost:8000/docs`.
- El feedback se guarda en `modelos/feedback.db`; esa ruta se cambia con `FIELDSHIFT_FEEDBACK_DB`.
  **Haz copias de seguridad de ese archivo**: es lo más valioso que genera la app.

## 3. Llamadas desde la app

Códigos de lengua: `es`, `kiche`, `kaqchikel`, `qeqchi`, `mam`. Por ahora solo se traduce entre el español y
una lengua maya, en cualquiera de los dos sentidos.

### Traducir

```http
POST /v1/traducir
{"texto": "maíz", "origen": "es", "destino": "kiche", "usuario_id": "3f9c…", "n_candidatos": 2}
```

```json
{
  "interaccion_id": "b1e2…",
  "modelo_version": "sft",
  "candidatos": [{"id": "c1…", "texto": "ixim"}, {"id": "c2…", "texto": "…"}],
  "aviso": "Texto generado automáticamente: debe revisarlo un hablante antes de publicarlo."
}
```

### Escribir un texto en una lengua

```http
POST /v1/generar
{"instruccion": "un consejo corto para sembrar maíz", "lengua": "mam", "usuario_id": "3f9c…", "max_tokens": 150}
```

La respuesta tiene la misma forma. Generar texto libre es todavía más débil que traducir palabras: muéstralo
como experimento.

### Enviar la reacción del usuario

Guarda `interaccion_id` y los `id` de los candidatos. Con ellos se envía cualquiera de estas tres señales:

| El usuario… | Cuerpo de `POST /v1/feedback` | Se usa para |
|---|---|---|
| toca 👍 o 👎 en un candidato | `{"interaccion_id", "usuario_id", "tipo": "voto", "candidato_id", "valor": 1}` (o `-1`) | KTO |
| elige el mejor de los dos | `{"interaccion_id", "usuario_id", "tipo": "preferencia", "preferido_id", "rechazado_id"}` | KTO y DPO |
| escribe la traducción correcta | `{"interaccion_id", "usuario_id", "tipo": "correccion", "candidato_id", "texto_corregido"}` | KTO y DPO (solo de hablantes verificados) |

Sin conexión, guarda las reacciones en una cola local y mándalas juntas con `POST /v1/feedback/lote`
(una lista con hasta 500). La respuesta trae `ok` para cada una, así puedes borrar de la cola las aceptadas.

## 4. Reglas para la interfaz

1. **Muestra siempre el `aviso`** y una etiqueta del tipo «traducción automática · versión experimental».
2. **Muestra los 2 candidatos** y pide elegir el mejor. Es la señal más fácil para el usuario y la más útil
   para el modelo. Que la elección sea un toque; los botones 👍/👎 y «Corregir» van como opciones secundarias.
3. **No publiques ni compartas automáticamente** lo que genera el modelo (SMS, avisos a la comunidad, carteles).
   Pide antes la revisión de una persona que hable la lengua.
4. Funciona mejor con **palabras sueltas y frases cortas** (vocabulario agrícola, nombres de cultivos,
   fenómenos del clima). Limita la entrada a unas pocas líneas y sugiere ejemplos de ese tipo.
5. **No lo uses** para salud, temas legales, alertas de emergencia ni documentos oficiales.
6. Muestra `modelo_version` en «Acerca de» o en un rincón de la pantalla: ayuda a reportar errores.

## 5. Usuarios, roles y privacidad

- `usuario_id` debe ser un **identificador anónimo** que la app genera una vez (UUID). No envíes nombre,
  teléfono ni ubicación.
- Antes de enviar feedback, **pide consentimiento** con un texto claro, por ejemplo: «Tus correcciones se
  guardan y se usan para mejorar el traductor».
- Roles (los cambia un administrador con `POST /v1/admin/usuarios/{id}/rol` y la cabecera `X-Admin-Token`):
  - `usuario`: sus votos cuentan la mitad (peso 0.5).
  - `hablante_verificado` y `revisor`: peso 1.0. Solo sus correcciones escritas se usan para entrenar.
- Para verificar hablantes conviene trabajar con organizaciones locales o con la ALMG, no con autodeclaración.

## 6. Ciclo de aprendizaje continuo

En el servidor, una vez por semana (o cada noche cuando haya bastante feedback):

```bash
python scripts/traductor_lenguas_mayas/entrenar_hfrl.py --min-ejemplos 50 --recargar-url http://localhost:8000
```

1. Toma el feedback pendiente y entrena una ronda KTO (o DPO con `--algoritmo dpo`). Mezcla ejemplos de
   repaso para que el modelo no olvide lo que ya sabía.
2. Evalúa la versión nueva y la actual sobre los mismos pares de prueba. **Solo la promueve si el chrF no
   baja** más de `--tolerancia` (1 punto por defecto). Si baja, producción queda igual y el feedback sigue
   pendiente.
3. Si la promueve, la registra en `modelos/ACTUAL` y pide a la API que la recargue sin reiniciarla. Las
   respuestas siguientes traen el nuevo `modelo_version`.

El estado del feedback se consulta con `GET /v1/admin/resumen`.

## 7. Si llamas al modelo sin la API

Respeta el formato con que se entrenó (lo arma `comun.prompt_traducir`):

- **system:** `Eres un asistente que escribe y traduce entre el español y los idiomas mayas k'iche', kaqchikel, q'eqchi' y mam de Guatemala. Usa la ortografía de la ALMG, con el saltillo escrito como '. Responde solo con el texto pedido.`
- **user:** `Traduce del español al k'iche':\n<texto>` (nombres de lengua: español, k'iche', kaqchikel, q'eqchi', mam)
- **user, para generar:** `Escribe en mam: <instrucción>`

Parámetros recomendados:
- Una sola respuesta: `temperature=0` (greedy).
- Varios candidatos: `temperature≈0.8` y `top_p=0.9`.
- En ambos casos, `repetition_penalty=1.1` y 40–60 tokens nuevos para traducir.

## 8. Licencia

[CC BY-NC 4.0](LICENSE.md): la app puede usar el modelo **sin fines comerciales** y debe citar la atribución
de [CREDITOS.md](CREDITOS.md). Para un uso comercial hay que revisar las licencias de las fuentes y hablar con
quienes las publicaron.
