class_name GemMeshGenerators
extends RefCounted

## Public facade for prototype 3D gem mesh generation.

const GemMeshBuildersScript = preload("res://core/visuals/gem_mesh_builders.gd")
const GemCutProfilesScript = preload("res://core/visuals/gem_cut_profiles.gd")
const GemCutGeneratorsScript = preload("res://core/visuals/gem_cut_generators.gd")


static func supports(cut_id: StringName) -> bool:
	if cut_id == &"classic_round" or cut_id == &"old_european_round":
		return true
	return GemCutGeneratorsScript.generate(cut_id) != null


static func generate(cut_id: StringName):
	match cut_id:
		&"classic_round":
			return _build_named_round_mesh(cut_id)
		&"old_european_round":
			return _build_named_round_mesh(cut_id)
	var cut = GemCutGeneratorsScript.generate(cut_id)
	if cut != null:
		return generate_from_cut(cut)
	push_warning("GemMeshGenerators: Unsupported cut_id '%s'" % str(cut_id))
	return null


static func generate_from_cut(cut: GemCutResource):
	if cut == null:
		return null
	match cut.cut_id:
		&"classic_round":
			if _cut_is_axis_aligned(cut):
				return _build_named_round_mesh(cut.cut_id)
		&"old_european_round":
			if _cut_is_axis_aligned(cut):
				return _build_named_round_mesh(cut.cut_id)
	return GemMeshBuildersScript.build_mesh_from_cut(cut)


static func _build_named_round_mesh(cut_id: StringName):
	match cut_id:
		&"old_european_round":
			return GemMeshBuildersScript.build_round_brilliant_mesh(GemCutProfilesScript.old_european_round())
		_:
			return GemMeshBuildersScript.build_round_brilliant_mesh(GemCutProfilesScript.classic_round())


static func _cut_is_axis_aligned(cut: GemCutResource) -> bool:
	if cut == null or cut.silhouette.is_empty():
		return true
	var bounds := _cut_bounds(cut.silhouette)
	if bounds.size.x <= 0.00001 or bounds.size.y <= 0.00001:
		return true
	var center := bounds.position + bounds.size * 0.5
	var max_axis_alignment := 0.0
	for point in cut.silhouette:
		var delta := point - center
		if delta.length_squared() <= 0.000001:
			continue
		var dir := delta.normalized().abs()
		max_axis_alignment = maxf(max_axis_alignment, maxf(dir.x, dir.y))
	return max_axis_alignment > 0.995


static func _cut_bounds(points: PackedVector2Array) -> Rect2:
	if points.is_empty():
		return Rect2()
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)
	for point in points:
		min_pt.x = minf(min_pt.x, point.x)
		min_pt.y = minf(min_pt.y, point.y)
		max_pt.x = maxf(max_pt.x, point.x)
		max_pt.y = maxf(max_pt.y, point.y)
	return Rect2(min_pt, max_pt - min_pt)
