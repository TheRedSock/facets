class_name GemDefectCompiler
extends RefCounted
## Procedural defect geometry. These are correlated geometric constructions,
## not a stress solver. Optical transport resolves both sides of every boundary.
static func apply(compiled: Dictionary, condition: GemCondition, size_mm: float, optimize_cleavage := true) -> void:
	if condition == null or (condition.defects.is_empty() and condition.cleavage == null):
		return
	var enabled: Array[GemDefect] = []
	var geometries: Array[GemMesh] = []
	var descriptors: Array[GemDefect] = condition.defects.duplicate()
	if condition.cleavage != null:
		var event := GemCleavageCompiler.realize(compiled, compiled.get("shape_recipe"), size_mm, condition.cleavage, compiled.get("crystal_to_stone", Quaternion.IDENTITY))
		if not event.error.is_empty():
			compiled["compilation_error"] = event.error
			return
		compiled["condition_report"] = {"cleavage":event.report}
		if event.has("defect"):
			var other_enabled := false
			for descriptor in descriptors:
				other_enabled = other_enabled or (descriptor != null and descriptor.enabled)
			if optimize_cleavage and not other_enabled and not compiled.has("mesh") and not compiled.has("analytic_shape") and not compiled.planes.is_empty():
				_apply_convex_cleavage(compiled, event, size_mm)
				return
			descriptors.append(event.defect)
	for defect in descriptors:
		if defect.enabled:
			var surface := compile(defect, size_mm)
			if defect.kind == "fracture" and surface.vertices.is_empty():
				# A fully closed aperture contributes no separate material region.
				continue
			enabled.append(defect)
			geometries.append(surface)
	if enabled.is_empty():
		return
	assert(enabled.size() < GemBoundarySet.MAX_REGIONS, "Too many resolved material regions; use effective media for subpixel populations")
	var boundaries := GemBoundarySet.new()
	if compiled.has("analytic_shape"):
		var added := boundaries.add_cabochon(compiled["analytic_shape"], 0)
		assert(added, "Invalid analytic host")
	else:
		var host: GemMesh = compiled.get("mesh", null)
		if host == null:
			host = GemShapeCompiler.from_hull(compiled["planes"], compiled.get("facet_ids", PackedInt32Array()))
		var added := boundaries.add(host, 0)
		assert(added, "Invalid host for defect boundaries")
	var materials: Array[Dictionary] = []
	var surfaces: Array = compiled.get("surfaces", [GemSurface.new()])
	for index in enabled.size():
		var defect := enabled[index]
		var surface := geometries[index]
		var material_id := -1
		if defect.filling != null:
			materials.append(GemMaterialCompiler.compile(defect.filling))
			material_id = materials.size()
		var added := boundaries.add(surface, material_id)
		assert(added, "Invalid physical defect: %s" % surface.validate())
		surfaces.append(defect.finish if defect.finish != null else GemSurface.new())
	compiled["boundaries"] = boundaries
	compiled["region_materials"] = materials
	compiled["surfaces"] = surfaces
	compiled["mesh"] = boundaries.mesh
	compiled["planes"] = PackedFloat32Array()

static func compile(defect: GemDefect, size_mm: float) -> GemMesh:
	assert(is_finite(size_mm) and size_mm > 0.0 and defect.half_extent_mm.is_finite())
	var extent := defect.half_extent_mm
	if extent.x <= 0.0 or extent.y <= 0.0 or extent.z <= 0.0:
		return GemMesh.new()
	if defect.kind == "cleavage":
		var mesh := GemShapeCompiler.loft(PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]),PackedVector2Array([Vector2(-1,1),Vector2(1,1)]))
		for i in mesh.vertices.size():
			mesh.vertices[i] = (defect.center_mm+defect.orientation*(mesh.vertices[i]*extent))/size_mm
		return mesh
	if defect.kind == "fracture":
		return GemFractureCompiler.compile(defect, size_mm)
	var points := PackedVector2Array()
	var phase := TAU * sample(defect.seed, 0)
	var count := defect.radial_segments
	for index in count:
		var angle := TAU * index / count
		# A correlated advancing front, rather than scattered circles or lines.
		var radius := 1.0 + defect.irregularity * (0.16 * sin(3.0 * angle + phase) + 0.07 * sin(7.0 * angle - phase))
		points.append(Vector2(cos(angle), sin(angle)) * radius)
	var sections := PackedVector2Array()
	if defect.kind == "crystal":
		points = PackedVector2Array()
		for index in 6:
			points.append(Vector2(cos(TAU * index / 6), sin(TAU * index / 6)))
		sections = PackedVector2Array([Vector2(-1, 0), Vector2(-0.65, 1), Vector2(0.65, 1), Vector2(1, 0)])
	else:
		sections.append(Vector2(-1, 0))
		for ring in range(1, defect.radial_rings * 2):
			var angle := -PI * 0.5 + PI * ring / (defect.radial_rings * 2)
			sections.append(Vector2(sin(angle), cos(angle)))
		sections.append(Vector2(1, 0))
	var mesh := GemShapeCompiler.loft(points, sections)
	for index in mesh.vertices.size():
		var p := mesh.vertices[index]
		# Shared long-scale corrugation of the chip cavity.
		if defect.kind != "crystal":
			p.z += defect.irregularity * 0.7 * sin(4.5 * p.x + phase) * sin(3.2 * p.y - phase)
		mesh.vertices[index] = (defect.center_mm + defect.orientation * (p * extent)) / size_mm
	return mesh

