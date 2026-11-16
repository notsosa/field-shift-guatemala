// Tarea 36, parte B: ¿con qué frecuencia el umbral publicado de calor (AquaCrop: Tmax 40 C, Tmin 10 C en la floración) se alcanza en los 20 puntos, 2001-2024?
// Maíz, primer ciclo (siembra por la regla de inicio de lluvias) y segundo ciclo (15 de agosto); lluvia ERA5, Tmax/Tmin corregidas por altitud del paquete.
// Unidad = sitio-año con el ciclo completo. Regla fijada antes de ver el resultado: si el calor cambia el rendimiento relativo en más de 0.01 en menos del 1 % de
// los sitios-año, no se reentrena nada. Además, como sensibilidad (nunca en decisiones): Lobell et al. 2011 sobre los mismos ciclos.
// Uso: node scripts/factors/heat_counts.mjs  -> escribe scripts/factors/out/factors_heat_counts.json
import fs from 'node:fs';
import path from 'node:path';
import {
  root, YEARS, loadAllCrops, loadPoints, loadSite, soilOfPoint, completeYears, simulateSowing, sowLocalIndex, round,
} from '../compare/rain_sources_lib.mjs';
import { degreeDaysAbove, lobellMultiplier } from '../../web/js/model/factors.js';
import { quantile } from '../compare/succession_lib.mjs';

export const THRESHOLD = 0.01; // cambio del rendimiento relativo que cuenta
export const RETRAIN_SHARE = 0.01; // 1 % de los sitios-año
const CALENDARS = { primera: 'onset', postrera: '08-15' };
const crops = loadAllCrops();
const points = loadPoints();

const perPoint = [];
const all = { primera: [], postrera: [] };
for (const p of points) {
  const s = loadSite(p.id);
  const usable = new Set(completeYears(s.dates, s.rain.ERA5));
  const soil = soilOfPoint(p);
  const row = { point: p.id, name: p.name, department: p.department, elevation: s.bundle.elevation };
  for (const [cal, when] of Object.entries(CALENDARS)) {
    const units = [];
    for (const y of YEARS) {
      if (!usable.has(y)) continue;
      const sowLocal = sowLocalIndex(s.bundle, s.rain.ERA5, y, when);
      const r = simulateSowing({ bundle: s.bundle, et0: s.et0, rain: s.rain.ERA5, crops, soil, year: y, cropId: 'maiz', sowLocal, factors: { heat: true } });
      if (!r.cycleCompletes) continue;
      // Lobell: grados-día sobre 30 C en el ciclo (aprox. por Tmax diaria), tomando "sequía" si Ks de floración < 0.7 se aproxima por la pérdida por agua: relYield agua < 0.7.
      const a = s.bundle.dates.indexOf(r.sowDate); const b = s.bundle.dates.indexOf(r.harvestDate);
      const dd = degreeDaysAbove(s.bundle.tmax, a, b);
      const drought = r.relYieldWaterOnly < 0.7;
      const lob = lobellMultiplier(dd, drought);
      units.push({ year: y, water: r.relYieldWaterOnly, heatMean: r.heatMultiplier, heatMin: r.heatMinCoefficient, daysBelow1: r.heatDaysBelow1, hotDays: r.heatHotDays, coldDays: r.heatColdDays, withHeat: r.relYield, delta: r.relYieldWaterOnly - r.relYield, degreeDays30: dd, drought, lobellMult: lob, lobellDelta: r.relYieldWaterOnly * (1 - lob) });
    }
    row[cal] = units;
    all[cal].push(...units.map((u) => ({ ...u, point: p.id })));
  }
  perPoint.push(row);
}

