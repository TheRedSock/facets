# Tools

Design-time utilities for level authoring, offline baking, and QA. These run headlessly without a scene tree.

## Available

### `run_offline_gem_bake.gd` — Offline Traced Gem Bake Runner

Headless entry point for the traced bake pipeline. Spawns `OfflineGemBakeJob` with CLI-configured options. Uses the native `GemTraceKernel` (C++ + Embree) when the extension is compiled, falling back to the GDScript `GemOpticsTracer` otherwise.

Usage:
```bash
godot --headless --path . --script res://tools/run_offline_gem_bake.gd -- [OPTIONS]
```

Key flags: `--gems`, `--size`, `--draw_size`, `--samples`, `--samples_per_pixel`, `--seed`, `--lighting_preset`, `--lighting_bins`, `--skip_lighting`, `--skip_rotations`, `--rotation_labels`, `--skip_stylize`, `--output`. See AGENTS.md "CLI Bake Reference" for the full flag table.

Example — bake all gems at gameplay size:
```bash
godot --headless --path . --script res://tools/run_offline_gem_bake.gd -- --gems=all --size=112 --samples=2
```

Example — one high-quality Diamond front view without stylization:
```bash
godot --headless --path . --script res://tools/run_offline_gem_bake.gd -- \
    --gems=diamond --size=512 --samples=5 \
    --skip_lighting --rotation_labels=front --skip_stylize \
    --output=res://assets/debug_bakes
```

### `offline_gem_bake_job.gd` — Bake Job Orchestrator

Manages the traced bake pipeline: request building, parallel variant execution, tracer dispatch, PNG output, and manifest writing. Called by both `run_offline_gem_bake.gd` (CLI) and the Gem Bake Workbench (UI). Not invoked directly.

### `run_production_bake.gd` — Production Bake CLI

Headless entry point for profile-driven production bakes. Reads a JSON bake profile and runs the full trace+stylize pipeline for all specified gems. Output goes to `res://generated/traced_bakes/` (gitignored).

Usage:
```bash
godot --headless --path . --script res://tools/run_production_bake.gd -- \
    --profile=res://config/bake_profiles/gameplay.json
```

Exit code 0 on success, 1 on failure. Prints manifest path and entry count on completion.

### `validate_production_bake.gd` — Production Bake Validator

Validates that a production bake matches its profile specification. Checks manifest identity (`profile_id`, `stylize_version`, `samples_per_pixel`), geometry (`cell_size`, `draw_size`, `image_format`), variant settings (atlas layers, grid size, rotation params), tile coverage (all gems in TileRegistry present), mineral template references, texture file existence, and orphan texture detection.

Usage:
```bash
godot --headless --path . --script res://tools/validate_production_bake.gd -- \
    --profile=res://config/bake_profiles/gameplay.json
```

Exit code 0 = valid, nonzero = errors. Use as a CI gate before export.

### `production_bake_profile.gd` — Bake Profile Helper

Shared utility for loading and parsing bake profile JSON files. Used by both `run_production_bake.gd` and `validate_production_bake.gd`. Provides `load_profile_file()`, `resolve_gems_list()`, and `profile_to_bake_options()`. Not invoked directly.

### `rebuild_traced_manifest_from_pngs.gd` — Manifest Rebuild

Rebuilds a gameplay manifest from existing baked image files on disk. Useful when the manifest is deleted or corrupted but the traced texture files are still present.

Usage:
```bash
godot --headless --path . --script res://tools/rebuild_traced_manifest_from_pngs.gd -- \
    --gems=all --size=112
```

### `stitch_rotations.py` — Rotation Atlas (Python)

