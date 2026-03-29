# Facets — Agent Context Reference

Gemstone-themed match-3 merge roguelike built in Godot 4.6 (GDScript). Portrait mobile layout (1080x1920). The player swaps tiles to form matches of 3+; matched tiles merge into higher-tier gems (3 Quartz → 1 Amethyst). The goal is to forge high-tier gems within a limited number of moves across roguelike floor progression.

---

## Critical Architectural Rules

These rules are non-negotiable. Violating them will cause subtle, hard-to-diagnose bugs.

### 1. Simulation and Rendering Are Fully Separated

The simulation layer (`core/`) is pure data — all classes extend `RefCounted`, have zero scene tree dependency, and can run headlessly. The rendering layer (`scenes/`) consumes simulation output but never feeds back into it.

**The communication contract:**
- The simulation runs a complete turn instantly and produces an `EventTimeline` (structured list of what happened: matches, removals, upgrades, gravity moves, spawns).
- The renderer reads the `EventTimeline` and plays it back as animations using Godot Tweens.
- The simulation DOES NOT wait for animations. The board state is already final when the timeline is handed to the renderer.
- `board_changed` signal triggers a full visual rebuild (only on run start / reroll). It must NOT fire after `attempt_swap` — the timeline animation handles the visual transition.

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
resources/      Resource class definitions (data schemas)
data/tiles/     Tile definition .tres files (the 8-gem merge ladder)
autoloads/      Global singletons (config, replay, save, debug, tile registry)
scenes/         Rendering: board display, tile views, animation, input, HUD
tools/          Design-time utilities (board layout validator)
tests/          Headless smoke tests (godot --headless --script tests/test_smoke.gd)
plans/          Design documents (not code — reference only)
```

### Layer Boundaries

| Layer | May depend on | Must NOT depend on |
|---|---|---|
| `core/board/` | Other `core/` classes, `SeededRng` | Scenes, autoloads (except `TileRegistry` in `EffectResolver` for merge chain lookup) |
| `core/run/` | `core/board/`, `core/rules/`, autoloads (`ReplayService`) | Scenes |
| `scenes/` | `core/` (read-only), autoloads | Must not mutate board state directly |
| `autoloads/` | `core/` classes, `resources/` | Scenes |
| `resources/` | Nothing (pure data schemas) | Everything |

The one intentional coupling: `EffectResolver` reads `TileRegistry` (autoload) to resolve merge chains. This is acceptable because the registry is read-only game data. If `TileRegistry` has no definitions loaded, `EffectResolver` falls back to simple `tier += 1`.

---

## Turn Pipeline

When the player swaps two tiles, this exact sequence executes:

```
RunScene._on_swap_requested(cell_a, cell_b)
  → RunController.attempt_swap(cell_a, cell_b)
      1. board.swap_cells(a, b)
      2. match_detector.find_matches(board) — if empty, revert swap, return null
      3. TurnController.execute_turn(board, rng, spawn_table, event_log, [a, b])
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
             h. Collect events into EventTimeline cascade step
                (chain rounds stored in chain_steps[] for sequential animation)
           UNTIL no matches found
      5. Return EventTimeline
      6. Adjust moves based on best match across all cascades + chains:
         — base_match (3): -1 move
         — match_4 (4): free (no cost)
         — match_5_plus / match_lt (5+): +1 move
  → await BoardScene.animate_swap(cell_a, cell_b)   — visual swap
  → await BoardScene.play_timeline(timeline)         — animate cascade
  → Unlock input
```

Key points:
- The simulation completes entirely before any animation starts
- `attempt_swap` does NOT emit `board_changed` — only `run_state_changed`
- `board_changed` only fires from `start_new_run()` and `reroll_board()` (causes full tile rebuild)
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

Each cascade step is animated in 4 sequential phases:
1. **Match highlight** — matched tiles flash bright (`modulate = 1.5`)
2. **Remove + Upgrade** — removed tiles fade/shrink; survivor resets modulate then shows upgrade visual with scale pulse
3. **Gravity** — tiles tween to new positions with `EASE_IN` + `TRANS_QUAD` (accelerating fall). Duration scales with distance: `sqrt(2 * distance / 45.0)`
4. **Spawn** — new tiles fade in and fall from above the board

Each phase awaits its tween's `finished` signal before starting the next. Cascade steps play sequentially with a brief pause between them.

**Swap animations** happen BEFORE the cascade: `animate_swap()` slides the two tiles to each other's positions over 0.15s. Invalid swaps use `animate_invalid_swap()` which slides tiles partway then bounces back.

---

## TileRegistry (Autoload)

Loads all `.tres` tile definitions from `data/tiles/` at startup. Provides:
- `get_definition(tile_id)` → `TileDefinitionResource`
- `get_ids_for_tier(tier)` → `Array[StringName]`
- `create_tile(tile_id)` → `TileState` with all fields populated from definition
- `create_tile_for_tier(tier, rng)` → random tile at that tier
- `get_atlas_region(tier)` → `Rect2` for the gem sprite atlas (2x4 grid, 384x384px cells)
- `has_definitions()` → `bool` (false in headless tests that skip autoloads)

`SpawnResolver` uses `TileRegistry` to create named tiles instead of anonymous debug tiles. `EffectResolver` uses it to resolve merge chains. Both fall back gracefully when the registry is unavailable.

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

40+ tests cover: board creation, topology (neighbors, portals, gravity), match detection (including unmatchable/holes), merge mechanic (remove count, upgrade, max tier), gravity (standard, custom direction, tile override, immovable, iterative convergence, diagonal fill, portals, cycle safety), pipeline (effect planning, conflict resolution, spawning, timeline structure), and deterministic replay verification.

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
