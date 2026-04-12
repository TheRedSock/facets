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
core/board/     Simulation: board, tiles, matching, effects, gravity, spawning
core/rules/     Simulation: RNG, event logging, event timeline
core/run/       Simulation: run lifecycle, turn pipeline
core/visuals/   Gem geometry: spec loading, topology, projection, mesh assembly, lighting
native/         C++ GDExtension: Embree ray tracer (GemTraceKernel)
native/src/     C++ source for native tracer
resources/      Resource class definitions (data schemas)
data/tiles/     Tile definition .tres files (8-gem merge ladder)
data/visuals/   GemVisualResource .tres + cut_specs/ for gem geometry
config/         Version-controlled config (bake profiles)
autoloads/      Singletons (config, replay, save, debug, tile registry, gem visuals)
scenes/menu/    Main menu
scenes/design/  Gem bake workbench (offline bake + preview)
scenes/run/     Run gameplay (wires simulation to rendering)
scenes/board/   Board rendering, animation, input
scenes/tile/    Tile visuals (texture cache + procedural fallback)
scenes/main/    Run entry point
scenes/debug/   Debug panel (F1)
tools/          Design-time utilities (board validator, bake CLI)
tests/          Headless tests
plans/          Design docs (reference only, not code)
```

### Deprecated

- `autoloads/perf_monitor.gd` — not autoloaded, unused
- `core/visuals/gem_material_sampler.gd` — used by procedural 2D renderer; native has C++ port
- No runtime loading screen in current flow

### Layer Boundaries

| Layer | May depend on | Must NOT depend on |
|---|---|---|
| `core/board/` | Other `core/`, `SeededRng` | Scenes, autoloads (exception: `EffectResolver` reads `TileRegistry` for merge chains) |
| `core/run/` | `core/board/`, `core/rules/`, `ReplayService` | Scenes |
| `core/visuals/` | `resources/visuals/` | Scenes, autoloads, `core/board/` |
| `native/` | godot-cpp, Embree, `resources/visuals/` | GDScript, scenes, autoloads |
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
- **Ladder:** Quartz(T1) → Amethyst(T2) → Peridot(T3) → Topaz(T4) → Sapphire(T5) → Emerald(T6) → Ruby(T7) → Diamond(T8)
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

### GemVisualRegistry

Loads `GemVisualResource` from `data/visuals/`, compiles/caches geometry on demand. Key API:

- `get_visual(tile_id)`, `get_cut(geometry_signature)`, `get_cut_model(geometry_signature)`
- `ensure_gameplay_texture_cache(draw_size)` / `get_gameplay_texture(...)`
- `get_gameplay_lighting_blend_set(...)` / `get_gameplay_rotation_blend_set(...)` → `{atlas, layer_index, weights}` for shader
- `load_run_gems(tile_ids)` / `unload_run_gameplay_textures()` — run-scoped memory
- `gameplay_texture_cache_rebuilt` signal

---

## Gem Visual Pipeline

Model-first: authored 3D geometry → offline-traced textures for gameplay, procedural 2D fallback when traced unavailable.

### Pipeline Stages

1. **GemCutSpecResource** (`data/visuals/cut_specs/`) — typed gem cut definition
2. **GemCutCompiler3D** → **GemCutModelResource** — compiled 3D facet model (topology → normalize → validate)
3. **GemCutProjector** → **GemProjectedCutResource** — 2D projection for procedural fallback
4. **GemMeshAssembler** → **GemMeshResource** — trace-ready mesh for offline ray tracer

All stages share `spec_id` / `geometry_signature` identifiers for cache coherence.

### GemVisualResource

`.tres` in `data/visuals/`, one per gem. References `cut_spec` + appearance config (color, specular, contrast, depth tint, dispersion, rim, translucency, extinction, etc.). See `resources/visuals/gem_visual_resource.gd` for full property list.

### GemRenderer

Pure `RefCounted`, no scene dependency. Computes flat-shaded per-facet colour via multi-pass lighting (diffuse half-lambert/lambert blend, Blinn-Phong specular, depth tint, gradient, translucency, rim, secondary specular, hue dispersion, sparkle, per-facet jitter, saturation boost, zone brilliance, transparency). Also `compute_pavilion_colors()` for extinction overlay.

### TileView Visual Priority

1. Offline-traced gameplay texture (when available)
2. Procedural `_draw()` (compiled geometry + GemRenderer)
3. Coloured rectangle (headless/debug fallback)

Gameplay textures use `sampler2DArray` blend shader (`gameplay_sprite_blend.gdshader`). Registry provides `{atlas, layer_index, weights}` blend dicts. When no pre-built atlas exists, ad-hoc 4-layer atlas is constructed to keep the shader path unified.

---

## Native Ray Tracer

C++ GDExtension (`native/`) using Embree for BVH traversal. The sole tracer implementation.

**API:** `trace_to_image(mesh_resource, visual, request) -> Image`, `get_last_trace_profile() -> Dictionary`.

**Required:** The native extension must be compiled. The GDScript tracer (`gem_optics_tracer.gd`) has been removed; the native kernel is the sole implementation.

**Build:** Requires MSVC 2022, Python 3.x, SCons.
```bash
cd native && python -m SCons platform=windows target=template_debug
```
Copy Embree DLLs once: `cp embree/bin/{embree4.dll,tbb12.dll} lib/win64/`

### Offline Bake

```bash
godot --headless --path . --script res://tools/run_offline_gem_bake.gd -- [OPTIONS]
```
See script source for full flag reference.

**Production bake** (profile-driven, spec at `config/bake_profiles/gameplay.json`):
```bash
godot --headless --path . --script res://tools/run_production_bake.gd -- --profile=res://config/bake_profiles/gameplay.json
godot --headless --path . --script res://tools/validate_production_bake.gd -- --profile=res://config/bake_profiles/gameplay.json
```

### Bake Contexts

| Context | Output | Manifest Priority |
|---------|--------|-------------------|
| Workbench / Dev CLI | `user://traced_bakes/` | 1st |
| Production | `res://generated/traced_bakes/` | 2nd (fallback) |

