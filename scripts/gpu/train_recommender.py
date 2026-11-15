"""Entrena en GPU la red que recomienda la acción tras perder el maíz (Tarea 31 en JS; Tarea 33 en GPU) con el núcleo compartido scripts/gpu/es_core.py.
Diseño idéntico al de scripts/compare/train_recommender.mjs: embudo 32 -> 64 -> 32 -> 16 -> 1, tanh y salida lineal en cero; puntaje de una acción = (1 si es la de la regla) + tanh(salida);
gana el mayor puntaje (empate de 1e-12: la de la regla; entre otras, dejar el campo y luego el orden de ACTION_IDS); población 32, padres 8, sigma 0.05, elitismo 1, 150 generaciones,
512 escenarios de entrenamiento por generación compartidos por los individuos, las dos prioridades; aptitud = promedio entre prioridades de la media del valor del resultado
(prioridad 0: y; prioridad 1: y - max(0, 0.5 - y)); el campeón de cada generación se puntúa en todo el conjunto de validación y se guarda el mejor.
Una generación = una sola operación por lotes: 32 individuos x 512 escenarios x 2 prioridades x 8 acciones. No hay bucles de Python por individuo ni por escenario, ni .item() dentro de la generación.
OJO: el flujo aleatorio es el del generador CUDA de torch, no mulberry32: mismo diseño y distribuciones, otros números.
Uso: node scripts/compare/train_recommender.mjs --dump ; C:/Users/velas/venv_lab4/Scripts/python.exe scripts/gpu/train_recommender.py [--seeds 17 29 43]
Entrada: scripts/compare/out/recommender_table.json. Salida: scripts/compare/out/recommender_es_seed{S}.json."""
import argparse, json, sys
from pathlib import Path
import torch

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from es_core import layer_sizes, forward, fit_standardization, evolve  # noqa: E402

OUT = HERE.parents[0] / "compare" / "out"
EPS = 1e-12
GENS = 150
NA = 8
ACTIONS = ["maiz", "frijol", "ajonjoli", "papa", "cebolla", "brocoli", "lechuga", "fallow"]
RANK = torch.tensor([0, 1, 2, 3, 4, 5, 6, -1], dtype=torch.float64)  # desempate entre no-regla: dejar el campo primero, luego el orden de ACTION_IDS


def to_tensors(sc, dev):
    f = lambda k: torch.tensor([s[k] for s in sc], dtype=torch.float64, device=dev)
    return {"state": f("state"), "actionRows": f("actionRows"), "y": f("y"), "rule": torch.tensor([s["ruleIdx"] for s in sc], dtype=torch.long, device=dev)}


def build_rows(T, mean, std):
    """-> filas [N, 2 (prioridad), 8 (acción), n_in]: estado, prioridad, fila de la acción (como inputRows en JS); estandarizadas si se dan mean y std."""
    N, S = T["state"].shape
    rows = torch.zeros(N, 2, NA, S + 1 + T["actionRows"].shape[2], dtype=torch.float64, device=T["state"].device)
    rows[..., :S] = T["state"][:, None, None, :]
    rows[..., S] = torch.tensor([0.0, 1.0], dtype=torch.float64, device=rows.device)[None, :, None]
    rows[..., S + 1:] = T["actionRows"][:, None, :, :]
    return rows if mean is None else (rows - mean) / std


def outcome_value(y, pri):
    """Prioridad 0: y. Prioridad 1: y - max(0, 0.5 - y)."""
    return torch.where(pri == 0, y, y - torch.clamp(0.5 - y, min=0.0))


def choose(out, rule):
    """out [P, B, 2, 8] (corrección sin tanh), rule [B] -> (acción elegida [P, B, 2], puntajes [P, B, 2, 8])."""
    onehot = torch.nn.functional.one_hot(rule, NA).to(out.dtype)[None, :, None, :]
    scores = onehot + torch.tanh(out)
    best = scores.amax(-1, keepdim=True)
    tied = scores >= best - EPS
    rank = RANK.to(out.device)
    key = torch.where(tied, rank, torch.full_like(scores, 99.0))
    pick = key.argmin(-1)
    rule_tied = tied.gather(-1, rule[None, :, None, None].expand(out.shape[0], -1, 2, 1)).squeeze(-1)
    return torch.where(rule_tied, rule[None, :, None].expand_as(pick), pick), scores


