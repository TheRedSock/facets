class_name GameCatalog
extends RefCounted

var _data: Dictionary

func _init(data: Dictionary) -> void:
	_data = GameValue.freeze(data)

func to_dict() -> Dictionary:
	return _data.duplicate(true)

func roster() -> Array:
	return _data.roster.duplicate()

func definition(tier: int) -> Dictionary:
	if tier < 1 or tier > 8: return {}
	return _data.definitions[_data.roster[tier - 1]]

func create_tile(tier: int) -> TileState:
	var d := definition(tier)
	if d.is_empty(): return null
	var tile := TileState.create(StringName(d.id), tier, StringName(d.match_group))
	tile.family_tags.assign(d.family_tags)
	return tile

func promote(tile: TileState) -> bool:
	var target := definition(tile.tier + 1)
	if target.is_empty(): return false
	tile.tier += 1
	tile.tile_id = StringName(target.id)
	tile.match_group = StringName(target.match_group)
	tile.family_tags.assign(target.family_tags)
	tile.merge_target_id = &""
	return true

func supply() -> SpawnTableResource:
	var table := SpawnTableResource.new()
	table.table_id = &"prototype_supply_v1"
	table.allowed_tiers.assign(_data.targets)
	table.weights.assign(_data.weights)
	return table

static func admit(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size() != 5: return {"ok": false, "code": "catalog_schema"}
	for key in ["schema", "roster", "definitions", "targets", "weights"]:
		if not data.has(key): return {"ok": false, "code": "catalog_field"}
	if data.schema != 1 or not data.schema is int or not data.roster is Array or data.roster.size() != 8 or not data.definitions is Dictionary or data.definitions.size() != 8:
		return {"ok": false, "code": "catalog_roster"}
	var seen := {}
	var match_groups := {}
	for i in 8:
		var id: Variant = data.roster[i]
		if not GameValue.valid_id(id) or seen.has(id) or not data.definitions.has(id): return {"ok": false, "code": "catalog_id"}
		seen[id] = true
		var d: Variant = data.definitions[id]
		if not d is Dictionary or d.size() != 4: return {"ok": false, "code": "definition_schema"}
		if d.get("id") != id or not d.get("tier") is int or d.tier != i + 1 or not GameValue.valid_id(d.get("match_group")) or not d.get("family_tags") is Array:
			return {"ok": false, "code": "definition_value"}
		if match_groups.has(d.match_group): return {"ok":false,"code":"duplicate_tier_match_group"}
		match_groups[d.match_group] = true
		var tags := {}
		for tag in d.family_tags:
			if not GameValue.valid_id(tag) or tags.has(tag): return {"ok": false, "code": "family_tags"}
			tags[tag] = true
	var issue := validate_supply(data.targets, data.weights)
	if not issue.is_empty(): return {"ok": false, "code": issue}
	var normalized: Dictionary = data.duplicate(true)
	for d in normalized.definitions.values(): d.family_tags.sort()
	return {"ok": true, "catalog": GameCatalog.new(normalized)}

static func validate_supply(targets: Variant, weights: Variant) -> String:
	if not targets is Array or not weights is Array or targets.size() != weights.size() or targets.size() > 8: return "supply_shape"
	var total := 0
	var positive := {}
	var seen := {}
	for i in targets.size():
		if not targets[i] is int or targets[i] < 1 or targets[i] > 8 or seen.has(targets[i]): return "supply_target"
		seen[targets[i]] = true
		if not weights[i] is int or weights[i] < 0 or weights[i] > 2147483647 - total: return "supply_weight"
		total += weights[i]
		if weights[i] > 0: positive[targets[i]] = true
	if total == 0 or positive.size() < 3: return "supply_diversity"
	return ""
