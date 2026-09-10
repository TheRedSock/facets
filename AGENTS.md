# Facets — Agent Context

Gemstone match-3 merge roguelike. Godot 4.6, GDScript. Desktop 1920x1080 (mobile pivot planned).

**Godot executable:** `C:/Godot/Godot_v4.6.1-stable_win64_console.exe` (shorthand `godot` in examples below).

---

## Agent Behavior

- **Do not be sycophantic.** No praise, affirmation, or filler. Respond with direct technical content only.
- **Do not assume the developer's question reflects their true intent.** Ask clarifying questions when the request is ambiguous or underspecified. A question about X may actually require a solution involving Y.
- **Do not assume the developer's suggestion is correct.** Evaluate proposals against this file's invariants, the codebase's existing patterns, and the project's goals. Push back explicitly when a suggestion conflicts with or contradicts established architecture, conventions, or design direction.
- **Verify, don't assume.** This applies at every level. For project-specific facts (behavior, rules, conventions), verify in the relevant source files before asserting. For domain knowledge (mathematical formulas, algorithms, gemological properties of real minerals, optical physics, cut geometry conventions, etc.), do not trust training data as a substitute for verification — look it up via web search when the claim is objectively verifiable. State uncertainty when verification is not possible.
- **Prefer interaction over assumption.** When context is incomplete or multiple valid interpretations exist, ask rather than guess. A wrong assumption costs more than a clarifying question.
- **Treat this file as the architectural source of truth.** If a request would violate a documented invariant, flag the conflict before proceeding.

---

## Invariants

### 1. Simulation/Rendering Separation

`core/` is pure data (`RefCounted`, zero scene tree dependency, runs headlessly). `scenes/` consumes simulation output, never feeds back.

- Simulation runs a complete turn instantly, producing an `EventTimeline`.
- Renderer plays back the timeline via Tweens. Simulation does NOT wait for animations.
- `board_changed` signal = full visual rebuild. Only fires from `start_new_run()` / `reroll_board()`. Must NOT fire after a swap begins.

### 2. All Simulation Randomness via SeededRng

Every random value in simulation MUST use the `SeededRng` instance passed as parameter. Never `randi()`, `randf()`, `Array.shuffle()`, or standalone `RandomNumberGenerator`. Deterministic replay depends on this.

No floating point in simulation paths. Spawn weights use `randi_range()` with integer weights for cross-platform determinism.

### 3. Adjacency via get_neighbor()

All adjacency: `BoardState.get_neighbor(cell, direction)`, never `cell + direction`. Checks portal overrides before grid arithmetic. Direct coordinate math bypasses portals.

### 4. Gravity via get_effective_gravity()

`BoardState.get_effective_gravity(cell)` priority order:
1. Tile's `gravity_override` (if non-zero)
2. Cell's `gravity_direction`
3. Default: `Vector2i.DOWN`

Never hardcode gravity direction.

### 5. TileView Mouse Filter

`TileView` and all children: `mouse_filter = MOUSE_FILTER_IGNORE`. Input handled by `BoardScene._gui_input()`. Any new TileView child MUST set this or input silently breaks.

---

## Project Structure

```
core/board/           Simulation: board, tiles, matching, effects, gravity, spawning
core/rules/           Simulation: RNG, event logging, event timeline
core/run/             Simulation: run lifecycle, turn pipeline
core/lapidary/        GPU gem pipeline (CPU side): stone compiler, cut language, lighting, clips, eval
core/lapidary/tracer/ GPU tracer host + GLSL compute shaders (path trace, print pass)
resources/            Resource class definitions (data schemas)
resources/lapidary/   Species, chromophore, grade, stone, cut, clip, rig, print schemas
data/tiles/           Tile definition .tres files (merge ladders)
data/lapidary/        Authored gem data: species/chromophores/grades/stones/cuts/clips/rigs
autoloads/            Singletons (config, replay, save, debug, tile registry, GemForge)
scenes/menu/          Main menu
scenes/design/        Gem Atelier (progressive preview + clip scrub)
scenes/run/           Run gameplay (wires simulation to rendering)
scenes/board/         Board rendering, animation, input
scenes/tile/          Tile visuals (GemForge clips + placeholder fallback)
scenes/main/          Run entry point
scenes/debug/         Debug panel (F1)
tools/                Design-time utilities (board validator, data generator, GPU checks, eval sheets)
tests/                Headless tests (simulation + lapidary CPU layers)
docs/                 Architecture docs (lapidary-architecture.md is the pipeline authority)
plans/                Design docs (reference only, not code)
artifacts/            Rendered evaluation output (sheets, lookdev) — not shipped
```

