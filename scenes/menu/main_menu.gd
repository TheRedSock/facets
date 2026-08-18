extends Control

## Main Menu — entry point for the game.
## Provides navigation to the Run scene and the Gem Atelier (lapidary designer).


func _ready() -> void:
	# Prevent root Control from eating mouse events.
	mouse_filter = MOUSE_FILTER_IGNORE

	# Dark background
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.08, 0.12)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)

	# Centred layout
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	center.add_child(vbox)

	# ---- Title ----
	var title := Label.new()
	title.text = "FACETS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96))
	vbox.add_child(title)

	# ---- Subtitle ----
	var subtitle := Label.new()
	subtitle.text = "Gemstone Match-3 Merge Roguelike"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", Color(0.45, 0.5, 0.6))
	vbox.add_child(subtitle)

	# ---- Spacer ----
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(spacer)

	# ---- Play button ----
	var play_btn := Button.new()
	play_btn.text = "Play"
	play_btn.custom_minimum_size = Vector2(300, 56)
	play_btn.add_theme_font_size_override("font_size", 24)
	play_btn.pressed.connect(_on_play)
	vbox.add_child(play_btn)

	# ---- Gem Atelier (lapidary designer) ----
	var atelier_btn := Button.new()
	atelier_btn.text = "Gem Atelier"
	atelier_btn.custom_minimum_size = Vector2(300, 56)
	atelier_btn.add_theme_font_size_override("font_size", 24)
	atelier_btn.pressed.connect(_on_atelier)
	vbox.add_child(atelier_btn)


func _on_play() -> void:
	get_tree().change_scene_to_file("res://scenes/main/main.tscn")


func _on_atelier() -> void:
	get_tree().change_scene_to_file("res://scenes/design/gem_atelier.tscn")
