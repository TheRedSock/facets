class_name RngStreamBank
extends RefCounted

const IDS := ["board", "rewards", "routes", "recovery"]
const VERSION := "facets-stream-v1"
var master_seed: int
var _streams := {}

func _init(seed_value: int = 0) -> void:
	master_seed = seed_value
	for id in IDS:
		var rng := SeededRng.new()
		rng.reseed(derive(seed_value, id))
		_streams[id] = rng

static func derive(seed_value: int, id: String) -> int:
	return (VERSION + "\n" + str(seed_value) + "\n" + id).sha256_text().left(15).hex_to_int()

func stream(id: String) -> SeededRng:
	return _streams.get(id)

func capture() -> Dictionary:
	var states := {}
	for id in IDS: states[id] = stream(id).capture()
	return {"version": VERSION, "implementation": Engine.get_version_info().string, "master_seed": master_seed, "streams": states}

static func restored(data: Variant) -> Dictionary:
	if not data is Dictionary or data.size() != 4 or data.get("version") != VERSION or data.get("implementation") != Engine.get_version_info().string or not data.get("master_seed") is int:
		return {"ok": false, "code": "rng_version"}
	if not data.get("streams") is Dictionary or data.streams.size() != IDS.size(): return {"ok": false, "code": "rng_streams"}
	var bank := RngStreamBank.new(data.master_seed)
	for id in IDS:
		if not data.streams.get(id) is Dictionary or data.streams[id].get("seed") != derive(data.master_seed, id) or not bank.stream(id).restore(data.streams[id]):
			return {"ok": false, "code": "rng_state"}
	return {"ok": true, "bank": bank}
