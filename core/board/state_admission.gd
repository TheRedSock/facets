class_name StateAdmission
extends RefCounted

static func exact(data: Variant, keys: Array) -> bool:
	if not data is Dictionary or data.size() != keys.size(): return false
	for key in keys:
		if not data.has(key): return false
	return true

static func vector_record(data: Variant) -> bool:
	return exact(data,["x","y"]) and data.x is int and data.y is int and data.x >= -2147483648 and data.x <= 2147483647 and data.y >= -2147483648 and data.y <= 2147483647

static func board(data: Variant, catalog: GameCatalog) -> Dictionary:
	var keys := ["size","cells","portals","spawn_policy","next_instance","id_namespace"]
	var room_board: bool = data is Dictionary and data.has("obstacles")
	if room_board: keys.append("obstacles")
	if not exact(data,keys): return fail("board_schema")
	if not data.size is Vector2i or not data.cells is Array or not data.portals is Dictionary or not data.spawn_policy is String or not data.next_instance is int or data.next_instance < 1 or data.next_instance > 1000000000 or not GameValue.valid_id(data.id_namespace): return fail("board_types")
	var size: Vector2i = data.size
	if size.x < 1 or size.y < 1 or size.x > 16 or size.y > 16 or data.cells.size() != size.x * size.y or data.portals.size() > size.x * size.y * 4: return fail("board_bounds")
	var layout := BoardLayoutResource.new()
	layout.board_size = size; layout.spawn_policy = data.spawn_policy
	var occupants: Array = []
	var ids := {}
	var overrides := {}
	for i in data.cells.size():
		var raw: Variant = data.cells[i]
		if not exact(raw,["blocked","gravity_direction","is_spawn_entry","fill_sources","tags","lock","tile"]): return fail("cell_schema")
		if not raw.blocked is bool or not raw.is_spawn_entry is bool or not vector_record(raw.gravity_direction) or not raw.fill_sources is Array or not raw.tags is Dictionary or not raw.lock is Dictionary: return fail("cell_types")
		if CanonicalCodec.encode(raw.tags).is_empty() or raw.tags.size() > 64: return fail("cell_tags")
		if not raw.lock.is_empty() and (not exact(raw.lock,["kind","durability"]) or raw.lock.kind not in ["seal","movement_lock"] or not raw.lock.durability is int or raw.lock.durability < 1 or raw.lock.durability > 1000000): return fail("lock_schema")
		var pos := Vector2i(i % size.x,i / size.x)
		if raw.blocked:
			if Vector2i(raw.gravity_direction.x,raw.gravity_direction.y) != Vector2i.DOWN: return fail("blocked_gravity")
			if raw.tile != null or not raw.lock.is_empty() or raw.is_spawn_entry or not raw.fill_sources.is_empty(): return fail("blocked_occupant")
			layout.add_blocked(pos)
		else:
			layout.set_gravity(pos, Vector2i(raw.gravity_direction.x,raw.gravity_direction.y))
			if raw.is_spawn_entry: layout.add_spawn_entry(pos)
			var sources: Array[Vector2i] = []
			for source in raw.fill_sources:
				if not source is Vector2i: return fail("fill_type")
				sources.append(source)
			layout.set_fill_sources(pos,sources)
		if raw.tile == null:
			if not raw.lock.is_empty(): return fail("empty_lock")
			occupants.append(null); continue
		var admitted := tile(raw.tile,catalog)
		if not admitted.ok: return admitted
		var piece: TileState = admitted.tile
		if ids.has(piece.instance_id): return fail("duplicate_instance")
		ids[piece.instance_id] = true
		var prefix: String = data.id_namespace + "/"
		if not piece.instance_id.begins_with(prefix): return fail("instance_namespace")
		var suffix := piece.instance_id.substr(prefix.length())
		if not suffix.is_valid_int() or str(int(suffix)) != suffix or int(suffix) < 0 or int(suffix) >= data.next_instance: return fail("instance_allocator")
		if piece.gravity_override != Vector2i.ZERO: overrides[piece.gravity_override] = true
		occupants.append(piece)
	for key in data.portals:
		if not key is String or not data.portals[key] is Vector2i: return fail("portal_type")
		var parts: PackedStringArray = key.split(",")
		if parts.size() != 4: return fail("portal_key")
		for part in parts:
			if not part.is_valid_int() or str(int(part)) != part or int(part) < -16 or int(part) > 16: return fail("portal_key")
		layout.add_portal(Vector2i(int(parts[0]),int(parts[1])),Vector2i(int(parts[2]),int(parts[3])),data.portals[key])
	var compiled := LayoutAdmission.admit(layout)
	if not compiled.ok: return {"ok": false, "code": "invalid_topology", "issues": compiled.issues}
	for direction in overrides:
		if not LayoutAdmission.cycle_path(LayoutAdmission.travel_graph(compiled.topology,direction)).is_empty(): return fail("override_cycle")
	var result := BoardState.new(); result.apply_topology(compiled.topology)
	result.id_namespace = data.id_namespace; result.next_instance = data.next_instance
	for i in occupants.size():
		var pos := Vector2i(i % size.x,i / size.x)
		result.get_cell(pos).tags = data.cells[i].tags.duplicate(true)
		result.get_cell(pos).lock = data.cells[i].lock.duplicate(true)
		result.get_cell(pos).tile = occupants[i]
	if room_board:
		if not data.obstacles is Dictionary or data.obstacles.size() > size.x * size.y: return fail("obstacle_schema")
		result.room_board = true
		var occupied := {}
		for id in data.obstacles:
			var obstacle: Variant = data.obstacles[id]
			if not GameValue.valid_id(id) or not exact(obstacle,["id","cell","kind","durability"]): return fail("obstacle_schema")
			if obstacle.id != id or not obstacle.cell is Vector2i or obstacle.kind != "rubble" or not obstacle.durability is int or obstacle.durability < 1 or obstacle.durability > 2: return fail("obstacle_value")
			if not result.can_enter(obstacle.cell) or occupied.has(obstacle.cell) or not result.get_cell(obstacle.cell).lock.is_empty(): return fail("obstacle_occupancy")
			occupied[obstacle.cell] = true
			result.obstacles[id] = obstacle.duplicate(true)
	return {"ok": true, "board": result}

