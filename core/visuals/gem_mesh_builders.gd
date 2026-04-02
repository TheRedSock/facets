class_name GemMeshBuilders
extends RefCounted

## Shared 3D mesh builders for runtime-baked gem prototypes.

const GemMeshResourceScript = preload("res://resources/visuals/gem_mesh_resource.gd")
const DEFAULT_RADIUS := 0.48
const DEFAULT_ROTATION := -PI * 0.5
const MIN_GENERIC_NORMAL_Z := 0.08
const MAX_GENERIC_CROWN_HEIGHT := 0.26
const BOUNDARY_EPSILON := 0.0025
const FORCE_MIRRORED_CROWN_PAVILION_BASELINE := true


static func build_round_brilliant_mesh(profile: Dictionary):
	var mesh = GemMeshResourceScript.new()
	mesh.cut_id = profile.get("cut_id", &"")
	mesh.display_name = profile.get("display_name", "")
	var crown_polygons_3d: Array[PackedVector3Array] = []
	var crown_zones: Array[StringName] = []

	var sector_count := int(profile.get("sector_count", 8))
	if sector_count < 3:
		return mesh

	var radius := float(profile.get("mesh_radius", DEFAULT_RADIUS))
	var table_ratio := float(profile.get("table_ratio", 0.5))
	var star_ratio := float(profile.get("star_ratio", lerpf(
		table_ratio,
		1.0,
		float(profile.get("star_length", 0.55))
	)))
	var crown_height := float(profile.get("crown_height", _default_crown_height(table_ratio)))
	var star_height := crown_height * float(profile.get("star_height_ratio", 0.62))
	var pavilion_depth := float(profile.get("pavilion_depth", crown_height * 1.9))
	var pavilion_ring_height := -pavilion_depth * float(profile.get("pavilion_ring_height_ratio", 0.48))
	var pavilion_ring_radius := radius * float(profile.get("pavilion_ring_radius_scale", 0.34))

	var main_angles := _regular_angles(sector_count, DEFAULT_ROTATION)
	var half_angles := _half_angles(main_angles)

	var table_ring := _sample_ring(main_angles, radius * table_ratio, crown_height)
	var star_ring := _sample_ring(half_angles, radius * star_ratio, star_height)
	var girdle_main := _sample_ring(main_angles, radius, 0.0)
	var girdle_half := _sample_ring(half_angles, radius, 0.0)
	var pavilion_ring := _sample_ring(half_angles, pavilion_ring_radius, pavilion_ring_height)
	var culet := Vector3(0.0, 0.0, -pavilion_depth)
	var count := table_ring.size()

	var table_polygon := PackedVector3Array(table_ring)
	crown_polygons_3d.append(table_polygon)
	crown_zones.append(&"table")
	mesh.add_facet(table_polygon, "table")

	for i in count:
		var next_index := (i + 1) % count
		var star_polygon := PackedVector3Array([
			table_ring[i],
			star_ring[i],
			table_ring[next_index],
		])
		crown_polygons_3d.append(star_polygon)
		crown_zones.append(&"star")
		mesh.add_facet(star_polygon, "star")

	for i in count:
		var prev_index := (i - 1 + count) % count
		var bezel_polygon := PackedVector3Array([
			star_ring[prev_index],
			table_ring[i],
			star_ring[i],
			girdle_main[i],
		])
		crown_polygons_3d.append(bezel_polygon)
		crown_zones.append(&"bezel")
		mesh.add_facet(bezel_polygon, "bezel")

	for i in count:
		var next_index := (i + 1) % count
		var left_girdle := PackedVector3Array([
			star_ring[i],
			girdle_main[i],
			girdle_half[i],
		])
		crown_polygons_3d.append(left_girdle)
		crown_zones.append(&"girdle")
		mesh.add_facet(left_girdle, "girdle")
		var right_girdle := PackedVector3Array([
			star_ring[i],
			girdle_half[i],
			girdle_main[next_index],
		])
		crown_polygons_3d.append(right_girdle)
		crown_zones.append(&"girdle")
		mesh.add_facet(right_girdle, "girdle")

	if FORCE_MIRRORED_CROWN_PAVILION_BASELINE:
		_append_mirrored_crown_pavilion(mesh, crown_polygons_3d, crown_zones)
		return mesh

	for i in count:
		var prev_index := (i - 1 + count) % count
		var next_index := (i + 1) % count
		mesh.add_facet(PackedVector3Array([
			girdle_main[i],
			pavilion_ring[prev_index],
			girdle_half[prev_index],
		]), "pavilion")
		mesh.add_facet(PackedVector3Array([
			girdle_main[i],
			girdle_half[i],
			pavilion_ring[i],
		]), "pavilion")
		mesh.add_facet(PackedVector3Array([
			pavilion_ring[i],
			culet,
			pavilion_ring[next_index],
		]), "culet")

	return mesh


