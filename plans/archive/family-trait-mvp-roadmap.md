# Facets: Family-Trait MVP Roadmap

Linked direction document: [Family-Trait Roguelike Proposal](family-trait-roguelike-proposal.md)

## Purpose

This document translates the higher-level family-trait proposal into a concrete MVP roadmap for the current repository.

It is meant to answer:

1. What is the smallest real version of this direction that is worth building?
2. In what order should systems be added?
3. Where should each system live in the current repo so future expansion remains clean?
4. What should explicitly wait until later?

This roadmap assumes the current project state is:

- deterministic turn simulation is already working
- swap input and authoritative timeline playback already exist
- the board already supports blocked cells, custom gravity, spawn entries, and portals
- the repo already has `TileRegistry`, `SpawnTableResource`, `BoardLayoutResource`, and a strong simulation/render split

---

## MVP Definition

The MVP for this direction is **not** "all families, all hazards, all room types."

The MVP is:

> A short, replayable, move-limited run where the player drafts toward a small family build, clears a handful of tagged rooms with clear objectives and hazards, and wins by forging and extracting a flagship gem.

### MVP success criteria

The MVP should support all of the following in one coherent slice:

- a full playable run of **5-6 rooms**
- **visible room choice** between at least 2 options on some steps
- **3 room objective archetypes**
- **3 hazard packages**
- **4 families or family packages** with clearly different roles
- **1 trait system** that drives gem behavior through event triggers
- **1 reward layer** between rooms that shapes the build
- a clear **run win condition** and **run fail condition**

### Recommended MVP content target

| Category | MVP target |
|---|---|
| **Neutral ladder** | Keep the existing 8-tier ladder as the backbone |
| **Family packages** | Quartz, Beryl, Chalcedony, Tourmaline |
| **Room archetypes** | Socket, Purify, Escort |
| **Hazards** | Obsidian blocker, Cinnabar spread, Locked seal |
| **Reward classes** | Family package, Setting, Treatment, one light-risk Inclusion |
| **Route structure** | Simple branching path with visible room tags |
| **Win condition** | Forge and extract a contract gem in the crown room |

### Explicit non-goals for the MVP

Do not treat these as MVP requirements:

- full T0 roster
- full T9 artifact system
- complete boon taxonomy
- more than one topology gimmick in the same room
- full modifier pipeline abstraction
- full procedural route graph generation
- many alternate gems per tier

---

## Core Build Principles

These are the compatibility rules that should govern implementation in this repo.

### 1. Do not break simulation/render separation

All real game rules remain in `core/`.

- `scenes/` can present room tags, objective progress, and rewards
- `scenes/` must not decide trait outcomes, objective completion, or hazard logic
- the board renderer should continue to consume authoritative resolved state and timeline events

### 2. Reuse existing data systems before inventing parallel ones

The repo already has:

- `TileDefinitionResource`
- `SpawnTableResource`
- `BoardLayoutResource`
- `TileRegistry`
- `RunController`
- `TurnController`
- `EventTimeline`

Build on top of those first.

Examples:

- room layouts should use `BoardLayoutResource`, not a second layout format
- room spawn rules should use `SpawnTableResource`, not a room-local random script
- tile behaviors should extend tile definitions, not be hardcoded in scene scripts

### 3. Keep deterministic replay intact

Any new system added for the MVP must be seed-safe.

That means:

- all room generation goes through `SeededRng`
- all trait-triggered random choices go through `SeededRng`
- room selection must be recorded in `ReplayService`
- run state additions must be serializable through `RunState.to_dict()`

### 4. Add systems in the narrowest useful form first

The repo should prefer:

- one concrete `TraitResolver` over a speculative universal modifier engine
- one concrete `RoomDefinitionResource` over a giant taxonomy of unfinished resources
- one simple route generator over a full campaign graph system

The shape of later abstractions should come from 2-3 working examples, not from theory.

### 5. Preserve existing board contracts

Do not violate the existing architecture rules:

- no `board_changed` emission during swaps/cascades
- no raw randomness outside `SeededRng`
- no direct adjacency math bypassing `get_neighbor()`
- no hardcoded gravity bypassing `get_effective_gravity()`

---

## Recommended New Systems

The MVP can fit cleanly into the current repo with six focused additions.

### 1. Trait definitions

Purpose:

- define event-triggered gem behaviors in data

Recommended files:

- `resources/definitions/trait_definition_resource.gd`
- `data/traits/`
- `autoloads/trait_registry.gd`

Recommended minimal schema:

