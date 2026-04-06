# Facets

A gemstone-themed match-3 merge roguelike built in Godot 4.6 (GDScript). Landscape desktop layout (1920x1080), with future portrait mobile pivot planned.

Players swap tiles to form matches of 3+. Matched tiles merge into higher-tier gems following the gem ladder (3 Quartz → 1 Amethyst → ... → Diamond). The goal is to forge high-tier gems within a limited number of moves.

## Project Structure

```
autoloads/          # Singletons (GameConfig, DebugFlags, ReplayService, SaveService, TileRegistry, GemVisualRegistry)
core/
  board/            # Simulation: board grid, tiles, matching, effects, gravity, spawning
  rules/            # Simulation: SeededRng, EventLog, EventTimeline
  run/              # Simulation: run lifecycle, turn pipeline orchestration
  visuals/          # Model-first gem geometry, projection, mesh assembly, and lighting math
native/             # C++ GDExtension: Embree-accelerated ray tracer (GemTraceKernel)
  src/              # C++ source: trace kernel, Embree scene, material sampler, types
  godot-cpp/        # Git submodule: Godot C++ bindings (4.5 branch)
  embree/           # Vendored Intel Embree 4.x SDK
data/
  tiles/            # Tile definition .tres files (8-gem merge ladder)
  visuals/          # GemVisualResource .tres files (per-gem colour, material, cut assignment)
  spawn_tables/     # SpawnTableResource .tres files
plans/              # Design documents (reference only, not code)
resources/
  definitions/      # Resource class definitions (simulation data schemas)
  visuals/          # Resource class definitions (GemCutSpecResource, GemCutModelResource, GemVisualResource, ...)
scenes/
  board/            # Board rendering, animation sequencer, input handling
  menu/             # Main menu (Play + Gem Bake Workbench navigation)
  design/           # Gem Bake Workbench (offline bake form + gameplay texture preview)
  main/             # Run entry point scene (hosts RunScene)
  run/              # Run gameplay scene (wires simulation to rendering)
  tile/             # Tile visuals (gameplay texture cache + procedural fallback)
  debug/            # Debug panel (F1 toggle, animation tuning sliders)
tests/              # Headless smoke tests (40+ tests)
tools/              # Board layout validator, offline bake CLI runner
```

## Core Pipeline

Each turn follows this deterministic pipeline:

1. **Swap** — Player swaps two adjacent tiles
2. **Detect** — `MatchDetector` finds all 3+ runs (topology-aware via `get_neighbor()`)
3. **Classify** — `MatchClassifier` labels patterns (base, 4-match, 5+, L/T)
4. **Plan** — `EffectPlanner` plans removes + 1 survivor upgrade per match
5. **Conflict** — `ConflictResolver` deduplicates effects targeting the same cell
6. **Resolve** — `EffectResolver` mutates the board (removes tiles, upgrades survivor via merge chain)
7. **Physics** — `BoardPhysics` runs iterative gravity settling (per-cell direction, portals, diagonal fill)
8. **Spawn** — `SpawnResolver` fills spawn-eligible cells using integer-weighted tables
9. **Cascade** — Steps 2–8 repeat until no new matches form

The simulation completes instantly and produces an `EventTimeline`. During gameplay, `RunScene` validates the swap, animates the visual swap first, then resolves the remaining cascades into one authoritative timeline for playback. `BoardScene` can split that precomputed timeline into independent async groups for clearer, more parallel-feeling animation without changing deterministic outcomes. See `AGENTS.md` for the full architectural reference.

## Procedural Gem Rendering

Gems are authored from a canonical 3D model-first pipeline. Normal gameplay consumes offline-traced textures generated from that source data; direct procedural drawing remains only as the visual fallback when a traced texture is unavailable. There is no hand-authored sprite atlas in the active path. The main layers are:

- **`GemCutSpecResource`** (`data/visuals/cut_specs/`) — typed authoring data for a cut family, symmetry, ring layout, pavilion, girdle, constraints, and optional named-loop patches
- **`GemCutModelResource`** — canonical compiled 3D artifact with facet polygons, normals, zones, and a stable `geometry_signature`
- **`GemProjectedCutResource`** — orthographic 2D projection packet derived from the compiled model for procedural fallback rendering
- **`GemMeshResource`** — traced-bake mesh packet assembled from the compiled model for the ray tracer
- **`GemVisualResource`** (`.tres` in `data/visuals/`) — per-gem appearance data plus a direct `cut_spec` reference and optional overrides
- **`GemCutCompiler3D`**, **`GemCutProjector`**, **`GemMeshAssembler`** — the compile/project/mesh stages of the canonical geometry pipeline
- **`GemRenderer`** — pure-math facet shading used by the procedural fallback and shared render bundles
- **`GemVisualRegistry`** — shared cache owner for compiled geometry, projected cuts, render bundles, and offline-traced gameplay textures
- **`GameplayGemBakeView`** — hidden raster surface for procedural preview/fallback rendering only; gameplay baking itself is sourced from offline traced output

Each tier has a distinct **silhouette shape** for instant visual identification:

| Tier | Gem | Shape | Signature Cut |
|------|-----|-------|---------------|
| T1 | Quartz | Circle | Classic Round Brilliant |
| T2 | Amethyst | Square (rounded) | Cushion |
| T3 | Peridot | Triangle (bowed edges) | Trillion |
| T4 | Topaz | Rotated Square ◆ | Radiant Diamond |
| T5 | Sapphire | Hexagon | Hex Brilliant |
| T6 | Emerald | Rectangle (portrait) | Emerald Step |
| T7 | Ruby | Oval (portrait) | Oval Brilliant |
| T8 | Diamond | Pear/Teardrop | Pear Brilliant |