## Stable deterministic recipe sample, independent of gameplay RNG.
static func sample(seed_value: int, dimension: int) -> float:
	var value := (seed_value * 747796405 + dimension * 2891336453 + 1013904223) & 0x7fffffff
	value = ((value ^ (value >> 16)) * 2246822519) & 0x7fffffff
	return float(value) / 2147483648.0

## Select a real exposed edge and place a flake cavity across it. Hardness is
## intentionally absent: chipping depends on impact/toughness and cleavage,
## not the Mohs scratch scale. Species-specific fracture recipes follow later.
static func edge_chip(compiled: Dictionary, size_mm: float, seed_value: int, radius_mm: float, depth_mm: float) -> GemDefect:
	var mesh: GemMesh = compiled.get("mesh", null)
	if mesh == null:
		mesh = GemShapeCompiler.from_hull(compiled["planes"])
	var edges := {}
	for triangle in mesh.triangle_count():
		var a := mesh.indices[triangle * 3]
		var b := mesh.indices[triangle * 3 + 1]
		var c := mesh.indices[triangle * 3 + 2]
		var normal := (mesh.vertices[b] - mesh.vertices[a]).cross(mesh.vertices[c] - mesh.vertices[a]).normalized()
		for edge in [Vector2i(a, b), Vector2i(b, c), Vector2i(c, a)]:
			var key := Vector2i(mini(edge.x, edge.y), maxi(edge.x, edge.y))
			if not edges.has(key):
				edges[key] = []
			edges[key].append(normal)
	var candidates := []
	var total := 0.0
	for key: Vector2i in edges:
		var normals: Array = edges[key]
		if normals.size() != 2 or normals[0].dot(normals[1]) > 0.98:
			continue
		var a := mesh.vertices[key.x]
		var b := mesh.vertices[key.y]
		var center := (a + b) * 0.5
		# More exposed girdle edges receive more impacts; all selection is in
		# physical object space and independent of camera or lighting.
		var weight: float = a.distance_to(b) * (1.0 - normals[0].dot(normals[1])) / (0.1 + absf(center.z))
		total += weight
		candidates.append({"edge": key, "normal": (normals[0] + normals[1]).normalized(), "end": total})
	if candidates.is_empty():
		return null
	var target := sample(seed_value, 1) * total
	var selected: Dictionary = candidates[-1]
	for candidate: Dictionary in candidates:
		if target <= candidate["end"]:
			selected = candidate
			break
	var edge: Vector2i = selected["edge"]
	var position := mesh.vertices[edge.x].lerp(mesh.vertices[edge.y], 0.2 + sample(seed_value, 2) * 0.6)
	var normal: Vector3 = selected["normal"]
	var along := (mesh.vertices[edge.y] - mesh.vertices[edge.x]).normalized()
	var defect := GemDefect.new()
	defect.kind = "chip"
	defect.seed = seed_value
	defect.half_extent_mm = Vector3(radius_mm, radius_mm * 0.7, depth_mm)
	defect.center_mm = position * size_mm + normal * depth_mm * 0.15
	defect.orientation = Basis(along, normal.cross(along).normalized(), normal).orthonormalized().get_rotation_quaternion()
	return defect

## Intersecting a convex body with one retained cleavage half-space remains
## convex. Keep the exact facet program and give the new face its own finish
## and semantic slot. The region backend remains the independent comparison
## path and handles nonconvex hosts or additional physical defects.
static func _apply_convex_cleavage(compiled: Dictionary, event: Dictionary, size_mm: float) -> void:
	var planes: PackedFloat32Array = compiled.planes.duplicate()
	var ids: PackedInt32Array = compiled.get("facet_ids", PackedInt32Array()).duplicate()
	var slots := PackedInt32Array()
	slots.resize(planes.size()/8)
	if ids.size() != slots.size():
		ids.resize(slots.size())
		for i in ids.size(): ids[i]=i
	var values: Array = event.report.normal_stone
	planes.append_array(PackedFloat32Array([values[0],values[1],values[2],event.report.plane_offset_mm/size_mm,0,0,0,0]))
	ids.append(-1) # Matches the negative-z cap of the reference air cutter.
	slots.append(1)
	var surfaces: Array = compiled.get("surfaces", [GemSurface.new()]).duplicate()
	surfaces.append(event.defect.finish if event.defect.finish != null else GemSurface.new())
	compiled["planes"]=planes
	compiled["facet_ids"]=ids
	compiled["plane_surface_ids"]=slots
	compiled["surfaces"]=surfaces
	compiled["geometry_backend"]="convex_cleavage"