const summarize = (units) => {
  const n = units.length;
  const mults = units.map((u) => u.heatMean);
  const below1 = units.filter((u) => u.daysBelow1 > 0);
  const big = units.filter((u) => u.delta > THRESHOLD);
  return {
    siteYears: n, heatBelow1: below1.length, siteYearsWithHotDay: units.filter((u) => u.hotDays > 0).length, siteYearsWithColdDay: units.filter((u) => u.coldDays > 0).length, hotDays: units.reduce((a, u) => a + u.hotDays, 0), coldDays: units.reduce((a, u) => a + u.coldDays, 0), changeOver001: big.length, shareChangeOver001: n ? round(big.length / n, 5) : null,
    multiplier: n ? { min: round(Math.min(...mults), 4), p1: round(quantile(mults, 0.01), 4), p5: round(quantile(mults, 0.05), 4), p50: round(quantile(mults, 0.5), 4), mean: round(mults.reduce((a, b) => a + b, 0) / n, 5) } : null,
    maxDelta: n ? round(Math.max(...units.map((u) => u.delta)), 4) : null,
    lobell: n ? { meanDegreeDays30: round(units.reduce((a, u) => a + u.degreeDays30, 0) / n, 2), siteYearsWithDegreeDays: units.filter((u) => u.degreeDays30 > 0).length, meanChange: round(units.reduce((a, u) => a + u.lobellDelta, 0) / n, 4), changeOver001: units.filter((u) => u.lobellDelta > THRESHOLD).length, maxChange: round(Math.max(...units.map((u) => u.lobellDelta)), 4), droughtSiteYears: units.filter((u) => u.drought).length } : null,
  };
};
const byPoint = perPoint.map((r) => ({ point: r.point, name: r.name, department: r.department, elevation: round(r.elevation, 0), primera: summarize(r.primera), postrera: summarize(r.postrera) }));
const total = summarize([...all.primera, ...all.postrera]);
const retrain = total.shareChangeOver001 >= RETRAIN_SHARE;
const out = {
  meta: {
    generated: new Date().toISOString().slice(0, 10), crop: 'maiz', years: '2001-2024 agricultural years with all rain days present (ERA5), cycle completing inside the agricultural year', points: points.length, rainSource: 'ERA5 (bundle with altitude-corrected Tmax/Tmin)',
    calendars: { primera: 'sown at the rain-onset rule', postrera: 'sown 15 August' },
    factor: 'AquaCrop v7.3 Annex I thresholds (Tmax 40 C, Tmin 10 C) with the logistic fall over 5 C (ch. 3, 3.12.5); mean daily coefficient over the flowering window multiplies the water-limited relative yield (our simplification: AquaCrop applies it to the harvest index); logistic steepness k = 10 is our choice.',
    rule: `If the heat factor changes the relative yield by more than ${THRESHOLD} in fewer than ${RETRAIN_SHARE * 100} % of site-years, nothing is retrained (fixed before seeing the result).`,
    lobellSensitivity: 'Lobell et al. 2011 (Africa): 1 % per degree-day above 30 C (1.7 % under drought; drought here = water-limited relative yield < 0.7), degree-days approximated from daily Tmax over the whole cycle. A proxy from another continent; off by default and never used in decisions.',
  },
  total, totalByCalendar: { primera: summarize(all.primera), postrera: summarize(all.postrera) }, retrainNeeded: retrain, byPoint,
  affectedSiteYears: [...all.primera.map((u) => ({ ...u, calendar: 'primera' })), ...all.postrera.map((u) => ({ ...u, calendar: 'postrera' }))].filter((u) => u.delta > THRESHOLD || u.daysBelow1 > 0).map((u) => ({ point: u.point, calendar: u.calendar, year: u.year, heatMean: round(u.heatMean, 4), heatMin: round(u.heatMin, 4), daysBelow1: u.daysBelow1, hotDays: u.hotDays, coldDays: u.coldDays, water: round(u.water, 4), withHeat: round(u.withHeat, 4) })),
};
fs.writeFileSync(path.join(root, 'scripts/factors/out/factors_heat_counts.json'), JSON.stringify(out, null, 1));
console.log('total', JSON.stringify(total));
console.log('retrainNeeded', retrain);
for (const b of byPoint) console.log(b.point.padEnd(18), 'prim', b.primera.siteYears, b.primera.heatBelow1, b.primera.changeOver001, 'min', b.primera.multiplier?.min, '| post', b.postrera.siteYears, b.postrera.heatBelow1, b.postrera.changeOver001, 'min', b.postrera.multiplier?.min);
