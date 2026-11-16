"""Entrena y evalua la red alineada con la app (Tarea 34, parte D) y escribe web/data/app_mlp.json y web/data/app_eval.json.
Entradas: scripts/app/cache/{X,Y,RA,RB}.f32 y meta.i16 (los escribe generate_samples.mjs). Division por ANO DE SIEMBRA: entrenamiento 2001-2016,
validacion 2017-2018 (parada temprana), prueba 2019-2024 (reservados 2022-2024 aparte); 2025 no se usa. El conjunto de entrenamiento se submuestrea
a 150 000 filas con semilla fija 17 (conteos en la salida). Modelos, semillas 17/29/43: red embudo N->64->32->16->3 con la receta base de
scripts/emulator/train_mlp.py (fit_network, PyTorch en CUDA) y ELM de GPU (scripts/gpu/elm_gpu.py: 1500 ocultas, escala 0.1, lambda 0.1).
Referencias: (a) lo que muestra la app hoy (RA) y (b) adelanto en seco (RB). Nada se ajusta con la prueba: la mejor semilla se elige por la perdida de validacion.
Uso: C:/Users/velas/venv_lab4/Scripts/python.exe scripts/app/train_eval.py"""
import json, sys, time
from pathlib import Path
import numpy as np
import torch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "emulator"))
sys.path.insert(0, str(ROOT / "scripts" / "gpu"))
from train_mlp import fit_network, predict_network, resolve_device, HIDDEN, N_OUT, VAL_YEARS  # noqa: E402
import elm_gpu  # noqa: E402

CACHE = ROOT / "scripts" / "app" / "cache"
SEEDS = [17, 29, 43]
TRAIN_ROWS = 150_000
SUBSAMPLE_SEED = 17
TARGETS = ["factorFinal", "estres7", "estres14"]
CLASS_THRESHOLD = 0.5  # fijo de antemano: "habra estres" si la prediccion >= 0.5 dia (redondeo al entero mas cercano)


def load():
    info = json.loads((CACHE / "samples_info.json").read_text(encoding="utf8"))
    n, w = info["n"], info["nInputs"]
    f32 = lambda name, k: np.fromfile(CACHE / name, dtype=np.float32).reshape(n, k)
    meta = np.fromfile(CACHE / "meta.i16", dtype=np.int16).reshape(n, 7).astype(np.int64)
    return info, f32("X.f32", w).astype(np.float64), f32("Y.f32", 3).astype(np.float64), f32("RA.f32", 3).astype(np.float64), f32("RB.f32", 3).astype(np.float64), meta


def r2(y, p):
    tot = ((y - y.mean()) ** 2).sum()
    return float(1 - ((y - p) ** 2).sum() / tot) if tot > 0 else None


def metrics(y, p, cls=False):
    out = {"n": int(len(y)), "r2": r2(y, p), "mae": float(np.abs(y - p).mean())}
    if cls:
        t = y >= 1
        q = p >= CLASS_THRESHOLD if cls == "model" else p >= 1
        tp, fp, fn, tn = int((t & q).sum()), int((~t & q).sum()), int((t & ~q).sum()), int((~t & ~q).sum())
        prec = tp / (tp + fp) if tp + fp else None
        rec = tp / (tp + fn) if tp + fn else None
        f1 = 2 * prec * rec / (prec + rec) if prec and rec else (0.0 if prec is not None and rec is not None else None)
        out.update({"tp": tp, "fp": fp, "fn": fn, "tn": tn, "precision": prec, "recall": rec, "f1": f1, "positives": int(t.sum())})
    return out


def block(Y, P, mask, kind):
    """Metricas de los tres objetivos de un modelo (kind = 'model' o 'ref') sobre las filas de `mask`."""
    return {TARGETS[k]: metrics(Y[mask, k], P[mask, k], (kind if k > 0 else False)) for k in range(3)}


def elm_predict(model, X, batch=20000):
    return np.concatenate([elm_gpu.predict(model, X[i:i + batch]) for i in range(0, len(X), batch)])


