# Data Directory

This directory holds `.tres` resource files that define game content. Resources are loaded at runtime by autoloads (e.g., `TileRegistry` loads all tile definitions) or referenced directly in run configuration.

## Current Subdirectories

- `tiles/` — `TileDefinitionResource` instances for each gem type (8 gems in the default merge ladder)
- `visuals/` — `GemVisualResource` instances that map tiles to procedural `cut_id`s and material settings
- `spawn_tables/` — `SpawnTableResource` instances for weighted tier distribution (default table is created in code; `.tres` files here override it)

## Adding Content

Create `.tres` files using the Godot editor inspector, or by hand following the resource class schemas in `resources/definitions/`.

- **New gem type:** Create a `.tres` in `data/tiles/` with `TileDefinitionResource`. `TileRegistry` auto-loads it at startup.
- **New gem visual or cut assignment:** Create or edit a `.tres` in `data/visuals/` with `GemVisualResource`. `GemVisualRegistry` loads these and generates the referenced cut profiles at startup.
- **New spawn table:** Create a `.tres` in `data/spawn_tables/` with `SpawnTableResource`. Weights must be `Array[int]` (no floats).
- **Board layouts:** `BoardLayoutResource` defines board shape, gravity, portals, and spawn entries. Can be authored as `.tres` files or built programmatically for procedural generation.

See [plans/deferred-systems-reference.md](../plans/deferred-systems-reference.md) for content directories that will be added in later phases (boons, hazards, floors, effects).
