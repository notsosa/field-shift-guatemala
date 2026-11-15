# Field Shift Guatemala · V1 red

V1 es la primera versión publicada de la política neuronal entrenada del equipo. Conserva los pesos de la corrida final para el piloto de maíz y frijol. La política recibe el estado de la finca y de cada sublote junto con las acciones candidatas. Devuelve un puntaje por acción y el sistema elige entre las que cumplen las restricciones de la finca.

## Arquitectura y entrenamiento

`policy.py` contiene la arquitectura de inferencia que coincide con los checkpoints. Usa cuatro codificadores para los datos fijos del sublote, las observaciones recientes, el historial y el estado financiero. Combina esas entradas con bloques residuales y atención entre sublotes. La salida suma una corrección aprendida al puntaje de una regla inicial y aplica una máscara a las acciones inviables.

Cada checkpoint tiene **68 131 parámetros** en `float32`. Los anchos de entrada son **24** para datos fijos, **12** por día de observación reciente, **16** por evento histórico, **26** para el estado financiero y **16** por acción candidata. La corrida usa ventanas de 28 días y 32 eventos. El entrenamiento usa neuroevolución **LM-MA-ES**, con 100 generaciones por semilla y selección de pesos en validación. Las prioridades de la corrida son producción por día y margen neto.

| Checkpoint | Semilla | Generación elegida | Utilidad de validación |
| --- | ---: | ---: | ---: |
| [`seed_17/best.pt`](seed_17/best.pt) | 17 | 100 | 0.660810 |
| [`seed_29/best.pt`](seed_29/best.pt) | 29 | 90 | 0.661228 |
| [`seed_43/best.pt`](seed_43/best.pt) | 43 | 50 | 0.661402 |

Los tres checkpoints son variantes de la misma arquitectura. La evaluación original usó las tres semillas. El checkpoint de la semilla 43 obtuvo la mayor utilidad de validación.

## Cómo cargar los pesos

Desde esta carpeta, con un entorno de Python que tenga PyTorch instalado:

```python
import torch
from policy import NeuralPolicy

policy = NeuralPolicy(24, 12, 16, 26, 16).eval()
checkpoint = torch.load("seed_43/best.pt", map_location="cpu", weights_only=True)
weights = checkpoint["weights"].unsqueeze(0)
score_actions = policy.prepare(weights)
```

La función `score_actions` recibe los tensores que construye el simulador, la máscara de factibilidad y los puntajes de la regla inicial. Esta carpeta conserva los pesos y el código de inferencia. El simulador y la preparación de los escenarios corresponden al proyecto original.

## Alcance de V1

Esta versión se entrenó con escenarios simulados de Field Shift. La evaluación reservó los años 2022–2025 y registró cero acciones inviables en esos escenarios. La evaluación tampoco demostró una mejora frente a la regla inicial. Los pesos son anteriores al reentrenamiento planteado para incorporar aporte hídrico natural y persistencia del encharcamiento.

Se comprobaron la carga en CPU y la producción de puntajes finitos para las tres semillas usando PyTorch 2.11.0. Los archivos conservan las huellas de los checkpoints seleccionados:

| Archivo | SHA-256 |
| --- | --- |
| `seed_17/best.pt` | `6c987ce6a0fc3be4e9138ec40ade0ff5e01ddfc697d86a4a492595badfa58c8e` |
| `seed_29/best.pt` | `6ee6a41b43ebea26f5ce34be3693458662d37f67aa1a61bc752dfe7a06592275` |
| `seed_43/best.pt` | `8526b117045e41a40fa8956d79a96f860978ef5a0aaece3f1c81970f31a5c814` |
