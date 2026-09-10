class_name GemTracer
extends RefCounted
## Lapidary GPU tracer host — kernel v3.
##
## Consumes StoneInstance dictionaries from LapidaryStoneCompiler plus a light
## rig, dispatches the spectral path tracer, and finalizes through the GPU
## print pass (house print or raw display transform). Batch-ready: stones are
## ranges in shared buffers, instances sit on a pixel grid (1x1 = single stone).
##
## Scatter field: when the rung policy sets `field_exits > 0`, the first
## accumulate() after an orientation / rig change runs the scatter-field
## pre-pass (gem_scatter_field.glsl): the in-scattered radiance of the volume
## on a 3D grid as SH (l<=3) per spectral band. The trace kernel then reads
## single scattering deterministically at every scatter event.
##
## Requires a RenderingDevice-capable context (NOT --headless).

const SHADER_DIR := "res://core/lapidary/tracer/shaders/"
const SHADER_PATH := SHADER_DIR + "gem_pathtrace.glsl"
const FIELD_SHADER_PATH := SHADER_DIR + "gem_scatter_field.glsl"
const PRINT_SHADER_PATH := SHADER_DIR + "gem_print.glsl"
const DENOISE_SHADER_PATH := SHADER_DIR + "gem_denoise.glsl"
const COMMON_PATH := SHADER_DIR + "gem_common.glsl"
const INCLUDE_LINE := "#include \"gem_common.glsl\""
const Colorimetry := preload("res://core/lapidary/lighting/colorimetry.gd")

const PUSH_SIZE := 96
const FIELD_PUSH_SIZE := 48
## Adaptive dispatch target (ms per GPU submission); far below any OS watchdog.
const DISPATCH_TARGET_MS := 120.0
const MAX_CHUNK_SPP := 64
const PRINT_PUSH_SIZE := 112
const STONE_STRIDE_BYTES := 128
const INST_STRIDE_BYTES := 64

# Must match gem_common.glsl.
const FIELD_BANDS := 16
const FIELD_SLABS := FIELD_BANDS * 4
const FIELD_TEXELS_PER_GROUP := 4  # gem_scatter_field.glsl TEXELS_PER_GROUP
const MAX_LIGHTS := 8
## 3D texture depth limit (Vulkan maxImageDimension3D floor) bounds grid * slabs.
const FIELD_MAX_DEPTH := 2048
## GPU memory budget for the scatter field of one configure (the grid is
## coarsened until the instance set fits).
const FIELD_BUDGET_BYTES := 160 * 1024 * 1024

const FLAG_DISPERSION := 1
const FLAG_BIREF := 2
const FLAG_VOLUME := 4
const FLAG_FLUOR := 16
const FLAG_FULL_SPECTRUM := 32

const STONE_FLAG_HAS_ERAY := 1
const STONE_FLAG_DISPERSION_STRONG := 2

var width := 0
var height := 0
var samples_accumulated := 0
var last_dispatch_ms := 0.0
var last_field_ms := 0.0
var last_accumulate_ms := 0.0
var last_print_ms := 0.0
var last_denoise_ms := 0.0
var _denoise_passes := 0
var _denoise_phi := 2.0
var _filtered_samples := -1
var _print_source: RID
var field_build_count := 0
var _instance_bytes := PackedByteArray()
var _field_state_key := ""
var debug_chunks := false

var _rd: RenderingDevice
var _owns_rd := false
var _shaders: Dictionary = {}    # name -> RID
var _pipelines: Dictionary = {}  # name -> RID
var _bufs: Dictionary = {}
var _sets: Dictionary = {}       # name -> uniform set RID
var _print_tex: RID
var _print_size := Vector2i.ZERO
var _field_tex: RID
var _field_sampler: RID

var _plane_count_total := 0
var _light_count := 0
var _inst_count := 1
var _spectral_norm := 0.0
var _seed := 1
var _max_bounces := 32
var _throughput_epsilon := 0.0001
var _flags := 0
var _grid := Vector2i.ONE
var _cell := Vector2i.ZERO
var _bg := Vector4(0.30, 0.16, 0.05, 0.0)  # zenith, horizon, below, spectrum offset
var _xyz_to_rgb := Colorimetry.xyz_to_srgb()  # print matrix incl. as-shot white balance
var _rad_clamp := 48.0
var _env_filter_rad := 0.06
var _field_exits := 0
var _field_grid := 16
var _field_dirs := 2048
var _field_dirty := true
# Adaptive dispatch unit (see accumulate()).
var _chunk_spp := 1
var _chunk_rows := 8
var _field_chunk := 2048  # texels per scatter-field dispatch (adaptive)
var _lights_packed := PackedFloat32Array()
var _spectra_packed := PackedFloat32Array()
var _camera_distance := 5.0
# Cached single-instance state (grid 1x1 convenience path).
var _inst_state := {
	"quat": Quaternion.IDENTITY, "rig_yaw": 0.0, "ortho_half": 1.25,
	"role_mult": [1.0, 1.0, 1.0, 1.0], "stone_index": 0,
}


