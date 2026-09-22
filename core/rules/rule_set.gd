class_name RuleSet
extends RefCounted

const DEFAULTS := {
	"rules_id": "facets.prototype.v1", "simulation": "facets-sim-v1",
	"codec": "facets-codec-v1", "rng": "facets-stream-v1",
	"settling": "legacy_scan_v1", "matching": "orthogonal_lines_v1",
	"survivor": "destination_origin_max_yx_v1", "progression": "roster_next_v1",
	"budget": "fixed_cost_v1", "fill": "local_sources_v1",
	"opening": "bounded_opening_v1", "swap_cost": 1,
	"max_settle": 256, "max_cascades": 50, "max_chains": 20,
	"max_openings": 64, "max_work": 1000000, "max_facts": 100000,
}
var _data: Dictionary

func _init(data: Dictionary = DEFAULTS) -> void:
	_data = GameValue.freeze(data)

func value(key: String) -> Variant:
	return _data[key]

func to_dict() -> Dictionary:
	return _data.duplicate(true)

func is_room() -> bool:
	return _data.simulation in ["facets-sim-v2","facets-sim-p3-merge-v1"]

func is_p3() -> bool:
	return _data.simulation == "facets-sim-p3-merge-v1"

static func p3_defaults() -> Dictionary:
	var data := room_defaults()
	data.simulation = "facets-sim-p3-merge-v1"; data.profile = "p3-merge"
	data.merge({"families":"quartz_corundum_beryl_v1","max_reactions":256})
	return data

static func for_p3() -> RuleSet:
	return RuleSet.new(p3_defaults())

static func room_defaults() -> Dictionary:
	var data := DEFAULTS.duplicate(true)
	data.simulation = "facets-sim-v2"
	data.merge({"profile":"p2", "economy":"work_craft_v1", "obstacles":"component_rubble_v1",
		"recovery":"low_tier_permutation_v1", "craft_capacity":6, "craft_gain_cap":3,
		"exchange_cost":2, "clear_cost":2, "promote_cost":3, "max_recoveries":64})
	return data

static func for_room() -> RuleSet:
	return RuleSet.new(room_defaults())

static func admit(data: Variant) -> Dictionary:
	if not data is Dictionary: return {"ok": false, "code": "rules_schema"}
	var defaults := p3_defaults() if data.get("simulation") == "facets-sim-p3-merge-v1" else (room_defaults() if data.get("simulation") == "facets-sim-v2" else DEFAULTS)
	if data.size() != defaults.size(): return {"ok": false, "code": "rules_schema"}
	for key in defaults:
		if not data.has(key) or typeof(data[key]) != typeof(defaults[key]): return {"ok": false, "code": "rules_field", "field": key}
		if defaults[key] is String and data[key] != defaults[key]: return {"ok": false, "code": "unsupported_policy", "field": key}
		if defaults[key] is int and (data[key] < 0 or data[key] > defaults[key]): return {"ok": false, "code": "rules_limit", "field": key}
	if defaults.has("profile"):
		for key in ["craft_capacity","craft_gain_cap","exchange_cost","clear_cost","promote_cost"]:
			if data[key] != defaults[key]: return {"ok":false,"code":"room_economy_policy"}
	if data.swap_cost != 1 or data.max_openings < 1: return {"ok": false, "code": "rules_cost_or_opening"}
	return {"ok": true, "rules": RuleSet.new(data)}
