# Facets

A gemstone-themed match-3 merge roguelike built in Godot 4.6 (GDScript). Landscape desktop layout (1920x1080), with future portrait mobile pivot planned.

Players swap tiles to form matches of 3+. Matched tiles merge into higher-tier gems following the gem ladder (3 Quartz → 1 Amethyst → ... → Diamond). The goal is to forge high-tier gems within a limited number of moves.

## Project Structure

```
autoloads/          # Singletons (GameConfig, DebugFlags, ReplayService, SaveService, TileRegistry, GemForge)
core/
  board/            # Simulation: board grid, tiles, matching, effects, gravity, spawning
  rules/            # Simulation: SeededRng, EventLog, EventTimeline
  run/              # Simulation: run lifecycle, turn pipeline orchestration
  lapidary/         # GPU gem pipeline (CPU side): stone compiler, cut language, lighting, clips, eval
    tracer/         # GPU tracer host + GLSL compute shaders (spectral path trace, print pass)
data/
  tiles/            # Tile definition .tres files (two 8-gem merge ladders)
  lapidary/         # Authored gem data: species, chromophores, grades, stones, cuts, clips, rigs
  spawn_tables/     # SpawnTableResource .tres files
plans/              # Design documents (reference only, not code)
docs/               # Architecture docs (lapidary-architecture.md is the pipeline authority)
resources/
  definitions/      # Resource class definitions (simulation data schemas)
  lapidary/         # Resource class definitions (GemSpecies, GemChromophore, GemStone, GemClip, ...)
scenes/
  board/            # Board rendering, animation sequencer, input handling
  menu/             # Main menu (Play + Gem Atelier navigation)
  design/           # Gem Atelier (progressive GPU preview + clip scrubbing)
  main/             # Run entry point scene (hosts RunScene)
  run/              # Run gameplay scene (wires simulation to rendering)
  tile/             # Tile visuals (GemForge clips + placeholder fallback)
  debug/            # Debug panel (F1 toggle, animation tuning sliders)
tests/              # Headless tests (simulation + lapidary CPU layers)
tools/              # Board validator, data generator, GPU render checks, eval sheets
artifacts/          # Rendered evaluation output (not shipped)
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

## Gem Rendering (Lapidary Pipeline)

Gems are rendered by a GPU spectral path tracer — a GLSL compute shader on Godot's `RenderingDevice`. There is no CPU tracer, no denoiser, and no hand-authored sprite atlas. Full design: [docs/lapidary-architecture.md](docs/lapidary-architecture.md).

- A stone is a **convex plane set** compiled from a cut template + tier silhouette — exact, watertight, no meshes, no BVH.
- Materials are **spectral**: 3-term Sellmeier IOR per species, 81-sample absorption curves per chromophore, Beer-Lambert body colour at the stone's physical size, birefringence, dispersion, fluorescence.
- Quality flaws are **honest**: grade axes (cut/clarity/surface/crystal) drive facet-meeting jitter, analytic inclusions from the species' vocabulary, wear scratches, and scatter — rendered, not composited.
- Lighting is a **language**: `GemLightRig` resources; grade is never faked with lighting.
- Output goes through a versioned **house print** (spectral → XYZ → linear sRGB → house tonescale → sRGB8), identical for baked clips and live draws.

Authoring is layered — a shipping stone touches a handful of fields:

```
GemSpecies      lattice physics of the mineral    data/lapidary/species/
GemChromophore  why ruby ≠ sapphire               data/lapidary/chromophores/
GemCutTemplate  facet program in the cut language data/lapidary/cuts/
GemGrade        4 quality axes per tier           data/lapidary/grades/
GemStone        the instance a tile references    data/lapidary/stones/   (stone_id == tile_id)
```

Two 8-gem merge ladders ship, sharing per-tier silhouettes, grades, and sizes:

| Tier | Silhouette | Main ladder | Alternate ladder |
|------|-----------|-------------|------------------|
| T1 | Round | Quartz | Fluorite |
| T2 | Square | Amethyst | Smoky Quartz |
| T3 | Triangle | Peridot | Tourmaline |
| T4 | Oval | Topaz | Rhodolite |
| T5 | Diamond ◆ | Sapphire | Aquamarine |
| T6 | Rectangle | Emerald | Alexandrite |
| T7 | Marquise | Ruby | Painite |
| T8 | Pear | Diamond | Blue Garnet |

All cuts are brilliant except the T6 rectangle tier, which carries the step cut. Every run seeds one gem per tier (`tier_tile_ids`), so boards mix the ladders across runs.

## Clips and GemForge

Board tiles play **authored clips** — named, versioned animations (idle, turn, flash) with lighting-relative motion — baked by the same kernel that powers live previews. The `GemForge` autoload is the launcher: it serves cached clips, bakes missing manifest entries incrementally in the background (never a whole clip in one frame), and covers the cold gap with a synchronous placeholder still. The delivery catalog lives in `data/lapidary/manifest.json`; idles for the run's tile set are `required_now`, presentation clips follow.

Live 3D on the board remains a packaging switch on the same compiled stone instance; the sprite-vs-live decision is held by measured numbers (`tools/board_grid_check.gd`).

## Gem Atelier

The Gem Atelier (`scenes/design/gem_atelier.tscn`, reachable from the main menu) is the design surface: pick any stone, watch a progressive GPU preview converge, scrub authored clips frame by frame, and compare lighting rigs.

## Playing

Open in Godot 4.6 and run the project. The main menu provides navigation to Play (starts a run) or the Gem Atelier. Click a tile to select it (yellow highlight), then click an adjacent tile to swap. Drag between adjacent tiles also works. Valid swaps trigger the full merge cascade with animations. Invalid swaps bounce back.

The HUD shows remaining moves and the current seed.

## Running Tests

Headless (simulation + lapidary CPU layers):

```bash
godot --headless --script tests/test_smoke.gd
godot --headless --script tests/test_rng_cross_platform.gd
godot --headless --script tests/lapidary/test_cut_compiler.gd
godot --headless --script tests/lapidary/test_species_data.gd
godot --headless --script tests/lapidary/test_clips.gd
godot --headless --script tests/lapidary/test_board_consumer.gd
```

GPU render checks run windowed (no `--headless`; `RenderingDevice` requires a window):

```bash
godot --path . --script res://tools/ladder_check.gd        # both ladders, one dispatch
godot --path . --script res://tools/kernel_v1_check.gd     # kernel feature renders
godot --path . res://tools/board_visual_check.tscn         # live board smoke check
```

Optional long-run balance harness:

```bash
godot --headless res://tests/test_simulation.tscn
```

## Key Architecture Decisions

- **Simulation-first:** All game logic is in `core/` using `RefCounted` classes with zero scene tree dependency. Runs headlessly.
- **Deterministic replay:** All randomness flows through `SeededRng` using integer-only operations. `BoardState.compute_hash()` provides checkpoint verification.
- **Topology abstraction:** All adjacency uses `BoardState.get_neighbor()` which supports portals. All gravity uses `get_effective_gravity()` which supports per-cell and per-tile overrides.
- **Event-driven rendering:** Simulation produces an authoritative `EventTimeline`; renderer plays it back via Godot Tweens and may overlap independent visual groups without re-running simulation.
- **Physics-first visuals:** Gems are spectral renders of real mineral data (published Sellmeier fits, absorption curves, inclusion vocabularies) — appearance emerges from physics plus grade, not per-gem art tuning.

## Documentation

- [AGENTS.md](AGENTS.md) — Full architectural reference for AI agents and contributors
- [Lapidary Architecture](docs/lapidary-architecture.md) — GPU gem pipeline design and decisions
- [Kernel Contract](core/lapidary/tracer/KERNEL_CONTRACT.md) — GPU buffer formats
- [Gem Engine Proposal](plans/gem-engine-proposal.md) — Game design and architecture proposal
- [Executive Analysis](plans/executive-analysis.md) — Proposal review and scaffolding audit
- [Getting Started Guide](plans/getting-started-guide.md) — Godot overview and phased prototyping plan
- [Deferred Systems Reference](plans/deferred-systems-reference.md) — Systems designed but deferred to later phases
