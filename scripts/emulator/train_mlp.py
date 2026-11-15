"""Entrena la red embudo N->64->32->16->3 (PyTorch; N = len(featureNames) de samples.json) y exporta web/data/emulator_mlp.json.
Uso: python scripts/emulator/train_mlp.py [--device auto|cpu|cuda] [--out RUTA] [--cpu-timing RUTA]
  --device      auto (por defecto) = cuda si hay GPU disponible, si no cpu.
  --out         archivo de salida (por defecto web/data/emulator_mlp.json); sirve para una corrida solo de tiempo.
  --cpu-timing  salida de una corrida con --device cpu (mismos datos e hiperparametros) para registrar su tiempo
                junto al de esta corrida (trainSecondsCpu / trainSecondsCuda).
Division identica a evaluate.mjs: prueba = year 2019-2024 O pointId heldOut.
Validacion para parada temprana: filas de entrenamiento de los years 2017-2018 (fuera de los pasos de gradiente).
fit_network() es importable: screen_features.py la usa para el cribado en validacion con la misma receta."""
import argparse, json, time, os
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn

try:
    import psutil
except ImportError:  # psutil es opcional (p. ej. un venv con CUDA sin psutil)
    psutil = None

HERE = Path(__file__).resolve().parent
DEFAULT_OUT = HERE.parent.parent / "web" / "data" / "emulator_mlp.json"
VAL_YEARS = [2017, 2018]
BATCH, MAXEP, PATIENCE = 256, 200, 10
HIDDEN = [64, 32, 16]
N_OUT = 3


def expected_params(n_in):
    h1, h2, h3 = HIDDEN
    return (n_in * h1 + h1) + (h1 * h2 + h2) + (h2 * h3 + h3) + (h3 * N_OUT + N_OUT)


V1_MGMT = ("sequence_", "irrigation_", "texture_", "slope_", "sowOffset30")
V2_MGMT = ("A_", "B_", "soil_")  # igual que la linea base de evaluate.mjs / evaluate_v2.mjs (v2 no agrupa por desfase)


def mgmt_cols(names, prefixes):
    return [i for i, n in enumerate(names) if n.startswith(prefixes)]


def recipe_kwargs(recipe, names, prefixes, seed):
    """Argumentos de fit_network para una receta: base | sched | resid | sched+resid."""
    parts = set(recipe.split("+")) if recipe != "base" else set()
    assert parts <= {"sched", "resid"}, recipe
    return {"seed": seed, "sched": "sched" in parts, "resid_cols": mgmt_cols(names, prefixes) if "resid" in parts else None}


def resolve_device(choice):
    if choice == "cuda" and not torch.cuda.is_available():
        raise SystemExit("--device cuda pedido pero torch.cuda.is_available() es False")
    dev = torch.device("cuda" if choice == "cuda" or (choice == "auto" and torch.cuda.is_available()) else "cpu")
    name = torch.cuda.get_device_name(dev) if dev.type == "cuda" else "CPU"
    return dev, name


def group_keys(X, cols):
    """Clave de grupo de manejo de cada fila: las columnas `cols` formateadas a 6 decimales (igual que emulator.js)."""
    return ["|".join(f"{v + 0.0:.6f}" for v in row) for row in X[:, cols]]


def make_baseline(Xfit, Yfit, cols):
    """Media de cada salida por grupo de manejo, solo con las filas de ajuste; `fallback` = media global (grupo no visto)."""
    keys = group_keys(Xfit, cols)
    table = {}
    for k in sorted(set(keys)):
        table[k] = Yfit[np.array([kk == k for kk in keys])].mean(0).tolist()
    return {"cols": list(cols), "table": table, "fallback": Yfit.mean(0).tolist()}


def baseline_rows(base, X):
    return np.array([base["table"].get(k, base["fallback"]) for k in group_keys(X, base["cols"])], dtype=np.float64)