static func build_mesh_from_cut(cut: GemCutResource):
	var mesh = GemMeshResourceScript.new()
	if cut == null:
		return mesh
	mesh.cut_id = cut.cut_id
	mesh.display_name = cut.display_name
	var boundary_radius := _compute_boundary_radius(cut)
	var solved := _solve_crown_vertex_heights(cut, boundary_radius)
	var heights: Dictionary = solved.get("heights", {})
	var crown_height := float(solved.get("crown_height", 0.18))
	var crown_polygons_3d: Array[PackedVector3Array] = []
	var crown_zones: Array[StringName] = []
	for facet_index in cut.facet_vertices.size():
		var polygon_2d: PackedVector2Array = cut.facet_vertices[facet_index]
		var polygon_3d := PackedVector3Array()
		for point in polygon_2d:
			var mesh_xy := _to_mesh_xy(point)
			polygon_3d.append(Vector3(
				mesh_xy.x,
				mesh_xy.y,
				float(heights.get(_point_key(point), 0.0))
			))
		var zone := cut.facet_zones[facet_index] if facet_index < cut.facet_zones.size() else ""
		crown_polygons_3d.append(polygon_3d)
		crown_zones.append(StringName(zone))
		mesh.add_facet(polygon_3d, zone)
	if FORCE_MIRRORED_CROWN_PAVILION_BASELINE:
		_append_mirrored_crown_pavilion(mesh, crown_polygons_3d, crown_zones)
		return mesh
	var pavilion_type := _detect_pavilion_type(cut)
	match pavilion_type:
		&"step":
			_append_step_pavilion(mesh, cut, crown_height)
		&"rose":
			_append_shallow_pavilion(mesh, cut)
		_ when _can_build_trillion_pavilion(cut):
			_append_trillion_pavilion(mesh, cut, crown_polygons_3d, crown_zones)
		_ when _can_build_standard_brilliant_pavilion(cut):
			_append_standard_brilliant_pavilion(mesh, cut, crown_height, crown_polygons_3d, crown_zones)
		_:
			_append_generic_pavilion(mesh, cut, crown_polygons_3d, crown_zones, crown_height)
	return mesh


static func uses_mirrored_crown_pavilion_baseline() -> bool:
	return FORCE_MIRRORED_CROWN_PAVILION_BASELINE


static func _default_crown_height(table_ratio: float) -> float:
	var compactness := clampf((0.58 - table_ratio) / 0.18, 0.0, 1.0)
	return lerpf(0.16, 0.24, compactness)


static func _detect_pavilion_type(cut: GemCutResource) -> StringName:
	for zone in cut.facet_zones:
		if zone == "step":
			return &"step"
		if zone == "rose" or zone == "rose_center":
			return &"rose"
	return &"brilliant"


