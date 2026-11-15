"""ELM en GPU (Tarea 33): mismo modelo que trainELM de web/js/model/emulator.js, con la solución de ridge por torch.linalg.
Capa oculta tanh con W y b fijos ~ U(-inputScale, inputScale) sobre entradas estandarizadas (media y desviación poblacional de las filas de ajuste), salida lineal sin sesgo (beta),
Y estandarizada por columna; beta = (H'H + lambda I)^-1 H'Y. Los pesos ocultos salen del MISMO generador mulberry32 que el de JS (aquí vectorizado: el estado tras k pasos es seed + k*0x6D2B79F5
módulo 2^32, así que cada sorteo se calcula sin bucle), de modo que, con la misma semilla, el modelo es el mismo salvo el redondeo del solucionador.
El resultado se escribe en el mismo formato que devuelve trainELM (arreglos planos W[k*nIn+j], beta[k*nOut+o]) y lo lee elmPredict sin cambios.
Uso:
  python scripts/gpu/elm_gpu.py v2     [--seeds 17 29 43]   ELM del emulador v2 (filas de ajuste de loss_decision_core.mjs) -> scripts/compare/out/elm_v2_seed{S}.json
  python scripts/gpu/elm_gpu.py coffee [--seeds 17 29 43]   ELM del café (filas train de la tabla) -> scripts/coffee/cache/elm_seed{S}.json (predicción de todos los escenarios)
  python scripts/gpu/elm_gpu.py check                        ajuste en una muestra de v2 para comparar con trainELM de JS -> scripts/compare/out/elm_check.json
Los argumentos --samples / --tag cambian el archivo de muestras y la etiqueta de salida (v3)."""
import argparse, json, time, sys
from pathlib import Path
import numpy as np
import torch

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
OUT = ROOT / "scripts" / "compare" / "out"
CFG = {"hidden": 1500, "inputScale": 0.1, "lambda": 0.1}
M32 = 0xFFFFFFFF


def mulberry32_stream(seed, n):
    """Los n primeros números de mulberry32(seed) de emulator.js, vectorizados (uint32 con envoltura, como Math.imul)."""
    k = np.arange(1, n + 1, dtype=np.uint64)
    a = (np.uint64(seed & M32) + k * np.uint64(0x6D2B79F5)) & np.uint64(M32)
    t = a

    def imul(x, y):
        return (x * y) & np.uint64(M32)  # uint64: x, y < 2^32 -> x*y < 2^64 sin desbordar; luego módulo 2^32

    t = imul(t ^ (t >> np.uint64(15)), t | np.uint64(1))
    t = t ^ ((t + imul(t ^ (t >> np.uint64(7)), t | np.uint64(61))) & np.uint64(M32))
    return ((t ^ (t >> np.uint64(14))) & np.uint64(M32)).astype(np.float64) / 4294967296.0


def fit_elm(X, Y, seed, dev, hidden=1500, input_scale=0.1, lam=0.1):
    """X [N, nIn], Y [N, nOut] (numpy float64) -> modelo en el formato de trainELM (listas planas) y segundos."""
    N, n_in = X.shape
    n_out = Y.shape[1]
    mu, sd = X.mean(0), X.std(0)
    sd = np.where(sd == 0, 1.0, sd)
    ym, ys = Y.mean(0), Y.std(0)
    ys = np.where(ys == 0, 1.0, ys)
    r = mulberry32_stream(seed, hidden * n_in + hidden)
    W = (r[:hidden * n_in] * 2 - 1) * input_scale
    b = (r[hidden * n_in:] * 2 - 1) * input_scale
    if dev.type == "cuda":
        torch.cuda.synchronize()
    t0 = time.perf_counter()
    f = lambda a: torch.tensor(a, dtype=torch.float64, device=dev)
    Wt, bt, mut, sdt, ymt, yst = f(W).reshape(hidden, n_in), f(b), f(mu), f(sd), f(ym), f(ys)
    A = lam * torch.eye(hidden, dtype=torch.float64, device=dev)
    B = torch.zeros(hidden, n_out, dtype=torch.float64, device=dev)
    for lo in range(0, N, 16384):  # por bloques de filas: H nunca se guarda entera (con ~120 mil filas ocuparía varios GB)
        H = torch.tanh(((f(X[lo:lo + 16384]) - mut) / sdt) @ Wt.T + bt)
        A += H.T @ H
        B += H.T @ ((f(Y[lo:lo + 16384]) - ymt) / yst)
    beta = torch.cholesky_solve(B, torch.linalg.cholesky(A))
    beta = beta.cpu().numpy()
    seconds = time.perf_counter() - t0  # incluye subir los datos y traer beta a la CPU
    model = {"nIn": n_in, "nOut": n_out, "hidden": hidden, "lambda": lam, "seed": seed, "inputScale": input_scale,
             "mean": mu.tolist(), "std": sd.tolist(), "yMean": ym.tolist(), "yStd": ys.tolist(), "W": W.tolist(), "b": b.tolist(), "beta": beta.reshape(-1).tolist()}
    return model, seconds


