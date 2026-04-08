class_name GemGeometryNormalizer
extends RefCounted

## Shared normalization and rotation logic for canonical 3D cut models.

const GemCutPrimitivesScript = preload("res://core/visuals/gem_cut_primitives.gd")

const TARGET_HORIZONTAL_SPAN := GemCutPrimitivesScript.GEM_RADIUS * 2.0


static func finalize_model(model):
	if model == null:
		return null
	_center_model_xy(model)
	_normalize_model_span(model)
	model.finalize_model()
	return model


static func create_visual_variant(base_model, rotation_degrees: float):
	if base_model == null:
		return null
	var model = base_model.duplicate_model()
	if not is_zero_approx(rotation_degrees):
		_rotate_model_z(model, deg_to_rad(rotation_degrees))
	_center_model_xy(model)
	_normalize_model_span(model)
	_apply_axis_fit_scale(model, rotation_degrees)
	model.finalize_model()
	return model


static func _center_model_xy(model) -> void:
	var bounds = model.compute_bounds()
	if bounds.size == Vector3.ZERO:
		return
	var center_xy := Vector2(
		bounds.position.x + bounds.size.x * 0.5,
		bounds.position.y + bounds.size.y * 0.5
	)
	_transform_model_points(model, func(vertex):
		return Vector3(vertex.x - center_xy.x, vertex.y - center_xy.y, vertex.z)
	)


static func _normalize_model_span(model) -> void:
	var bounds = model.compute_bounds()
	var horizontal_span := maxf(bounds.size.x, bounds.size.y)
	if horizontal_span <= 0.00001:
		return
	var scale := TARGET_HORIZONTAL_SPAN / horizontal_span
	_transform_model_points(model, func(vertex):
		return vertex * scale
	)
	model.crown_height *= scale
	model.girdle_thickness *= scale
	model.pavilion_depth *= scale


static func _apply_axis_fit_scale(model, rotation_degrees: float) -> void:
	var axis_fit_scale := clampf(model.orthographic_axis_fit_scale, 0.5, 1.0)
	if axis_fit_scale >= 0.999:
		return
	var axis_alignment := absf(cos(deg_to_rad(rotation_degrees) * 2.0))
	var scale := lerpf(1.0, axis_fit_scale, axis_alignment)
	if scale >= 0.999:
		return
	_transform_model_points(model, func(vertex):
		return vertex * scale
	)
	model.crown_height *= scale
	model.girdle_thickness *= scale
	model.pavilion_depth *= scale


static func _rotate_model_z(model, angle: float) -> void:
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	_transform_model_points(model, func(vertex):
		return Vector3(
			vertex.x * cos_a - vertex.y * sin_a,
			vertex.x * sin_a + vertex.y * cos_a,
			vertex.z
		)
	)


static func _transform_model_points(model, transform: Callable) -> void:
	for i in model.facet_vertices.size():
		var polygon = model.facet_vertices[i]
		var transformed = PackedVector3Array()
		transformed.resize(polygon.size())
		for j in polygon.size():
			transformed[j] = transform.call(polygon[j])
		model.facet_vertices[i] = transformed
	for i in model.outer_loop.size():
		model.outer_loop[i] = transform.call(model.outer_loop[i])
