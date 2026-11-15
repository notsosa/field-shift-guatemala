# Demo del piloto: la app Field Shift (copia `app/V01-keu`)

Guion para mostrar la app en el navegador, con una lista de pruebas al final. La app es la de nuestro compañero, con los arreglos de la rama `modelo-keu` (ver el README de `app/V01-keu`).

## Antes de empezar

```bash
cd app/V01-keu
flutter pub get
flutter build web --release
python -m http.server 8787 -d build/web
```

Abre `http://localhost:8787` en Chrome, con wifi (el clima se baja de NASA POWER al guardar la parcela). Para empezar de cero: Ajustes, "Borrar todos los datos". El teléfono simulado queda mejor con la ventana angosta (unos 400 px).

## Guion

### 1. Maíz en Chiquimula, con riego

1. En la bienvenida toca **Empezar**. En "Tu parcela" escribe nombre "Chiquimula", latitud `14.80`, longitud `-89.54` y toca **Continuar**. No uses "Usar mi ubicación": el navegador puede negarla. (Punto alternativo, el de la finca: `14.8250`, `-89.5312`; es el que usa "Ver un ejemplo".)
2. En "Plantación" elige **Maíz**, suelo **Franco**, y como fecha de siembra el inicio de las lluvias (hacia mediados de mayo). Riego **Goteo**, temporada **Auxilio**. Deja "Plaga reciente" apagada y toca **Guardar**.
3. En **Hoy** muestra el porcentaje de agua disponible, la etapa, la cosecha y el rendimiento. Dilo así: "es una estimación del agua en la raíz, calculada con el clima de NASA de este punto".
4. Si hoy ya pasó la cosecha (ciclo de 120 días), la app dice "Ciclo terminado": el rendimiento queda fijo y ya no cae por los días después de cosechar. Para ver un cultivo activo, usa una siembra de hace 40 a 60 días.
5. En **Registros**, toca **+**: "Veces que regaste" 3, plaga **Ninguna**, "Fertilizaste" apagado, **Guardar**. Debe aparecer en la lista con "3 riegos" y la reserva de agua en Hoy sube si el clima de esos días fue seco.

### 2. Café con roya

1. Ajustes, **Borrar todos los datos**, y repite la parcela (`14.80`, `-89.54`).
2. En "Plantación" elige **Café**. La fecha es la de la última floración. Riego **Ninguno**. Enciende **Plaga reciente**: aparece "Tipo de plaga" con Roya, Minador, Antracnosis y Otra. Elige **Roya** y **Guardar**.
3. En Hoy debe salir el aviso "Plaga reportada". Di: "la app registra qué plaga es; no la predice ni dice cuándo aplicar".
4. En **Registros**, **+**: plaga **Media**, tipo **Roya**, sin riego (el café no tiene riego en este caso, así que la pregunta de riegos no aparece), **Guardar**. En la lista debe verse "plaga media (roya)".
5. Para mostrar dos registros en una misma sesión, usa **Ver un ejemplo** (frijol, `14.8250`, `-89.5312`): ya trae un registro de hace 9 días con 2 riegos. Agrega el de hoy sin riegos (semana sin lluvia). La app guarda un registro por día, así que dos registros propios exigen dos días distintos.

### 3. Fertilizar solo con agua (frijol o maíz en desarrollo)

Con un maíz o frijol en etapa de desarrollo, sin fertilización registrada: si hubo lluvia en los últimos 7 días o hay riego, sale "Momento de fertilizar"; si no, "Fertilizar: en espera". Di: "así lo hace el productor: sin lluvia no abona".

## Lista de pruebas

| Qué probar | Resultado esperado |
|---|---|
| Parcela con `14.80`, `-89.54` y Continuar | Pasa a "Plantación"; al guardar, Hoy baja el clima y muestra el nombre de la parcela |
| Coordenadas fuera de rango (`95`, `-89`) | Mensaje de coordenadas inválidas y no avanza |
| Cultivo Café, Plaga reciente encendida | Aparece "Tipo de plaga" con cuatro opciones |
| Cultivo Maíz o Frijol, Plaga reciente encendida | No aparece "Tipo de plaga" (lista pendiente del compañero) |
| Registro con plaga y tipo | La lista muestra "plaga media (roya)", por ejemplo |
| Cambiar a English | Todos los textos cambian, incluido el tipo de plaga ("Rust", "Leaf miner") |
| Día con clima faltante | Hoy dice "N días estimados" y la precisión baja si caen en la última semana |
| Sin lluvia en 7 días y sin riego, cultivo en desarrollo | "Fertilizar: en espera" en vez de "Momento de fertilizar" |
| Recargar la página | La parcela, la plantación y los registros siguen ahí |
| Sin internet | La app abre con el clima guardado y avisa que no se pudo actualizar |

## Lo que la app no hace

- No predice plagas ni dice cuándo aplicar; solo las registra.
- Su lluvia viene de NASA POWER (celda de unos 50 km, 3 o 4 días de retraso), no de IMERG ni de ERA5 como nuestro modelo; en el oriente de Guatemala puede estar sobreestimada.
- Usa un solo número de curva, un Ky único por cultivo y parámetros de café y tomate citados de memoria (por verificar).
- Un registro por día y una sola plantación por parcela. No hay red neuronal.
- Sin validar en campo: apoya, no reemplaza, el criterio del finquero.

## Cómo se conecta con nuestro modelo

La app es el asesor del día a día de una plantación: balance de agua FAO-56 con aviso de riego, plaga y abono. Nuestro modelo de la rama `modelo-keu` responde la pregunta de antes de sembrar: qué rotación y qué fecha de siembra convienen, con 24 años de historia (`proyecto/resultados-modelo-keu.md`, con la matriz de las 42 sucesiones entre siete cultivos). Para ver si la red de política del equipo decide mejor que nuestro simulador, se usa el protocolo de `proyecto/comparacion-modelos.md`: mismos sitios, años y juez, con la regla de información fijada de antemano.
