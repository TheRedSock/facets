extends SceneTree
var failures := 0
var checks := 0
func check(value: bool,label:String) -> void:
	checks+=1
	if not value:
		failures+=1
		printerr("FAIL: "+label)
func box() -> GemMesh:
	return GemShapeCompiler.loft(PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(-1,1)]),PackedVector2Array([Vector2(-1,1),Vector2(1,1)]))
func _initialize() -> void:
	var cube:=box()
	var recipe:=GemCleavageRecipe.new()
	recipe.normals=PackedVector3Array([Vector3(1,1,1).normalized()])
	for size_mm in [1.0,3.0,10.0]:
		for depth in [0.01,0.1,0.5]:
			recipe.depth_mm=depth
			var realized:=GemCleavageCompiler.realize({"mesh":cube},null,size_mm,recipe)
			check(realized.error.is_empty(),"corner cleavage admits physical size/depth")
			if not realized.error.is_empty(): continue
			var expected:=pow(sqrt(3.0)*depth,3)/6.0
			check(absf(realized.report.host_cap_mm3-expected)<maxf(1e-9,expected*1e-5),"exact tetrahedral cap volume in mm3")
			var cutter:=GemDefectCompiler.compile(realized.defect,size_mm)
			check(cutter.validate().is_empty(),"finite air cutter closed")
			var boundaries:=GemBoundarySet.new()
			boundaries.add(cube,0)
			boundaries.add(cutter,-1)
			check(boundaries.mesh.validate().is_empty(),"cutter crosses host without coincident patches")
			var direction:=Vector3(-1,-1,-1).normalized()
			var length:=0.0
			for segment in boundaries.segments(-direction*20,direction):
				length+=segment.end-segment.begin
			check(absf(length*size_mm-(2*sqrt(3.0)*size_mm-depth))<0.001,"real removed cap shortens optical path")
	# Independent analytic slicing, including a disconnected concave cross-section.
	for d in [-1.5,-0.5,0.0,0.5,1.5]:
		check(absf(GemCleavageCompiler.retained_volume(cube,Vector3.RIGHT,d)-4*clampf(d+1,0,2))<1e-12,"axis-aligned cube slice volume")
	var outline:=PackedVector2Array([Vector2(-1,-1),Vector2(1,-1),Vector2(1,1),Vector2(.4,1),Vector2(.4,-.2),Vector2(-.4,-.2),Vector2(-.4,1),Vector2(-1,1)])
	var concave:=GemShapeCompiler.loft(outline,PackedVector2Array([Vector2(-.5,1),Vector2(.5,1)]))
	# Complement identity plus a separately calculated concave slice.
	for d in [-.7,0.0,.4]:
		var left:=GemCleavageCompiler.retained_volume(concave,Vector3.RIGHT,d)
		var right:=GemCleavageCompiler.retained_volume(concave,Vector3.LEFT,-d)
		check(absf(left+right-concave.signed_volume())<1e-12,"concave slice complements conserve volume")
	check(absf(GemCleavageCompiler.retained_volume(concave,Vector3.UP,.4)-2.32)<1e-7,"concave U slice agrees with independent rectangular area sum")
	var hollow:=box()
	var cavity:=box()
	for i in cavity.vertices.size():cavity.vertices[i]*=.5
	for i in cavity.triangle_count():
		var swap:=cavity.indices[i*3]
		cavity.indices[i*3]=cavity.indices[i*3+1]
		cavity.indices[i*3+1]=swap
	hollow.append_region(cavity,0)
	check(absf(GemCleavageCompiler.retained_volume(hollow,Vector3.RIGHT,.25)-4.25)<1e-12,"clipped signed boundary integral retains hollow-region subtraction")
	var dome:=GemShape.faceted_outline(&"oval")
	dome.mode="cabochon"
	dome.radial_segments=128
	dome.dome_rings=64
	var q:=Vector4(1,1.0/dome.aspect_ratio,dome.dome_height,-.04)
	recipe.normals=PackedVector3Array([Vector3.BACK])
	recipe.depth_mm=.1
	var cap:=GemCleavageCompiler.realize({"analytic_shape":q},dome,1.0,recipe)
	check(cap.error.is_empty(),"analytic cabochon supports cleavage")
	if cap.error.is_empty():
		var exact:=PI*q.x*q.y*(.1*.1/q.z-pow(.1,3)/(3*q.z*q.z))
		check(absf(cap.report.plane_offset_mm-(q.z-.1))<1e-12,"analytic upper support is exact")
		check(absf(cap.report.host_cap_mm3/exact-1)<.002,"labeled tessellated cap-volume estimate converges")
		check(cap.report.volume_reference=="tessellated_analytic_host","analytic volume approximation is explicit")
	var stone:GemStone=load("res://data/lapidary/stones/diamond.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	stone.condition.cleavage=load("res://data/lapidary/conditions/diamond_cleavage.tres").duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	var job:=GemFrameJob.new()
	job.stone=stone
	job.rig=load("res://data/lapidary/rigs/gameplay_studio.tres")
	job.print_style=GemPrint.load_house()
	check(GemJobValidator.validate(job).is_empty(),"physical cleavage factory admission")
	var compiled:=LapidaryStoneCompiler.compile(stone)
	check(compiled.get("geometry_backend")=="convex_cleavage" and compiled.plane_surface_ids[-1]==1,"convex recipe preserves planes and independent cut-face finish")
	check(compiled.condition_report.cleavage.host_cap_mm3>0,"realized cap volume reported")
	var original:=GemFramePlan.master_key(job)
	var geo:=GemGeometryPlan.key(job,4)
	stone.condition.cleavage.finish.alpha_u=.05
	check(GemFramePlan.master_key(job)!=original and GemGeometryPlan.key(job,4)==geo,"cleavage finish changes optics but not geometry")
	stone.condition.cleavage.depth_mm=.3
	check(GemGeometryPlan.key(job,4)!=geo,"depth changes geometry identity")
	geo=GemGeometryPlan.key(job,4)
	stone.crystal_to_stone=Quaternion(Vector3.UP,.4)
	var rotated:=LapidaryStoneCompiler.compile(stone)
	var normal_values:Array=rotated.condition_report.cleavage.normal_stone
	var actual:=Vector3(normal_values[0],normal_values[1],normal_values[2])
	var index:int=rotated.condition_report.cleavage.normal_index
	check(actual.distance_to(stone.crystal_to_stone*stone.condition.cleavage.normals[index])<1e-6,"cleavage shares the specimen crystal frame")
	check(rotated.optic_axis.distance_to(stone.crystal_to_stone*stone.material.species.optic_axis_stone.normalized())<1e-6,"host optics shares the crystal frame")
	check(GemGeometryPlan.key(job,4)!=geo,"crystal orientation changes cleavage geometry")
	stone.material.scatter_per_mm=0
	check("rough cleavage" in GemCrystalAdmission.stone_error(stone),"rough cleavage rejected by crystal backend before GPU work")
	original=GemContentIdentity.digest(stone.transport_inputs())
	stone.grade.surface=.1
	check(original==GemContentIdentity.digest(stone.transport_inputs()),"grade labels do not silently create damage")
	var saved:="res://artifacts/cleavage/roundtrip.res"
	DirAccess.make_dir_recursive_absolute(saved.get_base_dir())
	check(GemResourceBundle.save(job,saved)==OK,"binary recipe save")
	var restored:GemFrameJob=load(saved)
	check(restored.stone.condition.cleavage is GemCleavageRecipe and restored.stone.fingerprint()==stone.fingerprint(),"typed portable condition roundtrip")
	stone.condition.cleavage.depth_mm=0
	check(not LapidaryStoneCompiler.compile(stone).has("boundaries"),"zero depth keeps the convex pristine path")
	stone.crystal_to_stone=Quaternion(0,0,0,0)
	check(not GemJobValidator.validate(job).is_empty(),"invalid shared crystal frame rejected")
	stone.crystal_to_stone=Quaternion.IDENTITY
	stone.optic_axis_override=Vector3.RIGHT
	check(LapidaryStoneCompiler.compile(stone).optic_axis==Vector3.RIGHT,"explicit object-space optic-axis override remains authoritative")
	stone.optic_axis_override=Vector3.ZERO
	stone.condition.cleavage.depth_mm=100
	check(not GemJobValidator.validate(job).is_empty(),"overlarge removal rejected")
	var bad:=GemCleavageRecipe.new()
	check(not bad.validate().is_empty(),"missing crystal family rejected")
	bad.normals=PackedVector3Array([Vector3.ONE])
	check(not bad.validate().is_empty(),"unnormalized plane rejected")
	print("Cleavage: %d checks, %d failures" % [checks,failures])
	print("CHECK_COMPLETE: test_cleavage"); quit(1 if failures else 0)
