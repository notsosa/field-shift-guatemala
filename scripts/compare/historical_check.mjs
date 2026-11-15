// Contraste descriptivo con decisiones documentadas de agricultores (Tarea 31, parte B). No ajusta nada.
// Uso: node scripts/compare/historical_check.mjs  (requiere web/data/recommender_mlp.json). Escribe web/data/historical_check.json.
// Las citas se verificaron abriendo las fuentes (ver "sources"); un evento cuya fuente no dice lo que se afirma se descarta y queda anotado.
import fs from 'node:fs';
import path from 'node:path';
import { ACTION_IDS, inputRows, recommend } from '../../web/js/model/recommender.js';
import { LOSS_DAYS } from './loss_decision_lib.mjs';
import { loadPointData, buildScenario, oracleAction, SPLIT_YEARS } from './recommender_scenarios.mjs';
import { root, readJson } from './loss_decision_core.mjs';

const net = readJson(path.join(root, 'web/data/recommender_mlp.json'));
const model = { params: Float64Array.from(net.params), mean: net.mean, std: net.std };
const { crops, data } = loadPointData();
const byId = Object.fromEntries(data.map((d) => [d.id, d]));
const km = (a, b) => { const R = 6371, r = (x) => (x * Math.PI) / 180; const h = Math.sin(r(b.lat - a.lat) / 2) ** 2 + Math.cos(r(a.lat)) * Math.cos(r(b.lat)) * Math.sin(r(b.lon - a.lon) / 2) ** 2; return 2 * R * Math.asin(Math.sqrt(h)); };
const pointsMeta = Object.fromEntries(readJson(path.join(root, 'scripts/emulator/points.json')).map((p) => [p.id, p]));
const splitOf = (year, isPilot) => (year >= SPLIT_YEARS.train[0] && year <= SPLIT_YEARS.train[1] ? 'train' : year >= SPLIT_YEARS.val[0] && year <= SPLIT_YEARS.val[1] ? 'validation' : year >= SPLIT_YEARS.test[0] && year <= SPLIT_YEARS.test[1] ? (isPilot ? 'test' : 'not used (test years are only scored at the pilots)') : 'outside the splits');

const SOURCES = {
  fao2010: { url: 'https://www.fao.org/4/ak344s/ak344s00.htm', title: 'Misión FAO/PMA de evaluación de cosecha y seguridad alimentaria en Guatemala, informe especial, 23 de febrero de 2010', where: 'Anexo 1, "Región Oriente (departamentos de Jalapa, Chiquimula, El Progreso, Jutiapa, Baja Verapaz, Zacapa y Quiché)", párrafo 3', opened: true,
    quotes: ['"se sembró maíz también en el segundo ciclo productivo"', '"perdiéndose nuevamente todas las plantaciones"'], context: 'Contexto de la fuente: por pérdidas en el primer ciclo y por el uso de semilla de maíz del Ministerio de Agricultura, en 2009 se sembró maíz también en el segundo ciclo; la sequía se prolongó y se perdieron de nuevo todas las plantaciones.' },
  magaJune2023: { url: 'https://precios.maga.gob.gt/archivos/smc/2023/06%20Informe%20SMC%20-%20Junio%20-%202023.pdf', title: 'MAGA/PMA Informe SMC No. 06, junio 2023', where: 'p. 10, sección de monitoreo de cultivos (PMA), región Nororiente', opened: true,
    quotes: ['"han tenido que realizar resiembra"'], context: 'Lo dicen los agricultores entrevistados de San Juan Ermita (Chiquimula), que sembraron el ciclo de primera del 10 al 18 de mayo. El cultivo que se resembró no se indica en la frase.' },
  magaJuly2023: { url: 'https://precios.maga.gob.gt/archivos/smc/2023/07%20Informe%20SMC%20-%20Julio%20-%202023.pdf', title: 'MAGA/PMA Informe SMC No. 07, julio 2023', where: 'p. 11, sección VI, región Nororiente', opened: true,
    quotes: ['"del municipio de Olopa realizaron resiembra debido a las condiciones climáticas desfavorables"'], context: 'Dice "algunos de los agricultores entrevistados"; no indica el cultivo resembrado ni la fecha de la pérdida o de la resiembra.' },
  fews2024: { url: 'https://fews.net/es/latin-america-and-caribbean/guatemala/perspectiva-de-seguridad-alimentaria/febrero-2024', title: 'FEWS NET, Guatemala, Perspectiva de seguridad alimentaria, febrero 2024', where: 'sección Situación actual, producción de granos básicos 2023 (nacional)', opened: true,
    quotes: ['"Algunos agricultores decidieron esperar que las lluvias mejoraran"', '"muchos pequeños agricultores no pudieron resembrar"'], context: 'Es una descripción nacional del ciclo de primera de 2023 (siembras retrasadas uno o dos meses); nombra Chiquimula solo entre los departamentos con daños por sequía. Dice que la mayoría de medianos, excedentarios y comerciales sí resembró, con "capacidades productivas" mayores (extensión, capital, mecanización). La frase "no tenían recursos" no aparece tal cual.' },
};