| Field | Purpose |
|---|---|
| `trait_id` | stable lookup id |
| `display_name` | UI/debug name |
| `trigger` | event window name |
| `effect_type` | what kind of effect it emits |
| `parameters` | effect payload |
| `targeting` | self, adjacent, room objective, random family tile, etc. |

Repository-fit recommendation:

- keep trait data separate from tile definitions
- store only `trait_ids` on tiles
- resolve trait behavior through a registry lookup, not large per-tile switches

### 2. Trait resolution service

Purpose:

- collect tile and room trigger responses after the base effect plan is created

Recommended file:

- `core/rules/trait_resolver.gd`

Why `core/rules/`:

- traits are rule logic, not board storage
- they operate on events and emit additional atomic effects
- they should sit close to `EventLog`, `EventTimeline`, and future room/boon rule logic

Recommended integration point:

Inside `TurnController.step_cascade()`:

1. detect and classify matches
2. build base merge plan via `EffectPlanner`
3. ask `TraitResolver` for triggered effect entries
4. merge those entries into the effect plan
5. conflict-resolve once
6. apply once

Important:

- keep `EffectPlanner` responsible for base match semantics
- keep `TraitResolver` responsible for triggered reactions
- do not fuse them into one giant planner too early

### 3. Room definitions

Purpose:

- define one encounter's objective, hazard, layout, spawn rules, and reward tags

Recommended files:

- `resources/definitions/room_definition_resource.gd`
- `data/rooms/`

Recommended minimal schema:

| Field | Purpose |
|---|---|
| `room_id` | stable id |
| `display_name` | UI name |
| `objective_type` | `socket`, `purify`, `escort`, etc. |
| `hazard_type` | `obsidian`, `cinnabar`, `sealed`, etc. |
| `board_layout` | reuse `BoardLayoutResource` |
| `spawn_table` | optional room-specific spawn table |
| `reward_tags` | what kind of reward the room tends to offer |
| `parameters` | room-specific numbers like target count, spread timer, extraction cell |

Scalability note:

For the MVP, keep objective and hazard data inside one room definition resource. Split them into their own resources later only if the combinations become too repetitive or too large.

### 4. Room runtime state

Purpose:

- track the live progress of the active encounter

Recommended file:

- `core/run/room_state.gd`

Recommended responsibilities:

- active room definition
- objective progress counters
- hazard timers/meters
- extraction target state
- completion / failure flags

Recommended `RunState` additions:

- `current_room: RoomState`
- `remaining_rooms: Array`
- `upcoming_room_offers: Array`
- `active_reward_choices: Array`
- `active_family_packages: Array[StringName]`

Important:

- `RunState` owns room progression
- `BoardState` remains board-only

### 5. Route generation

Purpose:

- present small room choice sets and record route progression

Recommended files:

- `core/run/route_generator.gd`
- optionally `core/run/room_offer.gd` if a typed runtime object becomes useful

Recommended MVP shape:

- generate 2-3 room offers at a time
- each room shows `objective`, `pressure`, and `reward` tags
- the player selects one
- the remaining offers are discarded or partially rolled forward

This is enough for agency without requiring a huge graph UI.

### 6. Reward resolution

Purpose:

- give the player build-shaping choices after rooms

Recommended MVP approach:

- do **not** build a universal reward economy first
- use a small `RewardChoice` dictionary schema owned by `RunController`

When it becomes stable, graduate it into:

- `resources/definitions/reward_definition_resource.gd`
- `data/rewards/`

This is a good example of where the repo should avoid over-abstraction too early.

---

## Recommended Repo Changes

### New files to add in the MVP window

```text
res://
  core/
    run/
      room_state.gd
      route_generator.gd
    rules/
      trait_resolver.gd
  resources/
    definitions/
      trait_definition_resource.gd
      room_definition_resource.gd
  autoloads/
    trait_registry.gd
  data/
    traits/
    rooms/
```

### Existing files most likely to change

| File | Why it changes |
|---|---|
| `resources/definitions/tile_definition_resource.gd` | add `trait_ids` export if not already present |
| `core/run/run_state.gd` | add room/build progression state |
| `core/run/run_controller.gd` | manage room start/end, route choices, rewards |
| `core/run/turn_controller.gd` | call `TraitResolver` at the correct point |
| `core/board/effect_planner.gd` | remain base-plan-only; maybe add a public plan merge helper if useful |
| `core/board/effect_resolver.gd` | support new atomic effects once validated |
| `scenes/run/run_scene.gd` | show room tags, room progress, reward choice UI hooks |
| `scenes/debug/debug_panel.gd` | debug controls for room and trait testing |
| `autoloads/replay_service.gd` | record room choice and reward choice actions |

### Existing files that should usually not become dumping grounds

Avoid piling unrelated logic into:

