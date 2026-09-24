# Deferred Systems Reference

This document preserves the design thinking for systems that were removed from the scaffolding because they commit to specific design decisions before those decisions have been validated through prototyping. Each section describes what the system was, why it was deferred, and how to re-implement it when the design is ready.

---

## 1. Modifier Pipeline (Hook-Based)

### What it was

A `ModifierPipeline` class that allowed callables to be registered at named hook points in the turn loop. The `TurnController` fired hooks at specific moments, and any registered modifier could transform the data passing through.

### Architecture

```
ModifierPipeline
  _hooks: Dictionary  # StringName -> Array[Callable]
  active_modifier_ids: Array[StringName]

  register_hook(hook_name, callback)
  unregister_all(target)
  fire_hook(hook_name, data) -> Variant    # transforms data through all callbacks
  fire_notification(hook_name)              # fire-and-forget, no data transform
  add_modifier(modifier_id)
  remove_modifier(modifier_id)
```

### Hook points

These were defined in a `RuleHooks` class:

| Hook | When it fires | Data it transforms |
|---|---|---|
| `BEFORE_MATCH_DETECTION` | Before `MatchDetector.find_matches()` | Notification only |
| `AFTER_MATCH_CLASSIFICATION` | After `MatchClassifier.classify()` | `Array[Dictionary]` of classified matches |
| `BEFORE_EFFECT_PLANNING` | Before `EffectPlanner.build_base_plan()` | Notification only |
| `AFTER_EFFECT_PLANNING` | After `EffectPlanner.build_base_plan()` | `Array[Dictionary]` of effect plan entries |
| `BEFORE_SPAWN_RESOLUTION` | Before `SpawnResolver.refill_empty_cells()` | Notification only |
| `END_OF_TURN` | After all cascades resolve | Notification only |
| `START_OF_FLOOR` | When a new floor begins | Notification only |
| `END_OF_FLOOR` | When a floor ends | Notification only |

### Why it was deferred

The hook-based architecture is one possible approach to modifiers, but it assumes:
- Modifiers are best expressed as data-transforming callables
- The specific hook points listed above are the right injection points
- Modifiers need to be registered/unregistered dynamically

Alternative approaches that might work better depending on the final design:
- **Config flags on run state** — simpler, just check `if run_state.has_flag("double_upgrade")`
- **Trait-based system** — modifiers as properties on tiles or the board, checked by the pipeline stages themselves
- **Event-response system** — modifiers react to events after they happen rather than intercepting the pipeline

### How to re-implement

