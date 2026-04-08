# Tools

Design-time utilities for level authoring, offline baking, and QA. These run headlessly without a scene tree.

## Available

### `run_offline_gem_bake.gd` — Offline Traced Gem Bake Runner

Headless entry point for the traced bake pipeline. Spawns `OfflineGemBakeJob` with CLI-configured options. Uses the native `GemTraceKernel` (C++ + Embree) when the extension is compiled, falling back to the GDScript `GemOpticsTracer` otherwise.

Usage:
```bash
godot --headless --path . --script res://tools/run_offline_gem_bake.gd -- [OPTIONS]
```

Key flags: `--gems`, `--size`, `--draw_size`, `--samples`, `--lighting_preset`, `--lighting_bins`, `--skip_lighting`, `--skip_rotations`, `--rotation_labels`, `--skip_stylize`, `--output`. See AGENTS.md "CLI Bake Reference" for the full flag table.

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

Validates that a production bake matches its profile specification. Checks manifest identity (`profile_id`, `stylize_version`, `max_trace_bounces`), geometry (`cell_size`, `draw_size`, `image_format`), variant settings (atlas layers, grid size, rotation params), tile coverage (all gems in TileRegistry present), texture file existence, and orphan texture detection.

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