### Deprecated

- `autoloads/perf_monitor.gd` — not autoloaded, unused
- No runtime loading screen in current flow

### Layer Boundaries

| Layer | May depend on | Must NOT depend on |
|---|---|---|
| `core/board/` | Other `core/`, `SeededRng` | Scenes, autoloads (exception: `EffectResolver` reads `TileRegistry` for merge chains) |
| `core/run/` | `core/board/`, `core/rules/`, `ReplayService` | Scenes |
| `core/lapidary/` | `resources/lapidary/`, `RenderingDevice` | Scenes, autoloads, `core/board/` |
| `scenes/` | `core/` (read-only), autoloads | Must not mutate board state |
| `autoloads/` | `core/`, `resources/` | Scenes |
| `resources/` | Nothing | Everything |

---

## Turn Pipeline

Exact sequence on player swap:

```
RunScene._on_swap_requested(cell_a, cell_b)
  → input lock
  → RunController.begin_swap(cell_a, cell_b)
      1. board.swap_cells(a, b)
      2. match_detector.find_matches(board) — if empty, revert, return false
      3. ReplayService.record_action("swap", ...)
      4. TurnController.prepare_turn(board, rng, spawn_table, event_log, [a, b])
  → await BoardScene.animate_swap(cell_a, cell_b)
  → await process_frame
  → RunController.resolve_remaining_cascades()
      5. TurnController.step_cascade() loop (max 50):
           a. MatchDetector.find_matches(board)
           b. MatchClassifier.classify(matches) — base/4/5+/L-T
           c. EffectPlanner.build_base_plan(classified, swap_cells)
              swap_cells only on first cascade (survivor prefers swapped cell)
           d. ConflictResolver.resolve(plan, board)
           e. EffectResolver.apply(board, plan, log)
           UPGRADE CHAIN LOOP (max 20):
             e2. find_matches — check if upgrade formed new match
             e3. If empty, break
             e4. Classify → plan → resolve → apply (before gravity)
           f. BoardPhysics.resolve_gravity(board)
           g. SpawnResolver.refill_spawn_entries(...)
           h. Collect cascade step into EventTimeline
         UNTIL no matches
  → await BoardScene.play_authoritative_async_timeline(timeline)
      6. Move cost: base_match(3)=-1, match_4=free, match_5+/L-T=+1
      7. ReplayService.record_checkpoint(final_hash)
      8. Emit run_state_changed
  → unlock input
```

- Timeline is fully resolved before cascade playback begins
- `begin_swap`/`resolve_remaining_cascades` do NOT emit `board_changed`
- `board_changed` only from `start_new_run()`/`reroll_board()`
- Input locked for entire swap+cascade duration

---

## Merge Mechanic

3+ tiles of same `match_group`: N-1 removed, 1 survivor upgraded.

- **Survivor (first cascade):** prefers swap destination, then origin cell
- **Survivor (later cascades):** last cell in match array (bottom-right bias)
- Merge chain: `tile.merge_target_id` → `TileRegistry` lookup → new tile_id/tier/match_group/family_tags
- **Main ladder:** Quartz(T1) → Amethyst(T2) → Peridot(T3) → Topaz(T4) → Sapphire(T5) → Emerald(T6) → Ruby(T7) → Diamond(T8)
- **Alternate ladder:** Fluorite(T1) → Smoky Quartz(T2) → Tourmaline(T3) → Rhodolite(T4) → Aquamarine(T5) → Alexandrite(T6) → Painite(T7) → Blue Garnet(T8)
- T8 matches: pure removal. `EffectPlanner.MAX_STANDARD_TIER = 8`
- Debug tiles (no merge_target_id): fallback `tier += 1`

---

## Gravity

`BoardPhysics.resolve_gravity()` — iterative settling, NOT column compaction:

1. Each round: process cells bottom-to-top, right-to-left. Each tile moves one cell in its effective gravity direction.
2. Diagonal fill pass: cells with `fill_sources` pull from diagonal neighbors.
3. Repeat until stable or `MAX_SETTLE_ROUNDS` (256).
4. Movements recorded in `last_move_events` for EventTimeline.