static func create(p_width: int, p_height: int) -> GemTracer:
	var t := GemTracer.new()
	t.width = p_width
	t.height = p_height
	t._rd = RenderingServer.create_local_rendering_device()
	t._owns_rd = true
	if t._rd == null:
		push_error("GemTracer: no RenderingDevice (headless mode has none).")
		return null
	if not t._compile_shaders():
		t.release()
		return null
	var zeros := PackedByteArray()
	zeros.resize(p_width * p_height * 16)
	t._bufs["accum"] = t._rd.storage_buffer_create(zeros.size(), zeros)
	t._bufs["filter_a"] = t._rd.storage_buffer_create(zeros.size(), zeros)
	t._bufs["filter_b"] = t._rd.storage_buffer_create(zeros.size(), zeros)
	for name in ["ballistic", "residual", "reconstructed"]:
		t._bufs[name] = t._rd.storage_buffer_create(zeros.size(), zeros)
	zeros.resize(p_width * p_height * 32)
	t._bufs["guides"] = t._rd.storage_buffer_create(zeros.size(), zeros)
	var standards := GemStandardSpectra.packed().to_byte_array()
	t._bufs["standards"] = t._rd.storage_buffer_create(standards.size(), standards)
	t._spectral_norm = (400.0 / 4.0) / Colorimetry.integral_ybar()
	t._cell = Vector2i(p_width, p_height)
	return t


func _compile_shaders() -> bool:
	var common := FileAccess.get_file_as_string(COMMON_PATH)
	if common.is_empty():
		push_error("GemTracer: cannot read %s" % COMMON_PATH)
		return false
	for entry in [[SHADER_PATH, "trace"], [FIELD_SHADER_PATH, "field"], [PRINT_SHADER_PATH, "print"], [DENOISE_SHADER_PATH, "denoise"]]:
		var text := FileAccess.get_file_as_string(entry[0])
		if text.is_empty():
			push_error("GemTracer: cannot read %s" % entry[0])
			return false
		text = text.replace(INCLUDE_LINE, common)
		text = text.replace("#include \"gem_mesh.glsl\"", FileAccess.get_file_as_string(SHADER_DIR + "gem_mesh.glsl"))
		text = text.replace("#include \"gem_surface.glsl\"", FileAccess.get_file_as_string(SHADER_DIR + "gem_surface.glsl"))
		var src := RDShaderSource.new()
		src.source_compute = text
		var spirv := _rd.shader_compile_spirv_from_source(src)
		if spirv.compile_error_compute != "":
			push_error("GemTracer %s shader compile error:\n%s" % [entry[1], spirv.compile_error_compute])
			return false
		var shader := _rd.shader_create_from_spirv(spirv)
		_shaders[entry[1]] = shader
		_pipelines[entry[1]] = _rd.compute_pipeline_create(shader)
	return true


# ------------------------------------------------------------------ configure

## Full-featured path: StoneInstance from LapidaryStoneCompiler + lights + rung policy.
## policy keys (see GemRung.TABLE): max_bounces, dispersion, birefringence, volume,
## rad_clamp, env_filter_rad, field_exits, field_grid, field_dirs. Ingests the instance's own
## seed; compiled lighting supplies all spectra, background and print neutral.
func configure_stone(instance: Dictionary, lighting: GemLighting, policy: Dictionary) -> void:
	if instance.has("seed"):
		_seed = int(instance["seed"])
	configure_stones([instance], lighting, policy, Vector2i.ONE)


