extends SceneTree
const COUNT := 256
func _initialize() -> void:
	var rd := RenderingServer.create_local_rendering_device()
	if rd == null: quit(1); return
	var finishes := PackedFloat32Array()
	var fields := PackedFloat32Array()
	var queries := PackedFloat32Array()
	for i in COUNT:
		var finish := GemSurface.new()
		finish.alpha_u = 0.02+0.15*absf(sin(i*0.4))
		finish.alpha_v = 0.001
		finish.direction = Vector3(cos(i*0.19),sin(i*0.19),0.3)
		for j in 3:
			var field := GemFinishField.new()
			field.center_mm = Vector3(j*0.4-0.5,0,0)
			field.radius_mm = Vector3(2,1.5,1)
			field.orientation = Quaternion(Vector3(0.3,0.4,0.5).normalized(),i*0.03+j*0.4)
			field.direction = Vector3(cos(i*0.13+j),sin(i*0.13+j),0.2)
			field.alpha_u = 0.1+0.6*absf(sin(i*0.3+j))
			field.alpha_v = 0.001
			field.strength = 0.3+j*0.3
			if i>=192:
				field.center_mm = Vector3.ZERO
				field.alpha_u = 1
				field.alpha_v = 0.0001
				field.strength = 1
			finish.fields.append(field)
		finishes.append_array(finish.packed(fields.size()/20))
		for field in finish.fields: fields.append_array(field.packed())
		var point := Vector3(sin(i*0.11)*1.7,cos(i*0.17)*0.7,sin(i*0.23)*0.5) if i<192 else Vector3.ZERO
		var normal := Vector3(sin(i*0.3),cos(i*0.37),0.6).normalized()
		queries.append_array(PackedFloat32Array([point.x,point.y,point.z,i,normal.x,normal.y,normal.z,0]))
	var source := RDShaderSource.new()
	source.source_compute = "#version 450\n"+FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_common.glsl")+FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_surface.glsl")+"""
layout(local_size_x=64) in;
layout(set=0,binding=16,std430) readonly buffer Queries { vec4 queries[]; };
layout(set=0,binding=17,std430) buffer Results { vec4 results[]; };
void main() {
    uint i=gl_GlobalInvocationID.x;
    vec3 n=normalize(queries[2*i+1].xyz);
    GemSurfaceData result=local_finish(surfaces[i],queries[2*i].xyz,n);
    mat3 frame=surface_frame(n,result.direction.xyz);
    results[2*i]=vec4(result.slopes.xy,0,0);
    results[2*i+1]=vec4(frame[0],0);
}
"""
	var spirv := rd.shader_compile_spirv_from_source(source)
	if not spirv.compile_error_compute.is_empty(): printerr(spirv.compile_error_compute); rd.free(); quit(1); return
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var blobs := {14:finishes.to_byte_array(),20:fields.to_byte_array(),16:queries.to_byte_array()}
	var zeros := PackedByteArray(); zeros.resize(COUNT*32)
	blobs[17]=zeros
	var uniforms: Array[RDUniform] = []
	var buffers := {}
	for binding in [0,1,2,3,4,5,6,14,15,16,17,20]:
		var data: PackedByteArray = blobs.get(binding,zeros)
		buffers[binding]=rd.storage_buffer_create(data.size(),data)
		var uniform := RDUniform.new(); uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER; uniform.binding=binding; uniform.add_id(buffers[binding]); uniforms.append(uniform)
	var uniform_set := rd.uniform_set_create(uniforms,shader,0)
	var list := rd.compute_list_begin(); rd.compute_list_bind_compute_pipeline(list,pipeline); rd.compute_list_bind_uniform_set(list,uniform_set,0); rd.compute_list_dispatch(list,COUNT/64,1,1); rd.compute_list_end(); rd.submit(); rd.sync()
	var raw := rd.buffer_get_data(buffers[17])
	var out := "res://artifacts/finish-fields"
	DirAccess.make_dir_recursive_absolute(out)
	for entry in [["surfaces",finishes.to_byte_array()],["fields",fields.to_byte_array()],["queries",queries.to_byte_array()],["results",raw]]:
		GemArtifactStore.atomic_write(out.path_join(entry[0]+".bin"),entry[1])
	var hashes := {}
	for path in ["core/lapidary/tracer/shaders/gem_common.glsl","core/lapidary/tracer/shaders/gem_surface.glsl","tools/finish_fields_gpu_check.gd"]:
		hashes[path]=FileAccess.get_sha256("res://"+path)
	GemArtifactStore.atomic_write(out.path_join("sources.json"),JSON.stringify(hashes).to_utf8_buffer())
	var failures := 0
	var values := raw.to_float32_array()
	for i in COUNT:
		var axis := Vector3(values[i*8+4],values[i*8+5],values[i*8+6])
		if not axis.is_finite() or absf(axis.length_squared()-1)>1e-5 or not is_finite(values[i*8]) or values[i*8]<0 or values[i*8]>1.00001 or values[i*8+1]<0:
			failures+=1
	for rid in [uniform_set,pipeline,shader]+buffers.values(): rd.free_rid(rid)
	rd.free()
	print("Finish field GPU: %d cases, %d invalid" % [COUNT,failures])
	quit(1 if failures else 0)