Processing order determines priority for competing tiles. Bottom-to-top right-to-left gives downward gravity natural priority.

---

## Board Topology

`BoardState` is the topology authority:

- **Grid:** flat `CellState` array, indexed `cell.y * size.x + cell.x`
- **Portals:** `_portals` dict (`"x,y,dx,dy"` → `Vector2i`). Override `get_neighbor()` for gravity only (not matching).
- **Layouts:** `BoardLayoutResource` defines shape, per-cell gravity, spawn entries, fill sources, portals. Applied via `board.apply_layout(layout)`.
- **Spawn entries:** `is_spawn_entry = true` cells receive new tiles. Fallback: fill all empties.

### CellState

| Property | Type | Default | Purpose |
|---|---|---|---|
| `tile` | `TileState` | `null` | Tile in this cell |
| `blocked` | `bool` | `false` | Hole/wall |
| `gravity_direction` | `Vector2i` | `DOWN` | Tile fall direction |
| `is_spawn_entry` | `bool` | `false` | New tiles enter here |
| `fill_sources` | `Array[Vector2i]` | `[]` | Diagonal fill directions |
| `tags` | `Dictionary` | `{}` | Extensible metadata |

### TileState

| Property | Type | Default | Purpose |
|---|---|---|---|
| `tile_id` | `StringName` | `&"debug_tile"` | Gem identifier |
| `match_group` | `StringName` | `&""` | Match grouping (falls back to tile_id) |
| `tier` | `int` | `1` | Tier (1-8 standard, 0 hazards, 9 transcendents) |
| `merge_target_id` | `StringName` | `&""` | Next in merge chain (empty = top tier) |
| `family_tags` | `Array[StringName]` | `[]` | Synergy grouping |
| `status_flags` | `Dictionary` | `{}` | On-board effects |
| `protected` | `bool` | `false` | Immune to destruction |
| `gravity_override` | `Vector2i` | `ZERO` | Per-tile gravity (ZERO = use cell) |
| `immovable` | `bool` | `false` | Cannot move |
| `unmatchable` | `bool` | `false` | Excluded from matching |

---

## Match Detection

`MatchDetector.find_matches()` scans along `match_axes` (default: `[RIGHT, DOWN]`):

- Uses `board.get_neighbor()` (topology-aware)
- Groups consecutive same-`match_group` tiles into runs of 3+
- Skips `unmatchable` tiles
- Portals do NOT create match adjacency

`MatchClassifier`: `base_match`(3), `match_4`(4), `match_5_plus`(5+), `match_lt`(L/T intersection).

---

## Rendering

`BoardScene` maintains persistent `Dictionary[Vector2i, TileView]`. Views persist and animate in place.

Cascade animation order:
1. Match highlight (flash `modulate = 1.5`)
2. Remove + Upgrade (converge/fade removed; survivor visual swap + scale pulse)
3. Gravity (tweened falls with column stagger)
4. Spawn (pre-created above board, join fall wave)

Upgrade chains play sequentially before gravity/spawn. Independent cell regions can animate in parallel.

Swap animation (0.15s slide) plays BEFORE cascade. Invalid swaps bounce back.

---

## Key Autoloads

### TileRegistry

Loads `.tres` from `data/tiles/`. Key API: `get_definition(tile_id)`, `create_tile(tile_id)`, `create_tile_for_tier(tier, rng)`, `get_ids_for_tier(tier)`, `has_definitions()`.

Used by `SpawnResolver` (tile creation) and `EffectResolver` (merge chains). Both fall back gracefully when unavailable.

### GemForge

Read-only game delivery service (`autoloads/gem_forge.gd`). It mounts the generated `gem-assets.pck`, reads library metadata, and uploads bounded texture pages on demand. No runtime optical baking.

- `get_clip(tile_id, clip_id)` — frame count, fps and loop metadata only.
- `get_frame(tile_id, clip_id, index)` — trimmed AtlasTexture preserving the original canvas size.
- `ensure_required(tile_ids)` — warms the actual run's idle pages; animation pages remain lazy.
- `delivery_report()` — metadata time, page loads and cache ownership bytes.
- `open_library(path)` / `library_changed` — explicit library replacement for viewers/tools.

