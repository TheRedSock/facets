class_name EffectPlanner
extends RefCounted

## Effect type constants for the atomic effect system.
## Add new effect types here as mechanics are prototyped and validated.
const EFFECT_REMOVE := &"remove_tile"
const EFFECT_UPGRADE := &"upgrade_tile"

## Maximum tier for standard gems. Matches at this tier remove all tiles
## (nothing to upgrade to). Can be overridden for special content.
const MAX_STANDARD_TIER := 8


## Generates an effect plan from classified matches.
## Each match produces a set of atomic effects (remove tiles, upgrade survivor).
## The plan is a flat array of effect dictionaries, not yet applied.
##
## swap_cells: optional pair of cells involved in a player swap [from, to].
## When provided, the survivor of each match prefers the swap cell that
## participates in that match (destination first). Only pass this for the
## first cascade step; subsequent cascades use the default (empty array).
func build_base_plan(matches: Array[Dictionary], swap_cells: Array[Vector2i] = []) -> Array[Dictionary]:
	var plan: Array[Dictionary] = []

	for match_data in matches:
		var semantic_type: StringName = match_data.get("semantic_type", &"base_match")
		var cells: Array = match_data.get("cells", [])
		var tier: int = match_data.get("tier", 0)

		match semantic_type:
			&"base_match":
				_plan_base_match(plan, cells, tier, swap_cells)
			&"match_4":
				_plan_match_4(plan, cells, tier, swap_cells)
			&"match_5_plus":
				_plan_match_5_plus(plan, cells, tier, swap_cells)
			&"match_lt":
				_plan_match_lt(plan, cells, tier, swap_cells)
			_:
				_plan_base_match(plan, cells, tier, swap_cells)

	return plan


## Base 3-match: merge mechanic — remove all except the survivor, upgrade the survivor.
## For max-tier matches, all tiles are removed (nothing to merge into).
func _plan_base_match(plan: Array[Dictionary], cells: Array, tier: int, swap_cells: Array[Vector2i] = []) -> void:
	_plan_merge(plan, cells, tier, &"base_match", swap_cells)


## 4-match: same merge behavior for now.
## TODO: This is the key design fork — destructive vs merge-forward.
## Could produce +2 tier upgrade, catalyst tile, or line clear.
func _plan_match_4(plan: Array[Dictionary], cells: Array, tier: int, swap_cells: Array[Vector2i] = []) -> void:
	_plan_merge(plan, cells, tier, &"match_4", swap_cells)


## 5+ match: same merge behavior for now.
## TODO: This is the key design fork — destructive vs merge-forward.
func _plan_match_5_plus(plan: Array[Dictionary], cells: Array, tier: int, swap_cells: Array[Vector2i] = []) -> void:
	_plan_merge(plan, cells, tier, &"match_5_plus", swap_cells)


## L/T match: same merge behavior for now.
## TODO: This is the key design fork — destructive vs merge-forward.
func _plan_match_lt(plan: Array[Dictionary], cells: Array, tier: int, swap_cells: Array[Vector2i] = []) -> void:
	_plan_merge(plan, cells, tier, &"match_lt", swap_cells)


## Core merge logic: remove all tiles except the survivor, upgrade the survivor.
## Survivor selection priority:
##   1. If swap_cells is provided ([from, to]), prefer the destination cell (to),
##      then the origin cell (from), if either participates in this match.
##   2. Otherwise, fall back to the last cell in the array (bottom-right bias).
## If the tier is at max, all tiles are removed (nothing to merge into).
func _plan_merge(plan: Array[Dictionary], cells: Array, tier: int, reason: StringName, swap_cells: Array[Vector2i] = []) -> void:
	if cells.is_empty():
		return

	# At max tier, pure removal (nothing to merge into)
	if tier >= MAX_STANDARD_TIER:
		for cell in cells:
			plan.append({
				"effect": EFFECT_REMOVE,
				"cell": cell,
				"reason": reason,
			})
		return

	# Pick the survivor: prefer a swap cell if one participates in this match,
	# destination (index 1) before origin (index 0). Fall back to bottom-right.
	var survivor_cell: Vector2i = cells[cells.size() - 1]
	if swap_cells.size() == 2:
		# Check destination first, then origin
		if swap_cells[1] in cells:
			survivor_cell = swap_cells[1]
		elif swap_cells[0] in cells:
			survivor_cell = swap_cells[0]

	# Remove all cells except the survivor
	for cell in cells:
		if cell != survivor_cell:
			plan.append({
				"effect": EFFECT_REMOVE,
				"cell": cell,
				"reason": reason,
			})

	# Upgrade the survivor
	plan.append({
		"effect": EFFECT_UPGRADE,
		"cell": survivor_cell,
		"reason": reason,
	})