1. Create `core/rules/rule_hooks.gd` with hook point constants
2. Create `core/rules/modifier_pipeline.gd` with the register/fire pattern
3. Add `modifiers.fire_hook()` / `modifiers.fire_notification()` calls at the appropriate points in `TurnController.execute_turn()`
4. Pass the pipeline as a parameter to `execute_turn()` (don't store it as a member)

---

## 2. Floor Progression System

### What it was

A `FloorState` runtime class and `FloorDefinitionResource` data class that modeled per-floor configuration in a roguelike run structure.

### Architecture

```
FloorDefinitionResource (Resource)
  floor_id: StringName
  display_name: String
  board_size: Vector2i = Vector2i(8, 8)
  starting_moves: int = 20
  visible_tiers: int = 4
  spawn_table: SpawnTableResource = null
  floor_modifiers: Array[StringName] = []

FloorState (RefCounted)
  floor_index: int
  moves_budget: int
  spawn_table: SpawnTableResource
  floor_modifiers: Array[StringName]
  definition: FloorDefinitionResource
```

`RunController` managed floor transitions: when moves ran out or a floor goal was met, it would advance to the next floor, load its definition, and reset the board.

### Why it was deferred

The floor-based roguelike structure is one possible run model, but alternatives include:
- **Continuous single-board runs** with escalating spawn pressure
- **Wave-based runs** where new tiles arrive in waves rather than per-floor
- **Objective-based runs** where the board persists but goals change
- **Endless mode** with no floor boundaries

The floor model also assumes specific between-floor mechanics (reward screens, shops, boon selection) that haven't been designed.

### How to re-implement

1. Create `resources/definitions/floor_definition_resource.gd` with per-floor config fields
2. Create `core/run/floor_state.gd` as the runtime companion
3. Add `floor_index` and `current_floor` to `RunState`
4. Add floor transition logic to `RunController` (advance floor, load definition, reset board)
5. Create floor definition `.tres` files in `data/floors/`
6. Build a between-floor scene for reward selection

---

## 3. Boon System

### What it was

A `BoonDefinitionResource` that defined passive bonuses the player could acquire during a run.

### Architecture

```
BoonDefinitionResource (Resource)
  boon_id: StringName
  display_name: String
  description: String
  boon_category: StringName  # "setting" or "treatment" (jewelry-themed)
  rarity: StringName          # common, uncommon, rare, legendary
  parameters: Dictionary
```

The proposal suggested boons would be offered between floors and would register hooks on the modifier pipeline to alter gameplay.

### Why it was deferred

- The boon categorization ("setting" vs "treatment") is a thematic choice that hasn't been validated
- The rarity system assumes a specific economy model
- How boons interact with gameplay (hook-based? flag-based? trait-based?) is unknown
- Whether boons are per-run, per-floor, or stackable is unspecified
- The `parameters` dictionary is a catch-all that defers the real design work

### How to re-implement

1. Design 3-5 concrete boons first (what they do mechanically)
2. Let the implementation of those boons inform the resource schema
3. Create `resources/definitions/boon_definition_resource.gd` based on actual needs
4. Create `.tres` instances in `data/boons/`

---

## 4. Hazard System

### What it was

A `HazardDefinitionResource` that defined board obstacles and threats.

### Architecture

```
HazardDefinitionResource (Resource)
  hazard_id: StringName
  display_name: String
  description: String
  hazard_type: StringName  # blocker, trickster, poison, etc.
  spread_rate: int          # turns between spread events (0 = no spread)
  parameters: Dictionary
```

### Why it was deferred

- T0 hazards might not be tile-based at all — they could be board modifiers, spawn events, or cell effects
- The `hazard_type` enum assumes categories that haven't been designed
- `spread_rate` assumes a specific spreading mechanic
- Whether hazards are spawned, placed, or triggered is unknown

### How to re-implement

1. Design 2-3 concrete hazards first (Obsidian blocker, Pyrite trickster, etc.)
2. Determine if they're tiles, cell effects, or board modifiers
3. Create the resource schema based on actual implementation needs
4. If they're tiles, they may just be `TileDefinitionResource` instances with special flags

---

## 5. Extended Effect Types

### What was removed

The `EffectPlanner` originally defined 9 effect type constants:

```gdscript
const EFFECT_REMOVE := &"remove_tile"
const EFFECT_UPGRADE := &"upgrade_tile"
const EFFECT_DOWNGRADE := &"downgrade_tile"     # removed
const EFFECT_CONVERT := &"convert_tile"          # removed
const EFFECT_SPAWN := &"spawn_tile"              # removed
const EFFECT_MOVE := &"move_tile"                # removed
const EFFECT_PROTECT := &"protect_tile"          # removed
const EFFECT_AWARD_MOVE := &"award_move"         # removed
const EFFECT_APPLY_STATUS := &"apply_status"     # removed
```

The `EffectResolver` had handlers for downgrade, protect, consume_protection, and apply_status.

### Why they were reduced

- `DOWNGRADE` — no mechanic currently uses it
- `CONVERT` — assumes a conversion mechanic that hasn't been designed
- `SPAWN` — effect-triggered spawning is speculative
- `MOVE` — tile movement effects are speculative
- `PROTECT` — protection is a specific mechanic that needs design validation
- `AWARD_MOVE` — assumes moves-as-reward, which depends on the run model
- `APPLY_STATUS` — status flags exist on `TileState` but no statuses are defined

### How to re-add

Each effect type follows the same pattern:

1. Add a constant to `EffectPlanner` (e.g., `const EFFECT_PROTECT := &"protect_tile"`)
2. Generate it in the appropriate planner method (e.g., `_plan_match_4()`)
3. Add a handler case in `EffectResolver.apply()` that mutates the board
4. If it can conflict with other effects, add a rule to `ConflictResolver`
5. Log the event to `EventLog`

---

## 6. Protection Mechanics

### What was removed

The `ConflictResolver` had logic to detect protected tiles and convert `remove` effects into `consume_protection` effects. The `EffectResolver` handled `consume_protection` by setting `tile.protected = false`.

### Architecture

```gdscript
# In ConflictResolver.resolve():
if tile != null and tile.protected:
    resolved.append({
        "effect": &"consume_protection",
        "cell": cell,
        "reason": entry.get("reason", &""),
    })
    seen_removals[key] = true
    continue

# In EffectResolver.apply():
&"consume_protection":
    var tile: TileState = board.get_tile(cell)
    if tile != null:
        tile.protected = false
        event_log.push(&"protection_consumed", { ... })
```

### Why it was deferred

Protection is a specific mechanic that depends on:
- What grants protection (boons? match rewards? special gems?)
- Whether protection is consumed on first hit or has durability
- Whether protection prevents all effects or only removal
- The `DebugFlags.protection_threshold` suggests tier-based auto-protection, which is another unvalidated design choice

### How to re-implement

1. Add protection check back to `ConflictResolver.resolve()` inside the `EFFECT_REMOVE` case
2. Add `consume_protection` handler back to `EffectResolver.apply()`
3. Decide what grants protection and implement that mechanic
4. The `TileState.protected` field is still present — it just isn't checked by the pipeline

---

## 7. Cell Tags

### What was removed

`CellState` had a `tags: Dictionary` field for arbitrary cell-level metadata (ice, lava, conveyor, etc.).

### Why it was deferred

Cell tags assume board topology features that are explicitly deferred in the proposal. The tag system is a generic catch-all that doesn't inform any current mechanic.

### How to re-implement

Add `var tags: Dictionary = {}` back to `CellState` when a specific cell mechanic needs it. Consider whether a more typed approach (e.g., `var ice_layers: int = 0`) would be better than a generic dictionary.

---

## 8. Effect Definition Resource

### What was kept (but noted)

`EffectDefinitionResource` remains in the scaffold but the `data/effects/` directory was removed. The resource class is minimal:

```gdscript
class_name EffectDefinitionResource
extends Resource

@export var effect_id: StringName
@export var display_name: String = ""
@export var effect_type: StringName = &"noop"
@export var parameters: Dictionary = {}
```

This is kept because data-driven effects are a likely future need, but no `.tres` instances should be created until the effect system is actually data-driven rather than code-driven.
