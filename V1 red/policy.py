"""Shared neural action scorer. Scenarios and sublots share one policy's weights."""

from __future__ import annotations

import math
from collections.abc import Callable

import torch
from torch import Tensor, nn
from torch.func import functional_call, vmap


def _encoder(input_dim: int, output_dim: int = 32) -> nn.Sequential:
    return nn.Sequential(nn.Linear(input_dim, 64), nn.SiLU(), nn.Linear(64, output_dim))


def _masked_softmax(logits: Tensor, valid: Tensor) -> Tensor:
    """Returns zero weights for rows with no observations or valid keys."""
    probabilities = logits.masked_fill(~valid, torch.finfo(logits.dtype).min).softmax(-1)
    return probabilities.masked_fill(~valid, 0.0)


class _SequenceEncoder(nn.Module):
    """Summarizes ordered observations without inventing readings at masked dates."""

    def __init__(self, input_dim: int) -> None:
        super().__init__()
        self.value = nn.Linear(input_dim, 32)
        self.position = nn.Linear(2, 32, bias=False)
        self.attention = nn.Linear(32, 1)
        self.output = nn.Linear(32, 32)
        self.missing = nn.Parameter(torch.zeros(32))

    def forward(self, sequence: Tensor, valid: Tensor) -> Tensor:
        steps = sequence.shape[-2]
        positions = torch.linspace(-1, 0, steps, device=sequence.device, dtype=sequence.dtype)
        time_features = torch.stack((positions, positions.square()), dim=-1)
        values = self.value(sequence.masked_fill(~valid.unsqueeze(-1), 0.0))
        values = torch.nn.functional.silu(values + self.position(time_features))
        weights = _masked_softmax(self.attention(values).squeeze(-1), valid)
        pooled = (values * weights.unsqueeze(-1)).sum(dim=-2)
        return torch.where(valid.any(dim=-1, keepdim=True), self.output(pooled), self.missing)


class _ResidualBlock(nn.Module):
    def __init__(self) -> None:
        super().__init__()
        self.layers = nn.Sequential(nn.LayerNorm(64), nn.Linear(64, 64), nn.SiLU(), nn.Linear(64, 64))

    def forward(self, representation: Tensor) -> Tensor:
        return representation + self.layers(representation)


class _SublotAttention(nn.Module):
    """Aggregates other active sublots of the same farm and scenario."""

    def __init__(self) -> None:
        super().__init__()
        self.projection = nn.Linear(64, 192)
        self.output = nn.Linear(64, 64, bias=False)

    def forward(self, nodes: Tensor, active: Tensor) -> Tensor:
        query, key, value = self.projection(nodes).reshape(*nodes.shape[:-1], 3, 4, 16).unbind(-3)
        query, key, value = (part.transpose(-3, -2) for part in (query, key, value))
        logits = query @ key.transpose(-1, -2) / math.sqrt(16)
        not_self = ~torch.eye(nodes.shape[-2], dtype=torch.bool, device=nodes.device)
        valid = active.unsqueeze(-1) & active.unsqueeze(-2) & not_self
        # A zero-logit, zero-value option lets each head attenuate its context
        # even when the farm has only one other active sublot.
        logits = torch.nn.functional.pad(logits, (0, 1))
        valid = torch.nn.functional.pad(valid.unsqueeze(-3), (0, 1), value=True)
        weights = _masked_softmax(logits, valid)[..., :-1]
        context = (weights @ value).transpose(-3, -2).flatten(-2)
        return self.output(context)


