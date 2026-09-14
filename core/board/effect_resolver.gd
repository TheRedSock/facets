class_name EffectResolver
extends RefCounted

## Per-tile removal events from the last apply() call.
var last_remove_events: Array[Dictionary] = []

## Per-tile upgrade events from the last apply() call.
var last_upgrade_events: Array[Dictionary] = []

var catalog: GameCatalog
var last_error := ""

func _init(admitted_catalog: GameCatalog = null) -> void:
	catalog = admitted_catalog


## Applies the approved effect plan to the board state.
## Emits structured events to the EventLog for animation, debug, and replay.
## Collects per-tile events in last_remove_events / last_upgrade_events
## for EventTimeline consumption.
## Returns the number of tiles removed (useful for cascade/scoring).
func apply(board: BoardState, effect_plan: Array[Dictionary], event_log: EventLog) -> int:
	last_remove_events.clear()
	last_upgrade_events.clear()
	var tiles_removed := 0
	last_error = ""
	if catalog == null:
		last_error = "missing_catalog"
		return -1

	for entry in effect_plan:
		var effect: StringName = entry.get("effect", &"")
		var cell: Vector2i = entry.get("cell", Vector2i(-1, -1))

		match effect:
			EffectPlanner.EFFECT_REMOVE:
				var removed_tile: TileState = board.remove_tile(cell)
				if removed_tile != null:
					tiles_removed += 1
					var event := {
						"type": &"tile_removed",
						"cell": cell,
						"tile_id": removed_tile.tile_id,
						"tier": removed_tile.tier,
						"reason": entry.get("reason", &""),
						"instance_id": removed_tile.instance_id,
						"source": removed_tile.to_dict(),
					}
					last_remove_events.append(event)
					event_log.push(&"tile_removed", {
						"cell_x": cell.x,
						"cell_y": cell.y,
						"tile_id": String(removed_tile.tile_id),
						"tier": removed_tile.tier,
						"reason": String(entry.get("reason", &"")),
					})

			EffectPlanner.EFFECT_UPGRADE:
				var tile: TileState = board.get_tile(cell)
				if tile != null:
					var old_tier := tile.tier
					var old_tile_id := tile.tile_id
					var old_snapshot := tile.to_dict()

					if not catalog.promote(tile):
						last_error = "invalid_promotion"
						return -1

					var event := {
						"type": &"tile_upgraded",
						"cell": cell,
						"tile_id": tile.tile_id,
						"old_tile_id": old_tile_id,
						"old_tier": old_tier,
						"new_tier": tile.tier,
						"instance_id": tile.instance_id,
						"old": old_snapshot,
						"new": tile.to_dict(),
					}
					last_upgrade_events.append(event)
					event_log.push(&"tile_upgraded", {
						"cell_x": cell.x,
						"cell_y": cell.y,
						"tile_id": String(tile.tile_id),
						"old_tile_id": String(old_tile_id),
						"old_tier": old_tier,
						"new_tier": tile.tier,
					})

			_:
				# Log unhandled effects for debugging — new effect types
				# should be added here as mechanics are prototyped.
				event_log.push(&"unhandled_effect", entry)

	return tiles_removed