static func _append_step_pavilion(mesh: GemMeshResource, cut: GemCutResource, crown_height: float) -> void:
	var boundary := _sanitize_loop(cut.silhouette)
	if boundary.size() < 3:
		return
	var pavilion_depth := maxf(0.32, crown_height * 2.0 + 0.08)
	var step_scales := [1.0, 0.66, 0.36]
	var step_depths := [0.0, -pavilion_depth * 0.45, -pavilion_depth * 0.82]
	var rotation_angle := _pavilion_rotation_angle(cut)
	var rings: Array = []
	for step_index in step_scales.size():
		var ring: Array[Vector3] = []
		var scale_factor: float = step_scales[step_index]
		var z: float = step_depths[step_index]
		for point in boundary:
			if step_index == 0:
				var mesh_xy := _to_mesh_xy(point)
				ring.append(Vector3(mesh_xy.x, mesh_xy.y, z))
			else:
				ring.append(_project_pavilion_point(point, scale_factor, z, rotation_angle))
		rings.append(ring)
	var culet := Vector3(0.0, 0.0, -pavilion_depth)
	for ring_index in rings.size() - 1:
		var outer: Array = rings[ring_index]
		var inner: Array = rings[ring_index + 1]
		for point_index in outer.size():
			var next_index := (point_index + 1) % outer.size()
			mesh.add_facet(PackedVector3Array([
				outer[point_index],
				outer[next_index],
				inner[next_index],
				inner[point_index],
			]), "pavilion")
	var inner_ring: Array = rings[rings.size() - 1]
	for point_index in inner_ring.size():
		var next_index := (point_index + 1) % inner_ring.size()
		mesh.add_facet(PackedVector3Array([
			inner_ring[point_index],
			inner_ring[next_index],
			culet,
		]), "culet")


static func _append_shallow_pavilion(mesh: GemMeshResource, cut: GemCutResource) -> void:
	var boundary := _sanitize_loop(cut.silhouette)
	if boundary.size() < 3:
		return
	var shallow_depth := 0.06
	var boundary_ring: Array[Vector3] = []
	for point in boundary:
		var mesh_xy := _to_mesh_xy(point)
		boundary_ring.append(Vector3(mesh_xy.x, mesh_xy.y, 0.0))
	var center_point := Vector3(0.0, 0.0, -shallow_depth)
	for index in boundary_ring.size():
		var next_index := (index + 1) % boundary_ring.size()
		mesh.add_facet(PackedVector3Array([
			boundary_ring[index],
			boundary_ring[next_index],
			center_point,
		]), "pavilion")


static func _can_build_standard_brilliant_pavilion(cut: GemCutResource) -> bool:
	if cut == null:
		return false
	match cut.shape_category:
		&"oval", &"pear", &"square", &"diamond", &"hexagon", &"pentagon", &"marquise":
			pass
		_:
			return false
	if cut.facet_vertices.is_empty():
		return false
	var count := cut.facet_vertices[0].size()
	if count < 4 or cut.facet_count() != 1 + count * 4:
		return false
	if cut.facet_zones.is_empty() or cut.facet_zones[0] != "table":
		return false
	return true


static func _can_build_trillion_pavilion(cut: GemCutResource) -> bool:
	return cut != null and cut.shape_category == &"triangle" and not cut.facet_vertices.is_empty()


static func _append_trillion_pavilion(
	mesh: GemMeshResource,
	cut: GemCutResource,
	crown_polygons_3d: Array[PackedVector3Array],
	crown_zones: Array[StringName],
) -> void:
	if cut == null:
		return
	var crown_height := 0.0
	for polygon in crown_polygons_3d:
		for vertex in polygon:
			crown_height = maxf(crown_height, vertex.z)
	_append_generic_pavilion(mesh, cut, crown_polygons_3d, crown_zones, crown_height)


