class_name GemTracer
extends RefCounted
## Lapidary GPU tracer host — kernel v1.
##
## Consumes StoneInstance dictionaries from LapidaryStoneCompiler plus a light
## rig, dispatches the spectral path tracer, and finalizes through the GPU
## print pass (house print or raw display transform). Batch-ready: stones are
## ranges in shared buffers, instances sit on a pixel grid (1x1 = single stone).
##
## Requires a RenderingDevice-capable context (NOT --headless).

const SHADER_PATH := "res://core/lapidary/tracer/shaders/gem_pathtrace.glsl"
const PRINT_SHADER_PATH := "res://core/lapidary/tracer/shaders/gem_print.glsl"
const PUSH_SIZE := 80
const PRINT_PUSH_SIZE := 48
const STONE_STRIDE_BYTES := 144
const INST_STRIDE_BYTES := 64

const FLAG_DISPERSION := 1
const FLAG_BIREF := 2
const FLAG_VOLUME_SHIFT := 2
const FLAG_FLUOR := 16

const STONE_FLAG_HAS_ERAY := 1
const STONE_FLAG_DISPERSION_STRONG := 2

var width := 0
var height := 0
var samples_accumulated := 0
var last_dispatch_ms := 0.0

var _rd: RenderingDevice
var _owns_rd := false
var _shader: RID
var _pipeline: RID
var _print_shader: RID
var _print_pipeline: RID
var _bufs: Dictionary = {}
var _uniform_set: RID
var _print_set: RID
var _print_tex: RID

var _plane_count_total := 0
var _light_count := 0
var _spectral_norm := 0.0
var _frame := 0
var _seed := 1
var _max_bounces := 32
var _flags := 0
var _grid := Vector2i.ONE
var _cell := Vector2i.ZERO
var _bg := Vector3(0.30, 0.16, 0.05)
var _rad_clamp := 48.0
# Cached single-instance state (grid 1x1 convenience path).
var _inst_state := {
	"quat": Quaternion.IDENTITY, "rig_yaw": 0.0, "ortho_half": 1.25,
	"role_mult": [1.0, 1.0, 1.0, 1.0], "stone_index": 0,
}


static func create(p_width: int, p_height: int, rd: RenderingDevice = null) -> GemTracer:
	var t := GemTracer.new()
	t.width = p_width
	t.height = p_height
	if rd != null:
		t._rd = rd
	else:
		t._rd = RenderingServer.create_local_rendering_device()
		t._owns_rd = true
	if t._rd == null:
		push_error("GemTracer: no RenderingDevice (headless mode has none).")
		return null
	if not t._compile_shaders():
		return null
	var zeros := PackedByteArray()
	zeros.resize(p_width * p_height * 16)
	t._bufs["accum"] = t._rd.storage_buffer_create(zeros.size(), zeros)
	t._spectral_norm = (400.0 / 4.0) / _integral_ybar()
	t._cell = Vector2i(p_width, p_height)
	return t


func _compile_shaders() -> bool:
	for entry in [[SHADER_PATH, "trace"], [PRINT_SHADER_PATH, "print"]]:
		var text := FileAccess.get_file_as_string(entry[0])
		if text.is_empty():
			push_error("GemTracer: cannot read %s" % entry[0])
			return false
		var src := RDShaderSource.new()
		src.source_compute = text
		var spirv := _rd.shader_compile_spirv_from_source(src)
		if spirv.compile_error_compute != "":
			push_error("GemTracer %s shader compile error:\n%s" % [entry[1], spirv.compile_error_compute])
			return false
		var shader := _rd.shader_create_from_spirv(spirv)
		if entry[1] == "trace":
			_shader = shader
			_pipeline = _rd.compute_pipeline_create(shader)
		else:
			_print_shader = shader
			_print_pipeline = _rd.compute_pipeline_create(shader)
	return true


static func _integral_ybar() -> float:
	var total := 0.0
	for i in 401:
		var w := 380.0 + float(i)
		var t1 := (w - 568.8) * (0.0213 if w < 568.8 else 0.0247)
		var t2 := (w - 530.9) * (0.0613 if w < 530.9 else 0.0322)
		total += 0.821 * exp(-0.5 * t1 * t1) + 0.286 * exp(-0.5 * t2 * t2)
	return total


# ------------------------------------------------------------------ configure

## Full-featured path: StoneInstance from LapidaryStoneCompiler + lights + rung policy.
## policy keys (see GemRung.TABLE): max_bounces, dispersion, birefringence, volume.
## Ingests the instance's own seed; background still comes from set_background
## (it belongs to the rig, not the stone).
func configure_stone(instance: Dictionary, lights: PackedFloat32Array, policy: Dictionary) -> void:
	if instance.has("seed"):
		_seed = int(instance["seed"])
	configure_stones([instance], lights, policy, Vector2i.ONE)


