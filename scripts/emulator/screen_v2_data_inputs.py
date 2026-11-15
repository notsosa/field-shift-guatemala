"""Cribado de la Tarea 33, parte B: más datos y más entradas para el emulador v2. Candidatos fijados de antemano; se juzga SOLO en validación (años 2017-2018); tres semillas cada uno.
  base          el v2 de hoy: reservorio de 60 000 muestras, 31 entradas
  data          todas las muestras candidatas que genera el generador (211 680), mismas 31 entradas
  inputs        el reservorio de 60 000 + 16 entradas nuevas (8 de A y 8 de B; ver web/js/model/emulatorV3.js)
  data+inputs   todas las muestras + las 47 entradas
Receta: la de siempre (fit_network de train_mlp.py: embudo n->64->32->16->3, Adam 1e-3, lotes de 256, parada temprana con paciencia 10 sobre 2017-2018; prueba = 2019-2024 o punto reservado, nunca se usa aquí).
Métrica de decisión: error cuadrático medio de las salidas estandarizadas (con la desviación del entrenamiento de `base`) sobre las MISMAS filas de validación para todos los candidatos
(las filas 2017-2018 del reservorio de 60 000; en `data` el conjunto de parada temprana es el de todas las muestras 2017-2018, que las contiene). Se reporta además el R2 de validación por salida.
Regla (fijada antes de correr): gana el menor MSE medio de las tres semillas; se adopta solo si mejora a `base` en al menos 2 % y no empeora el R2 de validación de ninguna salida en más de 0.01 (medias de las tres semillas); si no, se conserva `base`.
Uso: PYTHONPATH=scripts/emulator C:/Users/velas/venv_lab4/Scripts/python.exe scripts/emulator/screen_v2_data_inputs.py   (requiere node scripts/emulator/generate_v3.mjs)
Escribe scripts/emulator/v2_screening.json."""
import json, time
from pathlib import Path
import numpy as np
import torch
from train_mlp import fit_network, predict_network, resolve_device, VAL_YEARS

HERE = Path(__file__).resolve().parent
SEEDS = [17, 29, 43]
N_V2 = 31


def main():
    dev, name = resolve_device("cuda")
    S = json.loads((HERE / "samples_v3_all.json").read_text(encoding="utf8"))
    points = json.loads((HERE / "points.json").read_text(encoding="utf8"))
    held = {p["id"] for p in points if p["heldOut"]}
    X, Y = np.array(S["X"], dtype=np.float64), np.array(S["Y"], dtype=np.float64)
    meta = S["meta"]
    year = np.array([m["year"] for m in meta])
    is_test = np.array([(2019 <= m["year"] <= 2024) or m["pointId"] in held for m in meta])
    res = np.array(S["reservoir"])
    # comprobación: las 31 primeras columnas del reservorio son las filas de samples_v2.json
    v2 = json.loads((HERE / "samples_v2.json").read_text(encoding="utf8"))
    assert np.array_equal(X[res][:, :N_V2], np.array(v2["X"])) and np.array_equal(Y[res], np.array(v2["Y"])), "el reservorio no coincide con samples_v2.json"
    allrows = np.arange(len(X))
    base_tr = res[~is_test[res]]
    ystd0 = Y[base_tr].std(0)
    ymean0 = Y[base_tr].mean(0)
    common = res[(~is_test[res]) & np.isin(year[res], VAL_YEARS)]  # mismas filas de validación para todos
    print(f"device {name}; candidatos {len(X)}; reservorio {len(res)}; entrenamiento base {len(base_tr)}; validación común {len(common)}")
    variants = {"base": (res, N_V2), "data": (allrows, N_V2), "inputs": (res, X.shape[1]), "data+inputs": (allrows, X.shape[1])}
    runs = []
    for vname, (rows, ncol) in variants.items():
        tr = rows[~is_test[rows]]
        for seed in SEEDS:
            fit = fit_network(X[tr][:, :ncol], Y[tr], year[tr].tolist(), dev, seed=seed)
            pred = predict_network(fit, X[common][:, :ncol])
            err = (pred - Y[common]) / ystd0
            mse = float((err ** 2).mean())
            r2 = [float(1 - ((pred[:, o] - Y[common][:, o]) ** 2).sum() / ((Y[common][:, o] - Y[common][:, o].mean()) ** 2).sum()) for o in range(Y.shape[1])]
            runs.append({"variant": vname, "seed": seed, "inputs": ncol, "nTrainRows": int(len(tr)), "nFit": fit["n_fit"], "nVal": fit["n_val"], "epochs": fit["epochs"], "trainSeconds": round(fit["train_seconds"], 2),
                         "ownBestValLoss": fit["best"], "commonValMSE": mse, "valR2": r2})
            print(f"{vname:12s} seed {seed}: {fit['epochs']} épocas, {fit['train_seconds']:.1f} s, MSE común {mse:.5f}, R2 {' '.join(f'{v:.3f}' for v in r2)}", flush=True)
    summ = {}
    for vname in variants:
        rr = [r for r in runs if r["variant"] == vname]
        summ[vname] = {"meanMSE": float(np.mean([r["commonValMSE"] for r in rr])), "mseBySeed": [r["commonValMSE"] for r in rr], "meanR2": np.mean([r["valR2"] for r in rr], axis=0).tolist(), "inputs": rr[0]["inputs"], "nTrainRows": rr[0]["nTrainRows"]}
    winner = min(summ, key=lambda k: summ[k]["meanMSE"])
    improvement = 1 - summ[winner]["meanMSE"] / summ["base"]["meanMSE"]
    r2_worst = float(min(np.array(summ[winner]["meanR2"]) - np.array(summ["base"]["meanR2"])))
    adopt = winner != "base" and improvement >= 0.02 and r2_worst >= -0.01
    out = {
        "meta": {"description": "Task 33 part B screening: more data and more inputs for emulator v2, validation years 2017-2018 only, three seeds each.", "candidates": list(variants), "seeds": SEEDS,
                 "recipe": "fit_network of scripts/emulator/train_mlp.py: funnel n->64->32->16->3, ReLU, Adam 1e-3, batch 256, early stopping (patience 10) on 2017-2018 rows",
                 "metric": "MSE of the standardised outputs (std of base training rows) on the same validation rows for every candidate: the 2017-2018 rows of the 60,000 reservoir (n = %d)" % len(common),
                 "rule": "lowest mean validation MSE over the three seeds wins; adopt only if it improves base by >= 2 % and no output's mean validation R2 gets worse than base by more than 0.01; otherwise keep base",
                 "device": name, "torchVersion": torch.__version__, "generated": time.strftime("%Y-%m-%d"), "samples": {"candidates": len(X), "reservoir": len(res), "featureNames": S["featureNames"], "provenance": S["provenance"]},
                 "testRowsUsed": False},
        "runs": runs, "summary": summ,
        "decision": {"winner": winner, "meanMSEBase": summ["base"]["meanMSE"], "meanMSEWinner": summ[winner]["meanMSE"], "improvementOverBase": improvement, "worstR2ChangeVsBase": r2_worst, "adopt": bool(adopt)},
    }
    (HERE / "v2_screening.json").write_text(json.dumps(out, indent=1), encoding="utf8")
    print("decisión:", out["decision"])


if __name__ == "__main__":
    main()
