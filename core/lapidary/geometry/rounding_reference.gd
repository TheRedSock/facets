class_name GemRoundingReference
extends RefCounted
## Tessellated comparison/volume reference, not the optical authoring backend.
## Convex spherical opening: planar faces, cylindrical edge strips, spherical
## vertex patches. Shared patch boundaries use the same indexed vertices.
## The mesh is inscribed in the ideal rounded solid; no shading-normal trick.
const MAX_TRIANGLES:=262144
static var _cache:Dictionary={}
static var _cached_triangles:=0
var mesh:=GemMesh.new()
var normals:=PackedVector3Array()
var core:=GemMesh.new()
var faces:=[]
var edges:={}
var corners:={}
var face_vertices:={}
var radius:=0.0
var step:=0.0
var max_sag:=0.0
var error:=""

static func compile(planes:PackedFloat32Array,identities:PackedInt32Array,size_mm:float,recipe:GemRounding, angular_step_deg:=6.0)->Dictionary:
	var key:=GemContentIdentity.digest([planes,identities,size_mm,recipe,angular_step_deg])
	if _cache.has(key):return _copy(_cache[key])
	var worker:=GemRoundingReference.new()
	var result:=worker._compile(planes,identities,size_mm,recipe,angular_step_deg)
	if result.has("mesh"):
		while not _cache.is_empty() and (_cache.size()>=16 or _cached_triangles+result.mesh.triangle_count()>MAX_TRIANGLES):
			var oldest:String=_cache.keys()[0]
			_cached_triangles-=_cache[oldest].mesh.triangle_count();_cache.erase(oldest)
		_cache[key]=result;_cached_triangles+=result.mesh.triangle_count()
		return _copy(result)
	return result

static func _copy(result:Dictionary)->Dictionary:
	var copy:=result.duplicate(true)
	var source:GemMesh=result.mesh
	var target:=GemMesh.new()
	target.vertices=source.vertices.duplicate();target.indices=source.indices.duplicate()
	target.facet_ids=source.facet_ids.duplicate();target.region_ids=source.region_ids.duplicate()
	copy.mesh=target
	return copy