## Multi-stone batch: instances laid out on a grid of equal cells (board atlas).
func configure_stones(instances: Array, lighting: GemLighting, policy: Dictionary, grid: Vector2i) -> void:
	assert(lighting != null)
	assert(lighting.validate().is_empty(), lighting.validate())
	var lights := lighting.lights
	assert(not instances.is_empty() and lights.size() % 8 == 0)
	assert(lights.size() / 8 <= MAX_LIGHTS, "GemTracer: rig exceeds %d lights" % MAX_LIGHTS)
	var bound_radius := 0.0
	for instance: Dictionary in instances:
		bound_radius = maxf(bound_radius, _boundary_radius(instance))
	_camera_distance = bound_radius + maxf(0.5, bound_radius * 0.05)
	_grid = grid
	@warning_ignore("integer_division")
	_cell = Vector2i(width / grid.x, height / grid.y)
	_inst_count = grid.x * grid.y
	_light_count = lights.size() / 8
	_denoise_passes = clampi(policy.get("denoise_passes", 0), 0, 5)
	_denoise_phi = clampf(policy.get("denoise_phi", 2.0), 0.1, 8.0)
	_max_bounces = policy.get("max_bounces", 32)
	_throughput_epsilon = clampf(policy.get("throughput_epsilon", 0.0001), 1.0e-8, 0.01)
	_flags = 0
	if policy.get("dispersion", false):
		_flags |= FLAG_DISPERSION
	if policy.get("spectral_geometry", "selective") == "full":
		_flags |= FLAG_DISPERSION | FLAG_FULL_SPECTRUM
	if policy.get("birefringence", false):
		_flags |= FLAG_BIREF
	if policy.get("volume", true):
		_flags |= FLAG_VOLUME
	# Fluorescence is deferred until excitation and emitted-path transport exist.
	_rad_clamp = policy.get("rad_clamp", 48.0)
	_env_filter_rad = policy.get("env_filter_rad", 0.06)
	_field_exits = clampi(policy.get("field_exits", 0), 0, 64)
	@warning_ignore("integer_division")
	_field_grid = clampi(policy.get("field_grid", 32), 4, FIELD_MAX_DEPTH / FIELD_SLABS)
	var scattering_present := false
	for instance: Dictionary in instances:
		if float(instance.get("scatter", {}).get("sigma_per_mm", 0.0)) > 0.0:
			scattering_present = true
	if not scattering_present or (_flags & FLAG_VOLUME) == 0:
		_field_exits = 0
	_field_dirs = clampi(policy.get("field_dirs", 2048), 64, 16384)
	while _field_exits > 0 and _field_grid > 6 and _field_bytes_for(_field_grid) > FIELD_BUDGET_BYTES:
		_field_grid -= 2
	_lights_packed = lights.duplicate()
	_spectra_packed = lighting.spectra.duplicate()
	_bg = lighting.background
	set_print_white(lighting.white_xyz)
	# Kernel cost changed: restart the adaptive dispatch unit conservatively.
	_chunk_spp = 1
	_chunk_rows = mini(height, 64)
	_field_chunk = 2048

	var planes := PackedFloat32Array()
	var absorb := PackedFloat32Array()
	var stones := StreamPeerBuffer.new()
	var triangle_data := PackedByteArray()
	var node_data := PackedByteArray()
	var region_data := PackedInt32Array()
	var surface_data := PackedFloat32Array()
	var nested_materials: Array[Dictionary] = []
	var host_index := 0
	for inst: Dictionary in instances:
		inst = inst.duplicate()
		inst["bvh_root"] = -1 if inst.has("analytic_shape") else 0
		inst["region_offset"] = region_data.size()
		region_data.append(host_index)
		if inst.has("boundaries"):
			var boundaries: GemBoundarySet = inst["boundaries"]
			inst["mesh"] = boundaries.mesh
			var local_materials: Array = inst.get("region_materials", [])
			for region in range(1, boundaries.materials.size()):
				var material := boundaries.materials[region]
				if material < 0:
					region_data.append(-1)
				elif material == 0:
					region_data.append(host_index)
				else:
					assert(material <= local_materials.size(), "Missing nested material")
					region_data.append(instances.size() + nested_materials.size())
					var nested: Dictionary = local_materials[material - 1].duplicate()
					nested["size_mm"] = inst["size_mm"] # all boundaries share stone coordinates
					nested_materials.append(nested)
					if nested.get("scatter", {}).get("sigma_per_mm", 0.0) > 0.0:
						inst["volume_present"] = 1.0
		var surfaces: Array = inst.get("surfaces", [])
		for region in range(region_data.size() - int(inst["region_offset"])):
			var finish: GemSurface = surfaces[region] if region < surfaces.size() else GemSurface.new()
			surface_data.append_array(finish.packed())
			if maxf(finish.alpha_u, finish.alpha_v) >= 0.0001:
				inst["rough_present"] = 1.0
				_field_exits = 0
		if inst.has("mesh"):
			var mesh: GemMesh = inst["mesh"]
			assert(mesh.validate().is_empty(), "Cannot render an invalid mesh: %s" % mesh.validate())
			var bvh := GemBvh.build(mesh)
			@warning_ignore("integer_division")
			inst["bvh_root"] = node_data.size() / 48 + 1
			@warning_ignore("integer_division")
			node_data.append_array(bvh.pack_nodes(node_data.size() / 48, triangle_data.size() / 64))
			triangle_data.append_array(bvh.pack_triangles())
			_field_exits = 0 # The legacy field only supports a convex plane host.
		var p: PackedFloat32Array = inst["planes"]
		if inst.has("analytic_shape"):
			var shape: Vector4 = inst["analytic_shape"]
			p = PackedFloat32Array([shape.x, shape.y, shape.z, shape.w, 0, 0, 0, 0])
			_field_exits = 0
		var ab: PackedFloat32Array = inst["absorption"]
		var ab_e: PackedFloat32Array = inst.get("absorption_eray", PackedFloat32Array())
		var stone_flags := 0
		var plane_offset := planes.size() / 8
		var absorb_offset := absorb.size()
		planes.append_array(p)
		absorb.append_array(ab)
		if not ab_e.is_empty():
			absorb.append_array(ab_e)
			stone_flags |= STONE_FLAG_HAS_ERAY
		if inst.get("dispersion_strong", false):
			stone_flags |= STONE_FLAG_DISPERSION_STRONG
		_pack_stone(stones, inst, plane_offset, p.size() / 8, absorb_offset, stone_flags)
		host_index += 1
	for material in nested_materials:
		var ab: PackedFloat32Array = material["absorption"]
		var offset := absorb.size()
		absorb.append_array(ab)
		var ab_e: PackedFloat32Array = material.get("absorption_eray", PackedFloat32Array())
		absorb.append_array(ab_e)
		_pack_stone(stones, material, 0, 0, offset, STONE_FLAG_HAS_ERAY if not ab_e.is_empty() else 0)
	_plane_count_total = planes.size() / 8
	if planes.is_empty():
		planes.resize(8)
	if triangle_data.is_empty():
		triangle_data.resize(64)
	if node_data.is_empty():
		node_data.resize(48)

	_free_scene_buffers()
	_bufs["planes"] = _rd.storage_buffer_create(planes.to_byte_array().size(), planes.to_byte_array())
	_upload_lighting_buffers()
	_bufs["absorb"] = _rd.storage_buffer_create(absorb.to_byte_array().size(), absorb.to_byte_array())
	_bufs["stones"] = _rd.storage_buffer_create(stones.data_array.size(), stones.data_array)
	_bufs["triangles"] = _rd.storage_buffer_create(triangle_data.size(), triangle_data)
	_bufs["nodes"] = _rd.storage_buffer_create(node_data.size(), node_data)
	_bufs["regions"] = _rd.storage_buffer_create(region_data.to_byte_array().size(), region_data.to_byte_array())
	_bufs["surfaces"] = _rd.storage_buffer_create(surface_data.to_byte_array().size(), surface_data.to_byte_array())

	var insts := StreamPeerBuffer.new()
	for i in _inst_count:
		_pack_inst(insts, Quaternion.IDENTITY, 0.0, 1.25, [1.0, 1.0, 1.0, 1.0], mini(i, instances.size() - 1))
	_bufs["insts"] = _rd.storage_buffer_create(insts.data_array.size(), insts.data_array)
	_instance_bytes = PackedByteArray()
	_field_state_key = ""
	_update_instance_buffer(insts.data_array)
	_inst_state = {"quat": Quaternion.IDENTITY, "rig_yaw": 0.0, "ortho_half": 1.25,
		"role_mult": [1.0, 1.0, 1.0, 1.0], "stone_index": 0}
	last_field_ms = 0.0

	_create_field_texture()
	_build_uniform_sets()
	_field_dirty = true
	reset_accumulation()


