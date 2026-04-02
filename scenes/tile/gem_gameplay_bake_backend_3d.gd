class_name GemGameplayBakeBackend3D
extends "res://scenes/tile/gem_gameplay_bake_backend.gd"

## Prototype 3D viewport bake path for selected cut families.

const GEM_BAKE_SHADER := preload("res://scenes/tile/gem_bake_3d.gdshader")
const GemMeshGeneratorsScript = preload("res://core/visuals/gem_mesh_generators.gd")

var _bake_viewport: SubViewport
var _root_3d: Node3D
var _pivot: Node3D
var _outer_mesh: MeshInstance3D
var _inner_mesh: MeshInstance3D
var _camera: Camera3D
var _key_light: DirectionalLight3D
var _fill_light: DirectionalLight3D
var _world_environment: WorldEnvironment
var _outer_material: ShaderMaterial
var _inner_material: ShaderMaterial
var _mesh_cache: Dictionary = {}
var _current_request: Dictionary = {}
var _start_usec := 0
var _frames_until_capture := 0


func _init() -> void:
	backend_id = &"viewport_3d_preview"


func supports_visual(_tile_id: StringName, _visual: GemVisualResource, cut: GemCutResource) -> bool:
	if cut == null:
		return false
	return GemMeshGeneratorsScript.supports(cut.cut_id)


func request_bake(request: Dictionary) -> void:
	var visual: GemVisualResource = request.get("visual", null)
	var draw_size: Vector2i = request.get("draw_size", Vector2i.ZERO)
	if visual == null or draw_size.x <= 0 or draw_size.y <= 0:
		texture_baked.emit(request.get("tile_id", &""), null, {
			"backend_id": backend_id,
			"elapsed_ms": 0.0,
			"status": "invalid_request",
		})
		return

	var mesh_bundle := _get_mesh_bundle(request)
	if mesh_bundle.is_empty():
		texture_baked.emit(request.get("tile_id", &""), null, {
			"backend_id": backend_id,
			"elapsed_ms": 0.0,
			"status": "unsupported_cut",
		})
		return

	_current_request = request
	_start_usec = Time.get_ticks_usec()
	_ensure_bake_surface(draw_size)
	_apply_visual_materials(visual)
	_apply_light_rig(request.get("light_dir", Vector3(-0.4, -0.5, 0.75)))
	_outer_mesh.mesh = mesh_bundle["array_mesh"]
	_inner_mesh.mesh = mesh_bundle["array_mesh"]
	_outer_mesh.scale = Vector3.ONE
	_inner_mesh.scale = Vector3.ONE * 0.78
	_pivot.rotation_degrees = _resolve_view_rotation(request)
	_configure_camera(mesh_bundle["mesh_resource"].compute_bounding_radius(), draw_size)
	_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_frames_until_capture = 2
	_schedule_capture()


func shutdown() -> void:
	if is_instance_valid(_bake_viewport):
		_bake_viewport.free()
	_bake_viewport = null
	_root_3d = null
	_pivot = null
	_outer_mesh = null
	_inner_mesh = null
	_camera = null
	_key_light = null
	_fill_light = null
	_world_environment = null
	_outer_material = null
	_inner_material = null
	_mesh_cache.clear()
	_current_request = {}
	_frames_until_capture = 0


func _ensure_bake_surface(draw_size: Vector2i) -> void:
	if _bake_viewport == null:
		_bake_viewport = SubViewport.new()
		_bake_viewport.disable_3d = false
		_bake_viewport.transparent_bg = true
		_bake_viewport.msaa_3d = int(ProjectSettings.get_setting(
			"rendering/anti_aliasing/quality/msaa_3d",
			0
		))
		_bake_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
		_bake_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(_bake_viewport)

		_root_3d = Node3D.new()
		_bake_viewport.add_child(_root_3d)

		_world_environment = WorldEnvironment.new()
		var environment := Environment.new()
		environment.background_mode = Environment.BG_COLOR
		environment.background_color = Color(0.0, 0.0, 0.0, 0.0)
		environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		environment.ambient_light_color = Color(0.85, 0.9, 1.0, 1.0)
		environment.ambient_light_energy = 0.65
		environment.tonemap_mode = Environment.TONE_MAPPER_ACES
		environment.glow_enabled = false
		_world_environment.environment = environment
		_root_3d.add_child(_world_environment)

		_pivot = Node3D.new()
		_root_3d.add_child(_pivot)

		_outer_mesh = MeshInstance3D.new()
		_outer_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pivot.add_child(_outer_mesh)

		_inner_mesh = MeshInstance3D.new()
		_inner_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_pivot.add_child(_inner_mesh)

		_camera = Camera3D.new()
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		_camera.near = 0.01
		_camera.far = 10.0
		_camera.current = true
		_root_3d.add_child(_camera)

		_key_light = DirectionalLight3D.new()
		_key_light.light_energy = 2.2
		_key_light.rotation_degrees = Vector3(-56.0, -25.0, 0.0)
		_root_3d.add_child(_key_light)

		_fill_light = DirectionalLight3D.new()
		_fill_light.light_energy = 0.85
		_fill_light.light_color = Color(0.72, 0.82, 1.0, 1.0)
		_fill_light.rotation_degrees = Vector3(42.0, 135.0, 0.0)
		_root_3d.add_child(_fill_light)

		_outer_material = ShaderMaterial.new()
		_outer_material.shader = GEM_BAKE_SHADER
		_outer_mesh.material_override = _outer_material

		_inner_material = ShaderMaterial.new()
		_inner_material.shader = GEM_BAKE_SHADER
		_inner_mesh.material_override = _inner_material

	_bake_viewport.size = draw_size


