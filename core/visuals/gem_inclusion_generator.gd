class_name GemInclusionGenerator
extends RefCounted

## Generates discrete inclusion geometry (needles, plates, crystals, fingerprints)
## and merges them into an existing GemMeshResource. Each facet is added with
## zone "inclusion" so the native tracer can distinguish inclusion surfaces from
## gem facet surfaces during transport.


## Generate inclusion geometry from profile and merge into mesh.
## mesh: GemMeshResource to add facets to.
## profile: GemInclusionProfile defining the inclusion parameters.
## bounding_radius: radius of the gem mesh (kept for API compat, AABB used internally).
## seed_base: base seed for deterministic RNG.
static func generate_and_merge(mesh: Resource, profile: Resource, bounding_radius: float, seed_base: int = 42) -> void:
	if mesh == null or profile == null:
		return
	if bounding_radius <= 0.0:
		bounding_radius = 0.5

	var count := int(lerpf(float(profile.count_range.x), float(profile.count_range.y), profile.density))
	count = maxi(count, 0)
	if count == 0:
		return

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_base + profile.seed_offset

	# Compute safe AABB from the gem mesh (before inclusions are added).
	# Shrink each axis by 20% to keep inclusions well inside the gem volume.
	# This replaces the old spherical containment which didn't account for
	# non-spherical gem shapes (marquise, pear, kite, etc.).
	var gem_aabb: AABB = mesh.compute_bounds()
	var margin := gem_aabb.size * 0.2
	var safe_min := gem_aabb.position + margin
	var safe_max := gem_aabb.end - margin
	var safe_aabb := AABB(safe_min, safe_max - safe_min)
	if safe_aabb.size.x <= 0.0 or safe_aabb.size.y <= 0.0 or safe_aabb.size.z <= 0.0:
		# Gem is too small for inclusions after margin — fall back to 10% margin
		margin = gem_aabb.size * 0.1
		safe_min = gem_aabb.position + margin
		safe_max = gem_aabb.end - margin
		safe_aabb = AABB(safe_min, safe_max - safe_min)
		if safe_aabb.size.x <= 0.0 or safe_aabb.size.y <= 0.0 or safe_aabb.size.z <= 0.0:
			return

	var inclusion_type: StringName = profile.inclusion_type

	for _i in count:
		var pos := _random_point_in_aabb(rng, safe_aabb)

		# Random orientation based on axis + spread
		var orient := _random_orientation(rng, profile.orientation_axis, profile.orientation_spread)

		# Random size
		var size := lerpf(profile.size_range.x, profile.size_range.y, rng.randf())

		# Fingerprints are clusters of sub-crystals, each with its own center.
		# Handle them separately so each sub-crystal gets correct normal orientation.
		if inclusion_type == &"fingerprints":
			var groups := _generate_fingerprint_groups(size, orient, pos, rng)
			for group in groups:
				var sub_facets: Array[PackedVector3Array] = group["facets"]
				var sub_center: Vector3 = group["center"]
				if _all_vertices_in_aabb(sub_facets, safe_aabb):
					for verts in sub_facets:
						mesh.add_facet(verts, "inclusion", sub_center)
			continue

		# Non-fingerprint types: single inclusion with center = pos
		var facets: Array[PackedVector3Array] = []
		match inclusion_type:
			&"needles":
				facets = _generate_needle(size, orient, pos)
			&"crystals":
				facets = _generate_crystal(size, orient, pos)
			&"plates":
				facets = _generate_plate(size, orient, pos)
			_:
				facets = _generate_crystal(size, orient, pos)

		# Validate all vertices are within the safe AABB before adding
		if _all_vertices_in_aabb(facets, safe_aabb):
			for verts in facets:
				mesh.add_facet(verts, "inclusion", pos)


# ---------------------------------------------------------------------------
# Geometry generators
# ---------------------------------------------------------------------------

