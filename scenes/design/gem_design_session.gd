class_name GemDesignSession
extends RefCounted

## Working copies of gem visual + cut spec for the runtime designer (unsaved edits).

signal geometry_changed
signal visual_changed

const GemCutSpecResourceScript = preload("res://resources/visuals/gem_cut_spec_resource.gd")
const GemCutCompiler3DScript = preload("res://core/visuals/gem_cut_compiler_3d.gd")
const GemCutProjectorScript = preload("res://core/visuals/gem_cut_projector.gd")
const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")
const GemCutModelModifierScript = preload("res://resources/visuals/gem_cut_model_modifier.gd")

var source_tile_id: StringName = &""
var source_visual_path: String = ""

var working_visual: GemVisualResource
## Resolved spec backing `working_visual` (duplicate of base + overrides merged in working_visual.cut_spec duplicate).
var working_cut_spec: GemCutSpecResource

## Optional post-compile modifiers (design-time only).
var cut_model_modifiers: Array = []

var _geometry_signature: String = ""
var _cached_model = null
var _cached_cut = null
var _cached_mesh = null


func load_from_tile_id(tile_id: StringName) -> bool:
	source_tile_id = tile_id
	source_visual_path = ""
	if GemVisualRegistry == null:
		return false
	var src: GemVisualResource = GemVisualRegistry.get_visual(tile_id)
	if src == null:
		return false
	_duplicate_from_visual(src)
	return true


func load_from_visual_path(path: String) -> bool:
	var res = load(path)
	if not (res is GemVisualResource):
		return false
	source_visual_path = path
	source_tile_id = res.visual_id if res.visual_id != &"" else StringName(path.get_file().get_basename())
	_duplicate_from_visual(res)
	return true


func _duplicate_from_visual(src: GemVisualResource) -> void:
	working_visual = src.duplicate(true)
	if working_visual.cut_spec != null and working_visual.cut_spec is GemCutSpecResourceScript:
		if not working_visual.cut_overrides.is_empty():
			var merged: GemCutSpecResource = working_visual.cut_spec.apply_overrides(working_visual.cut_overrides)
			working_visual.cut_spec = merged
			working_visual.cut_overrides = {}
		else:
			working_visual.cut_spec = working_visual.cut_spec.duplicate_spec()
	working_cut_spec = working_visual.cut_spec as GemCutSpecResource if working_visual.cut_spec is GemCutSpecResourceScript else null
	cut_model_modifiers.clear()
	_invalidate_geometry_cache()
	visual_changed.emit()


func get_effective_cut_spec() -> GemCutSpecResource:
	if working_visual == null:
		return null
	return working_visual.resolve_cut_spec()


func mark_visual_dirty() -> void:
	visual_changed.emit()


func mark_geometry_dirty() -> void:
	_invalidate_geometry_cache()
	geometry_changed.emit()


func _invalidate_geometry_cache() -> void:
	_geometry_signature = ""
	_cached_model = null
	_cached_cut = null
	_cached_mesh = null


func compile_geometry(force: bool = false):
	if working_visual == null:
		return
	var spec = get_effective_cut_spec()
	if spec == null:
		_cached_model = null
		_cached_cut = null
		_cached_mesh = null
		_geometry_signature = ""
		return
	var sig := spec.build_geometry_signature()
	if not force and sig == _geometry_signature and _cached_model != null and _cached_mesh != null:
		return
	_geometry_signature = sig
	var model = GemCutCompiler3DScript.compile_spec(spec)
	if model == null:
		_cached_model = null
		_cached_cut = null
		_cached_mesh = null
		return
	var total_rot := working_visual.rotation_degrees
	if not is_zero_approx(total_rot) or model.orthographic_axis_fit_scale < 0.999:
		model = GemCutCompiler3DScript.create_visual_variant(model, total_rot)
	for mod in cut_model_modifiers:
		if mod != null and is_instance_valid(mod) and mod is GemCutModelModifierScript:
			(mod as GemCutModelModifierScript).apply_to_model(model)
	_cached_model = model
	_cached_cut = GemCutProjectorScript.project(model)
	_cached_mesh = GemMeshGeneratorsScript.generate_from_model(model)


func get_cached_model():
	compile_geometry(false)
	return _cached_model


func get_cached_projected_cut():
	compile_geometry(false)
	return _cached_cut


func get_cached_mesh():
	compile_geometry(false)
	return _cached_mesh


func get_geometry_signature() -> String:
	compile_geometry(false)
	return _geometry_signature


func save_to_path(path: String) -> Error:
	if working_visual == null:
		return ERR_INVALID_DATA
	var err := ResourceSaver.save(working_visual, path)
	if err == OK:
		source_visual_path = path
	return err


func apply_contract_dict_to_cut(contract: Dictionary) -> void:
	if working_cut_spec == null:
		return
	var merged := GemCutSpecResourceScript._deep_merge_dict(working_cut_spec.build_contract_dict(), contract)
	working_cut_spec.apply_full_contract(merged)
	mark_geometry_dirty()
