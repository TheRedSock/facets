class_name GemMeshValidation
extends RefCounted
## Admission for closed piecewise-linear region boundaries. Separate regions
## may overlap. Within a region shells must be disjoint or nested with alternating
## orientation (outer solid, cavity, island), never interpenetrating or touching.
const P := preload("res://core/lapidary/geometry/exact_predicates.gd")
const Contact := preload("res://core/lapidary/geometry/mesh_intersections.gd")

static func validate(mesh: GemMesh) -> PackedStringArray:
	var count := mesh.triangle_count()
	if mesh.indices.size() % 3 != 0 or mesh.facet_ids.size() != count or mesh.region_ids.size() != count:
		return PackedStringArray(["Triangle/facet/region buffer sizes disagree"])
	if mesh.vertices.size() < 4 or count < 4:
		return PackedStringArray(["A solid needs at least four vertices and faces"])
	for vertex in mesh.vertices:
		if not vertex.is_finite():
			return PackedStringArray(["Nonfinite vertex"])
	for index in mesh.indices:
		if index < 0 or index >= mesh.vertices.size():
			return PackedStringArray(["Triangle index outside vertex buffer"])
	var edges := {}
	var links := {}
	var adjacency: Array[Array] = []
	for triangle in count:
		adjacency.append([])
		var region := mesh.region_ids[triangle]
		if region < 0:
			return PackedStringArray(["Negative region identity"])
		var ids := [mesh.indices[triangle * 3], mesh.indices[triangle * 3 + 1], mesh.indices[triangle * 3 + 2]]
		if Contact.projection(mesh.vertices[ids[0]], mesh.vertices[ids[1]], mesh.vertices[ids[2]]).x < 0:
			return PackedStringArray(["Degenerate triangle %d" % triangle])
		for k in 3:
			var a: int = ids[k]
			var b: int = ids[(k + 1) % 3]
			var c: int = ids[(k + 2) % 3]
			var key := Vector3i(region, mini(a, b), maxi(a, b))
			if edges.has(key):
				var previous: Vector3i = edges[key]
				if previous.z != 1 or previous.y != b:
					return PackedStringArray(["Open, nonmanifold or inconsistently wound edge %s" % key])
				adjacency[triangle].append(previous.x)
				adjacency[previous.x].append(triangle)
				edges[key] = Vector3i(previous.x, previous.y, 2)
			else:
				edges[key] = Vector3i(triangle, a, 1)
			var vertex_key := Vector2i(region, a)
			var link: Dictionary = links.get(vertex_key, {})
			var neighbors: Array = link.get(b, [])
			neighbors.append(c)
			link[b] = neighbors
			neighbors = link.get(c, [])
			neighbors.append(b)
			link[c] = neighbors
			links[vertex_key] = link
	for key: Vector3i in edges:
		if edges[key].z != 2:
			return PackedStringArray(["Open boundary edge %s" % key])
	# Edge-manifold alone permits disconnected fans pinched at a vertex.
	for vertex_key: Vector2i in links:
		var link: Dictionary = links[vertex_key]
		var visited := {}
		var pending: Array = [link.keys()[0]]
		while not pending.is_empty():
			var vertex: int = pending.pop_back()
			if visited.has(vertex):
				continue
			visited[vertex] = true
			pending.append_array(link[vertex])
		if visited.size() != link.size():
			return PackedStringArray(["Disconnected surface fan at region/vertex %s" % vertex_key])
	var intersection := Contact.first_invalid(mesh)
	if intersection.x >= 0:
		return PackedStringArray(["Self-intersection, unshared contact or coincident region interfaces between triangles %d and %d" % [intersection.x, intersection.y]])
	var seen := {}
	var components: Array[Array] = []
	for triangle in count:
		if seen.has(triangle):
			continue
		var component: Array[int] = []
		var pending: Array[int] = [triangle]
		while not pending.is_empty():
			var face: int = pending.pop_back()
			if seen.has(face):
				continue
			seen[face] = true
			component.append(face)
			pending.append_array(adjacency[face])
		components.append(component)
	for i in components.size():
		var component: Array[int] = components[i]
		var region := mesh.region_ids[component[0]]
		var point := mesh.vertices[mesh.indices[component[0] * 3]]
		var depth := 0
		for j in components.size():
			if j != i and mesh.region_ids[components[j][0]] == region and Contact.contains(mesh, components[j], point):
				depth += 1
		var volume := mesh.component_volume(component)
		if not is_finite(volume) or volume == 0.0 or (volume > 0.0) != (depth % 2 == 0):
			return PackedStringArray(["Region %d shell %d has incorrect orientation at nesting depth %d (volume %s)" % [region, i, depth, volume]])
	return PackedStringArray()
