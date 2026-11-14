"""Entrena la red embudo 25->64->32->16->3 (PyTorch, CPU) y exporta web/data/emulator_mlp.json.
Uso: python scripts/emulator/train_mlp.py
Division identica a evaluate.mjs: prueba = year 2019-2024 O pointId heldOut."""
import json, time, os
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn
import psutil

HERE = Path(__file__).resolve().parent
OUT = HERE.parent.parent / "web" / "data" / "emulator_mlp.json"

samples = json.loads((HERE / "samples.json").read_text(encoding="utf8"))
points = json.loads((HERE / "points.json").read_text(encoding="utf8"))
held = {p["id"] for p in points if p["heldOut"]}
X = np.array(samples["X"], dtype=np.float64)
Y = np.array(samples["Y"], dtype=np.float64)
meta = samples["meta"]
is_test = np.array([(2019 <= m["year"] <= 2024) or m["pointId"] in held for m in meta])
Xtr, Ytr = X[~is_test], Y[~is_test]
Xte = X[is_test]
test_idx = np.where(is_test)[0]
print(f"train {len(Xtr)}  test {len(Xte)}  heldOut {sorted(held)}")

mean, std = Xtr.mean(0), Xtr.std(0)
std = np.where(std == 0, 1.0, std)
ymean, ystd = Ytr.mean(0), Ytr.std(0)
ystd = np.where(ystd == 0, 1.0, ystd)
Xs = ((Xtr - mean) / std).astype(np.float32)
Ys = ((Ytr - ymean) / ystd).astype(np.float32)

torch.manual_seed(42)
net = nn.Sequential(nn.Linear(25, 64), nn.ReLU(), nn.Linear(64, 32), nn.ReLU(), nn.Linear(32, 16), nn.ReLU(), nn.Linear(16, 3))
params = sum(p.numel() for p in net.parameters())
assert params == 4323, params

g = torch.Generator().manual_seed(42)
perm = torch.randperm(len(Xs), generator=g)
nval = int(round(0.1 * len(Xs)))
vi, ti = perm[:nval], perm[nval:]
Xt, Yt = torch.from_numpy(Xs)[ti], torch.from_numpy(Ys)[ti]
Xv, Yv = torch.from_numpy(Xs)[vi], torch.from_numpy(Ys)[vi]

opt = torch.optim.Adam(net.parameters(), lr=1e-3)
lossf = nn.MSELoss()
BATCH, MAXEP, PATIENCE = 256, 200, 10
proc = psutil.Process(os.getpid())
rss0 = peak = proc.memory_info().rss
best, best_state, bad, epochs = float("inf"), None, 0, 0
t0 = time.perf_counter()
for ep in range(MAXEP):
    epochs = ep + 1
    net.train()
    order = torch.randperm(len(Xt), generator=g)
    for s in range(0, len(Xt), BATCH):
        b = order[s:s + BATCH]
        opt.zero_grad()
        lossf(net(Xt[b]), Yt[b]).backward()
        opt.step()
        peak = max(peak, proc.memory_info().rss)
    net.eval()
    with torch.no_grad():
        vl = lossf(net(Xv), Yv).item()
    if vl < best - 1e-7:
        best, bad = vl, 0
        best_state = {k: v.clone() for k, v in net.state_dict().items()}
    else:
        bad += 1
        if bad >= PATIENCE:
            break
train_seconds = time.perf_counter() - t0
net.load_state_dict(best_state)
net.eval()
print(f"epocas {epochs}, mejor val loss {best:.5f}, {train_seconds:.1f} s")

rss_mb = (peak - rss0) / 1048576
analytic = (params * 4 * 4 + BATCH * (25 + 64 + 32 + 16 + 3) * 4 * 2) / 1048576  # pesos+grad+2 estados Adam; activaciones fwd+bwd
sd = net.state_dict()
layers = []
for i in (0, 2, 4, 6):
    layers.append({"W": sd[f"{i}.weight"].numpy().astype(np.float64).tolist(), "b": sd[f"{i}.bias"].numpy().astype(np.float64).tolist()})

with torch.no_grad():
    stride = len(Xte) // 100
    sel = np.arange(100) * stride
    xin = torch.from_numpy(((Xte[sel] - mean) / std).astype(np.float32))
    pred = net(xin).numpy().astype(np.float64) * ystd + ymean
check = [{"index": int(test_idx[sel[i]]), "pred": pred[i].tolist()} for i in range(100)]
check_inputs = Xte[sel].tolist()

out = {
    "layers": layers, "mean": mean.tolist(), "std": std.tolist(), "yMean": ymean.tolist(), "yStd": ystd.tolist(),
    "architecture": [25, 64, 32, 16, 3], "params": params, "trainSeconds": round(train_seconds, 2),
    "trainMemoryAnalyticMB": round(analytic, 3), "trainMemoryMeasuredMB": round(rss_mb, 1),
    "memoryMethod": "trainMemoryMeasuredMB = peak process RSS minus RSS before the training loop (psutil; includes framework/allocator noise). trainMemoryAnalyticMB = analytical estimate: params x 4 B x (weights + grad + 2 Adam states) + 2 x batch(256) x activations(140) x 4 B.",
    "epochs": epochs, "bestValLoss": best, "checkPredictions": check, "checkInputs": check_inputs,
}
OUT.write_text(json.dumps(out), encoding="utf8")
print(f"params {params}; memoria analitica {analytic:.3f} MB; delta RSS pico {rss_mb:.1f} MB; escrito {OUT}")
