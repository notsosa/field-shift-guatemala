// Tablas en Markdown del documento proyecto/resultados-modelo-keu.md para la Tarea 33, generadas SOLO desde los artefactos (ningún número escrito a mano).
// Uso: node scripts/gpu/doc_tables.mjs <pieza>   con <pieza> = recommender | historical | timing | screening | v3 ; escribe en la salida estándar.
import fs from 'node:fs';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { root, readJson } from '../compare/loss_decision_core.mjs';

const d = (f) => readJson(path.join(root, 'web/data', f));
const OLD = '4778afc'; // commit con los artefactos de la Tarea 31/32 (entrenamiento en JS)
const gitJson = (f) => JSON.parse(execFileSync('git', ['-C', root, 'show', `${OLD}:web/data/${f}`], { encoding: 'utf8', maxBuffer: 1 << 28 }));
const f3 = (v) => (v == null ? '' : v.toFixed(3));
const sg = (v) => (v == null ? '' : `${v >= 0 ? '+' : ''}${v.toFixed(3)}`);
const SEEDS = [17, 29, 43];
const PRI = ['typical', 'cautious'];
const PN = { typical: 'típico', cautious: 'cauto' };

function row(label, m, n, opts = {}) {
  const gep = opts.noGep ? '' : `${m.win} / ${m.tie} / ${m.loss}`;
  return `| ${label} | ${f3(m.chosenMean)} | ${opts.noGain ? '' : sg(m.meanGainVsRule)} | ${gep} | ${f3(m.meanRegret)} | ${f3(m.p10)} | ${f3(m.worst)} | ${m.executable}/${n} | ${m.below05}/${n} | ${m.departsFromRule}/${n} |`;
}
const HEAD = '| Política | Media | Ganancia | G / E / P | Arrepent. | P10 | Peor | Ejecut. | < 0.5 | Se aparta |\n|---|---|---|---|---|---|---|---|---|---|';

function table(ev, setName) {
  const ref = ev.decision.reference[setName];
  const n = ref.n;
  const L = [HEAD];
  L.push(row('Regla agronómica', ref.ruleRecomputed, n));
  const o = ref.oracle;
  L.push(`| Mejor opción en retrospectiva (techo) | ${f3(o.chosenMean)} | | | ${f3(0)} | | | ${Math.round(o.executableShare * n)}/${n} | ${o.below05}/${n} | ${o.departsFromRule}/${n} |`);
  for (const p of PRI) L.push(row(`Simulador como política (${PN[p]})`, ref.simulatorPolicy[p], n));
  for (const s of SEEDS) for (const p of PRI) L.push(row(`**Red que recomienda**, semilla ${s}, ${PN[p]}`, ev.decision.perSeed[setName][s][p], n));
  for (const [k, name] of [['mlp', 'red v2'], ['elm', 'ELM v2']]) for (const s of SEEDS) for (const p of PRI) L.push(row(`Predecir y elegir: ${name}, semilla ${s}, ${PN[p]} (copiado)`, ref.predictThenChoose[s][k][p], n));
  return L.join('\n');
}

function summaryLine(ev, setName) {
  return PRI.map((p) => { const s = ev.decision.summary[setName][p].chosenMean; return `${PN[p]} ${f3(s.mean)} (${f3(s.min)}–${f3(s.max)})`; }).join('; ');
}

function wins(ev, setName) { // en cuántas de las 6 combinaciones la ganancia media sobre la regla es > 0 (y en cuántas hay más ganados que perdidos)
  let pos = 0, more = 0, tot = 0;
  for (const s of SEEDS) for (const p of PRI) { const m = ev.decision.perSeed[setName][s][p]; tot++; if (m.meanGainVsRule > 1e-9) pos++; if (m.win > m.loss) more++; }
  return { pos, more, tot };
}

function oldNew() {
  const o = gitJson('recommender_eval.json'), n = d('recommender_eval.json');
  const out = [];
  for (const [setName, title] of [['reserved2022_2024', 'Años reservados 2022–2024 (27 casos)'], ['years2019_2024', 'Adicional 2019–2024 (54 casos)']]) {
    const nn = n.decision.reference[setName].n;
    out.push(`**${title}.** Media de lo elegido (ganancia sobre la regla; ganados / empatados / perdidos; se aparta de la regla). Regla: ${f3(n.decision.reference[setName].ruleRecomputed.chosenMean)}; techo: ${f3(n.decision.reference[setName].oracle.chosenMean)}.\n`);
    out.push('| Semilla | Prioridad | Antes (JS) | Ahora (GPU) |\n|---|---|---|---|');
    for (const s of SEEDS) for (const p of PRI) {
      const a = o.decision.perSeed[setName][s][p], b = n.decision.perSeed[setName][s][p];
      const cell = (m) => `${f3(m.chosenMean)} (${sg(m.meanGainVsRule)}; ${m.win}/${m.tie}/${m.loss}; ${m.departsFromRule}/${nn})`;
      out.push(`| ${s} | ${PN[p]} | ${cell(a)} | ${cell(b)} |`);
    }
    out.push('');
  }
  return out.join('\n');
}