static func _append_standard_brilliant_pavilion(
	mesh: GemMeshResource,
	cut: GemCutResource,
	crown_height: float,
	crown_polygons_3d: Array[PackedVector3Array],
	crown_zones: Array[StringName],
) -> void:
	var crown_rings := _extract_standard_brilliant_rings(cut)
	if crown_rings.is_empty():
		_append_generic_pavilion(mesh, cut, crown_polygons_3d, crown_zones, crown_height)
		return
	var girdle_main: Array[Vector2] = crown_rings.get("girdle_main", [])
	var girdle_half: Array[Vector2] = crown_rings.get("girdle_half", [])
	if girdle_main.is_empty() or girdle_half.is_empty():
		_append_generic_pavilion(mesh, cut, crown_polygons_3d, crown_zones, crown_height)
		return
	var count := girdle_main.size()
	var pavilion_depth := maxf(0.42, crown_height * 2.05 + 0.10)
	var upper_scale := clampf(cut.pavilion_scale * 0.39, 0.24, 0.42)
	var lower_scale := clampf(upper_scale * 0.42, 0.10, 0.18)
	var upper_z := -pavilion_depth * 0.50
	var lower_z := -pavilion_depth * 0.84
	var girdle_main_3d := _ring_to_mesh_points(girdle_main, 1.0, 0.0)
	var girdle_half_3d := _ring_to_mesh_points(girdle_half, 1.0, 0.0)
	var upper_ring := _ring_to_mesh_points(girdle_half, upper_scale, upper_z)
	var lower_ring := _ring_to_mesh_points(girdle_half, lower_scale, lower_z)
	var culet := Vector3(0.0, 0.0, -pavilion_depth)
	for i in count:
		var prev_index := (i - 1 + count) % count
		var next_index := (i + 1) % count
		mesh.add_facet(PackedVector3Array([
			girdle_main_3d[i],
			upper_ring[prev_index],
			girdle_half_3d[prev_index],
		]), "pavilion")
		mesh.add_facet(PackedVector3Array([
			girdle_main_3d[i],
			girdle_half_3d[i],
			upper_ring[i],
		]), "pavilion")
		mesh.add_facet(PackedVector3Array([
			upper_ring[i],
			lower_ring[i],
			lower_ring[next_index],
			upper_ring[next_index],
		]), "pavilion")
		mesh.add_facet(PackedVector3Array([
			lower_ring[i],
			culet,
			lower_ring[next_index],
		]), "culet")


static func _regular_angles(count: int, rotation: float = DEFAULT_ROTATION) -> Array[float]:
	var angles: Array[float] = []
	for i in count:
		angles.append(rotation + TAU * float(i) / float(count))
	return angles


static func _half_angles(angles: Array[float]) -> Array[float]:
	var half_angles: Array[float] = []
	if angles.is_empty():
		return half_angles
	for i in angles.size():
		var next_index := (i + 1) % angles.size()
		var current := angles[i]
		var next_angle := angles[next_index]
		if next_index == 0:
			next_angle += TAU
		half_angles.append(lerpf(current, next_angle, 0.5))
	return half_angles


static func _sample_ring(angles: Array[float], radius: float, z: float) -> Array[Vector3]:
	var ring: Array[Vector3] = []
	for angle in angles:
		ring.append(Vector3(cos(angle) * radius, sin(angle) * radius, z))
	return ring


static func _solve_crown_vertex_heights(cut: GemCutResource, boundary_radius: float) -> Dictionary:
	var height_sum: Dictionary = {}
	var height_count: Dictionary = {}
	var fallback_height: Dictionary = {}
	var boundary_keys: Dictionary = {}
	for facet_index in cut.facet_vertices.size():
		var polygon: PackedVector2Array = cut.facet_vertices[facet_index]
		if polygon.size() < 3:
			continue
		var zone := cut.facet_zones[facet_index] if facet_index < cut.facet_zones.size() else ""
		var normal: Vector3 = cut.facet_normals[facet_index] if facet_index < cut.facet_normals.size() else Vector3(0, 0, 1)
		if normal.z < MIN_GENERIC_NORMAL_Z:
			normal = Vector3(normal.x, normal.y, MIN_GENERIC_NORMAL_Z).normalized()
		var centroid_2d := cut.facet_centroids[facet_index] if facet_index < cut.facet_centroids.size() else _centroid_2d(polygon)
		var centroid_xy := _to_mesh_xy(centroid_2d)
		var radial := clampf(centroid_xy.length() / maxf(boundary_radius, 0.0001), 0.0, 1.0)
		var centroid_height := _estimate_zone_height(zone, radial, normal.z)
		var plane_d := normal.x * centroid_xy.x + normal.y * centroid_xy.y + normal.z * centroid_height
		for point in polygon:
			var key := _point_key(point)
			var point_xy := _to_mesh_xy(point)
			var point_radial := clampf(point_xy.length() / maxf(boundary_radius, 0.0001), 0.0, 1.0)
			var point_height := _estimate_zone_height(zone, point_radial, normal.z)
			fallback_height[key] = maxf(float(fallback_height.get(key, 0.0)), point_height)
			if _is_boundary_point(point, cut.silhouette):
				boundary_keys[key] = true
				continue
			var predicted_height := (plane_d - normal.x * point_xy.x - normal.y * point_xy.y) / normal.z
			predicted_height = clampf(predicted_height, 0.0, MAX_GENERIC_CROWN_HEIGHT)
			height_sum[key] = float(height_sum.get(key, 0.0)) + predicted_height
			height_count[key] = int(height_count.get(key, 0)) + 1
	var heights: Dictionary = {}
	var crown_height := 0.0
	for key in fallback_height.keys():
		if boundary_keys.has(key):
			heights[key] = 0.0
			continue
		var count := int(height_count.get(key, 0))
		var averaged := float(height_sum.get(key, 0.0)) / float(count) if count > 0 else 0.0
		var blended := lerpf(float(fallback_height[key]), averaged, 0.82) if count > 0 else float(fallback_height[key])
		var final_height := clampf(blended, 0.0, MAX_GENERIC_CROWN_HEIGHT)
		heights[key] = final_height
		crown_height = maxf(crown_height, final_height)
	return {
		"heights": heights,
		"crown_height": crown_height,
	}


