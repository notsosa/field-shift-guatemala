"""Núcleo compartido del entrenamiento por evolución en GPU (PyTorch), sin retropropagación.
Generaliza scripts/coffee/train_es.py (Tarea 32) para que lo usen también el recomendador de pérdida de cultivo (Tarea 33) y el café.
Estrategia (mu, lambda) con elitismo: población P, padres, sigma, elitismo; embudo n_in -> 64 -> 32 -> 16 -> 1, tanh en capas ocultas, salida lineal en cero.
Cada generación evalúa los P individuos sobre un lote de escenarios en UNA operación por lotes (pesos apilados [P, D], bmm): no hay bucle por individuo ni por escenario
y no hay .item() dentro de la generación; los valores vuelven a la CPU una sola vez al final de la semilla.
El flujo aleatorio es el del generador de torch (CUDA, con la semilla), no el mulberry32 de la versión en JS: mismos diseño y distribuciones, otros números.
Orden de los sorteos (fijo): init (capas ocultas), ruido de la población inicial, y por generación: permutación del lote, padres, ruido de los hijos."""
import time
import numpy as np
import torch

HID = [64, 32, 16]
POP, PARENTS, SIGMA, ELITE, BATCH = 32, 8, 0.05, 1, 512


def layer_sizes(n_in):
    return [n_in, *HID, 1]


def n_params(sizes):
    return sum(o * sizes[l] + o for l, o in enumerate(sizes[1:]))


def init_params(gen, sizes, dev):
    """Capas ocultas ~ N(0, 1/fan_in), sesgos 0, capa de salida (pesos y sesgo) en cero."""
    chunks = []
    for l in range(len(sizes) - 1):
        n_in, n_out, last = sizes[l], sizes[l + 1], l == len(sizes) - 2
        w = torch.zeros(n_out * n_in, dtype=torch.float64, device=dev) if last else torch.randn(n_out * n_in, generator=gen, dtype=torch.float64, device=dev) / np.sqrt(n_in)
        chunks += [w, torch.zeros(n_out, dtype=torch.float64, device=dev)]
    return torch.cat(chunks)


def forward(pop, x, sizes):
    """pop [P, D] (pesos planos, mismo orden que recommender.js: por capa, W fila a fila y luego b); x [R, n_in] ya estandarizado -> salida lineal [P, R]."""
    P = pop.shape[0]
    a = x.unsqueeze(0).expand(P, -1, -1)
    o = 0
    for l in range(len(sizes) - 1):
        n_in, n_out = sizes[l], sizes[l + 1]
        W = pop[:, o:o + n_out * n_in].reshape(P, n_out, n_in)
        b = pop[:, o + n_out * n_in:o + n_out * n_in + n_out]
        a = torch.bmm(a, W.transpose(1, 2)) + b.unsqueeze(1)
        if l < len(sizes) - 2:
            a = torch.tanh(a)
        o += n_out * n_in + n_out
    return a.squeeze(-1)


def fit_standardization(raw):
    """Media y desviación poblacional por columna sobre las filas de entrenamiento (raw [..., n]); desviación 0 -> 1."""
    flat = raw.reshape(-1, raw.shape[-1])
    mean, std = flat.mean(0), flat.std(0, unbiased=False)
    return mean, torch.where(std == 0, torch.ones_like(std), std)


def evolve(seed, sizes, train_idx, fit_fn, val_fn, gens, dev, pop=POP, parents=PARENTS, sigma=SIGMA, elite=ELITE, batch=BATCH):
    """Entrena una semilla. fit_fn(pop [P,D], idx [B]) -> aptitud [P] (mayor mejor) sobre los escenarios idx (índices de la tabla);
    val_fn(params [1,D]) -> aptitud escalar en validación. Devuelve tensores en GPU (se pasan a la CPU al final, una vez)."""
    gen = torch.Generator(device=dev).manual_seed(seed)
    init = init_params(gen, sizes, dev)
    D = init.numel()
    popu = init.repeat(pop, 1)
    popu[1:] += sigma * torch.randn(pop - 1, D, generator=gen, dtype=torch.float64, device=dev)  # individuo 0 = la red inicial
    init_val = val_fn(init[None])
    curve = torch.zeros(gens, 3, dtype=torch.float64, device=dev)  # trainBest, trainMean, val
    best_val = torch.tensor(-1e18, dtype=torch.float64, device=dev)
    best_params = init.clone()
    best_gen = torch.tensor(0, device=dev)
    ntr = len(train_idx)
    if dev.type == "cuda":
        torch.cuda.synchronize()
    t0 = time.perf_counter()
    for g in range(gens):
        bidx = train_idx[torch.randperm(ntr, generator=gen, device=dev)[:batch]]
        fit = fit_fn(popu, bidx)
        order = torch.sort(-fit, stable=True).indices  # mayor aptitud primero; empate por índice
        champ = popu[order[0]]
        vfit = val_fn(champ[None])
        curve[g, 0], curve[g, 1], curve[g, 2] = fit[order[0]], fit.mean(), vfit
        better = vfit > best_val
        best_val = torch.where(better, vfit, best_val)
        best_params = torch.where(better, champ, best_params)
        best_gen = torch.where(better, torch.tensor(g, device=dev), best_gen)
        top = order[:parents]
        par = top[torch.randint(0, parents, (pop - elite,), generator=gen, device=dev)]
        children = popu[par] + sigma * torch.randn(pop - elite, D, generator=gen, dtype=torch.float64, device=dev)
        popu = torch.cat([popu[order[:elite]], children])
    if dev.type == "cuda":
        torch.cuda.synchronize()
    seconds = time.perf_counter() - t0
    return {"seconds": seconds, "init_val": init_val, "curve": curve, "best_val": best_val, "best_params": best_params, "best_gen": best_gen, "evals": gens * pop * batch}
