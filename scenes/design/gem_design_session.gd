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
## Merged editable cut (duplicate of resolve_cut_spec()). Geometry uses this.
var working_cut_spec: GemCutSpecResource

## When non-empty, restore-default and save use this base `res://` cut template.
var base_cut_template_path: String = ""
## Snapshot of the base template contract (for restore / diff). Not written to disk.
var baseline_cut_contract: Dictionary = {}

## Source path for mineral template when loaded from disk (for save-as-reference).
var mineral_template_source_path: String = ""

## Optional post-compile modifiers (design-time only).
var cut_model_modifiers: Array = []

var _geometry_signature: String = ""
var _cached_model = null
var _cached_cut = null
var _cached_mesh = null


func _gem_visual_registry():
	return Engine.get_main_loop().root.get_node_or_null("GemVisualRegistry")


func load_from_tile_id(tile_id: StringName) -> bool:
	source_tile_id = tile_id
	source_visual_path = ""
	var reg = _gem_visual_registry()
	if reg == null:
		return false
	var src: GemVisualResource = reg.get_visual(tile_id)
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
	base_cut_template_path = ""
	baseline_cut_contract.clear()
	mineral_template_source_path = ""

	# Session-local mineral duplicate; track source path for save reference.
	if working_visual.mineral_template != null:
		var mt = working_visual.mineral_template
		if mt.resource_path:
			mineral_template_source_path = mt.resource_path
		if mt is GemMineralTemplate:
			working_visual.mineral_template = (mt as GemMineralTemplate).duplicate(true)

	# Cut: keep base + overrides as stored in the resource (do not flatten).
	if working_visual.cut_spec != null and working_visual.cut_spec is GemCutSpecResourceScript:
		var cs: Resource = working_visual.cut_spec
		if cs.resource_path:
			base_cut_template_path = cs.resource_path
			var base_loaded = load(base_cut_template_path)
			if base_loaded is GemCutSpecResourceScript:
				baseline_cut_contract = (base_loaded as GemCutSpecResourceScript).duplicate_spec().build_contract_dict()
		else:
			baseline_cut_contract = (working_visual.cut_spec as GemCutSpecResourceScript).duplicate_spec().build_contract_dict()

	_rebuild_working_cut_from_visual()
	cut_model_modifiers.clear()
	_invalidate_geometry_cache()
	visual_changed.emit()


func _rebuild_working_cut_from_visual() -> void:
	var resolved = working_visual.resolve_cut_spec() if working_visual != null else null
	if resolved == null:
		working_cut_spec = null
		return
	working_cut_spec = resolved.duplicate_spec()


## Push working cut edits into `working_visual.cut_spec` + `cut_overrides` for persistence.
func sync_cut_to_visual() -> void:
	if working_visual == null or working_cut_spec == null:
		return
	if not (working_cut_spec is GemCutSpecResourceScript):
		return
	var current_contract := working_cut_spec.build_contract_dict()
	if base_cut_template_path.is_empty():
		working_visual.cut_spec = working_cut_spec.duplicate_spec()
		working_visual.cut_overrides = {}
		return
	var base_res = load(base_cut_template_path)
	if base_res == null or not (base_res is GemCutSpecResourceScript):
		working_visual.cut_spec = working_cut_spec.duplicate_spec()
		working_visual.cut_overrides = {}
		return
	var base_contract := (base_res as GemCutSpecResourceScript).build_contract_dict()
	var overrides := GemCutSpecResourceScript.compute_contract_overrides(base_contract, current_contract)
	working_visual.cut_spec = base_res
	working_visual.cut_overrides = overrides


## Select a cut template from disk: base reference + editable working copy.
func apply_cut_template_path(path: String) -> bool:
	if path.is_empty():
		return false
	var res = load(path)
	if res == null or not (res is GemCutSpecResourceScript):
		return false
	base_cut_template_path = path
	var spec: GemCutSpecResourceScript = res
	baseline_cut_contract = spec.duplicate_spec().build_contract_dict()
	working_cut_spec = spec.duplicate_spec()
	sync_cut_to_visual()
	mark_geometry_dirty()
	visual_changed.emit()
	return true


