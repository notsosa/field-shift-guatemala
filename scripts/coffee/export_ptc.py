"""Exporta los pesos de la política "predecir y luego elegir" del café (red embudo 16 -> 64 -> 32 -> 16 -> 1) para poder usarla fuera de este repositorio.
Reentrena con la misma receta, datos y semillas que scripts/coffee/ptc_mlp.py (no cambia nada del diseño), compara la predicción con la que ya estaba guardada
en scripts/coffee/cache/ptc_mlp_seed{S}.json (la que se midió en web/data/coffee_eval.json) y exporta la semilla con la pérdida de validación (2017-2018) más baja.
No toca el caché ni web/data/coffee_eval.json. La utilidad de la red exportada se vuelve a calcular aquí con la misma regla (regar si la predicción supera el precio).
Uso: PYTHONPATH=scripts/emulator C:/Users/velas/venv_lab4/Scripts/python.exe scripts/coffee/export_ptc.py
Escribe web/data/coffee_ptc_mlp.json en el formato que leen mlpPredict (web/js/model/emulator.js) y predecirCapas (scripts/app/dart/red.dart)."""
import json
from pathlib import Path
import numpy as np
import torch
import train_mlp
from train_mlp import fit_network, predict_network, resolve_device

train_mlp.N_OUT = 1
HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
CACHE = HERE / "cache"
SEEDS = [17, 29, 43]
PRICE = {"saveWater": 3, "protectCrop": 1}  # días de estrés: prioridad 0 y 1 (web/js/model/coffee.js, PRICE)
STATE_NAMES = ["daysSinceFlowering", "doy", "rain7", "et0_7", "rain28", "et0_28", "rainSinceNov1", "et0SinceNov1", "dryspell28",
               "tmean28", "tmaxMax28", "runningDepletion", "soilAWmm", "elevation", "shadeTrees", "deciduous"]


def utility(pred, avoided, rows, price):
    irr = pred[rows] > price
    return float(np.where(irr, avoided[rows] - price, 0.0).mean()), int(irr.sum())


def main():
    device, name = resolve_device("cuda")
    tab = json.loads((CACHE / "coffee_table.json").read_text(encoding="utf8"))
    assert tab["meta"]["stateNames"] == STATE_NAMES, "el orden de las entradas cambió"
    sc = tab["scenarios"]
    X = np.array([s["state"] for s in sc], dtype=np.float64)
    Y = np.array([[s["avoided"]] for s in sc], dtype=np.float64)
    avoided = Y[:, 0]
    split = np.array([s["split"] for s in sc])
    year = np.array([s["year"] for s in sc])
    rule = np.array([s["rule"] for s in sc])
    fit_rows = np.isin(split, ["train", "val"])
    test = split == "test"
    reserved = test & (year >= 2022) & (year <= 2024)

    runs = []
    for seed in SEEDS:
        fit = fit_network(X[fit_rows], Y[fit_rows], year[fit_rows].tolist(), device, seed=seed)
        pred = predict_network(fit, X)[:, 0]
        cached = np.array(json.loads((CACHE / f"ptc_mlp_seed{seed}.json").read_text(encoding="utf8"))["pred"])
        same_dec = {k: int(((pred > p) == (cached > p)).sum()) for k, p in PRICE.items()}
        runs.append({"seed": seed, "fit": fit, "pred": pred, "maxDiffVsCached": float(np.abs(pred - cached).max()), "sameDecisionsVsCached": same_dec, "n": len(pred)})
        print(f"seed {seed}: val loss {fit['best']:.5f}, epochs {fit['epochs']}, max |pred - cached| {runs[-1]['maxDiffVsCached']:.3g}, same decisions {same_dec} of {len(pred)}")

    best = min(runs, key=lambda r: r["fit"]["best"])
    fit, pred = best["fit"], best["pred"]
    sd = fit["net"].state_dict()
    layers = [{"W": sd[f"{i}.weight"].cpu().numpy().astype(np.float64).tolist(), "b": sd[f"{i}.bias"].cpu().numpy().astype(np.float64).tolist()} for i in (0, 2, 4, 6)]
    ti = np.where(test)[0]
    sel = ti[np.arange(50) * (len(ti) // 50)]

    def block(rows):
        out = {"n": int(rows.sum())}
        for k, p in PRICE.items():
            u, n_irr = utility(pred, avoided, rows, p)
            ru = float(np.where(rule[rows] == 1, avoided[rows] - p, 0.0).mean())
            out[k] = {"price": p, "meanUtility": u, "irrigations": n_irr, "ruleMeanUtility": ru}
        return out

    out = {
        "kind": "coffee_irrigation_predict_then_choose",
        "target": "stressDaysAvoided: días con Ks < 1 que evita regar 20 mm hoy, en los 30 días siguientes",
        "decision": "regar si la predicción es mayor que el precio: 3 días (prioridad ahorrar agua y trabajo) o 1 día (prioridad proteger el cultivo)",
        "activation": "ReLU en las capas ocultas, salida lineal",
        "standardisation": "x_std = (x - mean) / std por entrada (std 0 -> 1); salida = red(x_std) * yStd + yMean",
        "inputNames": STATE_NAMES,
        "layers": layers, "mean": fit["mean"].tolist(), "std": fit["std"].tolist(), "yMean": fit["ymean"].tolist(), "yStd": fit["ystd"].tolist(),
        "architecture": [fit["n_in"], 64, 32, 16, 1], "params": fit["params"],
        "seed": best["seed"], "selectedBy": "pérdida de validación más baja (años 2017-2018) entre las semillas 17, 29 y 43",
        "valLossBySeed": {str(r["seed"]): r["fit"]["best"] for r in runs},
        "epochs": fit["epochs"], "bestValLoss": fit["best"], "nFit": fit["n_fit"], "nVal": fit["n_val"],
        "device": str(device), "deviceName": name, "torchVersion": torch.__version__,
        "reexport": {
            "note": "reentrenada para exportar los pesos; se compara con la predicción medida en web/data/coffee_eval.json (scripts/coffee/cache/ptc_mlp_seed{S}.json)",
            "bySeed": {str(r["seed"]): {"maxAbsDiffVsMeasured": r["maxDiffVsCached"], "sameDecisionsVsMeasured": r["sameDecisionsVsCached"], "scenarios": r["n"]} for r in runs},
        },
        "utilityOfExported": {"test2019_2024": block(test), "reserved2022_2024": block(reserved)},
        "checkInputs": X[sel].tolist(),
        "checkPredictions": [{"index": int(i), "pred": [float(pred[i])]} for i in sel],
    }
    (ROOT / "web" / "data" / "coffee_ptc_mlp.json").write_text(json.dumps(out), encoding="utf8")
    print(f"exported seed {best['seed']}; utility {json.dumps(out['utilityOfExported'])}")


if __name__ == "__main__":
    main()
