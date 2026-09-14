class_name LayoutAdmission
extends RefCounted
const CARDINALS := [Vector2i.UP, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.DOWN]

static func issue(code: String, field: String, id: String, cells: Array = [], severity: String = "error") -> Dictionary:
	return {"code": code, "severity": severity, "resource_id": id, "field_path": field, "cells": cells, "edges": [], "message_key": "layout." + code}

static func admit(layout: BoardLayoutResource) -> Dictionary:
	var issues: Array = []
	if layout == null: return {"ok": false, "issues": [issue("missing_layout", "", "")]}
	var id := str(layout.layout_id)
	var size := layout.board_size
	if layout.schema_version != 1 or not GameValue.valid_id(id): issues.append(issue("schema_or_id", "layout_id", id))
	if size.x < 1 or size.y < 1 or size.x > 16 or size.y > 16:
		return {"ok": false, "issues": [issue("size_limit", "board_size", id)]}
	if layout.spawn_policy not in ["fill_empty_cells", "entry_only"]: issues.append(issue("spawn_policy", "spawn_policy", id))
	var blocked := {}
	for pos in layout.blocked_cells:
		if not inside(pos, size) or blocked.has(pos): issues.append(issue("blocked_reference", "blocked_cells", id, [pos]))
		blocked[pos] = true
	if blocked.size() >= size.x * size.y: issues.append(issue("empty_mask", "blocked_cells", id))
	var entries := {}
	for pos in layout.spawn_entries:
		if not inside(pos, size) or blocked.has(pos) or entries.has(pos): issues.append(issue("invalid_spawn_entry", "spawn_entries", id, [pos]))
		entries[pos] = true
	if layout.spawn_policy == "entry_only" and entries.is_empty(): issues.append(issue("missing_spawn_entries", "spawn_entries", id))
	var gravity := {}
	for key in layout.gravity_overrides:
		var pos: Variant = parse_cell(key)
		var value: Variant = layout.gravity_overrides[key]
		if pos == null or not inside(pos, size) or blocked.has(pos) or not value is Vector2i or (value != Vector2i.ZERO and value not in CARDINALS):
			issues.append(issue("invalid_gravity", "gravity_overrides/" + str(key), id)); continue
		gravity[pos] = value
	var fill := {}
	for key in layout.fill_source_overrides:
		var pos: Variant = parse_cell(key)
		var values: Variant = layout.fill_source_overrides[key]
		if pos == null or not inside(pos, size) or blocked.has(pos) or not values is Array or values.size() > 8:
			issues.append(issue("invalid_fill", "fill_source_overrides/" + str(key), id)); continue
		var seen := {}
		for direction in values:
			if not direction is Vector2i or direction == Vector2i.ZERO or abs(direction.x) > 1 or abs(direction.y) > 1 or seen.has(direction):
				issues.append(issue("invalid_fill_direction", "fill_source_overrides/" + str(key), id)); continue
			seen[direction] = true
			var source: Vector2i = pos + direction
			if not inside(source, size) or blocked.has(source): issues.append(issue("invalid_fill_source", "fill_source_overrides/" + str(key), id, [source]))
		fill[pos] = values.duplicate()
	var portals := {}
	for i in layout.portals.size():
		var edge: Dictionary = layout.portals[i]
		var field := "portals/%d" % i
		if edge.size() != 3 or not edge.get("from") is Vector2i or not edge.get("to") is Vector2i or not edge.get("direction") is Vector2i:
			issues.append(issue("portal_schema", field, id)); continue
		if not inside(edge.from, size) or not inside(edge.to, size): issues.append(issue("portal_out_of_bounds", field, id, [edge.from, edge.to])); continue
		if blocked.has(edge.from) or blocked.has(edge.to) or edge.direction not in CARDINALS: issues.append(issue("portal_endpoint", field, id)); continue
		var key := BoardState._portal_key(edge.from, edge.direction)
		if portals.has(key): issues.append(issue("duplicate_portal_edge", field, id))
		portals[key] = edge.to
	if not issues.is_empty(): return {"ok": false, "issues": issues}
	var cells: Array = []
	var neighbors: Array = []
	for y in size.y:
		for x in size.x:
			var pos := Vector2i(x, y)
			cells.append({"blocked": blocked.has(pos), "gravity": gravity.get(pos, Vector2i.DOWN), "entry": entries.has(pos), "fill": fill.get(pos, [])})
			var row: Array = []
			for direction in CARDINALS:
				var target: Vector2i = pos + direction
				row.append(target if inside(target, size) and not blocked.has(target) and not blocked.has(pos) else Vector2i(-1, -1))
			neighbors.append(row)
	var compiled := {"schema": 1, "id": id, "size": size, "cells": cells, "neighbors": neighbors, "portals": portals, "spawn_policy": layout.spawn_policy}
	var graph := travel_graph(compiled)
	var cycle := cycle_path(graph)
	if not cycle.is_empty():
		var error := issue("travel_cycle", "gravity/fill/portals", id, cycle)
		error.edges = cycle
		return {"ok": false, "issues": [error]}
	for index in graph.size():
		var incoming := 0
		for row in graph:
			if index in row: incoming += 1
		if incoming > 1: issues.append(issue("contention", "gravity/fill", id, [index], "warning"))
	if layout.spawn_policy == "entry_only":
		var reachable := {}
		var queue: Array = []
		for pos in entries: queue.append(pos.y * size.x + pos.x)
		while not queue.is_empty():
			var index: int = queue.pop_front()
			if reachable.has(index): continue
			reachable[index] = true
			queue.append_array(graph[index])
		for index in cells.size():
			if not cells[index].blocked and not reachable.has(index): issues.append(issue("unreachable_cell", "spawn_entries", id, [index], "warning"))
	return {"ok": true, "issues": issues, "topology": GameValue.freeze(compiled)}

