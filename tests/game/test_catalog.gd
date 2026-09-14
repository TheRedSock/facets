class_name GameTestCatalog
extends RefCounted
## Explicit synthetic catalog. Never used by production bootstrap.
static func create() -> GameCatalog:
	var data := {"schema": 1, "roster": [], "definitions": {}, "targets": [1, 2, 3, 4], "weights": [4, 3, 2, 1]}
	for tier in range(1, 9):
		var id := "debug_tier_%d" % tier
		data.roster.append(id)
		data.definitions[id] = {"id": id, "tier": tier, "match_group": id, "family_tags": []}
	return GameCatalog.admit(data).catalog
