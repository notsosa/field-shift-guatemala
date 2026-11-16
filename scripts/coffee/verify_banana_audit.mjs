// Tarea 40: nuestro simulador de café con banano frente a la auditoría del asesor (café solo vs café + banano, Chiquimula 2025) -> web/data/banana_audit_check.json
// Uso: node scripts/coffee/verify_banana_audit.mjs
// No cambia código del modelo: solo llama a simulateCoffee/simulateDays con entradas distintas. Las cifras de la auditoría vienen de scripts/coffee/banana_audit_reference.json (copia sin cambios de origin/main ac37f1b).
// Tolerancias fijadas ANTES de calcular (brief de la tarea 40):
//  - signo y orden iguales a los de la auditoría (obligatorio): solo < banano 0.15 < banano 0.30 en demanda y en déficit, y banano − solo > 0.
//  - magnitud "cercana": diferencia de déficit (banano 0.15 − solo) dentro del rango regulado de la auditoría ×/÷ 2 (79.21/2 = 39.6 a 120.25×2 = 240.5 mm);
//    banano 0.30 entre el rango regulado ÷ 2 (39.6) y el rango denso-contra-limpio × 2 (292.80 × 2 = 585.6 mm). También se informa el intervalo estricto de la fila ERA5 (96.36 a 238.74 mm).
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadCrops } from '../../web/js/model/crops.js';
import { computeEt0Series } from '../../web/js/model/simulate.js';
import { COFFEE_ID, BANANA, simulateCoffee, plotAdjust } from '../../web/js/model/coffee.js';
import { simulateDays } from '../../web/js/model/waterBalance.js';
import { buildPerennialPhase } from '../../web/js/model/phenology.js';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const readJson = (f) => JSON.parse(fs.readFileSync(path.join(root, f), 'utf8'));
const r2 = (v) => Math.round(v * 100) / 100;
const r4 = (v) => Math.round(v * 1e4) / 1e4;
const sum = (a) => a.reduce((x, y) => x + y, 0);

const ref = readJson('scripts/coffee/banana_audit_reference.json');
const snap = readJson('web/data/snapshots/chiquimula.json');
const pilot = readJson('scripts/emulator/points.json').find((p) => p.id === 'chiquimula');
const crops = loadCrops(readJson('web/data/crops.json'));
const crop = crops.get(COFFEE_ID);

const i0 = snap.dates.indexOf('2025-01-01');
const i1 = snap.dates.indexOf('2025-12-31');
if (i0 < 0 || i1 < 0 || i1 - i0 + 1 !== 365) throw new Error('el snapshot de Chiquimula no cubre 2025 completo');
if (snap.rainSource !== 'ERA5') throw new Error('se esperaba lluvia ERA5 en el snapshot');
const et0All = computeEt0Series(snap);
const slice = (a) => a.slice(i0, i1 + 1);
const dates25 = slice(snap.dates);

const CASES = [
  { id: 'alone', label: 'café solo', shade: 'none' },
  { id: 'banana015', label: 'banano, cobertura 0.15', shade: 'trees', treeType: 'banana', bananaCover: 0.15 },
  { id: 'banana030', label: 'banano, cobertura 0.30', shade: 'trees', treeType: 'banana', bananaCover: 0.30 },
  { id: 'evergreen', label: 'árbol de hoja perenne', shade: 'trees', treeType: 'evergreen' },
  { id: 'deciduous', label: 'árbol de hoja caduca', shade: 'trees', treeType: 'deciduous' },
];

function measures(sim, lo, hi) {
  let etc = 0, eta = 0, d95 = 0, d1 = 0, runoff = 0;
  for (let i = lo; i <= hi; i++) { etc += sim.etc[i]; eta += sim.eta[i]; runoff += sim.runoff[i]; if (sim.ks[i] < 0.95) d95++; if (sim.ks[i] < 1) d1++; }
  return { demand_mm: r2(etc), eta_mm: r2(eta), deficit_mm: r2(etc - eta), days_ks_lt_095: d95, days_ks_lt_1: d1, runoff_mm: r2(runoff) };
}

