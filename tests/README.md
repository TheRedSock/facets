# Tests

The current engine gate inventory is tools/engine_checks.json. Run
`tools/check_engine.ps1` for CPU checks or add `-Gpu` for windowed GPU/factory
checks. `-Only name1,name2` selects enabled stages; `-List -Gpu` lists them.
Every Godot stage must report its own completion marker. Exit-zero exceptions,
automatic quit before completion, and missing markers fail validation.
`tests/test_check_result.ps1` verifies the stage-result classifier.

Each invocation writes a fresh timestamped directory under `artifacts/checks/`.
Use `-OutputRoot <new-directory>` for a named evidence run. Nonempty destinations
reject before execution. Report-producing stages receive their own destinations;
`run.json` records expected/completed stages and source stability. Historical
reports must never be used as scratch output or overwritten by a rerun.

Numerical tests distinguish source-data regression, analytic/reference evidence,
GPU backend agreement and visual acceptance. A parsed script is not an executed
test; a supported physical mechanism is not necessarily an accepted visual preset.
Optional independent Python checks use `-ReferencePython <environment-python>`.

`test_clips.gd` runs sampling/service checks headlessly and production
planner/worker image checks windowed. GPU tests require a RenderingDevice;
headless runs cannot establish GPU coverage.

Core simulation smoke: `godot --headless --script tests/test_smoke.gd`.
Cross-platform RNG corpus: `godot --headless --script tests/test_rng_cross_platform.gd`.
Long-running balance experiments: `godot --headless res://tests/test_simulation.tscn`.

Logs and artifacts are ignored under artifacts/. See docs/ENGINE_READINESS_REPORT.md
for phase acceptance and core/lapidary/*/CONTRACT.md for detailed contracts.

Gameplay foundation, merge-window and P3 expedition checks are documented in
[tests/game](game/README.md), with current evidence in [P3 status](game/P3_IMPLEMENTATION_STATUS.md). Run:

```powershell
& ./tools/check_engine.ps1 -Only import,source_check,test_smoke,test_rng_cross_platform,test_board_consumer,test_run_delivery,test_game_rules,test_game_state,test_game_transaction,test_game_replay,test_game_playback,test_game_motion
```

The replay corpus has a 30-minute ceiling and 100 explicit seeds. Interrupted
runs are incomplete, even if their first seeds passed. Frozen P0 fixture ownership
and historical smoke dispositions are tracked beside the game tests.

P1-A actual-action presentation measurement is `-Gpu -Only game_action_probe`.
Its report distinguishes functional completion from measured performance targets;
use the executable probe described in the tools guide for release evidence.
