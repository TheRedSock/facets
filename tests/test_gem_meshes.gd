extends SceneTree

## Canonical 3D mesh assembly checks.

const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemCutGeneratorsScript = preload("res://core/visuals/gem_cut_generators.gd")
const GemCutPrimitives = preload("res://core/visuals/gem_cut_primitives.gd")

const MESH_CUT_IDS := [
	&"classic_round",
	&"old_european_round",
	&"emerald_step",
	&"trillion",
	&"princess_square",
	&"lozenge",
	&"oval_brilliant",
	&"pear_brilliant",
]

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	print("\n=== Gem Mesh Tests ===\n")
	await process_frame
	test_generate_supported_meshes()
	test_generate_all_visual_cut_meshes()
	test_generate_rotated_variant_meshes()
	test_trillion_pavilion_stays_within_crown_footprint()
	test_princess_pavilion_stays_within_crown_footprint()
	test_lozenge_pavilion_has_detail()
	test_oval_brilliant_pavilion_has_detail()
	test_pear_brilliant_pavilion_has_detail()
	test_bounds_and_radius()
	test_normals_face_outward()
	test_array_mesh_build()
	test_trace_data_build()

	print("\n=== Results: %d passed, %d failed ===" % [_pass_count, _fail_count])
	quit(1 if _fail_count > 0 else 0)


func test_generate_supported_meshes() -> void:
	for cut_id in MESH_CUT_IDS:
		var mesh = GemMeshGeneratorsScript.generate_from_spec_id(cut_id)
		assert_true(mesh != null, "%s should generate a mesh resource" % str(cut_id))
		if mesh == null:
			continue
		assert_eq(mesh.spec_id, cut_id, "%s should preserve spec_id" % str(cut_id))
		assert_eq(mesh.facet_vertices.size(), mesh.facet_normals.size(), "%s normals align" % str(cut_id))
		assert_eq(mesh.facet_vertices.size(), mesh.facet_zones.size(), "%s zones align" % str(cut_id))


func test_generate_all_visual_cut_meshes() -> void:
	var registry := get_root().get_node_or_null("GemVisualRegistry")
	assert_true(registry != null, "GemVisualRegistry autoload should exist for all-visual mesh coverage")
	if registry == null:
		return
	for tile_id in registry.get_visual_ids():
		var visual = registry.get_visual(tile_id)
		assert_true(visual != null, "%s should resolve a gem visual" % str(tile_id))
		if visual == null:
			continue
		var mesh = GemMeshGeneratorsScript.generate_from_visual(visual)
		assert_true(mesh != null, "%s visual should generate a mesh resource" % str(tile_id))
		if mesh == null:
			continue
		assert_true(mesh.facet_count() > 0, "%s visual should have facets" % str(tile_id))


func test_generate_rotated_variant_meshes() -> void:
	var base_model = GemCutGeneratorsScript.generate_model_from_visual_with_rotation(_make_visual(&"emerald_step", 0.0))
	var rotated_model = GemCutGeneratorsScript.generate_model_from_visual_with_rotation(_make_visual(&"emerald_step", 45.0))
	assert_true(base_model != null, "Emerald Step model should generate for rotated mesh coverage")
	assert_true(rotated_model != null, "Emerald Step rotated model should generate for rotated mesh coverage")
	if base_model == null or rotated_model == null:
		return
	var base_mesh = GemMeshGeneratorsScript.generate_from_model(base_model)
	var rotated_mesh = GemMeshGeneratorsScript.generate_from_model(rotated_model)
	assert_true(base_mesh != null, "Base non-round cut should build a mesh from canonical model geometry")
	assert_true(rotated_mesh != null, "Rotated non-round cut should build a mesh from canonical model geometry")
	if base_mesh == null or rotated_mesh == null:
		return
	var base_bounds: AABB = base_mesh.compute_bounds()
	var rotated_bounds: AABB = rotated_mesh.compute_bounds()
	assert_true(
		absf(rotated_bounds.size.x - rotated_bounds.size.y) < absf(base_bounds.size.x - base_bounds.size.y),
		"Rotated emerald mesh should reflect the rotated cut footprint"
	)


