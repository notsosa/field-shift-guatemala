// Tabla de escenarios del café (Tarea 32): sitios con siteElevation >= 900 m x suelo (arena/franco/arcilla) x año cafetalero x día de decisión (30/60/90 tras la floración)
// x sombra (ninguna, árboles siempreverdes, árboles deciduos). Entradas del día de la decisión + resultado de las dos acciones en el simulador.
// Años cafetaleros: 2001-2016 entrenamiento, 2017-2018 validación, 2019-2024 prueba (reservado 2022-2024).
// Uso: node scripts/coffee/scenarios.mjs   (escribe scripts/coffee/cache/coffee_table.json)
import fs from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { fileURLToPath } from 'node:url';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series } from '../../web/js/model/simulate.js';
import { resolveSoil } from '../../web/js/model/soil.js';
import {
  COFFEE_ID, DECISION_DAYS, STATE_NAMES, floweringFor, simulateCoffee, coffeeYearMeasures, coffeeDecisionState, counterfactual, ruleIrrigates,
} from '../../web/js/model/coffee.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(f, 'utf8'));
export const MIN_ELEVATION = 900;
export const SOILS = ['sand', 'loam', 'clay'];
export const SHADES = [{ label: 'none', shade: 'none', treeType: 'evergreen' }, { label: 'evergreen', shade: 'trees', treeType: 'evergreen' }, { label: 'deciduous', shade: 'trees', treeType: 'deciduous' }];
export const SPLITS = { train: [2001, 2016], val: [2017, 2018], test: [2019, 2024] };
export const RESERVED = [2022, 2023, 2024];
export const splitOf = (y) => Object.entries(SPLITS).find(([, [a, b]]) => y >= a && y <= b)[0];

export function buildCoffeeTable() {
  const t0 = performance.now();
  const crops = loadCrops(readJson(path.join(root, 'web/data/crops.json')));
  const crop = crops.get(COFFEE_ID);
  const points = readJson(path.join(root, 'scripts/emulator/points.json')).filter((p) => p.siteElevation >= MIN_ELEVATION);
  const scenarios = [], yearMeasures = [], sites = [];
  for (const pt of points) {
    const bundle = readJson(path.join(root, `scripts/emulator/cache/${pt.id}.json`));
    const et0 = computeEt0Series(bundle);
    const { dates, rain, tmax, tmin } = bundle;
    const tmeanAll = tmax.reduce((s, v, i) => s + (v + tmin[i]) / 2, 0) / tmax.length;
    sites.push({ id: pt.id, name: pt.name, department: pt.department, siteElevation: pt.siteElevation, meanTempC: tmeanAll, rainMmPerYear: rain.reduce((a, b) => a + b, 0) / (rain.length / 365.25), heldOut: pt.heldOut, rainSource: bundle.rainSource });
    for (const soilLabel of SOILS) {
      const soil = resolveSoil(soilLabel);
      for (const sh of SHADES) {
        const sim = simulateCoffee({ dates, rain, et0, crops, texture: soilLabel, shade: sh.shade, treeType: sh.treeType });
        for (let year = 2001; year <= 2024; year++) {
          const fl = floweringFor(dates, rain, year + 1);
          yearMeasures.push({ site: pt.id, soil: soilLabel, shade: sh.label, ...coffeeYearMeasures({ sim, dates, rain, year }) });
          for (const dayAfter of DECISION_DAYS) {
            const t = fl.idx + dayAfter;
            const { state, depletion, taw } = coffeeDecisionState({ dates, rain, et0, tmax, tmin, t, year, floweringIdx: fl.idx, soil, crop, elevation: pt.siteElevation, shade: sh.shade, treeType: sh.treeType });
            const cf = counterfactual({ dates, rain, et0, crops, texture: soilLabel, shade: sh.shade, treeType: sh.treeType, sim, t });
            scenarios.push({
              site: pt.id, soil: soilLabel, shade: sh.label, year, dayAfter, split: splitOf(year), date: dates[t], noTrigger: fl.noTrigger,
              state, depletion, taw, rule: ruleIrrigates(depletion, taw, crop.p) ? 1 : 0,
              stressNo: cf.stressNo, stressYes: cf.stressYes, avoided: cf.stressDaysAvoided,
            });
          }
        }
      }
    }
  }
  return { meta: { stateNames: STATE_NAMES, splits: SPLITS, reserved: RESERVED, decisionDays: DECISION_DAYS, seconds: (performance.now() - t0) / 1000 }, sites, scenarios, yearMeasures };
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const t = buildCoffeeTable();
  const dir = path.join(root, 'scripts/coffee/cache');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'coffee_table.json'), JSON.stringify(t));
  const c = (s) => t.scenarios.filter((x) => x.split === s).length;
  console.log(`sitios ${t.sites.length}; escenarios train/val/test = ${c('train')}/${c('val')}/${c('test')}; ${t.meta.seconds.toFixed(1)} s`);
  for (const s of t.sites) console.log(`${s.id.padEnd(18)} ${String(s.siteElevation).padStart(5)} m  T media ${s.meanTempC.toFixed(1)} C  lluvia ${s.rainMmPerYear.toFixed(0)} mm/año`);
}
