// Tablas en Markdown de la red alineada con la app, generadas desde web/data/app_eval.json (todo número del documento sale de aquí).
// Uso: node scripts/app/doc_tables.mjs > salida.md
import { readFileSync } from 'node:fs';

const ev = JSON.parse(readFileSync(new URL('../../web/data/app_eval.json', import.meta.url), 'utf8'));
const f = (x, d = 3) => (x == null ? '—' : x.toFixed(d));
const NAMES = { mlp_s17: 'Red (backprop) s17', mlp_s29: 'Red (backprop) s29', mlp_s43: 'Red (backprop) s43', elm_s17: 'ELM s17', elm_s29: 'ELM s29', elm_s43: 'ELM s43', refApp: 'Referencia: lo que muestra la app', refDry: 'Referencia: adelanto en seco' };
const MODELS = Object.keys(NAMES);
const out = [];
const P = (s = '') => out.push(s);

export function subsetTable(s) {
  const n = ev.metrics.refApp[s].factorFinal.n;
  P(`| Modelo | factorFinal R² | factorFinal MAE | estres7 R² | estres7 MAE | estres7 precisión / recall / F1 | estres14 R² | estres14 MAE | estres14 precisión / recall / F1 |`);
  P('|---|---|---|---|---|---|---|---|---|');
  for (const m of MODELS) {
    const x = ev.metrics[m][s];
    const c = (t) => `${f(x[t].precision)} / ${f(x[t].recall)} / ${f(x[t].f1)}`;
    P(`| ${NAMES[m]} | ${f(x.factorFinal.r2)} | ${f(x.factorFinal.mae, 4)} | ${f(x.estres7.r2)} | ${f(x.estres7.mae)} | ${c('estres7')} | ${f(x.estres14.r2)} | ${f(x.estres14.mae)} | ${c('estres14')} |`);
  }
  const p7 = ev.metrics.refApp[s].estres7, p14 = ev.metrics.refApp[s].estres14;
  P();
  P(`Filas: ${n}. Con estrés en los próximos 7 días: ${p7.positives} (${f((100 * p7.positives) / n, 1)} %); en los próximos 14: ${p14.positives} (${f((100 * p14.positives) / n, 1)} %).`);
}

export function breakdownTable(kind, target) {
  const keys = Object.keys(ev.breakdownTest.refApp[kind]);
  const models = ['mlp_s17', 'mlp_s29', 'mlp_s43', 'elm_s17', 'refApp', 'refDry'];
  P(`| ${kind === 'byFraction' ? 'Fracción del ciclo' : 'Cultivo'} | Modelo | MAE | R² |${target === 'factorFinal' ? '' : ' F1 |'}`);
  P(`|---|---|---|---|${target === 'factorFinal' ? '' : '---|'}`);
  for (const k of keys) for (const m of models) {
    const x = ev.breakdownTest[m][kind][k][target];
    P(`| ${k} | ${NAMES[m]} | ${f(x.mae, target === 'factorFinal' ? 4 : 3)} | ${f(x.r2)} |${target === 'factorFinal' ? '' : ` ${f(x.f1)} |`}`);
  }
}

export function verdictTable(s) {
  P('| Objetivo | Modelo frente a | Semillas que ganan en MAE (de 3) | MAE medio del modelo | MAE de la referencia | Semillas que ganan en R² | R² medio del modelo | R² de la referencia | Semillas que ganan en F1 |');
  P('|---|---|---|---|---|---|---|---|---|');
  for (const t of ev.targets) for (const [k, v] of Object.entries(ev.verdicts[s][t])) {
    const [fam, ref] = k.split('_vs_');
    P(`| ${t} | ${fam === 'mlp' ? 'Red' : 'ELM'} frente a ${ref === 'refApp' ? 'lo que muestra la app' : 'adelanto en seco'} | ${v.maeBeatsInSeeds} | ${f(v.meanMaeModel, 4)} | ${f(v.maeRef, 4)} | ${v.r2BeatsInSeeds} | ${f(v.meanR2Model)} | ${f(v.r2Ref)} | ${v.f1BeatsInSeeds ?? '—'} |`);
  }
}

if (process.argv[1] && process.argv[1].endsWith('doc_tables.mjs')) {
  const which = process.argv[2];
  if (which === 'subset') subsetTable(process.argv[3]);
  else if (which === 'breakdown') breakdownTable(process.argv[3], process.argv[4]);
  else if (which === 'verdict') verdictTable(process.argv[3]);
  console.log(out.join('\n'));
}
