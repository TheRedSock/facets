extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+message)
func _initialize()->void:
	var rounded:=OS.get_cmdline_user_args().has("--rounded")
	var stone:GemStone=load("res://data/lapidary/stones/diamond.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm=0
	var recipe:=GemCleavageRecipe.new()
	recipe.normals=PackedVector3Array([Vector3(1,0,.5).normalized()])
	recipe.depth_mm=.5
	stone.condition.cleavage=recipe
	if rounded:
		stone.condition.rounding=GemRounding.new()
		stone.condition.rounding.radius_mm=.12
	var inst:=LapidaryStoneCompiler.compile(stone)
	var tracer:=GemTracer.create(64,64)
	if tracer==null:quit(1);return
	var policy:=GemRung.policy(GemRung.PREVIEW)
	policy["birefringence"]=false
	policy["max_bounces"]=256
	policy["denoise_passes"]=0
	var furnace:=GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	for mode in (["scalar","polarized","crystal"] if rounded else ["scalar","polarized"]):
		policy["polarization"]=mode=="polarized"
		policy["crystal_transport"]=mode=="crystal"
		for angle in [0.0,-.5]:
			check(tracer.configure_stone(inst,furnace,policy),"configure cleavage furnace")
			tracer.set_stone_orientation(Quaternion(Vector3.UP,angle))
			tracer.accumulate(64 if rounded else 256)
			var values:=tracer.read_xyz()
			var y:=0.0;var alpha:=0.0
			for i in values.size()/4:y+=values[i*4+1];alpha+=values[i*4+3]
			check(absf(y/alpha-1)<.002,"cleaved scalar/Mueller furnace conserves radiance")
			check(tracer.transport_error().is_empty(),"cleavage transport completes")
			var geometry:=tracer.geometry_aov(2)
			var exposed:=0
			var error:=0.0
			for py in geometry.height:
				for px in geometry.width:
					var record:=geometry.record(px,py)
					if record.coverage>0 and record.region==1:
						exposed+=1
						error=maxf(error,absf(recipe.normals[0].dot(record.position_mm)-inst.condition_report.cleavage.plane_offset_mm))
			check(exposed>0 and error<.0001,"exposed cut AOV lies on declared physical plane")
	if rounded:
		check(inst.has("rounded_solid") and inst.boundaries.rounded_solid==inst.rounded_solid,"authored cleavage retains continuous host")
		check(inst.condition_report.cleavage.volume_reference=="tessellated_continuous_host","cap volume estimate remains distinct from optical geometry")
	tracer.release()
	var job:=GemFramePlan.animation(stone,load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.PREVIEW)[0]
	job.resolution=Vector2i(32,32);job.output_size=Vector2i(24,24);job.samples=16
	var output:="res://artifacts/cleavage/factory-%d" % Time.get_ticks_usec()
	var worker:=GemFrameWorker.new(output)
	check(worker.run(job,5).get("status")=="partial","cleavage partial frame")
	worker.release();worker=GemFrameWorker.new(output)
	check(not worker.run(job).is_empty() and worker.counters.resumed_samples==5,"cleavage resumed frame")
	var master:=worker.store.read(GemFramePlan.master_key(job))
	check(master.metadata.condition_report.cleavage.host_cap_mm3>0,"factory retains physical condition report")
	worker.release();worker=GemFrameWorker.new(output)
	job.exposure=1.2
	check(not worker.run(job).is_empty() and worker.tracer._print_only,"cleavage print-only reuse")
	worker.release()
	print(("Rounded " if rounded else "")+"Cleavage GPU: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