static func _append_generic_pavilion(
	mesh: GemMeshResource,
	cut: GemCutResource,
	crown_polygons_3d: Array[PackedVector3Array],
	crown_zones: Array[StringName],
	crown_height: float = 0.18,
) -> void:
	if cut == null:
		_append_mirrored_crown_pavilion(mesh, crown_polygons_3d, crown_zones)
		return
	var boundary := _sanitize_loop(cut.silhouette)
	if boundary.size() < 3:
		_append_mirrored_crown_pavilion(mesh, crown_polygons_3d, crown_zones)
		return
	var overlay_scale := _estimate_pavilion_overlay_scale(cut, _compute_boundary_radius(cut))
	var upper_scale := clampf(lerpf(1.0, overlay_scale, 0.60), 0.46, 0.82)
	var lower_scale := clampf(overlay_scale * 0.82, 0.18, upper_scale - 0.06)
	var rotation_angle := 0.0
	var pavilion_depth := maxf(0.30, crown_height * 2.0 + 0.10)
	var upper_z := -pavilion_depth * 0.46
	var lower_z := -pavilion_depth * 0.82
	var outer_ring: Array[Vector3] = []
	var upper_ring: Array[Vector3] = []
	var lower_ring: Array[Vector3] = []
	for index in boundary.size():
		var point := boundary[index]
		var sharpness := _loop_vertex_sharpness(boundary, index)
		var point_upper_scale := clampf(upper_scale - sharpness * 0.06, 0.28, 0.96)
		var point_lower_scale := clampf(lower_scale - sharpness * 0.10, 0.18, point_upper_scale - 0.04)
		var mesh_xy := _to_mesh_xy(point)
		outer_ring.append(Vector3(mesh_xy.x, mesh_xy.y, 0.0))
		upper_ring.append(_project_pavilion_point(point, point_upper_scale, upper_z, rotation_angle))
		lower_ring.append(_project_pavilion_point(point, point_lower_scale, lower_z, rotation_angle))
	var culet := Vector3(0.0, 0.0, -pavilion_depth)
	for index in outer_ring.size():
		var next_index := (index + 1) % outer_ring.size()
		mesh.add_facet(PackedVector3Array([
			outer_ring[index],
			outer_ring[next_index],
			upper_ring[next_index],
			upper_ring[index],
		]), "pavilion")
		mesh.add_facet(PackedVector3Array([
			upper_ring[index],
			upper_ring[next_index],
			lower_ring[next_index],
			lower_ring[index],
		]), "pavilion")
		mesh.add_facet(PackedVector3Array([
			lower_ring[index],
			lower_ring[next_index],
			culet,
		]), "culet")


