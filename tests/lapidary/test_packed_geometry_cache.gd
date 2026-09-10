extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: " + label)

func _initialize() -> void:
	var source := GemShapeCompiler.loft(PackedVector2Array([Vector2(-1,-1), Vector2(1,-1), Vector2(1,1), Vector2(-1,1)]), PackedVector2Array([Vector2(-1,1), Vector2(1,1)]))
	var cache := GemPackedGeometryCache.new()
	var reference := GemBvh.build(source)
	var first := cache.packed(source)
	check(first.error.is_empty() and first.nodes == reference.pack_nodes() and first.triangles == reference.pack_triangles(), "canonical bytes equal uncached BVH")
	for offsets in [Vector2i.ZERO, Vector2i(1, 9), Vector2i(97, 100003)]:
		check(GemPackedGeometryCache.relocate_nodes(first.nodes, offsets.x, offsets.y) == reference.pack_nodes(offsets.x, offsets.y), "batch relocation preserves all node fields: %s" % offsets)
	first.nodes[0] ^= 255
	first.triangles[0] ^= 255
	var repeated := cache.packed(source)
	check(repeated.nodes == reference.pack_nodes() and repeated.triangles == reference.pack_triangles(), "returned bytes cannot corrupt cached payload")
	check(cache.hits == 1 and cache.builds == 1, "same geometry reuses its packed BVH")
	var clone := _clone(source)
	cache.packed(clone)
	check(cache.hits == 2 and cache.builds == 1, "detached equal mesh reuses actual contents")
	clone.vertices[0] *= 1.01
	var changed := cache.packed(clone)
	check(changed.error.is_empty() and cache.builds == 2 and changed.triangles != repeated.triangles, "in-place vertex change invalidates payload")
	clone = _clone(source)
	# Cyclic permutation preserves winding and geometry but changes encoded topology.
	var a := clone.indices[0]
	clone.indices[0] = clone.indices[1]; clone.indices[1] = clone.indices[2]; clone.indices[2] = a
	changed = cache.packed(clone)
	check(changed.error.is_empty() and cache.builds == 3, "index edits invalidate payload")
	clone = _clone(source)
	clone.facet_ids[0] = -123456789
	changed = cache.packed(clone)
	check(changed.error.is_empty() and cache.builds == 4 and changed.triangles == GemBvh.build(clone).pack_triangles(), "signed semantic facet changes survive packing")
	clone = _clone(source)
	clone.region_ids.fill(7)
	changed = cache.packed(clone)
	check(changed.error.is_empty() and cache.builds == 5 and changed.triangles == GemBvh.build(clone).pack_triangles(), "closed region remapping invalidates payload")
	clone.indices[0] = -1
	check(not cache.packed(clone).error.is_empty() and cache.builds == 5, "invalid mutation rejected before unsafe BVH traversal")
	check(not cache.packed(null).error.is_empty(), "missing mesh rejected")
	var payload_bytes: int = repeated.nodes.size() + repeated.triangles.size()
	cache.clear(); cache.budget_bytes = payload_bytes * 2; cache.entry_limit = 2
	var b := _clone(source); b.facet_ids.fill(2)
	var c := _clone(source); c.facet_ids.fill(3)
	cache.packed(source); cache.packed(b); cache.packed(source); cache.packed(c)
	var builds := cache.builds
	cache.packed(source)
	check(cache.builds == builds, "most recently used payload survives eviction")
	cache.packed(b)
	check(cache.builds == builds + 1 and cache.retained_bytes == payload_bytes * 2, "least recently used payload evicted within byte budget")
	cache.budget_bytes = payload_bytes - 1
	cache.packed(source)
	check(cache.retained_bytes == 0 and cache.statistics().entries == 0, "oversized payload returned but not retained; lowered budget enforced")
	cache.budget_bytes = payload_bytes * 8; cache.entry_limit = 0
	cache.packed(source)
	check(cache.retained_bytes == 0, "zero entry limit disables retention")
	cache.entry_limit = 2; cache.packed(source); cache.clear()
	check(cache.retained_bytes == 0 and cache.statistics().entries == 0, "explicit clear releases retained payloads")
	print("Packed geometry cache: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _clone(source: GemMesh) -> GemMesh:
	var result := GemMesh.new()
	result.vertices = source.vertices.duplicate(); result.indices = source.indices.duplicate()
	result.facet_ids = source.facet_ids.duplicate(); result.region_ids = source.region_ids.duplicate()
	return result
