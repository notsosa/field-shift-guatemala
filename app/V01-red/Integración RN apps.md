# Integración RN apps

## Inferencia local en Field Shift

La primera ruta a probar en Field Shift V01 es **ExecuTorch en la CPU del teléfono**. En la PC, PyTorch reconstruye cada política desde su checkpoint y la exporta a un archivo `.pte`. El APK incluye los modelos. Flutter llama al módulo Kotlin mediante un canal de plataforma que carga el modelo y ejecuta la inferencia. Con los datos requeridos ya guardados, el cálculo puede hacerse en modo avión. La sincronización de clima y perfiles sigue dependiendo de la conectividad. [ExecuTorch en Android](https://docs.pytorch.org/executorch/stable/using-executorch-android.html) · [Canales de plataforma de Flutter](https://docs.flutter.dev/platform-integration/platform-channels)

```text
Preparación en PC    checkpoint best.pt → política PyTorch → archivo .pte
Inferencia Android   datos locales → tensores → ExecuTorch → puntajes → acción
```

## Qué son las tres redes

El informe local de rotaciones `runs/rotation_final/RESULTADOS.md` llama «las tres redes congeladas» a las políticas de las semillas **17, 29 y 43** de `runs/final`. Comparten arquitectura y tienen pesos distintos. Un mismo módulo Android puede ejecutar cualquiera de las tres. El trío de `runs/farm_training_150` corresponde a otra corrida con franjas y escorrentía y requiere entradas adicionales. Las medianas publicadas resumen evaluaciones por semilla.

La app ya calcula el balance hídrico FAO-56 con los datos de plantación, clima y bitácora. La política recibe además datos estáticos, una ventana de 28 días de observaciones, hasta 32 eventos históricos, caja y precios, acciones candidatas, máscaras de viabilidad y puntajes base. Devuelve **un puntaje por acción**. La selección posterior aplica los límites de agua y caja compartida y resuelve empates. Por ejemplo, que regar tenga el puntaje más alto solo es relevante si hay agua disponible y la acción cabe en el presupuesto. FAO-56 aporta la lámina en milímetros, los gráficos y los avisos. [Recomendador de la app](lib/motor/recomendador.dart)

## Ruta de integración

1. **Fijar la referencia en Python.** Se cargaron en CPU los seis checkpoints de ambos tríos. En una prueba con entradas sintéticas, el grafo capturado por `torch.export` reprodujo los puntajes de PyTorch. La comprobación de identidad para la evaluación completa rechazó los seis porque las huellas de `sim.py` y `final_objective.py` difieren de las registradas al entrenar. Para generar casos de referencia con decisiones completas, recuperar la revisión correspondiente o demostrar equivalencia con la revisión actual. La conversión a `.pte` y la ejecución en Android quedan pendientes.
2. **Probar una sola política en el APK.** Usar primero un checkpoint de `runs/final` y exportar su inferencia en FP32. Empaquetar el `.pte` como recurso de Android y cargarlo una vez desde Kotlin. Desde `AppEstado`, ejecutar la inferencia de forma asíncrona cuando cambien los datos de la plantación. Comparar puntajes y acciones de Python y Android con las mismas entradas, incluidos casos con historial parcial, empates y riego inviable. [Estado de la app](lib/estado.dart) · [Exportación con ExecuTorch](https://docs.pytorch.org/executorch/stable/getting-started-setup.html)
3. **Conectar entradas reales y probar en modo avión.** Empezar con maíz y frijol, los cultivos del estudio final. Comparar las tres políticas por separado en paralelo con la regla actual. La evaluación reservada del estudio final dejó sin demostrar una mejora frente a esa regla. Cuando falten entradas obligatorias para la red, usar el recomendador de la app. Para comparar rotaciones de una campaña completa sin conexión también hace falta ejecutar localmente el simulador que actualiza el suelo, el cultivo y la caja día a día.

Las referencias del checkout local de simulación están en `field_shift/policy.py` para las entradas y puntajes, `field_shift/sim.py` para la preparación de datos y selección, `field_shift/run.py` para la identidad de los checkpoints y `runs/final/RESULTADOS.md` para la evaluación reservada.

## Antecedentes

- **Edge Impulse** muestra cómo incluir un modelo `.pte` en un APK y ejecutarlo con Kotlin y XNNPACK en CPU. **Arm** muestra cómo una sola aplicación selecciona entre dos modelos locales y prepara sus entradas. [Demo de Edge Impulse](https://github.com/edgeimpulse/executorch-android-app/blob/main/README.md) · [App de referencia de Arm](https://github.com/arm-education/ai-portal-android-app-image-to-image)
- **PlantVillage Nuru** es un antecedente agrícola evaluado en campo. Ejecuta en Android un diagnóstico de síntomas a partir de imágenes y ofrece asesoría de manejo sin conexión. [Estudio de PlantVillage Nuru](https://pmc.ncbi.nlm.nih.gov/articles/PMC7775399/)
- **ONNX Runtime** es una alternativa para usar el mismo archivo también en Windows o si ExecuTorch presenta una incompatibilidad al convertir la política. Microsoft publica una app Android reproducible y PyTorch documenta la exportación a `.onnx`. [Ejemplo Android de Microsoft](https://onnxruntime.ai/docs/tutorials/mobile/deploy-android.html) · [Exportación de PyTorch a ONNX](https://docs.pytorch.org/tutorials/beginner/onnx/export_simple_model_to_onnx_tutorial.html)