Build with `tools/build_gem_assets.ps1`. Source jobs, resumable masters and delivery files stay ignored under `generated/`. Copy `generated/gem-assets.pck` beside an exported desktop executable. Project settings `lapidary/delivery/pack` and `lapidary/delivery/library` can select another pack/library. The PCK contains only the manifest's referenced pages; no optics, masters, checkpoints or stale pages. Missing assets use the debug tier tint.

---

## Lapidary — GPU Gem Pipeline

The engine is being rebuilt under explicit user authorization (2026-09-10); earlier no-mesh/no-denoiser/clip-only restrictions are superseded. Local audit and working journal are ignored in `docs/` and `artifacts/`; search them with `rg --no-ignore`. Source and buffer contracts are authoritative. Buffer formats: `core/lapidary/tracer/KERNEL_CONTRACT.md`. Summary:

- **Tracer** — GPU spectral path transport on a local `RenderingDevice`. Repeated volume scattering, deterministic dielectric exit splitting, and full per-wavelength geometry at PREVIEW and above. The rejected SH prepass has been removed after error/cost comparisons. Optional variance-guided reconstruction filters the volume residual; zero-scatter transmission/reflection and the original XYZ master remain intact. `REFERENCE` disables reconstruction. Birefringence remains an approximation pending redesign. Fluorescence is disabled until excitation and emitted transport exist. Physics gate: `tools/foundation_gpu_check.gd`; measured reconstruction: `tools/reconstruction_check.gd`.
- **Cut design** — Explicit template angles/proportions are independent of material and grade. `GemCondition.workmanship` supplies angular and millimeter manufacturing tolerances. `tools/optimize_cut.gd` explores candidate recipes under illumination/view ensembles with held-out evaluation; it never edits the catalog or claims a certified grade.
- **Geometry** — convex planes for faceted fast paths, or closed procedural surfaces with a shared BVH for concave lofts, cabochons and nested material boundaries. Convexity is an optimization, not an invariant.
- **Grading** — labels never alter optics. Explicit cut templates, workmanship, material coefficients and conditions own realized properties. The nonphysical primitive backend is removed. Explicit boundary finishes support light polish; strong frosting and automatic clarity/surface recipes remain unaccepted.
- **Authoring layers** — `GemSpecies` (principal index curves, hardness, inclusion vocabulary) + `GemChromophore` (sampled absorption curves (catalog 5 nm, compiled 1 nm)) + `GemCutTemplate` + `GemGrade` (cut/clarity/surface/crystal axes) + `GemStone` (the instance a tile references; `stone_id == tile_id`). All `.tres` under `data/lapidary/`, regenerated by `tools/generate_lapidary_data.gd` from published constants.
- **Compilation** — `LapidaryStoneCompiler.compile(stone) -> Dictionary` (geometry, materials, boundary finishes, fingerprint). One compiled instance feeds both clip baking and live 3D draws; the board consumer is a packaging switch, decided by measured numbers.
- **Lighting language** — `GemLightRig` resources (`data/lapidary/rigs/`), packed by `core/lapidary/lighting/rig_compiler.gd` (`compile()` returns atomic `GemLighting`: lights, deduplicated 1 nm SPDs, background and integrated neutral XYZ). Grade is never faked with lighting; lighting changes are rig edits, A/B'd with `tools/rig_ab_check.gd`, designed from the measured face-up return function (`tools/return_sweep.gd`). Exposure is the house print's only; tools and bakes pass 1.0.
- **House print** — mastering pass (`gem_print.glsl` + `GemPrint` resource): spectral → XYZ (tabulated CIE 1931 2° CMFs) → as-shot white balance (Bradford, rig neutral spectrum → D65; `core/lapidary/lighting/colorimetry.gd`) → linear sRGB → hue-preserving tonescale / chroma governor → sRGB8, straight alpha. Applied identically to clips and live draws; versioned.
- **Quality rungs** — `GemRung.TABLE`: `INTERACT`, `PREVIEW`, `BOARD_LIVE`, `CLIP_BAKE`, `HERO`, `REFERENCE`. Policy objects (spp, bounces, dispersion, volume mode, batch size, rad clamp) — never hand-tune trace params per call site.
- **Clips** — authored, named animations (`GemClip` in `data/lapidary/clips/`: idle, turn, flash) with lighting-relative motion, baked by the same kernel at `CLIP_BAKE`. No rotation/lighting lattice harvesting.

### TileView Visual Priority