The spec library also includes alternate cuts such as Asscher, baguette, tapered baguette, octagon step, marquise, heart, old European round, princess square, radiant octagon, and a rose-cut family for future use.

Higher tiers have progressively more dramatic shading, brighter specular highlights, deeper depth tints, stronger rim lighting, and more pronounced pavilion extinction patterns. Diamond features prismatic hue dispersion ("fire"), maximum sparkle, and strong secondary specular.

`TileView` prefers an offline-traced gameplay texture from `GemVisualRegistry` and falls back to procedural `_draw()` only when that texture is unavailable. Both paths share the same compiled geometry and render-bundle caches, so the traced and procedural views stay aligned. The procedural draw pass still renders filled crown facets, pavilion extinction overlay, silhouette outline, and internal edge lines. Pavilion overlays are derived from projected model metadata, and `extinction` controls only overlay strength rather than also darkening crown facets. If no gem visual can be resolved, the remaining fallback is a coloured debug rectangle. Silhouette outlines are toggled via `DebugFlags.gem_silhouette_outline`.

Gameplay baking is an offline-traced pipeline backed by the native C++ ray tracer (`GemTraceKernel` GDExtension with Intel Embree). The GDScript `GemOpticsTracer` is kept only as an internal fallback implementation for environments without the compiled extension. The bake pipeline, manifest format, and CLI usage are documented in [AGENTS.md](AGENTS.md) under "Native Ray Tracer" and "CLI Bake Reference".

## Gem Bake Workbench

The Gem Bake Workbench (`scenes/design/gem_bake_workbench.tscn`) is the active gem tooling surface. It provides:

- **Offline bake form** — choose which gems to trace, lighting-grid density, rotation-axis sweeps, cell size, bake draw size, sample count, and worker threads
- **Async job runner** — launches the traced bake in a separate headless Godot process and polls a status file so the UI stays responsive
- **Gameplay preview board** — drag the selected gem around a run-style light grid to inspect the loaded lighting-bin blend
- **Axis rotation cards** — preview pitch/yaw/roll rotation bins when the loaded manifest includes those sweeps
- **Runtime reload** — refreshes the gameplay texture cache after a bake completes so subsequent runs use the new traced textures

## Building the Native Tracer

The native `GemTraceKernel` GDExtension requires MSVC 2022 (Desktop C++ workload), Python 3.x, and SCons. Without building it, the project still works using the GDScript fallback tracer.

```bash
pip install scons
cd native
python -m SCons platform=windows target=template_debug
# Copy Embree runtime DLLs (once):
cp embree/bin/embree4.dll lib/win64/
cp embree/bin/tbb12.dll lib/win64/
```

After building, restart Godot. The bake pipeline will automatically detect and use the native kernel.

## Playing

Open in Godot 4.6 and run the project. The main menu provides navigation to Play (starts a run) or the Gem Bake Workbench. Click a tile to select it (yellow highlight), then click an adjacent tile to swap. Drag between adjacent tiles also works. Valid swaps trigger the full merge cascade with animations. Invalid swaps bounce back.

The HUD shows remaining moves and the current seed.

## Running Tests

```bash
godot --headless --script tests/test_smoke.gd
```

Focused cut regression coverage:

```bash
godot --headless --script tests/test_gem_cuts.gd
```

The test suites cover topology, match detection, merge mechanics, gravity, the full cascade pipeline, deterministic replay verification, cut generation, normalized geometry bounds, facet counts, silhouette stability, pavilion fragment integrity, pavilion symmetry metadata, and winding-independent clipping.

Additional traced/bake coverage:

```bash
godot --headless --script tests/test_gem_meshes.gd
godot --headless --script tests/test_gem_optics_tracer.gd
godot --headless --script tests/test_native_trace_kernel.gd
godot --headless --script tests/test_gameplay_bake_backends.gd
godot --headless --script tests/test_gameplay_variant_math.gd
```

Optional long-run balance harness:

```bash
godot --headless res://tests/test_simulation.tscn
```

Cross-platform RNG verification:
```bash
godot --headless --script tests/test_rng_cross_platform.gd
```

## Key Architecture Decisions

- **Simulation-first:** All game logic is in `core/` using `RefCounted` classes with zero scene tree dependency. Runs headlessly.
- **Deterministic replay:** All randomness flows through `SeededRng` using integer-only operations. `BoardState.compute_hash()` provides checkpoint verification.
- **Topology abstraction:** All adjacency uses `BoardState.get_neighbor()` which supports portals. All gravity uses `get_effective_gravity()` which supports per-cell and per-tile overrides.
- **Event-driven rendering:** Simulation produces an authoritative `EventTimeline`; renderer plays it back via Godot Tweens and may overlap independent visual groups without re-running simulation.
- **Model-first visuals:** Gem geometry is authored as `GemCutSpecResource`, compiled once into a canonical 3D model, then projected or meshed for each consumer. No hand-authored sprites are needed in the active path.

## Documentation

- [AGENTS.md](AGENTS.md) — Full architectural reference for AI agents and contributors
- [core/visuals/README.md](core/visuals/README.md) — Procedural cut-system architecture and extension guide
- [Traced Bake Pipeline Reference](plans/traced-bake-pipeline-reference.md) — Offline traced bake architecture, parameter flow, and recommended settings
- [Gem Engine Proposal](plans/gem-engine-proposal.md) — Game design and architecture proposal
- [Executive Analysis](plans/executive-analysis.md) — Proposal review and scaffolding audit
- [Getting Started Guide](plans/getting-started-guide.md) — Godot overview and phased prototyping plan
- [Deferred Systems Reference](plans/deferred-systems-reference.md) — Systems designed but deferred to later phases
