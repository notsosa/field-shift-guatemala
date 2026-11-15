// Comparación de fuentes de lluvia por año agrícola (1 abr Y .. 31 mar Y+1). Sin dependencias.
// Un año con algún día null en la serie no se suma: sus cifras quedan null (no se inventa lluvia).

const agriYear = (iso) => (Number(iso.slice(5, 7)) >= 4 ? Number(iso.slice(0, 4)) : Number(iso.slice(0, 4)) - 1);

/**
 * @param {string[]} dates ISO ascendentes
 * @param {(number|null)[]} rain mm/día alineada con dates
 * @returns {Map<number, {year, days, missingDays, totalMm, mayOctMm, caniculaDays}>} solo años agrícolas completos
 *   (365/366 días presentes). caniculaDays = racha seca más larga (lluvia < 1 mm) del 1 jul al 31 ago,
 *   la misma definición que la característica caniculaDays del emulador.
 */
export function annualRainStats(dates, rain) {
  const byYear = new Map();
  dates.forEach((d, i) => {
    const y = agriYear(d);
    if (!byYear.has(y)) byYear.set(y, []);
    byYear.get(y).push([d, rain[i]]);
  });
  const out = new Map();
  for (const [year, rows] of byYear) {
    const first = `${year}-04-01`; const last = `${year + 1}-03-31`;
    const expected = (Date.UTC(year + 1, 2, 31) - Date.UTC(year, 3, 1)) / 86400000 + 1;
    if (rows.length !== expected || rows[0][0] !== first || rows.at(-1)[0] !== last) continue;
    const missingDays = rows.filter(([, v]) => v == null).length;
    let total = null; let mayOct = null; let dry = null;
    if (missingDays === 0) {
      total = 0; mayOct = 0; dry = 0;
      let run = 0;
      for (const [d, v] of rows) {
        total += v;
        const md = d.slice(5);
        if (md >= '05-01' && md <= '10-31' && Number(d.slice(0, 4)) === year) mayOct += v;
        if (md >= '07-01' && md <= '08-31' && Number(d.slice(0, 4)) === year) { run = v < 1 ? run + 1 : 0; if (run > dry) dry = run; }
      }
    }
    out.set(year, { year, days: rows.length, missingDays, totalMm: total, mayOctMm: mayOct, caniculaDays: dry });
  }
  return out;
}

const r1 = (v) => (v == null ? null : Math.round(v * 10) / 10);
const mean = (a) => { const v = a.filter((x) => x != null); return v.length ? r1(v.reduce((s, x) => s + x, 0) / v.length) : null; };

/**
 * Estadísticas por año agrícola de cada producto de lluvia y medias sobre los años completos en TODOS los productos.
 * @param {string[]} dates ISO ascendentes
 * @param {Record<string,(number|null)[]>} rainAlt serie por producto, alineada con dates (día sin dato = null)
 * @param {number[]} years años agrícolas a reportar
 * @param {Record<string,string>} [labels] texto descriptivo por producto
 * @param {Record<string,string[]>} [sets] conjuntos nombrados de productos para los que además se calculan medias sobre sus años completos comunes
 * @returns {{sources: Record<string,object>, common: {years:number[], meanAnnualMm:object, meanMayOctMm:object, meanCaniculaDays:object}, commonSets: Record<string,object>}}
 *   Un año con algún día null en un producto tiene cifras null en ese producto y queda fuera de `common`; no se rellena.
 */
export function compareSources(dates, rainAlt, years, labels = {}, sets = {}) {
  const sources = {};
  for (const [name, series] of Object.entries(rainAlt)) {
    const stats = annualRainStats(dates, series);
    const rows = years.map((y) => stats.get(y) ?? null);
    sources[name] = {
      label: labels[name],
      annualMm: rows.map((r) => r1(r?.totalMm)),
      mayOctMm: rows.map((r) => r1(r?.mayOctMm)),
      caniculaDays: rows.map((r) => r?.caniculaDays ?? null),
      missingDays: rows.map((r) => r?.missingDays ?? null),
      meanAnnualMm: mean(rows.map((r) => r?.totalMm ?? null)),
      meanMayOctMm: mean(rows.map((r) => r?.mayOctMm ?? null)),
      meanCaniculaDays: mean(rows.map((r) => r?.caniculaDays ?? null)),
      validYears: rows.filter((r) => r && r.missingDays === 0).length,
    };
  }
  const commonOf = (names) => {
    const idx = years.map((_, i) => i).filter((i) => names.every((n) => sources[n].missingDays[i] === 0));
    const c = { products: names, years: idx.map((i) => years[i]), meanAnnualMm: {}, meanMayOctMm: {}, meanCaniculaDays: {} };
    for (const n of names) {
      c.meanAnnualMm[n] = mean(idx.map((i) => sources[n].annualMm[i]));
      c.meanMayOctMm[n] = mean(idx.map((i) => sources[n].mayOctMm[i]));
      c.meanCaniculaDays[n] = mean(idx.map((i) => sources[n].caniculaDays[i]));
    }
    return c;
  };
  const { products, ...common } = commonOf(Object.keys(sources));
  const commonSets = Object.fromEntries(Object.entries(sets).map(([k, names]) => [k, commonOf(names)]));
  return { sources, common, commonSets };
}

const addDay = (iso, n) => new Date(Date.parse(`${iso}T00:00:00Z`) + n * 86400000).toISOString().slice(0, 10);

/**
 * Cobertura de una serie alineada con `dates` (día sin dato = null): primer y último día con valor, días sin dato,
 * rangos consecutivos de días sin dato y total (mm) del año calendario `year` si ese año está completo (todas sus
 * fechas presentes y con valor), si no null. No rellena nada.
 * @returns {{first:string|null,last:string|null,missingDays:number,missingRanges:string[][],calendarYear:number,calendarYearTotalMm:number|null}}
 */
export function coverageOf(dates, rain, year = 2025) {
  let first = null; let last = null; let missingDays = 0;
  const missingRanges = [];
  let total = 0; let yearDays = 0; let yearGap = false;
  dates.forEach((d, i) => {
    const v = rain[i];
    if (v == null) {
      missingDays++;
      const open = missingRanges.at(-1);
      if (open && addDay(open[1], 1) === d) open[1] = d; else missingRanges.push([d, d]);
    } else { first ??= d; last = d; }
    if (Number(d.slice(0, 4)) === year) { yearDays++; if (v == null) yearGap = true; else total += v; }
  });
  const expected = (Date.UTC(year + 1, 0, 1) - Date.UTC(year, 0, 1)) / 86400000;
  const complete = yearDays === expected && !yearGap;
  return { first, last, missingDays, missingRanges, calendarYear: year, calendarYearTotalMm: complete ? Math.round(total * 10) / 10 : null };
}