1. Generated delivery clip (idle still; "turn" oneshot on upgrade), loaded by page.
2. Coloured rectangle via `TileRegistry.get_tier_color` when the requested asset is absent.

### GPU/Headless Constraint

`RenderingDevice` does not exist under `--headless` (verified). GPU tools run windowed: `godot --path . --script res://tools/<tool>.gd`. Pure-CPU stages (cut compiler, data layer, stone compiler) stay headless-testable. Autoload identifiers are not compile-time-resolvable in `--script` mode — scene scripts resolve them via `get_node_or_null("/root/GemForge")` at runtime.

---

## SpawnTableResource

```
allowed_tiers: Array[int] = [1, 2, 3, 4]
weights: Array[int] = [4, 3, 2, 1]     # INTEGER only
```

---

## State Hashing & Replay

- `BoardState.compute_hash()` — deterministic hash of complete board state
- `ReplayService` records seed + actions + hash checkpoints. Verifier replays and compares.

---

## Testing

```bash
godot --headless --script tests/test_smoke.gd                       # Core simulation smoke
godot --headless --script tests/test_rng_cross_platform.gd          # Cross-platform RNG
godot --headless --script tests/lapidary/test_cut_compiler.gd       # Cut language -> hulls (30 cuts)
godot --headless --script tests/lapidary/test_species_data.gd       # Species/chromophore/grade/stone data
godot --headless --script tests/lapidary/test_pleochroism.gd        # Optic axis + GIA dichroism mix (CPU)
godot --headless --script tests/lapidary/test_clips.gd              # Animation sampling + service contract
godot --headless --script tests/lapidary/test_board_consumer.gd     # TileView/GemForge contract
```

GPU rendering checks are windowed tools, not headless tests: `tools/foundation_gpu_check.gd`, `tools/grain_check.gd` (print-space two-seed RMSE, all stones), `tools/noise_spp_check.gd`, `tools/rig_ab_check.gd`, `tools/return_sweep.gd`, `tools/ladder_check.gd`, `tools/board_grid_check.gd`, `tools/eval_sheets.gd`, `tools/turn_gifs.gd`, `tools/board_visual_check.tscn`.

---

## Board Validation

`BoardValidator` (`tools/`) validates `BoardLayoutResource`: cycle detection, reachability, portal targets, contention zones. Errors = will break engine.

---

## Common Pitfalls

