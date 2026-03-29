class_name MatchClassifier
extends RefCounted


## Classifies raw matches into semantic types.
## Detects overlapping L/T shapes by finding intersections between horizontal and vertical matches.
func classify(matches: Array[Dictionary]) -> Array[Dictionary]:
	var classified: Array[Dictionary] = []

	# Separate horizontal and vertical for L/T detection
	var h_matches: Array[Dictionary] = []
	var v_matches: Array[Dictionary] = []

	for match_data in matches:
		var raw_type: StringName = match_data.get("type", &"unknown")
		if raw_type == &"line_horizontal":
			h_matches.append(match_data)
		elif raw_type == &"line_vertical":
			v_matches.append(match_data)

	# Track which matches have been consumed by L/T grouping
	var consumed_h: Dictionary = {}  # index -> true
	var consumed_v: Dictionary = {}  # index -> true

	# Detect L/T intersections: a horizontal and vertical match sharing a cell and match_group
	for hi in h_matches.size():
		var h: Dictionary = h_matches[hi]
		var h_cells: Array = h.get("cells", [])
		var h_group: StringName = h.get("match_group", &"")

		for vi in v_matches.size():
			if consumed_v.has(vi):
				continue
			var v: Dictionary = v_matches[vi]
			var v_cells: Array = v.get("cells", [])
			var v_group: StringName = v.get("match_group", &"")

			if h_group != v_group:
				continue

			# Check for shared cell
			for hc in h_cells:
				if hc in v_cells:
					# Found an L/T intersection
					var merged_cells: Array[Vector2i] = []
					for c in h_cells:
						if c not in merged_cells:
							merged_cells.append(c)
					for c in v_cells:
						if c not in merged_cells:
							merged_cells.append(c)

					classified.append({
						"raw_type": &"intersection",
						"semantic_type": &"match_lt",
						"cells": merged_cells,
						"match_group": h_group,
						"tier": h.get("tier", 0),
					})
					consumed_h[hi] = true
					consumed_v[vi] = true
					break

			if consumed_h.has(hi):
				break

	# Classify remaining non-consumed matches
	for hi in h_matches.size():
		if consumed_h.has(hi):
			continue
		classified.append(_classify_line(h_matches[hi]))

	for vi in v_matches.size():
		if consumed_v.has(vi):
			continue
		classified.append(_classify_line(v_matches[vi]))

	return classified


func _classify_line(match_data: Dictionary) -> Dictionary:
	var cells: Array = match_data.get("cells", [])
	var match_type: StringName = match_data.get("type", &"unknown")
	var semantic_type := &"base_match"

	if cells.size() == 4:
		semantic_type = &"match_4"
	elif cells.size() >= 5:
		semantic_type = &"match_5_plus"

	return {
		"raw_type": match_type,
		"semantic_type": semantic_type,
		"cells": cells,
		"match_group": match_data.get("match_group", &""),
		"tier": match_data.get("tier", 0),
	}
