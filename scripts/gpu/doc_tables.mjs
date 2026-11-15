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
};

const piece = process.argv[2];
if (piece === 'oldnew') console.log(oldNew());
else if (pieces[piece]) console.log(pieces[piece]());
else { console.error(`pieza desconocida: ${piece}`); process.exit(1); }
