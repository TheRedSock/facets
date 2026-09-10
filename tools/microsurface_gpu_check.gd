extends SceneTree
## Standalone Smith sampler gate for the explicit multiple-scattering finish.
const SAMPLES := 65536
var failures := 0

func _initialize() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null:
		quit(1)
		return
	var cases: Array[Dictionary] = []
	var input := PackedFloat32Array()
	for alpha in [Vector2(0.02, 0.02), Vector2(0.3, 0.3), Vector2(1, 1), Vector2(0.5, 0.05), Vector2(0.0001, 0.0001), Vector2(1, 0.0001)]:
		for eta in [1.0 / 1.5, 1.5, 1.0 / 2.4, 2.4]:
			for angle in [0.0, 60.0, 85.0, -1.0]:
				var direction := Vector3(sin(deg_to_rad(angle)), 0, -cos(deg_to_rad(angle)))
				cases.append({"alpha": [alpha.x, alpha.y], "eta": eta, "angle": angle})
				input.append_array(PackedFloat32Array([direction.x, direction.y, direction.z, eta, alpha.x, alpha.y, 1 if angle < 0 else 0, 0]))
	var source := RDShaderSource.new()
	source.source_compute = "#version 450\n" + FileAccess.get_file_as_string("res://core/lapidary/microsurface/smith_walk.glsl") + """
layout(local_size_x=64) in;
layout(set=0,binding=0,std430) readonly buffer Inputs { vec4 inputs[]; };
layout(set=0,binding=1,std430) buffer Outputs { vec4 outputs[]; };
layout(push_constant,std430) uniform Params { uint case_index; uint count; } pc;
void main() {
    uint i = gl_GlobalInvocationID.x;
    if (i >= pc.count) return;
    vec4 spec = inputs[2u*pc.case_index];
    vec2 alpha = inputs[2u*pc.case_index+1u].xy;
    uint rng = (i+1u)*1664525u ^ (pc.case_index+1u)*1013904223u;
    vec3 ray = spec.xyz;
    if (inputs[2u*pc.case_index+1u].z > 0.5) {
        float r2 = smith_random(rng), phi = 6.283185307179586*smith_random(rng);
        ray = vec3(sqrt(r2)*vec2(cos(phi),sin(phi)), -sqrt(1.0-r2));
    }
    SmithSample result = smith_sample(ray, alpha, spec.w, rng, 256);
    outputs[2u*i] = vec4(result.direction, result.valid ? float(result.order) : -1.0);
    // An independent draw exercises below-horizon VNDF visibility too.
    vec3 outgoing = normalize(vec3(-spec.x, 0.17, spec.z));
    vec3 normal = smith_normal(outgoing, alpha, vec2(smith_random(rng),smith_random(rng)));
    outputs[2u*i+1u] = vec4(normal, dot(normal,outgoing));
}
"""
	var spirv := rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty():
		printerr(spirv.compile_error_compute)
		rd.free()
		quit(1)
		return
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var input_buffer := rd.storage_buffer_create(input.size() * 4, input.to_byte_array())
	var output_buffer := rd.storage_buffer_create(SAMPLES * 32)
	var uniforms: Array[RDUniform] = []
	for i in 2:
		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
		uniform.binding = i
		uniform.add_id(input_buffer if i == 0 else output_buffer)
		uniforms.append(uniform)
	var uniform_set := rd.uniform_set_create(uniforms, shader, 0)
	var out := "res://artifacts/microsurface"
	DirAccess.make_dir_recursive_absolute(out)
	for case_index in cases.size():
		var start := Time.get_ticks_usec()
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipeline)
		rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		var push := PackedInt32Array([case_index, SAMPLES, 0, 0]).to_byte_array()
		rd.compute_list_set_push_constant(list, push, push.size())
		rd.compute_list_dispatch(list, SAMPLES / 64, 1, 1)
		rd.compute_list_end()
		rd.submit()
		rd.sync()
		var raw := rd.buffer_get_data(output_buffer)
		cases[case_index]["ms"] = (Time.get_ticks_usec() - start) / 1000.0
		var data := raw.to_float32_array()
		var invalid := 0
		var max_order := 0
		for i in SAMPLES:
			var offset := i * 8
			var direction := Vector3(data[offset], data[offset+1], data[offset+2])
			var normal := Vector3(data[offset+4], data[offset+5], data[offset+6])
			if data[offset+3] < 1 or not direction.is_finite() or absf(direction.length_squared()-1) > 2e-5 or not normal.is_finite() or absf(normal.length_squared()-1) > 2e-5 or normal.z < 0 or data[offset+7] < -1e-6:
				invalid += 1
			max_order = maxi(max_order, int(data[offset+3]))
		cases[case_index]["invalid"] = invalid
		cases[case_index]["max_order"] = max_order
		if invalid:
			failures += 1
			printerr("FAIL: microsurface case %d has %d invalid samples" % [case_index, invalid])
		GemArtifactStore.atomic_write(out.path_join("case_%02d.bin" % case_index), raw)
		print("Smith case %d: %s" % [case_index, JSON.stringify(cases[case_index])])
	GemArtifactStore.atomic_write(out.path_join("cases.json"), JSON.stringify({"samples": SAMPLES, "cases": cases, "source_sha256": FileAccess.get_sha256("res://core/lapidary/microsurface/smith_walk.glsl")}, "\t").to_utf8_buffer())
	for rid in [uniform_set, pipeline, shader, input_buffer, output_buffer]:
		rd.free_rid(rid)
	rd.free()
	print("Microsurface: %d directional samples, %d failing cases" % [SAMPLES*cases.size(), failures])
	quit(1 if failures else 0)
