extends SceneTree
## Optional historical A/B: save prior gem_pathtrace.glsl as the baseline path.
const OUT := "res://artifacts/reconstruction"
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	var quick := "--quick" in OS.get_cmdline_user_args()
	var size := 128 if quick else 256
	var reference_samples := 512 if quick else 2048
	var baseline := OUT.path_join("baseline-pathtrace.glsl")
	if not FileAccess.file_exists(baseline):
		printerr("Missing historical baseline shader: " + baseline)
		quit(1)
		return
	var reports := []
	var sheet := Image.create(size*3,size*4,false,Image.FORMAT_RGBA8)
	var lights := GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy["max_bounces"] = 256
	policy["birefringence"] = false
	policy["spectral_geometry"] = "full"
	for item in 4:
		var stone := specimen(item)
		var compiled := LapidaryStoneCompiler.compile(stone)
		var images: Array[Image] = []
		var raw_images: Array[Image] = []
		var raw_values: Array[PackedFloat32Array] = []
		var milliseconds := []
		var high: Image
		var sharp_fraction := 0.0
		var high_ms := 0.0
		for variant in 2:
			var tracer := GemTracer.create(size,size)
			if tracer==null:quit(1);return
			if variant==0:
				tracer._rd.free_rid(tracer._pipelines["trace"])
				tracer._rd.free_rid(tracer._shaders["trace"])
				if not tracer._compile_shader(baseline,"trace"):quit(1);return
			check(tracer.configure_stone(compiled,lights,policy),"configure comparison")
			tracer.set_seed(8123)
			tracer.set_stone_orientation(Quaternion(Vector3.UP,-.5)*Quaternion(Vector3.RIGHT,-.15))
			tracer.accumulate(4)
			tracer.reset_accumulation()
			milliseconds.append(tracer.accumulate(128))
			images.append(tracer.finalize_print(GemPrint.load_house()))
			raw_images.append(tracer.finalize_print(GemPrint.load_house(), GemPrint.View.HOUSE_PRINT,1,Vector2i.ZERO,false))
			raw_values.append(tracer.read_xyz())
			check(tracer.transport_error().is_empty(),"comparison transport finishes")
			images[-1].save_png(OUT.path_join("case%d_variant%d.png"%[item,variant]))
			sheet.blit_rect(images[-1],Rect2i(0,0,size,size),Vector2i(variant*size,item*size))
			if variant==1:
				var sharp: PackedFloat32Array = tracer.checkpoint().buffers.ballistic.to_float32_array()
				var total_y := 0.0
				var sharp_y := 0.0
				for i in size*size:
					total_y+=raw_values[-1][i*4+1]
					sharp_y+=sharp[i*4+1]/128.0
				sharp_fraction=sharp_y/maxf(total_y,1e-12)
				tracer.set_seed(8591)
				tracer.reset_accumulation()
				high_ms=tracer.accumulate(reference_samples)
				high=tracer.finalize_print(GemPrint.load_house(), GemPrint.View.HOUSE_PRINT,1,Vector2i.ZERO,false)
				check(tracer.transport_error().is_empty(),"reference transport finishes")
			tracer.release()
		high.save_png(OUT.path_join("case%d_reference.png"%item))
		sheet.blit_rect(high,Rect2i(0,0,size,size),Vector2i(size*2,item*size))
		var maximum := 0.0
		for i in raw_values[0].size():maximum=maxf(maximum,absf(raw_values[0][i]-raw_values[1][i]))
		if item!=3:check(maximum<.0001,"auxiliary sharp component leaves rough physical estimator unchanged")
		var report := {"case":item,"trace_ms":milliseconds,"reference_ms":high_ms,"sharp_Y_fraction":sharp_fraction,"raw_max_difference":maximum,
			"old_filtered_error":GemPagePacker.compression_error(high.get_data(),images[0].get_data()),
			"new_filtered_error":GemPagePacker.compression_error(high.get_data(),images[1].get_data()),
			"new_raw_error":GemPagePacker.compression_error(high.get_data(),raw_images[1].get_data())}
		reports.append(report)
		print(JSON.stringify(report))
	sheet.save_png(OUT.path_join("comparison.png"))
	GemArtifactStore.atomic_write(OUT.path_join("report.json"),JSON.stringify({"cases":reports,"size":size,"samples":[128,reference_samples],"engine":GemRenderIdentity.pipeline_digest("scalar"),"baseline_sha256":FileAccess.get_sha256(baseline)},"\t").to_utf8_buffer())
	quit(1 if failures else 0)
static func specimen(item: int) -> GemStone:
	var id := "diamond" if item<2 else "quartz"
	var stone: GemStone=load("res://data/lapidary/stones/"+id+".tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm=.1 if item==3 else 0.0
	stone.condition.banding.contrast=0
	if item<2:
		var recipe:=GemCleavageRecipe.new()
		recipe.normals=PackedVector3Array([Vector3(1,0,.35).normalized()])
		recipe.depth_mm=1.2
		recipe.finish.multiple_scattering=true
		recipe.finish.alpha_u=.02 if item==0 else .15
		recipe.finish.alpha_v=recipe.finish.alpha_u
		stone.condition.cleavage=recipe
	else:
		var planes:PackedFloat32Array=LapidaryStoneCompiler.compile(stone).planes
		var height:=0.0
		for i in planes.size()/8:
			if planes[i*8+2]>.9999:height=planes[i*8+3]*stone.size_mm;break
		var field:=GemFinishField.new()
		field.center_mm=Vector3(0,0,height)
		field.radius_mm=Vector3(stone.size_mm*100,stone.size_mm*100,.01)
		field.alpha_u=.15;field.alpha_v=.03
		stone.condition.finish.multiple_scattering=true
		stone.condition.finish.fields.append(field)
	return stone
