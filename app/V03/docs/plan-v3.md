# Redes neuronales locales

En **Finca → Plan diario**, el usuario elige el objetivo, puede indicar la caja y el costo por turno, y pulsa **Calcular plan**. La app carga los pesos incluidos en el APK, evalúa los lotes y guarda el tablero diario para consultarlo sin conexión. Una fecha nueva o cambios en las entradas marcan el plan guardado como desactualizado.

## Cálculo

`lib/motor/red_v3.dart` ejecuta en Dart la política V3 de 72,099 parámetros, con atención entre lotes, máscaras temporales y ajuste residual sobre la regla base. `assets/modelos/field_shift_v3.f32` contiene los parámetros FP32 en orden de la arquitectura entrenada, a partir de `runs/v3_150/seed_17/best.pt`, generación seleccionada 60. La huella SHA-256 del checkpoint es `e2bf12901e4a67f7aee3d891df5679d4fa7fe6ec53ac87fe260940221cdbd7d8`. La del archivo incluido es `d60a22b7e73ecf1610a4bc50336dca98983be7ab3b5d7098d995d13d0ae2889f`.

`lib/motor/entradas_v3.dart` construye las entradas con el clima guardado, la campaña, el suelo, los eventos y el balance FAO-56 de la app. Los valores disponibles se distinguen de las referencias del modelo y las observaciones faltantes usan sus máscaras correspondientes.

`lib/motor/planificador_v3.dart` habilita las acciones diarias de esperar, continuar y regar para campañas activas con perfil V3. La lámina proviene del balance hídrico. El turno considera el suministro confirmado, el volumen compartido, el presupuesto y el riego reciente. Se asigna como máximo un turno al lote elegible con mayor diferencia entre el puntaje de regar y esperar. El costo opcional declarado sustituye la referencia de Q28 por turno. El tablero muestra la decisión, la reserva de agua, los m³ y el costo del plan cuando aplica.

## Elegir una siembra

**Nueva plantación** abre el registro manual. **Sugerir cultivo con red neuronal** toma un lote disponible o el contorno dibujado y puntúa los candidatos del catálogo de 18 especies y 19 perfiles. La propuesta incluye cultivo, variedad de referencia, fecha y ciclo. Usa el suelo y método de riego de la campaña anterior, cuando existen. Para un lote nuevo, parte de suelo franco y secano como supuestos. El cultivo se registra tras la revisión del usuario. Una fecha futura se muestra como propuesta de calendario y conserva el lote disponible.

## Riego del café

Para un cafetal, **Hoy** y la ficha del lote muestran el beneficio estimado de aplicar 20 mm. La red de Keu estima días de estrés hídrico que se podrían evitar durante los próximos 30 días. **Datos del cafetal** permite guardar la sombra, el suelo entre surcos y la prioridad. La sincronización solicita clima desde el 1 de noviembre más reciente cuando hay café activo. La pantalla explica si falta historial, si ya se registró riego o si la fecha queda fuera de la etapa evaluada por el modelo. La disponibilidad de agua y el balance FAO-56 limitan la recomendación de riego.

La red de café y sus pesos provienen de [`modelo-keu`](https://github.com/notsosa/field-shift-guatemala/blob/modelo-keu/app/V01-red/lib/motor/pesos_cafe.dart). Las pruebas fijas comparan la política de planificación con PyTorch y el resultado de café con la referencia de Keu. El simulador anual y las proyecciones de cosecha y margen quedan pendientes. Las estimaciones requieren contraste agronómico en campo.