| Pitfall | Correct Approach |
|---|---|
| `randf()`/`randi()` in simulation | `SeededRng` parameter (Invariant #2) |
| `cell + direction` for adjacency | `board.get_neighbor()` (Invariant #3) |
| `board_changed` after swap | Only from `start_new_run`/`reroll_board` (Invariant #1) |
| TileView child without `MOUSE_FILTER_IGNORE` | Always set it (Invariant #5) |
| Hardcoded gravity `DOWN` | `board.get_effective_gravity()` (Invariant #4) |
| `Array[float]` spawn weights | `Array[int]` only |
| Game logic reading frame timing | Simulation is instant, never time-dependent |
| Dictionary iteration in simulation | Use arrays for ordered data |

---

## Deferred Systems (Not Implemented)

Designed but excluded from current scaffold. See `plans/deferred-systems-reference.md`.

- Modifier Pipeline, Floor Progression, Boon System, Hazard System (T0 tiles — polygon silhouettes: pentagon, hexagon, heptagon)
- Extended Effects (DOWNGRADE, CONVERT, SPAWN, MOVE, PROTECT, AWARD_MOVE, APPLY_STATUS)
- Protection Mechanics, Cell Tags, T9 Transcendent Gems (special silhouettes: heart, star, shield, etc.)

---

## File Quick Reference

| Task | File(s) |
|---|---|
| New gem type | `.tres` in `data/tiles/` (auto-loaded) + `GemStone` in `data/lapidary/stones/` (`stone_id == tile_id`) |
| Gem appearance (colour) | `GemChromophore` in `data/lapidary/chromophores/` (81-sample absorption) |
| Mineral physics | `GemSpecies` in `data/lapidary/species/` (Sellmeier, birefringence, inclusions) |
| Quality per tier | `GemGrade` in `data/lapidary/grades/` (labels only; explicit materials, banding, cut templates, workmanship, conditions and finishes own realized properties) |
| New gem cut | `GemCutTemplate` in `data/lapidary/cuts/` + `core/lapidary/cut/cut_compiler.gd` |
| Regenerate data layer | `tools/generate_lapidary_data.gd` (headless) |
| Trace/shading logic | `core/lapidary/tracer/shaders/gem_pathtrace.glsl` (+ `gem_common.glsl`) + `gem_tracer.gd` host |
| Mastering / print | `core/lapidary/tracer/shaders/gem_print.glsl` + `GemPrint` resource; white balance in `core/lapidary/lighting/colorimetry.gd` |
| GPU buffer formats | `core/lapidary/tracer/KERNEL_CONTRACT.md` (update when packing changes) |
| Stone -> kernel packing | `core/lapidary/stone_compiler.gd` |
| Quality rung policy | `core/lapidary/tracer/rung.gd` — `GemRung.TABLE` |
| Lighting rigs | `data/lapidary/rigs/*.tres` + `core/lapidary/lighting/rig_compiler.gd`; judge with `tools/rig_ab_check.gd`, design from `tools/return_sweep.gd` |
| Named clip animations | `GemClip` in `data/lapidary/clips/` + `core/lapidary/clips/clip_baker.gd` |
| Asset build / delivery | `core/lapidary/factory/`, `tools/build_gem_assets.ps1`, `autoloads/gem_forge.gd` |
| Atelier preview/scrub | `scenes/design/gem_atelier.tscn` |
| Evaluation sheets | `tools/eval_sheets.gd` -> `artifacts/eval/` |
| Merge behavior (4/5-match) | `core/board/effect_planner.gd` — `_plan_match_4()`, `_plan_match_5_plus()` |
| New effect type | `EffectPlanner` const + `EffectResolver.apply()` |
| Gravity behavior | `core/board/board_physics.gd` |
| Spawn distribution | `SpawnTableResource` weights |
| New tile property | `TileState` + `duplicate_tile()` + `to_dict()` + `BoardState.compute_hash()` |
| New cell property | `CellState` + `to_dict()` + `BoardLayoutResource` if per-level |
| Board layout | `BoardLayoutResource` + `board.apply_layout()` |
| New effect animation | `BoardScene._play_cascade_step()` |
| Animation timing | `scenes/board/animation_sequencer.gd` |
| Input handling | `BoardScene._gui_input()` (board), `RunScene` (game-level) |
| New autoload | `autoloads/` + register in `project.godot` `[autoload]` |
| Board validation | `tools/board_validator.gd` |

### Geometry implementation update
`GemShape` is the procedural outline/profile recipe on `GemStone`. Faceted cuts may use convex planes; `GemShapeCompiler` also builds closed indexed surfaces from cuts, cabochons and concave lofts. `GemBvh` and `gem_mesh.glsl` provide general dielectric transport with external re-entry. Triangle normals are currently geometric, so curved highlight quality is tessellation-limited. `tests/lapidary/test_geometry.gd` and `tools/foundation_gpu_check.gd` are the current geometry/transport gates.

### Material and condition implementation update
`GemStone.material` is a reusable `GemMaterial` (species/chromophore/scatter/provenance). `GemStone.condition` holds explicit `GemDefect` boundaries in millimeters. `GemBoundarySet` supports host-clipped priority media, overlapping cavities and fillings. Automatic fracture grading remains disabled after visual checks showed noise and lens-like morphology. `tools/check_engine.ps1 -Gpu` runs the current gates and treats GDScript exceptions as failures even if Godot returns exit0. Generated logs are ignored under artifacts/checks.

### Analytic curved host update
Round/oval cabochons now use `GemQuadric`/analytic GLSL intersections, including hybrid mesh cavities in the same host. This removes curved highlight tessellation for those profiles. Camera origins derive from geometry bounds. Other curved outlines remain tessellation-limited.

### Asset factory and delivery
`GemFramePlan` expands named animations into explicit poses and light samples; optical masters deduplicate independently of exposure, print and delivery resolution. `GemJobBundle` creates a minimal standalone GPU worker project/ZIP with exact binary resource inputs. `GemFrameWorker` resumes raw estimator checkpoints and reprints compressed associated-XYZ masters. Master-grouped shard jobs can run on separate workers; GPU environment and Godot version are recorded, not assumed portable to headless Vulkan.

`GemPagePacker` trims and pixel-deduplicates frames, preserves canvas offsets, pads boundaries and packs bounded specimen pages. Lossless WebP is the default. BC7/ASTC are explicit platform profiles with per-frame black/white-composited RGB and alpha error gates; the loader rejects unsupported formats. A low error over empty atlas space is insufficient. `GemAssetLibrary` validates all references/dimensions/checksums, loads pages selectively, and bounds LRU ownership (active view references can exceed that cache budget). `tools/library_gpu_check.gd` tests compression, PCK roundtrip, selective loading and actual TileView playback.

`GemStoreMaintenance` pins the requested manifests and keeps optional optical masters within a byte budget. Cooperative activity guards exclude collection during render/publish/pack operations. The local build runs collection after packing; `-CacheBudgetMiB` controls retention and `-SkipCollection` skips it. Standalone `tools/maintain_gem_store.gd` defaults to dry-run. Interrupted-process tokens require confirming that worker has stopped before removal. See `core/lapidary/factory/CONTRACT.md` for storage, concurrency and delivery formats.

### Spectroscopy inputs
`GemOpticalEvidence` separately identifies refraction, absorption and scattering evidence. The catalog's absorption is authored; four refraction models use published coefficients and others are fitted/assumed. `tools/import_absorption.gd` imports unit-declared spectroscopy, retains raw SHA256/interpretation, and requires interface/scattering correction for transmission data. Source absorption grids must cover 380..780 nm; compiled absorption is 401 samples at1nm on both o/e axes. No implicit material extrapolation. GPU contract v18 describes the layout, including exact int32 facet IDs and optional primary geometry companions.

### Surface finish update
`GemCondition.finish` and each `GemDefect.finish` hold independent `GemSurface` resources (GGX slope widths, polish direction and explicit `multiple_scattering`). Binding14 is aligned with the region table. Single scattering is appropriate for light polish and loses energy at high roughness. The optional height-correlated Smith walk includes inter-microfacet reflection/refraction, composes scalar/Mueller weights, and forces independent wavelength paths. Binding19 records64-bit walk/event counts plus errors; invalid or capped walks block factory publication. Kernel contract v18 and checkpoint v2 describe the new layout. Scalar/polarized furnaces pass through roughness1/index2.4; independent slope-CDF reference tests cover angular distributions and hemispherical reciprocity. Uniform frosting has not been calibrated to real specimens or wear history, so automatic surface grading stays disabled. Optional reconstruction filters the full rough signal; raw references remain available. Run `microsurface_gpu_check.gd`, `check_microsurface_reference.py`, `surface_check.gd` and `microsurface_lookdev.gd` for this model.

Spatial material variation: `GemCondition.volume_fields` adds smooth physical concentration/scattering fields (`GemVolumeField`), with exact polynomial chord integration and inverse optical-depth sampling. No automatic clarity recipe uses them yet. Validate with `test_volume_fields.gd`, `volume_gpu_check.gd`, and pose/noise comparisons in `volume_lookdev.gd`.

Optional policy `polarization=true` provides persistent Mueller/Stokes transport for isotropic real refraction, including axial weak-loss absorption, with full per-wavelength geometry and explicit HG depolarization. Dichroism requires a physical axis and peak imaginary/real index ratio <=0.001, including spatial concentration bounds. Default policies remain scalar; birefringent refraction remains unsupported in this variant. `polarization_gpu_check.gd` and optional Mitsuba comparisons validate interface/absorption chains independently. Run `tools/check_engine.ps1 -Gpu -ReferencePython <isolated-python>` after transport changes when that environment is available. The explicit `crystal_transport=true` policy integrates uniaxial Maxwell modes with coherent coincident packets, Poynting rays and FP64 intersections. It requires shaderFloat64 and admits only smooth, non-scattering, weak-loss media. Default rendering remains unchanged; float32 near-critical tests fail. Invalid interface diagnostics prevent factory publication, while bounce-limit truncations are recorded. Run `crystal_transport_check.gd` for slabs, shapes, nested media, resume equivalence and isotropic Mueller comparisons. This backend is currently expensive; biaxial media, rough boundaries and anisotropic scattering remain unsupported.


### Explicit volume authoring
`GemMaterial` owns homogeneous scattering; `GemCondition.banding` stores an authored sinusoidal concentration field with period in millimeters, specimen-space axis, contrast, phase and evidence. Species no longer supplies hidden zoning. `GemGrade` never changes transport. Catalog volume values are explicit authored look-development values, not measurements or a physical grading law. Atelier exposes scatter/mm, HG g, band period and contrast, and deep-copies all resources before editing. `GemFractureProfile` supports variable opening/contact geometry; automatic fracture grading remains disabled after visual evaluation.

### Geometry companions and portable jobs
`build_gem_assets.ps1 -GeometryCoverage 4` optionally schedules primary geometry companions. `GemGeometryPlan` separates geometry identity from optics/lighting/print; `GemGeometryWorker` generates no optical samples and caches GAO1 records. Manifests link each display to its companion, pin requested geometry during collection, and support farm transfer. `--outputs=geometry` selects only these jobs. They stay out of shipping texture pages and describe primary boundaries, not refracted inclusion visibility. Rebuild only stopped bundle directories; marked generated bundles prune obsolete sources and hash-named jobs so removed shaders cannot contaminate standalone engine identity.


Principal refraction is authored with `GemIndexCurve` resources on
`GemSpecies.ordinary` and `.extraordinary` (null = isotropic). Float64 source
coefficients/evidence survive binary farm jobs; the GPU Stone is 160B with both
principal Sellmeier curves. Quartz/corundum o/e use cited published dispersion;
other anisotropic catalog axes remain explicit constant-offset approximations.
The scalar renderer still uses approximate o/e transport and skips weak
anisotropy; do not mistake improved inputs for validated full anisotropic optics.
Run `test_principal_indices.gd` and `principal_indices_gpu_check.gd` with the suite.

Result identity uses `GemRenderIdentity.pipeline_digest()` by scalar, polarized,
crystal, print or geometry pass; `worker_digest()` retains full renderer provenance.
Bundle source checks remain exact. Master/display/geometry records declare their
own pipeline engine; farm transfer accepts compatible pipelines across worker
revisions without rewriting producer metadata. Unknown files in inventoried roots
are conservative shared dependencies. Verify changes with
`test_render_dependencies.gd` and `pipeline_cache_check.gd`; rebuild old manifests
that lack per-result pipeline declarations.

Spatial finish: `GemSurface.fields` contains ordered `GemFinishField` regions in physical millimeters. Binding20 holds80B records; binding14 uses its spare components for field offset/count. Local GGX shape matrices interpolate without changing geometry or painting color. Narrow anisotropic lobes retain precision through positive determinant terms. A rough field enables boundary transport even when the base finish is smooth; crystal admission rejects potentially rough fields. Geometry companion keys exclude these optical properties. The finish-field CPU, GPU matrix/reference, renderer and lookdev tools validate this path. Fields and facet-anchored examples are authored condition descriptions, not a polishing-rate law or automatic grading recipe.

### Mesh admission
`GemMesh.validate()` checks per-region edge closure, vertex fans, BVH triangle contacts and alternating shell orientation by containment depth. Exact predicate fallbacks operate on the encoded float32 coordinates; separate priority-region crossings remain legal, coincident triangle patches do not. Disconnected fracture pockets and inward cavity shells are supported. A bounded content cache avoids repeating admission across animation jobs and invalidates on buffer changes. `GemJobValidator` checks combined mesh regions before GPU work; `GemTracer.configure_stones` has a release-safe rejection path. `test_mesh_admission.gd`, `check_mesh_predicates.py` and `mesh_admission_benchmark.gd` cover correctness and cost. This does not certify analytic-host coincidence or minimum optically resolvable feature size.

### Cleavage condition and crystal frame
`GemCondition.cleavage` optionally references `GemCleavageRecipe`; `data/lapidary/conditions/diamond_cleavage.tres` is an opt-in cubic {111} example. One seeded plane separation removes a physical cap and exposes a boundary with independent finish. `GemStone.crystal_to_stone` rotates both declared cleavage normals and the species base optic axis; a nonzero object-space optic-axis override is explicit. Host cap-volume reports exclude existing defects and label tessellated estimates for analytic hosts. No impact, toughness or grading law is inferred; automatic grading remains off. `test_cleavage.gd`, `cleavage_gpu_check.gd` and `cleavage_lookdev.gd` cover the implementation. Convex hosts with one cleavage and no other enabled defects append a retained half-space with independent per-plane finish/semantic slot; mesh/analytic/combined conditions use the general region backend. `cleavage_backend_check.gd` compares both paths and `convex_surface_check.gd` checks mixed-batch packing and rough-face energy.