func _field_bytes_for(gn: int) -> int:
	return _inst_count * gn * gn * gn * FIELD_SLABS * 8  # RGBA16F


## Camera origins must be outside every region, including cavity geometry
## protruding beyond the host. Rotation preserves this enclosing sphere.
static func _boundary_radius(instance: Dictionary) -> float:
	var radius := 0.0
	if instance.has("analytic_shape"):
		var shape: Vector4 = instance["analytic_shape"]
		radius = maxf(shape.z, sqrt(maxf(shape.x * shape.x, shape.y * shape.y) + shape.w * shape.w))
	var mesh: GemMesh = instance.get("mesh", null)
	if instance.has("boundaries"):
		mesh = instance["boundaries"].mesh
	if mesh != null:
		for point in mesh.vertices:
			radius = maxf(radius, point.length())
	elif not instance.has("analytic_shape"):
		var data: PackedFloat32Array = instance["planes"]
		var planes: Array[Plane] = []
		for i in data.size() / 8:
			planes.append(Plane(Vector3(data[i * 8], data[i * 8 + 1], data[i * 8 + 2]), data[i * 8 + 3]))
		for point in Geometry3D.compute_convex_mesh_points(planes):
			radius = maxf(radius, point.length())
	return radius


## Scatter field texture: x = instances stacked, y, z = FIELD_SLABS slabs of
## grid_n. Written by the field pre-pass (image), read by the kernel (sampler).
func _create_field_texture() -> void:
	if _field_tex.is_valid():
		_rd.free_rid(_field_tex)
		_field_tex = RID()
	var gn := _field_grid if _field_exits > 0 else 1
	var fmt := RDTextureFormat.new()
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_3D
	fmt.width = gn * _inst_count
	fmt.height = gn
	fmt.depth = gn * FIELD_SLABS
	fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_field_tex = _rd.texture_create(fmt, RDTextureView.new())
	if not _field_sampler.is_valid():
		var ss := RDSamplerState.new()
		ss.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		ss.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
		ss.mip_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		ss.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		ss.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		ss.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		_field_sampler = _rd.sampler_create(ss)


func _pack_stone(b: StreamPeerBuffer, inst: Dictionary, p_off: int, p_cnt: int,
		a_off: int, stone_flags: int) -> void:
	var sb: Vector3 = inst["sellmeier_b"]
	var sc: Vector3 = inst["sellmeier_c"]
	var scat: Dictionary = inst.get("scatter", {})
	var zon: Dictionary = inst.get("zoning", {})
	var fluor: Dictionary = inst.get("fluorescence", {})
	var optic: Vector3 = inst.get("optic_axis", Vector3(0, 0, 1))
	var zaxis: Vector3 = zon.get("axis", Vector3(0, 0, 1))
	for v: float in [sb.x, sb.y, sb.z, inst.get("size_mm", 4.0),
			sc.x, sc.y, sc.z, inst.get("birefringence", 0.0),
			scat.get("sigma_per_mm", 0.0), scat.get("g", 0.6), zon.get("frequency", 0.0), zon.get("contrast", 0.0),
			zaxis.x, zaxis.y, zaxis.z, zon.get("phase", 0.0),
			optic.x, optic.y, optic.z, fluor.get("strength", 0.0),
			fluor.get("nm", 0.0), inst.get("absorb_scale", 1.0), inst.get("volume_present", 0.0), inst.get("rough_present", 0.0)]:
		b.put_float(v)
	for v: int in [p_off, -1 if inst.has("analytic_shape") else p_cnt, 0, 0, a_off, stone_flags, inst.get("bvh_root", 0), inst.get("region_offset", 0)]:
		b.put_32(v)
	assert(b.data_array.size() % STONE_STRIDE_BYTES == 0)


func _pack_inst(b: StreamPeerBuffer, quat: Quaternion, rig_yaw: float, ortho_half: float,
		role_mult: Array, stone_index: int) -> void:
	for v: float in [quat.x, quat.y, quat.z, quat.w,
			rig_yaw, ortho_half, role_mult[0], role_mult[1],
			role_mult[2], role_mult[3], _camera_distance, 0.0]:
		b.put_float(v)
	for v: int in [stone_index, 0, 0, 0]:
		b.put_32(v)


