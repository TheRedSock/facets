extends SceneTree
var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var planes:=PackedFloat32Array()
	for n:Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]:
		planes.append_array(PackedFloat32Array([n.x,n.y,n.z,1,0,0,0,0]))
	var recipe:=GemRounding.new();recipe.radius_mm=.2;recipe.angular_step_deg=6
	var result:=GemRoundingCompiler.compile(planes,PackedInt32Array(),1,recipe)
	check(result.get("error","").is_empty(),"rounded cube: "+str(result.get("error")))
	if result.has("mesh"):
		var mesh:GemMesh=result.mesh
		var a:=1-recipe.radius_mm;var r:=recipe.radius_mm
		# Core cube + six face slabs + twelve quarter-cylinders + eight octants.
		var exact:=8*a*a*a+24*a*a*r+6*PI*a*r*r+4*PI*r*r*r/3
		var volume:=mesh.signed_volume()
		check(volume<exact and exact-volume<.002,"cube volume agrees with independent analytic decomposition")
		check(mesh.validate().is_empty(),"closed oriented rounded cube")
		var extent:=0.0
		for vertex in mesh.vertices:extent=maxf(extent,maxf(absf(vertex.x),maxf(absf(vertex.y),absf(vertex.z))))
		check(extent<=1.000001,"rounding adds no material outside cube")
		var original_key:=mesh.fingerprint()
		mesh.vertices[0]+=Vector3.ONE
		check(GemRoundingCompiler.compile(planes,PackedInt32Array(),1,recipe).mesh.fingerprint()==original_key,"cached mesh cannot be mutated by a consumer")
		var scale_recipe:GemRounding=recipe.duplicate();scale_recipe.radius_mm*=3
		var scaled:=GemRoundingCompiler.compile(planes,PackedInt32Array(),3,scale_recipe)
		check(absf(scaled.report.retained_mm3-result.report.retained_mm3*27)<1e-8,"millimeter scaling is volumetrically consistent")
		print("Rounded cube ",JSON.stringify(result.report)," exact volume ",exact)
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var geometry:=LapidaryStoneCompiler.compile_geometry(stone)
	recipe.radius_mm=.03;recipe.angular_step_deg=10
	result=GemRoundingCompiler.compile(geometry.planes,geometry.facet_ids,stone.size_mm,recipe)
	check(result.get("error","").is_empty(),"rounded faceted quartz: "+str(result.get("error")))
	if result.has("mesh"):print("Rounded quartz ",JSON.stringify(result.report))
	stone.size_mm=4
	stone.condition.rounding=recipe
	for outline in [&"round",&"square",&"triangle",&"oval",&"diamond",&"rectangle",&"marquise",&"pear"]:
		stone.shape=GemShape.faceted_outline(outline)
		var compiled:=LapidaryStoneCompiler.compile(stone)
		check(not compiled.has("compilation_error"),"admit rounded "+str(outline)+": "+str(compiled.get("compilation_error","")))
		if compiled.has("mesh"):
			check(compiled.mesh.validate().is_empty(),"closed rounded "+str(outline))
			check(compiled.condition_report.rounding.removed_mm3>0,"positive material removal")
	stone.shape=GemShape.faceted_outline(&"round")
	var job:=GemFramePlan.animation(stone,load("res://data/lapidary/clips/idle.tres"),load("res://data/lapidary/rigs/gameplay_studio.tres"),GemPrint.load_house(),GemRung.INTERACT)[0]
	check(GemJobValidator.validate(job).is_empty(),"rounded factory job admitted")
	var optical:=GemFramePlan.master_key(job);var primary:=GemGeometryPlan.key(job,2)
	recipe.radius_mm*=1.5
	check(GemFramePlan.master_key(job)!=optical and GemGeometryPlan.key(job,2)!=primary,"radius edits invalidate optics and geometry")
	var path:="res://artifacts/rounding/portable.res"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	check(GemResourceBundle.save(job,path)==OK,"binary job stores rounding recipe")
	var copy:GemFrameJob=load(path)
	check(GemFramePlan.master_key(copy)==GemFramePlan.master_key(job),"binary rounding job keeps exact identity")
	recipe.radius_mm=100
	check(not GemJobValidator.validate(job).is_empty(),"collapsed core rejected before device creation")
	recipe.radius_mm=.03;recipe.max_removed_fraction=1e-8
	check(not GemJobValidator.validate(job).is_empty(),"removed-volume budget enforced")
	recipe.max_removed_fraction=.25;stone.shape.mode="cabochon"
	check(not GemJobValidator.validate(job).is_empty(),"unsupported curved input rejected explicitly")
	recipe.radius_mm=0
	check(GemJobValidator.validate(job).is_empty(),"disabled rounding permits ordinary cabochons")
	var diamond:GemStone=load("res://data/lapidary/stones/diamond.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	diamond.condition.rounding=GemRounding.new();diamond.condition.rounding.radius_mm=.03;diamond.condition.rounding.angular_step_deg=12
	diamond.condition.cleavage=load("res://data/lapidary/conditions/diamond_cleavage.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	diamond.condition.cleavage.depth_mm=.15
	var mixed:=LapidaryStoneCompiler.compile(diamond)
	check(not mixed.has("compilation_error") and mixed.has("boundaries"),"cleavage operates on the rounded host")
	check(mixed.get("condition_report",{}).has("rounding") and mixed.get("condition_report",{}).has("cleavage"),"condition reports retain both ordered operations")
	if mixed.has("mesh"):check(mixed.mesh.validate().is_empty(),"combined rounded/cleaved mesh admitted")
	print("Rounding: %d checks, %d failures"%[checks,failures]);quit(1 if failures else 0)
