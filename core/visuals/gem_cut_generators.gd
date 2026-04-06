class_name GemCutGenerators
extends RefCounted

## Public facade for canonical cut generation.
##
## The active runtime now compiles fully 3D cut models and projects them to the
## 2D procedural packet on demand from GemCutSpecResource or GemVisualResource.

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
	return generate_model_from_spec(visual.resolve_cut_spec())


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
