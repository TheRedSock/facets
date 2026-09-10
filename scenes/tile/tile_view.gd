class_name TileView
extends Control

## Renders one gem tile from authored clips served by the GemForge autoload.
##
## Visual priority:
##   1. Clip strip from GemForge (idle still; "turn" oneshot on upgrade)
##   2. GemForge placeholder still (synchronous INTERACT render)
##   3. ColorRect tinted via TileRegistry.get_tier_color (headless / no data)
##
## BoardScene owns all position/scale/modulate animation via Control tweens;
## this node only decides WHAT the tile draws, never how the board moves it.
## Invariant #5: this node and every child use MOUSE_FILTER_IGNORE — input is
## handled by BoardScene._gui_input.

const IDLE_CLIP := &"idle"
const SPECIAL_ROTATION_DEFAULT_DURATION := 0.42
const SPECIAL_ROTATION_DEFAULT_TURNS := 1.0

## The grid cell this tile currently represents.
var cell: Vector2i = Vector2i.ZERO

## The tile's identifier and tier for display.
var tile_id: StringName = &""
var tier: int = 0

var _background: ColorRect
var _clip_rect: TextureRect
var _frame_atlas: AtlasTexture
## GemForge autoload, resolved by path: a compile-time identifier would break
## this script in --script tool mode and headless tests, where the analyzer
## has no autoload map. Null when the forge is absent (fallback visuals).
var _forge: Node

## Active clip playback state. _process runs only while a oneshot is playing
## or the current clip loops with more than one frame; a 1-frame idle costs
## zero per-frame work.
var _clip_id: StringName = &""
var _frames := 0
var _fps := 1.0
var _loop := false
var _frame_size := Vector2i.ZERO
var _frame := 0
var _elapsed := 0.0


func _ready() -> void:
	# All mouse input is handled by BoardScene, not individual tiles.
	mouse_filter = MOUSE_FILTER_IGNORE

	_background = ColorRect.new()
	_background.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_background.color = Color("94a3b8")
	_background.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(_background)

	_frame_atlas = AtlasTexture.new()
	_clip_rect = TextureRect.new()
	_clip_rect.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_clip_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_clip_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_clip_rect.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_clip_rect.mouse_filter = MOUSE_FILTER_IGNORE
	_clip_rect.visible = false
	add_child(_clip_rect)

	# Scale and rotation pivot at the tile centre so animations grow symmetrically.
	pivot_offset = size * 0.5
	resized.connect(_on_resized)
	set_process(false)
	_forge = get_node_or_null("/root/GemForge")
	if _forge != null and not _forge.clip_ready.is_connected(_on_clip_ready):
		_forge.clip_ready.connect(_on_clip_ready)

	_show_idle_or_fallback()


func _exit_tree() -> void:
	if _forge != null and _forge.clip_ready.is_connected(_on_clip_ready):
		_forge.clip_ready.disconnect(_on_clip_ready)


func configure(tile: TileState, new_cell: Vector2i) -> void:
	cell = new_cell
	tile_id = tile.tile_id
	tier = tile.tier
	if is_inside_tree():
		_show_idle_or_fallback()


func configure_from_data(p_tile_id: StringName, p_tier: int, p_cell: Vector2i) -> void:
	cell = p_cell
	tile_id = p_tile_id
	tier = p_tier
	if is_inside_tree():
		_show_idle_or_fallback()


## Swaps to the new tile's idle visual. The board then plays the "turn"
## clip (quick 360) via play_special_rotation_animation — do not start
## flash here or the oneshot guard swallows the spin.
func show_upgrade_full(new_tier: int, new_tile_id: StringName) -> void:
	tier = new_tier
	tile_id = new_tile_id
	if is_inside_tree():
		_show_idle_or_fallback()


