"""Tarea 19, paso 2 del cribado: entrena la red embudo con la receta estandar (train_mlp.fit_network, semilla 42) sobre
cinco conjuntos de entradas y compara R2 en validacion (years 2017-2018, puntos de entrenamiento).
Lee SOLO scripts/emulator/screening_superset.json (build_screening_superset.mjs), que no contiene filas de prueba:
no hay forma de calcular una metrica de prueba desde aqui. Escribe scripts/emulator/feature_screening.json.
Uso: node scripts/emulator/build_screening_superset.mjs && python scripts/emulator/screen_features.py [--device cpu|cuda]
Conjuntos y regla fijados de antemano (task-19-brief.md); no se agregan candidatas ni se reajustan umbrales."""
import argparse, json
from pathlib import Path
import numpy as np
import train_mlp as T

HERE = Path(__file__).resolve().parent
OUT = HERE / "feature_screening.json"
SETS = {
    "S0": [],
    "S1": ["rainPre30", "drySpellPre20"],
    "S2": ["balancePre30", "balanceSeason", "rainPreSow30"],
    "S3": ["apiFlower", "storeProxy"],
    "S4": ["rainPre30", "drySpellPre20", "balancePre30", "balanceSeason", "rainPreSow30", "apiFlower", "storeProxy"],
}
MIN_GAIN, TIE, BARE_TOL = 0.01, 0.005, 0.005
RULE = (
    "Per set: funnel MLP, standard recipe (train_mlp.fit_network, seed 42), fit on training rows outside the validation years 2017-2018, "
    "R2 per output on the validation rows (training points, years 2017-2018); score = mean of R2(waterIndex) and R2(ksFlowerMain). "
    "A set is excluded if its validation R2(bareFrac) is more than 0.005 below S0's. Choose the highest score among the non-excluded sets; "
    "sets within 0.005 of the best are tied and the one with fewer inputs wins. If the chosen set does not beat S0's score by at least 0.01, "
    "keep S0 (no artifact changes). No test row (years 2019-2024 or held-out points) is read by this script: its only input, "
    "screening_superset.json, does not contain any."
)


def r2(y, p):
    return float(1 - ((y - p) ** 2).sum() / ((y - y.mean()) ** 2).sum())


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", choices=["auto", "cpu", "cuda"], default="cpu")
    args = ap.parse_args()
    device, device_name = T.resolve_device(args.device)
    s = json.loads((HERE / "screening_superset.json").read_text(encoding="utf8"))
    X, E, Y = (np.array(s[k], dtype=np.float64) for k in ("X", "E", "Y"))
    years = np.array(s["year"])
    assert not ((years >= 2019) & (years <= 2024)).any(), "el superconjunto trae filas de prueba"
    names, cand = s["featureNames"], s["candidateNames"]
    ins = names.index("deficitFlower") + 1  # las candidatas van justo despues de las 4 de floracion, como en el modelo final
    is_val = np.isin(years, T.VAL_YEARS)
    results = []
    for sid, extra in SETS.items():
        cols = [cand.index(n) for n in extra]
        Xs = np.concatenate([X[:, :ins], E[:, cols], X[:, ins:]], axis=1)
        feat = names[:ins] + extra + names[ins:]
        assert Xs.shape[1] == len(feat)
        fit = T.fit_network(Xs, Y, years, device)
        pv = T.predict_network(fit, Xs[is_val])
        r = [r2(Y[is_val][:, o], pv[:, o]) for o in range(3)]
        results.append({"id": sid, "added": extra, "nInputs": len(feat), "inputs": feat, "params": fit["params"], "epochs": fit["epochs"],
                        "valR2": dict(zip(s["targetNames"], r)), "score": (r[0] + r[1]) / 2})
        print(f"{sid}: {len(feat)} entradas, val R2 {[round(v, 4) for v in r]}, score {results[-1]['score']:.4f}, epocas {fit['epochs']}")
    s0 = results[0]
    for r in results:
        r["excluded"] = bool(r["valR2"]["bareFrac"] < s0["valR2"]["bareFrac"] - BARE_TOL)
        r["gainVsS0"] = r["score"] - s0["score"]
    ok = [r for r in results if not r["excluded"]]
    best = max(r["score"] for r in ok)
    tied = [r for r in ok if r["score"] >= best - TIE]
    chosen = min(tied, key=lambda r: r["nInputs"])
    selected = chosen["id"] if chosen["gainVsS0"] >= MIN_GAIN else "S0"
    out = {"rule": RULE, "device": device_name, "valYears": T.VAL_YEARS, "nFit": int((~is_val).sum()), "nVal": int(is_val.sum()),
           "nTestRowsRead": 0, "sets": results, "bestScore": best, "tiedWithinHalfPoint": [r["id"] for r in tied],
           "chosenByScore": chosen["id"], "selected": selected, "selectedInputs": next(r for r in results if r["id"] == selected)["inputs"],
           "selectedAdded": next(r for r in results if r["id"] == selected)["added"]}
    OUT.write_text(json.dumps(out, indent=1), encoding="utf8")
    print(f"tied {out['tiedWithinHalfPoint']}, chosen by score {chosen['id']} (gain {chosen['gainVsS0']:+.4f}), selected {selected}; escrito {OUT}")


if __name__ == "__main__":
    main()
