"""Predecir y luego elegir v2 (Tarea 38): la misma red embudo y receta que ptc_mlp.py / export_ptc.py (Adam 1e-3, lotes de 256, parada temprana con paciencia 10 sobre 2017-2018,
semillas 17, 29, 43), con 18 entradas: las 16 del día de la decisión más banana (0/1) y bananaCover. El banano es un SUPUESTO PROVISIONAL, no una medida (ver coffee.js, BANANA).
Un solo guion: entrena las tres semillas, guarda la predicción de todos los escenarios en scripts/coffee/cache/ptc_v2_seed{S}.json y exporta la semilla con la menor pérdida
de validación a web/data/coffee_ptc_mlp_v2.json (mismo formato que coffee_ptc_mlp.json, que no se toca).
Uso: PYTHONPATH=scripts/emulator C:/Users/velas/venv_lab4/Scripts/python.exe scripts/coffee/ptc_mlp_v2.py"""
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
PRICE = {"saveWater": 3, "protectCrop": 1}
STATE_NAMES = ["daysSinceFlowering", "doy", "rain7", "et0_7", "rain28", "et0_28", "rainSinceNov1", "et0SinceNov1", "dryspell28",
               "tmean28", "tmaxMax28", "runningDepletion", "soilAWmm", "elevation", "shadeTrees", "deciduous", "banana", "bananaCover"]
PROVISIONAL = ("Banano = SUPUESTO PROVISIONAL, no medido. (1) Evaporacion del suelo 0.52 mm/dia menor en lluvias (mayo-octubre), como los otros arboles (Padovan et al. 2018, Nicaragua). "
               "(2) Gasto de agua del banano = bananaCover x 1.10 x ET0 x KsBanana por dia, con Kc 1.10 de FAO-56 Tabla 12 (banano de segundo ano, fin de temporada) y KsBanana con p = 0.35 "
               "(FAO-56 Tabla 22): el banano deja de gastar antes que el cafe (p = 0.40). bananaCover = fraccion del suelo cubierta por copa de banano, declarada por el agricultor; "
               "0.15 y 0.30 son convenciones. No es una medida del banano disperso como sombra: el unico estudio de campo (Sarmiento-Soler et al. 2019, Uganda, solo el resumen) vio que la "
               "humedad del suelo bajo 6 % bajo banano y 59 % bajo Cordia, lo que sugiere que el banano real compite menos por agua que este supuesto.")


def utility(pred, avoided, rows, price):
    irr = pred[rows] > price
    return float(np.where(irr, avoided[rows] - price, 0.0).mean()), int(irr.sum())


def main():
    device, name = resolve_device("cuda")
    tab = json.loads((CACHE / "coffee_table_v2.json").read_text(encoding="utf8"))
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
    print(f"device {device} ({name}); fit rows {fit_rows.sum()}, inputs {X.shape[1]}")

    runs = []
    for seed in SEEDS:
        fit = fit_network(X[fit_rows], Y[fit_rows], year[fit_rows].tolist(), device, seed=seed)
        pred = predict_network(fit, X)[:, 0]
        (CACHE / f"ptc_v2_seed{seed}.json").write_text(json.dumps({"seed": seed, "pred": pred.tolist(), "trainSeconds": fit["train_seconds"], "epochs": fit["epochs"], "bestValLoss": fit["best"],
                                                                    "params": fit["params"], "architecture": [fit["n_in"], 64, 32, 16, 1], "device": str(device), "deviceName": name, "torchVersion": torch.__version__}), encoding="utf8")
        runs.append({"seed": seed, "fit": fit, "pred": pred})
        print(f"seed {seed}: val loss {fit['best']:.5f}, epochs {fit['epochs']}, {fit['train_seconds']:.1f} s")

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
        "version": 2,
        "provisional": PROVISIONAL,
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
        "utilityOfExported": {"test2019_2024": block(test), "reserved2022_2024": block(reserved)},
        "checkInputs": X[sel].tolist(),
        "checkPredictions": [{"index": int(i), "pred": [float(pred[i])]} for i in sel],
    }
    (ROOT / "web" / "data" / "coffee_ptc_mlp_v2.json").write_text(json.dumps(out), encoding="utf8")
    print(f"exported seed {best['seed']}; utility {json.dumps(out['utilityOfExported'])}")


if __name__ == "__main__":
    main()
