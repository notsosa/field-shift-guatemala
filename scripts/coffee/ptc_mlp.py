"""Predecir y luego elegir, red embudo (Tarea 32): N -> 64 -> 32 -> 16 -> 1 entrenada con retropropagación en PyTorch (CUDA) para predecir los días de estrés evitados
al regar 20 mm (stressDaysAvoided). Receta = fit_network de scripts/emulator/train_mlp.py (Adam 1e-3, lotes de 256, parada temprana con paciencia 10 sobre 2017-2018,
fuera de los pasos de gradiente); aquí solo se cambia el número de salidas (train_mlp.N_OUT = 1). Entradas: las del día de la decisión (sin prioridad ni acción).
Uso: PYTHONPATH=scripts/emulator C:/Users/velas/venv_lab4/Scripts/python.exe scripts/coffee/ptc_mlp.py [--seeds 17 29 43]
Escribe scripts/coffee/cache/ptc_mlp_seed{S}.json con la predicción para todos los escenarios de la tabla (mismo orden)."""
import argparse, json
from pathlib import Path
import numpy as np
import torch
import train_mlp
from train_mlp import fit_network, predict_network, resolve_device

train_mlp.N_OUT = 1  # fit_network lee N_OUT al llamarse
HERE = Path(__file__).resolve().parent
CACHE = HERE / "cache"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, nargs="+", default=[17, 29, 43])
    ap.add_argument("--device", default="cuda")
    args = ap.parse_args()
    device, name = resolve_device(args.device)
    tab = json.loads((CACHE / "coffee_table.json").read_text(encoding="utf8"))
    sc = tab["scenarios"]
    X = np.array([s["state"] for s in sc], dtype=np.float64)
    Y = np.array([[s["avoided"]] for s in sc], dtype=np.float64)
    split = np.array([s["split"] for s in sc])
    year = np.array([s["year"] for s in sc])
    fit_rows = np.isin(split, ["train", "val"])  # val (2017-2018) solo para la parada temprana, dentro de fit_network
    print(f"device {device} ({name}); fit rows {fit_rows.sum()} (train+val years), inputs {X.shape[1]}")
    for seed in args.seeds:
        fit = fit_network(X[fit_rows], Y[fit_rows], year[fit_rows].tolist(), device, seed=seed)
        pred = predict_network(fit, X)[:, 0]
        out = {"seed": seed, "pred": pred.tolist(), "trainSeconds": fit["train_seconds"], "epochs": fit["epochs"], "bestValLoss": fit["best"], "params": fit["params"],
               "architecture": [fit["n_in"], 64, 32, 16, 1], "device": str(device), "deviceName": name, "torchVersion": torch.__version__, "nFit": fit["n_fit"], "nVal": fit["n_val"]}
        (CACHE / f"ptc_mlp_seed{seed}.json").write_text(json.dumps(out), encoding="utf8")
        print(f"seed {seed}: {fit['epochs']} epocas, {fit['train_seconds']:.1f} s, params {fit['params']}, val loss {fit['best']:.5f}")


if __name__ == "__main__":
    main()
