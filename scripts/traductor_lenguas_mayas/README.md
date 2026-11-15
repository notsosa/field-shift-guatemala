# LLM de lenguas mayas: generador y traductor con aprendizaje continuo (HFRL)

Un modelo de lenguaje pequeño (Qwen2.5-0.5B-Instruct por defecto) adaptado al **k'iche'**, **kaqchikel**, **q'eqchi'** y **mam**. Hace tres cosas: genera texto en estas lenguas y en español, y traduce entre el español y cada una de ellas. Después de publicarse sigue mejorando con el feedback de las personas que usan la app.

> **Aviso.** Con el corpus actual (≈18 M caracteres y ≈6 800 pares de diccionario, casi todos de palabras sueltas) el modelo traduce palabras y frases cortas, pero las oraciones completas todavía salen con errores. Toda salida debe revisarla un hablante antes de mostrarse como texto oficial en la app (ver [diccionarios/README.md](../../diccionarios/README.md)). El feedback de hablantes es lo que más lo hará mejorar.

## Archivos

| Script | Qué hace |
|---|---|
| [construir_corpus_pretraining.py](construir_corpus_pretraining.py) | PDF + diccionarios web → corpus limpio (`datos/lenguas_mayas/pretraining/`) |
| [preparar_datos_llm.py](preparar_datos_llm.py) | Corpus + diccionarios → dataset de instrucciones (`datos/lenguas_mayas/pretraining/llm/`) |
| [probar_modelo.py](probar_modelo.py) | **Consola interactiva:** escribes texto y ves la traducción o la generación |
| [entrenar_pretraining.py](entrenar_pretraining.py) | **Etapa 1.** Pre-entrenamiento continuo con texto maya crudo (LoRA) |
| [entrenar_sft.py](entrenar_sft.py) | **Etapa 2.** Ajuste por instrucciones: traducir, continuar texto, escribir párrafos, explicar palabras |
| [evaluar.py](evaluar.py) | chrF++ sobre pares reservados (no vistos en el entrenamiento) |
| [generar.py](generar.py) | Probar el modelo desde la terminal |
| [servidor_api.py](servidor_api.py) | API HTTP (FastAPI) para la app: traducir, generar y recibir feedback |
| [feedback_db.py](feedback_db.py) | Base SQLite de interacciones y feedback, y conversión a datos de preferencia |
| [entrenar_hfrl.py](entrenar_hfrl.py) | **Etapa 3, continua.** Ronda de aprendizaje con feedback humano (KTO o DPO) con compuerta de calidad |
| [clases_transformer_llm.py](clases_transformer_llm.py) | Prototipo anterior con mT5 (encoder-decoder). Lo reemplaza este pipeline |

## Datos

