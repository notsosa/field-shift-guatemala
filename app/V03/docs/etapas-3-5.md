# Campañas, bitácoras y paquete de datos

Entrega local 1.2.0+4, 15 de noviembre de 2026. Continúa [agua y geometría](etapas-1-2.md). Las etapas 3–5 corresponden a la captura e intercambio de datos en la app. La conexión al modelo neuronal sigue pendiente de que su autor publique el contrato. El cálculo de relieve y escorrentía requiere un modelo de elevación y un método todavía no disponibles.

## Uso

- En **Agua y riego por fecha**, si hay varias plantaciones con riego artificial, se debe elegir la destinataria. Cambiarla carga su registro del día y vacía los datos de aplicación que no le pertenecen. El suministro sigue siendo compartido por la finca. Los cultivos sin riego mantienen oculto el acceso de captura.
- En la ficha de plantación se agregaron variedad, cultivo anterior, mantener cultivo, permitir mezcla y mínimo del lote. El usuario confirmó que este último es el **porcentaje del área del lote** que debe conservar el cultivo actual, entre 0 y 100; es opcional y solo se guarda cuando se permite mezcla.
- **Registros → Cosechas, pérdidas y manejo** abre la bitácora de la campaña seleccionada. Cada evento queda asociado explícitamente a esa campaña y a su lote. Puede editarse o borrarse un evento detallado con confirmación de borrado.
- **Campañas e historial**, disponible también en Ajustes, conserva las campañas cerradas. Cerrar una campaña libera el mismo lote para otra siembra. La nueva campaña tiene otro identificador; conserva geometría, suelo y sistema como valores iniciales, y presenta el cultivo anterior para revisión. El contorno de un lote reutilizado no se redibuja durante ese alta.
- **Ajustes → Paquete de datos** permite copiar JSON y pegar un paquete para revisar antes de importar. Funciona sin conexión. No sustituye la finca actual por otra.

## Diccionario mínimo

| Dato | Identidad, alcance y significado |
|---|---|
| Lote | ID físico estable y geometría geográfica WGS84, posiciones `[longitud, latitud]`. Un cambio de campaña no crea otro lote. |
| Campaña (`Plantacion`) | ID independiente, lote, cultivo, variedad opcional, cultivo anterior, siembra/referencia, duración, suelo y manejo. `fin == null` indica campaña activa. Solo una activa por lote. |
| Restricciones | `mantenerCultivo` obliga a conservar la especie en alternativas; `permitirMezcla` permite componentes simultáneos; `proporcionMinima` expresa porcentaje del lote para el cultivo actual. No ejecutan un optimizador todavía. |
| Riego diario | Campaña + lote + fecha; necesidad, aplicación y lámina opcional en mm. Una campaña nueva no hereda las aplicaciones de la anterior. |
| Suministro | Fecha de la finca, sí/no/desconocido, saldo opcional en m³. No se hereda al día siguiente. |
| Cosecha parcial | Fecha, cantidad y unidad original. Se suman kg, g y t convertibles; otras unidades permanecen pendientes de conversión y pueden describirse en la nota. El total es cosecha registrada, no una estimación de producción total. |
| Pérdida | Fecha, cantidad opcional y referencia obligatoria: superficie, producción esperada o producto ya cosechado. Superficie admite %, m² o ha; producción y producto admiten %, kg, g o t. No se descuenta automáticamente del total cosechado ni del rendimiento calculado. |
| Plaga | Observación fechada, severidad y nota. Una observación detallada reciente puede actualizar la alerta; un tratamiento no acredita eficacia ni curación. |
| Tratamiento / fertilización | Fecha, producto, cantidad y unidad opcionales; si hay dosis, se guarda su referencia: lote, ha, m², litro de mezcla o desconocida. No se inventa dosis ni efecto cuantitativo. |
| Sombra | Porcentaje observado del área del lote, fecha, método y nota opcionales. |
| Humedad del suelo | Valor opcional en %, m³/m³ o kPa, fecha, profundidad en cm y método cuando se conocen. No se convierten entre sí sin información adicional. |
| Vecinos | Cobertura (%) o densidad (plantas/m² o plantas/ha), especie y distancia en m opcionales, método y referencia espacial en la nota. |
| Procedencia | Eventos detallados declarados; vistas derivadas de ficha inicial o resumen semanal. La fecha de tratamiento de una ficha antigua permanece desconocida; un resumen conserva su intervalo. |
| Clima | Valores originales de NASA POWER para el centro de la finca, con null por variable faltante. Un cero de lluvia y una lluvia desconocida permanecen distintos. |

