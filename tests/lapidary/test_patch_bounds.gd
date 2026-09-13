extends SceneTree
const V := preload("res://core/lapidary/geometry/geometry64.gd")
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: "+label)

func _initialize() -> void:
	for height in [-.7,0.0,.5,.9999999999]:
		var clips: Array[PackedFloat64Array] = [PackedFloat64Array([0,0,-1,-height])]
		var bounds:=GemPatchBounds.sphere(clips)
		var extent:=1.0 if height<=0 else sqrt(1-height*height)
		check(not bounds.is_empty() and absf(bounds.min[2]-height)<1e-12 and absf(bounds.max[2]-1)<1e-12,"spherical cap exact axial extent")
		check(not bounds.is_empty() and absf(bounds.min[0]+extent)<1e-12 and absf(bounds.max[1]-extent)<1e-12,"spherical cap exact radial extent")
	var octant: Array[PackedFloat64Array] = [PackedFloat64Array([-1,0,0,0]),PackedFloat64Array([0,-1,0,0]),PackedFloat64Array([0,0,-1,0])]
	var octant_bounds:=GemPatchBounds.sphere(octant)
	check(V.dot(octant_bounds.min,octant_bounds.min)<1e-24 and V.dot(V.subtract(octant_bounds.max,V.vec(1,1,1)),V.subtract(octant_bounds.max,V.vec(1,1,1)))<1e-24,"spherical octant includes all exact extrema")
	var band: Array[PackedFloat64Array] = [PackedFloat64Array([0,0,1,.4]),PackedFloat64Array([0,0,-1,.2])]
	var band_bounds:=GemPatchBounds.sphere(band)
	check(not band_bounds.is_empty() and absf(band_bounds.min[2]+.2)<1e-12 and absf(band_bounds.max[2]-.4)<1e-12 and absf(band_bounds.max[0]-1)<1e-12,"opposite parallel circles retain the spherical band")
	var uncertain: Array[PackedFloat64Array] = [PackedFloat64Array([1,0,0,0]),PackedFloat64Array([1,1e-12,0,0])]
	check(GemPatchBounds.sphere(uncertain).is_empty(),"nearly parallel clipping asks for enclosing-quadric bounds")
	# Independent feasible-direction samples. Rotations use normalized binary64
	# frames and offsets span tiny tolerance expansions and finite spherical caps.
	for fixture in 12:
		var axis:=V.unit(V.vec(.2+fixture*.13,.7-fixture*.031,.9))
		var tangent:=V.unit(V.cross(axis,V.vec(0,0,1)))
		var across:=V.cross(axis,tangent)
		var clips: Array[PackedFloat64Array] = []
		for direction in [axis,tangent,across]:
			clips.append(PackedFloat64Array([-direction[0],-direction[1],-direction[2],.001*(fixture%3)]))
		var bounds:=GemPatchBounds.sphere(clips)
		check(not bounds.is_empty(),"rotated normal domain bounded")
		if bounds.is_empty():continue
		var contained:=true;var accepted:=0
		for sample in 4096:
			var z:=1-2*(sample+.5)/4096.0
			var phi:=sample*2.399963229728653
			var p:=V.vec(sqrt(1-z*z)*cos(phi),sqrt(1-z*z)*sin(phi),z)
			var valid:=true
			for clip in clips:
				if V.dot(clip,p)>clip[3]:valid=false;break
			if not valid:continue
			accepted+=1
			for k in 3:contained=contained and p[k]>=bounds.min[k]-1e-12 and p[k]<=bounds.max[k]+1e-12
		check(accepted>300 and contained,"independent sphere samples stay inside rotated bounds")
		var radial_clips: Array[PackedFloat64Array] = [clips[1],clips[2]]
		var circle:=GemPatchBounds.circle(axis,radial_clips)
		contained=not circle.is_empty();accepted=0
		for sample in 4096:
			var angle:=TAU*(sample+.123)/4096.0
			var p:=V.add(V.scale(tangent,cos(angle)),V.scale(across,sin(angle)))
			if V.dot(radial_clips[0],p)>radial_clips[0][3] or V.dot(radial_clips[1],p)>radial_clips[1][3]:continue
			accepted+=1
			for k in 3:contained=contained and p[k]>=circle.min[k]-1e-12 and p[k]<=circle.max[k]+1e-12
		check(accepted>900 and contained,"independent circle samples stay inside rotated bounds")
	print("Patch bounds: %d checks, %d failures"%[checks,failures]);print("CHECK_COMPLETE: test_patch_bounds"); quit(1 if failures else 0)
