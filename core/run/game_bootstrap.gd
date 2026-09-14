class_name GameBootstrap
extends RefCounted
## Composition boundary: resources are read here, never by rule services.

static func catalog(profile: GameRulesResource = null) -> Dictionary:
	if profile == null: profile = load("res://data/game/rules/prototype.tres")
	if profile == null: return {"ok": false, "code": "missing_profile"}
	var data := {"schema": 1, "roster": [], "definitions": {}, "targets": Array(profile.supply_targets), "weights": Array(profile.supply_weights)}
	for id in profile.roster:
		if not GameValue.valid_id(id) or "/" in id: return {"ok": false, "code": "invalid_definition_id"}
		var path := "res://data/tiles/" + id + ".tres"
		if not ResourceLoader.exists(path): return {"ok": false, "code": "missing_definition"}
		var d := load(path) as TileDefinitionResource
		if d == null or str(d.tile_id) != id: return {"ok": false, "code": "invalid_definition"}
		data.roster.append(id)
		data.definitions[id] = {"id": id, "tier": d.tier, "match_group": "tier_%d" % d.tier, "family_tags": Array(d.family_tags)}
	return GameCatalog.admit(data)
