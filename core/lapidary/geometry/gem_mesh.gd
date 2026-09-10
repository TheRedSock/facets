class_name GemMesh
extends RefCounted
## CPU mesh IR. Indexed, oriented closed surfaces; facet identities survive
## triangulation and BVH reordering. No scene-tree or imported mesh dependency.
var vertices := PackedVector3Array()
var indices := PackedInt32Array()
var facet_ids := PackedInt32Array()

func triangle_count() -> int:
	return indices.size() / 3

func add_triangle(a: int, b: int, c: int, facet: int) -> void:
	indices.append_array(PackedInt32Array([a, b, c]))
	facet_ids.append(facet)

func signed_volume() -> float:
	var volume := 0.0
	for i in triangle_count():
		volume += vertices[indices[i * 3]].dot(vertices[indices[i * 3 + 1]].cross(vertices[indices[i * 3 + 2]])) / 6.0
	return volume

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if indices.size() % 3 != 0 or facet_ids.size() != triangle_count():
		errors.append("Triangle/facet buffer sizes disagree")
		return errors
	if vertices.size() < 4 or triangle_count() < 4:
		errors.append("A solid needs at least four vertices and faces")
		return errors
	for vertex in vertices:
		if not vertex.is_finite():
			errors.append("Nonfinite vertex")
			return errors
	for index in indices:
		if index < 0 or index >= vertices.size():
			errors.append("Triangle index outside vertex buffer")
			return errors
	var edges := {}
	for triangle in triangle_count():
		var a := indices[triangle * 3]
		var b := indices[triangle * 3 + 1]
		var c := indices[triangle * 3 + 2]
		if (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a]).length_squared() < 1.0e-18:
			errors.append("Degenerate triangle %d" % triangle)
		for edge in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
			var key := Vector2i(mini(edge.x, edge.y), maxi(edge.x, edge.y))
			var record: Vector2i = edges.get(key, Vector2i.ZERO)
			record.x += 1
			record.y += 1 if edge.x < edge.y else -1
			edges[key] = record
	for edge: Vector2i in edges:
		var record: Vector2i = edges[edge]
		if record.x != 2 or record.y != 0:
			errors.append("Open, nonmanifold or inconsistently wound edge %s (%s)" % [edge, record])
	if signed_volume() <= 1.0e-12:
		errors.append("Solid has zero or negative oriented volume")
	return errors

func fingerprint() -> String:
	return GemContentIdentity.digest([vertices, indices, facet_ids])