## Multi-stone batch: instances laid out on a grid of equal cells (board atlas).
func configure_stones(instances: Array, lights: PackedFloat32Array, policy: Dictionary, grid: Vector2i) -> void:
	assert(not instances.is_empty() and lights.size() % 8 == 0)
	_grid = grid
	@warning_ignore("integer_division")
	_cell = Vector2i(width / grid.x, height / grid.y)
	_light_count = lights.size() / 8
	_max_bounces = policy.get("max_bounces", 32)
	_flags = 0
	if policy.get("dispersion", false):
		_flags |= FLAG_DISPERSION
	if policy.get("birefringence", false):
		_flags |= FLAG_BIREF
	_flags |= (int(policy.get("volume", 1)) & 3) << FLAG_VOLUME_SHIFT
	if policy.get("fluorescence", true):
		_flags |= FLAG_FLUOR
	_rad_clamp = policy.get("rad_clamp", 48.0)

	var planes := PackedFloat32Array()
	var prims := PackedFloat32Array()
	var absorb := PackedFloat32Array()
	var stones := StreamPeerBuffer.new()
	for inst: Dictionary in instances:
		var p: PackedFloat32Array = inst["planes"]
		var pr: PackedFloat32Array = inst.get("inclusions", PackedFloat32Array())
		var ab: PackedFloat32Array = inst["absorption"]
		var ab_e: PackedFloat32Array = inst.get("absorption_eray", PackedFloat32Array())
		var stone_flags := 0
		var plane_offset := planes.size() / 8
		var prim_offset := prims.size() / 16
		var absorb_offset := absorb.size()
		planes.append_array(p)
		prims.append_array(pr)
		absorb.append_array(ab)
		if not ab_e.is_empty():
			absorb.append_array(ab_e)
			stone_flags |= STONE_FLAG_HAS_ERAY
		if inst.get("dispersion_strong", false):
			stone_flags |= STONE_FLAG_DISPERSION_STRONG
		_pack_stone(stones, inst, plane_offset, p.size() / 8, prim_offset, pr.size() / 16, absorb_offset, stone_flags)
	_plane_count_total = planes.size() / 8
	if prims.is_empty():
		prims.resize(16) # SSBO cannot be zero-sized

	_free_scene_buffers()
	_bufs["planes"] = _rd.storage_buffer_create(planes.to_byte_array().size(), planes.to_byte_array())
	_bufs["lights"] = _rd.storage_buffer_create(lights.to_byte_array().size(), lights.to_byte_array())
	_bufs["absorb"] = _rd.storage_buffer_create(absorb.to_byte_array().size(), absorb.to_byte_array())
	_bufs["prims"] = _rd.storage_buffer_create(prims.to_byte_array().size(), prims.to_byte_array())
	_bufs["stones"] = _rd.storage_buffer_create(stones.data_array.size(), stones.data_array)

	var insts := StreamPeerBuffer.new()
	for i in grid.x * grid.y:
		_pack_inst(insts, Quaternion.IDENTITY, 0.0, 1.25, [1.0, 1.0, 1.0, 1.0], mini(i, instances.size() - 1))
	_bufs["insts"] = _rd.storage_buffer_create(insts.data_array.size(), insts.data_array)

	_build_uniform_sets()
	reset_accumulation()


## Compatibility path (spike-era API): single stone, no inclusions/wear.
func configure(planes: PackedFloat32Array, lights: PackedFloat32Array, absorb: PackedFloat32Array, params: Dictionary) -> void:
	var instance := {
		"planes": planes,
		"absorption": absorb,
		"inclusions": PackedFloat32Array(),
		"sellmeier_b": params.get("sellmeier_b", Vector3.ZERO),
		"sellmeier_c": params.get("sellmeier_c", Vector3.ZERO),
		"size_mm": params.get("size_mm", 3.0),
		"seed": params.get("seed", 1),
		"scatter": {"sigma_per_mm": 0.0, "g": 0.6},
		"zoning": {"axis": Vector3(0, 0, 1), "frequency": 0.0, "contrast": 0.0, "phase": 0.0},
		"wear": {"roughness_boost": 0.01, "scratch_density": 0.0, "scratch_aniso": 0.75,
			"abrasion": 0.0, "dirt": 0.0, "edge_round": 0.008},
		"birefringence": 0.0,
		"optic_axis": Vector3(0, 0, 1),
		"fluorescence": {"nm": 0.0, "strength": 0.0},
		"dispersion_strong": false,
		"absorb_scale": params.get("absorb_scale", 1.0),
	}
	_seed = params.get("seed", 1)
	_bg = params.get("background", Vector3(0.30, 0.16, 0.05))
	configure_stone(instance, lights, {"max_bounces": params.get("max_bounces", 32), "volume": 0})
	_inst_state["quat"] = params.get("stone_quat", Quaternion.IDENTITY)
	_inst_state["ortho_half"] = params.get("ortho_half", 1.25)
	_push_inst_state()


