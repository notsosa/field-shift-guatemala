# Demo del piloto: la app Field Shift (copia `app/V01-keu`)

Guion para mostrar la app en el navegador, con una lista de pruebas al final. La app es la de nuestro compañero, con los arreglos de la rama `modelo-keu` (ver el README de `app/V01-keu`). Los pasos de abajo se ensayaron en Chrome (ventana de teléfono, 390 px) el 15 de noviembre de 2026 y funcionan en cualquier fecha, porque las fechas de siembra se dan en días antes del día de la demo.

## Antes de empezar

```bash
cd app/V01-keu
flutter pub get
flutter build web --release
python -m http.server 8787 -d build/web
```

Abre `http://localhost:8787` en Chrome con internet: al guardar la parcela la app baja el clima de NASA POWER y tarda unos 5 a 10 segundos en mostrar la pantalla **Hoy**. Para empezar de cero: Ajustes, "Borrar todos los datos", Borrar.

## Qué muestra y qué no muestra "Ver un ejemplo"

El botón de la bienvenida carga un frijol sembrado hace 38 días en Chiquimula (`14.8250`, `-89.5312`, el punto de la finca), con goteo, fertilización ya registrada y un registro de hace 9 días (2 riegos, plaga leve, "Mosca blanca"). Sirve para ver rápido las pantallas y un registro con riego. **No** sirve para: el aviso de fertilizar (el ejemplo ya está fertilizado), café ni roya (es frijol), ni un maíz. Para esas escenas hay que crear la plantación a mano, como abajo.

## Guion

### 1. Maíz en Chiquimula, con riego

1. En la bienvenida toca **Empezar**. En "Tu parcela" escribe el nombre "Chiquimula", latitud `14.80` y longitud `-89.54`, y toca **Continuar**. No uses "Usar mi ubicación": el navegador puede negarla.
2. En "Plantación" deja **Maíz**, ciclo **120 días**, suelo **Franco**. Toca la fecha de siembra: se abre una rueda de día, mes y año; gira el día y el mes hasta **hace 50 días** (el inicio de las lluvias en Chiquimula es hacia mediados de mayo; si la demo no cae en esa época, hace 50 días mantiene el maíz en pleno desarrollo) y toca **Listo**. En Riego elige **Goteo**. Toca **Guardar**.
3. En **Hoy** debe verse (ensayado con el maíz de hace 50 días): "Maíz · Chiquimula", un porcentaje de agua disponible, la etapa **Desarrollo**, "Cosecha: en 70 días", "Rendimiento 100%", la gráfica de los últimos 14 días con la lluvia y la necesidad de la semana, y en "Por hacer" el registro semanal pendiente y **Momento de fertilizar** (hay riego, y por eso el aviso sale aunque no llueva). Di: "es una estimación del agua en la raíz, con el clima de NASA de este punto".
4. Si la siembra fuera de hace más de 120 días, Hoy dice "Ciclo terminado", sin fila de cosecha, y el rendimiento queda fijo. Es un buen momento para decir que después de cosechar ya no baja.
5. Abre **Registros**, toca **Registro semanal** (o el **+**): sube "Veces que regaste" a 3 con el **+**, deja la plaga en Ninguna y toca **Guardar**. En la lista debe aparecer la fecha de hoy y "3 riegos". Vuelve a Hoy: el aviso de registro pendiente ya no está y el agua disponible refleja los riegos.

### 2. Café con roya

