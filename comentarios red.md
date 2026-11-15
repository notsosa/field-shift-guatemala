# Comentarios sobre las redes de Field Shift

**Para la demo, usaría `modelo-keu`**, porque ya corre y sus resultados se pueden reproducir. Para el caso de Field Shift de decidir qué hacer después de perder una cosecha, la red de política propuesta encaja mejor con la decisión que necesita tomar el productor. Todavía falta implementarla y medir si toma mejores decisiones.

| Aspecto | Red de `modelo-keu` | Red de política propuesta |
| --- | --- | --- |
| **Qué recibe** | Clima, suelo, riego, una rotación predefinida y una fecha candidata. | Estado del lote en ese momento, daño observado, agua, semilla, presupuesto, prioridad del productor y una acción candidata. |
| **Qué devuelve** | Estimaciones de rendimiento relativo por agua, estrés en floración y suelo descubierto. El programa usa esas estimaciones para elegir una fecha. | Un puntaje para cada acción viable: continuar, esperar, resembrar, cambiar de cultivo o dejar cobertura. El programa elige la de mayor puntaje y puede reevaluar en la siguiente fecha de decisión. |
| **Cómo aprende** | Aprende a reproducir las salidas del simulador de balance hídrico FAO-56. | La búsqueda evolutiva ajustaría los pesos según los resultados de las decisiones a lo largo de la temporada. |

[Código del emulador](web/js/model/emulator.js) · [Selección de la fecha de siembra](web/js/ui/bestSowing.js) · [Diseño de la red evolutiva propuesta](https://github.com/notsosa/field-shift-guatemala/blob/d53941b7a6700add491122b8e3541483c7a24939/contexto%20parametros%20hackaton.md#estructura-y-entrenamiento-de-la-red-evolutiva)

Por ejemplo, **`modelo-keu` ayuda a estimar cuántos días después del inicio de las lluvias conviene sembrar el maíz**. La red de política respondería **qué hacer si ese maíz ya se sembró y se perdió**. Podría preferir esperar si eso abre una opción de resiembra, o cambiar de cultivo si la ventana ya se está cerrando.

Aprovecharía `modelo-keu` para estimar las consecuencias de las acciones que ya cubre. Para medir el aporte de la red de política, la compararía contra una regla agronómica sencilla en los mismos casos de pérdida de cosecha y con la misma información disponible en la fecha de decisión. Las medidas serían **margen, pérdidas en años malos y proporción de acciones recomendadas que el productor puede ejecutar**.
