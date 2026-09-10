extends SceneTree
const V := preload("res://core/lapidary/crystal_modes.gd")
var failures := 0
var stress := "--stress" in OS.get_cmdline_user_args()
var fp64 := "--fp64" in OS.get_cmdline_user_args()

func _initialize() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(1)
		return
	var data := PackedFloat32Array()
	var inputs: Array[PackedFloat32Array] = []
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
			inputs.append(input)
	# Real principal dispersion feeds the independent Maxwell implementation;
	# it is not approximated by a constant delta-n in these interface cases.
	for species_id in ["quartz", "corundum"]:
		var species: GemSpecies = load("res://data/lapidary/species/" + species_id + ".tres")
		for wavelength in [380, 486.1, 589.3, 656.3, 780]:
			for angle in [0.0, 0.3, 0.8]:
				for mode in 2:
					inputs.append(PackedFloat32Array([1, 1, species.ior_at(wavelength), species.extraordinary_ior_at(wavelength),
						0, 0, 1, mode, 0.6, 0, 0.8, 0, 0, 0, 1, 0, angle, 0, 0, 0]))
	if stress:
		inputs.append_array(_stress_inputs())
	for input in inputs:
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
		var incoming := V.modes(source.no, source.ne, source.axis, n, t, 1)[int(input[7])]
		if incoming.evanescent or incoming.normal_flux < 1e-7:
			continue
		var result := GemCrystalInterface.scatter(source, target, n, incoming)
		if result.has("error"):
			printerr(result.error)
			failures += 1
			continue
		# Feed the identical physical incident Jones state into both solvers.
		# Near the optic axis, their arbitrary modal bases can differ without
		# implying a different material; comparing basis labels is misleading.
		for field in ["E_real", "E_imag", "H_real", "H_imag"]:
			var value: PackedFloat64Array = incoming[field]
			input.append_array(PackedFloat32Array([value[0], value[1], value[2], 0]))
		references.append(result)
		data.append_array(input)
	var source := RDShaderSource.new()
	var module := GemCrystalShader.module(fp64)
	source.source_compute = "#version 450\n" + module + """
layout(local_size_x=32) in;
layout(set=0,binding=0,std430) readonly buffer Inputs { vec4 inputs[]; };
layout(set=0,binding=1,std430) buffer Outputs { vec4 outputs[]; };
void main() {
 int i=int(gl_GlobalInvocationID.x); if(i>=CASE_COUNT) return;
 vec4 indices=inputs[i*9], sa=inputs[i*9+1], ta=inputs[i*9+2];
 vec3 normal=normalize(inputs[i*9+3].xyz);
 vec3 tangent=inputs[i*9+4].xyz; tangent-=normal*dot(normal,tangent);
 CrystalMode incoming=crystal_mode(indices.x,indices.y,sa.xyz,normal,tangent,1.0,sa.w>0.5);
 incoming.er=inputs[i*9+5].xyz; incoming.ei=inputs[i*9+6].xyz;
 incoming.hr=inputs[i*9+7].xyz; incoming.hi=inputs[i*9+8].xyz;
 incoming.poynting=0.5*(cross(incoming.er,incoming.hr)+cross(incoming.ei,incoming.hi));
 CrystalInterface result=crystal_interface(indices.xy,sa.xyz,indices.zw,ta.xyz,normal,incoming);
 outputs[i*20]=vec4(result.power);
 outputs[i*20+1]=vec4(vec2(result.amplitude[0]),vec2(result.amplitude[1]));
 outputs[i*20+2]=vec4(vec2(result.amplitude[2]),vec2(result.amplitude[3]));
 outputs[i*20+3]=vec4(result.valid?1.0:0.0,result.residual,0,0);
 for(int j=0;j<4;j++) {
  outputs[i*20+4+j*2]=vec4(result.mode[j].q,result.mode[j].normal_flux,result.mode[j].evanescent?1.0:0.0);
  outputs[i*20+5+j*2]=vec4(normalize(result.mode[j].poynting),0);
 }
 // Total boundary fields are basis-independent, including degenerate modes.
 for(int side=0;side<2;side++) {
  vec3 er=vec3(0),ei=vec3(0),hr=vec3(0),hi=vec3(0);
  for(int j=side*2;j<side*2+2;j++) {
   vec2 a=result.amplitude[j]; CrystalMode m=result.mode[j];
   er+=a.x*m.er-a.y*m.ei; ei+=a.x*m.ei+a.y*m.er;
   hr+=a.x*m.hr-a.y*m.hi; hi+=a.x*m.hi+a.y*m.hr;
  }
  outputs[i*20+12+side*4]=vec4(er,0); outputs[i*20+13+side*4]=vec4(ei,0);
  outputs[i*20+14+side*4]=vec4(hr,0); outputs[i*20+15+side*4]=vec4(hi,0);
 }
}
""".replace("CASE_COUNT", str(references.size()))
	if fp64:
		source.source_compute = source.source_compute.replace("vec3 normal=normalize(inputs[i*9+3].xyz)", "dvec3 normal=normalize(dvec3(inputs[i*9+3].xyz))")
		source.source_compute = source.source_compute.replace("vec3 tangent=inputs[i*9+4].xyz", "dvec3 tangent=dvec3(inputs[i*9+4].xyz)")
		source.source_compute = source.source_compute.replace("vec3 er=vec3(0),ei=vec3(0),hr=vec3(0),hi=vec3(0)", "dvec3 er=dvec3(0),ei=dvec3(0),hr=dvec3(0),hi=dvec3(0)")
		source.source_compute = source.source_compute.replace("vec2 a=result.amplitude[j]", "dvec2 a=result.amplitude[j]")
	var spirv := rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		printerr(spirv.compile_error_compute)
		rd.free()
		quit(1)
		return
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var input_buffer := rd.storage_buffer_create(data.size() * 4, data.to_byte_array())
	var output_buffer := rd.storage_buffer_create(references.size() * 320)
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
	var max_side_power := 0.0
	var max_field := 0.0
	var max_field_case := -1
	var max_side_power_case := -1
	for value in values:
		if not is_finite(value):
			failures += 1
	for index in references.size():
		var offset := index * 80
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
		for side in 2:
			var expected_power: float = references[index].branches[side * 2].power + references[index].branches[side * 2 + 1].power
			var power_error := absf(values[offset + side * 2] + values[offset + side * 2 + 1] - expected_power)
			if power_error > max_side_power:
				max_side_power = power_error
				max_side_power_case = index
			for pair in 2:
				var field: String = "E" if pair == 0 else "H"
				var er := V.vec(0, 0, 0)
				var ei := V.vec(0, 0, 0)
				for branch_index in range(side * 2, side * 2 + 2):
					var branch: Dictionary = references[index].branches[branch_index]
					var ar: float = branch.amplitude[0]
					var ai: float = branch.amplitude[1]
					er = V.add(er, V.subtract(V.scale(branch.mode[field + "_real"], ar), V.scale(branch.mode[field + "_imag"], ai)))
					ei = V.add(ei, V.add(V.scale(branch.mode[field + "_real"], ai), V.scale(branch.mode[field + "_imag"], ar)))
				for axis in 3:
					var error := maxf(absf(values[offset + 48 + side * 16 + pair * 8 + axis] - er[axis]), absf(values[offset + 52 + side * 16 + pair * 8 + axis] - ei[axis]))
					if error > max_field:
						max_field = error
						max_field_case = index
		max_flux_error = maxf(max_flux_error, absf(sum - 1))
		max_residual = maxf(max_residual, values[offset + 13])
	if (not stress and (max_power > 1e-5 or max_amplitude > 1e-5)) or max_q > 1e-5 or max_ray > 1e-5 or max_flux_error > 1e-5 or max_residual > 1e-5 or max_field > 1e-5 or max_side_power > 1e-5:
		failures += 1
	var report := {"stress": stress, "fp64": fp64, "interfaces": references.size(), "failures": failures, "max_power_error": max_power,
		"max_amplitude_error": max_amplitude, "max_q_error": max_q, "max_ray_error": max_ray,
		"max_flux_error": max_flux_error, "max_continuity_residual": max_residual,
		"max_side_power_error": max_side_power, "max_field_error": max_field, "max_field_case": max_field_case, "max_side_power_case": max_side_power_case}
	var name := "crystal-gpu" + ("-stress" if stress else "") + ("-fp64" if fp64 else "")
	GemArtifactStore.atomic_write("res://artifacts/reference/" + name + ".json", JSON.stringify(report, "\t").to_utf8_buffer())
	print("Crystal GPU: " + JSON.stringify(report))
	for rid in [uniform_set, pipeline, shader, input_buffer, output_buffer]:
		rd.free_rid(rid)
	rd.free()
	quit(1 if failures else 0)