func test_oval_brilliant_pavilion_has_detail() -> void:
	var mesh = GemMeshGeneratorsScript.generate_from_spec_id(&"oval_brilliant")
	assert_true(mesh != null, "Oval brilliant should generate a mesh resource")
	if mesh == null:
		return
	var pavilion_count := 0
	var culet_count := 0
	for zone in mesh.facet_zones:
		if zone == "pavilion":
			pavilion_count += 1
		elif zone == "culet":
			culet_count += 1
	assert_true(pavilion_count >= 16, "Oval brilliant should use multiple pavilion facet bands")
	assert_true(culet_count >= 8, "Oval brilliant should provide dedicated culet facets")


func test_trillion_pavilion_stays_within_crown_footprint() -> void:
	var cut = GemCutGeneratorsScript.generate_from_spec_id(&"trillion")
	var mesh = GemMeshGeneratorsScript.generate_from_spec_id(&"trillion")
	assert_true(cut != null, "Trillion should generate a cut resource")
	assert_true(mesh != null, "Trillion should generate a mesh resource")
	if cut == null or mesh == null:
		return
	for facet_index in mesh.facet_count():
		var zone: StringName = mesh.facet_zones[facet_index]
		if zone != "pavilion" and zone != "culet":
			continue
		for vertex in mesh.facet_vertices[facet_index]:
			var point_2d := Vector2(vertex.x + 0.5, 0.5 - vertex.y)
			assert_true(
				Geometry2D.is_point_in_polygon(point_2d, cut.silhouette) or _point_near_polygon_boundary(point_2d, cut.silhouette, 0.0025),
				"Trillion pavilion vertices should stay within the crown footprint"
			)


func test_lozenge_pavilion_has_detail() -> void:
	var mesh = GemMeshGeneratorsScript.generate_from_spec_id(&"lozenge")
	assert_true(mesh != null, "Lozenge should generate a mesh resource")
	if mesh == null:
		return
	var pavilion_count := 0
	var culet_count := 0
	for zone in mesh.facet_zones:
		if zone == "pavilion":
			pavilion_count += 1
		elif zone == "culet":
			culet_count += 1
	assert_true(pavilion_count >= 8, "Lozenge should use a dedicated stepped pavilion")
	assert_true(culet_count >= 4, "Lozenge should provide dedicated culet facets")


func test_princess_pavilion_stays_within_crown_footprint() -> void:
	var cut = GemCutGeneratorsScript.generate_from_spec_id(&"princess_square")
	var mesh = GemMeshGeneratorsScript.generate_from_spec_id(&"princess_square")
	assert_true(cut != null, "Princess square should generate a cut resource")
	assert_true(mesh != null, "Princess square should generate a mesh resource")
	if cut == null or mesh == null:
		return
	for facet_index in mesh.facet_count():
		var zone: StringName = mesh.facet_zones[facet_index]
		if zone != "pavilion" and zone != "culet":
			continue
		for vertex in mesh.facet_vertices[facet_index]:
			var point_2d := Vector2(vertex.x + 0.5, 0.5 - vertex.y)
			assert_true(
				Geometry2D.is_point_in_polygon(point_2d, cut.silhouette) or _point_near_polygon_boundary(point_2d, cut.silhouette, 0.0025),
				"Princess pavilion vertices should stay within the crown footprint"
			)


func test_pear_brilliant_pavilion_has_detail() -> void:
	var mesh = GemMeshGeneratorsScript.generate_from_spec_id(&"pear_brilliant")
	assert_true(mesh != null, "Pear brilliant should generate a mesh resource")
	if mesh == null:
		return
	var pavilion_count := 0
	var culet_count := 0
	for zone in mesh.facet_zones:
		if zone == "pavilion":
			pavilion_count += 1
		elif zone == "culet":
			culet_count += 1
	assert_true(pavilion_count >= 20, "Pear brilliant should use multiple pavilion facet bands")
	assert_true(culet_count >= 10, "Pear brilliant should provide dedicated culet facets")