Requires Python 3 and [Pillow](https://pillow.readthedocs.io/) (`pip install Pillow`).

Scans a traced-bakes directory recursively for rotation frames named `{gem}__rot_{NN}.webp` or `{gem}__rot_{NN}.png` (production bake convention: the `@` variant key becomes `__` on disk). Groups frames by gem, orders rows by tier using `data/tiles/*.tres`, and composites one horizontal row per gem into a single PNG atlas.

By default, non-gameplay-only visuals (material studies, debug quartz, `red_beryl`, etc.) are skipped; use `--include-all` to include them.

### Reviewing “raw” traced output (rotation atlas / material QA)

- **Stylizer:** `offline_gem_bake_job.gd` applies [`GemBakeStylizer`](c:\GIT\facets\core\visuals\gem_bake_stylizer.gd) unless the request sets `skip_stylize: true`. Setting `stylize_mix = 0` on `GemVisualResource` alone does **not** skip the post-process; use `--skip_stylize` on [`run_offline_gem_bake.gd`](c:\GIT\facets\tools\run_offline_gem_bake.gd) or the workbench “Skip stylization” checkbox, or `skip_stylize` in a production profile (`tools/production_bake_profile.gd`).
- **Environment:** Record whether the bake used the default analytical sky/cards from [`build_environment`](c:\GIT\facets\native\src\gem_trace_kernel.cpp) or an HDR map (`environment_profile` / `load_hdr_image` in [`gem_trace_environment.cpp`](c:\GIT\facets\native\src\gem_trace_environment.cpp)). Hue and saturation are lighting-dependent.
- **Production profile (`config/bake_profiles/gameplay.json`):** `default_environment` is `gameplay_studio` (resolved via `production_bake_profile.gd` → tracer environment). The profile does **not** set `skip_stylize`, so production rotation atlases are **stylized** unless you add `"skip_stylize": true` to the JSON or bake via CLI with `--skip_stylize`.
- **Reference run:** The native kernel reads trace request `seed` (see `GemTraceKernel::trace_row_band`, default `42`). Pass `--seed=<int>` to `run_offline_gem_bake.gd` or add `"seed": <int>` to a production profile JSON so pixel RNG is reproducible. Also fix `samples_per_pixel`, `trace_size` / `draw_size`, the same `skip_stylize` + environment so changes are attributable to tracer or `.tres` data.
- **Warm-axis / atlas diagnosis:** Native regression hooks live in `GemTraceKernel::run_physics_tests()` (`tests/test_trace_physics.gd`) — spectral uplift warm-vs-cool, hero-XYZ linearity, ruby-like Beer–Lambert sanity. For **environment vs mineral data**, bake the same gems under `res://data/environments/neutral_warm_reference.tres` and under `gameplay_studio.tres` with identical `--seed`, `--samples_per_pixel`, `--size`, and `--skip_stylize`, then compare. Do **not** retune `GemVisualResource` absorption / phenomenon / gradients until this A/B (and pavilion proportion checks — `tests/test_pavilion_proportions.gd`) show material data is the dominant error.

Example — small hero set, raw tracer output, neutral/warm environment (output under `user://`, manifest listed at end of run):

```bash
godot --headless --path . --script res://tools/run_offline_gem_bake.gd -- \
  --environment=res://data/environments/neutral_warm_reference.tres \
  --gems=ruby,rhodolite,topaz,tourmaline,smoky_quartz,alexandrite \
  --skip_stylize --seed=424242 \
  --output=user://atlas_diagnosis_hero_raw
```

Usage (from the repo root; paths resolve relative to the project root when using defaults):
```bash
python tools/stitch_rotations.py [OPTIONS]
```

| Option | Short | Default | Description |
|--------|-------|---------|-------------|
| `--size` | `-s` | `128` | Frame size in pixels; each frame is scaled to this square. |
| `--input` | `-i` | `generated/traced_bakes/` | Directory to scan (relative to project root unless absolute). |
| `--output` | `-o` | `<input>/rotation_atlas.png` | Output PNG path. |
| `--padding` | `-p` | `2` | Gap in pixels between adjacent frames. |
| `--labels` | `-l` | off | Draw gem name labels on the left of each row. |
| `--include-all` | | off | Include study/debug and other gems excluded by default. |

Examples:
```bash
python tools/stitch_rotations.py
python tools/stitch_rotations.py --size 64 --padding 4
python tools/stitch_rotations.py -i path/to/traced_bakes -o atlas.png --labels
python tools/stitch_rotations.py --include-all
```

### `board_validator.gd` — Board Layout Validator

Validates `BoardLayoutResource` configurations and reports issues:

- **Gravity cycles** — Cells whose gravity paths loop back to themselves (ERROR)
- **Unreachable cells** — Cells that no spawn entry's gravity lane can reach (WARNING)
- **Orphaned spawn entries** — Spawn entries on blocked cells (ERROR)
- **Contention zones** — Cells where multiple gravity paths converge (WARNING)
- **Portal validation** — Out-of-bounds or blocked portal targets (ERROR)

Usage:
```gdscript
var validator := BoardValidator.new()
var issues := validator.validate(layout)
for issue in issues:
    print(issue)  # "[ERROR] ..." or "[WARNING] ..."
```

## Planned

- `balance_simulator.gd` — Headless simulation for testing spawn distributions and merge reachability across thousands of runs
- `board_inspector.gd` — Editor tool for visualizing board state, gravity lanes, and portal connections
- `replay_player.gd` — Tool for replaying recorded game sessions and verifying determinism
