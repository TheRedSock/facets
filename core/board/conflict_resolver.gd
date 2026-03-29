class_name ConflictResolver
extends RefCounted


## Resolves conflicts in the effect plan.
## - Deduplicates effects targeting the same cell.
## - Ensures deterministic ordering.
##
## Protection, priority rules, and other conflict resolution logic
## should be added here as those mechanics are designed and prototyped.
func resolve(effect_plan: Array[Dictionary], _board: BoardState) -> Array[Dictionary]:
	var resolved: Array[Dictionary] = []
	var seen_removals: Dictionary = {}  # Vector2i -> true

	for entry in effect_plan:
		var effect: StringName = entry.get("effect", &"")
		var cell: Vector2i = entry.get("cell", Vector2i(-1, -1))

		match effect:
			EffectPlanner.EFFECT_REMOVE:
				# Deduplicate: only remove a cell once
				if seen_removals.has(cell):
					continue
				seen_removals[cell] = true
				resolved.append(entry)

			_:
				# Pass through other effect types
				resolved.append(entry)

	return resolved