static func _append_mirrored_crown_pavilion(
	mesh: GemMeshResource,
	crown_polygons_3d: Array[PackedVector3Array],
	crown_zones: Array[StringName],
) -> void:
	if crown_polygons_3d.is_empty():
		return
	for i in crown_polygons_3d.size():
		var crown_polygon: PackedVector3Array = crown_polygons_3d[i]
		if crown_polygon.size() < 3:
			continue
		var mirrored := PackedVector3Array()
		mirrored.resize(crown_polygon.size())
		for j in crown_polygon.size():
			var vertex: Vector3 = crown_polygon[j]
			mirrored[j] = Vector3(vertex.x, vertex.y, -vertex.z)
		var crown_zone: StringName = crown_zones[i] if i < crown_zones.size() else &""
		var mirrored_zone := "culet" if crown_zone == &"table" else "pavilion"
		mesh.add_facet(mirrored, mirrored_zone)


static func _extract_standard_brilliant_rings(cut: GemCutResource) -> Dictionary:
	if cut == null or cut.facet_vertices.is_empty():
		return {}
	var table: PackedVector2Array = cut.facet_vertices[0]
	var count := table.size()
	if count < 4 or cut.facet_count() != 1 + count * 4:
		return {}
	var star_ring: Array[Vector2] = []
	var girdle_main: Array[Vector2] = []
	var girdle_half: Array[Vector2] = []
	for i in count:
		var star_facet: PackedVector2Array = cut.facet_vertices[1 + i]
		if star_facet.size() < 3:
			return {}
		star_ring.append(star_facet[1])
		var bezel_facet: PackedVector2Array = cut.facet_vertices[1 + count + i]
		if bezel_facet.size() < 4:
			return {}
		girdle_main.append(bezel_facet[bezel_facet.size() - 1])
		var left_girdle_facet: PackedVector2Array = cut.facet_vertices[1 + count * 2 + i * 2]
		if left_girdle_facet.size() < 3:
			return {}
		girdle_half.append(left_girdle_facet[left_girdle_facet.size() - 1])
	return {
		"table": _packed_to_array(table),
		"star": star_ring,
		"girdle_main": girdle_main,
		"girdle_half": girdle_half,
	}


static func _packed_to_array(points: PackedVector2Array) -> Array[Vector2]:
	var result: Array[Vector2] = []
	for point in points:
		result.append(point)
	return result


static func _ring_to_mesh_points(points: Array[Vector2], scale_factor: float, z: float) -> Array[Vector3]:
	var ring: Array[Vector3] = []
	for point in points:
		var delta := point - Vector2(0.5, 0.5)
		var mesh_xy := _to_mesh_xy(Vector2(0.5, 0.5) + delta * scale_factor)
		ring.append(Vector3(mesh_xy.x, mesh_xy.y, z))
	return ring


static func _estimate_zone_height(zone: String, radial: float, normal_z: float) -> float:
	var center_weight := 1.0 - clampf(radial, 0.0, 1.0)
	var zone_height := 0.08
	match zone:
		"table":
			zone_height = 0.22
		"star":
			zone_height = lerpf(0.12, 0.18, center_weight)
		"bezel":
			zone_height = lerpf(0.05, 0.12, center_weight)
		"step":
			zone_height = lerpf(0.02, 0.18, pow(center_weight, 0.85))
		"girdle":
			zone_height = 0.0
		"rose_center":
			zone_height = 0.24
		"rose":
			zone_height = lerpf(0.05, 0.2, center_weight)
		"pavilion", "culet":
			zone_height = 0.0
		_:
			zone_height = lerpf(0.04, 0.14, center_weight)
	var normal_scale := lerpf(0.86, 1.04, clampf(normal_z, 0.0, 1.0))
	return clampf(zone_height * normal_scale, 0.0, MAX_GENERIC_CROWN_HEIGHT)


static func _pavilion_rotation_angle(cut: GemCutResource) -> float:
	var sector_count := maxi(cut.pavilion_sector_count, 0)
	if sector_count <= 0:
		return 0.0
	return TAU / float(sector_count) * cut.pavilion_rotation_fraction