static func travel_graph(topology: Dictionary, override: Vector2i = Vector2i.ZERO) -> Array:
	var graph: Array = []
	var size: Vector2i = topology.size
	for i in topology.cells.size(): graph.append([])
	for i in topology.cells.size():
		var cell: Dictionary = topology.cells[i]
		if cell.blocked: continue
		var pos := Vector2i(i % size.x, i / size.x)
		var gravity: Vector2i = override if override != Vector2i.ZERO else cell.gravity
		if gravity == Vector2i.ZERO: gravity = Vector2i.DOWN
		var target: Vector2i = topology.portals.get(BoardState._portal_key(pos, gravity), pos + gravity)
		if inside(target, size):
			var index: int = target.y * size.x + target.x
			if not topology.cells[index].blocked: graph[i].append(index)
		for direction in cell.fill:
			var source: Vector2i = pos + direction
			if inside(source, size):
				var index: int = source.y * size.x + source.x
				if not topology.cells[index].blocked and i not in graph[index]: graph[index].append(i)
	return graph

static func cycle_path(graph: Array) -> Array:
	var colors := {}
	var path: Array = []
	for i in graph.size():
		var cycle := visit(i, graph, colors, path)
		if not cycle.is_empty(): return cycle
	return []

static func visit(index: int, graph: Array, colors: Dictionary, path: Array) -> Array:
	if colors.get(index, 0) == 2: return []
	if colors.get(index, 0) == 1:
		var cycle := path.slice(path.find(index)); cycle.append(index); return cycle
	colors[index] = 1; path.append(index)
	for target in graph[index]:
		var cycle := visit(target, graph, colors, path)
		if not cycle.is_empty(): return cycle
	path.pop_back(); colors[index] = 2
	return []

static func inside(pos: Vector2i, size: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < size.x and pos.y < size.y

static func parse_cell(key: Variant) -> Variant:
	if not key is String: return null
	var parts: PackedStringArray = key.split(",")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int(): return null
	var pos := Vector2i(int(parts[0]), int(parts[1]))
	return pos if "%d,%d" % [pos.x, pos.y] == key else null
