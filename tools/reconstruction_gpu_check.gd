extends SceneTree
## Component conservation, inactive finish, furnace and progressive state.
const Cases = preload("res://tools/reconstruction_lookdev.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: "+message)
func _initialize() -> void:
	var tracer:=GemTracer.create(48,48)
	if tracer==null:quit(1);return
	var policy:=GemRung.policy(GemRung.PREVIEW)
	policy["birefringence"]=false
	policy["max_bounces"]=256
	var lights:=GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	for polarized in [false,true]:
		policy["polarization"]=polarized
		for item in 6:
			var stone:=Cases.specimen(item if item<4 else 2)
			if item==4:stone.condition.finish.fields[0].center_mm=Vector3(1000,1000,1000)
			if item==5:
				stone.condition.finish.fields.clear()
				stone.condition.finish.alpha_u=.3
				stone.condition.finish.alpha_v=.3
			var compiled:=LapidaryStoneCompiler.compile(stone)
			# Synthetic isotropic host isolates reconstruction in Mueller tests.
			if polarized:compiled["extraordinary_refraction"]={}
			var configured:=tracer.configure_stone(compiled,lights,policy)
			check(configured,"component fixture config")
			if not configured:tracer.release();quit(1);return
			tracer.accumulate(128)
			var state:=tracer.checkpoint()
			var raw:PackedFloat32Array=state.buffers.accum.to_float32_array()
			var sharp:PackedFloat32Array=state.buffers.ballistic.to_float32_array()
			var residual:PackedFloat32Array=state.buffers.residual.to_float32_array()
			var max_error:=0.0
			var sharp_y:=0.0
			var residual_y:=0.0
			for i in 48*48:
				for c in 3:max_error=maxf(max_error,absf(raw[i*4+c]-sharp[i*4+c]-residual[i*4+c])/128)
				sharp_y+=sharp[i*4+1]
				residual_y+=absf(residual[i*4+1])
			check(max_error<.00002,"sharp+residual conserves actual raw estimator")
			check(tracer.transport_error().is_empty(),"component paths complete")
			if item<4:check(sharp_y>0 and residual_y>0,"localized roughness retains both components")
			if item==4:
				check(residual_y<.00001,"inactive rough field leaves no filtered signal")
				var filtered:=tracer.read_reconstructed_xyz()
				var maximum:=0.0
				for i in raw.size():maximum=maxf(maximum,absf(filtered[i]-raw[i]/128))
				check(maximum<.00001,"inactive roughness cannot blur unrelated facets")
			if item==5:check(sharp_y<.00001 and residual_y>0,"uniform rough first boundary has no sharp component")
			var before:=tracer.read_reconstructed_xyz()
			check(tracer.restore_checkpoint(state),"component checkpoint restore")
			var after:=tracer.read_reconstructed_xyz()
			var difference:=0.0
			for i in before.size():difference=maxf(difference,absf(before[i]-after[i]))
			check(difference<.000001,"checkpoint restores reconstructed result")
			if item==2:
				tracer.accumulate(8)
				var resumed:=tracer.read_reconstructed_xyz()
				tracer.reset_accumulation()
				tracer.accumulate(136)
				var continuous:=tracer.read_reconstructed_xyz()
				var resume_error:=0.0
				for i in resumed.size():resume_error=maxf(resume_error,absf(resumed[i]-continuous[i]))
				check(resume_error<.00002,"resumed sharp/residual accumulation matches uninterrupted samples")
		# Energy also checks the filtered combination, not only raw transport.
		var furnace:=GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
		var lossless:=LapidaryStoneCompiler.compile(Cases.specimen(3))
		lossless["absorption"].fill(0)
		lossless["absorption_eray"]=PackedFloat32Array()
		if polarized:lossless["extraordinary_refraction"]={}
		check(tracer.configure_stone(lossless,furnace,policy),"mixed rough-volume furnace")
		tracer.accumulate(512)
		var xyz:=tracer.read_reconstructed_xyz()
		var sum_y:=0.0
		var coverage:=0.0
		for i in xyz.size()/4:sum_y+=xyz[i*4+1];coverage+=xyz[i*4+3]
		check(absf(sum_y/coverage-1)<.015,"reconstructed rough-volume furnace conserves radiance within sampling/filter budget")
	tracer.release()
	print("Reconstruction: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
