# Agua y geometrías · versión 1.1

Implementación del 15 de noviembre de 2026. Las cantidades desconocidas permanecen nulas. La captura y los cálculos siguen funcionando sin conexión con el clima guardado.

| Dato | Significado y unidad |
|---|---|
| `SuministroAgua.fecha` | Fecha civil de la observación; no se hereda a otros días. |
| `disponibilidad` | `desconocida`, `si` o `no`, para una fuente compartida de la finca. |
| `volumenM3` | Saldo disponible para repartir entre los lotes en esa fecha, m³; opcional, admite cero. No representa el caudal ni el total aplicado en el pasado. |
| `RegistroRiego.loteId` | Identidad del terreno al que pertenece la observación. |
| `RegistroRiego.fecha` | Día de la observación/aplicación. |
| `necesito` | Declaración del productor sobre la necesidad de riego: sí, no o sin dato. Se conserva aparte de la necesidad calculada. |
| `rego` | Aplicación confirmada, ausencia confirmada de aplicación o desconocida. No determina el saldo disponible. |
| `laminaMm` | Cantidad aplicada al lote, mm; opcional y positiva si `rego` es verdadero. |
| `DiaAgua.lluvia` / `EstadoDia.lluvia` | Observación de precipitación, mm, o nulo. Cero observado y dato faltante son distintos. |
| `et0Estimada`, `riegoEstimado` | Indicadores de imputación independientes de la observación de lluvia. |

Cuando la plantación seleccionada tiene riego configurado, desde **Hoy → Suministro de agua hoy**, o desde **Registros → Agua y riego por fecha**, se captura el suministro de la finca y la aplicación del lote seleccionado. Se pueden consultar o corregir observaciones de fechas anteriores. Al guardar otra vez el mismo lote/día se reemplaza su observación, sin duplicarla.

Tener un tipo de riego instalado no basta para sugerir una aplicación. Sin suministro confirmado en la fecha actual, `riegoSugerido` queda en cero y la necesidad física se conserva en `necesidadRiego`. El formulario no deduce falta de agua de no haber regado, ni convierte disponibilidad pasada en disponibilidad actual.

Si hay saldo conocido, la app convierte las necesidades a m³ usando las áreas geográficas válidas y reparte proporcionalmente entre los lotes activos. La suma de las propuestas no supera el saldo declarado. Un lote sin perímetro válido no recibe una asignación cuantitativa cuando el volumen debe repartirse. Esta versión representa una fuente compartida; no implementa turnos ni múltiples fuentes independientes.

Los registros semanales anteriores conservan sus conteos e intervalos. Su reparto diario y las láminas por tipo son estimaciones. Una aplicación diaria con cantidad conocida sustituye la estimación semanal de ese día; un «no regué» explícito la anula. Las cantidades supuestas siguen marcadas. La disponibilidad y las observaciones de necesidad desconocidas no anulan por sí mismas el resumen semanal.

Los huecos de ET₀ usan la media de las últimas siete observaciones válidas anteriores, o 4 mm/día si no hay antecedentes. Una lluvia conocida se conserva aunque falten variables para ET₀. Donde falta lluvia, el balance numérico considera un escenario sin aporte de precipitación, pero conserva el nulo en la salida y muestra la advertencia. El total semanal queda desconocido si falta lluvia en esa semana; el factor de rendimiento se oculta si el balance tiene lluvia desconocida. Los conteos incluyen huecos internos. La calidad de datos es una regla de cobertura, no una precisión calibrada.

Los contornos antiguos se convierten una vez usando el centro, ancho y proyección del plano que tenían guardados. `Lote` conserva su identificador y una lista canónica de `Coordenada`; `Plantacion.loteId` lo referencia. El contorno fraccional que usan las pantallas se deriva de esas coordenadas. Cambiar el ancho o el punto de consulta de la finca no traslada el terreno. El cambio de punto sí invalida el clima anterior.

El plano permite pellizcar y arrastrar dentro del encuadre mostrado; esos gestos no escriben geometrías. Los botones de escala amplían el encuadre del editor. No se incorporó un sistema de navegación cartográfica mundial ni una herramienta para trasladar todos los lotes a otra ubicación.

Antes de guardar un trazo se comprueban superficie, puntos finitos, cruces propios, contención en la finca y solapamiento con otros lotes activos. Se admiten bordes y esquinas compartidos. La tolerancia de superficie es 0.01 m² en el plano métrico local; no expresa precisión del dibujo o del GPS. La comprobación usa triangulación y recorte, de modo que contempla concavidades y no solo los vértices. Los contornos antiguos inválidos se conservan para corregirlos; no se reparan ni se borran automáticamente y no se exportan como válidos.

**Finca → Copiar GeoJSON** entrega una `FeatureCollection` con finca y lotes activos, identificadores, asociaciones y áreas. Las posiciones se expresan como longitud/latitud WGS 84, con anillos exteriores cerrados y antihorarios. Un lote sin dibujar tiene `geometry: null`. Las áreas usan una esfera de radio medio 6 371 008.8 m y son aproximadas. No hay importador de geometrías con huecos o multipolígonos en esta entrega; el editor produce polígonos simples y está pensado para el contexto de Guatemala.

La persistencia usa una escritura JSON versionada en `fincaV2`, que agrupa finca, plantaciones, lotes, observaciones de agua, registros y selección. Las escrituras se ordenan. Las claves anteriores se conservan como respaldo de la migración; no deben tratarse como una segunda fuente actualizada. Cambios nuevos pertenecen al esquema nuevo. Clima, preferencias y caché de mapa mantienen sus claves actuales. La migración no inventa observaciones de agua ni fechas exactas de los riegos antiguos.

La revisión automática cubre disponibilidad desconocida/no/sí, caducidad de la observación, saldo cero y compartido, área pendiente, lluvia nula/cero e independiente de ET₀, reemplazo de conteos por aplicaciones diarias, migración y reapertura, polígonos cóncavos y cruzados, bordes compartidos, estabilidad de coordenadas y guardar/cancelar. La validación agronómica y de campo sigue pendiente.

Verificación de esta entrega: `flutter analyze` sin problemas, 61 pruebas aprobadas y APK release compilado. La versión 1.1.0+2 se instaló en el Galaxy A14 con `adb install -r`, después de comprobar la firma y guardar el APK anterior. Tras una reapertura en frío se conservaron las tres plantaciones y el punto de la finca. Cancelar el formulario de agua no creó observaciones. La exportación detectó un contorno antiguo de Frijol fuera de la finca y lo identificó por nombre; ese dibujo se conservó y requiere revisión antes de exportar. No se guardaron registros ficticios en el teléfono.

Corrección 1.1.1+3: las plantaciones configuradas «Sin riego» no muestran los accesos de suministro en Hoy ni de captura diaria de riego en Registros. Si existen aplicaciones antiguas, el historial se conserva en consulta. La prueba de regresión comprueba el cambio de selección entre cultivos con/sin riego y la conservación del historial al retirar el sistema. Verificación automática: 62 pruebas aprobadas y análisis limpio.
