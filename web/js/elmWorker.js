// Entrena la ELM fuera del hilo principal para que la página siga respondiendo mientras resuelve HᵀH.
import { trainELM } from './model/emulator.js';

self.onmessage = ({ data }) => {
  try {
    const t0 = performance.now();
    const model = trainELM(data.X, data.Y, data.options);
    const seconds = (performance.now() - t0) / 1000;
    const buffers = [model.mean, model.std, model.yMean, model.yStd, model.W, model.b, model.beta].map((a) => a.buffer);
    self.postMessage({ ok: true, model, seconds }, buffers);
  } catch (err) {
    self.postMessage({ ok: false, error: String(err?.message ?? err) });
  }
};