class NeuralPolicy(nn.Module):
    """Four 32-d encoders, two residual blocks, farm attention, and an action scorer."""

    def __init__(
        self, static_dim: int, recent_dim: int, history_dim: int, finance_dim: int, action_dim: int,
    ) -> None:
        super().__init__()
        self.input_dimensions = (static_dim, recent_dim, history_dim, finance_dim, action_dim)
        self.static = _encoder(static_dim)
        self.recent = _SequenceEncoder(recent_dim)
        self.history = _SequenceEncoder(history_dim)
        self.finance = _encoder(finance_dim)
        self.fusion = nn.Sequential(nn.Linear(128, 64), nn.SiLU(), _ResidualBlock(), _ResidualBlock())
        self.attention = _SublotAttention()
        self.action = _encoder(action_dim)
        self.score_head = nn.Sequential(
            nn.Linear(160, 64), nn.SiLU(), nn.Linear(64, 32), nn.SiLU(), nn.Linear(32, 1),
        )
        nn.init.zeros_(self.score_head[-1].weight)
        nn.init.zeros_(self.score_head[-1].bias)
        # Cache metadata, not parameter values, so the entire model can evolve.
        offset = 0
        self._layout: list[tuple[str, int, int, torch.Size]] = []
        for name, parameter in self.named_parameters():
            end = offset + parameter.numel()
            self._layout.append((name, offset, end, parameter.shape))
            offset = end
        self.num_parameters = offset

    def initial_vector(self, seed: int = 0) -> Tensor:
        """Reinitialize the full genome deterministically, retaining the exact rule initially."""
        generator = torch.Generator(device="cpu").manual_seed(seed)
        values = []
        for name, parameter in self.named_parameters():
            owner = self.get_submodule(name.rsplit(".", 1)[0])
            if owner is self.score_head[-1] or name.endswith(".missing"):
                value = torch.zeros(parameter.shape, dtype=torch.float32)
            elif isinstance(owner, nn.LayerNorm):
                value = torch.full(parameter.shape, float(name.endswith(".weight")), dtype=torch.float32)
            else:
                bound = 1 / math.sqrt(owner.in_features)
                value = torch.empty(parameter.shape, dtype=torch.float32).uniform_(-bound, bound, generator=generator)
            values.append(value.flatten())
        first_parameter = next(self.parameters())
        return torch.cat(values).to(device=first_parameter.device, dtype=first_parameter.dtype)

    def forward(
        self,
        static: Tensor,
        recent: Tensor,
        history: Tensor,
        finance: Tensor,
        candidate_features: Tensor,
        sublot_mask: Tensor,
        recent_mask: Tensor,
        history_mask: Tensor,
        feasible: Tensor,
        base_scores: Tensor,
    ) -> Tensor:
        valid_sublots = sublot_mask.unsqueeze(-1)
        static_latent = self.static(static.masked_fill(~valid_sublots, 0.0))
        recent_latent = self.recent(recent, recent_mask & valid_sublots)
        history_latent = self.history(history, history_mask & valid_sublots)
        finance_latent = self.finance(finance.masked_fill(~valid_sublots, 0.0))
        latent = self.fusion(torch.cat((static_latent, recent_latent, history_latent, finance_latent), dim=-1))
        context = self.attention(latent, sublot_mask)
        feasible = feasible & valid_sublots
        actions = self.action(candidate_features.masked_fill(~feasible.unsqueeze(-1), 0.0))
        state = torch.cat((latent, context), dim=-1).unsqueeze(-2).expand(*actions.shape[:-1], 128)
        residual = self.score_head(torch.cat((state, actions), dim=-1)).squeeze(-1).tanh()
        return (base_scores + residual).masked_fill(~feasible, -torch.inf)

    def prepare(self, vectors: Tensor) -> Callable[..., Tensor]:
        """Bind [policy, parameter] weights once for repeated evaluation within a rollout."""
        if vectors.ndim != 2 or vectors.shape[1] != self.num_parameters:
            raise ValueError(f"Expected population weights with shape [P, {self.num_parameters}]")
        parameters = {
            name: vectors[:, start:end].reshape(vectors.shape[0], *shape)
            for name, start, end, shape in self._layout
        }

        def call(parameters: dict[str, Tensor], *inputs: Tensor) -> Tensor:
            return functional_call(self, parameters, inputs, strict=True)

        batched = vmap(call)

        def score(
            static: Tensor,
            recent: Tensor,
            history: Tensor,
            finance: Tensor,
            candidate_features: Tensor,
            *,
            sublot_mask: Tensor | None = None,
            recent_mask: Tensor | None = None,
            history_mask: Tensor | None = None,
            feasible: Tensor | None = None,
            base_scores: Tensor | None = None,
        ) -> Tensor:
            # Features are [P, scenario × priority, sublot, ...].
            if sublot_mask is None:
                sublot_mask = torch.ones_like(static[..., 0], dtype=torch.bool)
            if recent_mask is None:
                recent_mask = torch.ones_like(recent[..., 0], dtype=torch.bool)
            if history_mask is None:
                history_mask = torch.ones_like(history[..., 0], dtype=torch.bool)
            if feasible is None:
                feasible = torch.ones_like(candidate_features[..., 0], dtype=torch.bool)
            if base_scores is None:
                base_scores = torch.zeros_like(candidate_features[..., 0])
            return batched(
                parameters, static, recent, history, finance, candidate_features,
                sublot_mask, recent_mask, history_mask, feasible, base_scores,
            )

        return score

    def score(
        self,
        vectors: Tensor,
        static: Tensor,
        recent: Tensor,
        history: Tensor,
        finance: Tensor,
        candidate_features: Tensor,
        **masks_and_scores: Tensor,
    ) -> Tensor:
        """Score the candidates of each scenario using its population member's weights."""
        return self.prepare(vectors)(static, recent, history, finance, candidate_features, **masks_and_scores)
