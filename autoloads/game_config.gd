extends Node

const DEFAULT_BOARD_SIZE := Vector2i(8, 8)
const DEFAULT_VISIBLE_TIERS := 4
const DEFAULT_STARTING_MOVES := 20
const DEFAULT_SEED := 1001
const DEFAULT_CELL_SIZE := Vector2i(112, 112)


func default_run_config() -> Dictionary:
	return {
		"board_size": DEFAULT_BOARD_SIZE,
		"visible_tiers": DEFAULT_VISIBLE_TIERS,
		"starting_moves": DEFAULT_STARTING_MOVES,
		"seed": DEFAULT_SEED,
		"cell_size": DEFAULT_CELL_SIZE,
	}
