class_name GemPatchBounds
extends RefCounted
## Extrema of the encoded curved patch, including its clipping tolerance.
## Sphere extrema occur at an unconstrained pole, a clipping circle stationary
## point, or the intersection of two clipping circles. Cylinder extrema use
## the corresponding circle candidates after conservatively eliminating height.
## An empty result requests the existing enclosing quadric bound when a domain
## is numerically ill-conditioned. This never substitutes render geometry.
const V := preload("res://core/lapidary/geometry/geometry64.gd")
const FEASIBILITY_EPS := 5e-10

static func encoded(records: PackedByteArray, index: int, clip_bytes: PackedByteArray, tolerance: float) -> Dictionary:
	var base := index*64
	var metadata := records.decode_s32(base+52)
	var kind := metadata&255
	if kind != 2 and kind != 3: return {}
	var center := V.vec(records.decode_float(base),records.decode_float(base+4),records.decode_float(base+8))
	var radius := records.decode_float(base+12)
	if radius <= 0: return {}
	var offset := records.decode_s32(base+56)*16
	var clips: Array[PackedFloat64Array] = []
	for i in metadata>>8:
		clips.append(PackedFloat64Array([clip_bytes.decode_float(offset+i*16),clip_bytes.decode_float(offset+i*16+4),clip_bytes.decode_float(offset+i*16+8),clip_bytes.decode_float(offset+i*16+12)+tolerance]))
	var normal_bounds: Dictionary
	var low := center.duplicate()
	var high := center.duplicate()
	if kind == 3:
		for i in clips.size():
			var length := sqrt(V.dot(clips[i],clips[i]))
			if length <= 0: return {}
			for k in 3: clips[i][k]/=length
			clips[i][3]/=radius*length
		normal_bounds = sphere(clips)
	else:
		if clips.size() != 4: return {}
		var axis := V.unit(V.vec(records.decode_float(base+16),records.decode_float(base+20),records.decode_float(base+24)))
		var lower_projection := V.dot(clips[0],axis)
		var upper_projection := V.dot(clips[1],axis)
		if lower_projection >= -1e-10 or upper_projection <= 1e-10: return {}
		var first := clips[0][3]/lower_projection
		var last := clips[1][3]/upper_projection
		if first > last: return {}
		var radial: Array[PackedFloat64Array] = []
		for i in range(2,4):
			var projection := V.dot(clips[i],axis)
			# Every admitted height obeys this relaxed radial inequality, even
			# if the encoded clipping normal is not exactly perpendicular to axis.
			var limit := (clips[i][3]-minf(projection*first,projection*last))/radius
			radial.append(PackedFloat64Array([clips[i][0],clips[i][1],clips[i][2],limit]))
		normal_bounds = circle(axis,radial)
		for k in 3:
			low[k] += minf(axis[k]*first,axis[k]*last)
			high[k] += maxf(axis[k]*first,axis[k]*last)
	if normal_bounds.is_empty(): return {}
	for k in 3:
		low[k] += radius*normal_bounds.min[k]
		high[k] += radius*normal_bounds.max[k]
	return {"min":low,"max":high}

static func circle(axis: PackedFloat64Array, clips: Array[PackedFloat64Array]) -> Dictionary:
	var tangent := V.unit(V.cross(axis,V.vec(0,0,1) if absf(axis[2])<.8 else V.vec(1,0,0)))
	var bitangent := V.cross(axis,tangent)
	var angles: Array[float] = []
	for k in 3:
		angles.append(atan2(bitangent[k],tangent[k]))
		angles.append(angles[-1]+PI)
	for clip in clips:
		var a := V.dot(clip,tangent)
		var b := V.dot(clip,bitangent)
		var length := sqrt(a*a+b*b)
		if length < 1e-15:
			if clip[3] < 0: return {}
			continue
		var ratio := clip[3]/length
		if ratio < -1: return {}
		if ratio > 1: continue
		var middle := atan2(b,a)
		var half_angle := acos(clampf(ratio,-1,1))
		angles.append(middle-half_angle);angles.append(middle+half_angle)
	var candidates: Array[PackedFloat64Array] = []
	for angle in angles: candidates.append(V.add(V.scale(tangent,cos(angle)),V.scale(bitangent,sin(angle))))
	return _extrema(candidates,clips)

## Clip normals are unit length; the offsets need not be zero. Nonzero offsets
## matter at small physical radii, where the rendering tolerance widens a cone.
static func sphere(clips: Array[PackedFloat64Array]) -> Dictionary:
	var candidates: Array[PackedFloat64Array] = []
	for k in 3:
		var e := V.vec(0,0,0);e[k]=1
		candidates.append(e);candidates.append(V.scale(e,-1))
	for i in clips.size():
		var n := V.vec(clips[i][0],clips[i][1],clips[i][2])
		var h := clips[i][3]
		if h < -1: return {}
		if h > 1: continue
		var center := V.scale(n,h)
		var radius := sqrt(maxf(0,1-h*h))
		for k in 3:
			var e := V.vec(0,0,0);e[k]=1
			var direction := V.subtract(e,V.scale(n,n[k]))
			if V.dot(direction,direction)<1e-24:
				direction=V.cross(n,V.vec(0,0,1) if absf(n[2])<.8 else V.vec(1,0,0))
			direction=V.scale(V.unit(direction),radius)
			candidates.append(V.add(center,direction));candidates.append(V.subtract(center,direction))
		for j in range(i+1,clips.size()):
			var m := V.vec(clips[j][0],clips[j][1],clips[j][2])
			var cross := V.cross(n,m)
			var squared := V.dot(cross,cross)
			if squared == 0: continue # Parallel boundaries are already covered by each circle.
			if squared < 1e-18: return {} # Do not trust an unstable two-plane intersection.
			var point := V.scale(V.add(V.scale(V.cross(m,cross),h),V.scale(V.cross(cross,n),clips[j][3])),1.0/squared)
			if absf(V.dot(point,n)-h)>FEASIBILITY_EPS or absf(V.dot(point,m)-clips[j][3])>FEASIBILITY_EPS: return {}
			var remainder := 1-V.dot(point,point)
			if remainder < -FEASIBILITY_EPS: continue
			var displacement := V.scale(cross,sqrt(maxf(0,remainder)/squared))
			candidates.append(V.add(point,displacement));candidates.append(V.subtract(point,displacement))
	return _extrema(candidates,clips)

static func _extrema(candidates: Array[PackedFloat64Array], clips: Array[PackedFloat64Array]) -> Dictionary:
	var low := V.vec(INF,INF,INF)
	var high := V.vec(-INF,-INF,-INF)
	var count := 0
	for p in candidates:
		var valid := true
		for clip in clips:
			if V.dot(clip,p)>clip[3]+FEASIBILITY_EPS: valid=false;break
		if not valid: continue
		count+=1
		for k in 3:
			low[k]=minf(low[k],p[k]);high[k]=maxf(high[k],p[k])
	return {"min":low,"max":high} if count>0 else {}
