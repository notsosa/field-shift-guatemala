// Tabla de escenarios del café v2 (Tarea 38): los escenarios de siempre (mismos sitios, suelos, años, días de decisión y cortes) más banano con cobertura 0.15 y 0.30.
// SUPUESTO PROVISIONAL del banano (ver web/js/model/coffee.js, BANANA): no es una medida. Entradas: las 16 de siempre + banana (0/1) + bananaCover.
// Las filas de las tres sombras originales salen idénticas a las de coffee_table.json (se comprueba aquí). La variante de sensibilidad sin KsBanana
// (el banano gasta igual con el suelo seco) va aparte, en sensitivityScenarios y sensitivityYearMeasures: no entra al entrenamiento.
// Uso: node scripts/coffee/scenarios_v2.mjs   (escribe scripts/coffee/cache/coffee_table_v2.json; no toca coffee_table.json)
import fs from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series } from '../../web/js/model/simulate.js';
import { resolveSoil } from '../../web/js/model/soil.js';
import {
  COFFEE_ID, DECISION_DAYS, STATE_NAMES_V2, BANANA, BANANA_COVERS, floweringFor, simulateCoffee, coffeeYearMeasures, coffeeDecisionStateV2, counterfactual, ruleIrrigates,
} from '../../web/js/model/coffee.js';
import { MIN_ELEVATION, SOILS, SHADES as SHADES_V1, SPLITS, RESERVED, splitOf } from './scenarios.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
export const BANANA_SHADES = BANANA_COVERS.map((c) => ({ label: `banana${c.toFixed(2)}`, shade: 'trees', treeType: 'banana', bananaCover: c }));
export const SHADES = [...SHADES_V1, ...BANANA_SHADES];
export const SENSITIVITY_SHADES = BANANA_SHADES.map((s) => ({ ...s, label: `${s.label}_noKs`, bananaKs: false }));

export function buildCoffeeTableV2() {
  const t0 = performance.now();
  const crops = loadCrops(readJson(path.join(root, 'web/data/crops.json')));
  const crop = crops.get(COFFEE_ID);
  const points = readJson(path.join(root, 'scripts/emulator/points.json')).filter((p) => p.siteElevation >= MIN_ELEVATION);
  const scenarios = [], yearMeasures = [], sensitivityScenarios = [], sensitivityYearMeasures = [], sites = [];
  for (const pt of points) {
    const bundle = readJson(path.join(root, `scripts/emulator/cache/${pt.id}.json`));
    const et0 = computeEt0Series(bundle);
    const { dates, rain, tmax, tmin } = bundle;
    sites.push({ id: pt.id, name: pt.name, department: pt.department, siteElevation: pt.siteElevation });
    for (const soilLabel of SOILS) {
      const soil = resolveSoil(soilLabel);
      for (const sh of [...SHADES, ...SENSITIVITY_SHADES]) {
        const sens = sh.bananaKs === false;
        const sim = simulateCoffee({ dates, rain, et0, crops, texture: soilLabel, shade: sh.shade, treeType: sh.treeType, bananaCover: sh.bananaCover, bananaKs: sh.bananaKs });
        for (let year = 2001; year <= 2024; year++) {
          const fl = floweringFor(dates, rain, year + 1);
          (sens ? sensitivityYearMeasures : yearMeasures).push({ site: pt.id, soil: soilLabel, shade: sh.label, ...coffeeYearMeasures({ sim, dates, rain, year }) });
          for (const dayAfter of DECISION_DAYS) {
            const t = fl.idx + dayAfter;
            const { state, depletion, taw } = coffeeDecisionStateV2({ dates, rain, et0, tmax, tmin, t, year, floweringIdx: fl.idx, soil, crop, elevation: pt.siteElevation, shade: sh.shade, treeType: sh.treeType, bananaCover: sh.bananaCover });
            const cf = counterfactual({ dates, rain, et0, crops, texture: soilLabel, shade: sh.shade, treeType: sh.treeType, sim, t, bananaCover: sh.bananaCover, bananaKs: sh.bananaKs });
            (sens ? sensitivityScenarios : scenarios).push({
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
      stateNames: STATE_NAMES_V2, splits: SPLITS, reserved: RESERVED, decisionDays: DECISION_DAYS, seconds: (performance.now() - t0) / 1000,
      provisional: `banana = SUPUESTO PROVISIONAL, no medido: evaporacion del suelo -0.52 mm/dia en lluvias (como los otros arboles) y gasto de banano = bananaCover x ${BANANA.kc} x ET0 x KsBanana (p = ${BANANA.p}); ${BANANA.source}`,
      bananaCovers: BANANA_COVERS, shades: SHADES.map((s) => s.label), sensitivityShades: SENSITIVITY_SHADES.map((s) => s.label),
    },
    sites, scenarios, yearMeasures, sensitivityScenarios, sensitivityYearMeasures,
  };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const t = buildCoffeeTableV2();
  // las filas de las sombras originales deben ser las de coffee_table.json (mismo orden, mismos números en las 16 primeras entradas)
  const v1 = readJson(path.join(root, 'scripts/coffee/cache/coffee_table.json'));
  const orig = t.scenarios.filter((s) => SHADES_V1.some((x) => x.label === s.shade));
  if (orig.length !== v1.scenarios.length) throw new Error(`filas originales ${orig.length} vs ${v1.scenarios.length}`);
  let maxDiff = 0;
  orig.forEach((s, i) => {
    const o = v1.scenarios[i];
    if (s.site !== o.site || s.soil !== o.soil || s.shade !== o.shade || s.year !== o.year || s.dayAfter !== o.dayAfter || s.avoided !== o.avoided || s.rule !== o.rule || s.stressNo !== o.stressNo || s.stressYes !== o.stressYes) throw new Error(`fila ${i} distinta`);
    for (let k = 0; k < 16; k++) maxDiff = Math.max(maxDiff, Math.abs(s.state[k] - o.state[k]));
  });
  t.meta.originalRowsCheck = { rows: orig.length, maxAbsStateDiffVsV1: maxDiff, sameOutcomes: true };
  const dir = path.join(root, 'scripts/coffee/cache');
  fs.writeFileSync(path.join(dir, 'coffee_table_v2.json'), JSON.stringify(t));
  const c = (s) => t.scenarios.filter((x) => x.split === s).length;
  console.log(`escenarios train/val/test = ${c('train')}/${c('val')}/${c('test')}; sensibilidad ${t.sensitivityScenarios.length}; ${t.meta.seconds.toFixed(1)} s; originales ${orig.length} identicos (max dif estado ${maxDiff})`);
}
