# Facets — Agent Context Reference

Gemstone-themed match-3 merge roguelike built in Godot 4.6 (GDScript). Landscape desktop layout (1920x1080), with future portrait mobile pivot planned. The player swaps tiles to form matches of 3+; matched tiles merge into higher-tier gems (3 Quartz → 1 Amethyst). The goal is to forge high-tier gems within a limited number of moves across roguelike floor progression.

---

## Critical Architectural Rules

These rules are non-negotiable. Violating them will cause subtle, hard-to-diagnose bugs.

### 1. Simulation and Rendering Are Fully Separated

The simulation layer (`core/`) is pure data — all classes extend `RefCounted`, have zero scene tree dependency, and can run headlessly. The rendering layer (`scenes/`) consumes simulation output but never feeds back into it.

**The communication contract:**
- The simulation runs a complete turn instantly and produces an `EventTimeline` (structured list of what happened: matches, removals, upgrades, gravity moves, spawns).
- The renderer reads the `EventTimeline` and plays it back as animations using Godot Tweens.
- The simulation DOES NOT wait for animations. The board state is already final when the timeline is handed to the renderer.
- `board_changed` signal triggers a full visual rebuild (only on run start / reroll). It must NOT fire after a player swap begins — the timeline animation handles the visual transition.

### 2. All Randomness Must Use SeededRng

Every random value in the simulation MUST go through the `SeededRng` instance passed as a parameter. Never use `randi()`, `randf()`, `Array.shuffle()`, or create a standalone `RandomNumberGenerator`. The game's deterministic replay and anti-cheat depend on identical RNG sequences from the same seed.

**No floating point in the simulation path.** The weighted tile selection in `SpawnResolver` uses `randi_range()` with integer weights, not `randf()`. This ensures cross-platform determinism (float multiplication can produce different results on different CPU architectures).

### 3. Topology Goes Through get_neighbor()

All adjacency queries must use `BoardState.get_neighbor(cell, direction)`, never raw `cell + direction`. This method checks portal overrides before falling back to grid arithmetic. Match detection, gravity, and any future mechanic that asks "what cell is next to this one" must use this method. Direct coordinate math bypasses portals and will break on non-standard board layouts.

### 4. Gravity Goes Through get_effective_gravity()

A cell's gravity direction is determined by `BoardState.get_effective_gravity(cell)`, which checks (in priority order):
1. The tile's `gravity_override` (if non-zero — used for "curse" modifiers)
2. The cell's `gravity_direction` property (set by board layout)
3. Default: `Vector2i.DOWN`

Never hardcode gravity direction. The `BoardPhysics` iterative settling algorithm handles arbitrary per-cell gravity, including spirals, zone transitions, and portals.

### 5. TileView Must Not Consume Mouse Events

`TileView` and all its children have `mouse_filter = MOUSE_FILTER_IGNORE`. All input is handled by `BoardScene._gui_input()` which converts pixel coordinates to cell positions. If a new child node is added to TileView, it MUST also set `mouse_filter = MOUSE_FILTER_IGNORE` or input will silently break.

---

## Project Structure

```
core/board/     Simulation: board grid, tiles, matching, effects, gravity, spawning
core/rules/     Simulation: RNG, event logging, event timeline
core/run/       Simulation: run lifecycle, turn pipeline orchestration
core/visuals/   Model-first gem geometry: spec loading, topology building, projection, mesh assembly, lighting math
native/         C++ GDExtension: Embree-accelerated ray tracer (GemTraceKernel)
native/src/     C++ source files for the native tracer kernel
resources/      Resource class definitions (data schemas)
data/tiles/     Tile definition .tres files (the 8-gem merge ladder)
data/visuals/   GemVisualResource .tres files plus `cut_specs/` authoring assets for gem geometry
autoloads/      Global singletons (config, replay, save, debug, tile registry, gem visuals)
scenes/menu/    Main menu screen (Play + Gem Bake Workbench navigation)
scenes/design/  Active gem bake workbench (offline bake form + preview); legacy designer/gallery remain for reference only
scenes/run/     Run gameplay scene (wires simulation to rendering)
scenes/board/   Board rendering, animation sequencer, input handling
scenes/tile/    Tile visuals (gameplay texture cache + procedural fallback)
scenes/main/    Run entry point scene (hosts RunScene)
scenes/debug/   Debug panel (F1 toggle)
tools/          Design-time utilities (board layout validator, offline bake CLI runner)
tests/          Headless smoke tests (godot --headless --script tests/test_smoke.gd)
plans/          Design documents (not code — reference only)
```

## Deprecated Surfaces

Treat these files/features as historical reference only unless the user explicitly asks to revive them:

