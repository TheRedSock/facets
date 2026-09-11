extends SceneTree
var failures:=0
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _initialize()->void:
	var planes:=PackedFloat32Array()
	for n:Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]:planes.append_array(PackedFloat32Array([n.x,n.y,n.z,1,0,0,0,0]))
	var recipe:=GemRounding.new();recipe.radius_mm=.2
	var rounded:=GemRoundedSolid.compile(planes,PackedInt32Array(),1,recipe)
	check(rounded.error.is_empty(),"rounded cube compiles")
	if not rounded.error.is_empty():quit(1);return
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres")
	var instance:=LapidaryStoneCompiler.compile(stone)
	instance["rounded_solid"]=rounded;instance["planes"]=PackedFloat32Array();instance["size_mm"]=1.0
	instance["absorption"]=PackedFloat32Array();instance.absorption.resize(401)
	instance["absorption_eray"]=PackedFloat32Array();instance["scatter"]={"sigma_per_mm":0.0,"g":0.0}
	instance["sellmeier_b"]=Vector3.ZERO;instance["sellmeier_c"]=Vector3.ZERO;instance["index_offset"]=.5;instance["extraordinary_refraction"]={}
	var lighting:=GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	var tracer:=GemTracer.create(64,64)
	if tracer==null:quit(1);return
	var policy:=GemRung.policy(GemRung.PREVIEW);policy["birefringence"]=false;policy["denoise_passes"]=0
	var maximum_distance:=0.0;var minimum_distance:=0.0;var maximum_angle:=0.0;var curved:=0
	for pose in 3:
		policy["polarization"]=pose==1
		policy["crystal_transport"]=pose==2
		check(tracer.configure_stone(instance,lighting,policy),"continuous rounded GPU admission")
		tracer.set_clip_sample(Quaternion(Vector3.UP,.31*pose)*Quaternion(Vector3.RIGHT,.23*pose),0,Vector4.ONE,1.8)
		var aov:=tracer.geometry_aov(1)
		check(aov!=null,"rounded geometry AOV")
		if aov==null:continue
		for y in 64:
			for x in 64:
				var hit:=aov.record(x,y)
				if hit.coverage==0:continue
				var p:Vector3=hit.position_mm
				var closest:=Vector3(clampf(p.x,-.8,.8),clampf(p.y,-.8,.8),clampf(p.z,-.8,.8))
				var delta:=p-closest
				var distance:=delta.length()-.2
				maximum_distance=maxf(maximum_distance,distance);minimum_distance=minf(minimum_distance,distance)
				maximum_angle=maxf(maximum_angle,acos(clampf(delta.normalized().dot(hit.normal_object),-1,1)))
				if hit.facet<0:curved+=1
		tracer.accumulate(64)
		check(tracer.transport_error().is_empty(),"rounded dielectric paths valid")
		var xyz:=tracer.read_xyz();var sum:=0.0;var count:=0
		for i in 4096:
			if xyz[i*4+3]>.999:sum+=xyz[i*4+1];count+=1
		print("Furnace pose %d: mean=%s pixels=%d" % [pose,sum/maxi(1,count),count])
		check(count>0 and absf(sum/count-1)<.002,"rounded dielectric white furnace pose%d" % pose)
	check(curved>40,"AOV samples actual curved patches")
	check(maximum_distance<.000005 and minimum_distance>=-.000005,"GPU hit positions lie within analytic rounded-box surface")
	check(maximum_angle<deg_to_rad(.1),"GPU normals approach analytic rounded-box normals")
	_mixed(instance,planes,lighting)
	print("Continuous transport GPU: %d checks, %d failures; distance [%s,%s], normal degrees %s"%[checks,failures,minimum_distance,maximum_distance,rad_to_deg(maximum_angle)])
	tracer.release();quit(1 if failures else 0)

