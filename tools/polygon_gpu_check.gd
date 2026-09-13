extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var square:=PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)])
	var subdivided:=PackedVector2Array()
	for side in 4:
		for k in 32:subdivided.append(square[side].lerp(square[(side+1)%4],k/32.0))
	var sections:=PackedVector2Array([Vector2(-.5,1),Vector2(.5,1)])
	var base:=LapidaryStoneCompiler.compile(load("res://data/lapidary/stones/quartz.tres"))
	base["planes"]=PackedFloat32Array();base["size_mm"]=1.0
	base.absorption.fill(0);base["absorption_eray"]=PackedFloat32Array()
	base["scatter"]={"sigma_per_mm":0.0,"g":0.0};base["zoning"]={}
	base["sellmeier_b"]=Vector3.ZERO;base["sellmeier_c"]=Vector3.ZERO
	base["index_offset"]=.5;base["extraordinary_refraction"]={}
	var tracer:=GemTracer.create(64,64)
	if tracer==null:print("CHECK_COMPLETE: polygon_gpu_check"); quit(1);return
	var rig:=GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	var furnace:=GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	var policy:=GemRung.policy(GemRung.PREVIEW)
	policy["birefringence"]=false;policy["denoise_passes"]=0
	for mode in ["scalar","polarized","crystal"]:
		policy["polarization"]=mode=="polarized";policy["crystal_transport"]=mode=="crystal"
		for angle in [0.0,.35]:
			var reference:=PackedFloat32Array()
			var geometry:GemGeometryAov=null
			for variant in 2:
				base["mesh"]=GemShapeCompiler.loft(square if variant==0 else subdivided,sections)
				check(tracer.configure_stone(base,rig,policy),mode+" collinear loft GPU admission")
				tracer.set_clip_sample(Quaternion(Vector3.UP,angle)*Quaternion(Vector3.RIGHT,angle*.7),0,Vector4.ONE,1.7)
				var aov:=tracer.geometry_aov(1)
				tracer.accumulate(64)
				check(tracer.transport_error().is_empty(),mode+" collinear loft valid paths")
				var film:=tracer.read_xyz()
				if variant==0:reference=film;geometry=aov;continue
				var error:=0.0;var coverage_equal:=true;var distance:=0.0
				for i in film.size():error=maxf(error,absf(film[i]-reference[i]))
				for y in 64:
					for x in 64:
						var a:=aov.record(x,y);var b:=geometry.record(x,y)
						coverage_equal=coverage_equal and a.coverage==b.coverage
						if a.coverage>0 and b.coverage>0:distance=maxf(distance,a.position_mm.distance_to(b.position_mm))
				check(coverage_equal and distance<5e-6,mode+" cap subdivisions preserve primary surface")
				check(error<.0005,mode+" cap subdivisions preserve optical film: "+str(error))
		var outline:=PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(.4,1),Vector2(.4,-.2),Vector2(-.4,-.2),Vector2(-.4,1),Vector2(-1,1)])
		base["mesh"]=GemShapeCompiler.loft(outline,sections)
		check(tracer.configure_stone(base,furnace,policy),mode+" concave loft GPU admission")
		tracer.set_clip_sample(Quaternion(Vector3.UP,.6)*Quaternion(Vector3.RIGHT,.4),0,Vector4.ONE,1.7)
		tracer.accumulate(64)
		check(tracer.transport_error().is_empty(),mode+" concave loft paths valid")
		var film:=tracer.read_xyz();var energy:=0.0;var pixels:=0
		for i in 4096:
			if film[i*4+3]>.999:energy+=film[i*4+1];pixels+=1
		check(pixels>100 and absf(energy/pixels-1)<.003,mode+" concave dielectric white furnace")
	tracer.release()
	print("Polygon GPU: %d checks, %d failures"%[checks,failures]);print("CHECK_COMPLETE: polygon_gpu_check"); quit(1 if failures else 0)