- `autoloads/perf_monitor.gd` — deprecated, no longer autoloaded or used by gameplay
- `core/visuals/gem_optics_tracer.gd` — GDScript CPU tracer, now a **fallback only**. The native C++ `GemTraceKernel` (in `native/`) is the primary tracer. The GDScript version is kept as a readable reference implementation and for environments without the compiled extension.
- `core/visuals/gem_material_sampler.gd` — Still used by the procedural 2D renderer (`GemRenderer`) and as reference. The native tracer has its own C++ port of the material sampling (`native/src/gem_trace_material.cpp`).
- Runtime loading-screen overlays are not part of the active run flow anymore; do not assume the game uses a loading screen when reasoning about current UX

### Layer Boundaries

| Layer | May depend on | Must NOT depend on |
|---|---|---|
| `core/board/` | Other `core/` classes, `SeededRng` | Scenes, autoloads (except `TileRegistry` in `EffectResolver` for merge chain lookup) |
| `core/run/` | `core/board/`, `core/rules/`, autoloads (`ReplayService`) | Scenes |
| `core/visuals/` | `resources/visuals/` (resource classes only) | Scenes, autoloads, `core/board/` |
| `native/` | godot-cpp, Embree, `resources/visuals/` (reads GemVisualResource/GemMeshResource via Variant API) | GDScript classes, scenes, autoloads — fully standalone |
| `scenes/` | `core/` (read-only), autoloads | Must not mutate board state directly |
| `autoloads/` | `core/` classes, `resources/` | Scenes |
| `resources/` | Nothing (pure data schemas) | Everything |

The one intentional coupling: `EffectResolver` reads `TileRegistry` (autoload) to resolve merge chains. This is acceptable because the registry is read-only game data. If `TileRegistry` has no definitions loaded, `EffectResolver` falls back to simple `tier += 1`.

---

## Turn Pipeline

When the player swaps two tiles, this exact sequence executes:

```
RunScene._on_swap_requested(cell_a, cell_b)
  → board_scene input lock
  → RunController.begin_swap(cell_a, cell_b)
      1. board.swap_cells(a, b)
      2. match_detector.find_matches(board) — if empty, revert swap, return false
      3. ReplayService.record_action("swap", ...)
      4. TurnController.prepare_turn(board, rng, spawn_table, event_log, [a, b])
  → await BoardScene.animate_swap(cell_a, cell_b)   — visual swap first
  → await process_frame
  → RunController.resolve_remaining_cascades()
      5. Repeatedly call TurnController.step_cascade() until it returns null:
           CASCADE LOOP (max 50 iterations):
             a. MatchDetector.find_matches(board)         — find 3+ runs
             b. MatchClassifier.classify(matches)         — tag as base/4/5+/L-T
             c. EffectPlanner.build_base_plan(classified, swap_cells)
                — plan removes + 1 upgrade
                — swap_cells passed only on first cascade (survivor prefers
                  the swapped cell; cascades use default bottom-right bias)
             d. ConflictResolver.resolve(plan, board)      — deduplicate
             e. EffectResolver.apply(board, plan, log)     — mutate board
             UPGRADE CHAIN LOOP (max 20 iterations):
               e2. MatchDetector.find_matches(board)       — check if upgrades formed new matches
               e3. If empty, break
               e4. Classify → plan → resolve → apply       — resolve chain matches before gravity
             f. BoardPhysics.resolve_gravity(board)        — iterative settling
             g. SpawnResolver.refill_spawn_entries(...)     — fill empty cells
             h. Collect one cascade step into EventTimeline
                (chain rounds stored in chain_steps[] for sequential animation)
           UNTIL no matches found
  → await BoardScene.play_authoritative_async_timeline(timeline)
      6. Adjust moves based on best match across all cascades + chains:
         — base_match (3): -1 move
         — match_4 (4): free (no cost)
         — match_5_plus / match_lt (5+): +1 move
      7. ReplayService.record_checkpoint(final_hash)
      8. Emit run_state_changed
  → Unlock input
```

Key points:
- The authoritative timeline is fully resolved after the swap animation but before cascade playback begins
- `begin_swap` / `resolve_remaining_cascades` do NOT emit `board_changed` — only `run_state_changed` after `finalize_swap()`
- `board_changed` only fires from `start_new_run()` and `reroll_board()` (causes full tile rebuild)
- `BoardScene` may split the authoritative timeline into dependency-safe async groups for playback, but it never feeds results back into simulation
- Input is locked by `RunScene` for the entire swap+cascade duration

---

## Merge Mechanic