1. Ajustes, **Borrar todos los datos**, Borrar. Repite la parcela (`14.80`, `-89.54`).
2. En "Plantación" toca **Café** (la fecha es la de la última floración; puedes dejar la de hoy). En Riego deja **Sin riego**. En "Manejo" enciende **Plaga reciente**: aparece "Tipo de plaga" con Roya, Minador, Antracnosis y Otra. Elige **Roya** y **Guardar**.
3. En Hoy debe verse (ensayado): "Café · Chiquimula", agua disponible, etapa **Establecido**, sin fila de cosecha ni de rendimiento (el café es perenne y no tiene Ky), y en "Por hacer" **Plaga reportada** y el registro pendiente. Di: "la app registra qué plaga es; no la predice ni dice cuándo aplicar".
4. En **Registros**, **Registro semanal**: como el café no tiene riego no aparece "Veces que regaste". Elige plaga **Media** y aparece "Tipo de plaga": toca **Roya** y **Guardar**. En la lista debe verse "Sin riego · plaga media (roya)".
5. La app guarda un registro por día (si guardas otro el mismo día, reemplaza al anterior). Para enseñar dos registros en una misma sesión, usa el ejemplo: ya trae el de hace 9 días con 2 riegos; agrega el de hoy con 0 riegos, y la lista muestra uno con riego y otro "Sin riego".

### 3. Fertilizar solo con agua

El aviso depende del clima real del día, así que no se puede forzar en vivo. Con un maíz o un frijol en etapa de desarrollo (sembrado hace 30 a 60 días) y sin fertilización registrada, la regla es: si hay riego o cayó lluvia (1 mm o más) en los últimos 7 días, sale "Momento de fertilizar"; si no, sale "Fertilizar: en espera", con la nota de que no hay lluvia registrada en los datos disponibles (los últimos días aún no se publican). Para verlo en una plantación **Sin riego**, hay que probar en una semana sin lluvia; en el ensayo de hoy llovió 10 mm en la semana, así que salió el recordatorio normal. Di: "así lo hace el productor: sin lluvia no abona".

### 4. Frijol con "Trips de las flores" y su fuente

1. Con el ejemplo cargado (frijol en Chiquimula), abre **Registros**, el **+**, y toca **Media** en Plaga. Aparece "Tipo de plaga": Trips de las flores (*Megalurothrips usitatus*), Mosca minadora (*Liriomyza huidobrensis*, *Liriomyza sabaziae*) y Otra, con la nota fija de que un registro documentado no significa presencia en la parcela.
2. Elige **Trips de las flores** y **Guardar**. En la lista sale "plaga media (trips de las flores)" con un botón (i). Tócalo: se ve la tarjeta de la fuente. Daña flores y vainas; muestreos 2022 en Petén, El Progreso, Zacapa y Chimaltenango y un estudio en San Jerónimo, Baja Verapaz; fuente ICTA ("Una nueva plaga en el cultivo de frijol en Guatemala"), con su dirección; y el límite del propio registro: no se extrapolan sus porcentajes de daño a otras localidades.
3. Di: "estas plagas no son una predicción ni una lista de lo que hay en tu parcela: son los registros locales que nuestro equipo encontró con fuente, con su lugar y su fecha, y cada uno dice hasta dónde vale".
4. Qué son y qué no son las listas: salen de 12 registros cultivo-taxón del equipo (maíz 1, frijol 3, cebolla 2, brócoli 3, lechuga 3). Ajonjolí y papa no tienen ninguno en este conjunto estricto y por eso solo ofrecen "Otra"; la app dice, con las palabras de la investigación, que sí tienen plagas documentadas (11 entradas en papa y 7 en ajonjolí, sin ser registros confirmados) y que su omisión no es ausencia de plagas ni riesgo cero. El café conserva roya, minador y antracnosis, marcados como "reportado por un caficultor", no como registro con fuente. No hay umbrales, ni recomendación de tratamiento, ni frecuencia.

## Lista de pruebas