func _pack_stone(b: StreamPeerBuffer, inst: Dictionary, p_off: int, p_cnt: int,
		i_off: int, i_cnt: int, a_off: int, stone_flags: int) -> void:
	var sb: Vector3 = inst["sellmeier_b"]
	var sc: Vector3 = inst["sellmeier_c"]
	var scat: Dictionary = inst.get("scatter", {})
	var zon: Dictionary = inst.get("zoning", {})
	var wear: Dictionary = inst.get("wear", {})
	var fluor: Dictionary = inst.get("fluorescence", {})
	var optic: Vector3 = inst.get("optic_axis", Vector3(0, 0, 1))
	var zaxis: Vector3 = zon.get("axis", Vector3(0, 0, 1))
	for v: float in [sb.x, sb.y, sb.z, inst.get("size_mm", 4.0),
			sc.x, sc.y, sc.z, inst.get("birefringence", 0.0),
			scat.get("sigma_per_mm", 0.0), scat.get("g", 0.6), zon.get("frequency", 0.0), zon.get("contrast", 0.0),
			zaxis.x, zaxis.y, zaxis.z, zon.get("phase", 0.0),
			optic.x, optic.y, optic.z, fluor.get("strength", 0.0),
			wear.get("roughness_boost", 0.01), wear.get("scratch_density", 0.0),
			wear.get("scratch_aniso", 0.75), wear.get("abrasion", 0.0),
			wear.get("dirt", 0.0), wear.get("edge_round", 0.008),
			fluor.get("nm", 0.0), inst.get("absorb_scale", 1.0)]:
		b.put_float(v)
	for v: int in [p_off, p_cnt, i_off, i_cnt, a_off, stone_flags, 0, 0]:
		b.put_32(v)


func _pack_inst(b: StreamPeerBuffer, quat: Quaternion, rig_yaw: float, ortho_half: float,
		role_mult: Array, stone_index: int) -> void:
	for v: float in [quat.x, quat.y, quat.z, quat.w,
			rig_yaw, ortho_half, role_mult[0], role_mult[1],
			role_mult[2], role_mult[3], 0.0, 0.0]:
		b.put_float(v)
	for v: int in [stone_index, 0, 0, 0]:
		b.put_32(v)


func _build_uniform_sets() -> void:
	var names := ["planes", "lights", "absorb", "accum", "prims", "stones", "insts"]
	var uniforms: Array[RDUniform] = []
	for i in names.size():
		var u := RDUniform.new()
		u.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		u.binding = i if i != 3 else 3
		u.add_id(_bufs[names[i]])
		uniforms.append(u)
	# Binding order in shader: 0 planes, 1 lights, 2 absorb, 3 accum, 4 prims, 5 stones, 6 insts
	uniforms[0].binding = 0
	uniforms[1].binding = 1
	uniforms[2].binding = 2
	uniforms[3].binding = 3
	uniforms[4].binding = 4
	uniforms[5].binding = 5
	uniforms[6].binding = 6
	_uniform_set = _rd.uniform_set_create(uniforms, _shader, 0)

	if not _print_tex.is_valid():
		var fmt := RDTextureFormat.new()
		fmt.width = width
		fmt.height = height
		fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
		_print_tex = _rd.texture_create(fmt, RDTextureView.new())
	var pu0 := RDUniform.new()
	pu0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	pu0.binding = 0
	pu0.add_id(_bufs["accum"])
	var pu1 := RDUniform.new()
	pu1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	pu1.binding = 1
	pu1.add_id(_print_tex)
	_print_set = _rd.uniform_set_create([pu0, pu1], _print_shader, 0)


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
	_rd.buffer_update(_bufs["insts"], 0, b.data_array.size(), b.data_array)


## Board batch path: update every instance (array of {quat, rig_yaw, ortho_half, role_mult, stone_index}).
func set_instances(states: Array) -> void:
	var b := StreamPeerBuffer.new()
	for s: Dictionary in states:
		var rm: Vector4 = s.get("role_mult", Vector4.ONE)
		_pack_inst(b, s.get("quat", Quaternion.IDENTITY), s.get("rig_yaw", 0.0),
			s.get("ortho_half", 1.25), [rm.x, rm.y, rm.z, rm.w], s.get("stone_index", 0))
	_rd.buffer_update(_bufs["insts"], 0, b.data_array.size(), b.data_array)