func _compile(planes:PackedFloat32Array,identities:PackedInt32Array,size_mm:float,recipe:GemRounding, angular_step_deg:=6.0)->Dictionary:
	if recipe==null or not recipe.validate().is_empty() or not is_finite(size_mm) or size_mm<=0:return {"error":"Invalid rounding recipe or physical size"}
	if not is_finite(angular_step_deg) or angular_step_deg<1 or angular_step_deg>20:return {"error":"Reference tessellation requires 1..20 degrees"}
	if recipe.radius_mm<=0:return {"error":"Rounding requires a positive radius"}
	if planes.size()<32 or planes.size()%8!=0:return {"error":"Rounding requires complete convex planes"}
	for i in planes.size()/8:
		var n:=Vector3(planes[i*8],planes[i*8+1],planes[i*8+2])
		if not n.is_finite() or n.length_squared()<1e-12 or not is_finite(planes[i*8+3]):return {"error":"Invalid rounding support plane"}
	var original:=GemShapeCompiler.from_hull(planes,identities)
	if not original.validate().is_empty():return {"error":"Rounding requires a valid convex host"}
	radius=recipe.radius_mm/size_mm;step=deg_to_rad(angular_step_deg)
	var inset:=planes.duplicate()
	for i in planes.size()/8:
		var n:=Vector3(planes[i*8],planes[i*8+1],planes[i*8+2])
		inset[i*8+3]-=radius*n.length()
	var cells:={}
	for face in planes.size()/8:
		var polygon:=GemShapeCompiler._clip_face64(inset,face)
		var ring:=PackedInt32Array()
		for vertex in polygon:
			var p:Array=vertex.point
			var index:=GemShapeCompiler._weld(core,Vector3(p[0],p[1],p[2]),cells)
			if not ring.has(index):ring.append(index)
		if ring.size()<3:continue
		var normal:=Vector3(planes[face*8],planes[face*8+1],planes[face*8+2]).normalized()
		var id:=faces.size()
		faces.append({"ring":ring,"normal":normal,"facet":identities[face] if identities.size()==planes.size()/8 else face})
		for i in ring.size():
			var a:=ring[i];var b:=ring[(i+1)%ring.size()]
			var key:=Vector2i(mini(a,b),maxi(a,b))
			if not edges.has(key):edges[key]={"faces":[],"arcs":{}}
			edges[key].faces.append(id)
			if not corners.has(a):corners[a]=[]
			corners[a].append(id)
	if faces.size()<4:return {"error":"Rounding radius collapses the inset solid"}
	for key:Vector2i in edges:
		if edges[key].faces.size()!=2:return {"error":"Inset facet topology is unresolved at this radius"}
	# Every original facet gets a translated, still-planar inner polygon.
	for face in faces.size():
		var ring:PackedInt32Array=faces[face].ring
		var center:=Vector3.ZERO
		var indices:=PackedInt32Array()
		for vertex in ring:
			center+=core.vertices[vertex]/ring.size()
			var index:=_vertex(core.vertices[vertex]+radius*faces[face].normal,faces[face].normal)
			face_vertices[Vector2i(vertex,face)]=index;indices.append(index)
		var middle:=_vertex(center+radius*faces[face].normal,faces[face].normal)
		for i in ring.size():_triangle(middle,indices[i],indices[(i+1)%ring.size()],faces[face].facet)
	var edge_id:=-1
	for key:Vector2i in edges:
		var descriptor:Dictionary=edges[key]
		var a:int=descriptor.faces[0];var b:int=descriptor.faces[1]
		var na:Vector3=faces[a].normal;var nb:Vector3=faces[b].normal
		var count:=maxi(1,ceili(acos(clampf(na.dot(nb),-1,1))/step))
		for vertex:int in [key.x,key.y]:
			var arc:=PackedInt32Array([face_vertices[Vector2i(vertex,a)]])
			for i in range(1,count):
				var n:=na.slerp(nb,float(i)/count).normalized()
				arc.append(_vertex(core.vertices[vertex]+radius*n,n))
			arc.append(face_vertices[Vector2i(vertex,b)])
			descriptor.arcs[vertex]=arc
		var left:PackedInt32Array=descriptor.arcs[key.x];var right:PackedInt32Array=descriptor.arcs[key.y]
		for i in count:
			_triangle(left[i],right[i],right[i+1],edge_id)
			_triangle(left[i],right[i+1],left[i+1],edge_id)
		edge_id-=1
	for vertex:int in corners:
		var ring:=_corner_ring(vertex)
		if ring.is_empty():return {"error":error}
		var ncenter:=Vector3.ZERO
		for face:int in corners[vertex]:ncenter+=faces[face].normal
		ncenter=ncenter.normalized()
		var distance:=0.0
		for index in ring:distance=maxf(distance,acos(clampf(ncenter.dot(normals[index]),-1,1)))
		var layers:=maxi(1,ceili(distance/step))
		if mesh.triangle_count()+ring.size()*layers*2>MAX_TRIANGLES:return {"error":"Rounded mesh exceeds triangle budget; use a coarser angular step"}
		var previous:=PackedInt32Array([_vertex(core.vertices[vertex]+radius*ncenter,ncenter)])
		for layer in range(1,layers+1):
			var current:=ring if layer==layers else PackedInt32Array()
			if layer<layers:
				for index in ring:
					var n:=ncenter.slerp(normals[index],float(layer)/layers).normalized()
					current.append(_vertex(core.vertices[vertex]+radius*n,n))
			for i in ring.size():
				var next:=(i+1)%ring.size()
				if layer==1:_triangle(previous[0],current[i],current[next],edge_id)
				else:
					_triangle(previous[i],current[i],current[next],edge_id)
					_triangle(previous[i],current[next],previous[next],edge_id)
			previous=current
		edge_id-=1
	var errors:=mesh.validate()
	if not errors.is_empty():return {"error":"Rounded mesh rejected: "+"; ".join(errors)}
	var before:=original.signed_volume()*pow(size_mm,3)
	var after:=mesh.signed_volume()*pow(size_mm,3)
	if after<=0 or after>before*(1+1e-6) or (before-after)/before>recipe.max_removed_fraction:return {"error":"Rounding exceeds the allowed removed volume"}
	return {"error":"","mesh":mesh,"report":{"model":"convex_spherical_opening","volume_reference":"inscribed_triangle_mesh","before_other_defects":true,"radius_mm":recipe.radius_mm,"original_mm3":before,"retained_mm3":after,"removed_mm3":before-after,"triangles":mesh.triangle_count(),"angular_step_deg":angular_step_deg,"chord_sag_bound_mm":max_sag*size_mm}}

func _corner_ring(vertex:int)->PackedInt32Array:
	var adjacent:={}
	for key:Vector2i in edges:
		if key.x!=vertex and key.y!=vertex:continue
		var pair:Array=edges[key].faces
		for i in 2:
			if not adjacent.has(pair[i]):adjacent[pair[i]]=[]
			adjacent[pair[i]].append({"other":pair[1-i],"edge":key})
	for face:int in adjacent:
		if adjacent[face].size()!=2:error="Inset corner normal fan is not a cycle";return PackedInt32Array()
	var start:int=corners[vertex][0];var current:=start;var previous:=-1
	var ring:=PackedInt32Array()
	for iteration in adjacent.size():
		var choices:Array=adjacent[current]
		var choice:Dictionary=choices[0] if choices[0].other!=previous else choices[1]
		var descriptor:Dictionary=edges[choice.edge]
		var arc:PackedInt32Array=descriptor.arcs[vertex].duplicate()
		if descriptor.faces[0]!=current:arc.reverse()
		for i in arc.size()-1:ring.append(arc[i])
		previous=current;current=choice.other
		if current==start:
			if iteration!=adjacent.size()-1:error="Inset corner has disconnected fans";return PackedInt32Array()
			return ring
	error="Inset corner fan did not close";return PackedInt32Array()

func _vertex(position:Vector3,normal:Vector3)->int:
	var index:=mesh.vertices.size();mesh.vertices.append(position);normals.append(normal);return index

func _triangle(a:int,b:int,c:int,facet:int)->void:
	var n:Vector3=normals[a]+normals[b]+normals[c]
	if (mesh.vertices[b]-mesh.vertices[a]).cross(mesh.vertices[c]-mesh.vertices[a]).dot(n)<0:
		var temp:=b;b=c;c=temp
	mesh.add_triangle(a,b,c,facet)
	max_sag=maxf(max_sag,radius*(1-minf(normals[a].dot(normals[b]),minf(normals[b].dot(normals[c]),normals[c].dot(normals[a])))))