- `run_scene.gd`
- `board_scene.gd`
- `debug_flags.gd`
- `effect_planner.gd`

Those files are easy places to create accidental coupling if the MVP is rushed.

---

## Phase Ordering

This ordering is designed for the current repo, not for a blank-slate project.

### Phase 0: Stabilize the current baseline

Goal:

- confirm the current swap-playable slice is the base for all further work

Tasks:

- verify run start, swap flow, invalid swap feedback, and cascade playback are stable
- make sure `RunScene` can display a simple run-over and run-win state
- add a deterministic debug way to start runs with a chosen seed and selected board layout

Repo focus:

- `scenes/run/run_scene.gd`
- `scenes/debug/debug_panel.gd`
- `core/run/run_controller.gd`

Exit criteria:

- a tester can repeatedly play turns from deterministic seeds
- runs can end cleanly
- debug tools can inject seed/layout variants

Why this phase first:

Every later system sits on top of this experience.

### Phase 1: Add trait scaffolding to the neutral ladder

Goal:

- prove that event-triggered gem behavior fits the current turn pipeline

Tasks:

- add `TraitDefinitionResource`
- add `TraitRegistry`
- add `TraitResolver`
- add `trait_ids` to tiles
- create 4-6 simple traits on existing neutral ladder gems

Recommended starter trait set:

- Quartz: `on_match` -> minor stabilize or same-family shard
- Topaz: `on_match_4` -> directional clear
- Sapphire: `on_match_5_line` -> charge or room progress
- Emerald: `on_upgrade` -> local convert
- Ruby: `on_destroy` -> burst effect
- Diamond: `on_match` or `on_upgrade` -> extraction assist or wildcard burst

Repo focus:

- `resources/definitions/tile_definition_resource.gd`
- `resources/definitions/trait_definition_resource.gd`
- `autoloads/trait_registry.gd`
- `core/rules/trait_resolver.gd`
- `core/run/turn_controller.gd`
- `data/traits/`

Exit criteria:

- at least two trigger windows work deterministically
- triggered effects appear in the same authoritative resolution flow as base effects
- tests cover triggered effect generation and replay stability

Important restraint:

Do not add boons, room logic, and cursed gems at the same time as the first trait implementation.

### Phase 2: Add room objectives without route choice

Goal:

- prove that board objectives can define encounter success beyond generic survival

Tasks:

- add `RoomDefinitionResource`
- add `RoomState`
- extend `RunState` and `RunController` to own a current room
- implement one room objective first, then expand to three

Recommended order:

1. `Socket`
2. `Purify`
3. `Escort`

Repo focus:

- `resources/definitions/room_definition_resource.gd`
- `core/run/room_state.gd`
- `core/run/run_state.gd`
- `core/run/run_controller.gd`
- `scenes/run/run_scene.gd`
- `data/rooms/`

Exit criteria:

- room completion can succeed even before moves hit zero
- room failure can end the run or advance to fail handling
- room progress is visible in UI and testable headlessly

Important compatibility recommendation:

Room win-condition checks should live in `RunController` or a small helper service, not in board scene code.

### Phase 3: Add four family packages

Goal:

- move from "traited neutral ladder" to actual build shaping

Tasks:

- create 1-2 alternate gems per chosen family
- assign one primary trait to each
- support in-family upgrade when present, neutral fallback when not
- allow the run to activate a family package for the current run pool

Recommended families:

- Quartz
- Beryl
- Chalcedony
- Tourmaline

Repo focus:

- `data/tiles/`
- `data/traits/`
- `autoloads/tile_registry.gd`
- `core/run/run_controller.gd`
- `core/run/run_state.gd`

Exit criteria:

- two runs with different chosen family packages feel mechanically different
- family tiles can be drafted into the pool without special-case code in scenes
- merge paths remain deterministic and data-driven

Important restraint:

Do not attempt to fully support all eight proposed families here.

### Phase 4: Add hazards and post-room rewards

Goal:

- make rooms ask different tactical questions and let the run bend in response

Tasks:

- implement three hazard packages:
  - Obsidian blocker
  - Cinnabar spread
  - Locked seal
- implement one reward choice screen after room completion
- support reward categories:
  - family package
  - setting
  - treatment
  - one mild inclusion

Repo focus:

- `core/run/run_controller.gd`
- `core/run/room_state.gd`
- `core/rules/trait_resolver.gd`
- `core/board/effect_resolver.gd` as needed for validated new effects
- `scenes/run/`

Exit criteria:

- at least one hazard strongly favors one family over another
- rewards change how later rooms are approached
- a short run has an identifiable build arc

Important compatibility recommendation:

