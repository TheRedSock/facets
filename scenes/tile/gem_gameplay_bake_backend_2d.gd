class_name GemGameplayBakeBackend2D
extends "res://scenes/tile/gem_gameplay_bake_backend.gd"

## Existing polygon-based bake path wrapped behind the backend contract.

var _bake_viewport: SubViewport
var _bake_view: GameplayGemBakeView
var _current_request: Dictionary = {}
var _start_usec := 0
var _frames_until_capture := 0


func _init() -> void:
	backend_id = &"procedural_2d"


func supports_visual(_tile_id: StringName, _visual: GemVisualResource, _cut: GemCutResource) -> bool:
	return true


func request_bake(request: Dictionary) -> void:
	_current_request = request
	_start_usec = Time.get_ticks_usec()

	var draw_size: Vector2i = request.get("draw_size", Vector2i.ZERO)
	var render_data: Dictionary = request.get("render_data", {})
	var visual: GemVisualResource = request.get("visual", null)
	if draw_size.x <= 0 or draw_size.y <= 0 or visual == null or render_data.is_empty():
		texture_baked.emit(request.get("tile_id", &""), null, {
			"backend_id": backend_id,
			"elapsed_ms": 0.0,
			"status": "invalid_request",
		})
		return

	_ensure_bake_surface(draw_size)
	_bake_view.update_render_bundle(visual, render_data)
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_frames_until_capture = 2
	_schedule_capture()


func shutdown() -> void:
	if is_instance_valid(_bake_view):
		_bake_view.clear_render_bundle()
	if is_instance_valid(_bake_viewport):
		_bake_viewport.free()
	_bake_view = null
	_bake_viewport = null
	_current_request = {}
	_frames_until_capture = 0


func _ensure_bake_surface(draw_size: Vector2i) -> void:
	if _bake_viewport == null:
		_bake_viewport = SubViewport.new()
		_bake_viewport.disable_3d = true
		_bake_viewport.transparent_bg = true
		_bake_viewport.msaa_2d = int(ProjectSettings.get_setting(
			"rendering/anti_aliasing/quality/msaa_2d",
			0
		))
		_bake_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(_bake_viewport)

		_bake_view = GameplayGemBakeView.new()
		_bake_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_bake_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_bake_viewport.add_child(_bake_view)

	_bake_viewport.size = draw_size


func _schedule_capture() -> void:
	if get_tree() == null:
		return
	get_tree().process_frame.connect(_on_capture_frame, CONNECT_ONE_SHOT)


func _on_capture_frame() -> void:
	if _frames_until_capture > 1:
		_frames_until_capture -= 1
		_schedule_capture()
		return
	_frames_until_capture = 0
	_on_frame_post_draw()


func _on_frame_post_draw() -> void:
	if not is_instance_valid(_bake_viewport):
		return
	var request := _current_request
	var texture: Texture2D = null
	var target_size: Vector2i = request.get("target_size", request.get("draw_size", Vector2i.ZERO))
	if DisplayServer.get_name() != "headless":
		var viewport_texture := _bake_viewport.get_texture()
		if viewport_texture != null:
			var image := viewport_texture.get_image()
			if image != null:
				if target_size.x > 0 and target_size.y > 0 and image.get_size() != target_size:
					image.resize(target_size.x, target_size.y, Image.INTERPOLATE_BILINEAR)
				texture = ImageTexture.create_from_image(image)
	var elapsed_ms := (Time.get_ticks_usec() - _start_usec) / 1000.0
	texture_baked.emit(request.get("tile_id", &""), texture, {
		"backend_id": backend_id,
		"elapsed_ms": elapsed_ms,
		"target_size": target_size,
		"draw_size": request.get("draw_size", Vector2i.ZERO),
		"cut_id": request.get("cut_id", &""),
		"visual_id": request.get("visual_id", &""),
		"variant_type": request.get("variant_type", &""),
		"variant_key": request.get("variant_key", &""),
		"lighting_bin": request.get("lighting_bin", Vector2i(-1, -1)),
		"rotation_bin": request.get("rotation_bin", -1),
	})
	_current_request = {}
