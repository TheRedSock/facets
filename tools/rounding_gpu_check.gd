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
	var rounded:=GemRoundingReference.compile(planes,PackedInt32Array(),1,recipe)
	check(rounded.has("mesh"),"rounded cube compiles")
	if not rounded.has("mesh"):print("CHECK_COMPLETE: rounding_gpu_check"); quit(1);return
	var stone:GemStone=load("res://data/lapidary/stones/quartz.tres")
	var instance:=LapidaryStoneCompiler.compile(stone)
	instance["mesh"]=rounded.mesh;instance["planes"]=PackedFloat32Array();instance["size_mm"]=1.0
	instance["absorption"]=PackedFloat32Array();instance.absorption.resize(401)
	instance["absorption_eray"]=PackedFloat32Array();instance["scatter"]={"sigma_per_mm":0.0,"g":0.0}
	instance["sellmeier_b"]=Vector3.ZERO;instance["sellmeier_c"]=Vector3.ZERO;instance["index_offset"]=.5;instance["extraordinary_refraction"]={}
	var lighting:=GemLighting.analytic(PackedFloat32Array(),Vector4(1,1,1,0))
	var tracer:=GemTracer.create(64,64)
	if tracer==null:print("CHECK_COMPLETE: rounding_gpu_check"); quit(1);return
	var policy:=GemRung.policy(GemRung.PREVIEW);policy["birefringence"]=false;policy["denoise_passes"]=0
	var maximum_distance:=0.0;var minimum_distance:=0.0;var maximum_angle:=0.0;var curved:=0
	for pose in 3:
		policy["polarization"]=pose==2
		check(tracer.configure_stone(instance,lighting,policy),"rounded mesh GPU admission")
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
		tracer.accumulate(256)
		check(tracer.transport_error().is_empty(),"rounded dielectric paths valid")
		var xyz:=tracer.read_xyz();var sum:=0.0;var count:=0
		for i in 4096:
			if xyz[i*4+3]>.999:sum+=xyz[i*4+1];count+=1
		check(count>0 and absf(sum/count-1)<.002,"rounded dielectric white furnace")
	check(curved>40,"AOV samples actual curved patches")
	check(maximum_distance<.000005 and minimum_distance>=-float(rounded.report.chord_sag_bound_mm)-.000005,"GPU hit positions lie within analytic rounded-box tessellation bound")
	check(maximum_angle<deg_to_rad(13),"GPU normals approach analytic rounded-box normals")
	print("Rounding GPU: %d checks, %d failures; distance [%s,%s], normal degrees %s"%[checks,failures,minimum_distance,maximum_distance,rad_to_deg(maximum_angle)])
	tracer.release();print("CHECK_COMPLETE: rounding_gpu_check"); quit(1 if failures else 0)