## Hexagonal prism (needle): 6 side quads (12 tris) + 2 hex caps (12 tris) = ~24 tris.
## Length = size * 3, radius = size * 0.15.
static func _generate_needle(size: float, basis: Basis, pos: Vector3) -> Array[PackedVector3Array]:
	var facets: Array[PackedVector3Array] = []
	var length := size * 3.0
	var radius := size * 0.15
	var half_len := length * 0.5

	# 6 vertices on each cap
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	top.resize(6)
	bot.resize(6)
	for i in 6:
		var angle := float(i) * TAU / 6.0
		var x := cos(angle) * radius
		var y := sin(angle) * radius
		top[i] = basis * Vector3(x, y, half_len) + pos
		bot[i] = basis * Vector3(x, y, -half_len) + pos

	# Side quads (each split into 2 triangles)
	for i in 6:
		var j := (i + 1) % 6
		# Triangle 1: top[i], bot[i], bot[j]
		var tri1 := PackedVector3Array([top[i], bot[i], bot[j]])
		facets.append(tri1)
		# Triangle 2: top[i], bot[j], top[j]
		var tri2 := PackedVector3Array([top[i], bot[j], top[j]])
		facets.append(tri2)

	# Top cap (fan from center)
	var top_center := Vector3.ZERO
	for v in top:
		top_center += v
	top_center /= 6.0
	for i in 6:
		var j := (i + 1) % 6
		facets.append(PackedVector3Array([top_center, top[i], top[j]]))

	# Bottom cap (fan from center, reversed winding)
	var bot_center := Vector3.ZERO
	for v in bot:
		bot_center += v
	bot_center /= 6.0
	for i in 6:
		var j := (i + 1) % 6
		facets.append(PackedVector3Array([bot_center, bot[j], bot[i]]))

	return facets


## Octahedron (crystal): 8 triangular faces.
static func _generate_crystal(size: float, basis: Basis, pos: Vector3) -> Array[PackedVector3Array]:
	var facets: Array[PackedVector3Array] = []
	var s := size

	var verts: Array[Vector3] = [
		basis * Vector3(0, 0, s) + pos,   # 0: +Z
		basis * Vector3(s, 0, 0) + pos,   # 1: +X
		basis * Vector3(0, s, 0) + pos,   # 2: +Y
		basis * Vector3(-s, 0, 0) + pos,  # 3: -X
		basis * Vector3(0, -s, 0) + pos,  # 4: -Y
		basis * Vector3(0, 0, -s) + pos,  # 5: -Z
	]

	var faces := [
		[0, 1, 2], [0, 2, 3], [0, 3, 4], [0, 4, 1],
		[5, 2, 1], [5, 3, 2], [5, 4, 3], [5, 1, 4],
	]

	for face in faces:
		facets.append(PackedVector3Array([verts[face[0]], verts[face[1]], verts[face[2]]]))

	return facets


## Flat hexagonal disc (plate): top + bottom hex faces (12 tris each) = 24 tris.
## Radius = size, thickness = size * 0.1.
static func _generate_plate(size: float, basis: Basis, pos: Vector3) -> Array[PackedVector3Array]:
	var facets: Array[PackedVector3Array] = []
	var radius := size
	var half_thick := size * 0.05  # half thickness

	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	top.resize(6)
	bot.resize(6)
	for i in 6:
		var angle := float(i) * TAU / 6.0
		var x := cos(angle) * radius
		var y := sin(angle) * radius
		top[i] = basis * Vector3(x, y, half_thick) + pos
		bot[i] = basis * Vector3(x, y, -half_thick) + pos

	# Top face (fan)
	var top_center := basis * Vector3(0, 0, half_thick) + pos
	for i in 6:
		var j := (i + 1) % 6
		facets.append(PackedVector3Array([top_center, top[i], top[j]]))

	# Bottom face (fan, reversed winding)
	var bot_center := basis * Vector3(0, 0, -half_thick) + pos
	for i in 6:
		var j := (i + 1) % 6
		facets.append(PackedVector3Array([bot_center, bot[j], bot[i]]))

	# Side quads
	for i in 6:
		var j := (i + 1) % 6
		facets.append(PackedVector3Array([top[i], bot[i], bot[j]]))
		facets.append(PackedVector3Array([top[i], bot[j], top[j]]))

	return facets


