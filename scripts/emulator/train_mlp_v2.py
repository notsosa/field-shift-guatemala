"""Entrena la red embudo del emulador v2 (N->64->32->16->3) con la receta de train_mlp.py (fit_network) sobre samples_v2.json
y exporta web/data/emulator_v2_mlp.json (mismo formato que lee mlpPredict). Uso: python scripts/emulator/train_mlp_v2.py [--device auto|cpu|cuda]
Division como v1: prueba = year 2019-2024 O pointId heldOut; validacion (parada temprana) = 2017-2018 dentro del entrenamiento."""
import argparse, json
from pathlib import Path
import numpy as np
from train_mlp import fit_network, predict_network, resolve_device, recipe_kwargs, V2_MGMT, HIDDEN, N_OUT, VAL_YEARS

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "web" / "data" / "emulator_v2_mlp.json"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", choices=["auto", "cpu", "cuda"], default="auto")
    ap.add_argument("--recipe", choices=["base", "sched", "resid", "sched+resid"], default="base")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--out", default=None, help="ruta de salida (por defecto web/data/emulator_v2_mlp.json)")
    args = ap.parse_args()
    device, device_name = resolve_device(args.device)
    samples = json.loads((HERE / "samples_v2.json").read_text(encoding="utf8"))
    points = json.loads((HERE / "points.json").read_text(encoding="utf8"))
    held = {p["id"] for p in points if p["heldOut"]}
    X = np.array(samples["X"], dtype=np.float64)
    Y = np.array(samples["Y"], dtype=np.float64)
    meta = samples["meta"]
    is_test = np.array([(2019 <= m["year"] <= 2024) or m["pointId"] in held for m in meta])
    Xtr, Ytr, Xte = X[~is_test], Y[~is_test], X[is_test]
    test_idx = np.where(is_test)[0]
    tr_years = [m["year"] for m, t in zip(meta, is_test) if not t]
    print(f"device {device} ({device_name}); train {len(Xtr)} test {len(Xte)} inputs {X.shape[1]}")
    fit = fit_network(Xtr, Ytr, tr_years, device, **recipe_kwargs(args.recipe, samples["featureNames"], V2_MGMT, args.seed))
    net = fit["net"]
    sd = net.state_dict()
    layers = [{"W": sd[f"{i}.weight"].cpu().numpy().astype(np.float64).tolist(), "b": sd[f"{i}.bias"].cpu().numpy().astype(np.float64).tolist()} for i in (0, 2, 4, 6)]
    sel = np.arange(100) * (len(Xte) // 100)
    pred = predict_network(fit, Xte[sel])
    out = {
        "layers": layers, "mean": fit["mean"].tolist(), "std": fit["std"].tolist(), "yMean": fit["ymean"].tolist(), "yStd": fit["ystd"].tolist(),
        "architecture": [fit["n_in"], *HIDDEN, N_OUT], "params": fit["params"], "trainSeconds": round(fit["train_seconds"], 2),
        "device": device.type, "deviceName": device_name, "recipe": args.recipe, "seed": args.seed, "epochs": fit["epochs"], "bestValLoss": fit["best"], "valYears": VAL_YEARS,
        "nFit": fit["n_fit"], "nVal": fit["n_val"],
        "checkPredictions": [{"index": int(test_idx[sel[i]]), "pred": pred[i].tolist()} for i in range(100)], "checkInputs": Xte[sel].tolist(),
    }
    if fit["baseline"]:
        out["baseline"] = fit["baseline"]
    dest = Path(args.out) if args.out else OUT
    dest.write_text(json.dumps(out), encoding="utf8")
    print(f"epocas {fit['epochs']}, {fit['train_seconds']:.1f} s, params {fit['params']}; escrito {dest}")


if __name__ == "__main__":
    main()
