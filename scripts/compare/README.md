# Decision comparison (sowing delay) and action scorer

Two tools, both on top of the simulator and emulator without changing them. The protocol for the other team is in `proyecto/comparacion-modelos.md` (Spanish); the results are in `proyecto/resultados-modelo-keu.md`, section "Decisiones con información previa".

- `sowing_policy.mjs`: our own decision-maker for one decision (days to wait after the rain-onset rule before sowing the main maize), three engines with the same rule (simulator, funnel network `web/data/emulator_mlp.json`, browser ELM), scored by the simulator and, for the site-soil cases, by AquaCrop. Output: `web/data/decision_eval.json`.
- `score_actions.mjs`: scores recommended actions from **any** model with our simulator. Example input: `example_actions.json`.

The design (sites, years, offsets, priorities, tolerance, information rule) is fixed in advance in `web/js/model/decision.js` and at the top of `sowing_policy.mjs`; the rule text is also stored in `meta.rule` of the output.

## Reproduce `decision_eval.json`
Node 18+ and the AquaCrop environment of `scripts/referee/README.md` (a Python venv with `scripts/referee/requirements.txt`). `<work>` is any scratch folder (`scripts/compare/out/` is git-ignored).
```
node scripts/compare/sowing_policy.mjs prepare --dir <work>
for s in chiquimula jutiapa sanmartin; do
  <venv>/Scripts/python scripts/referee/aquacrop_referee.py --weather <work>/weather_$s.txt --cases <work>/cases_$s.json --out <work>/aq_$s.json
done
node scripts/compare/sowing_policy.mjs score --dir <work>            # writes web/data/decision_eval.json
```
`prepare` writes the weather of each pilot and 42 AquaCrop cases per pilot (6 years x 7 delays; `soil: "site"` already resolved to the pilot's thetaFC/thetaWP, dry start, maize sown on the date `resolveMainSowIdx` gives). `score` fails loudly if a result file, a case, a yield or a sowing date is missing. If `<work>/aquacrop_seconds.txt` exists (seconds the AquaCrop runs took) it is copied to `meta.runtime`.

About 5 s for the policy evaluation (72 cases) and 1 s to train the ELM; about 30 s of wall time for the 126 AquaCrop seasons.

## Score another model's actions
```
node scripts/compare/score_actions.mjs --in scripts/compare/example_actions.json            # JSON to the screen
node scripts/compare/score_actions.mjs --in my_actions.json --out scored.json
```
See the action format in `proyecto/comparacion-modelos.md`. Invalid actions are rejected together, each named by its `id`; nothing is scored until all are valid.

## Tests
`tests/decision.test.mjs` (hand-computed rule, tie-break, information rule, metrics), `tests/sowing_policy.test.mjs` (information rule with the real engines, AquaCrop merge failures), `tests/score_actions.test.mjs`. None needs the network or AquaCrop.
