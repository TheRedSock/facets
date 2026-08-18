class_name GemCutGenerators
extends RefCounted

## Public facade for canonical cut generation.
##
## The active runtime now compiles fully 3D cut models and projects them to the
## 2D procedural packet on demand from GemCutSpecResource or GemVisualResource.

const GemPavilionSolverScript = preload("res://core/visuals/gem_pavilion_solver.gd")

static func generate_from_spec_id(spec_id: StringName):
	var model = generate_model_from_spec_id(spec_id)
	if model == null:
		return null
	return GemCutProjector.project(model)


static func generate_model_from_spec_id(spec_id: StringName):
	return GemCutCompiler3D.compile_spec_id(spec_id)


static func generate_from_spec(spec):
	var model = generate_model_from_spec(spec)
	if model == null:
		return null
	return GemCutProjector.project(model)


static func generate_model_from_spec(spec):
	return GemCutCompiler3D.compile_spec(spec)


static func generate_from_visual(visual: GemVisualResource):
	var model = generate_model_from_visual(visual)
	if model == null:
		return null
	return GemCutProjector.project(model)


static func generate_model_from_visual(visual: GemVisualResource):
	if visual == null:
		return null
	var resolved := resolve_visual_geometry(visual)
	if resolved.is_empty():
		return null
	return GemCutCompiler3D.compile_spec(resolved.spec, resolved.pavilion_params)


static func resolve_visual_geometry(visual: GemVisualResource) -> Dictionary:
	if visual == null:
		push_error("GemCutGenerators.resolve_visual_geometry requires a GemVisualResource")
		return {}
	var spec = visual.resolve_cut_spec()
	if spec == null:
		push_error("GemVisualResource '%s' has no valid cut_spec" % String(visual.visual_id))
		return {}
	if visual.mineral_template == null or not visual.mineral_template.has_method("get_reference_ior"):
		push_error("GemVisualResource '%s' requires a mineral_template with get_reference_ior()" % String(visual.visual_id))
		return {}
	var ior: float = visual.mineral_template.get_reference_ior()
	var pavilion_params := GemPavilionSolverScript.resolve(spec, ior, visual.cut_quality)
	var resolved_spec = spec.duplicate_spec()
	resolved_spec.apply_pavilion_resolution(pavilion_params)
	return {
		"spec": resolved_spec,
		"pavilion_params": pavilion_params,
		"geometry_signature": resolved_spec.build_geometry_signature(),
	}


static func generate_visual_with_rotation(
	visual: GemVisualResource,
	additional_rotation_degrees: float = 0.0,
):
	var model = generate_model_from_visual_with_rotation(visual, additional_rotation_degrees)
	if model == null:
		return null
	return GemCutProjector.project(model)


static func generate_model_from_visual_with_rotation(
	visual: GemVisualResource,
	additional_rotation_degrees: float = 0.0,
):
	var base_model = generate_model_from_visual(visual)
	if base_model == null:
		return null
	return GemCutCompiler3D.create_visual_variant(
		base_model,
		visual.rotation_degrees + additional_rotation_degrees
	)