When 3+ tiles of the same `match_group` are matched:
- **N-1 tiles are removed**, 1 survivor is upgraded
- **Survivor selection (first cascade):** prefers the swap destination cell, then the swap origin cell, if either participates in the match. This places the upgrade where the player acted.
- **Survivor selection (cascade chains):** falls back to the last cell in the match array (deterministic, bottom-right bias from detection order)
- The upgrade follows the merge chain: `tile.merge_target_id` → look up target definition in `TileRegistry` → transform tile_id, tier, match_group, family_tags
- **Merge ladder:** Quartz(T1) → Amethyst(T2) → Peridot(T3) → Topaz(T4) → Sapphire(T5) → Emerald(T6) → Ruby(T7) → Diamond(T8)
- **T8 matches:** Pure removal (no upgrade target). `EffectPlanner.MAX_STANDARD_TIER = 8`
- **Debug tiles** (no merge_target_id): Fall back to simple `tier += 1`

---

## Gravity System

`BoardPhysics.resolve_gravity()` uses iterative settling, NOT column compaction:

1. Each round: process all cells in fixed order (bottom-to-top, right-to-left). Each tile tries to move one cell in its effective gravity direction.
2. After primary gravity: a diagonal fill pass checks cells with `fill_sources` configured and pulls tiles from diagonal neighbors.
3. Repeat until no tile moves (stable) or `MAX_SETTLE_ROUNDS` (256) reached.
4. All tile movements are recorded in `last_move_events` for the EventTimeline.

This supports: uniform gravity, per-cell gravity directions, per-tile gravity overrides, portals, diagonal fill, immovable tiles, and zone-based gravity layouts (spirals, L-paths, etc.).

**Processing order determines priority** when two tiles compete for the same empty cell. Bottom-to-top right-to-left gives downward gravity natural priority.

---

## Board Topology

`BoardState` is the central topology authority:

- **Grid storage:** Flat array of `CellState`, indexed by `cell.y * size.x + cell.x`
- **Portals:** `_portals` dictionary maps `"x,y,dx,dy"` string keys to `Vector2i` targets. Portals override `get_neighbor()` for gravity routing only (not match detection).
- **Board layouts:** `BoardLayoutResource` defines shape (blocked cells), per-cell gravity, spawn entries, fill sources, and portals. Applied via `board.apply_layout(layout)`. Can be authored as `.tres` files or built programmatically for procedural generation.
- **Spawn entries:** Cells with `is_spawn_entry = true` receive new tiles after gravity. If no cells are marked, falls back to filling all empties (standard behavior).

---

## CellState Properties

| Property | Type | Default | Purpose |
|---|---|---|---|
| `tile` | `TileState` | `null` | The tile occupying this cell |
| `blocked` | `bool` | `false` | Hole/wall — cannot hold tiles |
| `gravity_direction` | `Vector2i` | `DOWN` | Which way tiles fall in this cell |
| `is_spawn_entry` | `bool` | `false` | New tiles enter the board here |
| `fill_sources` | `Array[Vector2i]` | `[]` | Diagonal directions to accept tiles from |
| `tags` | `Dictionary` | `{}` | Extensible metadata (ice, lava, etc.) |

## TileState Properties

| Property | Type | Default | Purpose |
|---|---|---|---|
| `tile_id` | `StringName` | `&"debug_tile"` | Gem identifier (e.g., `&"quartz"`) |
| `match_group` | `StringName` | `&""` | What this tile matches with (falls back to tile_id) |
| `tier` | `int` | `1` | Current tier (1-8 standard, 0 hazards, 9 transcendents) |
| `merge_target_id` | `StringName` | `&""` | Next gem in merge chain (empty = top tier) |
| `family_tags` | `Array[StringName]` | `[]` | Synergy grouping |
| `status_flags` | `Dictionary` | `{}` | On-board effects ("polished", etc.) |
| `protected` | `bool` | `false` | Immune to destruction |
| `gravity_override` | `Vector2i` | `ZERO` | Per-tile gravity (ZERO = use cell gravity) |
| `immovable` | `bool` | `false` | Cannot be moved by gravity or swap |
| `unmatchable` | `bool` | `false` | Excluded from match detection |

---

## Match Detection

`MatchDetector.find_matches()` scans the board along configurable `match_axes` (default: `[RIGHT, DOWN]`).

- Walks each axis using `board.get_neighbor()` (topology-aware)
- Groups consecutive tiles with the same `match_group` into runs
- Runs of 3+ cells become matches
- Skips tiles with `unmatchable = true`
- Portals do NOT create match adjacency (gravity only)

`MatchClassifier` tags matches as `base_match` (3), `match_4` (4), `match_5_plus` (5+), or `match_lt` (L/T intersection of horizontal + vertical matches sharing a cell).

