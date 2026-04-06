class_name GemCutCompiler3D
extends RefCounted

## Compiles typed cut profiles into canonical normalized 3D cut models.

static func compile_spec_id(spec_id: StringName):
	var spec_library = load("res://core/visuals/gem_cut_spec_library.gd").new()
	var spec = spec_library.get_spec(spec_id)
	if spec == null:
		push_warning("GemCutCompiler3D: Unknown spec_id '%s'" % str(spec_id))
		return null
	return compile_spec(spec)


static func compile_spec(spec):
	if spec == null:
		return null
	var builders = load("res://core/visuals/gem_topology_builders_3d.gd")
	var normalizer = load("res://core/visuals/gem_geometry_normalizer.gd")
	var validator = load("res://core/visuals/gem_geometry_validator.gd")
	var model = builders.build(spec)
	model = normalizer.finalize_model(model)
	return validator.validate_or_reject(model, spec)


static func create_visual_variant(base_model, rotation_degrees: float):
	var normalizer = load("res://core/visuals/gem_geometry_normalizer.gd")
	return normalizer.create_visual_variant(base_model, rotation_degrees)
