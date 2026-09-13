extends SceneTree
var checks:=0
var failures:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: "+label)
func _initialize()->void:
	var stone:GemStone=load("res://data/lapidary/stones/diamond.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition.cleavage=load("res://data/lapidary/conditions/diamond_cleavage.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for outline in [&"round",&"square",&"triangle",&"oval",&"diamond",&"rectangle",&"marquise",&"pear"]:
		stone.shape=GemShape.faceted_outline(outline)
		for depth in [.1,.7]:
			stone.condition.cleavage.depth_mm=depth
			stone.crystal_to_stone=Quaternion(Vector3(1,2,3).normalized(),.43)
			var fast:=LapidaryStoneCompiler.compile(stone,true)
			var reference:=LapidaryStoneCompiler.compile(stone,false)
			check(fast.get("geometry_backend")=="convex_cleavage" and not fast.has("mesh"),"convex cleavage compiles as planes")
			check(reference.has("boundaries"),"reference backend remains independently selectable")
			var mesh:=GemShapeCompiler.from_hull(fast.planes,fast.facet_ids)
			check(mesh.validate().is_empty(),"clipped %s %.1f hull is closed: %s"%[outline,depth,mesh.validate()])
			var volume:=mesh.signed_volume()*pow(stone.size_mm,3)
			check(absf(volume-fast.condition_report.cleavage.retained_mm3)<.0001,"clipped hull volume agrees with independent clipped-boundary integral")
			check(fast.plane_surface_ids[-1]==1 and fast.facet_ids[-1]==-1 and fast.surfaces.size()==2,"cut preserves face semantics and separate finish")
	stone.shape.mode="cabochon"
	check(LapidaryStoneCompiler.compile(stone).has("boundaries"),"analytic curved host keeps general region representation")
	stone.shape=GemShape.faceted_outline(&"round")
	var defect:=GemDefect.new();defect.kind="crystal"
	stone.condition.defects.append(defect)
	check(LapidaryStoneCompiler.compile(stone).has("boundaries"),"additional regions keep general representation")
	stone.condition.defects.clear()
	var inst:=LapidaryStoneCompiler.compile(stone)
	var tracer:=GemTracer.new()
	var lighting:=GemRigCompiler.compile(load("res://data/lapidary/rigs/gameplay_studio.tres"))
	inst.plane_surface_ids[-1]=2
	check(not tracer.configure_stone(inst,lighting,{}) and "missing surface slot" in tracer.configuration_error,"out-of-range surface slot rejected before device access")
	inst.plane_surface_ids=PackedInt32Array()
	check(not tracer.configure_stone(inst,lighting,{}) and "complete convex plane" in tracer.configuration_error,"empty slot table cannot bypass validation")
	print("Convex cleavage: %d checks, %d failures"%[checks,failures])
	print("CHECK_COMPLETE: test_convex_cleavage"); quit(1 if failures else 0)