const pieces = {
  recommender() {
    const n = d('recommender_eval.json'), m = n.meta;
    const best = m.selected;
    const T = SEEDS.map((s) => { const t = n.training[s]; return `| ${s} | ${f3(t.valFitness.first)} / ${f3(t.valFitness.best)} / ${f3(t.valFitness.last)} | ${t.bestGen} | ${f3(t.trainBest.first)} / ${f3(t.trainBest.last)} | ${t.seconds.toFixed(1)} | ${Math.round(t.scenarioEvalsPerSecond)} |`; });
    const w27 = wins(n, 'reserved2022_2024'), w54 = wins(n, 'years2019_2024');
    const lo = (setName, key) => {
      const v = []; for (const s of SEEDS) for (const p of PRI) v.push(n.decision.perSeed[setName][s][p].chosenMean);
      const ptc = []; for (const s of SEEDS) for (const k of ['mlp', 'elm']) for (const p of PRI) ptc.push(n.decision.reference[setName].predictThenChoose[s][k][p].chosenMean);
      return key === 'net' ? [Math.min(...v), Math.max(...v)] : [Math.min(...ptc), Math.max(...ptc)];
    };
    const line = (setName, label, nn) => {
      const [a, b] = lo(setName, 'net'), [c, e] = lo(setName, 'ptc'), w = wins(n, setName), r = n.decision.reference[setName];
      return `- ${label} (n = ${nn} casos): la red que recomienda queda entre ${f3(a)} y ${f3(b)} de rendimiento relativo medio, frente a ${f3(r.ruleRecomputed.chosenMean)} de la regla y ${f3(r.oracle.chosenMean)} del techo; mejora la media de la regla en ${w.pos} de las 6 combinaciones de semilla y prioridad, y tiene más casos ganados que perdidos en ${w.more} de 6. Las políticas de predecir y elegir (red v2 y ELM v2) van de ${f3(c)} a ${f3(e)}: la red que recomienda ${b >= e ? 'llega a las más altas de ellas' : `no alcanza a las más altas (${f3(e)}); la mejor semilla (${f3(b)}) queda ${b >= c ? 'dentro de su rango' : 'por debajo de todas'}`}.`;
    };
    const dep = (list) => { const c = {}; list.forEach((x) => { const k = `${x.rule} → ${x.chose}`; c[k] = (c[k] ?? 0) + 1; }); return Object.entries(c).sort((a, b) => b[1] - a[1]).map(([k, v]) => `${k}: ${v}`).join('; '); };
    const s17 = n.decision.perSeed.years2019_2024['17'];
    return `## Red que recomienda (prioridad del agricultor, estado del lote, entrenada por el resultado de la decisión)

15 de noviembre de 2026. Es la tarea de la pérdida del maíz de las condiciones comunes (\`proyecto/condiciones-comunes.md\`), pero ahora una red elige directamente la acción en vez de predecir y luego elegir. Todo es aditivo: el simulador, las redes v2 y sus resultados no cambian. Los números salen de \`web/data/recommender_eval.json\` (commit del simulador \`${m.simulatorCommit}\`); las filas de las políticas de "predecir y elegir" están copiadas de \`web/data/aligned_eval.json\`, no recalculadas. **Desde la Tarea 33 la red se entrena en GPU (otro flujo aleatorio que la versión en JS de la Tarea 31); los números de esta sección son los del reentrenamiento y la comparación con los anteriores está en la sección "Entrenamiento en GPU y más datos y entradas".**

**Qué hace.** Para cada una de las 8 acciones (resembrar uno de siete cultivos o dejar el terreno) la red da una corrección; el puntaje es 1 si la acción es la de la regla agronómica (0 si no) más tanh(corrección), y se recomienda el mayor puntaje (empate: la acción de la regla). Al inicio la corrección vale 0 y la red recomienda exactamente lo que la regla (hay una prueba). Tres ideas tomadas del diseño del compañero: la **prioridad del agricultor** como entrada (0 = rendir más en un año típico, 1 = no perder en un año malo), el entrenamiento por **cómo salió la decisión**, y **más información del lote** el día de la decisión.

**Diseño (fijado antes de ver los casos de prueba).**
- Entradas (${m.inputNames.length}): día del año, días desde el inicio de lluvias (la siembra), días al 15 de noviembre y al fin del año agrícola, día de la pérdida, lluvia y ET₀ de los últimos 7 y 28 días y desde el 1 de abril, racha seca más larga de los últimos 28 días, temperatura media de los últimos 28 días, balance antecedente acotado a 150 mm (la lógica de \`storeProxy\` del emulador, con Kc del maíz hasta el día de la pérdida y suelo desnudo, Kc = kc.ini del maíz, después), agua disponible del suelo (mm por m), número de curva del cultivo, altitud; la prioridad; y por acción: one-hot de 8, ciclo nominal en días, Kc medio, profundidad de raíz, p, Ky y si el ciclo nominal cabe antes del fin del año agrícola. Solo se usa el clima hasta el día de la decisión (el día de la pérdida, con el clima de ese día); una prueba altera todo lo posterior y ninguna entrada cambia.
- **No hay entradas de finanzas ni de historial de plagas o fertilizante: el proyecto no tiene esos datos y no se inventaron.**
- Red: ${m.design.layers.join(' → ')} (tanh en las ocultas, salida en cero al inicio), ${m.parameterCount} parámetros.
- Entrenamiento sin retropropagación: estrategia de evolución (μ, λ), población ${m.design.popSize}, ${m.design.parents} padres, mutación gaussiana σ = ${m.design.sigma}, elitismo ${m.design.elite}, ${m.design.generations} generaciones; en cada generación ${m.design.batch} escenarios de entrenamiento (sorteados con el generador de torch) con las dos prioridades. Aptitud: prioridad 0 = media de y; prioridad 1 = media de y − max(0, 0.5 − y); la aptitud es el promedio de las dos. El mejor de cada generación se puntúa con toda la validación y se guarda el mejor. Semillas ${SEEDS.join(', ')}. Código: \`scripts/gpu/train_recommender.py\` sobre el núcleo \`scripts/gpu/es_core.py\` (una operación por lotes por generación: 32 individuos × 512 escenarios × 2 prioridades × 8 acciones).
- Datos: tabla de escenarios calculada una vez con el simulador: entrenamiento ${m.scenarios.train} (20 puntos × años 2001–2016 × pérdida 30/45/60; arena, franco y arcilla en los puntos que no son piloto y el suelo del sitio en los pilotos), validación ${m.scenarios.val} (2017–2018), prueba ${m.scenarios.test} (los 3 pilotos, 2019–2024). Tiempo de la tabla: ${m.tableSeconds.toFixed(1)} s.
- Comprobación entre JS y PyTorch (\`jsVsTorchCheck\` en el artefacto): ${SEEDS.map((s) => `semilla ${s}, ${n.jsVsTorchCheck[s].rows} filas, diferencia máxima de puntaje ${n.jsVsTorchCheck[s].maxScoreDiff.toExponential(1)}, misma recomendación en ${n.jsVsTorchCheck[s].sameRecommendation}/${n.jsVsTorchCheck[s].rows}`).join('; ')}.

### Aprendizaje y tiempos

| Semilla | Validación primera / mejor / última | Mejor generación | Aptitud de entrenamiento primera / última | Tiempo (s) | Evaluaciones de escenario por s |
|---|---|---|---|---|---|
${T.join('\n')}

La aptitud de validación de la red inicial (igual a la regla) es ${f3(n.training[17].valFitness.initialIdentity)}; "primera" es la del mejor de la generación 0. Las tres semillas corrieron una tras otra en la GPU (${m.gpu.device}, torch ${m.gpu.torch}). Una evaluación de escenario = un individuo decidiendo un escenario con una prioridad. El checkpoint guardado en \`web/data/recommender_mlp.json\` es el de la semilla ${best.seed} (generación ${best.generation}, aptitud de validación ${f3(best.valFitness)}), la mejor en validación. Tiempo por recomendación (8 acciones, JS): ${m.msPerRecommendation.toFixed(3)} ms.

### Años reservados 2022–2024 (n = ${n.decision.reference.reserved2022_2024.n} casos)

Columnas: rendimiento relativo medio de lo elegido; ganancia media sobre la regla; casos ganados / empatados / perdidos (tolerancia 0.001); arrepentimiento medio frente a la mejor opción; percentil 10; peor caso; recomendaciones ejecutables; resultados por debajo de 0.5; casos en que se aparta de la regla.

${table(n, 'reserved2022_2024')}

Resumen de la red que recomienda entre las 3 semillas (media, mínimo y máximo de la media de lo elegido): ${summaryLine(n, 'reserved2022_2024')}.

### Adicional 2019–2024 (n = ${n.decision.reference.years2019_2024.n} casos)

Mismas columnas.

${table(n, 'years2019_2024')}

Resumen de la red que recomienda entre las 3 semillas (media, mínimo y máximo de la media de lo elegido): ${summaryLine(n, 'years2019_2024')}.

### En qué casos se aparta de la regla (semilla 17, ${n.decision.reference.years2019_2024.n} casos)

La lista completa, con lo que eligió en lugar de la regla y los rendimientos de cada una, está en \`recommender_eval.json\` (\`decision.perSeed.years2019_2024.17.*.departures\`). Resumen:

| Prioridad | Regla → elegido (casos) |
|---|---|
${PRI.map((p) => `| ${PN[p]} | ${dep(s17[p].departures)} |`).join('\n')}

### Lectura, sin rodeos

${line('reserved2022_2024', 'Años reservados 2022–2024', n.decision.reference.reserved2022_2024.n)}
${line('years2019_2024', 'Adicional 2019–2024', n.decision.reference.years2019_2024.n)}
- **Cambio frente a la versión en JS (Tarea 31):** con el flujo aleatorio de la GPU la red ya **no** mejora a la regla en las seis combinaciones (en la versión en JS sí lo hacía): ver la tabla "antes y ahora" de la sección de GPU. Es una variación entre corridas del mismo diseño, no un cambio de diseño; el resultado depende de la semilla.
- Con 27 y 54 casos (muchos casi iguales entre sí porque comparten sitio y año), los conteos ganados / empatados / perdidos son descriptivos; no se calculó significancia. Las semillas difieren entre sí, así que la diferencia entre prioridades no se puede ordenar con firmeza. (Mejora en ${w27.pos} de 6 con 27 casos y en ${w54.pos} de 6 con 54.)

### Límites

- **El juez es nuestro simulador**: "lo mejor" es lo que el simulador califica más alto, no una cosecha medida. Un segundo juez (AquaCrop) no se aplicó a estas recomendaciones.
- **Una decisión por caso** (la pérdida a los 30, 45 o 60 días y una resiembra 14 días después); no vuelve a decidir en cada fecha.
- **Sin finanzas, plagas ni fertilizante** como entradas: no hay esos datos en el proyecto. **El margen no se calcula** (no hay precios ni costos en el juez).
- 54 y 27 casos de tres pilotos. La red que recomienda se entrenó con 2001–2016 y se validó con 2017–2018; las redes de predecir y elegir se entrenaron sin 2019–2024. El año agrícola 2025 no se puede medir (la serie termina el 2025-12-31).
- Los escenarios de entrenamiento usan arena, franco y arcilla en 17 puntos y el suelo del sitio solo en los pilotos; la prueba usa el suelo del sitio.
- El diseño (tamaños, σ, generaciones, entradas, regla) no se tocó después de ver los números de prueba.
`;
  },

  historical() {
    const h = d('historical_check.json');
    const out = [];
    for (const ev of h.events) {
      out.push(`#### ${ev.id}`);
      out.push('| Punto (suelo), distancia | Pérdida (día) | Fecha de resiembra | Partición del año | Regla (rend.) | Red típica (rend.) | Red cauta (rend.) | Maíz resembrado (rend.) | Mejor (rend.) |\n|---|---|---|---|---|---|---|---|---|');
      for (const c of ev.cases) out.push(`| ${c.point} (${c.soil}), ${c.distanceKmToEventReference} km | ${c.lossDay} | ${c.resowDate} | ${c.split} | ${c.rule.action} (${f3(c.rule.relYield)}) | ${c.network.typical.action} (${f3(c.network.typical.relYield)}) | ${c.network.cautious.action} (${f3(c.network.cautious.relYield)}) | ${f3(c.documented.simulatorRelYieldIfMaizeResown)} | ${c.oracle.action} (${f3(c.oracle.relYield)}) |`);
      out.push('');
    }
    return out.join('\n');
  },

  timing() {
    const oldRec = gitJson('recommender_eval.json'), newRec = d('recommender_eval.json'), cof = d('coffee_eval.json').meta.timing, ev2 = d('emulator_v2_eval.json'), al = d('aligned_eval.json'), gc = d('gpu_checks.json');
    const rj = SEEDS.map((s) => oldRec.training[s].seconds), rg = SEEDS.map((s) => newRec.training[s].seconds);
    const cj = cof.jsEsBenchmark.projected150GenerationsSeconds, cg = SEEDS.map((s) => cof.gpuEs[s].seconds);
    const ej = ev2.elm.trainSeconds, eg = SEEDS.map((s) => al.meta.networks.elm.trainSecondsGpu[s]);
    const kj = SEEDS.map((s) => cof.elmSecondsJs[s]), kg = SEEDS.map((s) => cof.elmSeconds[s]);
    const L = (a) => a.map((v) => v.toFixed(2)).join(' / ');
    const sum = (a) => a.reduce((x, y) => x + y, 0);
    return `| Entrenamiento | JS antes (s) | GPU ahora (s) | Cómo se midió |
|---|---|---|---|
| Recomendador de pérdida de cultivo, evolución, 150 generaciones, semillas 17 / 29 / 43 | ${L(rj)} (3 procesos a la vez, ${oldRec.meta.wallSecondsAllSeeds.toFixed(0)} s en total) | ${L(rg)} (una tras otra, ${sum(rg).toFixed(1)} s en total) | JS: \`recommender_eval.json\` de la Tarea 31 (commit ${OLD}), medido; GPU: \`recommender_eval.json\` actual |
| Recomendador de riego del café, evolución, 150 generaciones | ${cj.toFixed(1)} por semilla (proyectado: ${cof.jsEsBenchmark.generationsMeasured} generaciones medidas y escaladas a 150) | ${L(cg)} | \`coffee_eval.json\` (\`timing.jsEsBenchmark\` y \`timing.gpuEs\`); el JS de 150 generaciones no se corrió completo |
| ELM del emulador v2 (1500 ocultas; filas de ajuste de v2) | ${ej.toFixed(1)} (semilla 42, \`emulator_v2_eval.json\`) | ${L(eg)} | JS: medido en la Tarea 26 con las mismas filas y configuración; GPU: \`aligned_eval.json\` (\`meta.networks.elm.trainSecondsGpu\`) |
| ELM del café (1500 ocultas) | ${L(SEEDS.map((s) => kj[SEEDS.indexOf(s)]))} | ${L(kg)} | \`coffee_eval.json\` (\`timing.elmSecondsJs\` y \`timing.elmSeconds\`) |
| ELM en una muestra de ${gc.elm.fitRows} filas de v2 (comprobación) | ${gc.elm.jsSeconds.toFixed(1)} | ${gc.elm.gpuSeconds.toFixed(2)} | \`gpu_checks.json\` |`;
  },

  screening() {
    const sc = readJson(path.join(root, 'scripts/emulator/v2_screening.json'));
    const NAMES = { base: 'base (v2 de hoy)', data: 'data (todos los candidatos)', inputs: 'inputs (60 000 + 16 entradas)', 'data+inputs': 'data+inputs' };
    const L = ['| Candidato | Entradas | Filas de entrenamiento | MSE de validación por semilla 17 / 29 / 43 | MSE medio | R² de validación medio: relYieldA / relYieldB / fit |', '|---|---|---|---|---|---|'];
    for (const [k, v] of Object.entries(sc.summary)) L.push(`| ${NAMES[k]} | ${v.inputs} | ${v.nTrainRows} | ${v.mseBySeed.map((x) => x.toFixed(4)).join(' / ')} | ${v.meanMSE.toFixed(4)} | ${v.meanR2.map(f3).join(' / ')} |`);
    const dd = sc.decision;
    L.push('');
    L.push(`Regla fijada antes de correr: gana el menor MSE de validación medio de las tres semillas; se adopta solo si mejora a \`base\` en al menos 2 % y ninguna salida empeora su R² de validación en más de 0.01 (medias de las tres semillas); si no, se conserva \`base\`. Resultado: gana **${dd.winner}** con un MSE medio de ${dd.meanMSEWinner.toFixed(4)} frente a ${dd.meanMSEBase.toFixed(4)} de \`base\` (mejora de ${(100 * dd.improvementOverBase).toFixed(1)} %); el menor cambio del R² de validación de una salida frente a \`base\` es ${sg(dd.worstR2ChangeVsBase)} (ninguna empeora). **Se adopta: ${dd.adopt ? 'sí' : 'no'}.**`);
    L.push('');
    L.push(`Métrica: error cuadrático medio de las salidas estandarizadas (con la desviación del entrenamiento de \`base\`) sobre las mismas filas de validación para todos los candidatos: las filas de 2017–2018 del reservorio de 60 000 (n = ${sc.meta.metric.match(/n = (\d+)/)[1]}). Receta: la de siempre (\`fit_network\`: embudo n → 64 → 32 → 16 → 3, ReLU, Adam 1e-3, lotes de 256, parada temprana con paciencia 10 sobre 2017–2018). Ninguna fila de prueba (años 2019–2024 y puntos reservados) se usó (\`testRowsUsed\`: ${sc.meta.testRowsUsed}). Épocas y tiempos de cada corrida: \`scripts/emulator/v2_screening.json\` (\`runs\`); las corridas más largas duran hasta ${Math.max(...sc.runs.map((r) => r.trainSeconds)).toFixed(0)} s en CUDA.`);
    const rel = (a, b) => `${(100 * (1 - sc.summary[b].meanMSE / sc.summary[a].meanMSE)).toFixed(1)} %`;
    L.push('');
    L.push(`Lectura: más filas sin más entradas (\`data\`) cambia el MSE de validación ${rel('base', 'data')} frente a \`base\` (reducción; un valor negativo sería un empeoramiento); las entradas nuevas con las mismas 60 000 filas (\`inputs\`) lo reducen ${rel('base', 'inputs')}; las dos juntas lo reducen ${rel('base', 'data+inputs')}.`);
    return L.join('\n');
  },

  v3() {
    const a = d('aligned_eval.json'), b = d('aligned_eval_v3.json'), rec = d('recommender_eval.json');
    const out = [];
    out.push('**Exactitud del emulador v2 → v3 por semilla**, sobre **las mismas filas de prueba** (las del reservorio de v2, para que la comparación sea directa). R² de relYieldA / relYieldB / fit; entre paréntesis, el RMSE de relYieldA.\n');
    out.push('| División (n) | Modelo | Semilla | v2 | v3 |\n|---|---|---|---|---|');
    for (const sp of ['newYears', 'newPoints']) for (const pol of ['mlp', 'elm']) for (const s of SEEDS) {
      const x = a.emulator.perSeed[s][pol][sp], y = b.emulator.perSeed[s].onV2Rows[pol][sp];
      out.push(`| ${sp === 'newYears' ? 'años nuevos' : 'puntos nuevos'} (${x.n}) | ${pol === 'mlp' ? 'red embudo' : 'ELM'} | ${s} | ${x.r2.map(f3).join(' / ')} (${f3(x.rmse[0])}) | ${y.r2.map(f3).join(' / ')} (${f3(y.rmse[0])}) |`);
    }
    out.push('');
    out.push(`En las filas de prueba **de todos los candidatos** (v3 se entrena con todos; ${b.emulator.perSeed[17].mlp.newYears.n} filas en años nuevos y ${b.emulator.perSeed[17].mlp.newPoints.n} en puntos nuevos; los del reservorio son un subconjunto) la red embudo da, en años nuevos, R² de relYieldA ${SEEDS.map((s) => f3(b.emulator.perSeed[s].mlp.newYears.r2[0])).join(' / ')} y en puntos nuevos ${SEEDS.map((s) => f3(b.emulator.perSeed[s].mlp.newPoints.r2[0])).join(' / ')} (semillas 17 / 29 / 43).`);
    out.push('');
    out.push('**Decisión tras perder el maíz con las redes v3 (predecir y elegir)**, mismas columnas que las demás tablas. Las filas de v2 se copian de `aligned_eval.json`, las de v3 vienen de `aligned_eval_v3.json`; regla, techo y simulador no cambian.\n');
    for (const [setName, title] of [['reserved2022_2024', 'Años reservados 2022–2024 (27 casos)'], ['years2019_2024', 'Adicional 2019–2024 (54 casos)']]) {
      const ref = a.decision.noSeed[setName], n = ref.n;
      out.push(`*${title}*\n`);
      out.push(HEAD);
      out.push(row('Regla agronómica', ref.rule, n));
      out.push(`| Mejor opción en retrospectiva (techo) | ${f3(ref.oracle.chosenMean)} | | | ${f3(0)} | | | ${Math.round(ref.oracle.executableShare * n)}/${n} | ${ref.oracle.below05}/${n} | ${ref.oracle.departsFromRule}/${n} |`);
      for (const p of PRI) out.push(row(`Simulador como política (${PN[p]})`, ref.simulator[p], n));
      for (const [tag, ev] of [['v2', a], ['v3', b]]) for (const [pol, name] of [['mlp', 'red'], ['elm', 'ELM']]) for (const s of SEEDS) for (const p of PRI) out.push(row(`Predecir y elegir: ${name} ${tag}, semilla ${s}, ${PN[p]}`, ev.decision.perSeed[setName][s][pol][p], n));
      out.push('');
      const mean = (ev, pol, p) => ev.decision.summary[setName][pol][p].chosenMean;
      out.push(`Resumen entre semillas (media, mínimo–máximo de la media de lo elegido): ${['mlp', 'elm'].map((pol) => PRI.map((p) => `${pol === 'mlp' ? 'red' : 'ELM'} ${PN[p]}: v2 ${f3(mean(a, pol, p).mean)} (${f3(mean(a, pol, p).min)}–${f3(mean(a, pol, p).max)}) → v3 ${f3(mean(b, pol, p).mean)} (${f3(mean(b, pol, p).min)}–${f3(mean(b, pol, p).max)})`).join('; ')).join('; ')}.\n`);
    }
    const cmp = (setName) => { let up = 0, down = 0; for (const s of SEEDS) for (const pol of ['mlp', 'elm']) for (const p of PRI) { const x = a.decision.perSeed[setName][s][pol][p].chosenMean, y = b.decision.perSeed[setName][s][pol][p].chosenMean; if (y > x + 1e-9) up++; else if (y < x - 1e-9) down++; } return { up, down }; };
    const c27 = cmp('reserved2022_2024'), c54 = cmp('years2019_2024');
    out.push(`De las 12 combinaciones (semilla × modelo × prioridad), v3 sube la media de lo elegido en ${c27.up} y la baja en ${c27.down} con 27 casos, y la sube en ${c54.up} y la baja en ${c54.down} con 54 casos.`);
    const best = (setName) => Math.max(...SEEDS.flatMap((s) => PRI.map((p) => rec.decision.perSeed[setName][s][p].chosenMean)));
    const bestV3 = (setName) => Math.max(...SEEDS.flatMap((s) => ['mlp', 'elm'].flatMap((pol) => PRI.map((p) => b.decision.perSeed[setName][s][pol][p].chosenMean))));
    out.push('');
    out.push(`La red que recomienda (reentrenada en GPU) llega, en la mejor de sus seis combinaciones, a ${f3(best('reserved2022_2024'))} (27 casos) y ${f3(best('years2019_2024'))} (54 casos); las políticas de predecir y elegir con v3, a ${f3(bestV3('reserved2022_2024'))} y ${f3(bestV3('years2019_2024'))}.`);
    return out.join('\n');
  },

  gpu() {
    const n = d('recommender_eval.json'), o = gitJson('recommender_eval.json'), gc = d('gpu_checks.json'), sc = readJson(path.join(root, 'scripts/emulator/v2_screening.json')), h = d('historical_check.json');
    const a = d('aligned_eval.json'), b = d('aligned_eval_v3.json');
    const cnt = (ev, setName) => { let pos = 0, more = 0; for (const s of SEEDS) for (const p of PRI) { const m = ev.decision.perSeed[setName][s][p]; if (m.meanGainVsRule > 1e-9) pos++; if (m.win > m.loss) more++; } return { pos, more }; };
    const ptcRange = (setName, ev) => { const v = SEEDS.flatMap((s) => ['mlp', 'elm'].flatMap((k) => PRI.map((p) => ev.decision.reference[setName].predictThenChoose[s][k][p].chosenMean))); return [Math.min(...v), Math.max(...v)]; };
    const recRange = (setName, ev) => { const v = SEEDS.flatMap((s) => PRI.map((p) => ev.decision.perSeed[setName][s][p].chosenMean)); return [Math.min(...v), Math.max(...v)]; };
    const r = (x) => `${f3(x[0])}–${f3(x[1])}`;
    const sets = [['reserved2022_2024', '27 casos de 2022–2024'], ['years2019_2024', '54 casos de 2019–2024']];
    const concl = sets.map(([k, t]) => { const x = cnt(o, k), y = cnt(n, k); return `- ${t}: la red que recomienda mejoraba la media de la regla en ${x.pos} de las 6 combinaciones (semilla × prioridad) con el entrenamiento en JS y la mejora en ${y.pos} de 6 con el de la GPU; tenía más casos ganados que perdidos en ${x.more} de 6 y ahora en ${y.more} de 6. Rango de la media de lo elegido: ${r(recRange(k, o))} antes y ${r(recRange(k, n))} ahora; predecir y elegir (red v2 y ELM v2, 12 combinaciones): ${r(ptcRange(k, n))}.`; }).join('\n');
    const ck = SEEDS.map((s) => n.jsVsTorchCheck[s]);
    const negL = []; for (const [k, t] of sets) for (const s of SEEDS) for (const p of PRI) { const m = n.decision.perSeed[k][s][p]; if (m.meanGainVsRule <= 1e-9) negL.push(`${t.split(' ')[0]} casos, semilla ${s}, ${PN[p]} (${sg(m.meanGainVsRule)})`); }
    const neg = negL.join('; ');
    const v3p = readJson(path.join(root, 'web/data/emulator_v3_mlp_seed17.json')).params, v2p = readJson(path.join(root, 'web/data/emulator_v2_mlp_seed17.json')).params;
    return `## Entrenamiento en GPU y más datos y entradas

15 de noviembre de 2026 (Tarea 33). Tres cosas: (1) el entrenamiento que faltaba pasó a lotes en la GPU; (2) con ello se reentrenó el recomendador de pérdida de cultivo y se midió cuánto cambia; (3) se probó si **más datos y más entradas** mejoran el emulador de siete cultivos (v2), juzgando solo con validación. Todos los números salen de artefactos: \`web/data/recommender_eval.json\`, \`web/data/gpu_checks.json\`, \`web/data/aligned_eval.json\` y \`aligned_eval_v3.json\`, \`web/data/coffee_eval.json\`, \`scripts/emulator/v2_screening.json\`. Seeds 17, 29 y 43; las condiciones son las de \`proyecto/condiciones-comunes.md\` (entrenamiento 2001–2016, validación 2017–2018, prueba 2019–2024 y puntos reservados); ninguna fila de prueba se usó para elegir nada y la prueba se evaluó una sola vez.

### 1. Entrenamiento por lotes en GPU

- **Núcleo compartido** \`scripts/gpu/es_core.py\`: la estrategia de evolución del café (Tarea 32), generalizada. Una generación evalúa los 32 individuos sobre 512 escenarios en una sola operación por lotes (pesos apilados, \`bmm\`), sin bucles de Python por individuo ni por escenario y sin \`.item()\` dentro de la generación. Lo usan el café (\`scripts/coffee/train_es.py\`, ya refactorizado: los pesos de las tres semillas salen idénticos a los de la Tarea 32, \`coffee_recommender.json\` no cambió) y el recomendador de pérdida de cultivo (\`scripts/gpu/train_recommender.py\`; el JS \`scripts/compare/train_recommender.mjs\` arma la tabla, evalúa y escribe los artefactos, y su entrenamiento en JS se conserva como referencia). Mismo diseño: población 32, 8 padres, σ 0.05, elitismo 1, 150 generaciones, 512 escenarios compartidos, las dos prioridades, mejor punto de control en validación, semillas 17/29/43, mismo formato de \`recommender_mlp.json\`. **El flujo aleatorio es el de torch (CUDA), no el de mulberry32 de JS: los números se mueven** (abajo).
- **Comprobación JS contra PyTorch** (puntajes de las 8 acciones con la regla, \`jsVsTorchCheck\` en \`recommender_eval.json\`): ${SEEDS.map((s, i) => `semilla ${s}: ${ck[i].rows} filas, diferencia máxima ${ck[i].maxScoreDiff.toExponential(1)}, misma recomendación en ${ck[i].sameRecommendation}/${ck[i].rows}`).join('; ')} (tolerancia 1e-5).
- **ELM en GPU** (\`scripts/gpu/elm_gpu.py\`): la misma ELM de \`trainELM\` con la solución de ridge por \`torch.linalg\` (Cholesky, float64), por bloques de filas. Los pesos ocultos salen del mismo generador mulberry32 (portado de forma vectorizada), de modo que con la misma semilla el modelo es el mismo. Comprobación (\`gpu_checks.json\`, \`scripts/gpu/check_gpu_training.mjs\`): ajuste con ${gc.elm.fitRows} filas de v2 y semilla 42; en ${gc.elm.probeRows} filas la diferencia máxima entre las predicciones de JS y de la GPU es ${gc.elm.maxAbsPredictionDiff.toExponential(1)} (tolerancia ${gc.elm.tolerance}). Se usa donde el ELM se repite por semilla: la evaluación alineada de v2 y de v3 y el café. Los artefactos de v1 no se regeneraron. La evaluación alineada de v2 con los ELM de la GPU da las mismas decisiones que antes (los números cambian solo en el redondeo, del orden de 1e-11).

**Tiempos, medidos** (equipo: ${gc.elm.device}, torch ${gc.elm.torchVersion}; el JS "antes" es el de los artefactos previos; la primera semilla de la GPU incluye el arranque de CUDA):

${pieces.timing()}

En el recomendador de pérdida de cultivo el JS corría las tres semillas a la vez (competencia entre procesos); en la GPU corren una tras otra.

### 2. El recomendador de pérdida de cultivo, antes y ahora

Mismo diseño, otro flujo aleatorio. Las semillas dan resultados distintos entre sí y distintos de la corrida en JS; esta es la variación entre corridas, no un cambio de diseño. Antes = \`recommender_eval.json\` de la Tarea 31 (commit ${OLD}); ahora = el actual.

${oldNew()}
**¿Cambian las conclusiones?** Sí, en una (la de la regla); la otra se mantiene:
${concl}
- **Ya no se puede decir que la red que recomienda mejora a la regla en las seis combinaciones**: con el entrenamiento de la GPU, las combinaciones con ganancia media sobre la regla de cero o menos son ${neg} (ver las tablas). El resultado depende de la semilla.
- **Sigue sin superar a predecir y elegir**: la mejor combinación de la red que recomienda (${f3(recRange('reserved2022_2024', n)[1])} con 27 casos y ${f3(recRange('years2019_2024', n)[1])} con 54) queda por debajo de la mejor de predecir y elegir (${f3(ptcRange('reserved2022_2024', n)[1])} y ${f3(ptcRange('years2019_2024', n)[1])}).
- El punto de control que guarda \`recommender_mlp.json\` es ahora el de la semilla ${n.meta.selected.seed} (generación ${n.meta.selected.generation}, aptitud de validación ${f3(n.meta.selected.valFitness)}); \`historical_check.json\` se regeneró con esa red (semilla ${h.meta.network.seed}, generación ${h.meta.network.generation}) y las tablas de la sección de contraste con agricultores son las nuevas; siguen siendo ilustrativas, no una prueba.

### 3. Más datos y más entradas para el emulador de siete cultivos

**Por qué.** La primera salida de v2 (\`relYieldA\`) tenía R² de unos 0.6 en años nuevos y una prueba de tamaño mostró que más parámetros no ayudan. La palanca es más datos o más entradas.

**Candidatos (fijados de antemano), tres semillas cada uno, solo validación 2017–2018.**
- \`base\`: v2 de hoy, 60 000 muestras (reservorio), 31 entradas.
- \`data\`: todas las muestras que produce el generador (${sc.meta.samples.candidates}), mismas 31 entradas.
- \`inputs\`: las 60 000 + 16 entradas nuevas: para el cultivo A y, con la misma definición, para B (ceros si no hay B, si A no termina en el año o si B ya no cabe): lluvia y ET₀ de los 30 días antes de que empiece la ventana de floración, el índice de lluvia antecedente y el balance corrido acotado a 150 mm al día anterior (la lógica de \`apiFlower\` y \`storeProxy\` de v1 con el Kc del propio cultivo), lluvia y déficit climático dentro de la ventana de floración, los días del ciclo simulado por grados-día y los días que quedan al fin del año agrícola en la siembra (\`web/js/model/emulatorV3.js\`).
- \`data+inputs\`: las dos cosas.

**Qué período cubre cada entrada nueva** (importante). Son entradas de una **temporada conocida** (retrospectiva), igual que \`rainYear\` o \`caniculaDays\` de v2: usan el clima diario del año agrícola (1 de abril a 31 de marzo) del paquete de datos, la ET₀ calculada de ese clima, los parámetros del cultivo y el día de siembra. La lluvia y la ET₀ se leen del 1 de abril hasta el último día de la ventana de floración (la de antes de la floración, la de dentro de ella); la temperatura diaria, que fija la duración del ciclo y por tanto la ventana, se lee de la siembra a la cosecha. **No usan ninguna salida del simulador** (ni balance de agua del suelo, ni Ks, ni rendimiento) ni nada posterior al 31 de marzo del año agrícola; \`storeProxy\` es el indicador sin suelo de v1, no el balance del simulador. Hay pruebas hechas a mano (\`tests/emulator_v3.test.mjs\`) que alteran la lluvia y la ET₀ posteriores a la floración, la temperatura posterior a la cosecha y todo lo posterior al 31 de marzo, y las entradas no cambian. En la decisión tras perder el maíz estas entradas se calculan sobre años pasados completos (como ya hacían las de v2), así que el modelo no ve la temporada que decide.

**Resultado del cribado** (solo validación; MSE de las salidas estandarizadas sobre las mismas filas de validación para todos):

${pieces.screening()}

**Adoptado: \`data+inputs\` (v3).** Se regeneraron las muestras (\`scripts/emulator/generate_v3.mjs\`: todos los candidatos, con las 47 entradas), se entrenaron las tres semillas en CUDA (\`scripts/emulator/train_mlp_v3.py\`; no se instaló nada en el entorno de CUDA) y se escribieron \`web/data/emulator_v3_mlp_seed{17,29,43}.json\` (y \`emulator_v3_mlp.json\`, semilla 42) junto a los de v2, que no se tocaron. La red es la misma receta con 47 entradas (${b.meta.features} entradas, ${v3p} parámetros; la de v2, 31 entradas y ${v2p}). Evaluación de prueba, una sola vez (\`aligned_eval_v3.json\`):

${pieces.v3()}

### 4. Qué empeoró, qué no se adoptó y límites

- **La red que recomienda ya no gana a la regla en las seis combinaciones** (sección 2): es lo único que empeoró de una conclusión anterior, por el cambio de flujo aleatorio y no por un cambio de diseño.
- **Con v3 la decisión no mejora de forma pareja.** La exactitud del emulador mejora claramente en las tres salidas y en las cuatro divisiones, pero la media de lo elegido por las políticas de predecir y elegir sube en unas combinaciones y baja en otras (ver el conteo arriba y las filas por semilla): la decisión elige el mejor de siete cultivos y no depende solo del error medio. No se afirma que v3 decida mejor.
- **No se adoptó** \`data\` solo (no mejora la validación) ni \`inputs\` solo (mejora mucho, pero \`data+inputs\` mejora más).
- **v3 no está conectado a la aplicación web**: la interfaz usa el simulador y el emulador v1; v2 y v3 son para la comparación de decisiones. Los artefactos v1 y v2 no se modificaron.
- **No se hizo:** AquaCrop como segundo juez de las recomendaciones; el margen económico (no hay precios y costos en el juez); el año agrícola 2025 (la serie termina el 2025-12-31); un reentrenamiento con 2019–2021 añadidos; ajustar el diseño del recomendador tras ver la prueba.
- El juez sigue siendo nuestro simulador y la prueba usa 3 pilotos con 27 y 54 casos casi repetidos entre sí; los conteos son descriptivos, no se calculó significancia.
`;
  },
};

const piece = process.argv[2];
if (piece === 'oldnew') console.log(oldNew());
else if (pieces[piece]) console.log(pieces[piece]());
else { console.error(`pieza desconocida: ${piece}`); process.exit(1); }