func set_seed(s: int) -> void:
	_seed = s


func set_background(bg: Vector3) -> void:
	_bg = bg


# ------------------------------------------------------------------ dispatch

func reset_accumulation() -> void:
	var zeros := PackedByteArray()
	zeros.resize(width * height * 16)
	_rd.buffer_update(_bufs["accum"], 0, zeros.size(), zeros)
	samples_accumulated = 0
	_frame = 0


func accumulate(spp: int) -> float:
	var pcb := StreamPeerBuffer.new()
	pcb.put_32(width)
	pcb.put_32(height)
	pcb.put_u32(_frame)
	pcb.put_u32(spp)
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
	pcb.put_float(0.0)
	pcb.put_float(0.0)
	pcb.put_float(0.0)
	assert(pcb.data_array.size() == PUSH_SIZE)

	var t0 := Time.get_ticks_usec()
	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _pipeline)
	_rd.compute_list_bind_uniform_set(cl, _uniform_set, 0)
	_rd.compute_list_set_push_constant(cl, pcb.data_array, PUSH_SIZE)
	@warning_ignore("integer_division")
	_rd.compute_list_dispatch(cl, (width + 7) / 8, (height + 7) / 8, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	last_dispatch_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	samples_accumulated += spp
	_frame += 1
	return last_dispatch_ms


# ------------------------------------------------------------------ output

## GPU print pass. print_res == null uses neutral defaults; raw bypasses the house print.
func finalize_print(print_res: GemPrint = null, raw := false, exposure := 1.0) -> Image:
	var pcb := StreamPeerBuffer.new()
	pcb.put_32(width)
	pcb.put_32(height)
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
	assert(pcb.data_array.size() == PRINT_PUSH_SIZE)

	var cl := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(cl, _print_pipeline)
	_rd.compute_list_bind_uniform_set(cl, _print_set, 0)
	_rd.compute_list_set_push_constant(cl, pcb.data_array, PRINT_PUSH_SIZE)
	@warning_ignore("integer_division")
	_rd.compute_list_dispatch(cl, (width + 7) / 8, (height + 7) / 8, 1)
	_rd.compute_list_end()
	_rd.submit()
	_rd.sync()
	var data := _rd.texture_get_data(_print_tex, 0)
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)


## Reads back accumulated XYZ (normalized) + coverage. For physics tests.
func read_xyz() -> PackedFloat32Array:
	var raw := _rd.buffer_get_data(_bufs["accum"]).to_float32_array()
	var inv := 1.0 / maxf(1.0, float(samples_accumulated))
	for i in raw.size():
		raw[i] *= inv
	return raw


## CPU finalize (compat; prefer finalize_print).
func finalize_image(exposure := 1.0) -> Image:
	var data := read_xyz()
	var bytes := PackedByteArray()
	bytes.resize(width * height * 4)
	for i in width * height:
		var x := data[i * 4 + 0]
		var y := data[i * 4 + 1]
		var z := data[i * 4 + 2]
		var cov := clampf(data[i * 4 + 3], 0.0, 1.0)
		var r := (3.2406 * x - 1.5372 * y - 0.4986 * z) * exposure
		var g := (-0.9689 * x + 1.8758 * y + 0.0415 * z) * exposure
		var bl := (0.0557 * x - 0.2040 * y + 1.0570 * z) * exposure
		r = maxf(0.0, r)
		g = maxf(0.0, g)
		bl = maxf(0.0, bl)
		r = r / (1.0 + r)
		g = g / (1.0 + g)
		bl = bl / (1.0 + bl)
		bytes[i * 4 + 0] = int(clampf(pow(r, 1.0 / 2.2), 0.0, 1.0) * 255.0)
		bytes[i * 4 + 1] = int(clampf(pow(g, 1.0 / 2.2), 0.0, 1.0) * 255.0)
		bytes[i * 4 + 2] = int(clampf(pow(bl, 1.0 / 2.2), 0.0, 1.0) * 255.0)
		bytes[i * 4 + 3] = int(cov * 255.0)
	return Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, bytes)


# ------------------------------------------------------------------ cleanup

func _free_scene_buffers() -> void:
	for key in ["planes", "lights", "absorb", "prims", "stones", "insts"]:
		if _bufs.has(key) and _bufs[key].is_valid():
			_rd.free_rid(_bufs[key])
			_bufs.erase(key)


func release() -> void:
	_free_scene_buffers()
	for rid in [_bufs.get("accum", RID()), _print_tex, _pipeline, _shader, _print_pipeline, _print_shader]:
		if rid is RID and rid.is_valid():
			_rd.free_rid(rid)
	_bufs.clear()
	if _owns_rd and _rd != null:
		_rd.free()
		_rd = null
