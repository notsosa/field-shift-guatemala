// Lee scripts/data/soilgrids_pilots.json (fetch_soilgrids.py) y escribe `soil` en los pilotos de scripts/emulator/points.json.
// Uso: node scripts/data/build_pilot_soil.mjs
// El objeto `soil` se pasa tal cual a simulateDays/runSequence como `texture` (ver resolveSoil en web/js/model/soil.js).
import { readFileSync, writeFileSync } from 'node:fs';
import { usdaTextureClass, hydrologicGroupOf, cnForGroup, nearestTextureInfo, HYDROLOGIC_GROUP_SOURCE, CN_TABLE_SOURCE } from '../../web/js/model/soil.js';

const here = (p) => new URL(p, import.meta.url);
const sg = JSON.parse(readFileSync(here('./soilgrids_pilots.json'), 'utf8'));
const pointsPath = here('../emulator/points.json');
let text = readFileSync(pointsPath, 'utf8');

const r4 = (v) => Math.round(v * 1e4) / 1e4;
const r1 = (v) => Math.round(v * 10) / 10;

export function pilotSoil(entry) {
  const w = entry.weighted0to100cm;
  const clayPct = r1(w.clay); const sandPct = r1(w.sand);
  const usdaClass = usdaTextureClass(clayPct, sandPct);
  const hydrologicGroup = hydrologicGroupOf(usdaClass);
  const methods = [...new Set(Object.values(entry.layers).flat().map((r) => r.method.replace(/\d+ valid/, 'N valid')))];
  const thetaFC = r4(w.wv0033); const thetaWP = r4(w.wv1500);
  return {
    thetaFC, thetaWP, clayPct, sandPct, usdaClass, hydrologicGroup,
    cn: cnForGroup(hydrologicGroup),
    ...nearestTextureInfo(thetaFC, thetaWP, hydrologicGroup),
    label: `SoilGrids 0–100 cm: ${usdaClass}, group ${hydrologicGroup}`,
    source: `ISRIC SoilGrids 2.0 WCS, mean prediction, thickness-weighted 0–100 cm (clay/sand g/kg÷10, wv0033 = θFC and wv1500 = θWP in 10⁻³ cm³/cm³÷1000; sampling: ${methods.join('; ')}); `
      + `${HYDROLOGIC_GROUP_SOURCE}; CN: ${CN_TABLE_SOURCE} (row crops straight row good / SR+CR good / fallow bare, group ${hydrologicGroup})`,
  };
}

for (const [id, entry] of Object.entries(sg.points)) {
  if (!entry.weighted0to100cm || Object.values(entry.weighted0to100cm).some((v) => v == null)) { console.log(`${id}: sin suelo (${entry.error ?? 'capas incompletas'})`); continue; }
  const soil = pilotSoil(entry);
  const re = new RegExp(`^(  \{"id": "${id}",.*?)(, "soil": \{.*\})?\}(,?)$`, 'm');
  if (!re.test(text)) throw new Error(`punto ${id} no encontrado en points.json`);
  text = text.replace(re, (_, head, _old, comma) => `${head}, "soil": ${JSON.stringify(soil)}}${comma}`);
  console.log(`${id}: ${soil.usdaClass} (${soil.hydrologicGroup}) θFC ${soil.thetaFC} θWP ${soil.thetaWP} AW ${r4(soil.thetaFC - soil.thetaWP)} -> nearestTexture ${soil.nearestTexture} (runoffMismatch ${soil.runoffMismatch})`);
}
writeFileSync(pointsPath, text);
JSON.parse(text); // valida