func _mixed(base:Dictionary,planes:PackedFloat32Array,lighting:GemLighting)->void:
	var warm:=GemTracer.create(64,16)
	var cold:=GemTracer.create(64,16)
	if warm==null or cold==null:check(false,"mixed tracers created");return
	cold._geometry_cache.entry_limit=0
	var boxes:=load("res://tests/lapidary/test_boundaries.gd")
	var boundaries:=GemBoundarySet.new()
	check(boundaries.add_rounded(base.rounded_solid,0),"mixed continuous host")
	check(boundaries.add(boxes.box(Vector3(-.45,-.45,-.45),Vector3(.45,.45,.45)),-1),"mixed cavity")
	check(boundaries.add(boxes.box(Vector3(-.2,-.2,-.2),Vector3(.2,.2,.2)),1),"filled region nested inside cavity")
	var nested:=base.duplicate(true)
	nested.erase("rounded_solid");nested["boundaries"]=boundaries
	nested["region_materials"]=[base.duplicate(true)]
	var sharp:=base.duplicate(true);sharp.erase("rounded_solid")
	sharp["mesh"]=GemShapeCompiler.from_hull(planes)
	var policy:=GemRung.policy(GemRung.PREVIEW)
	policy["birefringence"]=false;policy["denoise_passes"]=0
	for mode in ["scalar","polarized","crystal"]:
		policy["polarization"]=mode=="polarized";policy["crystal_transport"]=mode=="crystal"
		for repetition in 2:
			var instances:=[nested,sharp,base,nested] if repetition==0 else [base,nested,sharp,nested]
			check(warm.configure_stones(instances,lighting,policy,Vector2i(4,1)),"%s mixed warm admission"%mode)
			check(cold.configure_stones(instances,lighting,policy,Vector2i(4,1)),"%s mixed cold admission"%mode)
			if not warm.configuration_error.is_empty() or not cold.configuration_error.is_empty():continue
			var poses:=[]
			for cell in 4:poses.append({"quat":Quaternion(Vector3.UP,.13*cell),"stone_index":cell})
			warm.set_instances(poses);cold.set_instances(poses)
			var aov:=warm.geometry_aov(2);var reference:=cold.geometry_aov(2)
			check(aov!=null and reference!=null and aov.data==reference.data,"%s mixed AOV identity after relocation"%mode)
			warm.accumulate(64);cold.accumulate(64)
			check(warm.transport_error().is_empty() and cold.transport_error().is_empty(),"%s mixed paths valid"%mode)
			var a:=warm.read_xyz();var b:=cold.read_xyz();var error:=0.0;var energy:=0.0;var count:=0
			for i in a.size():error=maxf(error,absf(a[i]-b[i]))
			for i in 1024:
				if a[i*4+3]>.999:energy+=a[i*4+1];count+=1
			check(error<3e-6,"%s cached/cold films agree"%mode)
			check(count>0 and absf(energy/count-1)<.003,"%s mixed white furnace"%mode)
	check(warm.geometry_cache_statistics().hits>8,"mixed batches exercise cached analytic and mesh geometry")
	var crystal:=LapidaryStoneCompiler.compile(load("res://data/lapidary/stones/quartz.tres"))
	crystal["rounded_solid"]=base.rounded_solid;crystal["planes"]=PackedFloat32Array();crystal["size_mm"]=1.0
	crystal.absorption.fill(0);crystal.absorption_eray.fill(0);crystal["scatter"]={"sigma_per_mm":0.0,"g":0.0}
	check(warm.configure_stone(crystal,lighting,policy),"actual uniaxial quartz continuous host")
	warm.set_stone_orientation(Quaternion(Vector3.UP,.31))
	warm.accumulate(64)
	check(warm.transport_error().is_empty(),"actual uniaxial curved-interface paths valid")
	var energy:=0.0;var count:=0;var data:=warm.read_xyz()
	for i in 1024:
		if data[i*4+3]>.999:energy+=data[i*4+1];count+=1
	check(count>0 and absf(energy/count-1)<.003,"actual uniaxial curved-interface furnace")
	warm.release();cold.release()