---

## Rendering Animation Flow

`BoardScene` maintains a persistent `Dictionary[Vector2i, TileView]` mapping grid cells to visual nodes. Tile views are NOT rebuilt each frame — they persist and are animated in place.

Each cascade step is animated in four ordered chunks, with optional async overlap between independent groups:
1. **Match highlight** — matched tiles flash bright (`modulate = 1.5`)
2. **Remove + Upgrade** — removed tiles converge/fade; survivor swaps to the upgraded gem visual and plays a scale pulse
3. **Gravity** — physics move events are consolidated per tile, then tweened with `AnimationSequencer.gravity_trans` and `AnimationSequencer.fall_duration()` plus per-column stagger
4. **Spawn** — new tiles are pre-created above the board and join the same fall wave as gravity tiles

Upgrade-chain rounds inside one cascade step are played sequentially before gravity/spawn. Independent touched-cell regions can be split into async groups and played in parallel when their dependencies are already complete.

**Swap animations** happen BEFORE the cascade: `animate_swap()` slides the two tiles to each other's positions over 0.15s. Invalid swaps use `animate_invalid_swap()` which slides tiles partway then bounces back.

---

## TileRegistry (Autoload)

Loads all `.tres` tile definitions from `data/tiles/` at startup. Provides:
- `get_definition(tile_id)` → `TileDefinitionResource`
- `get_ids_for_tier(tier)` → `Array[StringName]`
- `create_tile(tile_id)` → `TileState` with all fields populated from definition
- `create_tile_for_tier(tier, rng)` → random tile at that tier
- `get_tier_color(tier)` → `Color` for debug or fallback rendering
- `has_definitions()` → `bool` (false in headless tests that skip autoloads)

`SpawnResolver` uses `TileRegistry` to create named tiles instead of anonymous debug tiles. `EffectResolver` uses it to resolve merge chains. Both fall back gracefully when the registry is unavailable.

---

## Procedural Gem Rendering

Gems are authored from a canonical 3D model-first pipeline. Gameplay uses offline-traced textures generated from that source data; procedural drawing remains as the runtime fallback when a traced texture is unavailable. The source-of-truth system has these layers:

### GemCutSpecResource (geometry authoring)

Defines a cut in typed, data-driven form. Stored in `data/visuals/cut_specs/`. Key sections include:
- `spec_id` / `display_name` / `compatibility_cut_id`
- `family` / `symmetry` / `rings`
- `crown` / `pavilion` / `girdle` / `culet`
- `patches` — small named-loop tweaks applied by the generic builders
- `constraints` / `orthographic_metadata`

### GemCutCompiler3D / GemCutModelResource

`GemCutCompiler3D` compiles a spec into the canonical `GemCutModelResource`. The compile path:
1. Builds family topology through `GemTopologyBuilders3D`
2. Normalizes/centers the model through `GemGeometryNormalizer`
3. Validates geometry quality through `GemGeometryValidator`

`GemCutModelResource` carries the compiled 3D facet data plus stable `spec_id` and `geometry_signature` identifiers used by caches and downstream consumers.

### GemCutProjector / GemProjectedCutResource

`GemCutProjector` derives the procedural fallback packet from the compiled model. `GemProjectedCutResource` contains:
- projected facet polygons and normals for `GemRenderer`
- silhouette and edge segments for outlines/internal lines
- pavilion extinction overlay fragments and source/target facet metadata
- the same `spec_id` / `geometry_signature` identity used by the model

### GemMeshAssembler / GemMeshResource

`GemMeshAssembler` converts the compiled model into `GemMeshResource`, the traced-bake mesh packet consumed by the offline ray tracer. The mesh retains `spec_id` and `geometry_signature` so traced manifests and runtime requests key the same canonical geometry.

### GemVisualResource (appearance config)

`.tres` files in `data/visuals/`, one per gem type. Each visual references a `cut_spec` and optional `cut_overrides`, then configures:
- `base_color` — primary gem colour
- `shininess` / `specular_intensity` — Blinn-Phong specular parameters
- `contrast` (0–1) — blends between Half-Lambert (soft, flat) and standard Lambert (dramatic shadows). Low tiers use low contrast; high tiers use high contrast.
- `depth_tint` — colour shift for facets facing away from the viewer (simulates transparency)
- `hue_dispersion` (0–0.5) — prismatic "fire" effect. Each facet shifts hue based on its normal angle. Used primarily for Diamond.
- `saturation_boost` — post-process saturation adjustment
- `transparency` (0–1) — reduces alpha across all facets
- `rim_intensity` / `rim_color` / `rim_power` — Fresnel edge glow on tilted facets
- `translucency` / `translucency_color` — subsurface scattering approximation; fills shadow areas with transmitted light
- `secondary_specular` / `secondary_light_angle` — second Blinn-Phong highlight from a rotated light direction
- `sparkle_intensity` / `sparkle_threshold` — dramatic brightness boost on highly specular-aligned facets
- `gradient_color` / `gradient_strength` — vertical colour zoning (top-to-bottom blend)
- `brilliance_contrast` (0–1) — zone-based brightness: brightens table/star, darkens girdle
- `extinction` (0–1) — pavilion extinction intensity; controls the pavilion overlay opacity only
- `use_texture` / `color_texture` — for patterned gems like opals (samples texture at facet centroid)