func _build_uniform_sets() -> void:
	# Binding order (gem_common.glsl): 0 planes, 1 lights, 2 absorb, 3 accum, 4 CIE standards,
	# 5 stones, 6 insts; 7 = scatter field (image in the pre-pass, sampler in the kernel).
	var names := {0: "planes", 1: "lights", 2: "absorb", 3: "accum", 4: "standards", 5: "stones", 6: "insts", 15: "spectra"}
	for shader_name in ["trace", "field"]:
		var uniforms: Array[RDUniform] = []
		for i: int in names:
			var u := RDUniform.new()
			u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			u.binding = i
			u.add_id(_bufs[names[i]])
			uniforms.append(u)
		var f := RDUniform.new()
		f.binding = 7
		if shader_name == "field":
			f.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
			f.add_id(_field_tex)
		else:
			f.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
			f.add_id(_field_sampler)
			f.add_id(_field_tex)
		uniforms.append(f)
		if shader_name == "trace":
			var guide := RDUniform.new()
			guide.binding = 8
			guide.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			guide.add_id(_bufs["guides"])
			uniforms.append(guide)
			for item in [[9, "ballistic"], [10, "residual"], [11, "triangles"], [12, "nodes"], [13, "regions"], [14, "surfaces"]]:
				var uniform := RDUniform.new()
				uniform.binding = item[0]
				uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
				uniform.add_id(_bufs[item[1]])
				uniforms.append(uniform)
		_sets[shader_name] = _rd.uniform_set_create(uniforms, _shaders[shader_name], 0)

	_create_print_target(Vector2i(width, height))


func _create_print_target(size: Vector2i, source := RID()) -> void:
	if not source.is_valid():
		source = _bufs["accum"]
	if _print_size == size and source == _print_source and _sets.has("print") and _rd.uniform_set_is_valid(_sets["print"]):
		return
	if _print_tex.is_valid():
		_rd.free_rid(_print_tex)
	var fmt := RDTextureFormat.new()
	fmt.width = size.x
	fmt.height = size.y
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_print_tex = _rd.texture_create(fmt, RDTextureView.new())
	_print_size = size
	var pu0 := RDUniform.new()
	pu0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	pu0.binding = 0
	pu0.add_id(source)
	_print_source = source
	var pu1 := RDUniform.new()
	pu1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	pu1.binding = 1
	pu1.add_id(_print_tex)
	_sets["print"] = _rd.uniform_set_create([pu0, pu1], _shaders["print"], 0)


# ------------------------------------------------------------------ per-frame state

func set_stone_orientation(q: Quaternion) -> void:
	_inst_state["quat"] = q
	_push_inst_state()


## Clip sample: orientation, rig yaw, per-role power multipliers, framing.
func set_clip_sample(q: Quaternion, rig_yaw: float, role_mult := Vector4.ONE, ortho_half := 1.25) -> void:
	_inst_state["quat"] = q
	_inst_state["rig_yaw"] = rig_yaw
	_inst_state["role_mult"] = [role_mult.x, role_mult.y, role_mult.z, role_mult.w]
	_inst_state["ortho_half"] = ortho_half
	_push_inst_state()


func _push_inst_state() -> void:
	if not _bufs.has("insts"):
		return
	var b := StreamPeerBuffer.new()
	_pack_inst(b, _inst_state["quat"], _inst_state["rig_yaw"], _inst_state["ortho_half"],
		_inst_state["role_mult"], _inst_state["stone_index"])
	_update_instance_buffer(b.data_array)


## Board batch path: update every instance (array of {quat, rig_yaw, ortho_half, role_mult, stone_index}).
func set_instances(states: Array) -> void:
	var b := StreamPeerBuffer.new()
	for s: Dictionary in states:
		var rm: Vector4 = s.get("role_mult", Vector4.ONE)
		_pack_inst(b, s.get("quat", Quaternion.IDENTITY), s.get("rig_yaw", 0.0),
			s.get("ortho_half", 1.25), [rm.x, rm.y, rm.z, rm.w], s.get("stone_index", 0))
	_update_instance_buffer(b.data_array)


func _update_instance_buffer(bytes: PackedByteArray) -> void:
	if bytes == _instance_bytes:
		return
	# Framing changes primary rays, but cannot change light inside the stone.
	var field_bytes := bytes.duplicate()
	for index in bytes.size() / INST_STRIDE_BYTES:
		field_bytes.encode_float(index * INST_STRIDE_BYTES + 20, 0.0)
	var key := GemContentIdentity.digest(field_bytes)
	if key != _field_state_key:
		_field_dirty = true
		_field_state_key = key
	_rd.buffer_update(_bufs["insts"], 0, bytes.size(), bytes)
	_instance_bytes = bytes


func set_seed(s: int) -> void:
	_seed = s


## Replaces all illumination atomically and retires samples only when optical
## inputs change. A white-only edit preserves the film and scatter field.
func set_lighting(lighting: GemLighting) -> void:
	assert(lighting != null)
	assert(lighting.validate().is_empty(), lighting.validate())
	set_print_white(lighting.white_xyz)
	if _lights_packed == lighting.lights and _spectra_packed == lighting.spectra and _bg == lighting.background:
		return
	_lights_packed = lighting.lights.duplicate()
	_spectra_packed = lighting.spectra.duplicate()
	_bg = lighting.background
	_light_count = _lights_packed.size() / 8
	assert(_light_count <= MAX_LIGHTS)
	for key in ["lights", "spectra"]:
		_rd.free_rid(_bufs[key])
	_upload_lighting_buffers()
	_build_uniform_sets()
	_field_dirty = true
	reset_accumulation()


