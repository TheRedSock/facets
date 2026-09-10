extends SceneTree
const V := preload("res://core/lapidary/crystal_modes.gd")
var failures := 0

func _initialize() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(1)
		return
	var data := PackedFloat32Array()
	var references: Array[Dictionary] = []
	for index in 180:
		var source_axis := Vector3(sin(index * 0.4), cos(index * 0.3), 0.7).normalized()
		var target_axis := Vector3(sin(index * 0.7), cos(index * 0.5), 0.3).normalized()
		var rotation := Basis(Vector3(0.3, 0.7, -0.4).normalized(), index * 0.21)
		source_axis = rotation * source_axis
		target_axis = rotation * target_axis
		var normal := rotation * Vector3.BACK
		var tangent := rotation * Vector3((index % 17) * 0.095, 0, 0)
		for mode in 2:
			var input := PackedFloat32Array([1 if index % 3 == 0 else 1.6, 1 if index % 3 == 0 else 1.8,
				1 if index % 3 == 1 else 1.7, 1 if index % 3 == 1 else 1.5,
				source_axis.x, source_axis.y, source_axis.z, mode, target_axis.x, target_axis.y, target_axis.z, 0,
				normal.x, normal.y, normal.z, 0, tangent.x, tangent.y, tangent.z, 0])
			var n := V.unit(V.vec(input[12], input[13], input[14]))
			var t := V.vec(input[16], input[17], input[18])
			t = V.subtract(t, V.scale(n, V.dot(t, n)))
			# Store the projected tangent. The CPU consumes the same float32 wire
			# values as the GPU, then projects once more in float64.
			for axis in 3:
				input[16 + axis] = t[axis]
			t = V.vec(input[16], input[17], input[18])
			t = V.subtract(t, V.scale(n, V.dot(t, n)))
			var source := {"no": input[0], "ne": input[1], "axis": V.vec(input[4], input[5], input[6])}
			var target := {"no": input[2], "ne": input[3], "axis": V.vec(input[8], input[9], input[10])}
			var incoming := V.modes(source.no, source.ne, source.axis, n, t, 1)[mode]
			if incoming.evanescent or incoming.normal_flux < 1e-7:
				continue
			var result := GemCrystalInterface.scatter(source, target, n, incoming)
			if result.has("error"):
				printerr(result.error)
				failures += 1
				continue
			references.append(result)
			data.append_array(input)
	var source := RDShaderSource.new()
	source.source_compute = "#version 450\n" + FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_crystal.glsl") + """
layout(local_size_x=32) in;
layout(set=0,binding=0,std430) readonly buffer Inputs { vec4 inputs[]; };
layout(set=0,binding=1,std430) buffer Outputs { vec4 outputs[]; };
void main() {
 int i=int(gl_GlobalInvocationID.x); if(i>=CASE_COUNT) return;
 vec4 indices=inputs[i*5], sa=inputs[i*5+1], ta=inputs[i*5+2];
 vec3 normal=normalize(inputs[i*5+3].xyz);
 vec3 tangent=inputs[i*5+4].xyz; tangent-=normal*dot(normal,tangent);
 CrystalMode incoming=crystal_mode(indices.x,indices.y,sa.xyz,normal,tangent,1.0,sa.w>0.5);
 CrystalInterface result=crystal_interface(indices.xy,sa.xyz,indices.zw,ta.xyz,normal,incoming);
 outputs[i*12]=result.power;
 outputs[i*12+1]=vec4(result.amplitude[0],result.amplitude[1]);
 outputs[i*12+2]=vec4(result.amplitude[2],result.amplitude[3]);
 outputs[i*12+3]=vec4(result.valid?1.0:0.0,result.residual,0,0);
 for(int j=0;j<4;j++) {
  outputs[i*12+4+j*2]=vec4(result.mode[j].q,result.mode[j].normal_flux,result.mode[j].evanescent?1.0:0.0);
  outputs[i*12+5+j*2]=vec4(normalize(result.mode[j].poynting),0);
 }
}
""".replace("CASE_COUNT", str(references.size()))
	var spirv := rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		printerr(spirv.compile_error_compute)
		rd.free()
		quit(1)
		return
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var input_buffer := rd.storage_buffer_create(data.size() * 4, data.to_byte_array())
	var output_buffer := rd.storage_buffer_create(references.size() * 192)
	var uniforms: Array[RDUniform] = []
	for entry in [[0, input_buffer], [1, output_buffer]]:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = entry[0]
		uniform.add_id(entry[1])
		uniforms.append(uniform)
	var uniform_set := rd.uniform_set_create(uniforms, shader, 0)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_dispatch(list, ceili(references.size() / 32.0), 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var values := rd.buffer_get_data(output_buffer).to_float32_array()
	var max_power := 0.0
	var max_amplitude := 0.0
	var max_q := 0.0
	var max_ray := 0.0
	var max_flux_error := 0.0
	var max_residual := 0.0
	for value in values:
		if not is_finite(value):
			failures += 1
	for index in references.size():
		var offset := index * 48
		if values[offset + 12] != 1:
			failures += 1
		var sum := 0.0
		for branch in 4:
			var reference: Dictionary = references[index].branches[branch]
			max_power = maxf(max_power, absf(values[offset + branch] - reference.power))
			sum += values[offset + branch]
			for part in 2:
				max_amplitude = maxf(max_amplitude, absf(values[offset + 4 + branch * 2 + part] - reference.amplitude[part]))
				max_q = maxf(max_q, absf(values[offset + 16 + branch * 8 + part] - reference.mode.q[part]))
			var ray := V.vec(values[offset + 20 + branch * 8], values[offset + 21 + branch * 8], values[offset + 22 + branch * 8])
			var difference := V.subtract(ray, reference.mode.ray)
			max_ray = maxf(max_ray, sqrt(V.dot(difference, difference)))
		max_flux_error = maxf(max_flux_error, absf(sum - 1))
		max_residual = maxf(max_residual, values[offset + 13])
	if max_power > 1e-5 or max_amplitude > 1e-5 or max_q > 1e-5 or max_ray > 1e-5 or max_flux_error > 1e-5 or max_residual > 1e-5:
		failures += 1
	var report := {"interfaces": references.size(), "failures": failures, "max_power_error": max_power,
		"max_amplitude_error": max_amplitude, "max_q_error": max_q, "max_ray_error": max_ray,
		"max_flux_error": max_flux_error, "max_continuity_residual": max_residual}
	GemArtifactStore.atomic_write("res://artifacts/reference/crystal-gpu.json", JSON.stringify(report, "\t").to_utf8_buffer())
	print("Crystal GPU: " + JSON.stringify(report))
	for rid in [uniform_set, pipeline, shader, input_buffer, output_buffer]:
		rd.free_rid(rid)
	rd.free()
	quit(1 if failures else 0)
