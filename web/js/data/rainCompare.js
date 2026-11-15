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