func set_print_white(white_xyz: Vector3) -> void:
	_xyz_to_rgb = Colorimetry.xyz_to_srgb(white_xyz)


func _upload_lighting_buffers() -> void:
	var lights := _lights_packed.to_byte_array()
	if lights.is_empty():
		lights.resize(32) # Background-only rig: valid zero-count SSBO.
	var spectra := _spectra_packed.to_byte_array()
	assert(not spectra.is_empty())
	_bufs["lights"] = _rd.storage_buffer_create(lights.size(), lights)
	_bufs["spectra"] = _rd.storage_buffer_create(spectra.size(), spectra)


func reset_accumulation() -> void:
	var zeros := PackedByteArray()
	zeros.resize(width * height * 16)
	for name in ["accum", "ballistic", "residual"]:
		_rd.buffer_update(_bufs[name], 0, zeros.size(), zeros)
	samples_accumulated = 0
	zeros.resize(width * height * 32)
	_rd.buffer_update(_bufs["guides"], 0, zeros.size(), zeros)
	_filtered_samples = -1


func _field_push(band_group: int, texel_base: int) -> PackedByteArray:
	var pcb := StreamPeerBuffer.new()
	for v: int in [_field_grid, _field_exits, _light_count, _inst_count, _field_dirs, band_group]:
		pcb.put_32(v)
	pcb.put_float(_env_filter_rad)
	pcb.put_32(texel_base)
	for v: float in [_bg.x, _bg.y, _bg.z, _bg.w]:
		pcb.put_float(v)
	assert(pcb.data_array.size() == FIELD_PUSH_SIZE)
	return pcb.data_array


## Rebuild the scatter field now (normally implicit in accumulate()). Work is
## issued per 4 spectral bands x texel chunk, each its own submission, so no
## dispatch approaches the OS GPU watchdog whatever the grid / dirs / exits
## policy. Returns ms.
func build_scatter_field() -> float:
	if not _field_dirty:
		return 0.0
	if _field_exits <= 0:
		_field_dirty = false
		return 0.0
	var t0 := Time.get_ticks_usec()
	var texels := _inst_count * _field_grid * _field_grid * _field_grid
	@warning_ignore("integer_division")
	for band_group in FIELD_BANDS / 4:
		var base := 0
		while base < texels:
			var n := mini(_field_chunk, texels - base)
			var t1 := Time.get_ticks_usec()
			var cl := _rd.compute_list_begin()
			_rd.compute_list_bind_compute_pipeline(cl, _pipelines["field"])
			_rd.compute_list_bind_uniform_set(cl, _sets["field"], 0)
			_rd.compute_list_set_push_constant(cl, _field_push(band_group, base), FIELD_PUSH_SIZE)
			@warning_ignore("integer_division")
			_rd.compute_list_dispatch(cl, (n + FIELD_TEXELS_PER_GROUP - 1) / FIELD_TEXELS_PER_GROUP, 1, 1)
			_rd.compute_list_end()
			_rd.submit()
			_rd.sync()
			base += n
			# Adapt the chunk toward DISPATCH_TARGET_MS (same watchdog policy as the kernel).
			var ms := float(Time.get_ticks_usec() - t1) / 1000.0
			if debug_chunks:
				print("    field dispatch band %d texels %d -> %.1f ms" % [band_group, n, ms])
			if n == _field_chunk:
				if ms > DISPATCH_TARGET_MS * 1.6:
					_field_chunk = maxi(FIELD_TEXELS_PER_GROUP * 64, _field_chunk / 2)
				elif ms < DISPATCH_TARGET_MS * 0.4:
					_field_chunk = mini(1 << 20, _field_chunk * 2)
	_field_dirty = false
	field_build_count += 1
	last_field_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	return last_field_ms


## Accumulate `spp` more samples per pixel. TDR-safe: the work is issued as
## (row band x spp chunk) dispatches whose size adapts to the measured kernel
## cost (dense milk and inclusions make a path many times dearer than clean
## optics), so no single dispatch approaches the OS GPU watchdog. Returns ms.
func accumulate(spp: int) -> float:
	assert(spp > 0)
	var start := Time.get_ticks_usec()
	if _field_dirty:
		build_scatter_field()
	var t0 := Time.get_ticks_usec()
	var remaining := spp
	while remaining > 0:
		var spp_now := mini(_chunk_spp, remaining)
		var row := 0
		while row < height:
			var rows_now := mini(_chunk_rows, height - row)
			var ms := _dispatch_trace(row, rows_now, spp_now)
			if debug_chunks:
				print("    dispatch rows %d spp %d -> %.1f ms" % [rows_now, spp_now, ms])
			if ms > DISPATCH_TARGET_MS * 1.6:
				if _chunk_spp > 1:
					_chunk_spp = maxi(1, _chunk_spp / 2)
				else:
					_chunk_rows = maxi(8, (_chunk_rows / 2 + 7) / 8 * 8)
			elif ms < DISPATCH_TARGET_MS * 0.4:
				if _chunk_rows < height:
					_chunk_rows = mini(height, _chunk_rows * 2)
				else:
					_chunk_spp = mini(MAX_CHUNK_SPP, _chunk_spp * 2)
			row += rows_now
		samples_accumulated += spp_now
		remaining -= spp_now
	last_dispatch_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	last_accumulate_ms = float(Time.get_ticks_usec() - start) / 1000.0
	return last_accumulate_ms


