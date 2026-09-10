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

Renders single gems through the full kernel (inclusions, zoning, dispersion, birefringence, scatter field, print pass) and writes PNGs to `artifacts/`. First stop after touching `gem_pathtrace.glsl` or the stone compiler.

### `kernel_physics_check.gd` — Kernel physics

Energy, Fresnel, absorption and scatter-field-vs-stochastic-reference checks with tolerances. Must pass after any change to `gem_common.glsl`, `gem_pathtrace.glsl` or `gem_scatter_field.glsl`.

### `rig_ab_check.gd` — Lighting rig A/B

Renders a row of stones per `GemLightRig` (`--rigs=a.tres,b.tres`, `--stones=...`, `--spp`, `--res`), house-printed at exposure 1.0, stacked into `artifacts/lookdev/rig_ab/ab.png`, and prints contrast-discipline numbers per stone (mean / p10 / p90 luma, clipped %, dark %). Lighting changes are rig edits judged here — never exposure or print tweaks.

### `return_sweep.gd` — Face-up light-return function

Sweeps one 15° unit light over the angle from the viewing axis and prints the mean stone luminance per cut (clean stones, rest pose). Tells you where a rig must put light to reach the body — the starting point for any rig design.

### `grain_check.gd` — Print-space grain

Two-seed RMSE in print space for all 16 stones at a rung / resolution / spp (`--dump` writes amplified difference images). The noise number that matters for sprites; sub-LSB is the target for body grain.

### `turn_gifs.gd` + `turn_gifs_encode.py` — 360° turn GIFs

Renders a 60-frame turntable per stone at 512 px and encodes GIFs (Pillow) into `artifacts/lookdev/turn_gif/`.

### `ladder_check.gd` — 8-gem ladder strip

Renders the main merge ladder in tier order to one strip; the fastest whole-catalog eyeball.

### `board_grid_check.gd` — Batch timing

Times 1/16/64-gem batched dispatches per quality rung; prints ms/gem. The numbers behind the sprite-vs-live-3D decision.

### `forge_cold_start_check.gd` — GemForge cold start

Clears the cache, then measures time-to-first-idle and full-catalog generation through the launcher path.

### `silhouette_diagnose.gd` — Girdle outline kinks (headless OK)

Prints girdle support count, outline vertex count, max turning angle, and mid-edge sagitta per silhouette. Use after touching `silhouettes.gd`: polygon kinds must be exact k-gons at q=1.

### `noise_spp_check.gd` — SPP ladder + ruby ablation

Windowed. Writes `artifacts/lookdev/noise/` (spp ladder, ruby ablation, metrics.json). Use this after kernel scatter/fluorescence changes — not a denoiser check. The SPP list is explicit so rung policy does not confound the ladder.

Composes the montages in `artifacts/eval/`: contact sheet, grade sheet, lighting sheet, rung ladder, clip filmstrips, timing table.

### `package_clips.gd` — Clip packaging

Bakes authored clips (named animations, lighting-relative motion) through `GemForge` and packages them for the board consumer.

### `atelier_screenshot.gd` / `board_visual_check.tscn` — Visual smoke checks

Windowed screenshot harnesses: the first captures the Gem Atelier (progressive preview + clip scrub), the second boots the run scene and verifies TileViews leave the ColorRect fallback (run the `.tscn`, not the script).

### `gpu_probe.gd` — Diagnostics

`gpu_probe.gd` verifies `RenderingDevice` + compute dispatch on this machine.

## Simulation

### `board_validator.gd` — Board layout validator

Validates `BoardLayoutResource`: gravity cycles (ERROR), unreachable cells (WARNING), orphaned spawn entries (ERROR), contention zones (WARNING), portal targets (ERROR).

```gdscript
var validator := BoardValidator.new()
for issue in validator.validate(layout):
    print(issue)
```
