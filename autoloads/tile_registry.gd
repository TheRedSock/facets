extends Node

## Registry for tile definitions. Loads all TileDefinitionResource files from data/tiles/
## and provides lookup by tile_id and tier-to-id mapping.

const TILE_DATA_PATH := "res://data/tiles/"

var _definitions: Dictionary = {}  # StringName -> TileDefinitionResource
var _tier_to_ids: Dictionary = {}  # int -> Array[StringName]
var _loaded: bool = false


func _ready() -> void:
	_load_definitions()


## Explicit gameplay preload hook.  Definitions are still loaded eagerly, but
## this gives the run bootstrap a single place to ensure tile data is ready.
func preload_runtime_assets() -> void:
	if not _loaded:
		_load_definitions()


## Returns the definition for a tile_id, or null if not found.
func get_definition(tile_id: StringName) -> TileDefinitionResource:
	return _definitions.get(tile_id, null)


## Returns all registered tile_ids for a given tier.
func get_ids_for_tier(tier: int) -> Array[StringName]:
	return _tier_to_ids.get(tier, [] as Array[StringName])


## Returns true if any tile definitions have been loaded.
func has_definitions() -> bool:
	return _loaded and not _definitions.is_empty()


## Creates a TileState from a tile definition, copying all relevant fields.
func create_tile(tile_id: StringName) -> TileState:
	var def: TileDefinitionResource = get_definition(tile_id)
	if def == null:
		# Fallback: create a debug tile
		return TileState.from_debug_tier(1)
	var tile := TileState.new()
	tile.tile_id = def.tile_id
	tile.tier = def.tier
	tile.match_group = def.match_group
	tile.merge_target_id = def.merge_target_id
	tile.family_tags = def.family_tags.duplicate()
	return tile


## Creates a TileState for a random tile at the given tier.
## If multiple tiles exist for that tier, picks one using the provided RNG.
func create_tile_for_tier(tier: int, rng: SeededRng) -> TileState:
	var ids: Array[StringName] = get_ids_for_tier(tier)
	if ids.is_empty():
		# Fallback: debug tile
		return TileState.from_debug_tier(tier)
	var chosen_id: StringName = ids[rng.randi_range(0, ids.size() - 1)]
	return create_tile(chosen_id)


# ---- Internal ----


func _load_definitions() -> void:
	var files:=ResourceLoader.list_directory(TILE_DATA_PATH)
	files.sort() # Stable tier ordering in both editor and exported packages.
	for file_name in files:
		if file_name.ends_with(".tres"):
			var resource:=ResourceLoader.load(TILE_DATA_PATH.path_join(file_name))
			if resource is TileDefinitionResource:_register_definition(resource)

	_loaded = true
	if _definitions.is_empty():
		push_warning("TileRegistry: No .tres tile definitions found in %s" % TILE_DATA_PATH)
	else:
		print("TileRegistry: Loaded %d tile definitions" % _definitions.size())


func _register_definition(def: TileDefinitionResource) -> void:
	_definitions[def.tile_id] = def
	if not _tier_to_ids.has(def.tier):
		_tier_to_ids[def.tier] = [] as Array[StringName]
	_tier_to_ids[def.tier].append(def.tile_id)
