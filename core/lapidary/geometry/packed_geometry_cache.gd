class_name GemPackedGeometryCache
extends RefCounted
## Per-consumer LRU of canonical, zero-offset BVH bytes. Actual boundary contents,
## including facet/region identities, determine reuse. No authoring ID is trusted.
## The budget counts retained packed payloads, not temporary build/copy memory.
var budget_bytes := 64 * 1024 * 1024
var entry_limit := 16
var retained_bytes := 0
var builds := 0
var hits := 0
var _entries: Dictionary = {}

func packed(mesh: GemMesh, solid: GemRoundedSolid = null) -> Dictionary:
	_trim()
	if mesh == null and solid == null:
		return {"error": "Missing boundary mesh"}
	if solid != null and not solid.validation_error().is_empty():
		return {"error":solid.validation_error()}
	var key := mesh.fingerprint() if solid == null else GemContentIdentity.digest([solid.fingerprint(),mesh.fingerprint() if mesh != null else ""])
	if _entries.has(key):
		var entry: Dictionary = _entries[key]
		_entries.erase(key)
		_entries[key] = entry
		hits += 1
		return _copy(entry)
	var result: Dictionary
	if solid != null:
		result = GemPrimitiveBvh.pack(solid,mesh)
		if not result.error.is_empty(): return result
	else:
		var errors := mesh.validate()
		if not errors.is_empty():
			return {"error": "Invalid packed boundary mesh: " + "; ".join(errors)}
		var bvh := GemBvh.build(mesh)
		result = {"error": "", "nodes": bvh.pack_nodes(), "triangles": bvh.pack_triangles(), "clips":PackedByteArray()}
	builds += 1
	var size: int = result.nodes.size() + result.triangles.size() + result.clips.size()
	if size <= maxi(0, budget_bytes) and entry_limit > 0:
		while not _entries.is_empty() and (retained_bytes + size > budget_bytes or _entries.size() >= entry_limit):
			_evict_oldest()
		_entries[key] = result
		retained_bytes += size
	return _copy(result)

## Relocation changes only node indices; packed triangle semantics stay local
## to their specimen's region table. Return independent bytes even at offset 0.
static func relocate_nodes(canonical: PackedByteArray, node_offset: int, triangle_offset: int) -> PackedByteArray:
	assert(canonical.size() % 48 == 0 and node_offset >= 0 and triangle_offset >= 0)
	var bytes := canonical.duplicate()
	if node_offset == 0 and triangle_offset == 0:
		return bytes
	for node in bytes.size() / 48:
		var base := node * 48
		for slot in [32, 36]:
			var child := bytes.decode_s32(base + slot)
			if child >= 0:
				bytes.encode_s32(base + slot, child + node_offset)
		bytes.encode_s32(base + 40, bytes.decode_s32(base + 40) + triangle_offset)
	return bytes

func clear() -> void:
	_entries.clear()
	retained_bytes = 0

func statistics() -> Dictionary:
	return {"builds": builds, "hits": hits, "retained_bytes": retained_bytes, "entries": _entries.size()}

func _trim() -> void:
	while not _entries.is_empty() and (retained_bytes > maxi(0, budget_bytes) or _entries.size() > maxi(0, entry_limit)):
		_evict_oldest()

func _evict_oldest() -> void:
	var key: String = _entries.keys()[0]
	var entry: Dictionary = _entries[key]
	retained_bytes -= entry.nodes.size() + entry.triangles.size() + entry.clips.size()
	_entries.erase(key)

static func _copy(entry: Dictionary) -> Dictionary:
	return {"error": "", "nodes": entry.nodes.duplicate(), "triangles": entry.triangles.duplicate(), "clips":entry.clips.duplicate()}
