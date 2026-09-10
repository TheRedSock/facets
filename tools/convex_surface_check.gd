extends SceneTree
## Mixed convex/region packing and rough cut-face transport.
var failures := 0
var checks := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + message)
func _initialize() -> void:
	var stone: GemStone = load("res://data/lapidary/stones/diamond.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.material.scatter_per_mm = 0
	var recipe := GemCleavageRecipe.new()
	recipe.normals = PackedVector3Array([Vector3(1,0,.5).normalized()])
	recipe.depth_mm = 1.2
	recipe.finish.multiple_scattering = true
	stone.condition.cleavage = recipe
	var tracer := GemTracer.create(192,48)
	if tracer == null:
		quit(1)
		return
	var policy := GemRung.policy(GemRung.PREVIEW)
	policy["birefringence"] = false
	policy["max_bounces"] = 256
	policy["denoise_passes"] = 0
	var furnace := GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	for polarized in [false,true]:
		policy["polarization"] = polarized
		for alpha in [.15,.3]:
			recipe.finish.alpha_u = alpha
			recipe.finish.alpha_v = alpha
			var cut := LapidaryStoneCompiler.compile(stone)
			var general := LapidaryStoneCompiler.compile(stone,false)
			stone.condition.cleavage = null
			var pristine := LapidaryStoneCompiler.compile(stone)
			stone.condition.cleavage = recipe
			check(tracer.configure_stones([cut,pristine,cut,general],furnace,policy,Vector2i(4,1)),"mixed convex/mesh finish blocks configure")
			tracer.accumulate(512)
			check(tracer.transport_error().is_empty(),"mixed rough cut transport completes")
			var stats := tracer.surface_diagnostics()
			check(stats.walks>0 and stats.micro_events>=stats.walks,"rough cut faces invoke Smith transport")
			var values := tracer.read_xyz()
			var geometry := tracer.geometry_aov(2)
			for cell in 4:
				var sum_y := 0.0
				var coverage := 0.0
				var cut_pixels := 0
				var id_errors := 0
				for y in 48:
					for x in 48:
						var px := cell*48+x
						var i := (y*192+px)*4
						sum_y += values[i+1]
						coverage += values[i+3]
						var a := geometry.record(px,y)
						if a.coverage>0:
							if a.instance!=cell or a.material!=cell: id_errors+=1
							if a.region==1:
								cut_pixels+=1
								if a.facet!=-1:id_errors+=1
				check(coverage>0 and absf(sum_y/coverage-1)<(.015 if polarized else .005),"per-instance furnace retains radiance")
				check(id_errors==0 and ((cut_pixels==0) if cell==1 else (cut_pixels>0)),"semantic cut-face slots do not change physical medium/instance IDs")
				print(JSON.stringify({"cell":cell,"polarized":polarized,"alpha":alpha,"Y":sum_y/maxf(coverage,1e-12),"cut_pixels":cut_pixels,"id_errors":id_errors}))
	tracer.release()
	print("Convex surfaces: %d checks, %d failures" % [checks,failures])
	quit(1 if failures else 0)