func restore_cut_to_baseline() -> void:
	if working_cut_spec == null:
		return
	if baseline_cut_contract.is_empty():
		return
	working_cut_spec.apply_full_contract(GemCutSpecResourceScript._duplicate_variant(baseline_cut_contract))
	sync_cut_to_visual()
	mark_geometry_dirty()
	visual_changed.emit()


func has_cut_local_edits() -> bool:
	if working_cut_spec == null or baseline_cut_contract.is_empty():
		return false
	var cur := working_cut_spec.build_contract_dict()
	var ovr := GemCutSpecResourceScript.compute_contract_overrides(baseline_cut_contract, cur)
	return not ovr.is_empty()


func get_effective_cut_spec() -> GemCutSpecResource:
	return working_cut_spec


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
	prepare_visual_for_save()
	var err := ResourceSaver.save(working_visual, path)
	if err == OK:
		source_visual_path = path
	return err


## Call before ResourceSaver.save: sync cut overrides + mineral references.
func prepare_visual_for_save() -> void:
	sync_cut_to_visual()
	if working_visual == null:
		return
	# Prefer external mineral reference when unchanged from source file.
	if working_visual.mineral_template != null and working_visual.mineral_template is GemMineralTemplate:
		var mt: GemMineralTemplate = working_visual.mineral_template
		if mineral_template_source_path and not mineral_template_source_path.is_empty():
			var disk = load(mineral_template_source_path)
			if disk is GemMineralTemplate:
				var cur_s := JSON.stringify(mt.build_mineral_json_dict())
				var disk_s := JSON.stringify((disk as GemMineralTemplate).build_mineral_json_dict())
				if cur_s == disk_s:
					working_visual.mineral_template = disk


func save_mineral_template_to_path(path: String) -> Error:
	if working_visual == null or working_visual.mineral_template == null:
		return ERR_INVALID_DATA
	if not (working_visual.mineral_template is GemMineralTemplate):
		return ERR_INVALID_DATA
	var err := ResourceSaver.save(working_visual.mineral_template, path)
	if err == OK:
		mineral_template_source_path = path
		working_visual.mineral_template = load(path)
	return err


func apply_contract_dict_to_cut(contract: Dictionary) -> void:
	if working_cut_spec == null:
		return
	var merged := GemCutSpecResourceScript._deep_merge_dict(working_cut_spec.build_contract_dict(), contract)
	working_cut_spec.apply_full_contract(merged)
	sync_cut_to_visual()
	mark_geometry_dirty()


func get_visual_json_dict() -> Dictionary:
	if working_visual == null:
		return {}
	return working_visual.build_visual_json_dict()


func apply_visual_json_dict(data: Dictionary) -> void:
	if working_visual == null:
		return
	working_visual.apply_visual_json_dict(data)
	if working_visual.mineral_template != null and working_visual.mineral_template is GemMineralTemplate:
		if working_visual.mineral_template.resource_path:
			mineral_template_source_path = working_visual.mineral_template.resource_path
		else:
			working_visual.mineral_template = (working_visual.mineral_template as GemMineralTemplate).duplicate(true)
	_rebuild_working_cut_from_visual()
	mark_visual_dirty()
	mark_geometry_dirty()


func build_cut_json_export_dict() -> Dictionary:
	if working_cut_spec == null:
		return {"cut_json_schema_version": 1}
	var d := working_cut_spec.build_json_safe_contract_dict()
	d["cut_json_schema_version"] = 1
	return d


func apply_cut_json_export_dict(data: Dictionary) -> void:
	if working_cut_spec == null:
		return
	var contract: Dictionary = data.duplicate(true)
	contract.erase("cut_json_schema_version")
	## Same merge path as partial JSON edits so JSON-parsed scalars coerce like the inspector.
	apply_contract_dict_to_cut(contract)
