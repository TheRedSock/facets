# Tile Definitions

`TileDefinitionResource` `.tres` files defining each gem in the merge ladder. Loaded automatically by the `TileRegistry` autoload at startup.

## Default 8-Gem Ladder

| tile_id | display_name | tier | debug_color | merge_target_id | .tres file |
|---------|-------------|------|-------------|-----------------|------------|
| quartz | Quartz | 1 | #f8fafc | amethyst | `quartz.tres` |
| amethyst | Amethyst | 2 | #a855f7 | peridot | `amethyst.tres` |
| peridot | Peridot | 3 | #84cc16 | topaz | `peridot.tres` |
| topaz | Topaz | 4 | #f97316 | sapphire | `topaz.tres` |
| sapphire | Sapphire | 5 | #3b82f6 | emerald | `sapphire.tres` |
| emerald | Emerald | 6 | #10b981 | ruby | `emerald.tres` |
| ruby | Ruby | 7 | #ef4444 | diamond | `ruby.tres` |
| diamond | Diamond | 8 | #f0f0ff | *(none)* | `diamond.tres` |

## Merge Chain

Matching 3+ tiles of the same type removes N-1 and upgrades the survivor to `merge_target_id`. The chain runs: Quartz → Amethyst → Peridot → Topaz → Sapphire → Emerald → Ruby → Diamond. Diamond (T8) matches are pure removal (no merge target).

## Adding New Gems

Create a new `.tres` file here with a `TileDefinitionResource`. Set `tile_id`, `tier`, `merge_target_id`, and `debug_color`. The `TileRegistry` will auto-load it. If multiple gems share a tier, `SpawnResolver` picks randomly among them (using `SeededRng`).

The `match_group` field defaults to `tile_id` if left empty. Set it explicitly to make different gem types match with each other (e.g., all gems in a family sharing a match group).