def predict(model, X):
    n_in, hidden, n_out = model["nIn"], model["hidden"], model["nOut"]
    Z = (X - np.array(model["mean"])) / np.array(model["std"])
    H = np.tanh(Z @ np.array(model["W"]).reshape(hidden, n_in).T + np.array(model["b"]))
    return (H @ np.array(model["beta"]).reshape(hidden, n_out)) * np.array(model["yStd"]) + np.array(model["yMean"])


def v2_fit_rows(samples, points):
    """Mismas filas de ajuste que loss_decision_core.loadContext: fuera de prueba (2019-2024 o punto reservado) y fuera de validación (2017-2018)."""
    held = {p["id"] for p in points if p["heldOut"]}
    return np.array([i for i, m in enumerate(samples["meta"]) if not ((2019 <= m["year"] <= 2024) or m["pointId"] in held) and m["year"] not in (2017, 2018)])


def device():
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    return dev, (torch.cuda.get_device_name(dev) if dev.type == "cuda" else "CPU")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["v2", "coffee", "check"])
    ap.add_argument("--seeds", type=int, nargs="+", default=[17, 29, 43])
    ap.add_argument("--samples", default=str(ROOT / "scripts" / "emulator" / "samples_v2.json"))
    ap.add_argument("--tag", default="v2")
    ap.add_argument("--n", type=int, default=4000, help="filas de la muestra del modo check")
    args = ap.parse_args()
    dev, name = device()
    meta = {"device": str(dev), "deviceName": name, "torchVersion": torch.__version__}
    OUT.mkdir(parents=True, exist_ok=True)
    if args.mode in ("v2", "check"):
        samples = json.loads(Path(args.samples).read_text(encoding="utf8"))
        points = json.loads((ROOT / "scripts" / "emulator" / "points.json").read_text(encoding="utf8"))
        rows = v2_fit_rows(samples, points)
        X, Y = np.array(samples["X"], dtype=np.float64), np.array(samples["Y"], dtype=np.float64)
        if args.mode == "check":
            fit_rows = rows[:: max(1, len(rows) // args.n)][: args.n]
            model, secs = fit_elm(X[fit_rows], Y[fit_rows], 42, dev, CFG["hidden"], CFG["inputScale"], CFG["lambda"])
            probe = np.arange(0, len(X), max(1, len(X) // 300))[:300]
            (OUT / "elm_check.json").write_text(json.dumps({"fitRows": fit_rows.tolist(), "probeRows": probe.tolist(), "pred": predict(model, X[probe]).tolist(), "seconds": secs, **meta, "samples": args.samples}), encoding="utf8")
            print(f"check: {len(fit_rows)} filas, {secs:.2f} s")
            return
        for seed in args.seeds:
            model, secs = fit_elm(X[rows], Y[rows], seed, dev, CFG["hidden"], CFG["inputScale"], CFG["lambda"])
            (OUT / f"elm_{args.tag}_seed{seed}.json").write_text(json.dumps({"model": model, "trainSeconds": secs, "nFit": int(len(rows)), **meta}), encoding="utf8")
            print(f"seed {seed}: ELM {len(rows)} filas x {X.shape[1]} entradas, {secs:.2f} s")
    else:
        cache = ROOT / "scripts" / "coffee" / "cache"
        sc = json.loads((cache / "coffee_table.json").read_text(encoding="utf8"))["scenarios"]
        S = np.array([s["state"] for s in sc], dtype=np.float64)
        Y = np.array([[s["avoided"]] for s in sc], dtype=np.float64)
        tr = np.array([i for i, s in enumerate(sc) if s["split"] == "train"])
        for seed in args.seeds:
            model, secs = fit_elm(S[tr], Y[tr], seed, dev, CFG["hidden"], CFG["inputScale"], CFG["lambda"])
            (cache / f"elm_seed{seed}.json").write_text(json.dumps({"seed": seed, "pred": predict(model, S)[:, 0].tolist(), "trainSeconds": secs, "nFit": int(len(tr)), **meta}), encoding="utf8")
            print(f"seed {seed}: ELM café {len(tr)} filas, {secs:.2f} s")


if __name__ == "__main__":
    sys.exit(main())