func _get_mesh_bundle(request: Dictionary) -> Dictionary:
	var cache_key := String(request.get("cut_key_override", request.get("cut_id", &"")))
	if _mesh_cache.has(cache_key):
		return _mesh_cache[cache_key]
	var mesh_resource = GemMeshGeneratorsScript.generate_from_cut(request.get("cut", null))
	if mesh_resource == null:
		mesh_resource = GemMeshGeneratorsScript.generate(request.get("cut_id", &""))
	if mesh_resource == null or mesh_resource.facet_count() <= 0:
		return {}
	var array_mesh = mesh_resource.create_array_mesh()
	var bundle = {
		"mesh_resource": mesh_resource,
		"array_mesh": array_mesh,
	}
	_mesh_cache[cache_key] = bundle
	return bundle


func _resolve_view_rotation(request: Dictionary) -> Vector3:
	if request.get("variant_type", &"") == &"lighting":
		return Vector3.ZERO
	return Vector3(-26.0, 36.0, 0.0)


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


func _configure_camera(radius: float, draw_size: Vector2i) -> void:
	var padded_radius := maxf(radius, 0.35) * 1.35
	var aspect := float(draw_size.x) / maxf(float(draw_size.y), 1.0)
	_camera.size = padded_radius * 2.0
	if aspect > 1.0:
		_camera.size *= aspect
	_camera.position = Vector3(0.0, 0.0, radius * 3.2 + 1.2)
	_camera.look_at(Vector3.ZERO, Vector3.UP)


func _apply_light_rig(light_dir: Vector3) -> void:
	var key_dir := light_dir.normalized()
	if key_dir.is_zero_approx():
		key_dir = Vector3(-0.4, -0.5, 0.75)
	var fill_dir := Vector3(-key_dir.x * 0.55, -key_dir.y * 0.2, maxf(key_dir.z * 0.8, 0.2)).normalized()
	_orient_directional_light(_key_light, key_dir)
	_orient_directional_light(_fill_light, fill_dir)


func _orient_directional_light(light: DirectionalLight3D, light_dir: Vector3) -> void:
	if light == null:
		return
	var target := -light_dir.normalized()
	if target.is_zero_approx():
		target = Vector3(0.4, 0.5, -0.75)
	light.look_at(target, Vector3.UP)


func _apply_visual_materials(visual: GemVisualResource) -> void:
	var base_color := visual.base_color
	var depth_tint := visual.depth_tint if visual.depth_tint.a > 0.01 else base_color.darkened(0.45)
	var rim_color := visual.rim_color if visual.rim_color.a > 0.01 else base_color.lightened(0.35)

	_outer_material.set_shader_parameter("gem_color", base_color)
	_outer_material.set_shader_parameter("rim_color", rim_color)
	_outer_material.set_shader_parameter("depth_tint", depth_tint)
	_outer_material.set_shader_parameter("alpha", clampf(0.62 - visual.transparency * 0.25, 0.3, 0.82))
	_outer_material.set_shader_parameter("roughness_value", clampf(0.08 - visual.specular_intensity * 0.06, 0.01, 0.12))
	_outer_material.set_shader_parameter("rim_strength", maxf(0.18, visual.rim_intensity * 1.8))
	_outer_material.set_shader_parameter("fire_strength", clampf(visual.hue_dispersion * 0.9 + visual.sparkle_intensity * 0.08, 0.05, 0.55))
	_outer_material.set_shader_parameter("emission_strength", clampf(visual.secondary_specular * 0.35 + visual.specular_intensity * 0.22, 0.08, 0.4))
	_outer_material.set_shader_parameter("absorption_strength", clampf(depth_tint.a * 0.5 + visual.extinction * 0.3, 0.08, 0.45))

	_inner_material.set_shader_parameter("gem_color", base_color.darkened(0.18))
	_inner_material.set_shader_parameter("rim_color", rim_color)
	_inner_material.set_shader_parameter("depth_tint", depth_tint.darkened(0.2))
	_inner_material.set_shader_parameter("alpha", clampf(0.24 + visual.extinction * 0.22, 0.18, 0.46))
	_inner_material.set_shader_parameter("roughness_value", 0.02)
	_inner_material.set_shader_parameter("rim_strength", 0.14)
	_inner_material.set_shader_parameter("fire_strength", clampf(visual.hue_dispersion * 0.35, 0.0, 0.16))
	_inner_material.set_shader_parameter("emission_strength", clampf(visual.secondary_specular * 0.12, 0.0, 0.12))
	_inner_material.set_shader_parameter("absorption_strength", clampf(0.24 + visual.extinction * 0.45, 0.2, 0.7))


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