static func _estimate_pavilion_overlay_scale(cut: GemCutResource, boundary_radius: float) -> float:
	if boundary_radius <= 0.0001:
		return clampf(cut.pavilion_scale * 0.52, 0.36, 0.76)
	var overlay_radius := 0.0
	for polygon in cut.pavilion_vertices:
		for point in polygon:
			overlay_radius = maxf(overlay_radius, _to_mesh_xy(point).length())
	if overlay_radius <= 0.0001:
		return clampf(cut.pavilion_scale * 0.52, 0.36, 0.76)
	return clampf(overlay_radius / boundary_radius, 0.36, 0.8)


static func _project_pavilion_point(
	point: Vector2,
	scale_factor: float,
	z: float,
	rotation_angle: float,
) -> Vector3:
	var delta := point - Vector2(0.5, 0.5)
	var cos_r := cos(rotation_angle)
	var sin_r := sin(rotation_angle)
	var scaled := delta * scale_factor
	var rotated := Vector2(
		scaled.x * cos_r - scaled.y * sin_r,
		scaled.x * sin_r + scaled.y * cos_r
	)
	var mesh_xy := _to_mesh_xy(Vector2(0.5, 0.5) + rotated)
	return Vector3(mesh_xy.x, mesh_xy.y, z)


static func _loop_vertex_sharpness(loop: PackedVector2Array, index: int) -> float:
	if loop.size() < 3:
		return 0.0
	var prev_index := (index - 1 + loop.size()) % loop.size()
	var next_index := (index + 1) % loop.size()
	var incoming := (loop[index] - loop[prev_index]).normalized()
	var outgoing := (loop[next_index] - loop[index]).normalized()
	if incoming.is_zero_approx() or outgoing.is_zero_approx():
		return 0.0
	var turn := clampf((1.0 - incoming.dot(outgoing)) * 0.5, 0.0, 1.0)
	return pow(turn, 0.7)


static func _compute_boundary_radius(cut: GemCutResource) -> float:
	var points: PackedVector2Array = cut.silhouette
	if points.is_empty():
		for polygon in cut.facet_vertices:
			for point in polygon:
				points.append(point)
	var radius := 0.0
	for point in points:
		radius = maxf(radius, _to_mesh_xy(point).length())
	return maxf(radius, 0.3)


static func _sanitize_loop(points: PackedVector2Array) -> PackedVector2Array:
	var cleaned := PackedVector2Array()
	for point in points:
		if cleaned.is_empty() or cleaned[cleaned.size() - 1].distance_squared_to(point) > 0.000001:
			cleaned.append(point)
	if cleaned.size() >= 2 and cleaned[0].distance_squared_to(cleaned[cleaned.size() - 1]) <= 0.000001:
		cleaned.remove_at(cleaned.size() - 1)
	return cleaned


static func _is_boundary_point(point: Vector2, boundary: PackedVector2Array) -> bool:
	var loop := _sanitize_loop(boundary)
	if loop.size() < 2:
		return false
	var epsilon_sq := BOUNDARY_EPSILON * BOUNDARY_EPSILON
	for index in loop.size():
		var next_index := (index + 1) % loop.size()
		if _distance_squared_to_segment(point, loop[index], loop[next_index]) <= epsilon_sq:
			return true
	return false


static func _distance_squared_to_segment(point: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.0000001:
		return point.distance_squared_to(a)
	var t := clampf((point - a).dot(ab) / denom, 0.0, 1.0)
	return point.distance_squared_to(a + ab * t)


static func _centroid_2d(points: PackedVector2Array) -> Vector2:
	var centroid := Vector2.ZERO
	for point in points:
		centroid += point
	return centroid / float(maxi(points.size(), 1))


static func _to_mesh_xy(point: Vector2) -> Vector2:
	return Vector2(point.x - 0.5, 0.5 - point.y)


static func _point_key(point: Vector2) -> String:
	return "%d:%d" % [
		int(round(point.x * 100000.0)),
		int(round(point.y * 100000.0)),
	]
