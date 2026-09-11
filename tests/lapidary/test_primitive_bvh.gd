extends SceneTree
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: " + label)

func _initialize() -> void:
	for value in [-1e10,-1.00000001,-.1,-1e-40,0.0,1e-40,.1,1.00000001,1e10]:
		check(GemPrimitiveBvh.outward_float(value,false)<=value and GemPrimitiveBvh.outward_float(value,true)>=value,"outward wire bounds contain binary64 value %s" % value)
	var planes := PackedFloat32Array()
	for n:Vector3 in [Vector3.RIGHT,Vector3.LEFT,Vector3.UP,Vector3.DOWN,Vector3.BACK,Vector3.FORWARD]:
		planes.append_array(PackedFloat32Array([n.x,n.y,n.z,1,0,0,0,0]))
	var recipe := GemRounding.new(); recipe.radius_mm=.2
	var solid := GemRoundedSolid.compile(planes,PackedInt32Array(),1,recipe)
	check(solid.validation_error().is_empty(),"constructed continuous host sealed")
	var cache := GemPackedGeometryCache.new()
	var a := cache.packed(null,solid)
	check(a.error.is_empty() and a.triangles.size()==26*64 and a.clips.size()>0,"continuous cube produces compact primitive payload")
	var size:int=a.nodes.size()+a.triangles.size()+a.clips.size()
	check(cache.retained_bytes==size,"retained budget includes clipping planes")
	a.clips[0]^=255
	var b:=cache.packed(null,solid)
	check(cache.builds==1 and cache.hits==1 and a.clips!=b.clips,"detached clipping bytes preserve cached data")
	var boundary:=GemBoundarySet.new()
	check(boundary.add_rounded(solid,0),"continuous region zero admitted")
	var boxes:=load("res://tests/lapidary/test_boundaries.gd")
	check(boundary.add(boxes.box(Vector3(-.4,-.4,-.4),Vector3(.4,.4,.4)),-1),"nested air region admitted")
	var packed:=cache.packed(boundary.mesh,solid)
	check(packed.error.is_empty() and packed.triangles.size()==38*64,"analytic host and triangle cavity share one hierarchy")
	var segments:=boundary.segments(Vector3(0,0,3),Vector3.FORWARD)
	check(segments.size()==2,"reference ray traverses two stone segments separated by air")
	var length:=0.0
	for segment in segments:length+=segment.end-segment.begin
	check(absf(length-1.2)<2e-5,"independent box cavity leaves 1.2 units of stone")
	var invalid:GemMesh=boxes.box(Vector3(-.4,-.4,-.4),Vector3(.4,.4,.4))
	check(not cache.packed(invalid,solid).error.is_empty(),"second region-zero host rejected")
	cache.budget_bytes=1;cache.packed(null,solid)
	check(cache.retained_bytes==0,"oversized continuous payload is not retained")
	solid.patches[0].axis[0]+=.1
	check(not solid.validation_error().is_empty() and not cache.packed(null,solid).error.is_empty(),"modified compiled patch rejected before packing")
	print("Primitive BVH: %d checks, %d failures" % [checks,failures]);quit(1 if failures else 0)
