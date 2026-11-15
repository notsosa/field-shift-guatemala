"""Entrena la red embudo 25->64->32->16->3 (PyTorch) y exporta web/data/emulator_mlp.json.
Uso: python scripts/emulator/train_mlp.py [--device auto|cpu|cuda] [--out RUTA] [--cpu-timing RUTA]
  --device      auto (por defecto) = cuda si hay GPU disponible, si no cpu.
  --out         archivo de salida (por defecto web/data/emulator_mlp.json); sirve para una corrida solo de tiempo.
  --cpu-timing  salida de una corrida con --device cpu (mismos datos e hiperparametros) para registrar su tiempo
                junto al de esta corrida (trainSecondsCpu / trainSecondsCuda).
Division identica a evaluate.mjs: prueba = year 2019-2024 O pointId heldOut.
Validacion para parada temprana: filas de entrenamiento de los years 2017-2018 (fuera de los pasos de gradiente)."""
import argparse, json, time, os
from pathlib import Path
import numpy as np
import torch
import torch.nn as nn

try:
    import psutil
except ImportError:  # psutil es opcional (p. ej. un venv con CUDA sin psutil)
    psutil = None

HERE = Path(__file__).resolve().parent
DEFAULT_OUT = HERE.parent.parent / "web" / "data" / "emulator_mlp.json"

ap = argparse.ArgumentParser()
ap.add_argument("--device", choices=["auto", "cpu", "cuda"], default="auto")
ap.add_argument("--out", type=Path, default=DEFAULT_OUT)
ap.add_argument("--cpu-timing", type=Path, default=None)
args = ap.parse_args()
if args.device == "cuda" and not torch.cuda.is_available():
    raise SystemExit("--device cuda pedido pero torch.cuda.is_available() es False")
device = torch.device("cuda" if args.device == "cuda" or (args.device == "auto" and torch.cuda.is_available()) else "cpu")
device_name = torch.cuda.get_device_name(device) if device.type == "cuda" else "CPU"
print(f"device {device} ({device_name}), torch {torch.__version__}")

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
torch.cuda.manual_seed_all(42)
net = nn.Sequential(nn.Linear(25, 64), nn.ReLU(), nn.Linear(64, 32), nn.ReLU(), nn.Linear(32, 16), nn.ReLU(), nn.Linear(16, 3))
params = sum(p.numel() for p in net.parameters())
assert params == 4323, params
net = net.to(device)

g = torch.Generator().manual_seed(42)  # orden de lotes en CPU: el mismo en cualquier dispositivo
VAL_YEARS = [2017, 2018]
tr_years = np.array([m["year"] for m, t in zip(meta, is_test) if not t])
is_val = np.isin(tr_years, VAL_YEARS)
vi, ti = torch.from_numpy(np.where(is_val)[0]), torch.from_numpy(np.where(~is_val)[0])
Xt, Yt = torch.from_numpy(Xs)[ti].to(device), torch.from_numpy(Ys)[ti].to(device)
Xv, Yv = torch.from_numpy(Xs)[vi].to(device), torch.from_numpy(Ys)[vi].to(device)
print(f"fit {len(ti)}  val {len(vi)} (years {VAL_YEARS}, grouped by year)")

opt = torch.optim.Adam(net.parameters(), lr=1e-3)
lossf = nn.MSELoss()
BATCH, MAXEP, PATIENCE = 256, 200, 10
proc = psutil.Process(os.getpid()) if psutil else None
rss0 = peak = proc.memory_info().rss if proc else 0
if device.type == "cuda":
    torch.cuda.synchronize()
    torch.cuda.reset_peak_memory_stats(device)
    cuda0 = torch.cuda.memory_allocated(device)
best, best_state, bad, epochs = float("inf"), None, 0, 0
t0 = time.perf_counter()
for ep in range(MAXEP):
    epochs = ep + 1
    net.train()
    order = torch.randperm(len(Xt), generator=g).to(device)
    for s in range(0, len(Xt), BATCH):
        b = order[s:s + BATCH]
        opt.zero_grad()
        lossf(net(Xt[b]), Yt[b]).backward()
        opt.step()
        if proc:
            peak = max(peak, proc.memory_info().rss)
    net.eval()
    with torch.no_grad():
        vl = lossf(net(Xv), Yv).item()  # .item() sincroniza con la GPU en cada época
    if vl < best - 1e-7:
        best, bad = vl, 0
        best_state = {k: v.clone() for k, v in net.state_dict().items()}
    else:
        bad += 1
        if bad >= PATIENCE:
            break
