# Glosario en lenguas mayas (borrador)

**Estado: borrador. Ningún hablante nativo lo ha revisado.** Las palabras deben revisarlas hablantes y la Academia de Lenguas Mayas de Guatemala (ALMG) antes de usarse con productores. Ortografía ALMG, con la glotal escrita como apóstrofo. Una celda vacía significa «sin borrador»: la app muestra el español.

El código está en `lib/lenguas.dart` (tabla `glosario`); este archivo es su registro de fuentes.

## Cotejo

Se cotejó cada término con los diccionarios del equipo en `field-shift-guatemala/diccionarios/` (`kiche.md`, `qeqchi.md`, `kaqchikel.md`, `mam.md`, `palabras-por-buscar.md`), de solo lectura. No se encontraron archivos csv/json/jsonl/tsv de diccionario; el modelo de traducción del equipo no se usó para generar texto.

Resumen de las 45 celdas con palabra:

- **Verificado exacto: 15** (K'iche' 7, Kaqchikel 2, Q'eqchi' 6).
- **Verificado con variante de escritura: 3** (se conserva la ortografía del encargo): Kaqchikel *kinäq'* (el archivo: *kinaq'*), Kaqchikel *ixkoya'* (*xkoya'*), Q'eqchi' *kape'* (*kape*).
- **Distinto en el diccionario: 0.**
- **Sin verificar: 27.** El mam no tiene fuente en el equipo (`mam.md` es una plantilla sin traducciones).

Referencias de página: las de cada archivo (K'iche': Vásquez García 2017; Q'eqchi': Cu Cab y Cu Cab 1998; Kaqchikel: Chacach Cutzal 1990). En `kaqchikel.md` *kinaq'* y *kape* figuran como «cognado» y *ya'* como «por verificar»; *xkoya'* por contexto.

| Español | K'iche' | Kaqchikel | Q'eqchi' | Mam |
|---|---|---|---|---|
| maíz | ixim: verificado (kiche.md p. 93) | ixim: sin verificar | ixim: verificado (qeqchi.md p. 268) | ixi'n: sin verificar |
| frijol | kinaq': verificado (p. 93) | kinäq': variante, el archivo trae kinaq' (pp. 64-66) | kenq': verificado (p. 238) | chenaq': sin verificar |
| tomate | pix: verificado (p. 92) | ixkoya': variante, el archivo trae xkoya' (p. 64) | pix: sin verificar (no está en qeqchi.md) | xko'ya': sin verificar |
| café | kape: verificado (p. 114, bebida; la planta es qakoj) | kape: verificado (p. 66, bebida) | kape': variante, el archivo trae kape (p. 208) | kape: sin verificar |
| banano | saq'ul: sin verificar | saq'ul: sin verificar | tul: sin verificar | (vacío) |
| agua | ja': verificado (p. 105) | ya': verificado (p. 66; el archivo lo marca «por verificar») | ha': verificado (p. 181) | a': sin verificar |
| lluvia | jab': verificado (p. 105) | jäb': sin verificar | hab': verificado (p. 266) | jb'al: sin verificar |
| tierra / suelo | ulew: verificado (p. 81, derivada de «piocha») | ulew: sin verificar | ch'och': verificado (p. 326) | tx'otx': sin verificar |
| hoy | (vacío) sin borrador: se retiró *kamik* porque el diccionario del equipo solo lo trae como «morir» | wakami: sin verificar | anaqwan: sin verificar | ja'la: sin verificar |
| siembra | tiko'n: sin verificar (kiche.md solo propone *tikonik*) | tiko'n: sin verificar (trae *ajtiko'n*, agricultor) | awimq: sin verificar (trae *awk* «sembrar» y *awleb'aal*) | awal: sin verificar |
| sombra | mu'j: sin verificar | muj: sin verificar | mu: sin verificar | muj: sin verificar |
| cosecha (de maíz) | jach': sin verificar (kiche.md solo propone *k'ob'anik*) | jach': sin verificar | q'olok: verificado (p. 208, cosechar milpa) | (vacío) |

## Fuentes (de `modelo_lenguas_mayas/CREDITOS.md` del equipo, y de sus diccionarios)

- Diccionario Kaqchikel (Webonary, SIL International).
- Talking Dictionaries de k'iche', kaqchikel, q'eqchi' y mam (Living Tongues Institute y comunidades lingüísticas de la ALMG).
- Diccionario Mam–Español de Comitancillo (Ikeda y Pérez Morales, 2001).
- Tablas verificadas del equipo Field Shift (`diccionarios/*.md`), con las fuentes por página: Vásquez García (2017) para K'iche'; Cu Cab y Cu Cab (1998) para Q'eqchi'; Chacach Cutzal (1990) para Kaqchikel.

Las palabras sin verificar vienen del encargo del equipo, no de una fuente consultada aquí.