static func tile(data: Variant, catalog: GameCatalog) -> Dictionary:
	if not exact(data,["instance_id","tile_id","match_group","tier","family_tags","status_flags","protected","gravity_override","immovable","unmatchable","merge_target_id"]): return fail("tile_schema")
	if not GameValue.valid_id(data.instance_id) or not data.tier is int or data.tier < 1 or data.tier > 8 or not data.family_tags is Array or not data.status_flags is Dictionary or not data.protected is bool or not data.immovable is bool or not data.unmatchable is bool or not vector_record(data.gravity_override): return fail("tile_types")
	if data.protected or data.merge_target_id != "" or data.status_flags.size() > 64 or CanonicalCodec.encode(data.status_flags).is_empty(): return fail("unsupported_tile_state")
	var definition := catalog.definition(data.tier)
	for tag in data.family_tags:
		if not (tag is String or tag is StringName): return fail("family_tag_type")
	if data.tile_id != definition.id or data.match_group != definition.match_group or data.family_tags.map(func(s: Variant) -> String: return str(s)) != Array(definition.family_tags).map(func(s: Variant) -> String: return str(s)): return fail("tile_definition")
	var gravity := Vector2i(data.gravity_override.x,data.gravity_override.y)
	if gravity != Vector2i.ZERO and gravity not in LayoutAdmission.CARDINALS: return fail("tile_gravity")
	var result := catalog.create_tile(data.tier)
	result.instance_id = data.instance_id; result.status_flags = data.status_flags.duplicate(true)
	result.gravity_override = gravity; result.immovable = data.immovable; result.unmatchable = data.unmatchable
	return {"ok": true, "tile": result}

static func fail(code: String) -> Dictionary:
	return {"ok": false, "code": code}