def main():
    device, device_name = resolve_device("cuda")
    info, X, Y, RA, RB, meta = load()
    year, point, crop, frac = meta[:, 1], meta[:, 0], meta[:, 2], meta[:, 5]
    pilots = [info["points"].index(p) for p in ["chiquimula", "jutiapa", "sanmartin"]]
    is_tr, is_val = (year >= 2001) & (year <= 2016), (year >= 2017) & (year <= 2018)
    is_te = (year >= 2019) & (year <= 2024)
    rng = np.random.default_rng(SUBSAMPLE_SEED)
    tr_all = np.where(is_tr)[0]
    tr_idx = np.sort(rng.choice(tr_all, size=TRAIN_ROWS, replace=False))
    val_idx = np.where(is_val)[0]
    fit_idx = np.concatenate([tr_idx, val_idx])
    counts = {"total": int(len(X)), "trainAvailable": int(len(tr_all)), "trainUsed": int(len(tr_idx)), "validation": int(len(val_idx)), "test": int(is_te.sum()),
              "reserved2022_2024": int((is_te & (year >= 2022)).sum()), "pilotsTest": int((is_te & np.isin(point, pilots)).sum()), "unused2025": int((year == 2025).sum()),
              "subsample": {"seed": SUBSAMPLE_SEED, "method": "numpy default_rng.choice sin reemplazo sobre las filas 2001-2016, luego ordenadas"}}
    print(counts)
    subsets = {"test": is_te, "reserved2022_2024": is_te & (year >= 2022), "pilots": is_te & np.isin(point, pilots), "pilotsReserved2022_2024": is_te & (year >= 2022) & np.isin(point, pilots), "validation": is_val}

    preds, runs = {}, {}
    best = None
    for seed in SEEDS:
        fit = fit_network(X[fit_idx], Y[fit_idx], list(year[fit_idx]), device, seed=seed)
        runs[f"mlp_s{seed}"] = {"seconds": round(fit["train_seconds"], 2), "epochs": fit["epochs"], "bestValLoss": fit["best"], "nFit": fit["n_fit"], "nVal": fit["n_val"], "params": fit["params"]}
        preds[f"mlp_s{seed}"] = predict_network(fit, X)
        print(f"mlp seed {seed}: {fit['epochs']} epocas, val loss {fit['best']:.5f}, {fit['train_seconds']:.1f} s")
        if best is None or fit["best"] < best[0]:
            best = (fit["best"], seed, fit)
    for seed in SEEDS:
        model, secs = elm_gpu.fit_elm(X[tr_idx], Y[tr_idx], seed, device, 1500, 0.1, 0.1)
        runs[f"elm_s{seed}"] = {"seconds": round(secs, 2), "nFit": int(len(tr_idx)), "hidden": 1500, "inputScale": 0.1, "lambda": 0.1}
        preds[f"elm_s{seed}"] = elm_predict(model, X)
        print(f"elm seed {seed}: {secs:.1f} s")
    preds["refApp"], preds["refDry"] = RA, RB

    # Exporta la red con mejor perdida de validacion (formato de mlpPredict de web/js/model/emulator.js).
    _, bseed, bfit = best
    sd = bfit["net"].state_dict()
    layers = [{"W": sd[f"{i}.weight"].cpu().numpy().astype(np.float64).tolist(), "b": sd[f"{i}.bias"].cpu().numpy().astype(np.float64).tolist()} for i in (0, 2, 4, 6)]
    te_idx = np.where(is_te)[0]
    sel = te_idx[np.arange(100) * (len(te_idx) // 100)]
    chk = predict_network(bfit, X[sel])
    export = {"layers": layers, "mean": bfit["mean"].tolist(), "std": bfit["std"].tolist(), "yMean": bfit["ymean"].tolist(), "yStd": bfit["ystd"].tolist(),
              "architecture": [bfit["n_in"], *HIDDEN, N_OUT], "params": bfit["params"], "inputNames": info["inputNames"], "targetNames": TARGETS,
              "seed": bseed, "selectedBy": "perdida de validacion mas baja (years 2017-2018) entre las semillas 17, 29 y 43", "recipe": "base", "epochs": bfit["epochs"], "bestValLoss": bfit["best"],
              "trainSeconds": round(bfit["train_seconds"], 2), "device": device.type, "deviceName": device_name, "torchVersion": torch.__version__, "valYears": VAL_YEARS,
              "nFit": bfit["n_fit"], "nVal": bfit["n_val"], "samples": counts,
              "standardisation": "x_std = (x - mean) / std por entrada (std 0 -> 1); salida = red(x_std) * yStd + yMean",
              "checkInputs": X[sel].tolist(), "checkPredictions": [{"index": int(sel[i]), "pred": chk[i].tolist()} for i in range(100)]}
    (ROOT / "web" / "data" / "app_mlp.json").write_text(json.dumps(export), encoding="utf8")

    # Evaluacion.
    models = list(preds)
    evals = {name: {s: block(Y, P, m, "ref" if name.startswith("ref") else "model") for s, m in subsets.items()} for name, P in preds.items()}
    breakdown = {}
    te = subsets["test"]
    for name, P in preds.items():
        kind = "ref" if name.startswith("ref") else "model"
        breakdown[name] = {
            "byFraction": {str(f): block(Y, P, te & (frac == i), kind) for i, f in enumerate(info["fracs"])},
            "byCrop": {c: block(Y, P, te & (crop == i), kind) for i, c in enumerate(info["crops"])},
        }
    # Veredicto por objetivo y subconjunto: ¿gana el modelo (cada semilla) a cada referencia? Mejor = menor MAE; para estres7/estres14 tambien mayor F1.
    verdicts = {}
    for s in ["test", "reserved2022_2024", "pilots"]:
        verdicts[s] = {}
        for t in TARGETS:
            verdicts[s][t] = {}
            for fam in ["mlp", "elm"]:
                for ref in ["refApp", "refDry"]:
                    seeds = [f"{fam}_s{sd_}" for sd_ in SEEDS]
                    maeWins = [evals[m][s][t]["mae"] < evals[ref][s][t]["mae"] for m in seeds]
                    r2Wins = [evals[m][s][t]["r2"] > evals[ref][s][t]["r2"] for m in seeds]
                    d = {"maeBeatsInSeeds": int(sum(maeWins)), "r2BeatsInSeeds": int(sum(r2Wins)), "seeds": len(seeds),
                         "meanMaeModel": float(np.mean([evals[m][s][t]["mae"] for m in seeds])), "maeRef": evals[ref][s][t]["mae"],
                         "meanR2Model": float(np.mean([evals[m][s][t]["r2"] for m in seeds])), "r2Ref": evals[ref][s][t]["r2"]}
                    if t != "factorFinal":
                        f1 = [evals[m][s][t]["f1"] for m in seeds]
                        d.update({"f1BeatsInSeeds": int(sum(f > evals[ref][s][t]["f1"] for f in f1)), "meanF1Model": float(np.mean(f1)), "f1Ref": evals[ref][s][t]["f1"]})
                    verdicts[s][t][f"{fam}_vs_{ref}"] = d
    # Mejor semilla (exportada): su veredicto aparte.
    out = {"task": 34, "description": "Red alineada con la app: solo entradas que la app tiene el dia de hoy; juez = motor de la app (appEngine.js) con el clima real de NASA POWER de todo el ciclo.",
           "targets": TARGETS, "inputNames": info["inputNames"], "classRule": {"event": "estres >= 1 dia", "modelPositiveIf": f"prediccion >= {CLASS_THRESHOLD}", "referencePositiveIf": "prediccion >= 1 (las referencias son conteos enteros)",
           "note": "umbral fijado antes de mirar la prueba"},
           "split": {"train": "years 2001-2016", "validation": "years 2017-2018", "test": "years 2019-2024", "reserved": "years 2022-2024 (dentro de la prueba)", "pilots": ["chiquimula", "jutiapa", "sanmartin"]},
           "counts": counts, "scenarioGrid": {k: info[k] for k in ["points", "crops", "soils", "fracs", "sowOffsetsDays", "groups", "skippedByCycleEnd", "rowsWithEstimatedDays", "maxAbsStateGapVsFullRun"]},
           "runs": runs, "exportedSeed": bseed, "device": device_name, "torchVersion": torch.__version__,
           "references": {"refApp": "lo que la app muestra hoy: factorFinal ~ factorRendimiento hasta hoy; estres7 ~ dias de estres de los ultimos 7; estres14 ~ min(2 x estres7, 14)",
                          "refDry": "adelanto en seco: motor de la app desde hoy hasta la cosecha sin lluvia y con la ET0 media de los ultimos 7 dias"},
           "metrics": evals, "breakdownTest": breakdown, "verdicts": verdicts}
    (ROOT / "web" / "data" / "app_eval.json").write_text(json.dumps(out), encoding="utf8")
    print("escrito app_mlp.json y app_eval.json; semilla exportada", bseed)


if __name__ == "__main__":
    main()
