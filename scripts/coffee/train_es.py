"""Entrena la red que recomienda el riego del café (Tarea 32) con la estrategia de evolución de web/js/model/recommender.js, en GPU (PyTorch).
Mismo diseño que la versión en JS: embudo N -> 64 -> 32 -> 16 -> 1, tanh en capas ocultas, salida lineal en cero; puntaje de una acción = (1 si es la de la regla) + tanh(salida);
población 32, padres 8, sigma 0.05, elitismo 1, 150 generaciones, 512 escenarios de entrenamiento compartidos por generación, las dos prioridades y las dos acciones;
aptitud = promedio entre prioridades de la utilidad media; el campeón de cada generación se puntúa en validación y se guarda el mejor.
Una generación evalúa los 32 individuos en los 512 escenarios en una sola operación por lotes (pesos apilados [P, ...], bmm); no hay bucle por individuo ni por escenario
y no hay .item() dentro de la generación: los valores vuelven a la CPU una vez al final de la semilla.
OJO: el flujo aleatorio es el de torch (generador CUDA con la semilla), no el mulberry32 de la versión en JS: mismos diseño y distribuciones, otros números.
Uso: C:/Users/velas/venv_lab4/Scripts/python.exe scripts/coffee/train_es.py [--seeds 17 29 43] [--generations 150]
Entrada: scripts/coffee/cache/coffee_table.json (node scripts/coffee/scenarios.mjs). Salida: scripts/coffee/cache/es_seed{S}.json."""
import argparse, json, sys
from pathlib import Path
import torch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "gpu"))
from es_core import layer_sizes, n_params, init_params, forward, fit_standardization, evolve, POP, PARENTS, SIGMA, ELITE, BATCH, HID  # noqa: F401  (núcleo compartido, Tarea 33)

HERE = Path(__file__).resolve().parent
CACHE = HERE / "cache"
PRICE = torch.tensor([3.0, 1.0], dtype=torch.float64)  # prioridad 0: 3 días de estrés; prioridad 1: 1 día
EPS = 1e-12


def build_rows(state, mean, std):
    """state [N, S] -> filas estandarizadas [N, 2 (prioridad), 2 (acción: 0 no regar, 1 regar), S + 2]."""
    N = state.shape[0]
    rows = torch.zeros(N, 2, 2, state.shape[1] + 2, dtype=torch.float64, device=state.device)
    rows[..., :state.shape[1]] = state[:, None, None, :]
    rows[..., state.shape[1]] = torch.tensor([0.0, 1.0], dtype=torch.float64, device=state.device)[None, :, None]
    rows[..., state.shape[1] + 1] = torch.tensor([0.0, 1.0], dtype=torch.float64, device=state.device)[None, None, :]
    return (rows - mean) / std


def decide(out, rule):
    """out [P, B, 2, 2] (corrección sin tanh) y regla [B] -> decisión de regar [P, B, 2] (1/0). Empate (±1e-12) -> la de la regla."""
    s_not = (1 - rule)[None, :, None] + torch.tanh(out[..., 0])
    s_irr = rule[None, :, None] + torch.tanh(out[..., 1])
    diff = s_irr - s_not
    return torch.where(diff.abs() <= EPS, rule[None, :, None].expand_as(diff), (diff > 0).to(torch.float64)), s_not, s_irr


def fitness(pop, rows, rule, util, sizes):
    """Utilidad media por individuo, promediada entre prioridades. rows [B,2,2,n]; util [B,2] = utilidad de regar."""
    B = rows.shape[0]
    out = forward(pop, rows.reshape(-1, rows.shape[-1]), sizes).reshape(pop.shape[0], B, 2, 2)
    irr, _, _ = decide(out, rule)
    return (irr * util[None]).mean(1).mean(1)  # [P]