func _dispatch_trace(row_origin: int, rows: int, spp_now: int) -> float:
	var pcb := StreamPeerBuffer.new()
	pcb.put_32(width)
	pcb.put_32(height)
	pcb.put_u32(samples_accumulated)
	pcb.put_u32(spp_now)
	pcb.put_u32(_seed)
	pcb.put_u32(_max_bounces)
	pcb.put_u32(_flags)
	pcb.put_u32(_light_count)
	pcb.put_32(_grid.x)
	pcb.put_32(_grid.y)
	pcb.put_32(_cell.x)
	pcb.put_32(_cell.y)
	pcb.put_float(_bg.x)
	pcb.put_float(_bg.y)
	pcb.put_float(_bg.z)
	pcb.put_float(_spectral_norm)
	pcb.put_float(_rad_clamp)
	pcb.put_float(_env_filter_rad)
	pcb.put_32(_field_exits)
	pcb.put_32(_field_grid)
	pcb.put_32(row_origin)
	pcb.put_32(_inst_count)
	pcb.put_float(_bg.w)
	pcb.put_float(_throughput_epsilon)
	assert(pcb.data_array.size() == PUSH_SIZE)

	var t0 := Time.get_ticks_usec()
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines["trace"])
	_rd.compute_list_bind_uniform_set(cl, _sets["trace"], 0)
	_rd.compute_list_set_push_constant(cl, pcb.data_array, PUSH_SIZE)
	@warning_ignore("integer_division")
	_rd.compute_list_dispatch(cl, (width + 7) / 8, (rows + 7) / 8, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	return float(Time.get_ticks_usec() - t0) / 1000.0


# ------------------------------------------------------------------ output

## GPU print pass. print_res is required for house print; raw bypasses mastering.
func finalize_print(print_res: GemPrint = null, raw := false, exposure := 1.0, output_size := Vector2i.ZERO, reconstruct := true) -> Image:
	var start := Time.get_ticks_usec()
	var target := Vector2i(width, height) if output_size == Vector2i.ZERO else output_size
	assert(target.x > 0 and target.y > 0)
	_create_print_target(target, reconstruct_linear() if reconstruct and _denoise_passes > 0 else _bufs["accum"])
	var pcb := StreamPeerBuffer.new()
	pcb.put_32(target.x)
	pcb.put_32(target.y)
	pcb.put_float(1.0 / maxf(1.0, float(samples_accumulated)))
	pcb.put_float(exposure * (print_res.exposure if print_res != null else 1.0))
	pcb.put_u32(1 if raw else 0)
	pcb.put_float(3.2 if print_res == null else 1.0 + 3.0 * print_res.shoulder_strength)
	pcb.put_float(print_res.contrast if print_res != null else 1.0)
	pcb.put_float(print_res.black_point if print_res != null else 0.0)
	pcb.put_float(print_res.chroma_ceiling if print_res != null else 10.0)
	pcb.put_float(print_res.chroma_soft if print_res != null else 0.1)
	pcb.put_float(print_res.highlight_desat if print_res != null else 0.0)
	pcb.put_float(0.0)
	# XYZ -> linear sRGB with the rig's as-shot white balance, as mat3 columns.
	for col: Vector3 in [_xyz_to_rgb.x, _xyz_to_rgb.y, _xyz_to_rgb.z]:
		for v: float in [col.x, col.y, col.z, 0.0]:
			pcb.put_float(v)
	for value in [width, height, 0, 0]:
		pcb.put_32(value)
	assert(pcb.data_array.size() == PRINT_PUSH_SIZE)

	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipelines["print"])
	_rd.compute_list_bind_uniform_set(cl, _sets["print"], 0)
	_rd.compute_list_set_push_constant(cl, pcb.data_array, PRINT_PUSH_SIZE)
	@warning_ignore("integer_division")
	_rd.compute_list_dispatch(cl, (target.x + 7) / 8, (target.y + 7) / 8, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	var data := _rd.texture_get_data(_print_tex, 0)
	last_print_ms = float(Time.get_ticks_usec() - start) / 1000.0
	return Image.create_from_data(target.x, target.y, false, Image.FORMAT_RGBA8, data)


## Reconstruction never overwrites the reference accumulation. It is cached
## by accumulated sample count, so exposure/style-only outputs reuse it.
func set_reconstruction(passes: int, phi := 2.0) -> void:
	_denoise_passes = clampi(passes, 0, 5)
	_denoise_phi = clampf(phi, 0.1, 8.0)
	_filtered_samples = -1


func reconstruct_linear() -> RID:
	if _denoise_passes <= 0 or samples_accumulated < 2:
		return _bufs["accum"]
	var output: RID = _bufs["residual"]
	if _filtered_samples == samples_accumulated:
		return _bufs["reconstructed"]
	var start := Time.get_ticks_usec()
	for pass_index in _denoise_passes + 1:
		var input := output
		output = _bufs["reconstructed"] if pass_index == _denoise_passes else _bufs["filter_a" if pass_index % 2 == 0 else "filter_b"]
		var uniforms: Array[RDUniform] = []
		var buffers := [input, _bufs["guides"], output, _bufs["ballistic"]]
		for binding in 4:
			var uniform := RDUniform.new()
			uniform.binding = binding
			uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
			uniform.add_id(buffers[binding])
			uniforms.append(uniform)
		var uniform_set := _rd.uniform_set_create(uniforms, _shaders["denoise"], 0)
		var push := StreamPeerBuffer.new()
		for value in [width, height, 0 if pass_index == _denoise_passes else 1 << pass_index]:
			push.put_32(value)
		for value in [float(samples_accumulated), _denoise_phi, 128.0, 0.0, 0.0]:
			push.put_float(value)
		var list := _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _pipelines["denoise"])
		_rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		_rd.compute_list_set_push_constant(list, push.data_array, 32)
		@warning_ignore("integer_division")
		_rd.compute_list_dispatch(list, (width + 7) / 8, (height + 7) / 8, 1)
		_rd.compute_list_end()
		_rd.submit()
		_rd.sync()
		_rd.free_rid(uniform_set)
	_filtered_samples = samples_accumulated
	last_denoise_ms = float(Time.get_ticks_usec() - start) / 1000.0
	return output


