"""Tarea 28: cribado en VALIDACION de recetas de entrenamiento (de las notas de Alex) para la red embudo v1.
Cuatro recetas fijadas de antemano x semillas 42 y 43: base | sched | resid | sched+resid (ver fit_network).
Lee solo samples.json y usa solo las filas de entrenamiento (no hay metrica de prueba aqui); mide en CUDA y en CPU.
Regla: gana el MSE de validacion (y estandarizado) medio de las 2 semillas mas bajo; si ninguna mejora a base en >= 2 %, se queda base.
Dentro de la receta ganadora se exporta la semilla con menor MSE de validacion. Escribe scripts/emulator/recipe_screening.json.
Uso: PYTHONPATH=scripts/emulator python scripts/emulator/screen_recipes.py"""
import json
from pathlib import Path
import numpy as np
import torch
import train_mlp as T

HERE = Path(__file__).resolve().parent
RECIPES, SEEDS, MIN_GAIN = ["base", "sched", "resid", "sched+resid"], [42, 43], 0.02


def main():
    samples = json.loads((HERE / "samples.json").read_text(encoding="utf8"))
    points = json.loads((HERE / "points.json").read_text(encoding="utf8"))
    held = {p["id"] for p in points if p["heldOut"]}
    X, Y = np.array(samples["X"]), np.array(samples["Y"])
    meta = samples["meta"]
    is_test = np.array([(2019 <= m["year"] <= 2024) or m["pointId"] in held for m in meta])
    Xtr, Ytr = X[~is_test], Y[~is_test]
    years = [m["year"] for m, t in zip(meta, is_test) if not t]
    devs = {"cuda": T.resolve_device("cuda")[0], "cpu": T.resolve_device("cpu")[0]}
    runs = []
    for r in RECIPES:
        for seed in SEEDS:
            kw = T.recipe_kwargs(r, samples["featureNames"], T.V1_MGMT, seed)
            row = {"recipe": r, "seed": seed}
            for dn, dev in devs.items():
                f = T.fit_network(Xtr, Ytr, years, dev, **kw)
                row[dn] = {"epochs": f["epochs"], "seconds": round(f["train_seconds"], 2), "valMse": f["best"]}
            row["valMse"] = row["cuda"]["valMse"]
            print(r, seed, row["cuda"], row["cpu"], flush=True)
            runs.append(row)
    mean = {r: float(np.mean([x["valMse"] for x in runs if x["recipe"] == r])) for r in RECIPES}
    gain = {r: 1 - mean[r] / mean["base"] for r in RECIPES}
    best = min(RECIPES, key=lambda r: mean[r])
    selected = best if best != "base" and gain[best] >= MIN_GAIN else "base"
    seed = min([x for x in runs if x["recipe"] == selected], key=lambda x: x["valMse"])["seed"]
    out = {"rule": __doc__, "device": torch.cuda.get_device_name(0), "torch": torch.__version__, "nFit": int(len(Xtr)), "nTestRowsRead": 0,
           "runs": runs, "meanValMse": mean, "gainVsBase": gain, "lowestMeanRecipe": best, "selected": selected, "selectedSeed": seed}
    (HERE / "recipe_screening.json").write_text(json.dumps(out, indent=1), encoding="utf8")
    print("mean", mean, "gain", gain, "selected", selected, seed)


if __name__ == "__main__":
    main()
