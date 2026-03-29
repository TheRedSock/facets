class_name TileView
extends Control

## The grid cell this tile currently represents.
var cell: Vector2i = Vector2i.ZERO

## The tile's identifier and tier for display.
var tile_id: StringName = &""
var tier: int = 0

var _label: Label
var _background: ColorRect
var _sprite: TextureRect


func _ready() -> void:
	# All mouse input is handled by BoardScene, not individual tiles
	mouse_filter = MOUSE_FILTER_IGNORE

	# Build visual structure programmatically
	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_background.color = Color("94a3b8")
	_background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_background)

	_sprite = TextureRect.new()
	_sprite.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_sprite.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_sprite.visible = false
	_sprite.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_sprite)

	_label = Label.new()
	_label.set_anchors_and_offsets_preset(PRESET_CENTER)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.grow_horizontal = GROW_DIRECTION_BOTH
	_label.grow_vertical = GROW_DIRECTION_BOTH
	_label.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_label)

	_update_visual()


func configure(tile: TileState, new_cell: Vector2i) -> void:
	cell = new_cell
	tile_id = tile.tile_id
	tier = tile.tier
	if is_inside_tree():
		_update_visual()


func configure_from_data(p_tile_id: StringName, p_tier: int, p_cell: Vector2i) -> void:
	cell = p_cell
	tile_id = p_tile_id
	tier = p_tier
	if is_inside_tree():
		_update_visual()


func show_upgrade(new_tier: int) -> void:
	tier = new_tier
	# When upgrading via merge, update tile_id to match the new tier
	if TileRegistry.has_definitions():
		var ids := TileRegistry.get_ids_for_tier(new_tier)
		if not ids.is_empty():
			tile_id = ids[0]
	if is_inside_tree():
		_update_visual()


func show_upgrade_full(new_tier: int, new_tile_id: StringName) -> void:
	tier = new_tier
	tile_id = new_tile_id
	if is_inside_tree():
		_update_visual()


func _update_visual() -> void:
	if _label == null:
		return

	# Try to show sprite from concept art atlas
	var has_sprite := false
	if _sprite != null and TileRegistry != null and TileRegistry.get_atlas_texture() != null:
		var atlas_tex := TileRegistry.get_atlas_texture()
		var region := TileRegistry.get_atlas_region(tier)
		if region.size.x > 0:
			var atlas := AtlasTexture.new()
			atlas.atlas = atlas_tex
			atlas.region = region
			_sprite.texture = atlas
			_sprite.visible = true
			has_sprite = true

	if has_sprite:
		# With sprite: hide background, show small tier label in corner
		_background.visible = false
		_label.text = "T%d" % tier
		_label.add_theme_font_size_override("font_size", 14)
		_label.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_label.add_theme_color_override("font_color", Color.BLACK)
		_label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.8))
		_label.add_theme_constant_override("shadow_offset_x", 1)
		_label.add_theme_constant_override("shadow_offset_y", 1)
	else:
		# No sprite: colored background with centered tier label (fallback)
		if _sprite != null:
			_sprite.visible = false
		_background.visible = true
		_background.color = _get_color()
		_label.text = "T%d" % tier
		_label.set_anchors_and_offsets_preset(PRESET_CENTER)
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.remove_theme_font_size_override("font_size")
		_label.remove_theme_color_override("font_color")
		_label.remove_theme_color_override("font_shadow_color")


func _get_color() -> Color:
	# Use TileRegistry colors if available, fall back to hardcoded palette
	if TileRegistry != null and TileRegistry.has_definitions():
		return TileRegistry.get_tier_color(tier)
	var palette := {
		1: Color("f8fafc"), 2: Color("a855f7"), 3: Color("84cc16"), 4: Color("f97316"),
		5: Color("3b82f6"), 6: Color("10b981"), 7: Color("ef4444"), 8: Color("f0f0ff"),
	}
	return palette.get(tier, Color("94a3b8"))
