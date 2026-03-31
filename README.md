# Facets

A gemstone-themed match-3 merge roguelike built in Godot 4.6 (GDScript). Landscape desktop layout (1920x1080), with future portrait mobile pivot planned.

Players swap tiles to form matches of 3+. Matched tiles merge into higher-tier gems following the gem ladder (3 Quartz → 1 Amethyst → ... → Diamond). The goal is to forge high-tier gems within a limited number of moves.

## Project Structure

```
autoloads/          # Singletons (GameConfig, DebugFlags, ReplayService, SaveService, TileRegistry, GemVisualRegistry, PerfMonitor)
core/
  board/            # Simulation: board grid, tiles, matching, effects, gravity, spawning
  rules/            # Simulation: SeededRng, EventLog, EventTimeline
  run/              # Simulation: run lifecycle, turn pipeline orchestration
  visuals/          # Procedural gem rendering: profiles, builders, primitives, lighting math
data/
  tiles/            # Tile definition .tres files (8-gem merge ladder)
  visuals/          # GemVisualResource .tres files (per-gem colour, material, cut assignment)
  spawn_tables/     # SpawnTableResource .tres files
plans/              # Design documents (reference only, not code)
resources/
  definitions/      # Resource class definitions (simulation data schemas)
  visuals/          # Resource class definitions (visual data schemas: GemCutResource, GemVisualResource)
scenes/
  board/            # Board rendering, animation sequencer, input handling
  menu/             # Main menu (Play + Gem Designer navigation)
  design/           # Gem Designer tool (interactive visual editor with real-time preview + export)
  main/             # Run entry point scene (hosts RunScene)
  run/              # Run gameplay scene (wires simulation to rendering)
  tile/             # Tile visuals (gameplay texture cache + procedural fallback)
  debug/            # Debug panel (F1 toggle, animation tuning sliders)
tests/              # Headless smoke tests (40+ tests)
tools/              # Board layout validator
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

Gems are still authored procedurally, but normal board gameplay now uses runtime-baked textures generated from that procedural source data rather than redrawing every polygon every frame. There is no hand-authored sprite atlas in the main path. Each gem type is defined by:

- **`GemCutResource`** — 2D polygon geometry defining the facet layout plus cut-specific pavilion overlay metadata/fragments (generated at startup from profile-driven cut builders)
- **`GemVisualResource`** (`.tres` in `data/visuals/`) — Per-gem colour and material properties (shininess, contrast, specular intensity, depth tint, hue dispersion, rim lighting, translucency, secondary specular, sparkle, gradient, zone brilliance, pavilion extinction)
- **`GemRenderer`** — Pure-math lighting: Half-Lambert/Lambert diffuse blend, Blinn-Phong specular, depth tint, colour gradient, translucency/SSS, Fresnel rim lighting, secondary specular, hue dispersion, sparkle boost, per-facet brightness jitter, zone brilliance, transparency, plus a separate pavilion-overlay colouring pass
- **`GemVisualRegistry`** — Shared cache owner for facet colours, scaled geometry, render bundles, and gameplay-baked textures
- **`GameplayGemBakeView`** — Hidden bake surface used by the registry to rasterize a gem into a gameplay texture for `TileView`
- **`core/visuals/gem_cut_profiles.gd`** — declarative cut library
- **`core/visuals/gem_cut_builders.gd`** — reusable facet topology builders + cut-specific pavilion overlay generation
- **`core/visuals/gem_cut_primitives.gd`** — shared outline math, curve sampling helpers, and winding-safe Sutherland-Hodgman polygon clipping

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

The profile base now also includes alternate cuts such as Asscher, baguette, tapered baguette, octagon step, marquise, heart, old European round, princess square, radiant octagon, and a rose-cut family for future use.

Higher tiers have progressively more dramatic shading, brighter specular highlights, deeper depth tints, stronger rim lighting, and more pronounced pavilion extinction patterns. Diamond features prismatic hue dispersion ("fire"), maximum sparkle, and strong secondary specular.

`TileView` now prefers a gameplay texture from `GemVisualRegistry` and falls back to procedural `_draw()` when the cache is unavailable. Both paths share the same cached render bundles, so the bake path and the direct path stay visually aligned. The procedural draw pass still renders filled crown facets, pavilion extinction overlay, silhouette outline, and internal edge lines. Pavilion overlays are derived from per-cut metadata on `GemCutResource`, and `extinction` controls only overlay strength rather than also darkening crown facets. If no gem visual can be resolved, the remaining fallback is a coloured debug rectangle. Silhouette outlines are toggled via `DebugFlags.gem_silhouette_outline`.

## Gem Designer

The Gem Designer (`scenes/design/gem_design.tscn`) is an interactive tool for designing gem visual configurations with real-time preview. It provides:

- **Cut profile dropdown** — all 23 available cuts
- **Preset loader** — load any of the 8 built-in gem configurations as a starting point
- **Full parameter control** — colour pickers (base, depth tint, rim, translucency, gradient, edge, outline), sliders for all material properties (shininess, specular, contrast, saturation, dispersion, transparency, rim power, translucency, secondary specular, sparkle, brilliance, extinction)
- **Live preview** — 400x400 rendered gem updates in real-time as parameters change
- **Export** — copy the designed configuration to clipboard as a ready-to-save `.tres` file or as JSON

## Playing

Open in Godot 4.6 and run the project. The main menu provides navigation to Play (starts a run) or the Gem Designer. Click a tile to select it (yellow highlight), then click an adjacent tile to swap. Drag between adjacent tiles also works. Valid swaps trigger the full merge cascade with animations. Invalid swaps bounce back.

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
- **Procedural visuals:** Gem rendering is fully data-driven — cut geometry is generated parametrically, shading computed from pseudo-3D normals. No hand-authored sprites needed. Adding a new gem visual is adding a `.tres` config file.

## Documentation

- [AGENTS.md](AGENTS.md) — Full architectural reference for AI agents and contributors
- [core/visuals/README.md](core/visuals/README.md) — Procedural cut-system architecture and extension guide
- [Gem Engine Proposal](plans/gem-engine-proposal.md) — Game design and architecture proposal
- [Executive Analysis](plans/executive-analysis.md) — Proposal review and scaffolding audit
- [Getting Started Guide](plans/getting-started-guide.md) — Godot overview and phased prototyping plan
- [Deferred Systems Reference](plans/deferred-systems-reference.md) — Systems designed but deferred to later phases