/** Corre un caso con simulateCoffee (como la app). run = { dates, rain, et0, texture, drInit }. */
function runCase(c, run, lo, hi) {
  const sim = simulateCoffee({ dates: run.dates, rain: run.rain, et0: run.et0, crops, texture: run.texture, shade: c.shade, treeType: c.treeType, slopeClass: 'flat', drInit: run.drInit, bananaCover: c.bananaCover });
  return measures(sim, lo, hi);
}
/** Variante de diagnóstico: banano sin el recorte de 0.52 mm/día (solo el gasto del banano), con las mismas funciones exportadas. */
function runBananaNoCut(cover, run, lo, hi) {
  const adj = plotAdjust(run.dates, 'trees', 'banana', { bananaCover: cover });
  adj.reduce = adj.reduce.map(() => 0);
  const sim = simulateDays({ rain: run.rain, et0: run.et0, phases: [buildPerennialPhase(crop, run.rain.length)], crops, texture: run.texture, slopeClass: 'flat', irrigation: 'none', drInit: run.drInit, plotAdjust: adj });
  return measures(sim, lo, hi);
}

// ---------- Corrida A: el simulador tal como lo usa la app (serie continua 2001-2025, suelo SoilGrids del piloto, arranque seco en 2001), se mide 2025 ----------
const runA = { dates: snap.dates, rain: snap.rain, et0: et0All, texture: pilot.soil, drInit: undefined };
const A = Object.fromEntries(CASES.map((c) => [c.id, runCase(c, runA, i0, i1)]));

// ---------- Corrida B: lo más cerca de la auditoría que permite nuestro código (sin cambiarlo) ----------
// TAW 130.7 mm sobre la zona radicular del café del simulador (zrMax = 1.2 m): θWP del piloto y θFC = θWP + 130.7/1200.
const zr = crop.zrMax;
const thetaWP = pilot.soil.thetaWP;
const thetaFC = thetaWP + ref.soil.TAW_mm_0_100cm / (1000 * zr);
// Escorrentía fija del 15 %: nuestro código usa SCS-CN diario, no una fracción. Se entra con lluvia efectiva = 0.85·P y CN mínimo (30), con lo que SCS no genera escorrentía (Ia = 118.5 mm/día).
const soilB = {
  thetaFC, thetaWP, cn: { crop: 30, residue: 30, bare: 30 },
  source: 'Tarea 40: TAW 130.7 mm de la auditoría (SoilGrids 0-100 cm del punto 14.8250, -89.5312) sobre Zr = 1.2 m; CN mínimo para que la escorrentía la fije la fracción 0.15 aplicada a la lluvia',
};
const maxDailyRain = Math.max(...slice(snap.rain));
const tawB = r2(1000 * (thetaFC - thetaWP) * zr);
const drInitB = (1 - ref.soil.initial_reserve_fraction) * tawB; // reserva inicial 25 %: Dr = 75 % de TAW
const runB = { dates: dates25, rain: slice(snap.rain).map((v) => v * (1 - ref.soil.runoff_fraction)), et0: slice(et0All), texture: soilB, drInit: drInitB };
const B = Object.fromEntries(CASES.map((c) => [c.id, runCase(c, runB, 0, 364)]));

// ---------- Corrida C: igual que B pero con las entradas diarias congeladas de la auditoría (ET0 FAO-56 con NASA POWER y lluvia ERA5 de su CSV) ----------
const runC = { dates: ref.dates, rain: ref.p_era5_mm.map((v) => v * (1 - ref.soil.runoff_fraction)), et0: ref.et0_power_fao56_mm, texture: soilB, drInit: drInitB };
const C = Object.fromEntries(CASES.map((c) => [c.id, runCase(c, runC, 0, 364)]));

