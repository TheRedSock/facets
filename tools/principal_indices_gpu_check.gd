extends SceneTree
## Tests the actual Stone packing and the same GLSL principal-index functions
## used by production, at fractional wavelengths across the transport band.
func _initialize() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		print("CHECK_COMPLETE: principal_indices_gpu_check"); quit(1)
		return
	var tracer := GemTracer.new()
	var wire := StreamPeerBuffer.new()
	var species_list: Array[GemSpecies] = []
	for name in ["quartz", "corundum", "elbaite", "diamond"]:
		species_list.append(load("res://data/lapidary/species/" + name + ".tres"))
	var shifted := GemSpecies.new()
	shifted.ordinary.b = PackedFloat64Array([-0.75, 0, 0])
	shifted.ordinary.index_offset = 1.0 # sqrt(0.25)+1; cannot clamp n^2 to 1.
	shifted.extraordinary = shifted.ordinary.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	shifted.extraordinary.index_offset = 1.1
	species_list.append(shifted)
	for species in species_list:
		var material := GemMaterial.new()
		material.species = species
		tracer._pack_stone(wire, GemMaterialCompiler.compile(material), 0, 0, 0, 0)
	var source := RDShaderSource.new()
	source.source_compute = "#version 450\n" + FileAccess.get_file_as_string(GemTracer.COMMON_PATH) + """
layout(local_size_x=32) in;
layout(set=0,binding=17,std430) buffer Outputs { vec4 output_values[]; };
void main() {
 int i=int(gl_GlobalInvocationID.x); if(i>=COUNT) return;
 Stone s=stones[i/1601]; float wl=380.0+float(i%1601)*0.25;
 float no=principal_index(s,wl,false), ne=principal_index(s,wl,true);
 output_values[i]=vec4(no,ne,n_e_phi(no,ne,0.6),s.sell_c_biref.w);
}
""".replace("COUNT", str(species_list.size() * 1601))
	var spirv := rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		printerr(spirv.compile_error_compute)
		rd.free()
		print("CHECK_COMPLETE: principal_indices_gpu_check"); quit(1)
		return
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var input_buffer := rd.storage_buffer_create(wire.data_array.size(), wire.data_array)
	var output_buffer := rd.storage_buffer_create(species_list.size() * 1601 * 16)
	var dummy := rd.storage_buffer_create(128)
	var uniforms: Array[RDUniform] = []
	for entry in [[0, dummy], [1, dummy], [2, dummy], [3, dummy], [4, dummy], [5, input_buffer], [6, dummy], [15, dummy], [17, output_buffer]]:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = entry[0]
		uniform.add_id(entry[1])
		uniforms.append(uniform)
	var uniform_set := rd.uniform_set_create(uniforms, shader, 0)
	var list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list, pipeline)
	rd.compute_list_bind_uniform_set(list, uniform_set, 0)
	rd.compute_list_dispatch(list, ceili(species_list.size() * 1601.0 / 32), 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var output := rd.buffer_get_data(output_buffer).to_float32_array()
	var maximum := 0.0
	var failures := 0
	for material_index in species_list.size():
		var species := species_list[material_index]
		for sample in 1601:
			var wl := 380.0 + sample * 0.25
			var no := species.ior_at(wl)
			var ne := species.extraordinary_ior_at(wl)
			var expected := [no, ne, 1.0 / sqrt(0.36 / (no * no) + 0.64 / (ne * ne))]
			for component in 3:
				var actual := output[(material_index * 1601 + sample) * 4 + component]
				var error: float = absf(expected[component] - actual)
				maximum = maxf(maximum, error)
				if not is_finite(actual) or error > 1e-6:
					failures += 1
			var bound := output[(material_index * 1601 + sample) * 4 + 3]
			if absf(ne - no) > bound + 1e-6:
				failures += 1
	for rid in [uniform_set, pipeline, shader, input_buffer, output_buffer, dummy]:
		rd.free_rid(rid)
	rd.free()
	var report := {"cases": species_list.size() * 1601, "max_index_error": maximum, "failures": failures}
	GemArtifactStore.atomic_write("res://artifacts/checks/principal_indices_gpu.json", JSON.stringify(report, "\t").to_utf8_buffer())
	print("Principal index GPU: ", report)
	print("CHECK_COMPLETE: principal_indices_gpu_check"); quit(1 if failures else 0)
