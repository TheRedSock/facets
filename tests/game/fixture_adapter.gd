class_name GameFixtureAdapter
extends RefCounted

const PATH := "res://tests/fixtures/game_prototype_v1/cases.json"
const FIELDS := {
	"swap_then_first_match": ["component_sizes", "survivor", "promoted_tier", "removed_count", "base_craft_candidate"],
	"match_snapshot": ["component_sizes", "survivor", "intersection", "unique_member_count", "seal_removed_before_merge"],
	"validate_action": ["accepted", "state_and_rng_unchanged"],
	"spawn_query": ["eligible_cells"], "gravity_query": ["direction"],
	"state_identity": ["hash_must_change"],
	"settle_refill": ["occupied_cells", "spawn_origins", "all_events_root_cause"],
	"recovery_query": ["legal_swaps_before", "preserve_multiset", "work_delta", "craft_delta", "result", "state_preserved"],
	"complete_action": ["room_result", "work", "marked_rubble_remaining", "completion_count"],
	"stable_extraction": ["room_result", "extracted_count", "removed_count", "carry_excludes_cell"],
}

static func read_cases() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string(PATH))["cases"]

static func cell(pair: Array) -> Vector2i:
	return Vector2i(int(pair[0]), int(pair[1]))

static func board(c: Dictionary) -> BoardState:
	var result := BoardState.new(Vector2i(c.board[0].size(), c.board.size()))
	result.id_namespace = c.id
	for y in result.size.y:
		for x in result.size.x:
			if c.board[y][x] == 0: continue
			var tile := TileState.from_debug_tier(int(c.board[y][x]))
			tile.instance_id = "%s/%d" % [c.id, y * result.size.x + x]
			result.set_tile(Vector2i(x, y), tile)
	result.next_instance = result.size.x * result.size.y
	for pair in c.get("immovable_cells", []): result.get_tile(cell(pair)).immovable = true
	for lock in c.get("locks", []): result.get_cell(cell(lock.cell)).lock = {"kind": lock.kind, "durability": int(lock.durability)}
	for entry in c.get("cell_gravity", []): result.get_cell(cell(entry.cell)).gravity_direction = cell(entry.direction)
	for portal in c.get("portals", []): result.add_portal(cell(portal.from), cell(portal.direction), cell(portal.to))
	if c.has("spawn_entries"):
		result.spawn_policy = "entry_only"
		for entry in c.spawn_entries: result.get_cell(cell(entry)).is_spawn_entry = true
	return result

static func inventory(cases: Array) -> Dictionary:
	var issues: Array[String] = []
	var rows: Array = []
	var ids := {}
	for c in cases:
		if ids.has(c.id): issues.append("duplicate case: " + c.id)
		ids[c.id] = true
		if not FIELDS.has(c.phase):
			issues.append("unknown phase: " + c.phase)
			continue
		var fields := {}
		for field in c.expected:
			if field not in FIELDS[c.phase]: issues.append("unknown expected field: " + c.id + "." + field)
			var owner := "P1"
			if c.phase == "complete_action" or field == "base_craft_candidate": owner = "P2"
			if c.phase == "recovery_query" and field != "legal_swaps_before": owner = "P2"
			if c.phase == "stable_extraction": owner = "P3"
			if field == "seal_removed_before_merge": owner = "P6"
			fields[field] = owner
		rows.append({"id": c.id, "phase": c.phase, "fields": fields})
	return {"issues": issues, "cases": rows}