El corpus **no está en este repositorio público**: varias fuentes (ALMG, Biblias con licencia CC BY-NC-ND) no permiten redistribuirlo abiertamente. Está en el repositorio privado [mariobet23440/lenguas-mayas-corpus](https://github.com/mariobet23440/lenguas-mayas-corpus); pide acceso a Mario. Clónalo en la carpeta que esperan los scripts, que ya está en `.gitignore`:

```bash
git clone https://github.com/mariobet23440/lenguas-mayas-corpus datos/lenguas_mayas/pretraining
```

Si lo tienes en otra carpeta, indica la ruta con la variable de entorno `FIELDSHIFT_CORPUS`.

- `datos/lenguas_mayas/pretraining/shards/<lengua>/*.jsonl`: corpus de pre-entrenamiento. Las autorías y licencias de cada fuente están en `final/CREDITOS.md`.
- `datos/lenguas_mayas/pretraining/raw_web/*.jsonl`: diccionarios web (pares palabra–glosa).
- `diccionarios/*.md`: tablas curadas. Solo se usan las filas con confianza *Fuente*, *Contexto* o *Derivada*, y se sobremuestrean ×3.
- `datos/lenguas_mayas/pretraining/llm/`: datasets del LLM (`sft_train.jsonl`, `sft_eval.jsonl`, `estadisticas_sft.json`). Los genera `preparar_datos_llm.py` en unos segundos y también están en el repo privado. Si los regeneras, súbelos desde esa carpeta (`git add llm && git commit && git push`).

## Cómo entrenar

Se necesita GPU. Con una T4 gratuita de Colab o Kaggle, la etapa 1 tarda unas 1–2 h y la etapa 2 unos 30–60 min con el modelo de 0.5B. Si hay una GPU de ≥16 GB, conviene `--modelo Qwen/Qwen2.5-1.5B-Instruct`, que traduce bastante mejor.

```bash
git clone https://github.com/notsosa/field-shift-guatemala && cd field-shift-guatemala
git clone https://github.com/mariobet23440/lenguas-mayas-corpus datos/lenguas_mayas/pretraining   # privado
cd scripts/traductor_lenguas_mayas
pip install -r requirements-llm.txt
python preparar_datos_llm.py
python entrenar_pretraining.py            # -> modelos/cpt/final
python entrenar_sft.py                    # -> modelos/sft/final, y queda registrado en modelos/ACTUAL
python probar_modelo.py                   # consola interactiva: escribe texto y ve la traducción
```

Ejemplo de sesión en `probar_modelo.py`:

```
[traducir español → k'iche'] > Mañana va a llover, no riegue la milpa.
[traducir español → k'iche'] > /traducir qeqchi es
[traducir q'eqchi' → español] > ixim
[traducir q'eqchi' → español] > /generar mam
[generar en mam] > un consejo corto para sembrar maíz
[generar en mam] > /n 2          (muestra dos opciones)
[generar en mam] > /salir
```

Para probar el pipeline en CPU antes de gastar GPU:

```bash
python entrenar_pretraining.py --modelo HuggingFaceTB/SmolLM2-135M-Instruct --max-docs 40 --max-pasos 3 --block-size 128
python entrenar_sft.py --max-ejemplos 64 --max-pasos 3 --max-eval 6
```

### Entrenar de noche en una computadora sin GPU

```powershell
powershell -ExecutionPolicy Bypass -File scripts\traductor_lenguas_mayas\iniciar_entrenamiento_noche.ps1 -Horas 8
Get-Content modelos\logs\ESTADO.txt          # ver en qué va
```

[entrenar_noche.py](entrenar_noche.py) corre en segundo plano con la ventana oculta y pide a Windows que no se suspenda. En CPU solo hace el SFT de traducción, con límite de horas y un checkpoint cada 25 pasos (unos 35 min). Si la computadora se apaga, vuelve a lanzarlo y sigue desde el último checkpoint. Al terminar evalúa y registra el modelo, y `probar_modelo.py` lo usa directamente.

Medido en una laptop de 8 núcleos con Qwen2.5-0.5B: unos 5 s por ejemplo, o sea ~5 500 ejemplos en 8 h (≈ 38 % de una época de traducción). Para el entrenamiento completo usa GPU (ver [ESTADISTICAS.md del repo privado](https://github.com/mariobet23440/lenguas-mayas-corpus/blob/main/ESTADISTICAS.md)).

Para generar las estadísticas de los datos: `python estadisticas_datos.py`. Escribe `ESTADISTICAS.md` en el repo privado.

## Aprendizaje continuo con feedback humano (HFRL) en una app de teléfono

El modelo **no se entrena dentro del teléfono**. El entrenamiento necesita GPU y debe controlarse antes de publicar. El teléfono solo hace dos cosas: muestra respuestas y recoge opiniones. Todo lo demás pasa en el servidor, en un ciclo:

```
 ┌──────────── teléfono ────────────┐        ┌──────────────── servidor ─────────────────┐
 │ 1. pide traducción               │ ─────▶ │ servidor_api.py  /v1/traducir             │
 │ 2. ve 2 opciones (A / B)         │ ◀───── │   genera 2 candidatos, guarda interacción │
 │ 3. 👍/👎, elige A o B, o corrige │ ─────▶ │   /v1/feedback  → modelos/feedback.db     │
 │    (sin señal: se guarda en cola │        │                                           │
 │     y se envía con /feedback/lote)│        │ cada noche: entrenar_hfrl.py              │
 └──────────────────────────────────┘        │   feedback → KTO/DPO → LoRA → evaluar     │
                                             │   ¿chrF no empeora? → modelos/ACTUAL       │
                                             │   → /v1/admin/recargar (modelo nuevo)     │
                                             └───────────────────────────────────────────┘
```

### 1. Qué tiene que hacer la app

Cada respuesta de `/v1/traducir` o `/v1/generar` trae un `interaccion_id` y 2 `candidatos` con su `id`. La app los muestra y ofrece tres gestos, del más fácil al más valioso:

| Gesto en la app | Llamada | Uso en el entrenamiento |
|---|---|---|
| 👍 / 👎 en una opción | `{"tipo": "voto", "candidato_id": "...", "valor": 1}` | ejemplo bueno/malo (KTO) |
| "Esta está mejor" (A o B) | `{"tipo": "preferencia", "preferido_id": "...", "rechazado_id": "..."}` | par elegido > rechazado (DPO y KTO) |
| ✏️ "Corregir" (escribe o dicta la versión correcta) | `{"tipo": "correccion", "candidato_id": "...", "texto_corregido": "..."}` | la señal más fuerte: par corrección > original |

Ejemplo:

```http
POST /v1/traducir
{"texto": "Hay riesgo de helada esta noche.", "origen": "es", "destino": "kaqchikel", "usuario_id": "c1f0…"}

→ {"interaccion_id": "9b2…", "modelo_version": "v0003",
   "candidatos": [{"id": "a1…", "texto": "…"}, {"id": "b7…", "texto": "…"}]}

POST /v1/feedback
{"interaccion_id": "9b2…", "usuario_id": "c1f0…", "tipo": "preferencia", "preferido_id": "b7…", "rechazado_id": "a1…"}
```

Recomendaciones para la app:

- **Sin conexión.** En el área rural la señal es intermitente. Guarda el feedback en una cola local (SQLite o Room) y envíalo con `/v1/feedback/lote` cuando haya red.
- **`usuario_id` seudónimo.** Genera un UUID al instalar la app. No envíes nombre, teléfono ni GPS: no hacen falta para entrenar.
- **Pocos toques.** El feedback debe ser opcional y rápido, por ejemplo dos botones grandes "A" y "B" debajo de la traducción. Para personas que leen poco, la corrección puede ser por voz (transcripción en el servidor, fuera de este pipeline).
- **Hablantes verificados.** Las correcciones solo se usan si vienen de un `hablante_verificado` o un `revisor` (por ejemplo, de la Comunidad Lingüística de la ALMG o extensionistas del MAGA). El rol se asigna con `POST /v1/admin/usuarios/{id}/rol`. Los votos de usuarios no verificados pesan 0.5, así que hacen falta al menos dos que coincidan.
- **Mostrar la versión.** `modelo_version` sirve para saber qué modelo produjo cada respuesta y comparar versiones.

### 2. Qué hace el servidor cada noche

```bash
python entrenar_hfrl.py --recargar-url http://localhost:8000     # KTO por defecto
```

1. Lee el feedback pendiente y lo convierte en datos de preferencia. Usa **KTO** cuando el feedback es sobre todo 👍/👎, y **DPO** (`--algoritmo dpo`) cuando ya hay muchas elecciones A/B y correcciones. Los dos son formas de RLHF que no necesitan un modelo de recompensa aparte ni PPO, y son estables con pocos datos.
2. Agrega ejemplos verificados del SFT como "repaso", para que el modelo no olvide lo que ya sabía.
3. Entrena un LoRA sobre el modelo en producción. El modelo anterior, congelado, sirve de referencia: la penalización KL (`--beta`) impide que se aleje demasiado.
4. **Compuerta de calidad.** Mide chrF con los pares reservados. Si baja más de `--tolerancia` puntos, la versión se descarta y el feedback queda pendiente para la próxima ronda. Si no, se guarda como `modelos/hfrl/vNNNN`, se registra en `modelos/ACTUAL` y se le pide a la API que la cargue sin reiniciar.
5. Cada versión anterior queda en disco. Para volver atrás, escribe su ruta en `modelos/ACTUAL` y llama a `/v1/admin/recargar`.

Para programarlo en Linux: `crontab -e` → `0 2 * * * cd /ruta/repo/scripts/traductor_lenguas_mayas && ../../.venv/bin/python entrenar_hfrl.py --recargar-url http://localhost:8000`. En Windows, con el Programador de tareas.

### 3. ¿Y si el modelo debe funcionar sin internet?

El modelo fusionado de 0.5B (≈1 GB en fp16, ≈350 MB en GGUF Q4) puede correr dentro del teléfono con llama.cpp o MLC LLM. En ese caso:

- El teléfono descarga la versión nueva (`vNNNN`) cuando hay Wi-Fi.
- El feedback se sigue guardando en la cola local y se sube después. El entrenamiento sigue siendo en el servidor.
- Para convertir el modelo: `python llama.cpp/convert_hf_to_gguf.py modelos/hfrl/v0003 --outtype q8_0`.

## Límites y próximos pasos

- **Faltan pares de oraciones.** Los mejores candidatos son las leyes bilingües del corpus (Ley de Acceso a la Información en kaqchikel, q'eqchi' y mam, y la Constitución en q'eqchi'), alineando artículo por artículo. Así el modelo aprendería oraciones, no solo palabras.
- **El k'iche' tiene poca prosa** (0.8 M caracteres). El muestreo con temperatura de la etapa 1 lo compensa en parte, pero hacen falta más textos.
- **La seguridad de la API es mínima** (un token de administrador). Antes de publicarla, agrega HTTPS, límite de peticiones por `usuario_id` y autenticación de la app.
