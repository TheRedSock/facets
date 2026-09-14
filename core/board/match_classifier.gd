class_name MatchClassifier
extends RefCounted

func classify(matches: Array[Dictionary]) -> Array[Dictionary]:
	var remaining: Array[Dictionary] = matches.duplicate(true)
	var result: Array[Dictionary] = []
	while not remaining.is_empty():
		var first: Dictionary = remaining.pop_front()
		var cells: Array = first.cells.duplicate()
		var runs: Array = [first]
		var changed := true
		while changed:
			changed = false
			for i in range(remaining.size() - 1, -1, -1):
				var run: Dictionary = remaining[i]
				if run.match_group != first.match_group or run.tier != first.tier: continue
				var overlaps := false
				for c in run.cells:
					if c in cells: overlaps = true; break
				if not overlaps: continue
				for c in run.cells:
					if c not in cells: cells.append(c)
				runs.append(run)
				remaining.remove_at(i)
				changed = true
		cells.sort_custom(cell_less)
		var lengths: Array = []
		for run in runs: lengths.append(run.cells.size())
		lengths.sort()
		var intersection := runs.size() > 1
		var semantic := &"match_lt" if intersection else (&"match_5_plus" if cells.size() >= 5 else (&"match_4" if cells.size() == 4 else &"base_match"))
		result.append({"cells": cells, "tier": first.tier, "match_group": first.match_group,
			"raw_type": &"intersection" if intersection else first.type, "semantic_type": semantic,
			"intersection": intersection, "line_lengths": lengths, "size_class": mini(5, cells.size())})
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return cell_less(a.cells[0], b.cells[0]))
	return result

static func cell_less(a: Vector2i, b: Vector2i) -> bool:
	return a.y < b.y or (a.y == b.y and a.x < b.x)

static func survivor(cells: Array, swap_pair: Array = []) -> Vector2i:
	if swap_pair.size() == 2:
		if swap_pair[1] in cells: return swap_pair[1]
		if swap_pair[0] in cells: return swap_pair[0]
	var ordered := cells.duplicate()
	ordered.sort_custom(cell_less)
	return ordered[-1]