const EVENTS = [
  { id: 'oriente2009', year: 2009, place: 'Oriente de Guatemala (departamentos de Jalapa, Chiquimula, El Progreso, Jutiapa, Baja Verapaz, Zacapa y Quiché)', sources: ['fao2010'],
    documented: 'Tras perder el primer ciclo de maíz, los agricultores resembraron maíz en el segundo ciclo con semilla del MAGA; la sequía siguió y se perdió de nuevo todo.',
    documentedAction: 'maiz', documentedOutcome: 'perdida (segunda siembra perdida)', points: ['chiquimula', 'jutiapa', 'zacapa', 'jalapa'], nearestNote: 'El informe describe una región; se usan los puntos de nuestros 20 que llevan el nombre de departamentos citados (distancia 0 a ese punto por construcción; no hay coordenada de parcela).', refPoint: null,
    caveat: 'El "segundo ciclo" del informe es una siembra de segunda (después de la cosecha o pérdida de la primera, calendario de segunda), no una resiembra 14 días después de perder el maíz a los 30, 45 o 60 días: el calendario de la decisión de nuestro simulador no es el mismo.' },
  { id: 'chiquimula2023', year: 2023, place: 'Olopa y San Juan Ermita, Chiquimula', sources: ['magaJune2023', 'magaJuly2023', 'fews2024'],
    documented: 'Agricultores entrevistados de Olopa y San Juan Ermita resembraron (cultivo no indicado); en el país algunos esperaron la lluvia y muchos pequeños no pudieron resembrar (FEWS NET, nacional).',
    documentedAction: 'resembrar (cultivo no indicado)', documentedOutcome: 'sin dato en las fuentes', points: ['olopa', 'chiquimula'], refPoint: 'olopa',
    nearestNote: 'Olopa es uno de los 20 puntos (distancia 0: el punto lleva el nombre del municipio). San Juan Ermita no tiene punto propio y no se verificó una coordenada para él. Chiquimula (departamento) se añade por ser piloto.',
    caveat: 'No hay rendimiento, fechas ni cultivo por parcela. Las fuentes describen municipios o el país.' },
];

const fmt = (x) => (x == null ? null : Math.round(x * 1000) / 1000);
const out = { meta: { generated: new Date().toISOString().slice(0, 10), network: { file: 'web/data/recommender_mlp.json', seed: net.seed, generation: net.generation }, lossDays: LOSS_DAYS,
  note: 'Illustrative, not a held-out test: 2009 is a training year at every point; 2023 is not used for training or validation (at the pilots it is a test year). Nothing is fitted to these events.',
  dropped: [{ event: 'San Martín Jilotepeque 2026 (farmers sowed local beans after losing maize)', reason: 'Outside the weather data (ends 2025-12-31) and not among the sources the brief asked to open; mentioned only, not evaluated.' }] },
  sources: SOURCES, events: [] };

for (const ev of EVENTS) {
  const cases = [];
  for (const pid of ev.points) {
    const pt = byId[pid];
    const [soilLabel, soil] = pt.soils.length === 1 ? pt.soils[0] : pt.soils.find(([l]) => l === 'loam');
    const dist = ev.refPoint ? km(pointsMeta[pid], pointsMeta[ev.refPoint]) : 0;
    for (const lossDay of LOSS_DAYS) {
      const s = buildScenario({ crops, pt, soilLabel, soil, year: ev.year, lossDay });
      const rec = [0, 1].map((p) => recommend(model, inputRows(s.state, p, s.actionRows).map((r) => r), s.rule));
      // recommend estandariza adentro; las filas crudas son las de inputRows
      const y = (a) => fmt(s.y[ACTION_IDS.indexOf(a)]);
      const net0 = rec[0].action, net1 = rec[1].action;
      cases.push({
        point: pid, distanceKmToEventReference: fmt(dist), soil: soilLabel, year: ev.year, lossDay, resowDate: s.resowDate,
        split: splitOf(ev.year, pt.isPilot),
        documented: { action: ev.documentedAction, simulatorRelYieldIfMaizeResown: y('maiz'), simulatorRelYieldIfBeansResown: y('frijol') },
        rule: { action: s.rule, relYield: y(s.rule) },
        network: { typical: { action: net0, relYield: y(net0) }, cautious: { action: net1, relYield: y(net1) } },
        oracle: { action: oracleAction(s.y), relYield: fmt(Math.max(...s.y)) },
        allActions: Object.fromEntries(ACTION_IDS.map((a) => [a, y(a)])),
      });
    }
  }
  out.events.push({ id: ev.id, year: ev.year, place: ev.place, sources: ev.sources, documented: ev.documented, documentedOutcome: ev.documentedOutcome, nearestPoints: ev.nearestNote, caveat: ev.caveat, cases });
}
fs.writeFileSync(path.join(root, 'web/data/historical_check.json'), JSON.stringify(out, null, 1));
for (const ev of out.events) for (const c of ev.cases) console.log(ev.id, c.point, c.soil, c.lossDay, c.resowDate, 'rule', c.rule.action, c.rule.relYield, 'net', c.network.typical.action, c.network.cautious.action, 'maize', c.documented.simulatorRelYieldIfMaizeResown, 'oracle', c.oracle.action, c.oracle.relYield, c.split);