def fit_network(Xtr, Ytr, tr_years, device, val_years=VAL_YEARS, seed=42, sched=False, resid_cols=None):
    """Receta unica de la red embudo: estandariza con la media/desv. de Xtr/Ytr, Adam 1e-3, lotes de 256,
    parada temprana (paciencia 10) sobre las filas de tr_years en val_years (fuera de los pasos de gradiente).
    sched: reduce el lr a la mitad tras 5 epocas sin mejora en validacion y paciencia 13 (en vez de 10).
    resid_cols: indices de las columnas de manejo; si se dan, la red aprende y - media_por_grupo (calculada solo con las filas de
    ajuste) con la capa de salida en cero. La validacion (`best`) siempre es el MSE de y estandarizado con la desv. de Ytr.
    Devuelve el estado entrenado (net en eval, normalizacion, tiempos, memoria)."""
    n_in = Xtr.shape[1]
    mean, std = Xtr.mean(0), Xtr.std(0)
    std = np.where(std == 0, 1.0, std)
    ymean, ystd = Ytr.mean(0), Ytr.std(0)
    ystd = np.where(ystd == 0, 1.0, ystd)
    Xs = ((Xtr - mean) / std).astype(np.float32)
    is_val = np.isin(np.asarray(tr_years), val_years)
    base = None
    if resid_cols is not None:
        base = make_baseline(Xtr[~is_val], Ytr[~is_val], resid_cols)
        ymean = np.zeros(N_OUT)  # la red predice (y - base) / ystd: sin desplazamiento
        Ys = ((Ytr - baseline_rows(base, Xtr)) / ystd).astype(np.float32)
    else:
        Ys = ((Ytr - ymean) / ystd).astype(np.float32)

    torch.manual_seed(seed)
    torch.cuda.manual_seed_all(seed)
    h1, h2, h3 = HIDDEN
    net = nn.Sequential(nn.Linear(n_in, h1), nn.ReLU(), nn.Linear(h1, h2), nn.ReLU(), nn.Linear(h2, h3), nn.ReLU(), nn.Linear(h3, N_OUT))
    params = sum(p.numel() for p in net.parameters())
    assert params == expected_params(n_in), (params, expected_params(n_in))
    if resid_cols is not None:
        nn.init.zeros_(net[6].weight)
        nn.init.zeros_(net[6].bias)
    net = net.to(device)

    g = torch.Generator().manual_seed(seed)  # orden de lotes en CPU: el mismo en cualquier dispositivo
    vi, ti = torch.from_numpy(np.where(is_val)[0]), torch.from_numpy(np.where(~is_val)[0])
    Xt, Yt = torch.from_numpy(Xs)[ti].to(device), torch.from_numpy(Ys)[ti].to(device)
    Xv, Yv = torch.from_numpy(Xs)[vi].to(device), torch.from_numpy(Ys)[vi].to(device)
    print(f"fit {len(ti)}  val {len(vi)} (years {val_years}, grouped by year)")

    opt = torch.optim.Adam(net.parameters(), lr=1e-3)
    patience = 13 if sched else PATIENCE
    plateau = torch.optim.lr_scheduler.ReduceLROnPlateau(opt, factor=0.5, patience=5, threshold=1e-7, threshold_mode="abs") if sched else None
    lossf = nn.MSELoss()
    proc = psutil.Process(os.getpid()) if psutil else None
    rss0 = peak = proc.memory_info().rss if proc else 0
    if device.type == "cuda":
        torch.cuda.synchronize()
        torch.cuda.reset_peak_memory_stats(device)
        cuda0 = torch.cuda.memory_allocated(device)
    best, best_state, bad, epochs = float("inf"), None, 0, 0
    t0 = time.perf_counter()
    for ep in range(MAXEP):
        epochs = ep + 1
        net.train()
        order = torch.randperm(len(Xt), generator=g).to(device)
        for s in range(0, len(Xt), BATCH):
            b = order[s:s + BATCH]
            opt.zero_grad()
            lossf(net(Xt[b]), Yt[b]).backward()
            opt.step()
        if proc:  # una medicion por epoca (no por lote: era el mayor costo de CPU del bucle)
            peak = max(peak, proc.memory_info().rss)
        net.eval()
        with torch.no_grad():
            vl = lossf(net(Xv), Yv).item()  # .item() sincroniza con la GPU en cada época
        if plateau:
            plateau.step(vl)
        if vl < best - 1e-7:
            best, bad = vl, 0
            best_state = {k: v.clone() for k, v in net.state_dict().items()}
        else:
            bad += 1
            if bad >= patience:
                break
    if device.type == "cuda":
        torch.cuda.synchronize()
    train_seconds = time.perf_counter() - t0
    net.load_state_dict(best_state)
    net.eval()

    if proc:
        measured_mb = round((peak - rss0) / 1048576, 1)
        memory_measured = "trainMemoryMeasuredMB = peak process RSS minus RSS before the training loop (psutil; includes framework/allocator noise)."
    elif device.type == "cuda":
        measured_mb = round((torch.cuda.max_memory_allocated(device) - cuda0) / 1048576, 3)
        memory_measured = "trainMemoryMeasuredMB = torch.cuda.max_memory_allocated() during the training loop minus the GPU memory allocated before it (psutil not installed; GPU tensors only, not host RAM)."
    else:
        measured_mb = None
        memory_measured = "trainMemoryMeasuredMB = null: psutil not installed and the run was on CPU."
    return {"net": net, "device": device, "mean": mean, "std": std, "ymean": ymean, "ystd": ystd, "n_in": n_in, "params": params,
            "train_seconds": train_seconds, "epochs": epochs, "best": best, "n_fit": int(len(ti)), "n_val": int(len(vi)),
            "measured_mb": measured_mb, "memory_measured": memory_measured, "baseline": base}


