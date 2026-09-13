class_name GemPrintPass
extends RefCounted
## Single GPU display implementation, also used when reprinting stored masters.
static func render(tracer: GemTracer, print_res: GemPrint, view: GemPrint.View, exposure: float, output_size: Vector2i, reconstruct: bool) -> Image:
	var start := Time.get_ticks_usec()
	var target := Vector2i(tracer.width, tracer.height) if output_size == Vector2i.ZERO else output_size
	assert(target.x > 0 and target.y > 0)
	tracer._create_print_target(target, tracer.reconstruct_linear() if reconstruct and tracer._denoise_passes > 0 else tracer._bufs["accum"])
	var pcb := StreamPeerBuffer.new()
	pcb.put_32(target.x)
	pcb.put_32(target.y)
	pcb.put_float(1.0 / maxf(1.0, float(tracer.samples_accumulated)))
	pcb.put_float(exposure * (print_res.exposure if print_res != null else 1.0))
	pcb.put_u32(view)
	pcb.put_float(3.2 if print_res == null else 1.0 + 3.0 * print_res.shoulder_strength)
	pcb.put_float(print_res.contrast if print_res != null else 1.0)
	pcb.put_float(print_res.black_point if print_res != null else 0.0)
	pcb.put_float(print_res.chroma_ceiling if print_res != null else 10.0)
	pcb.put_float(print_res.chroma_soft if print_res != null else 0.1)
	pcb.put_float(print_res.highlight_desat if print_res != null else 0.0)
	pcb.put_float(0.0)
	# XYZ -> linear sRGB with the rig's as-shot white balance, as mat3 columns.
	for col: Vector3 in [tracer._xyz_to_rgb.x, tracer._xyz_to_rgb.y, tracer._xyz_to_rgb.z]:
		for v: float in [col.x, col.y, col.z, 0.0]:
			pcb.put_float(v)
	for value in [tracer.width, tracer.height, 0, 0]:
		pcb.put_32(value)
	assert(pcb.data_array.size() == tracer.PRINT_PUSH_SIZE)

	var cl := tracer._rd.compute_list_begin()
	tracer._rd.compute_list_bind_compute_pipeline(cl, tracer._pipelines["print"])
	tracer._rd.compute_list_bind_uniform_set(cl, tracer._sets["print"], 0)
	tracer._rd.compute_list_set_push_constant(cl, pcb.data_array, tracer.PRINT_PUSH_SIZE)
	@warning_ignore("integer_division")
	tracer._rd.compute_list_dispatch(cl, (target.x + 7) / 8, (target.y + 7) / 8, 1)
	tracer._rd.compute_list_end()
	tracer._rd.submit()
	tracer._rd.sync()
	var data := tracer._rd.texture_get_data(tracer._print_tex, 0)
	tracer.last_print_ms = float(Time.get_ticks_usec() - start) / 1000.0
	return Image.create_from_data(target.x, target.y, false, Image.FORMAT_RGBA8, data)
