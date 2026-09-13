extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var cube:=GemCrystalHabit.new()
	var mesh:=GemCrystalHabitCompiler.compile(cube)
	check(mesh.validate().is_empty() and absf(mesh.signed_volume()-.008)<1e-8,"physical support cube volume")
	mesh.vertices[0]=Vector3(99,99,99)
	check(GemCrystalHabitCompiler.compile(cube).validate().is_empty(),"cached habit geometry is detached")
	cube.faces[0]=Plane(Vector3.RIGHT,.2)
	check(absf(GemCrystalHabitCompiler.compile(cube).signed_volume()-.012)<1e-8,"mutated support invalidates template cache")
	var octahedron:=GemCrystalHabit.new();octahedron.faces.clear()
	for x in [-1,1]:
		for y in [-1,1]:
			for z in [-1,1]:octahedron.faces.append(Plane(Vector3(x,y,z).normalized(),.1/sqrt(3)))
	check(absf(GemCrystalHabitCompiler.compile(octahedron).signed_volume()-4.0/3*.001)<1e-8,"custom non-prismatic octahedral habit")
	for sides in [3,4,6,8]:
		var habit:=GemCrystalHabit.prism(sides,.1,.4)
		var volume:float=2*.4*sides*.01*tan(PI/sides)
		check(absf(GemCrystalHabitCompiler.compile(habit).signed_volume()-volume)<1e-7,"prism analytic volume %d"%sides)
		var terminated:=GemCrystalHabit.prism(sides,.1,.4,35)
		var solid:=GemCrystalHabitCompiler.compile(terminated)
		check(solid.validate().is_empty() and solid.signed_volume()<volume,"terminated physical supports %d"%sides)
		var bound_error:=0.0
		for p in solid.vertices:
			for face in terminated.faces:bound_error=maxf(bound_error,face.normal.dot(p)-face.d)
		check(bound_error<1e-6,"vertices obey authored support planes")
	var invalid:=GemCrystalHabit.new();invalid.faces[0]=Plane(Vector3.ZERO,.1)
	check(not invalid.validate().is_empty() and GemCrystalHabitCompiler.compile(invalid).vertices.is_empty(),"invalid normal rejected")
	invalid=GemCrystalHabit.new();invalid.faces.remove_at(0)
	check(GemCrystalHabitCompiler.compile(invalid).vertices.is_empty(),"unbounded habit rejected")
	var source:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var original:=source.fingerprint()
	var recipe:=GemMicrostructureRecipe.new()
	var population:=GemInclusionPopulation.new()
	population.population_id=&"growth_layer";population.count=12
	population.habit=GemCrystalHabit.prism(4,.025,.06,35)
	population.domain.radius_mm=Vector3(1.5,.8,.3);population.domain.center_mm=Vector3(.2,0,-.1)
	population.angular_spread_deg=0
	population.filling=source.material.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	population.orientation_families=[Quaternion(Vector3.UP,.7)]
	recipe.populations.append(population)
	var result:=GemMicrostructureCompiler.realize(source,recipe)
	check(result.error.is_empty(),"bounded population realizes: "+result.error)
	if not result.error.is_empty():print("CHECK_COMPLETE: test_microstructure"); quit(1);return
	var stone:GemStone=result.stone
	check(source.fingerprint()==original and source.condition.defects.is_empty(),"authoring source remains unchanged")
	check(stone.condition.defects.size()==12,"requested explicit regions realized")
	check(stone.fingerprint()==GemMicrostructureCompiler.realize(source,recipe).stone.fingerprint(),"identical recipe and seed reproduce exact specimen")
	var radius:float=result.report.populations[0].unscaled_bound_mm
	for i in stone.condition.defects.size():
		var a:=stone.condition.defects[i]
		check(population.domain.density(a.center_mm)>0,"center follows common density domain")
		check(a.orientation.is_equal_approx(population.orientation_families[0]),"zero spread retains crystal family frame")
		for j in i:
			var b:=stone.condition.defects[j]
			check(a.center_mm.distance_to(b.center_mm)+1e-6>=radius*(a.crystal_scale+b.crystal_scale)+population.minimum_gap_mm,"conservative physical separation")
	population.count=5
	var prefix:=GemMicrostructureCompiler.realize(source,recipe)
	for i in 5:check(GemContentIdentity.digest(prefix.stone.condition.defects[i])==GemContentIdentity.digest(stone.condition.defects[i]),"count reduction preserves earlier members")
	population.count=12
	var second:GemInclusionPopulation=population.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	second.population_id=&"other_layer";second.count=1;second.domain.center_mm=Vector3(2,0,0)
	recipe.populations.push_front(second)
	var extended:=GemMicrostructureCompiler.realize(source,recipe)
	for i in 12:check(GemContentIdentity.digest(extended.stone.condition.defects[i+1])==GemContentIdentity.digest(stone.condition.defects[i]),"adding an independent population preserves existing seed channels")
	recipe.populations.pop_front()
	source.cut.table_ratio=.48
	check(GemContentIdentity.digest(GemMicrostructureCompiler.realize(source,recipe).stone.condition)==GemContentIdentity.digest(stone.condition),"recutting does not move physical inclusions")
	source.grade.clarity=.01
	check(GemContentIdentity.digest(GemMicrostructureCompiler.realize(source,recipe).stone.condition)==GemContentIdentity.digest(stone.condition),"grade metadata cannot change microstructure")
	source.crystal_to_stone=Quaternion(Vector3.RIGHT,.4)*Quaternion(Vector3.UP,.5)
	var rotated:=GemMicrostructureCompiler.realize(source,recipe)
	for i in 12:
		check(rotated.stone.condition.defects[i].center_mm.is_equal_approx(source.crystal_to_stone*stone.condition.defects[i].center_mm),"host frame rotates placement coherently")
	var compiled:=LapidaryStoneCompiler.compile(rotated.stone)
	check(not compiled.has("compilation_error") and compiled.region_materials.size()==12,"realized habits compile to filled regions")
	var expected:Vector3=rotated.stone.condition.defects[0].orientation*population.filling.species.optic_axis_stone.normalized()
	check(compiled.region_materials[0].optic_axis.is_equal_approx(expected),"inclusion optical axis follows its own crystal geometry")
	var first:GemDefect=stone.condition.defects[0]
	var before:=GemDefectCompiler.compile(first,source.size_mm).signed_volume()
	first.crystal_scale*=2
	check(absf(GemDefectCompiler.compile(first,source.size_mm).signed_volume()/before-8)<1e-4,"uniform physical scaling cubes volume")
	first.crystal_scale*=.5
	var job:=GemFrameJob.new();job.stone=rotated.stone
	job.rig=load("res://data/lapidary/rigs/gameplay_studio.tres");job.print_style=GemPrint.load_house()
	var error:=GemJobValidator.validate(job)
	check(error.is_empty(),"realized specimen admitted to normal factory: "+error)
	var out:="res://artifacts/microstructure/test-specimen.res"
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	check(GemResourceBundle.save(rotated.stone,out)==OK,"physical plane habit serializes to binary job resource")
	var loaded:GemStone=ResourceLoader.load(out,"",ResourceLoader.CACHE_MODE_IGNORE)
	check(loaded!=null and loaded.fingerprint()==rotated.stone.fingerprint(),"resource round-trip preserves planes, frames and seed identity")
	population.domain.scatter_per_mm=.1
	check(not recipe.validate().is_empty(),"resolved population cannot silently add effective scattering")
	population.domain.scatter_per_mm=0
	recipe.populations.append(population)
	check(not recipe.validate().is_empty(),"duplicate seed-channel ID rejected")
	recipe.populations.pop_back()
	population.domain.radius_mm=Vector3(.001,.001,.001);population.count=2
	var crowded:=GemMicrostructureCompiler.realize(source,recipe)
	check(not crowded.error.is_empty() and not crowded.has("stone"),"infeasible packing fails without partial output or shrunken inclusions")
	population.habit=null
	check(not GemMicrostructureCompiler.realize(source,recipe).error.is_empty(),"missing habit rejected before compilation")
	var example:GemMicrostructureRecipe=load("res://data/lapidary/microstructures/diagnostic_crystal_layer.tres")
	check(example.validate().is_empty() and GemMicrostructureCompiler.realize(source,example).error.is_empty(),"authored diagnostic recipe is usable without source-code edits")
	print("Microstructure: %d checks, %d failures"%[checks,failures]);print("CHECK_COMPLETE: test_microstructure"); quit(1 if failures else 0)
