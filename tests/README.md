# Tests

Headless tests for the simulation engine and the lapidary (GPU gem) pipeline's CPU-side layers. Everything here runs without a window; GPU-dependent checks live in `tools/` and require a windowed run.

## Core Simulation

```bash
godot --headless --script tests/test_smoke.gd
```

110+ assertions covering the board data layer, match detection, merge mechanic, gravity physics, spawn, cascade pipeline, replay determinism, and board validation. Exit code 0 on success.

Coverage highlights:

- **Data layer** — board creation, `CellState`/`TileState` properties, layouts, portals, `get_neighbor()`, effective gravity priority, board hash determinism
- **Match detection** — match-3, unmatchable breaks, holes, classification (base/4/5+/L-T)
- **Merge mechanic** — removes + survivor upgrade, max-tier pure removal
- **Board physics** — gravity directions, overrides, barriers, diagonal fill, portal routing, convergence, cycle safety
- **Pipeline** — effect planning/conflict/resolution, integer weighted spawn, EventTimeline, full cascade, SeededRng determinism
- **Verification** — deterministic replay, BoardValidator cycles and portal targets

## Lapidary (GPU gem pipeline)

```bash
godot --headless --script tests/lapidary/test_cut_compiler.gd    # cut language -> convex plane sets (30 cuts)
godot --headless --script tests/lapidary/test_species_data.gd    # species/chromophore/grade/stone data layer
godot --headless --script tests/lapidary/test_clips.gd           # clip resources, manifest, cache keys
godot --headless --script tests/lapidary/test_board_consumer.gd  # TileView/GemForge contract (headless side)
```

- `test_cut_compiler.gd` — compiles every silhouette x cut-template combination, validates hulls with the exact face test (polygon clipping), checks solver angles, girdle counts, and pruning.
- `test_species_data.gd` — asserts published n_D and B-G dispersion per species, 81-sample curve invariants, grade ramp monotonicity, stone/tile identity, cut assignments (brilliant everywhere, step on the T6 rectangle tier), fingerprint stability/uniqueness, and a `LapidaryStoneCompiler` consumption smoke.
- GPU rendering itself cannot be tested headlessly (`RenderingDevice` is unavailable under `--headless`); see `tools/kernel_v1_check.gd` and friends.

## Cross-Platform RNG

```bash
godot --headless --script tests/test_rng_cross_platform.gd
```

Prints 100 reference RNG values for seed 42. Run on each target platform and compare; matching output means integer RNG is cross-platform safe.

## Balance Simulation Harness

```bash
godot --headless res://tests/test_simulation.tscn
```

Runs N full games with a greedy swap picker and prints per-run and aggregate statistics. Slow; for balance work, not CI.