if device.type == "cuda":
    torch.cuda.synchronize()
train_seconds = time.perf_counter() - t0
net.load_state_dict(best_state)
net.eval()
print(f"epocas {epochs}, mejor val loss {best:.5f}, {train_seconds:.1f} s en {device_name}")

if proc:
    measured_mb = round((peak - rss0) / 1048576, 1)
    memory_measured = "trainMemoryMeasuredMB = peak process RSS minus RSS before the training loop (psutil; includes framework/allocator noise)."
elif device.type == "cuda":
    measured_mb = round((torch.cuda.max_memory_allocated(device) - cuda0) / 1048576, 3)
    memory_measured = "trainMemoryMeasuredMB = torch.cuda.max_memory_allocated() during the training loop minus the GPU memory allocated before it (psutil not installed; GPU tensors only, not host RAM)."
else:
    measured_mb = None
    memory_measured = "trainMemoryMeasuredMB = null: psutil not installed and the run was on CPU."
analytic = (params * 4 * 4 + BATCH * (25 + 64 + 32 + 16 + 3) * 4 * 2) / 1048576  # pesos+grad+2 estados Adam; activaciones fwd+bwd
sd = net.state_dict()
layers = []
for i in (0, 2, 4, 6):
    layers.append({"W": sd[f"{i}.weight"].cpu().numpy().astype(np.float64).tolist(), "b": sd[f"{i}.bias"].cpu().numpy().astype(np.float64).tolist()})

with torch.no_grad():
    stride = len(Xte) // 100
    sel = np.arange(100) * stride
    xin = torch.from_numpy(((Xte[sel] - mean) / std).astype(np.float32)).to(device)
    pred = net(xin).cpu().numpy().astype(np.float64) * ystd + ymean
check = [{"index": int(test_idx[sel[i]]), "pred": pred[i].tolist()} for i in range(100)]
check_inputs = Xte[sel].tolist()

# Tiempos por dispositivo: el de esta corrida y, si se pasa, el de una corrida en CPU con los mismos datos.
timing = {"cpu": None, "cuda": None}
timing[device.type] = round(train_seconds, 2)
cpu_ref = None
if args.cpu_timing:
    ref = json.loads(args.cpu_timing.read_text(encoding="utf8"))
    if ref.get("device") != "cpu":
        raise SystemExit(f"--cpu-timing {args.cpu_timing}: no es una corrida en CPU (device {ref.get('device')})")
    timing["cpu"] = ref["trainSeconds"]
    cpu_ref = {"trainSeconds": ref["trainSeconds"], "epochs": ref["epochs"], "torchVersion": ref.get("torchVersion"), "bestValLoss": ref["bestValLoss"]}

out = {
    "layers": layers, "mean": mean.tolist(), "std": std.tolist(), "yMean": ymean.tolist(), "yStd": ystd.tolist(),
    "architecture": [25, 64, 32, 16, 3], "params": params, "trainSeconds": round(train_seconds, 2),
    "device": device.type, "deviceName": device_name, "torchVersion": torch.__version__,
    "trainSecondsCpu": timing["cpu"], "trainSecondsCuda": timing["cuda"], "cpuTimingRun": cpu_ref,
    "timingNote": "trainSeconds = this run (the exported weights). trainSecondsCpu / trainSecondsCuda = the same script, data and hyperparameters (batch 256, Adam 1e-3, patience 10) on each device; the CPU figure comes from a separate run whose weights are not exported, and its early stopping may end at a different epoch.",
    "trainMemoryAnalyticMB": round(analytic, 3), "trainMemoryMeasuredMB": measured_mb,
    "memoryMethod": memory_measured + " trainMemoryAnalyticMB = analytical estimate (the like-for-like figure): params x 4 B x (weights + grad + 2 Adam states) + 2 x batch(256) x activations(140) x 4 B.",
    "epochs": epochs, "bestValLoss": best, "valYears": VAL_YEARS, "nFit": int(len(ti)), "nVal": int(len(vi)), "checkPredictions": check, "checkInputs": check_inputs,
}
args.out.parent.mkdir(parents=True, exist_ok=True)
args.out.write_text(json.dumps(out), encoding="utf8")
print(f"params {params}; memoria analitica {analytic:.3f} MB; medida {measured_mb} MB; escrito {args.out}")