// ---------- Auditoría (fila ERA5 y rangos entre las 4 fuentes de lluvia) ----------
const au = ref.audit;
const E = au.era5;
const sources = Object.keys(au);
const range = (f) => { const v = sources.map(f); return [r2(Math.min(...v)), r2(Math.max(...v))]; };
const auditRef = {
  era5: {
    alone: E.cafe_solo_limpio, regulated: E.cafe_banano_regulado, weedy_alone: E.cafe_solo_malezas, dense: E.cafe_banano_denso,
    demand_diff_regulated_mm: r2(E.cafe_banano_regulado.ETc_mm - E.cafe_solo_limpio.ETc_mm),
    demand_diff_dense_vs_clean_mm: r2(E.cafe_banano_denso.ETc_mm - E.cafe_solo_limpio.ETc_mm),
    demand_diff_regulated_pct: r2(100 * (E.cafe_banano_regulado.ETc_mm / E.cafe_solo_limpio.ETc_mm - 1)),
    demand_diff_dense_pct: r2(100 * (E.cafe_banano_denso.ETc_mm / E.cafe_solo_limpio.ETc_mm - 1)),
    deficit_diff_regulated_mm: r2(E.cafe_banano_regulado.deficit_mm - E.cafe_solo_limpio.deficit_mm),
    deficit_diff_dense_vs_clean_mm: r2(E.cafe_banano_denso.deficit_mm - E.cafe_solo_limpio.deficit_mm),
    stress_days_diff_regulated: E.cafe_banano_regulado.dias_Ks_lt_095 - E.cafe_solo_limpio.dias_Ks_lt_095,
    stress_days_diff_dense_vs_clean: E.cafe_banano_denso.dias_Ks_lt_095 - E.cafe_solo_limpio.dias_Ks_lt_095,
  },
  deficit_diff_regulated_range_mm: range((s) => au[s].cafe_banano_regulado.deficit_mm - au[s].cafe_solo_limpio.deficit_mm),
  deficit_diff_dense_vs_clean_range_mm: range((s) => au[s].cafe_banano_denso.deficit_mm - au[s].cafe_solo_limpio.deficit_mm),
  deficit_diff_regulated_vs_weedy_range_mm: range((s) => au[s].cafe_banano_regulado.deficit_mm - au[s].cafe_solo_malezas.deficit_mm),
  stress_days_diff_regulated_range: range((s) => au[s].cafe_banano_regulado.dias_Ks_lt_095 - au[s].cafe_solo_limpio.dias_Ks_lt_095),
};
const regLo = auditRef.deficit_diff_regulated_range_mm[0], regHi = auditRef.deficit_diff_regulated_range_mm[1];
const denseHi = auditRef.deficit_diff_dense_vs_clean_range_mm[1];
const tol = {
  sign_and_order: 'required: demanda y déficit con solo < banano 0.15 < banano 0.30',
  cover015_deficit_diff_mm: [r2(regLo / 2), r2(regHi * 2)],
  cover030_deficit_diff_mm: [r2(regLo / 2), r2(denseHi * 2)],
  strict_era5_regulated_to_dense_mm: [auditRef.era5.deficit_diff_regulated_mm, auditRef.era5.deficit_diff_dense_vs_clean_mm],
};
const inside = (v, [lo, hi]) => v >= lo && v <= hi;

function compare(R) {
  const d = (k, f) => r2(R[k][f] - R.alone[f]);
  const out = {};
  for (const k of ['banana015', 'banana030']) {
    out[k] = {
      demand_diff_mm: d(k, 'demand_mm'), demand_diff_pct: r2(100 * (R[k].demand_mm / R.alone.demand_mm - 1)),
      eta_diff_mm: d(k, 'eta_mm'), deficit_diff_mm: d(k, 'deficit_mm'),
      stress_days_ks_lt_095_diff: R[k].days_ks_lt_095 - R.alone.days_ks_lt_095, stress_days_ks_lt_1_diff: R[k].days_ks_lt_1 - R.alone.days_ks_lt_1,
    };
  }
  const order = (f) => R.alone[f] < R.banana015[f] && R.banana015[f] < R.banana030[f];
  out.sign_ok = out.banana015.deficit_diff_mm > 0 && out.banana030.deficit_diff_mm > 0 && out.banana015.demand_diff_mm > 0;
  out.order_ok = order('demand_mm') && order('deficit_mm');
  out.cover015_magnitude_close = inside(out.banana015.deficit_diff_mm, tol.cover015_deficit_diff_mm);
  out.cover030_magnitude_close = inside(out.banana030.deficit_diff_mm, tol.cover030_deficit_diff_mm);
  out.cover030_inside_strict_era5 = inside(out.banana030.deficit_diff_mm, tol.strict_era5_regulated_to_dense_mm);
  return out;
}
const cmp = { A: compare(A), B: compare(B), C: compare(C) };

