class_name GemMeshGenerators
extends RefCounted

## Public facade for canonical 3D gem mesh generation.

const GemCutGeneratorsScript = preload("res://core/visuals/gem_cut_generators.gd")
const GemMeshAssemblerScript = preload("res://core/visuals/gem_mesh_assembler.gd")


static func supports_spec_id(spec_id: StringName) -> bool:
	return GemCutGeneratorsScript.generate_model_from_spec_id(spec_id) != null


static func generate_from_spec_id(spec_id: StringName):
	var model = GemCutGeneratorsScript.generate_model_from_spec_id(spec_id)
	if model != null:
		return generate_from_model(model)
	push_warning("GemMeshGenerators: Unsupported spec_id '%s'" % str(spec_id))
	return null


static func generate_from_visual(visual: GemVisualResource):
	if visual == null:
		return null
	return generate_from_model(GemCutGeneratorsScript.generate_model_from_visual(visual))


static func generate_from_spec(spec):
	if spec == null:
		return null
	return generate_from_model(GemCutGeneratorsScript.generate_model_from_spec(spec))


static func generate_from_model(model):
	if model == null:
		return null
	return GemMeshAssemblerScript.assemble(model)
