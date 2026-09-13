# Tests

The current engine gate inventory is tools/engine_checks.json. Run
`tools/check_engine.ps1` for CPU checks or add `-Gpu` for windowed GPU/factory
checks. `-Only name1,name2` selects enabled stages; `-List -Gpu` lists them.
Every Godot stage must report its own completion marker. Exit-zero exceptions,
automatic quit before completion, and missing markers fail validation.
`tests/test_check_result.ps1` verifies the stage-result classifier.

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
