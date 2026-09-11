class_name GemPrimitiveBvh
extends RefCounted
## A balanced hierarchy over continuous patches and closed defect triangles.
## Leaves use the shared 64-byte boundary record; clipping planes stay separate.
## Bounds are rounded outward on the binary32 wire. Clip padding is a tested
## numerical policy, not an interval-arithmetic certificate.
const V := preload("res://core/lapidary/geometry/geometry64.gd")
const CLIP_TOLERANCE := 1e-6
var nodes: Array[Dictionary] = []
var order := PackedInt32Array()
var bounds: Array[Dictionary] = []

static func pack(solid: GemRoundedSolid, mesh: GemMesh = null) -> Dictionary:
	if solid == null or not solid.validation_error().is_empty() or solid.patches.is_empty():
		return {"error": "Missing or invalid continuous host"}
	var encoded := GemAnalyticPacking.pack(solid)
	var records: PackedByteArray = encoded.primitives
	var tree := GemPrimitiveBvh.new()
	for index in solid.patches.size():
		var patch := solid.patches[index]
		var tight := GemPatchBounds.encoded(records,index,encoded.clips,CLIP_TOLERANCE)
		var scale := 1.0
		for axis in 3:
			scale = maxf(scale, maxf(absf(patch.lower[axis]), absf(patch.upper[axis])))
		var padding := CLIP_TOLERANCE * 16 * scale
		var low: PackedFloat64Array = tight.get("min",patch.lower)
		var high: PackedFloat64Array = tight.get("max",patch.upper)
		tree.bounds.append({"min": V.subtract(low,V.vec(padding,padding,padding)), "max": V.add(high,V.vec(padding,padding,padding))})
	if mesh != null and mesh.triangle_count() > 0:
		var errors := mesh.validate()
		if not errors.is_empty(): return {"error": "Invalid combined defect mesh: " + "; ".join(errors)}
		for region in mesh.region_ids:
			if region <= 0 or region >= GemBoundarySet.MAX_REGIONS: return {"error":"Continuous-host triangles must belong to a non-host region"}
		var triangles := GemBvh.build(mesh).pack_triangles()
		for index in triangles.size()/64:
			var low := V.vec(INF,INF,INF)
			var high := V.vec(-INF,-INF,-INF)
			for corner in 3:
				for axis in 3:
					var value := triangles.decode_float(index*64+corner*16+axis*4)
					low[axis] = minf(low[axis],value)
					high[axis] = maxf(high[axis],value)
			tree.bounds.append({"min":low,"max":high})
		records.append_array(triangles)
	var indices: Array[int] = []
	for index in tree.bounds.size(): indices.append(index)
	tree._build(indices)
	var packed := PackedByteArray()
	for index in tree.order: packed.append_array(records.slice(index*64,(index+1)*64))
	return {"error":"", "nodes":tree._pack_nodes(), "triangles":packed, "clips":encoded.clips}

func _build(indices: Array[int]) -> int:
	var low := V.vec(INF,INF,INF)
	var high := V.vec(-INF,-INF,-INF)
	var centroid_low := low.duplicate()
	var centroid_high := high.duplicate()
	for index in indices:
		for axis in 3:
			low[axis] = minf(low[axis],bounds[index].min[axis])
			high[axis] = maxf(high[axis],bounds[index].max[axis])
			var center: float = (bounds[index].min[axis]+bounds[index].max[axis])*.5
			centroid_low[axis] = minf(centroid_low[axis],center)
			centroid_high[axis] = maxf(centroid_high[axis],center)
	var node := nodes.size()
	nodes.append({"min":low,"max":high,"left":-1,"right":-1,"first":0,"count":0})
	if indices.size() <= 4:
		nodes[node].first = order.size()
		nodes[node].count = indices.size()
		order.append_array(PackedInt32Array(indices))
	else:
		var axis := 0
		for k in range(1,3):
			if centroid_high[k]-centroid_low[k] > centroid_high[axis]-centroid_low[axis]: axis=k
		indices.sort_custom(func(a:int,b:int)->bool:
			var ca:float=bounds[a].min[axis]+bounds[a].max[axis]
			var cb:float=bounds[b].min[axis]+bounds[b].max[axis]
			return ca<cb if ca!=cb else a<b)
		var middle := indices.size()/2
		nodes[node].left = _build(indices.slice(0,middle))
		nodes[node].right = _build(indices.slice(middle))
	return node

func _pack_nodes() -> PackedByteArray:
	var output := StreamPeerBuffer.new()
	for node in nodes:
		for key in ["min","max"]:
			for axis in 3: output.put_float(outward_float(node[key][axis],key=="max"))
			output.put_float(0)
		for key in ["left","right","first","count"]: output.put_32(node[key])
	return output.data_array

static func outward_float(value: float, upper: bool) -> float:
	var bytes := PackedByteArray(); bytes.resize(4); bytes.encode_float(0,value)
	var rounded := bytes.decode_float(0)
	if (upper and rounded < value) or (not upper and rounded > value):
		if rounded == 0:
			bytes.encode_u32(0,1 if upper else 0x80000001)
		else:
			var bits := bytes.decode_u32(0)
			bytes.encode_u32(0,bits+(1 if (upper == (rounded > 0)) else -1))
	return bytes.decode_float(0)
