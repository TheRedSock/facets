extends Node

## Loads GemVisualResource definitions from data/visuals/, generates cuts at
## startup, and provides lookup for the rendering layer.
##
## Depends on: GemCutGenerators, GemVisualResource, GemCutResource.

const VISUAL_DATA_PATH := "res://data/visuals/"

var _visuals: Dictionary = {}          # StringName (visual_id / tile_id) -> GemVisualResource
var _cuts: Dictionary = {}             # StringName (cut_id) -> GemCutResource
var _tier_to_visual: Dictionary = {}   # int -> GemVisualResource (first match)
var _loaded: bool = false


func _ready() -> void:
	_load_visuals()
	_generate_cuts()


## Returns the visual definition for a tile, or null.
func get_visual(tile_id: StringName) -> GemVisualResource:
	return _visuals.get(tile_id, null)


## Returns the visual for a tier (first visual found at that tier via TileRegistry).
func get_visual_for_tier(tier: int) -> GemVisualResource:
	if _tier_to_visual.has(tier):
		return _tier_to_visual[tier]
	# Try to resolve via TileRegistry.
	if TileRegistry != null and TileRegistry.has_definitions():
		var ids := TileRegistry.get_ids_for_tier(tier)
		for id in ids:
			if _visuals.has(id):
				_tier_to_visual[tier] = _visuals[id]
				return _visuals[id]
	return null


## Returns the generated GemCutResource for a cut_id, or null.
func get_cut(cut_id: StringName) -> GemCutResource:
	return _cuts.get(cut_id, null)


## Returns true if visuals have been loaded.
func has_visuals() -> bool:
	return _loaded and not _visuals.is_empty()


# ---- Internal ----


func _load_visuals() -> void:
	var dir := DirAccess.open(VISUAL_DATA_PATH)
	if dir == null:
		push_warning("GemVisualRegistry: Could not open %s — no visuals loaded" % VISUAL_DATA_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := VISUAL_DATA_PATH + file_name
			var resource = load(path)
			if resource is GemVisualResource:
				_visuals[resource.visual_id] = resource
		file_name = dir.get_next()
	dir.list_dir_end()

	_loaded = true
	if _visuals.is_empty():
		push_warning("GemVisualRegistry: No .tres visual definitions found in %s" % VISUAL_DATA_PATH)
	else:
		print("GemVisualRegistry: Loaded %d visual definitions" % _visuals.size())


func _generate_cuts() -> void:
	# Collect all unique cut_ids referenced by loaded visuals.
	var needed: Dictionary = {}
	for visual_id in _visuals:
		var vis: GemVisualResource = _visuals[visual_id]
		if vis.cut_id != &"":
			needed[vis.cut_id] = true

	# Generate each cut.
	for cut_id in needed:
		var cut := GemCutGenerators.generate(cut_id)
		if cut != null:
			_cuts[cut_id] = cut

	if not _cuts.is_empty():
		print("GemVisualRegistry: Generated %d gem cuts" % _cuts.size())