### GemRenderer (lighting math)

Pure `RefCounted`, no scene dependency. Computes flat-shaded colour per facet:
1. **Diffuse:** `lerp(half_lambert, standard_lambert, contrast)` — blends soft/dramatic shading
2. **Specular:** Blinn-Phong with configurable shininess and intensity
3. **Depth tint:** Back-facing facets shift toward the depth tint colour
4. **Color gradient:** Optional vertical colour zoning from top to bottom of gem
5. **Translucency:** Fills shadow areas with transmitted light colour (subsurface scattering approximation)
6. **Rim lighting:** Fresnel edge glow on tilted facets, remapped for pseudo-3D normal range
7. **Secondary specular:** Second Blinn-Phong from rotated light direction
8. **Hue dispersion:** Optional prismatic hue shift per facet based on normal angle
9. **Sparkle boost:** Dramatic additive brightness on facets exceeding specular alignment threshold
10. **Per-facet jitter:** ±4% deterministic brightness variation from centroid hash — ensures neighbouring facets are always distinguishable even without visible edge lines
11. **Saturation boost:** Post-process saturation adjustment
12. **Zone brilliance:** Table/star brightened, girdle darkened, scaled by brilliance_contrast
13. **Transparency:** Reduces alpha across all facets

Also provides `compute_pavilion_colors()` for the pavilion extinction overlay — semi-transparent dark colours for each clipped pavilion fragment, with opacity based on `extinction` intensity and the fragment's light-return score.

### GemVisualRegistry (autoload)

Loads `GemVisualResource` files from `data/visuals/` and compiles/caches canonical geometry on demand. Provides:
- `get_visual(tile_id)` → `GemVisualResource`
- `get_visual_for_tier(tier)` → `GemVisualResource` (resolved via TileRegistry)
- `get_cut(geometry_signature)` → `GemProjectedCutResource`
- `get_cut_model(geometry_signature)` → `GemCutModelResource`
- `get_visual_cut_with_offset(...)` / `get_visual_cut_model_with_offset(...)` for resolved visual geometry plus normalized draw offset
- shared color / geometry / render-bundle caches used by both direct drawing and gameplay baking
- `ensure_gameplay_texture_cache(draw_size)` / `get_gameplay_texture(...)` for board-ready offline-traced textures
- `get_offline_traced_manifest_summary()` for runtime/workbench visibility into traced assets
- `gameplay_texture_cache_rebuilt` signal so `BoardScene` can await the correct cell-size bake before rebuilding views

### TileView integration

`TileView` resolves visuals in this priority order:
1. Offline-traced gameplay texture (when `use_gameplay_texture_cache` is enabled and the registry has a traced texture for this tile/tier)
2. Procedural gem via `_draw()` using shared cached render data
3. Coloured rectangle (headless/debug fallback)

The procedural draw pass renders: filled crown facets, pavilion extinction overlay (semi-transparent dark fragments), silhouette outline, and internal edge lines. Gameplay textures are sourced from the offline-traced manifest, while the procedural fallback uses the same compiled geometry and render-bundle data so the two paths stay aligned.

Silhouette outline toggled via `DebugFlags.gem_silhouette_outline`.

### Shape-to-Tier Mapping

Each tier has a distinct silhouette shape for instant visual identification:

| Tier | Gem | Shape | Cut ID | Facet Count |
|------|-----|-------|--------|-------------|
| T1 | Quartz | Octagon | `simple_octagon_step` | 17 |
| T2 | Amethyst | Square (rounded) | `cushion` | 33 |
| T3 | Peridot | Triangle (bowed edges) | `trillion` | 19 |
| T4 | Topaz | Rotated Square ◆ | `lozenge` | 13 |
| T5 | Sapphire | Hexagon | `hex_brilliant` | 25 |
| T6 | Emerald | Rectangle (portrait) | `emerald_step` | 17 |
| T7 | Ruby | Oval (portrait) | `oval_brilliant` | 33 |
| T8 | Diamond | Pear/Teardrop | `pear_brilliant` | 41 |