def predict_network(fit, X):
    """Predicciones en la escala original de Y para filas X sin estandarizar."""
    with torch.no_grad():
        xin = torch.from_numpy(((X - fit["mean"]) / fit["std"]).astype(np.float32)).to(fit["device"])
        out = fit["net"](xin).cpu().numpy().astype(np.float64) * fit["ystd"] + fit["ymean"]
    return out + baseline_rows(fit["baseline"], X) if fit.get("baseline") else out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", choices=["auto", "cpu", "cuda"], default="auto")
    ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
    ap.add_argument("--cpu-timing", type=Path, default=None)
    ap.add_argument("--recipe", choices=["base", "sched", "resid", "sched+resid"], default="base")
    ap.add_argument("--seed", type=int, default=42)
    args = ap.parse_args()
    device, device_name = resolve_device(args.device)
    print(f"device {device} ({device_name}), torch {torch.__version__}")

    samples = json.loads((HERE / "samples.json").read_text(encoding="utf8"))
    points = json.loads((HERE / "points.json").read_text(encoding="utf8"))
    held = {p["id"] for p in points if p["heldOut"]}
    X = np.array(samples["X"], dtype=np.float64)
    Y = np.array(samples["Y"], dtype=np.float64)
    meta = samples["meta"]
    is_test = np.array([(2019 <= m["year"] <= 2024) or m["pointId"] in held for m in meta])
    Xtr, Ytr = X[~is_test], Y[~is_test]
    Xte = X[is_test]
    test_idx = np.where(is_test)[0]
    print(f"train {len(Xtr)}  test {len(Xte)}  heldOut {sorted(held)}  inputs {X.shape[1]}")
    tr_years = [m["year"] for m, t in zip(meta, is_test) if not t]

    fit = fit_network(Xtr, Ytr, tr_years, device, **recipe_kwargs(args.recipe, samples["featureNames"], V1_MGMT, args.seed))
    net, params, n_in = fit["net"], fit["params"], fit["n_in"]
    mean, std, ymean, ystd = fit["mean"], fit["std"], fit["ymean"], fit["ystd"]
    train_seconds, epochs, best = fit["train_seconds"], fit["epochs"], fit["best"]
    print(f"epocas {epochs}, mejor val loss {best:.5f}, {train_seconds:.1f} s en {device_name}")

    analytic = (params * 4 * 4 + BATCH * (n_in + sum(HIDDEN) + N_OUT) * 4 * 2) / 1048576  # pesos+grad+2 estados Adam; activaciones fwd+bwd
    sd = net.state_dict()
    layers = []
    for i in (0, 2, 4, 6):
        layers.append({"W": sd[f"{i}.weight"].cpu().numpy().astype(np.float64).tolist(), "b": sd[f"{i}.bias"].cpu().numpy().astype(np.float64).tolist()})

    stride = len(Xte) // 100
    sel = np.arange(100) * stride
    pred = predict_network(fit, Xte[sel])
    check = [{"index": int(test_idx[sel[i]]), "pred": pred[i].tolist()} for i in range(100)]
    check_inputs = Xte[sel].tolist()

    # Tiempos por dispositivo: el de esta corrida y, si se pasa, el de una corrida en CPU con los mismos datos.
    timing = {"cpu": None, "cuda": None}
    timing[device.type] = round(train_seconds, 2)
    cpu_ref = None
    if args.cpu_timing:
        ref = json.loads(args.cpu_timing.read_text(encoding="utf8"))
        if ref.get("device") != "cpu":
            raise SystemExit(f"--cpu-timing {args.cpu_timing}: no es una corrida en CPU (device {ref.get('device')})")
        timing["cpu"] = ref["trainSeconds"]
        cpu_ref = {"trainSeconds": ref["trainSeconds"], "epochs": ref["epochs"], "torchVersion": ref.get("torchVersion"), "bestValLoss": ref["bestValLoss"]}

    out = {
        "layers": layers, "mean": mean.tolist(), "std": std.tolist(), "yMean": ymean.tolist(), "yStd": ystd.tolist(),
        "architecture": [n_in, *HIDDEN, N_OUT], "params": params, "trainSeconds": round(train_seconds, 2),
        "device": device.type, "deviceName": device_name, "torchVersion": torch.__version__,
        "trainSecondsCpu": timing["cpu"], "trainSecondsCuda": timing["cuda"], "cpuTimingRun": cpu_ref,
        "timingNote": "trainSeconds = this run (the exported weights). trainSecondsCpu / trainSecondsCuda = the same script, data and hyperparameters (batch 256, Adam 1e-3, patience 10) on each device; the CPU figure comes from a separate run whose weights are not exported, and its early stopping may end at a different epoch.",
        "trainMemoryAnalyticMB": round(analytic, 3), "trainMemoryMeasuredMB": fit["measured_mb"],
        "memoryMethod": fit["memory_measured"] + f" trainMemoryAnalyticMB = analytical estimate (the like-for-like figure): params x 4 B x (weights + grad + 2 Adam states) + 2 x batch(256) x activations({n_in} + 64 + 32 + 16 + 3) x 4 B.",
        "recipe": args.recipe, "seed": args.seed, "epochs": epochs, "bestValLoss": best, "valYears": VAL_YEARS, "nFit": fit["n_fit"], "nVal": fit["n_val"], "checkPredictions": check, "checkInputs": check_inputs,
    }
    if fit["baseline"]:
        out["baseline"] = fit["baseline"]
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(out), encoding="utf8")
    print(f"params {params}; memoria analitica {analytic:.3f} MB; medida {fit['measured_mb']} MB; escrito {args.out}")


if __name__ == "__main__":
    main()
