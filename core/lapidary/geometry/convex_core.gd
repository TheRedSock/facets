class_name GemConvexCore
extends RefCounted
## Float64 indexed boundary of a bounded convex half-space intersection.
## This retains original plane identities; it is not a triangle render mesh.
const V := preload("res://core/lapidary/geometry/geometry64.gd")
var vertices: Array[PackedFloat64Array] = []
var faces: Array[Dictionary] = []
var edges: Array[Dictionary] = []
var neighbors: Array[PackedInt32Array] = []
var volume := 0.0
var area := 0.0
var mean_curvature := 0.0
var construction_residual := 0.0
var tolerance := 1e-12
var error := ""

static func build(planes: PackedFloat64Array, identities: PackedInt32Array) -> GemConvexCore:
	var core := GemConvexCore.new()
	core._build(planes,identities)
	return core

func _build(planes: PackedFloat64Array, identities: PackedInt32Array) -> void:
	if planes.size()<32 or planes.size()%8!=0 or planes.size()>512*8 or (not identities.is_empty() and identities.size()!=planes.size()/8):
		error="Invalid convex plane/identity count"; return
	var scale_bound := 1.0
	for i in planes.size()/8:
		for k in 4:
			if not is_finite(planes[8*i+k]): error="Nonfinite convex plane"; return
		var n:=V.vec(planes[8*i],planes[8*i+1],planes[8*i+2])
		if absf(V.dot(n,n)-1)>1e-10: error="Convex construction requires unit plane normals"; return
		scale_bound=maxf(scale_bound,absf(planes[8*i+3]))
	tolerance=scale_bound*1e-12
	var edge_map: Dictionary = {}
	for face in planes.size()/8:
		var polygon := GemShapeCompiler._clip_face64(planes,face)
		var ring := PackedInt32Array()
		for corner:Dictionary in polygon:
			if corner.supports.x<0 or corner.supports.y<0:
				error="Convex clipping did not resolve a bounded face"; return
			var point:=PackedFloat64Array(corner.point)
			var index:=_weld(point)
			if not ring.has(index): ring.append(index)
		if ring.size()<3: continue
		var normal:=V.vec(planes[face*8],planes[face*8+1],planes[face*8+2])
		var id:=faces.size()
		faces.append({"ring":ring,"normal":normal,"offset":planes[face*8+3],"facet":identities[face] if not identities.is_empty() else face})
		for i in ring.size():
			var a:=ring[i];var b:=ring[(i+1)%ring.size()]
			var key:=Vector2i(mini(a,b),maxi(a,b))
			if not edge_map.has(key): edge_map[key]={"a":key.x,"b":key.y,"faces":PackedInt32Array(),"directions":PackedInt32Array()}
			edge_map[key].faces.append(id);edge_map[key].directions.append(1 if a<b else -1)
	if vertices.size()<4 or faces.size()<4: error="Inset convex solid is empty or collapsed"; return
	for vertex in vertices.size(): neighbors.append(PackedInt32Array())
	for key:Vector2i in edge_map:
		var edge:Dictionary=edge_map[key]
		if edge.faces.size()!=2 or edge.directions[0]+edge.directions[1]!=0:
			error="Convex core has unresolved edge adjacency"; return
		neighbors[edge.a].append(edge.b);neighbors[edge.b].append(edge.a)
		edges.append(edge)
		var length:=sqrt(V.dot(V.subtract(vertices[edge.b],vertices[edge.a]),V.subtract(vertices[edge.b],vertices[edge.a])))
		var angle:=acos(clampf(V.dot(faces[edge.faces[0]].normal,faces[edge.faces[1]].normal),-1,1))
		mean_curvature+=.5*length*angle
	if vertices.size()-edges.size()+faces.size()!=2: error="Convex core Euler characteristic is not spherical"; return
	var origin:=vertices[0]
	var correction:=0.0
	for face:Dictionary in faces:
		var ring:PackedInt32Array=face.ring
		for index in ring:
			construction_residual=maxf(construction_residual,absf(V.dot(face.normal,vertices[index])-face.offset))
		for i in range(1,ring.size()-1):
			var a:=vertices[ring[0]];var b:=vertices[ring[i]];var c:=vertices[ring[i+1]]
			var cross:=V.cross(V.subtract(b,a),V.subtract(c,a))
			var signed_area:=.5*V.dot(cross,face.normal)
			if signed_area<=0: error="Convex face has invalid winding or zero area"; return
			area+=signed_area
			var term:=V.dot(V.subtract(a,origin),V.cross(V.subtract(b,origin),V.subtract(c,origin)))/6.0-correction
			var total:=volume+term;correction=(total-volume)-term;volume=total
	if volume<=0 or construction_residual>tolerance*64: error="Convex core construction precision is insufficient"; return
	# Every retained vertex must satisfy every input support, including inactive faces.
	for vertex in vertices:
		for i in planes.size()/8:
			if planes[i*8]*vertex[0]+planes[i*8+1]*vertex[1]+planes[i*8+2]*vertex[2]-planes[i*8+3]>tolerance*64:
				error="Convex vertex lies outside a support plane"; return

func _weld(point: PackedFloat64Array) -> int:
	for i in vertices.size():
		var delta:=V.subtract(point,vertices[i])
		if V.dot(delta,delta)<=tolerance*tolerance: return i
	vertices.append(point)
	return vertices.size()-1

## Independent closest-feature query, useful for validating a rounded surface
## against distance(point, core)==radius. Interior points have distance zero.
func closest_point(point: PackedFloat64Array) -> Dictionary:
	if not error.is_empty() or not V.finite(point): return {}
	var interior:=true
	for face:Dictionary in faces:
		if V.dot(face.normal,point)>face.offset: interior=false;break
	if interior:return {"point":point.duplicate(),"distance":0.0}
	var best:=vertices[0]
	var squared:=INF
	for vertex in vertices:
		var difference:=V.subtract(point,vertex)
		var candidate:=V.dot(difference,difference)
		if candidate<squared:squared=candidate;best=vertex
	for edge:Dictionary in edges:
		var a:=vertices[edge.a];var delta:=V.subtract(vertices[edge.b],a)
		var t:=clampf(V.dot(V.subtract(point,a),delta)/V.dot(delta,delta),0,1)
		var q:=V.add(a,V.scale(delta,t));var difference:=V.subtract(point,q)
		var candidate:=V.dot(difference,difference)
		if candidate<squared:squared=candidate;best=q
	for face:Dictionary in faces:
		var distance:float=V.dot(face.normal,point)-face.offset
		if distance<0 or distance*distance>=squared:continue
		var q:=V.subtract(point,V.scale(face.normal,distance))
		var valid:=true
		var ring:PackedInt32Array=face.ring
		for i in ring.size():
			var a:=vertices[ring[i]];var b:=vertices[ring[(i+1)%ring.size()]]
			var outward:=V.unit(V.cross(V.subtract(b,a),face.normal))
			if V.dot(outward,V.subtract(q,a))>tolerance: valid=false;break
		if valid:squared=distance*distance;best=q
	return {"point":best.duplicate(),"distance":sqrt(squared)}