### Progressive Visual Hierarchy

| Tier | Contrast | Specular | Depth Tint | Dispersion | Visual Feel |
|------|----------|----------|------------|------------|-------------|
| T1 | 0.18 | 0.3 | warm amber | none | Soft, warm, translucent |
| T2 | 0.55 | 0.5 | deep violet | none | Vivid, dramatic |
| T3 | 0.35 | 0.4 | yellow-green | none | Bright, highly translucent |
| T4 | 0.5 | 0.4 | deep amber | none | Warm, golden shadows |
| T5 | 0.7 | 0.55 | near-black blue | none | Intense, deep |
| T6 | 0.6 | 0.4 | blue-teal | none | Rich, window effect |
| T7 | 0.7 | 0.55 | dark red-black | none | Dramatic, intense |
| T8 | 0.6 | 0.9 | icy blue | 0.25 | Brilliant, prismatic fire |

All gems additionally use rim lighting, zone brilliance, and pavilion extinction at tier-appropriate intensities. Higher tiers feature secondary specular, sparkle, and stronger extinction for increased visual complexity.

---

## Native Ray Tracer (GemTraceKernel)

The primary offline bake tracer is a C++ GDExtension using Intel Embree for hardware-optimized BVH traversal and intersection. It replaces the GDScript `GemOpticsTracer` (which remains as a fallback for environments without the compiled extension).

### Architecture

```
native/
├── godot-cpp/              Git submodule (Godot C++ bindings, 4.5 branch)
├── embree/                 Vendored Embree 4.x SDK (headers, libs, runtime DLLs)
├── SConstruct              SCons build script
├── src/
│   ├── register_types.cpp  GDExtension entry point — registers GemTraceKernel
│   ├── gem_trace_kernel.h  Public class (RefCounted, exposed to GDScript)
│   ├── gem_trace_kernel.cpp Full trace pipeline: spectral trace, lighting, grading
│   ├── gem_trace_scene.h   Embree scene wrapper (RTCDevice/RTCScene lifecycle)
│   ├── gem_trace_scene.cpp Builds Embree scene from GDScript trace_data Dictionary
│   ├── gem_trace_material.h Procedural material sampling (ported from GemMaterialSampler)
│   ├── gem_trace_material.cpp Noise, patterns, reactive effects — all stateless
│   └── gem_trace_types.h   All shared types, constants, inline math helpers
└── lib/win64/              Build output (.dll) + Embree runtime DLLs
```

### Tracer Selection (Feature Flag)

`OfflineGemBakeJob._trace_request_worker()` checks at runtime:
```gdscript
if ClassDB.class_exists(&"GemTraceKernel"):
    tracer = ClassDB.instantiate(&"GemTraceKernel")  # Native C++ + Embree
else:
    tracer = GemOpticsTracerScript.new()               # GDScript fallback
```

Both expose the same API: `trace_to_image(mesh_resource, visual, request) -> Image` and `get_last_trace_profile() -> Dictionary`. The native kernel is ~50-100x faster.

### Building

Requires: MSVC 2022 (Desktop C++ workload), Python 3.x, SCons (`pip install scons`).

```bash
cd native
python -m SCons platform=windows target=template_debug
# Copy Embree runtime DLLs (once, or when Embree is updated):
cp embree/bin/embree4.dll lib/win64/
cp embree/bin/tbb12.dll lib/win64/
```

The `.gdextension` descriptor (`native.gdextension` in project root) and `.godot/extension_list.cfg` tell Godot where to find the compiled library. No changes to `project.godot` are needed.

### What the C++ Kernel Ports

The native kernel is a complete port of `GemOpticsTracer` (~1935 lines GDScript → ~3200 lines C++):

| Component | GDScript (fallback) | C++ (primary) |
|---|---|---|
| BVH build + intersection | `gem_mesh_resource.gd` (median-split BVH) | `gem_trace_scene.cpp` (Embree QBVH with SIMD) |
| Recursive spectral trace | `gem_optics_tracer.gd` | `gem_trace_kernel.cpp` |
| Surface lighting (~200 lines) | `gem_optics_tracer.gd` | `gem_trace_kernel.cpp` |
| Material sampling (noise, patterns) | `gem_material_sampler.gd` | `gem_trace_material.cpp` |
| Output grading (ACES, gamma) | `gem_optics_tracer.gd` | `gem_trace_kernel.cpp` |
| Row-band threading | GDScript `Thread` | `std::thread` |

### CLI Bake Reference

The offline bake runs as a headless Godot process via `tools/run_offline_gem_bake.gd`. Key flags:

```bash
godot --headless --path . --script res://tools/run_offline_gem_bake.gd -- [OPTIONS]
```

| Flag | Default | Description |
|---|---|---|
| `--gems=<ids>` | `all` | Comma-separated tile IDs or `all` |
| `--size=<px>` | `112` | Cell size (square) |
| `--draw_size=<px>` | same as size | Trace resolution (can be larger for supersampling) |
| `--samples=<n>` | `1` | MSAA sample count (1-5) |
| `--max_trace_bounces=<n>` | `12` | Max internal reflection bounces |
| `--threads=<n>` | auto | Per-trace thread count |
| `--variant_workers=<n>` | auto (max 4) | Parallel variant bake workers |
| `--lighting_preset=<name>` | `quality` | Grid preset: `performance`(3x3), `balanced`(4x4), `quality`(5x5), `ultra`(6x6) |
| `--lighting_grid=<X,Y>` | from preset | Custom lighting grid dimensions |
| `--lighting_bins=<X,Y[;...]>` | all | Specific lighting bin coordinates to bake |
| `--skip_lighting` | false | Skip all lighting variants |
| `--skip_rotations` | false | Skip all rotation variants |
| `--rotation_base_view_count=<n>` | `6` | Number of orthogonal views (crown, front, right, pavilion, left, back) |
| `--rotation_labels=<names>` | all | Specific rotation views by label |
| `--rotation_bins=<indices>` | all | Specific rotation views by index |
| `--skip_stylize` | false | Skip post-trace stylizer |
| `--output=<path>` | `user://traced_bakes` | Output directory |
| `--trace_profile` | false | Include per-trace timing profile |

Example — bake one high-quality Diamond frame without stylization:
```bash
godot --headless --path . --script res://tools/run_offline_gem_bake.gd -- \
    --gems=diamond --size=512 --draw_size=512 --samples=5 \
    --skip_lighting --rotation_labels=front --skip_stylize \
    --output=res://assets/debug_bakes
```

---

## SpawnTableResource

Defines which tiers can spawn and with what probability:
```
allowed_tiers: Array[int] = [1, 2, 3, 4]
weights: Array[int] = [4, 3, 2, 1]     # INTEGER only — no floats
```

The default table spawns T1-T4 with decreasing probability. Weights are integers to avoid floating-point cross-platform determinism issues.

---

## State Hashing & Replay

- `BoardState.compute_hash()` produces a deterministic integer hash of the complete board state (cell blocked flags, gravity directions, all tile properties). Used for anti-cheat checkpoints.
- `ReplayService` records seed + player actions + board hash checkpoints. A verifier replays the same seed+actions and compares hashes at each checkpoint.
- Hash is recorded after every turn via `ReplayService.record_checkpoint()`.

---

## Board Validation

`BoardValidator` (in `tools/`) validates `BoardLayoutResource` configurations:
- **Cycle detection:** Gravity paths that loop back to themselves
- **Reachability:** Cells that no spawn entry's gravity lane can reach
- **Portal validation:** Out-of-bounds or blocked portal targets
- **Contention zones:** Cells where multiple gravity paths converge

Run headlessly for level design QA. Warnings are informational; errors indicate configurations that will break the engine.

---

## Testing

Run headless smoke tests: `godot --headless --script tests/test_smoke.gd`

Focused cut regression test: `godot --headless --script tests/test_gem_cuts.gd`

Native tracer extension test: `godot --headless --script tests/test_native_trace_kernel.gd`

The test suites cover: board creation, topology (neighbors, portals, gravity), match detection (including unmatchable/holes), merge mechanic (remove count, upgrade, max tier), gravity (standard, custom direction, tile override, immovable, iterative convergence, diagonal fill, portals, cycle safety), pipeline (effect planning, conflict resolution, spawning, timeline structure), deterministic replay verification, and procedural cut generation invariants including pavilion fragment integrity, pavilion symmetry metadata, and winding-independent clipping.

Cross-platform RNG test: `godot --headless --script tests/test_rng_cross_platform.gd` — prints reference values to compare across platforms.

---

## Common Pitfalls

| Pitfall | Why it breaks | What to do instead |
|---|---|---|
| Using `randf()` or `randi()` in simulation | Breaks deterministic replay | Use `SeededRng` instance passed as parameter |
| Using `cell + direction` for adjacency | Bypasses portals | Use `board.get_neighbor(cell, direction)` |
| Emitting `board_changed` after a swap | Destroys tile views mid-animation | Only emit from `start_new_run` / `reroll_board` |
| Adding a child node to TileView without `MOUSE_FILTER_IGNORE` | Blocks click events from reaching BoardScene | Set `mouse_filter = MOUSE_FILTER_IGNORE` on all TileView children |
| Hardcoding gravity as DOWN | Breaks custom gravity layouts | Use `board.get_effective_gravity(cell)` |
| Using `Array[float]` for spawn weights | Float math may differ across platforms | Use `Array[int]` — integer-only weighted selection |
| Adding game logic that reads frame timing or animation state | Couples simulation to rendering | Simulation is instant; only the renderer deals with time |
| Iterating a Dictionary in simulation and expecting stable order | Dictionary iteration order can vary | Use arrays for ordered data; dictionaries for lookup only |