def train_seed(seed, T, gens, dev):
    S = T["state"]
    sizes = layer_sizes(S.shape[1] + 2)
    tr, va = T["idx"]["train"], T["idx"]["val"]
    # estandarización con filas de entrenamiento: escenario x prioridad x acción (población, como fitStandardization de JS)
    raw = torch.zeros(len(tr), 2, 2, S.shape[1] + 2, dtype=torch.float64, device=dev)
    raw[..., :S.shape[1]] = S[tr][:, None, None, :]
    raw[..., S.shape[1]] = torch.tensor([0.0, 1.0], dtype=torch.float64, device=dev)[None, :, None]
    raw[..., S.shape[1] + 1] = torch.tensor([0.0, 1.0], dtype=torch.float64, device=dev)[None, None, :]
    mean, std = fit_standardization(raw)
    rows = build_rows(S, mean, std)
    util = T["avoided"][:, None] - PRICE.to(dev)[None, :]
    rule = T["rule"]
    val_rows, val_rule, val_util = rows[va], rule[va], util[va]
    res = evolve(seed, sizes, tr, lambda pop, bidx: fitness(pop, rows[bidx], rule[bidx], util[bidx], sizes),
                 lambda p: fitness(p, val_rows, val_rule, val_util, sizes)[0], gens, dev)  # los 32 individuos x 512 escenarios x 2 prioridades x 2 acciones, en un solo lote
    seconds, evals = res["seconds"], res["evals"] * 2
    best_params, best_val, best_gen, curve, init_val = res["best_params"], res["best_val"], res["best_gen"], res["curve"], res["init_val"]
    rule_val = (rule[va][:, None] * val_util).mean()
    # comprobación cruzada con JS: puntajes de las 4 filas (prioridad x acción) en una muestra de escenarios de validación y prueba
    chk = torch.cat([T["idx"]["val"][::6], T["idx"]["test"][::13]])
    out = forward(best_params[None], rows[chk].reshape(-1, rows.shape[-1]), sizes).reshape(1, len(chk), 2, 2)
    irr, s_not, s_irr = decide(out, rule[chk])
    check = {"index": chk.cpu().tolist(), "sNot": s_not[0].cpu().tolist(), "sIrr": s_irr[0].cpu().tolist(), "irrigate": irr[0].cpu().tolist()}
    c = curve.cpu().numpy()
    return {
        "seed": seed, "seconds": seconds, "scenarioEvals": evals, "scenarioEvalsPerSecond": evals / seconds, "bestGen": int(best_gen.item()),
        "valFitness": {"first": float(c[0, 2]), "best": float(best_val.item()), "last": float(c[-1, 2]), "initialIdentity": float(init_val.item()), "rule": float(rule_val.item())},
        "curve": [{"gen": i, "trainBest": float(c[i, 0]), "trainMean": float(c[i, 1]), "val": float(c[i, 2])} for i in range(gens)],
        "layerSizes": sizes, "mean": mean.cpu().tolist(), "std": std.cpu().tolist(), "params": best_params.cpu().tolist(), "check": check,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, nargs="+", default=[17, 29, 43])
    ap.add_argument("--generations", type=int, default=150)
    ap.add_argument("--table", default=str(CACHE / "coffee_table.json"))
    ap.add_argument("--out", default=str(CACHE))
    args = ap.parse_args()
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"device {dev} ({torch.cuda.get_device_name(dev) if dev.type == 'cuda' else 'CPU'}), torch {torch.__version__}")
    tab = json.loads(Path(args.table).read_text(encoding="utf8"))
    sc = tab["scenarios"]
    T = {
        "state": torch.tensor([s["state"] for s in sc], dtype=torch.float64, device=dev),
        "avoided": torch.tensor([s["avoided"] for s in sc], dtype=torch.float64, device=dev),
        "rule": torch.tensor([s["rule"] for s in sc], dtype=torch.float64, device=dev),
        "idx": {k: torch.tensor([i for i, s in enumerate(sc) if s["split"] == k], dtype=torch.long, device=dev) for k in ("train", "val", "test")},
    }
    print({k: len(v) for k, v in T["idx"].items()}, "inputs", T["state"].shape[1] + 2)
    for seed in args.seeds:
        r = train_seed(seed, T, args.generations, dev)
        r["device"] = str(dev)
        r["deviceName"] = torch.cuda.get_device_name(dev) if dev.type == "cuda" else "CPU"
        r["torchVersion"] = torch.__version__
        Path(args.out, f"es_seed{seed}.json").write_text(json.dumps(r), encoding="utf8")
        print(f"seed {seed}: {r['seconds']:.1f} s ({r['scenarioEvalsPerSecond']:.0f} evals/s); val first/best/last {r['valFitness']['first']:.4f}/{r['valFitness']['best']:.4f}/{r['valFitness']['last']:.4f} (gen {r['bestGen']}); identity {r['valFitness']['initialIdentity']:.4f}, rule {r['valFitness']['rule']:.4f}")


if __name__ == "__main__":
    main()
