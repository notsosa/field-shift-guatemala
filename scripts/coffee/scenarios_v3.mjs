// Tabla de escenarios del café v3 (Tarea 41): los escenarios de siempre (mismos sitios, suelos, años, días de decisión y cortes) más tres sistemas con las clases de la auditoría del asesor:
// café con malezas, banano regulado con mulch y banano denso (Kc compuesto y p únicos por clase, ver web/js/model/coffee.js, SYSTEMS). Las tres sombras originales (sin sombra, árboles de hoja perenne y caduca)
// salen idénticas a las de coffee_table.json (se comprueba aquí). "Sin sombra" es el café de siempre (Kc 0.95 constante, p 0.40): la línea base limpia de la red.
// Entradas: las 16 de siempre + weeds + bananaRegulated + bananaDense. Los parámetros son valores de referencia de FAO-56, no medidos en campo.
// Uso: node scripts/coffee/scenarios_v3.mjs   (escribe scripts/coffee/cache/coffee_table_v3.json; no toca coffee_table.json ni coffee_table_v2.json)
import fs from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series } from '../../web/js/model/simulate.js';
import { resolveSoil } from '../../web/js/model/soil.js';
import {
  COFFEE_ID, DECISION_DAYS, STATE_NAMES_V3, SYSTEMS, SYSTEMS_SOURCE, floweringFor, simulateCoffee, coffeeYearMeasures, coffeeDecisionStateV3, counterfactual, ruleIrrigates,
} from '../../web/js/model/coffee.js';
import { MIN_ELEVATION, SOILS, SHADES as SHADES_V1, SPLITS, RESERVED, splitOf } from './scenarios.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
export const SYSTEM_SHADES = [
  { label: 'weedy', shade: 'none', treeType: 'evergreen', system: 'malezas' },
  { label: 'regulated', shade: 'none', treeType: 'evergreen', system: 'regulado' },
  { label: 'dense', shade: 'none', treeType: 'evergreen', system: 'denso' },
];
export const SHADES = [...SHADES_V1, ...SYSTEM_SHADES];

export function buildCoffeeTableV3() {
  const t0 = performance.now();
  const crops = loadCrops(readJson(path.join(root, 'web/data/crops.json')));
  const crop = crops.get(COFFEE_ID);
  const points = readJson(path.join(root, 'scripts/emulator/points.json')).filter((p) => p.siteElevation >= MIN_ELEVATION);
  const scenarios = [], yearMeasures = [], sites = [];
  for (const pt of points) {
    const bundle = readJson(path.join(root, `scripts/emulator/cache/${pt.id}.json`));
    const et0 = computeEt0Series(bundle);
    const { dates, rain, tmax, tmin } = bundle;
    sites.push({ id: pt.id, name: pt.name, department: pt.department, siteElevation: pt.siteElevation });
    for (const soilLabel of SOILS) {
      const soil = resolveSoil(soilLabel);
      for (const sh of SHADES) {
        const sim = simulateCoffee({ dates, rain, et0, crops, texture: soilLabel, shade: sh.shade, treeType: sh.treeType, system: sh.system });
        for (let year = 2001; year <= 2024; year++) {
          const fl = floweringFor(dates, rain, year + 1);
          yearMeasures.push({ site: pt.id, soil: soilLabel, shade: sh.label, ...coffeeYearMeasures({ sim, dates, rain, year }) });
          for (const dayAfter of DECISION_DAYS) {
            const t = fl.idx + dayAfter;
            const { state, depletion, taw } = coffeeDecisionStateV3({ dates, rain, et0, tmax, tmin, t, year, floweringIdx: fl.idx, soil, crop, elevation: pt.siteElevation, shade: sh.shade, treeType: sh.treeType, system: sh.system });
            const cf = counterfactual({ dates, rain, et0, crops, texture: soilLabel, shade: sh.shade, treeType: sh.treeType, sim, t, system: sh.system });
            scenarios.push({
              site: pt.id, soil: soilLabel, shade: sh.label, year, dayAfter, split: splitOf(year), date: dates[t], noTrigger: fl.noTrigger,
              state, depletion, taw, rule: ruleIrrigates(depletion, taw, crop.p) ? 1 : 0, stressNo: cf.stressNo, stressYes: cf.stressYes, avoided: cf.stressDaysAvoided,
            });
          }
        }
      }
    }
  }
  return {
    meta: {
      stateNames: STATE_NAMES_V3, splits: SPLITS, reserved: RESERVED, decisionDays: DECISION_DAYS, seconds: (performance.now() - t0) / 1000,
      systemsSource: SYSTEMS_SOURCE,
      systems: Object.fromEntries(SYSTEM_SHADES.map((s) => [s.label, { id: s.system, kc_ini_mid_end: SYSTEMS[s.system].kc, p: SYSTEMS[s.system].p }])),
      shades: SHADES.map((s) => s.label),
    },
    sites, scenarios, yearMeasures,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const t = buildCoffeeTableV3();
  // las filas de las sombras originales deben ser las de coffee_table.json (mismo orden, mismos números en las 16 primeras entradas)
  const v1 = readJson(path.join(root, 'scripts/coffee/cache/coffee_table.json'));
  const orig = t.scenarios.filter((s) => SHADES_V1.some((x) => x.label === s.shade));
  if (orig.length !== v1.scenarios.length) throw new Error(`filas originales ${orig.length} vs ${v1.scenarios.length}`);
  let maxDiff = 0;
  orig.forEach((s, i) => {
    const o = v1.scenarios[i];
    if (s.site !== o.site || s.soil !== o.soil || s.shade !== o.shade || s.year !== o.year || s.dayAfter !== o.dayAfter || s.avoided !== o.avoided || s.rule !== o.rule || s.stressNo !== o.stressNo || s.stressYes !== o.stressYes) throw new Error(`fila ${i} distinta`);
    for (let k = 0; k < 16; k++) maxDiff = Math.max(maxDiff, Math.abs(s.state[k] - o.state[k]));
    if (s.state.slice(16).some((v) => v !== 0)) throw new Error(`fila ${i}: las marcas de sistema de una sombra original deben ser 0`);
  });
  t.meta.originalRowsCheck = { rows: orig.length, maxAbsStateDiffVsV1: maxDiff, sameOutcomes: true };
  const dir = path.join(root, 'scripts/coffee/cache');
  fs.writeFileSync(path.join(dir, 'coffee_table_v3.json'), JSON.stringify(t));
  const c = (s) => t.scenarios.filter((x) => x.split === s).length;
  console.log(`escenarios train/val/test = ${c('train')}/${c('val')}/${c('test')}; ${t.meta.seconds.toFixed(1)} s; originales ${orig.length} identicos (max dif estado ${maxDiff})`);
}