If a hazard can be expressed as a tile or cell rule, prefer that over a scene-only overlay mechanic.

### Phase 5: Add room routing

Goal:

- let players choose encounters that suit their build

Tasks:

- add `RouteGenerator`
- generate 2-3 tagged room offers
- add room-choice UI
- record room selections in replay
- optionally add one route-control mechanic:
  - reveal one future room
  - reroll one room offer

Repo focus:

- `core/run/route_generator.gd`
- `core/run/run_state.gd`
- `core/run/run_controller.gd`
- `scenes/run/run_scene.gd`
- `autoloads/replay_service.gd`

Exit criteria:

- players can intentionally choose rooms that suit their current family package
- route choice is visible and understandable
- replay and saves remain stable with room selections included

At this point, the game has a real roguelike backbone.

### Phase 6: Topology and post-MVP scale

Goal:

- increase room identity using systems already present in the board model

Recommended order:

1. blocked-cell layouts
2. spawn-entry or lane-shaped layouts
3. portals
4. gravity-direction rooms

Why this order:

- blocked cells are easiest for players to read
- portals and gravity redirection are powerful, but should arrive after room goals are already intuitive

This phase is best treated as post-MVP.

---

## Testing Requirements By Phase

The repo is already built for headless simulation testing. Use that advantage.

### Phase 1 tests

- triggered effects fire on the right event windows
- triggered effects remain deterministic with the same seed
- trait resolution order is stable

### Phase 2 tests

- objective progress changes correctly from board events
- room completion/failure conditions are deterministic
- room parameters serialize correctly

### Phase 3 tests

- family package activation changes spawn/selection as expected
- family merge fallback works when no in-family target exists

### Phase 4 tests

- hazard timers/spread behavior are deterministic
- reward choices modify later room behavior correctly

### Phase 5 tests

- route generation is deterministic for the same seed
- room choices are replay-safe

Recommended test files:

- `tests/test_traits.gd`
- `tests/test_rooms.gd`
- `tests/test_route_generation.gd`

Keep `tests/test_smoke.gd` as the broad integration suite, but move feature-specific complexity into dedicated tests.

---

## Specific Architectural Recommendations

These recommendations matter for future scalability.

### Recommendation 1: Keep objective logic outside `BoardState`

`BoardState` should stay focused on topology and tile occupancy.

Do:

- keep room objective counters in `RoomState`
- read board events to update objective progress

Do not:

- store room completion state on the board
- make `BoardState` aware of reward logic or route logic

### Recommendation 2: Make traits emit normal effect entries

The best compatibility rule for the repo is:

> traits should create the same atomic effect dictionaries the normal planner already uses.

That means traits inherit:

- conflict resolution
- event logging
- future animation compatibility

### Recommendation 3: Reuse `BoardLayoutResource` aggressively

Do not create a separate "room geometry" format.

Instead:

- let room definitions reference layouts
- add room parameters for objective cells or extraction cells
- keep layout and objective state distinct

### Recommendation 4: Use resource ids for content references

For scalability and serialization:

- room definitions should reference ids or resources
- rewards should store ids
- traits should store ids
- run state should store selected ids

Avoid node references or scene paths in runtime rule state.

### Recommendation 5: Add UI last for each rule

For each new rule system:

1. simulation test
2. debug trigger
3. HUD display
4. polished UI

This keeps the repo honest and minimizes half-working visual systems.

### Recommendation 6: Avoid a generic "everything hooks everything" system too early

The repo should not jump straight to a huge universal modifier framework unless the smaller systems force it.

For the MVP:

- traits can be one resolver
- room objectives can be another
- rewards can be run-state modifications

If those converge later, then formalize the hook system.

---

## Recommended MVP Milestone Sequence

If the team wants a short milestone list instead of full phases, use this:

1. **Playable baseline**
   - stable swap/cascade/run-end flow
2. **Trait proof**
   - neutral ladder gems with event-triggered abilities
3. **Objective proof**
   - one room contract working end to end
4. **Build proof**
   - four family packages produce different runs
5. **Hazard proof**
   - rooms ask different tactical questions
6. **Route proof**
   - the player can intentionally pick rooms that suit their build
7. **MVP complete**
   - 5-6 room run with visible tags, rewards, and flagship extraction

---

## Final Recommendation

The safest scalable path for this repository is:

- keep the board engine authoritative
- add traits as a rule-layer extension to the existing effect pipeline
- add rooms as run-state data, not scene-local logic
- add routing only after room objectives and family packages already matter
- use the repo's existing resource-driven architecture instead of building temporary hardcoded detours

If this roadmap is followed, the project should reach a meaningful MVP without needing to discard the current architecture later.
