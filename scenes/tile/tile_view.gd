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

## Cached procedural gem data (set by _update_visual, consumed by _draw).
var _gem_cut: GemCutResource = null
var _gem_visual: GemVisualResource = null
var _gem_colors: PackedColorArray = PackedColorArray()
var _use_procedural: bool = false


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

	# Scale and rotation pivot at the tile centre so animations grow symmetrically.
	pivot_offset = size * 0.5
	resized.connect(func(): pivot_offset = size * 0.5)

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

	# ---- Priority 1: Procedural gem rendering ----
	if _try_procedural_visual():
		return

	# ---- Priority 2: Atlas sprite (concept art) ----
	_use_procedural = false
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
		# ---- Priority 3: Coloured rectangle fallback ----
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


## Attempts to set up procedural gem rendering.  Returns true on success.
func _try_procedural_visual() -> bool:
	if GemVisualRegistry == null or not GemVisualRegistry.has_visuals():
		return false

	var visual := GemVisualRegistry.get_visual(tile_id)
	if visual == null:
		visual = GemVisualRegistry.get_visual_for_tier(tier)
	if visual == null:
		return false

	var cut := GemVisualRegistry.get_cut(visual.cut_id)
	if cut == null:
		return false

	_gem_visual = visual
	_gem_cut = cut
	_gem_colors = GemRenderer.compute_all_facet_colors(cut, visual)
	_use_procedural = true

	# Hide the sprite and background — _draw() handles rendering.
	if _sprite != null:
		_sprite.visible = false
	_background.visible = false

	# Small tier label in the bottom-right corner.
	_label.text = "T%d" % tier
	_label.add_theme_font_size_override("font_size", 12)
	_label.set_anchors_and_offsets_preset(PRESET_BOTTOM_RIGHT)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)

	queue_redraw()
	return true


func _draw() -> void:
	if not _use_procedural or _gem_cut == null or _gem_visual == null:
		return

	var s := minf(size.x, size.y)
	var offset := (size - Vector2(s, s)) * 0.5  # centre the gem if non-square

	# ---- Draw filled facets ----
	for i in _gem_cut.facet_count():
		var verts := _gem_cut.facet_vertices[i]
		var scaled := PackedVector2Array()
		scaled.resize(verts.size())
		for j in verts.size():
			scaled[j] = verts[j] * s + offset
		if i < _gem_colors.size():
			draw_colored_polygon(scaled, _gem_colors[i])

	# ---- Draw silhouette outline ----
	if DebugFlags.gem_silhouette_outline and _gem_cut.silhouette.size() >= 3:
		var sil := _gem_cut.silhouette
		var scaled_sil := PackedVector2Array()
		scaled_sil.resize(sil.size())
		for j in sil.size():
			scaled_sil[j] = sil[j] * s + offset
		scaled_sil.append(scaled_sil[0])
		draw_polyline(scaled_sil, Color(0, 0, 0, 0.5), 1.5, true)

	# ---- Draw internal edge lines ----
	if _gem_visual.edge_width > 0.01:
		for seg in _gem_cut.edge_segments:
			if seg.size() >= 2:
				var a := seg[0] * s + offset
				var b := seg[1] * s + offset
				draw_line(a, b, _gem_visual.edge_color,
					_gem_visual.edge_width, true)


func _get_color() -> Color:
	# Use TileRegistry colors if available, fall back to hardcoded palette
	if TileRegistry != null and TileRegistry.has_definitions():
		return TileRegistry.get_tier_color(tier)
	var palette := {
		1: Color("f8fafc"), 2: Color("a855f7"), 3: Color("84cc16"), 4: Color("f97316"),
		5: Color("3b82f6"), 6: Color("10b981"), 7: Color("ef4444"), 8: Color("f0f0ff"),
	}
	return palette.get(tier, Color("94a3b8"))