## Cluster of 5-8 small octahedra arranged in a disc (fingerprint).
## Returns an Array of Dictionaries: [{"facets": Array[PackedVector3Array], "center": Vector3}]
## so each sub-crystal can be oriented relative to its own center.
static func _generate_fingerprint_groups(size: float, basis: Basis, pos: Vector3, rng: RandomNumberGenerator) -> Array:
	var groups: Array = []
	var sub_count := rng.randi_range(5, 8)
	var cluster_radius := size * 0.6
	var sub_size := size * 0.25

	for i in sub_count:
		# Arrange sub-inclusions in a disc pattern with some randomness
		var angle := float(i) * TAU / float(sub_count) + rng.randf() * 0.4
		var r := cluster_radius * (0.3 + rng.randf() * 0.7)
		var offset := basis * Vector3(cos(angle) * r, sin(angle) * r, (rng.randf() - 0.5) * size * 0.1)
		var sub_pos := pos + offset

		# Small random orientation perturbation
		var sub_basis := basis * Basis(Vector3(rng.randf() - 0.5, rng.randf() - 0.5, rng.randf() - 0.5).normalized(), rng.randf() * 0.3)

		var sub_facets := _generate_crystal(sub_size, sub_basis, sub_pos)
		groups.append({"facets": sub_facets, "center": sub_pos})

	return groups


# ---------------------------------------------------------------------------
# Utility
# ---------------------------------------------------------------------------

## Random point uniformly distributed inside a sphere.
static func _random_point_in_sphere(rng: RandomNumberGenerator, radius: float) -> Vector3:
	# Rejection sampling
	for _attempt in 100:
		var v := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0),
		)
		if v.length_squared() <= 1.0:
			return v * radius
	return Vector3.ZERO


## Random point uniformly distributed inside an AABB.
static func _random_point_in_aabb(rng: RandomNumberGenerator, aabb: AABB) -> Vector3:
	return Vector3(
		lerpf(aabb.position.x, aabb.end.x, rng.randf()),
		lerpf(aabb.position.y, aabb.end.y, rng.randf()),
		lerpf(aabb.position.z, aabb.end.z, rng.randf()),
	)


## Check that all vertices in the given facets array are within the AABB.
static func _all_vertices_in_aabb(facets: Array[PackedVector3Array], aabb: AABB) -> bool:
	for verts in facets:
		for v in verts:
			if not aabb.has_point(v):
				return false
	return true


## Build a Basis oriented toward the given axis with angular spread.
## spread=0: perfectly aligned to axis. spread=1: fully random orientation.
static func _random_orientation(rng: RandomNumberGenerator, axis: Vector3, spread: float) -> Basis:
	if axis.is_zero_approx():
		axis = Vector3.UP
	axis = axis.normalized()

	# Start with a basis aligned to the axis (axis = local Z)
	var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var right := up.cross(axis).normalized()
	up = axis.cross(right).normalized()
	var base_basis := Basis(right, up, axis)

	if spread <= 0.001:
		return base_basis

	# Apply random tilt proportional to spread
	var max_angle := spread * PI * 0.5
	var tilt_angle := rng.randf() * max_angle
	var tilt_axis := Vector3(cos(rng.randf() * TAU), sin(rng.randf() * TAU), 0.0).normalized()
	var tilt := Basis(tilt_axis, tilt_angle)

	# Apply random rotation around the main axis
	var spin := Basis(Vector3.FORWARD, rng.randf() * TAU)

	return base_basis * tilt * spin
