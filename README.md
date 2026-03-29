# Facets

A gemstone-themed match-3 merge roguelike built in Godot 4.6 (GDScript). Portrait mobile layout (1080x1920).

Players swap tiles to form matches of 3+. Matched tiles merge into higher-tier gems following the gem ladder (3 Quartz → 1 Amethyst → ... → Diamond). The goal is to forge high-tier gems within a limited number of moves.

## Project Structure

```
autoloads/          # Singletons (GameConfig, DebugFlags, ReplayService, SaveService, TileRegistry)
core/
  board/            # Simulation: board grid, tiles, matching, effects, gravity, spawning
  rules/            # Simulation: SeededRng, EventLog, EventTimeline
  run/              # Simulation: run lifecycle, turn pipeline orchestration
data/
  tiles/            # Tile definition .tres files (8-gem merge ladder)
  spawn_tables/     # SpawnTableResource .tres files
plans/              # Design documents (reference only, not code)
resources/
  definitions/      # Resource class definitions (data schemas)
scenes/
  board/            # Board rendering, animation sequencer, input handling
  main/             # Entry point scene
  run/              # Run gameplay scene (wires simulation to rendering)
  tile/             # Tile visual component
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

## Playing

Open in Godot 4.6 and run the main scene. Click a tile to select it (yellow highlight), then click an adjacent tile to swap. Valid swaps trigger the full merge cascade with animations. Invalid swaps bounce back.

The HUD shows remaining moves and the current seed.

## Running Tests

```bash
godot --headless --script tests/test_smoke.gd
```

40+ tests cover topology, match detection, merge mechanics, gravity (standard, custom direction, portals, diagonal fill, immovable tiles), the full cascade pipeline, spawn distribution, event timeline structure, and deterministic replay verification.

Cross-platform RNG verification:
```bash
godot --headless --script tests/test_rng_cross_platform.gd
```

## Key Architecture Decisions

- **Simulation-first:** All game logic is in `core/` using `RefCounted` classes with zero scene tree dependency. Runs headlessly.
- **Deterministic replay:** All randomness flows through `SeededRng` using integer-only operations. `BoardState.compute_hash()` provides checkpoint verification.
- **Topology abstraction:** All adjacency uses `BoardState.get_neighbor()` which supports portals. All gravity uses `get_effective_gravity()` which supports per-cell and per-tile overrides.
- **Event-driven rendering:** Simulation produces `EventTimeline`; renderer plays it back via Godot Tweens. The two layers never run simultaneously.

## Documentation

- [AGENTS.md](AGENTS.md) — Full architectural reference for AI agents and contributors
- [Gem Engine Proposal](plans/gem-engine-proposal.md) — Game design and architecture proposal
- [Executive Analysis](plans/executive-analysis.md) — Proposal review and scaffolding audit
- [Getting Started Guide](plans/getting-started-guide.md) — Godot overview and phased prototyping plan
- [Deferred Systems Reference](plans/deferred-systems-reference.md) — Systems designed but deferred to later phases