func read_reconstructed_xyz() -> PackedFloat32Array:
	var data := _rd.buffer_get_data(reconstruct_linear()).to_float32_array()
	var inv := 1.0 / maxf(float(samples_accumulated), 1.0)
	for index in data.size():
		data[index] *= inv
	return data


## Reads back accumulated XYZ (normalized) + coverage. For physics tests.
func read_xyz() -> PackedFloat32Array:
	var raw := _rd.buffer_get_data(_bufs["accum"]).to_float32_array()
	var inv := 1.0 / maxf(1.0, float(samples_accumulated))
	for i in raw.size():
		raw[i] *= inv
	return raw


## Scene-linear master: coverage-weighted XYZ, alpha coverage. No white
## balance, exposure, tonescale, gamut mapping, or display encoding. EXR
## consumers must read the declared XYZ color space, not assume RGB.
func read_linear_master() -> Image:
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBAF, read_xyz().to_byte_array())


## Checkpoints contain accumulation sums, not normalized images. Restoring all
## estimator buffers preserves progressive reconstruction and sample indexing.
func checkpoint() -> Dictionary:
	var buffers := {}
	for key in ["accum", "guides", "ballistic", "residual"]:
		buffers[key] = _rd.buffer_get_data(_bufs[key])
	return {"version": 1, "width": width, "height": height, "samples": samples_accumulated, "buffers": buffers}


func restore_checkpoint(state: Dictionary) -> bool:
	if state.get("version") != 1 or state.get("width") != width or state.get("height") != height or int(state.get("samples", -1)) < 0:
		return false
	var buffers: Dictionary = state.get("buffers", {})
	for key in ["accum", "guides", "ballistic", "residual"]:
		if not buffers.get(key) is PackedByteArray or buffers[key].size() != width * height * (32 if key == "guides" else 16):
			return false
	reset_accumulation()
	for key: String in buffers:
		if key in ["accum", "guides", "ballistic", "residual"]:
			_rd.buffer_update(_bufs[key], 0, buffers[key].size(), buffers[key])
	samples_accumulated = int(state["samples"])
	_filtered_samples = -1
	return true


## Load an already normalized associated XYZ master for display-only work.
## Caller supplies the rig white balance; no optical samples are generated.
func load_linear_master(master: Image) -> bool:
	if master == null or master.get_format() != Image.FORMAT_RGBAF or master.get_size() != Vector2i(width, height):
		return false
	reset_accumulation()
	var bytes := master.get_data()
	_rd.buffer_update(_bufs["accum"], 0, bytes.size(), bytes)
	samples_accumulated = 1
	return true


func profile() -> Dictionary:
	return {"accumulate_wall_ms": last_accumulate_ms, "trace_wall_ms": last_dispatch_ms,
		"field_last_build_ms": last_field_ms, "field_builds": field_build_count,
		"print_readback_wall_ms": last_print_ms, "denoise_wall_ms": last_denoise_ms, "samples": samples_accumulated,
		"field": field_info()}


## Raw scatter-field texel data (RGBA16F), for tools that inspect the field.
func debug_field_bytes() -> PackedByteArray:
	if not _field_tex.is_valid():
		return PackedByteArray()
	return _rd.texture_get_data(_field_tex, 0)


## Scatter-field configuration in effect (diagnostics).
func field_info() -> Dictionary:
	return {"exits": _field_exits, "grid": _field_grid, "dirs": _field_dirs,
		"bytes": _field_bytes_for(_field_grid) if _field_exits > 0 else 0, "build_ms": last_field_ms}


# ------------------------------------------------------------------ cleanup

func _free_scene_buffers() -> void:
	for key in ["planes", "lights", "spectra", "absorb", "stones", "insts", "triangles", "nodes", "regions", "surfaces"]:
		if _bufs.has(key) and _bufs[key].is_valid():
			_rd.free_rid(_bufs[key])
			_bufs.erase(key)


func release() -> void:
	_free_scene_buffers()
	var rids: Array = [_bufs.get("standards", RID()), _bufs.get("accum", RID()), _bufs.get("guides", RID()), _bufs.get("filter_a", RID()), _bufs.get("filter_b", RID()), _bufs.get("ballistic", RID()), _bufs.get("residual", RID()), _bufs.get("reconstructed", RID()), _print_tex, _field_tex, _field_sampler]
	rids.append_array(_pipelines.values())
	rids.append_array(_shaders.values())
	for rid in rids:
		if rid is RID and rid.is_valid():
			_rd.free_rid(rid)
	_bufs.clear()
	_pipelines.clear()
	_shaders.clear()
	if _owns_rd and _rd != null:
		_rd.free()
		_rd = null