Runtime searches `user://` first, then `res://generated/`. To rebake: delete `user://traced_bakes/` manifest.

### Asset Optimization

- **GPU compression:** BC7/BPTC on load (constants in `GemTracedBakeContract`). ASTC on mobile, S3TC fallback. ~4x VRAM savings.
- **Texture2DArray atlases:** per-gem lighting + rotation atlases. Shader samples 4 layers for bilinear blend.
- **Run-scoped loading:** `load_run_gems(tile_ids)` / `unload_run_gameplay_textures()`. `GemAtlasCache` tracks scope + VRAM estimation.

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
godot --headless --script tests/test_smoke.gd                # Core smoke tests
godot --headless --script tests/test_gem_cuts.gd              # Cut regression
godot --headless --script tests/test_native_trace_kernel.gd   # Native tracer
godot --headless --script tests/test_rng_cross_platform.gd    # Cross-platform RNG
```

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
| New gem type | `.tres` in `data/tiles/` (auto-loaded) |
| Gem visual appearance | `.tres` in `data/visuals/` |
| New gem cut | `GemCutSpecResource` in `data/visuals/cut_specs/`, reference from `GemVisualResource` |
| Cut outline math | `core/visuals/gem_cut_primitives.gd` |
| Cut topology family | `core/visuals/gem_topology_builders_3d.gd` |
| Lighting model | `core/visuals/gem_renderer.gd` — `compute_facet_color()` |
| Visual modifier effect | `GemRenderer.compute_all_facet_colors()` modifiers dict |
| New visual property | `resources/visuals/gem_visual_resource.gd` + `GemRenderer` + workbench if tooling needed |
| Per-gem bake quality | `GemVisualResource.bake_quality_override` (-1.0 = auto) |
| Pavilion extinction geometry | `core/visuals/gem_cut_projector.gd` / `gem_topology_builders_3d.gd` |
| Pavilion extinction rendering | `core/visuals/gem_renderer.gd` — `compute_pavilion_colors()` |
| Workbench preview/rebake | `scenes/design/gem_bake_workbench.tscn` |
| Native trace logic | `native/src/gem_trace_kernel.cpp` (rebuild after) |
| Native material sampling | `native/src/gem_trace_material.cpp` (rebuild after) |
| Native Embree intersection | `native/src/gem_trace_scene.cpp` (rebuild after) |
| Rebuild native extension | `cd native && python -m SCons platform=windows target=template_debug` |
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
| VRAM compression | `core/visuals/gem_traced_bake_contract.gd` |
| Atlas/blend API | `autoloads/gem_visual_registry.gd` |
| Blend shader | `scenes/tile/gameplay_sprite_blend.gdshader` |
| Production bake config | `config/bake_profiles/gameplay.json` |
| Run production bake | `tools/run_production_bake.gd` |
| Validate production bake | `tools/validate_production_bake.gd` |
| Rebuild manifest | `tools/rebuild_traced_manifest_from_pngs.gd` |
| Run-scoped gem loading | `autoloads/gem_visual_registry.gd` — `load_run_gems()` |
