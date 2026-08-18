# Tools

Design-time and QA utilities. Scripts that touch the GPU tracer must run **windowed** (no `--headless`): Godot does not create a `RenderingDevice` in headless mode. Pass `--quit-after` or let the script quit itself.

```bash
godot --path . --script res://tools/<script>.gd          # windowed (GPU available)
godot --headless --path . --script res://tools/<script>.gd  # CPU-only scripts
```

## Lapidary pipeline (GPU)

### `generate_lapidary_data.gd` — Data layer generator (headless OK)

Regenerates `data/lapidary/` from published optical constants: species (Sellmeier fits, birefringence, inclusion vocabularies), chromophores (81-sample absorption curves), grades (t1-t8 ramp), and the 16 stones (main ladder + alternate ladder), wiring cut templates. Prints a Beer-Lambert audit table. Source citations live in each resource's `source_note`.

### `kernel_v1_check.gd` — Tracer feature check

Renders single gems through the full kernel (wear, inclusions, zoning, dispersion, birefringence, print pass) and writes PNGs to `artifacts/`. First stop after touching `gem_pathtrace.glsl` or the stone compiler.

### `rig_ab_check.gd` — Lighting rig A/B

Renders the same stones under two `GemLightRig` resources side by side (`data/lapidary/rigs/`). Use before retuning any per-stone appearance: lighting dominates most "the gem looks wrong" reads.

### `ladder_check.gd` — 8-gem ladder strip

Renders the main merge ladder in tier order to one strip; the fastest whole-catalog eyeball.

### `board_grid_check.gd` — Batch timing

Times 1/16/64-gem batched dispatches per quality rung; prints ms/gem. The numbers behind the sprite-vs-live-3D decision.

### `forge_cold_start_check.gd` — GemForge cold start

Clears the cache, then measures time-to-first-idle and full-catalog generation through the launcher path.

### `eval_sheets.gd` — Evaluation sheets

Composes the montages in `artifacts/eval/`: contact sheet, grade sheet, lighting sheet, rung ladder, clip filmstrips, timing table.

### `package_clips.gd` — Clip packaging

Bakes authored clips (named animations, lighting-relative motion) through `GemForge` and packages them for the board consumer.

### `atelier_screenshot.gd` / `board_visual_check.tscn` — Visual smoke checks

Windowed screenshot harnesses: the first captures the Gem Atelier (progressive preview + clip scrub), the second boots the run scene and verifies TileViews leave the ColorRect fallback (run the `.tscn`, not the script).

### `gpu_probe.gd` / `spike_trace.gd` — Diagnostics

`gpu_probe.gd` verifies `RenderingDevice` + compute dispatch on this machine. `spike_trace.gd` is the minimal end-to-end tracer kept as a readable reference.

## Simulation

### `board_validator.gd` — Board layout validator

Validates `BoardLayoutResource`: gravity cycles (ERROR), unreachable cells (WARNING), orphaned spawn entries (ERROR), contention zones (WARNING), portal targets (ERROR).

```gdscript
var validator := BoardValidator.new()
for issue in validator.validate(layout):
    print(issue)
```
