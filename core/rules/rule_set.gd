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

static func admit(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size() != DEFAULTS.size(): return {"ok": false, "code": "rules_schema"}
	for key in DEFAULTS:
		if not data.has(key) or typeof(data[key]) != typeof(DEFAULTS[key]): return {"ok": false, "code": "rules_field", "field": key}
		if DEFAULTS[key] is String and data[key] != DEFAULTS[key]: return {"ok": false, "code": "unsupported_policy", "field": key}
		if DEFAULTS[key] is int and (data[key] < 0 or data[key] > DEFAULTS[key]): return {"ok": false, "code": "rules_limit", "field": key}
	if data.swap_cost != 1 or data.max_openings < 1: return {"ok": false, "code": "rules_cost_or_opening"}
	return {"ok": true, "rules": RuleSet.new(data)}