// ---------- ¿Qué bananaCover reproduce el aumento de ETc de la auditoría? (regulado +120.73 mm, denso contra limpio +294.36 mm) ----------
const targets = { regulated: auditRef.era5.demand_diff_regulated_mm, dense: auditRef.era5.demand_diff_dense_vs_clean_mm };
function solveCover(target, run, lo, hi, fn) {
  const alone = runCase(CASES[0], run, lo, hi).demand_mm;
  let a = 0, b = 1;
  for (let it = 0; it < 60; it++) { const m = (a + b) / 2; const v = fn(m).demand_mm - alone; if (v < target) a = m; else b = m; }
  return r4((a + b) / 2);
}
const asApp = (run, lo, hi) => (m) => runCase({ shade: 'trees', treeType: 'banana', bananaCover: m }, run, lo, hi);
const noCut = (run, lo, hi) => (m) => runBananaNoCut(m, run, lo, hi);
const solve = (run, lo, hi) => ({
  formula_as_in_app: { regulated: solveCover(targets.regulated, run, lo, hi, asApp(run, lo, hi)), dense: solveCover(targets.dense, run, lo, hi, asApp(run, lo, hi)) },
  banana_use_only_no_evap_cut: { regulated: solveCover(targets.regulated, run, lo, hi, noCut(run, lo, hi)), dense: solveCover(targets.dense, run, lo, hi, noCut(run, lo, hi)) },
});
const cover = { targets_demand_increase_mm: targets, run_A_our_weather: solve(runA, i0, i1), run_B_our_weather_audit_soil: solve(runB, 0, 364), run_C_audit_daily_inputs: solve(runC, 0, 364) };
// Comprobación independiente: con la cobertura derivada solo de la demanda (ETc), ¿qué da el déficit y los días de estrés? (la auditoría, fila ERA5: regulado +96.36 mm y +15 días; denso contra limpio +238.74 mm y +27 días)
const atDerived = (run, derived) => {
  const alone = runCase(CASES[0], run, 0, 364);
  const out = {};
  for (const k of ['regulated', 'dense']) {
    const m = runCase({ shade: 'trees', treeType: 'banana', bananaCover: derived[k] }, run, 0, 364);
    out[k] = { cover: derived[k], demand_diff_mm: r2(m.demand_mm - alone.demand_mm), deficit_diff_mm: r2(m.deficit_mm - alone.deficit_mm), stress_days_ks_lt_095_diff: m.days_ks_lt_095 - alone.days_ks_lt_095 };
  }
  return out;
};
cover.at_derived_cover = { run_B: atDerived(runB, cover.run_B_our_weather_audit_soil.formula_as_in_app), run_C: atDerived(runC, cover.run_C_audit_daily_inputs.formula_as_in_app) };
// Referencia de la fórmula de FAO-56 (sustituir, no sumar): Kc ponderado = (1 - f)·Kc_café + f·Kc_banano; ΔETc ≈ f·(Kc_banano − Kc_café)·ΣET0 (Kc_café 0.95, Kc_banano 1.10 como en nuestro código).
const sumEt0C = sum(ref.et0_power_fao56_mm);
cover.fao56_replacement_formula_on_audit_et0 = {
  note: 'f tal que f·(1.10 − 0.95)·ΣET0 = aumento de ETc de la auditoría; ΣET0 = ET0 FAO-56 NASA POWER de la auditoría',
  sum_et0_mm: r2(sumEt0C),
  regulated: r4(targets.regulated / ((BANANA.kc - 0.95) * sumEt0C)), dense: r4(targets.dense / ((BANANA.kc - 0.95) * sumEt0C)),
};