func test_bounds_and_radius() -> void:
	for cut_id in MESH_CUT_IDS:
		var mesh = GemMeshGeneratorsScript.generate_from_spec_id(cut_id)
		var bounds: AABB = mesh.compute_bounds()
		assert_true(bounds.size.x > 0.30, "%s bounds span X" % str(cut_id))
		assert_true(bounds.size.y > 0.5, "%s bounds span Y" % str(cut_id))
		assert_true(bounds.size.z > 0.3, "%s bounds span Z" % str(cut_id))
		assert_true(
			mesh.compute_bounding_radius() > GemCutPrimitives.GEM_RADIUS - 0.01,
			"%s radius stays within the canonical fit" % str(cut_id)
		)


func test_normals_face_outward() -> void:
	for cut_id in MESH_CUT_IDS:
		var mesh = GemMeshGeneratorsScript.generate_from_spec_id(cut_id)
		for i in mesh.facet_count():
			var centroid := _facet_centroid(mesh.facet_vertices[i])
			assert_true(
				mesh.facet_normals[i].dot(centroid) > 0.0,
				"%s facet %d should face outward" % [str(cut_id), i]
			)


func test_array_mesh_build() -> void:
	for cut_id in MESH_CUT_IDS:
		var mesh = GemMeshGeneratorsScript.generate_from_spec_id(cut_id)
		var array_mesh: ArrayMesh = mesh.create_array_mesh()
		assert_true(array_mesh != null, "%s should create an ArrayMesh" % str(cut_id))
		if array_mesh == null:
			continue
		assert_eq(array_mesh.get_surface_count(), 1, "%s mesh uses one surface" % str(cut_id))


func test_trace_data_build() -> void:
	for cut_id in MESH_CUT_IDS:
		var mesh = GemMeshGeneratorsScript.generate_from_spec_id(cut_id)
		var trace_data: Dictionary = mesh.build_trace_data()
		var triangle_vertices_a: Array = trace_data.get("triangle_vertices_a", [])
		var triangle_vertices_b: Array = trace_data.get("triangle_vertices_b", [])
		var triangle_vertices_c: Array = trace_data.get("triangle_vertices_c", [])
		var triangle_normals: Array = trace_data.get("triangle_normals", [])
		var bvh_triangle_indices: Array = trace_data.get("bvh_triangle_indices", [])
		var bvh_node_bounds: Array = trace_data.get("bvh_node_bounds", [])
		var bvh_node_count: Array = trace_data.get("bvh_node_count", [])
		assert_true(triangle_vertices_a.size() > mesh.facet_count(), "%s trace data triangulates facets" % str(cut_id))
		assert_eq(triangle_vertices_a.size(), triangle_vertices_b.size(), "%s trace data keeps triangle arrays aligned" % str(cut_id))
		assert_eq(triangle_vertices_a.size(), triangle_vertices_c.size(), "%s trace data keeps triangle arrays aligned" % str(cut_id))
		assert_eq(triangle_vertices_a.size(), triangle_normals.size(), "%s trace data keeps normals aligned" % str(cut_id))
		assert_eq(bvh_triangle_indices.size(), triangle_vertices_a.size(), "%s BVH indexes every triangle" % str(cut_id))
		assert_true(not bvh_node_bounds.is_empty(), "%s BVH should contain at least one node" % str(cut_id))
		assert_true(bvh_node_count[0] == 0 or triangle_vertices_a.size() <= 4, "%s BVH root should either branch or stay a single small leaf" % str(cut_id))


func assert_true(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		push_error("FAIL: %s" % message)


func assert_eq(actual, expected, message: String) -> void:
	assert_true(actual == expected, "%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _facet_centroid(vertices: PackedVector3Array) -> Vector3:
	var centroid := Vector3.ZERO
	for vertex in vertices:
		centroid += vertex
	return centroid / float(vertices.size())


func _point_near_polygon_boundary(point: Vector2, polygon: PackedVector2Array, tolerance: float) -> bool:
	for i in polygon.size():
		var a: Vector2 = polygon[i]
		var b: Vector2 = polygon[(i + 1) % polygon.size()]
		if Geometry2D.get_closest_point_to_segment(point, a, b).distance_to(point) <= tolerance:
			return true
	return false


func _make_visual(spec_id: StringName, rotation_degrees: float = 0.0) -> GemVisualResource:
	var visual := GemVisualResource.new()
	visual.cut_spec = load("res://data/visuals/cut_specs/%s.tres" % String(spec_id))
	visual.rotation_degrees = rotation_degrees
	return visual
