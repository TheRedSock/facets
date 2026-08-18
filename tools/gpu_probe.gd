extends SceneTree
## GPU capability probe for the gem tracer pipeline.
## Run windowed:  godot --path . --script res://tools/gpu_probe.gd
## Run headless:  godot --headless --path . --script res://tools/gpu_probe.gd
## Reports adapter, local RenderingDevice availability, and a trivial compute dispatch.

const PROBE_SHADER := """
#version 450
layout(local_size_x = 64) in;
layout(set = 0, binding = 0, std430) restrict buffer Data { float values[]; };
void main() {
	uint i = gl_GlobalInvocationID.x;
	values[i] = values[i] * 2.0 + 1.0;
}
"""


func _initialize() -> void:
	print("=== GPU PROBE ===")
	print("video_adapter: ", RenderingServer.get_video_adapter_name())
	print("adapter_vendor: ", RenderingServer.get_video_adapter_vendor())
	print("adapter_type: ", RenderingServer.get_video_adapter_type())
	print("api_version: ", RenderingServer.get_video_adapter_api_version())
	print("rendering_method: ", RenderingServer.get_current_rendering_method())
	print("rendering_driver: ", RenderingServer.get_current_rendering_driver_name())

	var rd: RenderingDevice = RenderingServer.create_local_rendering_device()
	if rd == null:
		print("local_rd: NULL (RenderingDevice unavailable in this mode)")
		quit(1)
		return
	print("local_rd: OK device=", rd.get_device_name(), " vendor=", rd.get_device_vendor_name())

	var src := RDShaderSource.new()
	src.source_compute = PROBE_SHADER
	var spirv := rd.shader_compile_spirv_from_source(src)
	if spirv.compile_error_compute != "":
		print("compile: FAILED — ", spirv.compile_error_compute)
		quit(1)
		return
	var shader := rd.shader_create_from_spirv(spirv)
	print("compile: OK")

	var count := 256
	var input := PackedFloat32Array()
	input.resize(count)
	for i in count:
		input[i] = float(i)
	var bytes := input.to_byte_array()
	var buf := rd.storage_buffer_create(bytes.size(), bytes)
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(buf)
	var uniform_set := rd.uniform_set_create([uniform], shader, 0)
	var pipeline := rd.compute_pipeline_create(shader)

	var t0 := Time.get_ticks_usec()
	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, pipeline)
	rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
	rd.compute_list_dispatch(cl, count / 64, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var t1 := Time.get_ticks_usec()

	var out := rd.buffer_get_data(buf).to_float32_array()
	var ok := absf(out[10] - 21.0) < 0.001 and absf(out[100] - 201.0) < 0.001
	print("dispatch: ", "OK" if ok else "WRONG RESULT", " roundtrip_us=", t1 - t0)
	print("=== PROBE DONE ===")
	quit(0 if ok else 1)