// ---------- Datos de contexto: en qué difieren nuestras entradas de las congeladas de la auditoría ----------
const context = {
  our_snapshot: { file: 'web/data/snapshots/chiquimula.json', lat: snap.lat, lon: snap.lon, elevation_m: snap.elevation, rain_source: snap.rainSource, rain_2025_mm: r2(sum(slice(snap.rain))), et0_2025_mm: r2(sum(slice(et0All))), temperature: 'NASA POWER Tmax/Tmin corregida por altitud (-0.0065 °C/m) a 403 m' },
  audit_inputs: { lat: ref.site.lat, lon: ref.site.lon, elevation_m: ref.site.elevation_dsm_m, rain_era5_2025_mm: r2(sum(ref.p_era5_mm)), et0_power_fao56_2025_mm: r2(sumEt0C) },
  soil: {
    ours_run_A: { source: 'SoilGrids 0-100 cm del piloto (14.80, -89.54)', thetaFC: pilot.soil.thetaFC, thetaWP: pilot.soil.thetaWP, zr_m: zr, taw_mm: r2(1000 * (pilot.soil.thetaFC - pilot.soil.thetaWP) * zr), cn: pilot.soil.cn },
    ours_run_B_C: { thetaFC: r4(thetaFC), thetaWP, zr_m: zr, taw_mm: tawB },
    audit: { taw_mm_0_100cm: ref.soil.TAW_mm_0_100cm, zr_m: 1.0 },
  },
  max_daily_rain_2025_mm: maxDailyRain,
  runB_runoff_check_mm: { run_B: B.alone.runoff_mm, run_C: C.alone.runoff_mm },
};

const out = {
  meta: {
    task: 40, generatedBy: 'scripts/coffee/verify_banana_audit.mjs',
    audit: 'auditorias/prueba cafe banano 2025/ (origin/main, commit ac37f1b); cifras copiadas en scripts/coffee/banana_audit_reference.json',
    banana_assumption: { kc: BANANA.kc, p: BANANA.p, provisional: BANANA.provisional, rainy_evap_cut_mm_day: 0.52 },
    definitions: 'demanda = Σ ETc del lote (incluye el gasto del banano y resta el recorte de evaporación del suelo en lluvias); ETa = Σ ETa; déficit = demanda − ETa; días con Ks<0.95 y Ks<1 sobre el Ks del café (el que aplica el simulador a la demanda completa del lote). Secano.',
    runs: {
      A: 'simulador tal como lo usa la app: serie continua 2001-2025 (arranque seco en 2001), suelo SoilGrids del piloto, escorrentía SCS-CN, clima del snapshot (ERA5 + POWER corregido); se mide 2025',
      B: 'como A pero con 2025 solo (desde el 1 de enero), TAW 130.7 mm sobre la zona radicular, lluvia efectiva 0.85·P (escorrentía fija 15 %), reserva inicial 25 %',
      C: 'como B pero con las entradas diarias congeladas de la auditoría: ET0 FAO-56 NASA POWER y lluvia ERA5 de su CSV',
    },
    not_matched: [
      'Kc del café: nuestro modelo usa 0.95 constante, la auditoría 0.90/0.95/0.95 por etapas (café solo: ETc de la corrida C frente a 1404.76 de la auditoría)',
      'Zr: la zona radicular del café del simulador es 1.2 m (FAO-56 0.9-1.5); la auditoría usa 1.0 m. Se igualó TAW, no la profundidad',
      'Escorrentía: SCS-CN diario no admite una fracción fija; se aplicó 0.85·P con CN mínimo (escorrentía cero en el modelo, ver runB_runoff_check_mm)',
      'Banano: nuestra fórmula SUMA el gasto del banano (cobertura × 1.10 × ET0 × KsBanana) a la demanda completa del café y resta 0.52 mm/día en lluvias; la auditoría usa un Kc compuesto por variante y Zr y p propios (0.38 regulado, 0.35 denso)',
      'p del lote: nuestro modelo usa p = 0.40 del café para el Ks de todo el lote; la auditoría 0.38 (regulado) y 0.35 (denso)',
      'Suelo de 5 capas de la auditoría frente a una zona radicular + subsuelo en nuestro simulador',
    ],
  },
  tolerances_fixed_before_computing: tol,
  context,
  audit: auditRef,
  run_A: A, run_B: B, run_C: C,
  comparison: cmp,
  cover_that_reproduces_audit_etc_increase: cover,
};
fs.writeFileSync(path.join(root, 'web/data/banana_audit_check.json'), `${JSON.stringify(out, null, 2)}\n`);
console.log(JSON.stringify({ A, B, C, cmp, cover, context, auditRef }, null, 1));