| Qué probar | Resultado esperado |
|---|---|
| Parcela con `14.80`, `-89.54` y Continuar | Pasa a "Plantación"; al guardar, Hoy baja el clima (5 a 10 s) y muestra el nombre de la parcela |
| Ajustes después de guardar | Muestra "Chiquimula 14.8000, -89.5400", la elevación de la celda de NASA y el cultivo con su fecha |
| Coordenadas fuera de rango (`95`, `-89`) | Mensaje de coordenadas inválidas y no avanza |
| Cultivo Café, Plaga reciente encendida | Aparece "Tipo de plaga" con Roya, Minador, Antracnosis y Otra |
| Cultivo Frijol, Plaga reciente encendida | "Tipo de plaga" con Trips de las flores, Mosca minadora y Otra; cada plaga con su botón (i) de fuente y la nota "Un registro documentado en Guatemala no significa que la plaga esté presente en esta parcela" |
| Cultivo Ajonjolí o Papa, Plaga reciente encendida | Solo "Otra", la línea "El equipo aún no tiene un registro local confirmado de plagas para este cultivo" y el conteo de la revisión documental (papa 11 entradas, ajonjolí 7) con "su omisión no representa ausencia de plagas ni riesgo cero"; sin botón de fuente |
| Brócoli o Lechuga en English | Nombres como "Diamondback moth", "White grub", "Aphid", "Thrips" sin cortarse |
| Registro con plaga y tipo (café) | La lista muestra "plaga media (roya)" |
| Cambiar a English en Ajustes | Los textos cambian, incluidos los tipos de plaga ("Rust", "Leaf miner", "Anthracnose", "Other") |
| Clima con 3 o 4 días de retraso (lo normal) | Hoy no baja la precisión por eso; si faltan más de 5 días de clima, o hay un hueco o lluvia faltante en la última semana, sí baja |
| Maíz sembrado hace más de 120 días | "Ciclo terminado" y el rendimiento no cambia de un día a otro |
| Recargar la página | La parcela, la plantación y los registros siguen ahí |
| Sin internet al abrir | La app abre con el clima guardado y avisa que no se pudo actualizar |

## Qué mostrar en la demo

- Para la demo, muestra la app, la comparación de rotaciones por agua y la matriz de sucesión.
- Presenta el consejo de la fecha de siembra como un límite que encontramos (el simulador dice que esperar gana y AquaCrop lo contradice), no como una recomendación.

## Lo que la app no hace

- No predice plagas ni dice cuándo aplicar; solo las registra. Las plagas listadas son registros documentados en Guatemala (lugar y fecha propios), no la presencia en tu parcela; no hay frecuencias ni umbrales.
- Su lluvia viene de NASA POWER (celda de unos 50 km, 3 o 4 días de retraso), no de IMERG ni de ERA5 como nuestro modelo; en el oriente de Guatemala puede estar sobreestimada. Los últimos días sin publicar se estiman con lluvia cero, así que una lluvia reciente puede no aparecer todavía.
- Usa un solo número de curva, un Ky único por cultivo y parámetros de café y tomate citados de memoria (por verificar). El café no tiene fecha de cosecha ni rendimiento.
- No registra la lluvia que el productor ve: solo riegos, plaga y abono.
- Un registro por día y una sola plantación por parcela. No hay red neuronal.
- Sin validar en campo: apoya, no reemplaza, el criterio del finquero.

## Café en el modelo (no en la app)

El modelo de la rama `modelo-keu` ya incluye café como cultivo perenne, con sombra como entrada, avisos con fuente (roya, minador, antracnosis, abono) y una recomendación de riego medida contra una regla. La app no cambió: sus textos, su café y sus avisos siguen como están descritos arriba. Resultados y límites en `proyecto/resultados-modelo-keu.md`, sección "Café: cultivo perenne, sombra, avisos y recomendación de riego".

## Cómo se conecta con nuestro modelo

La app es el asesor del día a día de una plantación: balance de agua FAO-56 con aviso de riego, plaga y abono. Nuestro modelo de la rama `modelo-keu` responde la pregunta de antes de sembrar: qué rotación y qué fecha de siembra convienen, con 24 años de historia (`proyecto/resultados-modelo-keu.md`, con la matriz de las 42 sucesiones entre siete cultivos). Para ver si la red de política del equipo decide mejor que nuestro simulador, se usa el protocolo de `proyecto/comparacion-modelos.md`: mismos sitios, años y juez, con la regla de información fijada de antemano.
