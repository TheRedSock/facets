extends Node

## Registry for tile definitions. Loads all TileDefinitionResource files from data/tiles/
## and provides lookup by tile_id, tier-to-id mapping, and atlas sprite regions.
##
## The gem atlas is a 2x4 grid (2 rows, 4 columns) of 384x384px cells.
## T1-T4 top row, T5-T8 bottom row.

const TILE_DATA_PATH := "res://data/tiles/"
const ATLAS_PATH := "res://assets/sprites/gems1.png"

## Atlas grid layout: 2 rows, 4 columns. Gems are in tier order left-to-right, top-to-bottom.
const ATLAS_ROWS := 2
const ATLAS_COLUMNS := 4

var _definitions: Dictionary = {}  # StringName -> TileDefinitionResource
var _tier_to_ids: Dictionary = {}  # int -> Array[StringName]
var _atlas_texture: Texture2D = null
var _atlas_cell_size: Vector2 = Vector2.ZERO
var _loaded: bool = false


func _ready() -> void:
	_load_definitions()
	_load_atlas()


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


## Returns the atlas texture for the gem sprites, or null if not loaded.
func get_atlas_texture() -> Texture2D:
	return _atlas_texture


## Returns the atlas region (Rect2) for a given tier (1-8).
## The atlas is a 2x4 grid with T1-T4 in the top row, T5-T8 in the bottom.
func get_atlas_region(tier: int) -> Rect2:
	if _atlas_texture == null or tier < 1 or tier > 8:
		return Rect2()
	var index := tier - 1
	var col := index % ATLAS_COLUMNS
	var row := index / ATLAS_COLUMNS
	return Rect2(
		Vector2(col * _atlas_cell_size.x, row * _atlas_cell_size.y),
		_atlas_cell_size
	)


## Returns the debug color for a tier, from the definition or a fallback palette.
func get_tier_color(tier: int) -> Color:
	var ids := get_ids_for_tier(tier)
	if not ids.is_empty():
		var def := get_definition(ids[0])
		if def != null:
			return def.debug_color
	# Fallback palette
	var palette := {
		1: Color("f8fafc"), 2: Color("a855f7"), 3: Color("84cc16"), 4: Color("f97316"),
		5: Color("3b82f6"), 6: Color("10b981"), 7: Color("ef4444"), 8: Color("f0f0ff"),
	}
	return palette.get(tier, Color("94a3b8"))


# ---- Internal ----


func _load_definitions() -> void:
	var dir := DirAccess.open(TILE_DATA_PATH)
	if dir == null:
		push_warning("TileRegistry: Could not open %s — no tile definitions loaded" % TILE_DATA_PATH)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".tres"):
			var path := TILE_DATA_PATH + file_name
			var resource = load(path)
			if resource is TileDefinitionResource:
				_register_definition(resource)
		file_name = dir.get_next()
	dir.list_dir_end()

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


func _load_atlas() -> void:
	if not ResourceLoader.exists(ATLAS_PATH):
		push_warning("TileRegistry: Concept art atlas not found at %s" % ATLAS_PATH)
		return
	_atlas_texture = load(ATLAS_PATH)
	if _atlas_texture != null:
		_atlas_cell_size = Vector2(
			_atlas_texture.get_width() / float(ATLAS_COLUMNS),
			_atlas_texture.get_height() / float(ATLAS_ROWS)
		)
		print("TileRegistry: Atlas loaded (%dx%d, cell size %dx%d)" % [
			_atlas_texture.get_width(), _atlas_texture.get_height(),
			int(_atlas_cell_size.x), int(_atlas_cell_size.y)])
