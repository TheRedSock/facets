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
core/delivery/        Runtime-only asset library, format and presentation mapping
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
scenes/tile/          Tile visuals (required delivered semantic clips)
scenes/main/          Run entry point
scenes/debug/         Debug panel (F1)
tools/                Design-time utilities (board validator, data generator, GPU checks, eval sheets)
tests/                Headless tests (simulation + lapidary CPU layers)
docs/                 Current index/plan/progress; superseded Markdown in ignored archive/
plans/                Design docs (reference only, not code)
artifacts/            Rendered evaluation output (sheets, lookdev) — not shipped
```

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

- `get_clip(tile_id, role)` — frame count, fps and loop metadata only.
- `get_frame(tile_id, role, index)` — trimmed AtlasTexture preserving the original canvas size.
- `await prepare_required(tile_ids, roles)` — validates bindings and retains the declared upcoming pages before presentation.
- `delivery_report()` — metadata time, page loads, cache ownership and live texture references outside the cache.
- `open_library(path, catalog)` / `library_changed` — explicit library replacement for viewers/tools.

Build with `tools/build_gem_assets.ps1`. Source jobs, resumable masters and delivery files stay ignored under `generated/`. Copy `generated/gem-assets.pck` beside an exported desktop executable. Project settings `lapidary/delivery/pack` and `lapidary/delivery/library` can select another pack/library. The PCK contains only the manifest's referenced pages; no optics, masters, checkpoints or stale pages. Required missing/corrupt assets fail loading explicitly. There is no production tier tint. `data/presentation/default.tres` maps logical tile IDs to asset IDs and semantic rest/upgrade roles independently of GemStone identity. TileView exposes restart, interruption, completion and return-to-rest through `play_role`; ignored rotation arguments and duplicate palettes are removed. Tests use explicit synthetic delivery fixtures.

`tools/build_game_package.ps1` stages runtime sources into a fresh project and
audits both PCKs before reporting package completion. Provision pinned templates
with `tools/fetch_export_templates.ps1`. Runtime cache and active-reference budgets,
external package probes and release UI acceptance are documented in
`core/delivery/CONTRACT.md`; package probes do not replace release-executable tests.

---

## Lapidary contracts and current work

The active readiness scope is `docs/lapidary-engine-readiness-plan-2026-09-13.md`;
phase acceptance is recorded in `docs/READINESS_PROGRESS.md`. P0–P5 are not complete
until their individual gates and final exported-game acceptance pass. Historical
audits/reports are in `docs/archive/`; never treat their old behavior as a current
requirement. Keep `docs/` current and archive superseded Markdown with verified
checksums. The archive and local documentation remain gitignored.

Authoritative detailed contracts:
- `core/lapidary/tracer/KERNEL_CONTRACT.md`: GPU packing, geometry, media,
  scalar/Mueller/uniaxial transport, diagnostics, numerical limits, print/AOVs.
- `core/lapidary/factory/CONTRACT.md`: authoring realization, immutable jobs,
  content identity, storage/checkpoints/claims/recovery, packaging and delivery.
- `tools/README.md` and `tools/engine_checks.json`: maintained commands and
  registered acceptance stages. `tools/check_engine.ps1 -List -Gpu` lists gates.

Current ownership:
- `GemSpecies` owns principal index curves, crystal-axis convention and hardness
  metadata. `GemMaterial` owns explicit nonnegative scattering and absorber
  mixtures with evidence. No species scattering inheritance, primitive inclusion
  vocabulary or inactive fluorescence knobs remain. Compiled absorption is
  401 samples at 1 nm over 380..780 nm; source grids may differ.
- `GemStone` owns material, shape/cut, condition, physical radius scale, seed and
  crystal frame. `GemGrade` is metadata and never changes transport. Conditions
  are explicit physical boundaries, finish, workmanship and spatial fields.
- `GemSpecimenRecipe`/`GemQualityPreset` realize detached specimens with bounded
  named variation channels. `GemMicrostructureRecipe` realizes physical regions
  with stable population IDs. Neither is a calibrated natural grading law.
- `GemAssetRequest`/`GemAssetBatch` define explicit delivery variants. Asset names
  are independent of physical stone identity. `GemClipSampler` is the shared clip
  math; deliverable rendering uses planner/worker jobs, with no second clip baker.
- `GemPresentation` independently owns orientation, rest framing and rotation
  pivot. Default pears point down; rest manufactured bounds are centered. Do not
  recenter each animation frame or alter crystal coordinates for presentation.
- `GemFrameWorker` owns optical work and reprinting; XYZ masters, prints and
  optional style have separate identities. `GemGeometryWorker` generates primary
  geometry companions. `GemPagePacker` packages only referenced display frames.
- GemForge is a read-only game service. No runtime optical baking. Delivery is
  currently lossless WebP by default; GPU compression requires per-frame gates.

Geometry fast paths and general BVH/analytic paths are complementary active
implementations. Convexity is an optimization, not a global invariant. Curved
round/oval cabochons and supported convex rounding use analytic intersections;
other procedural curves can remain tessellation-limited. See the kernel contract
for thin-feature precision and encoded-boundary admission limits.

Faceted cuts use one declarative `GemCutTemplate`/`GemFacetGroup` program with
independent index sets and explicit construction meets. See
`core/lapidary/cut/CONTRACT.md`. No table/culet is forced. Cut labels do not seed
manufacture; stable group/index IDs own its channels. The old crown-row grammar,
shape sector coupling and nominal cut condition-variation targets are removed.

Transport policies (`GemRung.TABLE`) own numerical work. Production uses repeated
volume scattering with optional residual reconstruction; reference disables
reconstruction. Increasing sample count does not add missing optical capabilities.
Isotropic Mueller and FP64 uniaxial transport are explicit opt-ins with admission
restrictions. Fluorescence, biaxial transport, directional silk and accepted healed
fracture morphology remain unsupported/outstanding. Do not revive abandoned
approximations or infer optical quality from a grade label.

GPU tools run windowed: RenderingDevice is unavailable under `--headless`. CPU
admission/planning, cached replay and packaging are headless-capable. Scene scripts
used by `--script` tools resolve autoloads by `/root/...`, not compile-time globals.
Use immutable detached resources across worker boundaries; never mutate loaded
shared resources to make an authoring preview.

## Validation and development

Authoring edits use `GemAuthoringDocument` and shared `GemAuthoringAdmission`.
See `core/lapidary/authoring/CONTRACT.md`. Catalog generation only emits candidates
and a diff under `generated/`; never regenerate over hand-authored source data.
Physical cache identity excludes labels/evidence; admission and appearance review
retain full provenance. Unsupported preview requests must clear stale images.

`tools/check_engine.ps1` runs the registered CPU gates; `-Gpu` adds GPU/factory
gates, `-CrystalPrecision` adds FP64 stress, and `-ReferencePython <python>` runs
independent Python comparisons. `-Only name1,name2` selects enabled gates. Stages
must emit their completion marker; an exit-zero exception or premature automatic
quit is a failure. Environmental errors are reported separately, not suppressed.
Logs and results are under ignored `artifacts/checks/`.

Core simulation: `godot --headless --script tests/test_smoke.gd` and
`tests/test_rng_cross_platform.gd`. Preserve seeded integer RNG, authoritative
event timelines, input ownership, topology and gravity invariants when changing
the delivery/game boundary. `BoardValidator` validates layouts, including cycles,
reachability, portal targets and contention.

`SpawnTableResource.weights` is `Array[int]`; default tiers [1,2,3,4] have weights
[4,3,2,1]. New tile/cell fields require duplication, serialization and hash updates.
Do not change game mechanics as a side effect of asset-authoring work.

Deferred game systems (modifiers, floors, boons, hazards and T9) are reference
designs in `plans/deferred-systems-reference.md`, not implemented behavior.
