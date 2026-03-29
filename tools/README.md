# Tools

Design-time utilities for level authoring and QA. These run headlessly without a scene tree.

## Available

### `board_validator.gd` — Board Layout Validator

Validates `BoardLayoutResource` configurations and reports issues:

- **Gravity cycles** — Cells whose gravity paths loop back to themselves (ERROR)
- **Unreachable cells** — Cells that no spawn entry's gravity lane can reach (WARNING)
- **Orphaned spawn entries** — Spawn entries on blocked cells (ERROR)
- **Contention zones** — Cells where multiple gravity paths converge (WARNING)
- **Portal validation** — Out-of-bounds or blocked portal targets (ERROR)

Usage:
```gdscript
var validator := BoardValidator.new()
var issues := validator.validate(layout)
for issue in issues:
    print(issue)  # "[ERROR] ..." or "[WARNING] ..."
```

## Planned

- `balance_simulator.gd` — Headless simulation for testing spawn distributions and merge reachability across thousands of runs
- `board_inspector.gd` — Editor tool for visualizing board state, gravity lanes, and portal connections
- `replay_player.gd` — Tool for replaying recorded game sessions and verifying determinism
