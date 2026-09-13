extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:
	var source:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	source.condition=GemCondition.new();source.material=GemMaterial.new();source.material.species=GemSpecies.new()
	source.material.species.ordinary.index_offset=.5
	var recipe:=GemMicrostructureRecipe.new();var population:=GemInclusionPopulation.new()
	population.population_id=&"furnace";population.count=8
	population.habit=GemCrystalHabit.prism(4,.04,.08,35)
	population.domain.radius_mm=Vector3(1.3,.8,.5)
	population.filling=GemMaterial.new();population.filling.species=GemSpecies.new()
	population.filling.species.ordinary.index_offset=.6
	population.filling.species.extraordinary=GemIndexCurve.new();population.filling.species.extraordinary.index_offset=.7
	recipe.populations.append(population)
	var result:=GemMicrostructureCompiler.realize(source,recipe)
	check(result.error.is_empty(),"furnace population realization")
	if not result.error.is_empty():print("CHECK_COMPLETE: microstructure_gpu_check"); quit(1);return
	var instance:=LapidaryStoneCompiler.compile(result.stone)
	var tracer:=GemTracer.create(48,48)
	if tracer==null:print("CHECK_COMPLETE: microstructure_gpu_check"); quit(1);return
	var lighting:=GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	var policy:=GemRung.policy(GemRung.PREVIEW);policy.denoise_passes=0;policy.birefringence=false
	for mode in ["scalar","polarized","crystal"]:
		policy.polarization=mode=="polarized";policy.crystal_transport=mode=="crystal"
		instance=LapidaryStoneCompiler.compile(result.stone)
		# Isotropic polarized transport has an explicit isotropic-real-index
		# fixture; the Maxwell fixture retains both principal indices.
		if mode!="crystal":
			for material in instance.region_materials:material.extraordinary_refraction={}
		var configured:=tracer.configure_stone(instance,lighting,policy)
		check(configured,mode+" populated habit admission")
		if not configured:continue
		tracer.set_clip_sample(Quaternion(Vector3.UP,.3),0,Vector4.ONE,1.4);tracer.accumulate(64)
		check(tracer.transport_error().is_empty(),mode+" populated paths valid")
		var metric:=GemCutMetrics.frame(tracer.read_xyz())
		check(metric.error.is_empty() and absf(metric.mean_Y-1)<.004,mode+" clear populations conserve furnace radiance")
	# Index-matched slab reference isolates the realized filling's local axis.
	source.size_mm=1;source.material.species.ordinary.index_offset=0
	source.shape.mode="loft"
	source.shape.outline_points=PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)])
	source.shape.loft_sections=PackedVector2Array([Vector2(-1,1),Vector2(1,1)])
	var defect:=GemDefect.new();defect.kind="crystal"
	defect.filling=GemMaterial.new();defect.filling.species=GemSpecies.new()
	var spectrum:=GemChromophore.new();spectrum.wavelength_step_nm=400
	spectrum.absorption_mm=PackedFloat32Array([.1,.1]);spectrum.absorption_eray_mm=PackedFloat32Array([.9,.9])
	defect.filling.absorbers.append(GemAbsorber.relative(spectrum))
	source.condition.defects.append(defect)
	for mode in ["scalar","polarized","crystal"]:
		policy.polarization=mode=="polarized";policy.crystal_transport=mode=="crystal"
		for angle in [0.0,PI/2]:
			defect.orientation=Quaternion(Vector3.UP,angle)
			check(tracer.configure_stone(LapidaryStoneCompiler.compile(source),lighting,policy),mode+" rotated filling admission")
			tracer.set_clip_sample(Quaternion.IDENTITY,0,Vector4.ONE,.04);tracer.accumulate(64)
			var metric:=GemCutMetrics.frame(tracer.read_xyz())
			var expected:=exp(-.1*.2) if angle==0 else .5*(exp(-.1*.2)+exp(-.9*.2))
			check(metric.error.is_empty() and absf(metric.mean_Y-expected)<.0003,mode+" local-axis Beer reference: "+str(metric.get("mean_Y")))
			check(tracer.transport_error().is_empty(),mode+" valid rotated filling paths")
	tracer.release();print("Microstructure GPU: %d checks, %d failures"%[checks,failures]);print("CHECK_COMPLETE: microstructure_gpu_check"); quit(1 if failures else 0)
