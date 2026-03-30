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
  main/             # Entry point scene
  run/              # Run gameplay scene (wires simulation to rendering)
  tile/             # Tile visual component (procedural gem drawing via _draw())
  debug/            # Debug panel (F1 toggle, animation tuning sliders)
  ui/               # Debug overlay (currently unused in main scene)
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

The simulation completes instantly and produces an `EventTimeline`. The renderer plays it back as animations. See `AGENTS.md` for the full architectural reference.

## Procedural Gem Rendering

Gems are rendered procedurally — there is no sprite atlas fallback in the main render path. Each gem type is defined by:

- **`GemCutResource`** — 2D polygon geometry defining the facet layout (generated at startup from profile-driven cut builders)
- **`GemVisualResource`** (`.tres` in `data/visuals/`) — Per-gem colour, material properties (shininess, contrast, specular intensity, depth tint, hue dispersion)
- **`GemRenderer`** — Pure-math lighting: Half-Lambert/Lambert diffuse blend, Blinn-Phong specular, per-facet brightness jitter, prismatic hue dispersion
- **`core/visuals/gem_cut_profiles.gd`** — declarative cut library
- **`core/visuals/gem_cut_builders.gd`** — reusable facet topology builders
- **`core/visuals/gem_cut_primitives.gd`** — shared outline math and curve sampling helpers

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

Higher tiers have progressively more dramatic shading, brighter specular highlights, and deeper depth tints. Diamond features prismatic hue dispersion ("fire").

`TileView._draw()` renders gems directly using Godot's `draw_colored_polygon()`. If no procedural visual can be resolved, the remaining fallback is a coloured debug rectangle. Silhouette outlines are toggled via `DebugFlags.gem_silhouette_outline`.

## Playing

Open in Godot 4.6 and run the main scene. Click a tile to select it (yellow highlight), then click an adjacent tile to swap. Drag between adjacent tiles also works. Valid swaps trigger the full merge cascade with animations. Invalid swaps bounce back.

The HUD shows remaining moves and the current seed.

## Running Tests

```bash
godot --headless --script tests/test_smoke.gd
```

Focused cut regression coverage:

```bash
godot --headless --script tests/test_gem_cuts.gd
```

The test suites cover topology, match detection, merge mechanics, gravity, the full cascade pipeline, deterministic replay verification, cut generation, normalized geometry bounds, facet counts, and silhouette stability.

Cross-platform RNG verification:
```bash
godot --headless --script tests/test_rng_cross_platform.gd
```

## Key Architecture Decisions

- **Simulation-first:** All game logic is in `core/` using `RefCounted` classes with zero scene tree dependency. Runs headlessly.
- **Deterministic replay:** All randomness flows through `SeededRng` using integer-only operations. `BoardState.compute_hash()` provides checkpoint verification.
- **Topology abstraction:** All adjacency uses `BoardState.get_neighbor()` which supports portals. All gravity uses `get_effective_gravity()` which supports per-cell and per-tile overrides.
- **Event-driven rendering:** Simulation produces `EventTimeline`; renderer plays it back via Godot Tweens. The two layers never run simultaneously.
- **Procedural visuals:** Gem rendering is fully data-driven — cut geometry is generated parametrically, shading computed from pseudo-3D normals. No hand-authored sprites needed. Adding a new gem visual is adding a `.tres` config file.

## Documentation

- [AGENTS.md](AGENTS.md) — Full architectural reference for AI agents and contributors
- [core/visuals/README.md](core/visuals/README.md) — Procedural cut-system architecture and extension guide
- [Gem Engine Proposal](plans/gem-engine-proposal.md) — Game design and architecture proposal
- [Executive Analysis](plans/executive-analysis.md) — Proposal review and scaffolding audit
- [Getting Started Guide](plans/getting-started-guide.md) — Godot overview and phased prototyping plan
- [Deferred Systems Reference](plans/deferred-systems-reference.md) — Systems designed but deferred to later phases
