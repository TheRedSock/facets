extends SceneTree
## Tests the real GLSL field sampler independently, then verifies full transport.
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_sampler()
	_transport()
	print("GPU spatial volume: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _sampler() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		check(false, "local GPU device")
		return
	var source := RDShaderSource.new()
	source.source_compute = "#version 450\n" + FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_common.glsl") + FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_volume.glsl") + """
layout(local_size_x=64) in;
layout(set=0,binding=16,std430) buffer Results { vec4 results[]; };
void main() {
 int i=int(gl_GlobalInvocationID.x);
 Stone st; st.sell_b_size=vec4(0,0,0,1); st.scatter_zone=vec4(0.03,0,0,0); st.ranges0=ivec4(0,0,0,3);
 vec3 origin=vec3(0.25*sin(float(i)*0.37),0.12,-2);
 vec3 direction=normalize(vec3(0.1*cos(float(i)*0.21),0,1));
 float tau=-log(1.0-(float(i%256)+0.5)/256.0);
 float t=scatter_distance(st,origin,direction,4.0,tau);
 results[i*3+1]=vec4(origin,0); results[i*3+2]=vec4(direction,0);
 results[i*3]=vec4(t,tau,field_columns(st,origin,direction,4.0).y,scattering_depth(st,origin,direction,min(t,4.0)));
}
"""
	var spirv := rd.shader_compile_spirv_from_source(source)
	check(spirv.compile_error_compute.is_empty(), "field sampler compiles: " + spirv.compile_error_compute)
	if not spirv.compile_error_compute.is_empty():
		rd.free()
		return
	var fields: Array[GemVolumeField] = []
	var data := PackedFloat32Array()
	for index in 3:
		var field := GemVolumeField.new()
		field.center_mm = Vector3(0.1 * index, 0, -0.7 + index * 0.7)
		field.radius_mm = Vector3(0.55, 0.8, 0.25 + index * 0.09)
		field.orientation = Quaternion(Vector3.UP, index * 0.2)
		field.scatter_per_mm = 3.0 + index
		fields.append(field)
		data.append_array(field.packed())
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var input := rd.storage_buffer_create(data.size() * 4, data.to_byte_array())
	var output := rd.storage_buffer_create(1024 * 48)
	var uniforms: Array[RDUniform] = []
	var dummy := rd.storage_buffer_create(401 * 16)
	for entry in [[0, dummy], [1, dummy], [2, dummy], [3, dummy], [4, dummy], [5, dummy], [6, dummy], [7, input], [15, dummy], [16, output]]:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = entry[0]
		uniform.add_id(entry[1])
		uniforms.append(uniform)
	var set := rd.uniform_set_create(uniforms, shader, 0)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, set, 0)
	rd.compute_list_dispatch(list, 16, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var result := rd.buffer_get_data(output).to_float32_array()
	var max_error := 0.0
	var depth_error := 0.0
	var escape_errors := 0
	for index in 1024:
		var origin := Vector3(result[index * 12 + 4], result[index * 12 + 5], result[index * 12 + 6])
		var direction := Vector3(result[index * 12 + 8], result[index * 12 + 9], result[index * 12 + 10])
		var t := result[index * 12]
		var tau := result[index * 12 + 1]
		var total := 0.12
		var actual := 0.03 * minf(t, 4.0)
		for field in fields:
			total += field.column(origin, direction, 4.0) * field.scatter_per_mm
			actual += field.column(origin, direction, minf(t, 4.0)) * field.scatter_per_mm
		depth_error = maxf(depth_error, absf(total - 0.12 - result[index * 12 + 2]))
		if (t > 4.0) != (tau >= total):
			escape_errors += 1
		if t <= 4.0:
			max_error = maxf(max_error, absf(actual - tau))
	check(depth_error < 0.00002, "GPU/CPU integrated depth agrees: %.9f" % depth_error)
	check(escape_errors == 0, "CDF escape events agree")
	check(max_error < 0.00003, "sampled collision inverts independent CPU CDF: %.9f" % max_error)
	for rid in [set, pipeline, shader, input, output, dummy]:
		rd.free_rid(rid)
	rd.free()

func _transport() -> void:
	var tracer := GemTracer.create(32, 32)
	if tracer == null:
		check(false, "tracer compiles")
		return
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var field := GemVolumeField.new()
	field.radius_mm = Vector3(3, 2, 0.6)
	field.absorption_concentration = 3.0
	stone.condition.volume_fields.append(field)
	var inst := LapidaryStoneCompiler.compile(stone)
	inst["size_mm"] = 1.0
	inst["sellmeier_b"] = Vector3.ZERO
	inst["sellmeier_c"] = Vector3.ZERO
	inst["birefringence"] = 0.0
	inst["absorption"].fill(0.2)
	inst["absorption_eray"] = PackedFloat32Array()
	inst["zoning"] = {}
	inst["scatter"] = {"sigma_per_mm": 0.0, "g": 0.0}
	var cube := load("res://tests/lapidary/test_boundaries.gd").box(Vector3(-1, -1, -1), Vector3(1, 1, 1)) as GemMesh
	inst["mesh"] = cube
	inst["planes"] = PackedFloat32Array()
	var lighting := GemLighting.analytic(PackedFloat32Array(), Vector4(1, 1, 1, 0))
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy["birefringence"] = false
	tracer.configure_stone(inst, lighting, policy)
	tracer.accumulate(1024)
	var expected := 0.0
	var cavity_expected := 0.0
	for y in range(14, 18):
		for x in range(14, 18):
			for sy in 8:
				for sx in 8:
					var px := ((x + (sx + 0.5) / 8.0 - 0.5) / 32.0 * 2.0 - 1.0) * 1.25
					var py := -((y + (sy + 0.5) / 8.0 - 0.5) / 32.0 * 2.0 - 1.0) * 1.25
					expected += exp(-0.2 * (2.0 + 3.0 * field.column(Vector3(px, py, 1), Vector3.FORWARD, 2.0))) / 1024.0
					var column := field.column(Vector3(px, py, 1), Vector3.FORWARD, 2.0) - field.column(Vector3(px, py, 0.2), Vector3.FORWARD, 0.4)
					cavity_expected += exp(-0.2 * (1.6 + 3.0 * column)) / 1024.0
	check(absf(_center_y(tracer.read_xyz()) - expected) < 0.0001, "full transport matches heterogeneous Beer-Lambert")
	inst.erase("mesh")
	var planes := PackedFloat32Array()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		for sign_value in [-1.0, 1.0]:
			var normal: Vector3 = axis * sign_value
			planes.append_array(PackedFloat32Array([normal.x, normal.y, normal.z, 1, 0, 0, 0, 0]))
	inst["planes"] = planes
	tracer.configure_stone(inst, lighting, policy)
	tracer.accumulate(1024)
	check(absf(_center_y(tracer.read_xyz()) - expected) < 0.0001, "convex fast path agrees with the field mesh transport")
	var boundaries := GemBoundarySet.new()
	boundaries.add(cube, 0)
	boundaries.add(load("res://tests/lapidary/test_boundaries.gd").box(Vector3(-0.5, -0.5, -0.2), Vector3(0.5, 0.5, 0.2)), -1)
	inst["boundaries"] = boundaries
	tracer.configure_stone(inst, lighting, policy)
	tracer.accumulate(1024)
	check(absf(_center_y(tracer.read_xyz()) - cavity_expected) < 0.0001, "spatial absorption is clipped away inside a cavity")
	inst.erase("boundaries")
	inst["absorption"].fill(0.0)
	field.scatter_per_mm = 4.0
	tracer.configure_stone(inst, lighting, policy)
	tracer.accumulate(128)
	check(absf(_center_y(tracer.read_xyz()) - 1.0) < 0.001, "heterogeneous multiple scattering preserves uniform radiance")
	var whole := tracer.read_xyz()
	tracer.reset_accumulation()
	for count in [3, 11, 19, 95]:
		tracer.accumulate(count)
	var partitioned := tracer.read_xyz()
	var error := 0.0
	for index in whole.size():
		error = maxf(error, absf(whole[index] - partitioned[index]))
	check(error < 0.000002, "field sampling preserves sample partition invariance")
	tracer.release()

func _center_y(values: PackedFloat32Array) -> float:
	var total := 0.0
	for y in range(14, 18):
		for x in range(14, 18):
			total += values[(y * 32 + x) * 4 + 1] / 16.0
	return total
