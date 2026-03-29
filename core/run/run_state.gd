class_name RunState
extends RefCounted

var board: BoardState
var moves_remaining: int = 0
var seed: int = 0
var visible_tiers: int = 4
var board_size: Vector2i = Vector2i.ZERO

## The active spawn table for this run.
var spawn_table: SpawnTableResource = null


func to_dict() -> Dictionary:
	return {
		"moves_remaining": moves_remaining,
		"seed": seed,
		"visible_tiers": visible_tiers,
		"board_size": {
			"x": board_size.x,
			"y": board_size.y,
		},
	}
