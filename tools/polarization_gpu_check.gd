extends SceneTree
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var tracer := GemTracer.create(32, 32)
	if tracer == null:
		quit(1)
		return
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres")
	var inst := LapidaryStoneCompiler.compile(stone)
	inst["size_mm"] = 1.0
	inst["extraordinary_refraction"] = {}
	inst["absorption_eray"] = PackedFloat32Array()
	inst["zoning"] = {}
	inst["scatter"] = {"sigma_per_mm": 0.0, "g": 0.0}
	var planes := PackedFloat32Array()
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		for sign_value in [-1.0, 1.0]:
			var normal: Vector3 = axis * sign_value
			planes.append_array(PackedFloat32Array([normal.x, normal.y, normal.z, 1.0 if axis.z != 0 else 100.0, 0, 0, 0, 0]))
	inst["planes"] = planes
	inst["sellmeier_c"] = Vector3.ZERO
	var lighting := GemLighting.analytic(PackedFloat32Array(), Vector4(1, 1, 1, 0))
	var policy := GemRung.policy(GemRung.REFERENCE)
	policy["polarization"] = true
	policy["birefringence"] = false
	var report := []
	for index in [1.5, 2.417]:
		inst["sellmeier_b"] = Vector3(index * index - 1.0, 0, 0)
		for angle in [0.0, 0.6, 1.2]:
			inst["absorption"].fill(0.6)
			tracer.configure_stone(inst, lighting, policy)
			tracer.set_stone_orientation(Quaternion(Vector3.UP, angle))
			tracer.accumulate(1024)
			var expected := slab(index, angle, 0.6)
			var actual := center_y(tracer)
			check(absf(actual - expected) < 0.0001, "polarized slab n=%.3f angle=%.2f: %.7f vs %.7f" % [index, angle, actual, expected])
			report.append({"index": index, "angle": angle, "alpha": 0.6, "godot": actual, "analytic": expected})
			tracer.set_stone_orientation(Quaternion(Vector3.BACK, 0.73) * Quaternion(Vector3.UP, angle))
			tracer.accumulate(1024)
			check(absf(center_y(tracer) - actual) < 0.0001, "polarization basis is covariant under camera-axis rotation")
			inst["absorption"].fill(0.0)
			tracer.configure_stone(inst, lighting, policy)
			tracer.set_stone_orientation(Quaternion(Vector3.UP, angle))
			tracer.accumulate(256)
			check(absf(center_y(tracer) - 1.0) < 0.0002, "polarized dielectric furnace preserves unpolarized equilibrium")
	var path := "res://artifacts/reference/polarized-slabs.json"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(report, "\t"))
	_dichroic_slabs(tracer, inst, lighting, policy)
	_interface_probes(tracer.get("_rd"))
	_interface_probes(tracer.get("_rd"), true)
	tracer.release()
	print("GPU polarization: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func _interface_probes(rd: RenderingDevice, dichroic := false) -> void:
	var packed := PackedFloat32Array()
	var cases := []
	for index in 64:
		var direction := Vector3(sin(0.25 + index * 0.014), 0, -cos(0.25 + index * 0.014))
		var steps := []
		var absorption := []
		for step in 5:
			var normal := Vector3.BACK
			var before := 1.0 if step == 0 else 1.5
			var after := 1.0 if step == 4 else 1.5
			var transmission := step in [0, 4]
			if step > 0:
				var tangent := direction.cross(Vector3.UP).normalized()
				var bitangent := direction.cross(tangent)
				var azimuth := index * 0.13 + step * 0.87
				var cosine := 0.85 if step == 4 else 0.5 + 0.1 * sin(index * 0.3 + step)
				normal = -direction * cosine + (tangent * cos(azimuth) + bitangent * sin(azimuth)) * sqrt(1.0 - cosine * cosine)
			if not transmission:
				after = 1.0 # TIR against the exterior; the path remains in n=1.5.
			var next := direction.bounce(normal)
			if transmission:
				var eta := before / after
				var ci := -direction.dot(normal)
				var ct := sqrt(1.0 - eta * eta * (1.0 - ci * ci))
				next = (eta * direction + (eta * ci - ct) * normal).normalized()
			var values := PackedFloat32Array([direction.x, direction.y, direction.z, before, next.x, next.y, next.z, after, normal.x, normal.y, normal.z, float(transmission)])
			packed.append_array(values)
			var absorption_axis := Vector3(sin(index * 0.2 + step), cos(index * 0.3 - step), 0.7).normalized()
			packed.append_array(PackedFloat32Array([absorption_axis.x, absorption_axis.y, absorption_axis.z, step + 1]))
			absorption.append({"axis": absorption_axis, "ordinary": exp(-0.1 * (step + 1)), "extraordinary": exp(-0.3 * (step + 1))})
			# JSON Vector3 would stringify; use explicit numeric arrays.
			absorption[-1]["axis"] = [absorption_axis.x, absorption_axis.y, absorption_axis.z]
			steps.append(Array(values))
			direction = next
		cases.append({"steps": steps, "absorption": absorption if dichroic else []})
	var source := RDShaderSource.new()
	source.source_compute = "#version 450\n#define POLARIZED_TRANSPORT 1\n" + FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_common.glsl") + FileAccess.get_file_as_string("res://core/lapidary/tracer/shaders/gem_polarization.glsl") + """
layout(local_size_x=64) in;
layout(set=0,binding=7,std430) readonly buffer Steps { vec4 events[]; };
layout(set=0,binding=16,std430) buffer Results { vec4 results[]; };
void main() {
 int i=int(gl_GlobalInvocationID.x);
 PathWeight w=weight_initial(events[i*20].xyz);
 for(int step=0;step<5;step++) {
  int base=i*20+step*4;
  vec4 a=events[base],b=events[base+1],n=events[base+2];
  w=interface_weight(w,a.xyz,b.xyz,n.xyz,vec4(a.w),vec4(b.w),n.w>0.5,1.0,vec4(1.0));
  if(ENABLE_ABSORPTION) {
   vec4 absorption=events[base+3];
   w=absorption_weight(w,b.xyz,absorption.xyz,vec4(exp(-0.1*absorption.w)),vec4(exp(-0.3*absorption.w)));
  }
 }
 results[i*2]=vec4(w.I.x,w.Q.x,w.U.x,w.V.x);
 results[i*2+1]=vec4(w.axis,0);
}
"""
	source.source_compute = source.source_compute.replace("ENABLE_ABSORPTION", "true" if dichroic else "false")
	var spirv := rd.shader_compile_spirv_from_source(source)
	check(spirv.compile_error_compute.is_empty(), "polarized interface probe compiles: " + spirv.compile_error_compute)
	if not spirv.compile_error_compute.is_empty():
		return
	var shader := rd.shader_create_from_spirv(spirv)
	var pipeline := rd.compute_pipeline_create(shader)
	var input := rd.storage_buffer_create(packed.size() * 4, packed.to_byte_array())
	var output := rd.storage_buffer_create(64 * 32)
	var dummy := rd.storage_buffer_create(401 * 16)
	var uniforms: Array[RDUniform] = []
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
	rd.compute_list_dispatch(list, 1, 1, 1)
	rd.compute_list_end()
	rd.submit()
	rd.sync()
	var values := rd.buffer_get_data(output).to_float32_array()
	for index in cases.size():
		cases[index]["weight"] = Array(values.slice(index * 8, index * 8 + 4))
		cases[index]["axis"] = Array(values.slice(index * 8 + 4, index * 8 + 7))
	FileAccess.open("res://artifacts/reference/polarized-dichroic-chains.json" if dichroic else "res://artifacts/reference/polarized-interface-chains.json", FileAccess.WRITE).store_string(JSON.stringify(cases, "\t"))
	for rid in [set, pipeline, shader, input, output, dummy]:
		rd.free_rid(rid)

static func slab(index: float, angle: float, alpha: float) -> float:
	var ci := cos(angle)
	var eta := 1.0 / index
	var ct := sqrt(1.0 - eta * eta * (1.0 - ci * ci))
	var rs := pow((eta * ci - ct) / (eta * ci + ct), 2)
	var rp := pow((ci - eta * ct) / (ci + eta * ct), 2)
	var transmittance := exp(-alpha * 2.0 / ct)
	var total := 0.0
	for reflectance in [rs, rp]:
		total += 0.5 * (reflectance + pow(1.0 - reflectance, 2) * transmittance / (1.0 - reflectance * transmittance))
	return total

static func center_y(tracer: GemTracer) -> float:
	var data := tracer.read_xyz()
	var total := 0.0
	for y in range(14, 18):
		for x in range(14, 18):
			total += data[(y * 32 + x) * 4 + 1] / 16.0
	return total

func _dichroic_slabs(tracer: GemTracer, original: Dictionary, lighting: GemLighting, policy: Dictionary) -> void:
	var inst := original.duplicate(true)
	inst["sellmeier_b"] = Vector3(1.25, 0, 0)
	inst["optic_axis"] = Vector3.RIGHT
	inst["absorption"].fill(0.2)
	inst["absorption_eray"] = PackedFloat32Array()
	inst["absorption_eray"].resize(401)
	inst["absorption_eray"].fill(1.3)
	for angle in [0.0, 0.6, 1.2]:
		tracer.configure_stone(inst, lighting, policy)
		tracer.set_stone_orientation(Quaternion(Vector3.UP, angle))
		tracer.accumulate(1024)
		var ci := cos(angle)
		var ct := sqrt(1 - pow(sin(angle) / 1.5, 2))
		var rs := pow((ci - 1.5 * ct) / (ci + 1.5 * ct), 2)
		var rp := pow((1.5 * ci - ct) / (1.5 * ci + ct), 2)
		var alpha_p := (1 - ct * ct) * 0.2 + ct * ct * 1.3
		var expected := 0.0
		for pair in [[rs, 0.2], [rp, alpha_p]]:
			var t := exp(-pair[1] * 2.0 / ct)
			expected += 0.5 * (pair[0] + pow(1 - pair[0], 2) * t / (1 - pair[0] * t))
		check(absf(center_y(tracer) - expected) < 0.0001, "dichroic slab with repeated internal reflection matches polarized Beer series")
	# Same-index overlapping region adds geometry segments without a new optical
	# interface. Absorption must carry its polarization through every segment.
	inst["sellmeier_b"] = Vector3.ZERO
	var boundaries := GemBoundarySet.new()
	var box_tool := load("res://tests/lapidary/test_boundaries.gd")
	boundaries.add(box_tool.box(Vector3(-2, -2, -1), Vector3(2, 2, 1)), 0)
	boundaries.add(box_tool.box(Vector3(-2, -2, -0.3), Vector3(2, 2, 0.4)), 0)
	inst["boundaries"] = boundaries
	tracer.configure_stone(inst, lighting, policy)
	tracer.set_stone_orientation(Quaternion.IDENTITY)
	tracer.accumulate(128)
	var expected := 0.5 * (exp(-0.4) + exp(-2.6))
	check(absf(center_y(tracer) - expected) < 0.0001, "dichroic polarization survives irrelevant boundary segmentation")