## Plays an authored clip if the forge can serve it; silently no-ops
## otherwise. Oneshot clips return to idle on completion.
func play_clip(clip_id: StringName, restart := true) -> void:
	if _forge == null:
		return
	if not restart and clip_id == _clip_id and is_processing():
		return
	var clip: Dictionary = _forge.get_clip(tile_id, clip_id)
	if clip.is_empty():
		return
	_apply_clip(clip, clip_id)


## Plays the authored "turn" clip (quick eased 360). Yields to an in-flight
## oneshot so a second call in the same upgrade does not restart the spin.
func play_special_rotation_animation(
	_duration: float = SPECIAL_ROTATION_DEFAULT_DURATION,
	_turns: float = SPECIAL_ROTATION_DEFAULT_TURNS,
) -> void:
	if is_processing() and not _loop:
		return
	play_clip(&"turn")


func _process(delta: float) -> void:
	if not visible:
		set_process(false)
		return
	_elapsed += delta
	var next_frame := int(_elapsed * _fps)
	if next_frame >= _frames:
		if _loop:
			next_frame %= _frames
		else:
			_show_idle_or_fallback()
			return
	if next_frame != _frame:
		_frame = next_frame
		_frame_atlas.region = Rect2(
			_frame * _frame_size.x, 0, _frame_size.x, _frame_size.y)


# ---- Visual state ----


func _show_idle_or_fallback() -> void:
	if _forge != null:
		var idle: Dictionary = _forge.get_clip(tile_id, IDLE_CLIP)
		if not idle.is_empty():
			_apply_clip(idle, IDLE_CLIP)
			return
		var still: ImageTexture = _forge.get_placeholder_still(tile_id)
		if still != null:
			_show_still(still)
			return
	_show_tier_color()


func _apply_clip(clip: Dictionary, clip_id: StringName) -> void:
	_clip_id = clip_id
	_frames = int(clip["frames"])
	_fps = maxf(float(clip["fps"]), 0.001)
	_loop = bool(clip["loop"])
	_frame_size = clip["frame_size"]
	_frame = 0
	_elapsed = 0.0
	_frame_atlas.atlas = clip["texture"]
	_frame_atlas.region = Rect2(0, 0, _frame_size.x, _frame_size.y)
	_clip_rect.texture = _frame_atlas
	_clip_rect.visible = true
	_background.visible = false
	set_process(_frames > 1)


func _show_still(still: Texture2D) -> void:
	_clip_id = &""
	_frames = 1
	_loop = false
	set_process(false)
	_clip_rect.texture = still
	_clip_rect.visible = true
	_background.visible = false


func _show_tier_color() -> void:
	_clip_id = &""
	_frames = 0
	_loop = false
	set_process(false)
	_clip_rect.visible = false
	_clip_rect.texture = null
	_background.color = _get_color()
	_background.visible = true


## Upgrades a placeholder/ColorRect visual once the background bake lands.
func _on_clip_ready(ready_tile_id: StringName, ready_clip_id: StringName) -> void:
	if not visible or ready_tile_id != tile_id or ready_clip_id != IDLE_CLIP:
		return
	if _clip_id == IDLE_CLIP:
		return
	if is_processing() and not _loop:
		return # active oneshot returns to idle on its own completion
	_show_idle_or_fallback()


func _on_resized() -> void:
	pivot_offset = size * 0.5


func _get_color() -> Color:
	# Use TileRegistry colors if available, fall back to hardcoded palette.
	# Path lookup, not identifier — same --script/headless rationale as _forge.
	var registry: Node = get_node_or_null("/root/TileRegistry")
	if registry != null and registry.has_definitions():
		return registry.get_tier_color(tier)
	var palette := {
		1: Color("f8fafc"), 2: Color("a855f7"), 3: Color("84cc16"), 4: Color("f97316"),
		5: Color("3b82f6"), 6: Color("10b981"), 7: Color("ef4444"), 8: Color("f0f0ff"),
	}
	return palette.get(tier, Color("94a3b8"))