func _stress_inputs() -> Array[PackedFloat32Array]:
	var result: Array[PackedFloat32Array] = []
	var normal := Vector3.BACK
	for rotation_angle in [0.0, 0.57]:
		var rotation := Basis(Vector3(0.3, 0.7, -0.4).normalized(), rotation_angle)
		for axis_angle in [0.0, 0.4, 1.2]:
			var axis := V.vec(sin(axis_angle), 0, cos(axis_angle))
			var mn := V.metric(V.vec(0, 0, 1), axis, 1.5, 1.7)
			var mt := V.metric(V.vec(1, 0, 0), axis, 1.5, 1.7)
			var critical := sqrt(mn[2] / (mn[2] * mt[0] - mt[2] * mt[2]))
			for target_ne in [1.5, 1.7]:
				var threshold: float = 1.5 if target_ne == 1.5 else critical
				for delta in [-0.01, -0.0001, -0.000001, -0.0000001, -0.00000001, 0.0, 0.00000001, 0.0000001, 0.000001, 0.0001, 0.01]:
					for mode in 2:
						result.append(_input(2.2, 2.4, Vector3(0.4, 0.2, 0.7).normalized(), 1.5, target_ne,
							Vector3(axis[0], axis[1], axis[2]), normal, Vector3(threshold * (1 + delta), 0, 0), rotation, mode))
		# Near/at optic-axis degeneracy on both sides; source is normally incident.
		for delta in [0.0, 1e-10, 1e-8, 1e-7, 1e-6, 1e-5, 1e-4, 0.01]:
			for mode in 2:
				result.append(_input(1.6, 1.8, Vector3(delta, 0, 1).normalized(), 1.5, 1.7,
					Vector3(0, delta, 1).normalized(), normal, Vector3.ZERO, rotation, mode))
	return result

func _input(no: float, ne: float, source_axis: Vector3, tno: float, tne: float, target_axis: Vector3,
		normal: Vector3, tangent: Vector3, rotation: Basis, mode: int) -> PackedFloat32Array:
	var sa := rotation * source_axis
	var ta := rotation * target_axis
	var n := rotation * normal
	var t := rotation * tangent
	return PackedFloat32Array([no, ne, tno, tne, sa.x, sa.y, sa.z, mode,
		ta.x, ta.y, ta.z, 0, n.x, n.y, n.z, 0, t.x, t.y, t.z, 0])