La bitácora ofrece cosecha, pérdida, plaga, tratamiento, fertilización y observación. Los campos opcionales vacíos permanecen desconocidos. Los eventos nuevos tienen fecha dentro de la campaña y no posterior a hoy. Las fechas de resúmenes importados conservan su precisión original. La app no incorpora efectos calibrados sobre rendimiento para las observaciones adicionales.

## Almacenamiento y migración

`fincaV3` es la escritura conjunta de finca, lotes, todas las campañas, registros, eventos detallados, agua y clima. Se lee primero V3; si no existe se lee V2, y después las claves antiguas. `fincaV2` y las claves antiguas se conservan como respaldo. La copia suelta de `dev/proyectos/field_shift` no se sincronizó.

Los identificadores existentes se conservan. Las nuevas campañas y eventos reciben identificadores aleatorios. Los riegos V2 solo se asignan si lote y fecha identifican una única campaña; los ambiguos permanecen sin campaña y se cuentan en la revisión del paquete. Los IDs de los resúmenes se derivan de ficha/campaña/semana y no crean aplicaciones detalladas duplicadas. Editar el resumen original actualiza esa vista.

Cerrar una campaña exige una fecha no anterior a sus registros. No borra eventos. La siguiente siembra no puede preceder al cierre anterior. El GeoJSON estricto emite cada lote físico una sola vez e incluye los IDs de sus campañas. Los lotes disponibles siguen visibles en el mapa. Los errores de geometría existentes se conservan: editar metadatos sin mover el contorno permite corregir o completar la ficha, mientras la exportación estricta sigue exigiendo geometría válida.

## Intercambio

El sobre usa `esquema: field-shift-finca`, `version: 1`. `datos` contiene el estado V3; `bitacora` reúne eventos detallados y vistas de resúmenes; `geografico` contiene los lotes y su validación; `procedencia` documenta unidades, fuentes y restricciones; `revision` informa lluvia faltante, riegos no asignados, geometrías y perfiles pendientes.

Los contornos originales se conservan en `datos.lotes`, incluso cuando su geometría no puede presentarse como un anillo simple. La exportación completa puede contener advertencias espaciales; la exportación GeoJSON estricta de Finca continúa rechazándolas. No se presenta como dato validado para entrenar el modelo.

Solo se señalan como candidatos reportados maíz con variedad escrita `ICTA B-5` y frijol `ICTA Ligero`. Los IDs son provisionales, sujetos a confirmación. Una variedad desconocida, tomate o café no se sustituyen por otra especie. Esto no cambia el catálogo del balance FAO actual.

La revisión de importación valida versión, fechas de calendario, IDs únicos, referencias, intervalos de campaña, unidades y cantidades. Los datos idénticos se mantienen una sola vez. Un mismo ID con contenido diferente rechaza toda la operación; no se resuelve sobrescribiendo. Solo se combinan datos de la misma finca, o se inicializa una instalación vacía desde la API. La pantalla de importación está en Ajustes de una finca configurada. El estado se guarda en una sola escritura; si falla la escritura se restablece la vista previa anterior en memoria.

## Verificación

Pruebas dirigidas cubren migración V2, campañas sucesivas en un lote, aislamiento de riegos, dos plantaciones con riego artificial, cosechas parciales y pérdidas, observaciones con unidades, vistas semanales, alertas, importación repetida, conflictos y JSON inválido. Las pantallas tienen capturas de referencia revisadas. La comprobación en teléfono se realiza conservando las tres plantaciones reales sin riego y sin insertar cosechas o aplicaciones de prueba.

Comprobación real completada en Galaxy A14: cinco plantaciones conservadas (tres originales sin riego y dos adicionales con goteo/manual); selector por lote, aislamiento y cancelación de borrador, bitácora vacía tras cancelar, historial de cinco lotes, exportación confirmada y reapertura en frío. No se guardaron eventos ficticios. Evidencia local en `tmp/etapas-3-5-telefono/resultado.json`, desde la raíz del repositorio.
