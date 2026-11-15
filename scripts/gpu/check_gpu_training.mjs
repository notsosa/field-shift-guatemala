// Comprueba que el ELM en GPU (scripts/gpu/elm_gpu.py) y trainELM de JS dan lo mismo con los mismos pesos ocultos (Tarea 33).
// Uso: C:/Users/velas/venv_lab4/Scripts/python.exe scripts/gpu/elm_gpu.py check ; node scripts/gpu/check_gpu_training.mjs
// Ajusta trainELM (JS) sobre las mismas filas y semilla 42, y compara las predicciones en una muestra de filas con las del archivo de la GPU; escribe web/data/gpu_checks.json (parte "elm").
import fs from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { trainELM, elmPredict } from '../../web/js/model/emulator.js';
import { root, readJson } from '../compare/loss_decision_core.mjs';

const chk = readJson(path.join(root, 'scripts/compare/out/elm_check.json'));
const samples = readJson(chk.samples);
const cfg = { hidden: 1500, inputScale: 0.1, lambda: 0.1, seed: 42 };
const t0 = performance.now();
const js = trainELM(chk.fitRows.map((i) => samples.X[i]), chk.fitRows.map((i) => samples.Y[i]), cfg);
const jsSeconds = (performance.now() - t0) / 1000;
let maxDiff = 0;
chk.probeRows.forEach((r, k) => { const p = elmPredict(js, samples.X[r]); p.forEach((v, o) => { maxDiff = Math.max(maxDiff, Math.abs(v - chk.pred[k][o])); }); });
console.log(`ELM JS vs GPU: ${chk.fitRows.length} filas de ajuste, ${chk.probeRows.length} filas de prueba, diferencia máxima ${maxDiff.toExponential(2)}; JS ${jsSeconds.toFixed(1)} s, GPU ${chk.seconds.toFixed(2)} s`);
if (!(maxDiff < 1e-4)) throw new Error(`ELM JS y GPU discrepan: ${maxDiff}`);
const file = path.join(root, 'web/data/gpu_checks.json');
const prev = fs.existsSync(file) ? readJson(file) : {};
prev.elm = { fitRows: chk.fitRows.length, probeRows: chk.probeRows.length, config: cfg, maxAbsPredictionDiff: maxDiff, tolerance: 1e-4, jsSeconds, gpuSeconds: chk.seconds, device: chk.deviceName, torchVersion: chk.torchVersion, note: 'same hidden weights (mulberry32 port), ridge solved with torch.linalg.cholesky in float64; fit on a sample of the v2 fit rows' };
fs.writeFileSync(file, JSON.stringify(prev, null, 1));
