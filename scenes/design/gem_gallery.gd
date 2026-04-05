extends Control

## Deprecated legacy preset gallery.
## This viewer is kept as a reference surface only; the active gem workflow now
## lives in `scenes/design/gem_bake_workbench.tscn`.

const TILE_VIEW_SCENE := preload("res://scenes/tile/tile_view.tscn")
const PREVIEW_TILE_SIZE := Vector2(112, 112)

const ALL_PRESET_IDS: Array[StringName] = [
	&"quartz", &"amethyst", &"peridot", &"topaz",
	&"sapphire", &"emerald", &"ruby", &"diamond",
	&"fluorite", &"smoky_quartz", &"tourmaline", &"rhodolite",
	&"aquamarine", &"alexandrite", &"painite", &"blue_garnet",
]

func _ready() -> void:
	if GemVisualRegistry != null:
		GemVisualRegistry.set_gameplay_bake_backend_preference(
			GemVisualRegistry.GAMEPLAY_BAKE_BACKEND_OFFLINE_TRACED
		)
		GemVisualRegistry.set_gameplay_runtime_bake_fallback_enabled(false)
		GemVisualRegistry.ensure_gameplay_texture_cache(Vector2i(PREVIEW_TILE_SIZE), ALL_PRESET_IDS)

	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.11)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	add_child(margin)

	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	_build_top_bar(root)
	_build_gallery(root)


func _build_top_bar(parent: VBoxContainer) -> void:
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 8)
	parent.add_child(top_bar)

	var menu_btn := Button.new()
	menu_btn.text = "< Menu"
	menu_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/menu/main_menu.tscn"))
	top_bar.add_child(menu_btn)

	var workbench_btn := Button.new()
	workbench_btn.text = "Gem Bake Workbench"
	workbench_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/design/gem_bake_workbench.tscn"))
	top_bar.add_child(workbench_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(spacer)

	var note := Label.new()
	note.text = "Offline traced presets"
	note.add_theme_color_override("font_color", Color(0.62, 0.67, 0.76))
	top_bar.add_child(note)


func _build_gallery(parent: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 8
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	parent.add_child(grid)

	for preset_id in ALL_PRESET_IDS:
		grid.add_child(_build_preset_card(preset_id))


func _build_preset_card(preset_id: StringName) -> Control:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(178, 0)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var card_style := StyleBoxFlat.new()
	card_style.bg_color = Color(0.12, 0.13, 0.17)
	card_style.set_corner_radius_all(8)
	card_style.content_margin_left = 8
	card_style.content_margin_right = 8
	card_style.content_margin_top = 8
	card_style.content_margin_bottom = 8
	card.add_theme_stylebox_override("panel", card_style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	card.add_child(vbox)

	var title := Label.new()
	title.text = _titleize_id(preset_id)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", Color(0.92, 0.93, 0.98))
	vbox.add_child(title)

	var visual := GemVisualRegistry.get_visual(preset_id)
	if visual != null:
		var meta := Label.new()
		meta.text = _build_meta_line(preset_id, visual)
		meta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		meta.add_theme_font_size_override("font_size", 10)
		meta.add_theme_color_override("font_color", Color(0.62, 0.67, 0.76))
		vbox.add_child(meta)

		var preview_bg := PanelContainer.new()
		var preview_style := StyleBoxFlat.new()
		preview_style.bg_color = Color(0.06, 0.06, 0.09)
		preview_style.set_corner_radius_all(6)
		preview_style.content_margin_left = 6
		preview_style.content_margin_right = 6
		preview_style.content_margin_top = 6
		preview_style.content_margin_bottom = 6
		preview_bg.add_theme_stylebox_override("panel", preview_style)
		vbox.add_child(preview_bg)

		var center := CenterContainer.new()
		preview_bg.add_child(center)

		var preview: TileView = TILE_VIEW_SCENE.instantiate()
		preview.use_gameplay_texture_cache = true
		preview.custom_minimum_size = PREVIEW_TILE_SIZE
		preview.size = PREVIEW_TILE_SIZE
		center.add_child(preview)
		preview.configure_from_data(preset_id, _resolve_tier(preset_id), Vector2i.ZERO)
	else:
		var missing := Label.new()
		missing.text = "Missing visual resource"
		missing.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		missing.add_theme_color_override("font_color", Color(0.9, 0.5, 0.5))
		vbox.add_child(missing)

	return card


func _build_meta_line(preset_id: StringName, visual: GemVisualResource) -> String:
	var parts: Array[String] = []
	var tier := _resolve_tier(preset_id)
	if tier > 0:
		parts.append("Tier %d" % tier)
	parts.append(_titleize_id(visual.cut_id))
	return " | ".join(parts)


func _resolve_tier(preset_id: StringName) -> int:
	if TileRegistry == null or not TileRegistry.has_method("get_definition"):
		return -1
	var definition = TileRegistry.get_definition(preset_id)
	if definition == null:
		return -1
	return int(definition.tier)


func _titleize_id(value: StringName) -> String:
	return String(value).replace("_", " ").capitalize()
