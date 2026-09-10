extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
	if not ok: failures+=1; printerr("FAIL: "+message)

func _initialize() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm=0
	stone.condition.banding.contrast=0
	var inst := LapidaryStoneCompiler.compile(stone)
	inst["sellmeier_b"]=Vector3(1.25,0,0)
	inst["sellmeier_c"]=Vector3.ZERO
	inst["extraordinary_refraction"]={}
	inst["absorption"].fill(0)
	inst["absorption_eray"]=PackedFloat32Array()
	inst["size_mm"]=1.0
	var planes := PackedFloat32Array()
	for axis in [Vector3.RIGHT,Vector3.UP,Vector3.BACK]:
		for sign_value in [-1.0,1.0]:
			var normal: Vector3=axis*sign_value
			planes.append_array(PackedFloat32Array([normal.x,normal.y,normal.z,1,0,0,0,0]))
	inst["planes"]=planes
	inst["facet_ids"]=PackedInt32Array([0,1,2,3,4,5])
	var finish := GemSurface.new()
	finish.multiple_scattering=true
	var field := GemFinishField.new()
	field.center_mm=Vector3(-0.5,0,1)
	field.radius_mm=Vector3(0.7,1,0.1)
	field.alpha_u=0.3
	field.alpha_v=0.08
	finish.fields=[field]
	inst["surfaces"]=[finish]
	var tracer := GemTracer.create(64,64)
	if tracer==null: quit(1); return
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy["birefringence"]=false
	policy["max_bounces"]=256
	policy["denoise_passes"]=0
	var furnace := GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	for angle in [0.0,0.4]:
		check(tracer.configure_stone(inst,furnace,policy),"configure spatial finish")
		tracer.set_stone_orientation(Quaternion(Vector3.UP,angle))
		tracer.accumulate(512)
		check(absf(mean_y(tracer.read_xyz())-1)<0.005,"spatial finish conserves furnace energy at rotated pose")
		check(tracer.surface_diagnostics().walks>0 and tracer.transport_error().is_empty(),"rough field on smooth base executes valid micro-walks")
	# Isolate local interface reflection with a strongly absorbing bulk.
	inst["absorption"].fill(100)
	var light := GemLighting.analytic(PackedFloat32Array([0,0,1,cos(0.06),5600,10,cos(0.04),0]))
	var out := "res://artifacts/finish-fields"
	DirAccess.make_dir_recursive_absolute(out)
	var images := []
	var geometry: PackedByteArray
	var means := []
	for angle in [0.0,0.3]:
		for enabled in [false,true]:
			finish.fields.clear()
			if enabled: finish.fields.append(field)
			check(tracer.configure_stone(inst,light,policy),"configure directional finish test")
			tracer.set_stone_orientation(Quaternion(Vector3.UP,angle))
			tracer.accumulate(2048)
			var values := tracer.read_xyz()
			means.append(mean_y(values))
			check(tracer.transport_error().is_empty(),"finite local reflection")
			var image := tracer.finalize_print(GemPrint.load_house())
			images.append(image)
			image.save_png(out.path_join("reflection_%s_%s.png" % [angle,enabled]))
			if angle==0:
				var current := tracer.geometry_aov(2).data
				if not enabled: geometry=current
				else: check(geometry==current,"surface fields leave geometry and primary semantic IDs unchanged")
	check(means[1]<means[0]*0.95,"rough area reduces narrow frontal reflection")
	check(means[3]>means[2]+0.0001,"rough area gains off-specular reflection instead of acting as dark paint")
	var sheet := Image.create(256,64,false,Image.FORMAT_RGBA8)
	for i in images.size(): sheet.blit_rect(images[i],Rect2i(0,0,64,64),Vector2i(i*64,0))
	sheet.save_png(out.path_join("reflection.png"))
	print("Finish field reflections (clean/field, frontal/tilted): ",means)
	tracer.release()
	_factory(stone,finish)
	print("Finish field renderer: %d failures" % failures)
	quit(1 if failures else 0)

func _factory(stone: GemStone, finish: GemSurface) -> void:
	stone.condition.finish=finish.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition.finish.fields[0].center_mm=Vector3.ZERO
	stone.condition.finish.fields[0].radius_mm=Vector3.ONE*stone.size_mm*3
	var job:=GemFramePlan.animation(stone,load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.PREVIEW)[0]
	job.resolution=Vector2i(32,32)
	job.output_size=Vector2i(24,24)
	job.samples=16
	var root:="res://artifacts/finish-fields/factory-%d" % Time.get_ticks_usec()
	var worker:=GemFrameWorker.new(root)
	check(worker.run(job,5).get("status")=="partial","factory checkpoints local-finish transport")
	worker.release()
	worker=GemFrameWorker.new(root)
	check(not worker.run(job).is_empty() and worker.counters.resumed_samples==5,"factory resumes local-finish transport")
	var master:=worker.store.read(GemFramePlan.master_key(job))
	check(master.metadata.surface_transport.walks>0,"master records actual spatial-finish micro-walks")
	worker.release()
	worker=GemFrameWorker.new(root)
	job.exposure=1.2
	check(not worker.run(job).is_empty() and worker.tracer._print_only,"local finish reprints without retracing")
	worker.release()

static func mean_y(values: PackedFloat32Array) -> float:
	var sum_y:=0.0
	var coverage:=0.0
	for i in values.size()/4:
		sum_y+=values[i*4+1]
		coverage+=values[i*4+3]
	return sum_y/maxf(coverage,1e-10)
