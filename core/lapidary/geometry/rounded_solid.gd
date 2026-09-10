class_name GemRoundedSolid
extends RefCounted
## Continuous convex spherical opening: (P eroded by r) + radius-r ball.
## Authored planes enter as float32; retained support-triple vertices and curve
## parameters use float64. The arbitrary clipping seed frame is not retained.
## Geometry reference only until GPU packing/intersection admission is supplied.
const V := preload("res://core/lapidary/geometry/geometry64.gd")
var core: GemConvexCore
var patches: Array[GemAnalyticPatch] = []
var radius := 0.0
var tolerance := 0.0
var report: Dictionary = {}
var error := ""

static func compile(planes: PackedFloat32Array, identities: PackedInt32Array, size_mm: float, recipe: GemRounding) -> GemRoundedSolid:
	var solid:=GemRoundedSolid.new()
	solid._compile(planes,identities,size_mm,recipe)
	return solid

func _compile(planes: PackedFloat32Array, identities: PackedInt32Array, size_mm: float, recipe: GemRounding) -> void:
	if recipe==null or not recipe.validate().is_empty() or recipe.radius_mm<=0 or not is_finite(size_mm) or size_mm<=0:
		error="Invalid continuous rounding radius or physical size";return
	if planes.size()<32 or planes.size()%8!=0 or planes.size()>4096:
		error="Continuous rounding needs 4..512 complete support planes";return
	var normalized:=PackedFloat64Array();normalized.resize(planes.size())
	for i in planes.size()/8:
		var n:=V.vec(planes[i*8],planes[i*8+1],planes[i*8+2])
		var length:=sqrt(V.dot(n,n))
		if not V.finite(n) or length<1e-20 or not is_finite(planes[i*8+3]): error="Invalid support plane";return
		for k in 4: normalized[i*8+k]=planes[i*8+k]/length
	var original:=GemConvexCore.build(normalized,identities)
	if not original.error.is_empty(): error="Original host: "+original.error;return
	radius=recipe.radius_mm/size_mm
	var inset:=normalized.duplicate()
	for i in planes.size()/8: inset[i*8+3]-=radius
	core=GemConvexCore.build(inset,identities)
	if not core.error.is_empty(): error=core.error;return
	tolerance=maxf(2e-14*maxf(1,pow(original.volume,1.0/3.0)),core.construction_residual*4)
	if radius<tolerance*1024: error="Rounding radius is below the continuous construction precision gate";return
	# Convex Steiner formula: V(K+rB)=V(K)+r A(K)+r^2 H(K)+4pi r^3/3.
	# H(K)=sum_edges exterior_angle*edge_length/2. No tessellation estimate.
	var retained:=core.volume+radius*core.area+radius*radius*core.mean_curvature+4*PI*pow(radius,3)/3
	var removed:=original.volume-retained
	if retained<=0 or removed < -original.volume*1e-12 or removed/original.volume>recipe.max_removed_fraction:
		error="Continuous rounding exceeds the removed-volume limit";return
	_build_patches()
	report={"model":"convex_spherical_opening","volume_reference":"convex_Steiner_formula","radius_mm":recipe.radius_mm,
		"original_mm3":original.volume*pow(size_mm,3),"retained_mm3":retained*pow(size_mm,3),"removed_mm3":maxf(0,removed)*pow(size_mm,3),
		"volume_difference_resolved":absf(removed)>original.volume*1e-12,"patches":patches.size(),"core_vertices":core.vertices.size(),
		"core_edges":core.edges.size(),"core_faces":core.faces.size(),"construction_residual_mm":core.construction_residual*size_mm,
		"clip_tolerance_mm":tolerance*size_mm}

func _build_patches() -> void:
	for face:Dictionary in core.faces:
		var patch:=GemAnalyticPatch.new()
		patch.kind=GemAnalyticPatch.Kind.PLANE;patch.axis=face.normal;patch.offset=face.offset+radius;patch.facet=face.facet
		var ring:PackedInt32Array=face.ring
		var moved: Array[PackedFloat64Array]=[]
		for i in ring.size():
			var a:=core.vertices[ring[i]];var b:=core.vertices[ring[(i+1)%ring.size()]]
			var p:=V.add(a,V.scale(face.normal,radius));moved.append(p)
			var outward:=V.unit(V.cross(V.subtract(b,a),face.normal))
			patch.clips.append(V.plane(outward,p))
		patch.center=moved[0]
		_bounds(patch,moved,0)
		patches.append(patch)
	var facet:=-1
	for edge:Dictionary in core.edges:
		var a:=core.vertices[edge.a];var b:=core.vertices[edge.b]
		var na:PackedFloat64Array=core.faces[edge.faces[0]].normal
		var nb:PackedFloat64Array=core.faces[edge.faces[1]].normal
		var cosine:=V.dot(na,nb)
		var patch:=GemAnalyticPatch.new()
		patch.kind=GemAnalyticPatch.Kind.CYLINDER;patch.center=a;patch.axis=V.unit(V.subtract(b,a));patch.radius=radius;patch.facet=facet
		patch.end=b
		patch.clips.append(V.plane(V.scale(patch.axis,-1),a));patch.clips.append(V.plane(patch.axis,b))
		patch.clips.append(V.plane(V.unit(V.subtract(V.scale(na,cosine),nb)),a))
		patch.clips.append(V.plane(V.unit(V.subtract(V.scale(nb,cosine),na)),a))
		_bounds(patch,[a,b],radius)
		patches.append(patch);facet-=1
	for vertex in core.vertices.size():
		var center:=core.vertices[vertex]
		var patch:=GemAnalyticPatch.new()
		patch.kind=GemAnalyticPatch.Kind.SPHERE;patch.center=center;patch.radius=radius;patch.facet=facet
		for neighbor in core.neighbors[vertex]:
			patch.clips.append(V.plane(V.unit(V.subtract(core.vertices[neighbor],center)),center))
		_bounds(patch,[center],radius)
		patches.append(patch);facet-=1

static func _bounds(patch: GemAnalyticPatch, points: Array[PackedFloat64Array], padding: float) -> void:
	patch.lower=V.vec(INF,INF,INF);patch.upper=V.vec(-INF,-INF,-INF)
	for p in points:
		for axis in 3:
			patch.lower[axis]=minf(patch.lower[axis],p[axis]-padding)
			patch.upper[axis]=maxf(patch.upper[axis],p[axis]+padding)

func intersect(origin: PackedFloat64Array, direction: PackedFloat64Array, min_t:=0.0, max_t:=INF) -> Dictionary:
	if not error.is_empty() or not V.finite(origin) or not V.finite(direction) or V.dot(direction,direction)<1e-30 or not is_finite(min_t) or min_t<0 or is_nan(max_t) or max_t<=min_t: return {}
	var hit:Dictionary={}
	var closest:=max_t
	for patch in patches:
		var candidate:=patch.intersect(origin,direction,min_t,closest,tolerance)
		if not candidate.is_empty(): closest=candidate.t;hit=candidate
	return hit