---

## Deferred Systems (Not Yet Implemented)

These systems are designed but intentionally excluded from the current scaffold. See `plans/deferred-systems-reference.md` for full specs.

- **Modifier Pipeline** — Hook-based system for boons/modifiers to inject behavior at pipeline stages
- **Floor Progression** — `FloorDefinitionResource` + `FloorState` for multi-floor runs with escalating difficulty
- **Boon System** — Passive run modifiers (Settings affect merge mechanics, Treatments affect economy/spawns)
- **Hazard System** — T0 obstacle tiles (blockers, tricksters, poison spreaders)
- **Extended Effects** — DOWNGRADE, CONVERT, SPAWN, MOVE, PROTECT, AWARD_MOVE, APPLY_STATUS
- **Protection Mechanics** — High-tier tiles immune to auto-clears
- **Cell Tags** — Per-cell modifiers (ice, lava, conveyor)
- **T9 Transcendent Gems** — Powerful one-use special tiles

---

## File Quick Reference

| What you want to change | File(s) to modify |
|---|---|
| Add a new gem type | Create `.tres` in `data/tiles/`, `TileRegistry` auto-loads it |
| Change a gem's visual appearance | Edit its `.tres` in `data/visuals/` (colour, shininess, `cut_spec`, overrides) |
| Add a new gem cut | Add/update a `GemCutSpecResource` in `data/visuals/cut_specs/`, then reference it from a `GemVisualResource` |
| Add shared cut outline math | `core/visuals/gem_cut_primitives.gd` |
| Add a new cut topology family | `core/visuals/gem_topology_builders_3d.gd` |
| Change the lighting model | `core/visuals/gem_renderer.gd` — `compute_facet_color()` |
| Add a visual modifier effect | Add parameter handling in `GemRenderer.compute_all_facet_colors()` modifiers dict |
| Add a new visual property | Add `@export` to `resources/visuals/gem_visual_resource.gd`, handle in `GemRenderer`, add control in `scenes/design/gem_bake_workbench.gd` if tooling needs it |
| Change pavilion extinction geometry | `core/visuals/gem_cut_projector.gd` and/or `core/visuals/gem_topology_builders_3d.gd` |
| Change pavilion extinction rendering | `core/visuals/gem_renderer.gd` — `compute_pavilion_colors()` |
| Preview or rebake gameplay gem variants | Use the Gem Bake Workbench scene (`scenes/design/gem_bake_workbench.tscn`) |
| Change the native tracer's trace logic | `native/src/gem_trace_kernel.cpp` — rebuild with `scons platform=windows target=template_debug` |
| Change the native tracer's material sampling | `native/src/gem_trace_material.cpp` — rebuild after changes |
| Change the native tracer's Embree intersection | `native/src/gem_trace_scene.cpp` — rebuild after changes |
| Rebuild the native extension | `cd native && python -m SCons platform=windows target=template_debug` |
| Change merge behavior (what happens on 4-match, 5-match) | `core/board/effect_planner.gd` — `_plan_match_4()`, `_plan_match_5_plus()` |
| Add a new effect type | Add const in `EffectPlanner`, handle in `EffectResolver.apply()` |
| Change gravity behavior | `core/board/board_physics.gd` |
| Change spawn distribution | Modify `SpawnTableResource` weights or create new `.tres` |
| Add a new tile property | Add to `TileState`, update `duplicate_tile()` and `to_dict()`, update `compute_hash()` in `BoardState` |
| Add a new cell property | Add to `CellState`, update `to_dict()`, update `BoardLayoutResource` if configurable per-level |
| Change board layout | Create/modify `BoardLayoutResource`, apply via `board.apply_layout()` |
| Add animation for a new effect | Add a phase in `BoardScene._play_cascade_step()` |
| Change animation timing | `scenes/board/animation_sequencer.gd` constants |
| Add input handling | `BoardScene._gui_input()` for board interaction, `RunScene` for game-level input |
| Add a new autoload | Create in `autoloads/`, register in `project.godot` under `[autoload]` |
| Validate a board layout | `tools/board_validator.gd` — `BoardValidator.new().validate(layout)` |