def fitness(pop, rows, y, rule, sizes):
    """Aptitud [P] = promedio entre prioridades de la media (entre escenarios) del valor del resultado. rows [B, 2, 8, n]; y [B, 8]; rule [B]."""
    B = rows.shape[0]
    out = forward(pop, rows.reshape(-1, rows.shape[-1]), sizes).reshape(pop.shape[0], B, 2, NA)
    pick, _ = choose(out, rule)
    yc = y[None, :, None, :].expand(pop.shape[0], -1, 2, -1).gather(-1, pick.unsqueeze(-1)).squeeze(-1)  # [P, B, 2]
    val = outcome_value(yc, torch.tensor([0.0, 1.0], dtype=torch.float64, device=pop.device)[None, None, :])
    return val.mean(1).mean(1)


def train_seed(seed, tr, va, te, dev):
    sizes = layer_sizes(tr["state"].shape[1] + 1 + tr["actionRows"].shape[2])
    mean, std = fit_standardization(build_rows(tr, None, None))
    rows = {k: build_rows(T, mean, std) for k, T in (("train", tr), ("val", va), ("test", te))}
    res = evolve(seed, sizes, torch.arange(len(tr["rule"]), device=dev), lambda pop, bidx: fitness(pop, rows["train"][bidx], tr["y"][bidx], tr["rule"][bidx], sizes),
                 lambda p: fitness(p, rows["val"], va["y"], va["rule"], sizes)[0], GENS, dev)
    yrule = va["y"].gather(1, va["rule"][:, None]).squeeze(1)
    rule_val = (outcome_value(yrule, torch.tensor(0.0, dtype=torch.float64, device=dev)).mean() + outcome_value(yrule, torch.tensor(1.0, dtype=torch.float64, device=dev)).mean()) / 2
    # comprobación cruzada con JS: puntajes de las 8 acciones, ambas prioridades, en muestras de validación y prueba
    chk = []
    for split, T, step in (("val", va, 17), ("test", te, 5)):
        idx = torch.arange(0, len(T["rule"]), step, device=dev)
        out = forward(res["best_params"][None], rows[split][idx].reshape(-1, rows[split].shape[-1]), sizes).reshape(1, len(idx), 2, NA)
        pick, scores = choose(out, T["rule"][idx])
        ii, pp, ss = idx.cpu().tolist(), pick[0].cpu().tolist(), scores[0].cpu().tolist()
        chk += [{"split": split, "index": ii[k], "priority": p, "scores": ss[k][p], "action": ACTIONS[pp[k][p]]} for k in range(len(ii)) for p in (0, 1)]
    c = res["curve"].cpu().numpy()
    return {
        "seed": seed, "seconds": res["seconds"], "scenarioEvals": res["evals"] * 2, "bestGen": int(res["best_gen"].item()),
        "valFitness": {"first": float(c[0, 2]), "best": float(res["best_val"].item()), "last": float(c[-1, 2]), "initialIdentity": float(res["init_val"].item()), "rule": float(rule_val.item())},
        "curve": [{"gen": i, "trainBest": float(c[i, 0]), "trainMean": float(c[i, 1]), "val": float(c[i, 2])} for i in range(GENS)],
        "layerSizes": sizes, "mean": mean.cpu().tolist(), "std": std.cpu().tolist(), "params": res["best_params"].cpu().tolist(), "check": chk,
    }


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, nargs="+", default=[17, 29, 43])
    args = ap.parse_args()
    dev = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    name = torch.cuda.get_device_name(dev) if dev.type == "cuda" else "CPU"
    print(f"device {dev} ({name}), torch {torch.__version__}")
    tab = json.loads((OUT / "recommender_table.json").read_text(encoding="utf8"))
    tr, va, te = (to_tensors(tab[k], dev) for k in ("train", "val", "test"))
    print({k: len(tab[k]) for k in ("train", "val", "test")}, "inputs", len(tab["inputNames"]))
    for seed in args.seeds:
        r = train_seed(seed, tr, va, te, dev)
        r.update({"device": str(dev), "deviceName": name, "torchVersion": torch.__version__})
        (OUT / f"recommender_es_seed{seed}.json").write_text(json.dumps(r), encoding="utf8")
        v = r["valFitness"]
        print(f"seed {seed}: {r['seconds']:.1f} s ({r['scenarioEvals'] / r['seconds']:.0f} evals/s); val first/best/last {v['first']:.4f}/{v['best']:.4f}/{v['last']:.4f} (gen {r['bestGen']}); identity {v['initialIdentity']:.4f}, rule {v['rule']:.4f}")


if __name__ == "__main__":
    main()
