class_name GemCleavageCompiler
extends RefCounted
## A finite air cutter realizes one half-space removal on any closed host mesh.
## Analytic round/oval hosts use their exact support function; only their volume
## report uses the explicitly identified tessellated reference surface.
static func realize(geometry: Dictionary, shape: GemShape, size_mm: float, recipe: GemCleavageRecipe, crystal_to_stone := Quaternion.IDENTITY) -> Dictionary:
	if not is_finite(size_mm) or size_mm <= 0 or not crystal_to_stone.is_finite() or absf(crystal_to_stone.length_squared()-1.0)>1e-5:
		return {"error":"Cleavage requires a positive physical scale and unit crystal frame"}
	var errors := recipe.validate()
	if not errors.is_empty():
		return {"error":"; ".join(errors)}
	if recipe.depth_mm == 0.0:
		return {"error":"", "report":{"host_cap_mm3":0.0,"host_cap_fraction":0.0}}
	var mesh: GemMesh = geometry.get("mesh", null)
	var analytic: bool = geometry.has("analytic_shape")
	var continuous: GemRoundedSolid = geometry.get("rounded_solid",null)
	if continuous != null:
		var reference := continuous.reference_mesh()
		if not reference.error.is_empty():return {"error":"Cleavage volume reference: "+reference.error}
		mesh = reference.mesh
	if mesh == null:
		mesh = GemShapeCompiler.compile(shape) if analytic else GemShapeCompiler.from_hull(geometry.planes, geometry.get("facet_ids",PackedInt32Array()))
	if not mesh.validate().is_empty():
		return {"error":"Cleavage host: %s" % mesh.validate()}
	var index := mini(recipe.normals.size()-1, int(GemDefectCompiler.sample(recipe.seed,17)*recipe.normals.size()))
	var n := (crystal_to_stone * recipe.normals[index]).normalized()
	var support := -INF
	var radius := 0.0
	for vertex in mesh.vertices:
		support = maxf(support, _dot(n,vertex))
		radius = maxf(radius, vertex.length())
	if analytic:
		var q: Vector4 = geometry.analytic_shape
		var radial := sqrt(pow(float(n.x)*q.x,2)+pow(float(n.y)*q.y,2))
		var dome := sqrt(radial*radial+pow(float(n.z)*q.z,2)) if n.z >= 0 else radial
		support = maxf(dome,radial+float(n.z)*q.w)
	if continuous != null:
		support = continuous.support(n)
		for patch in continuous.patches:
			var squared:=0.0
			for k in 3:squared+=pow(maxf(absf(patch.lower[k]),absf(patch.upper[k])),2)
			radius=maxf(radius,sqrt(squared))
	var d := support-recipe.depth_mm/size_mm
	var reference_volume := mesh.signed_volume()
	var reference_retained := retained_volume(mesh,n,d)
	var removed := reference_volume-reference_retained
	var volume := continuous.volume_units() if continuous != null else reference_volume
	var retained := volume-removed
	var discretization_gap := maxf(0,volume-reference_volume)
	if not is_finite(retained) or volume <= 0 or removed <= 0 or retained <= 0:
		return {"error":"Cleavage must remove a positive cap and retain a solid host"}
	var fraction := removed/volume
	if (removed+discretization_gap)/volume > recipe.max_removed_fraction:
		return {"error":"Cleavage removal estimate plus discretization allowance %.6f exceeds limit %.6f" % [(removed+discretization_gap)/volume,recipe.max_removed_fraction]}
	var along := n.cross(Vector3.RIGHT if absf(n.x)<0.8 else Vector3.UP).normalized()
	var across := n.cross(along).normalized()
	# The first local-z face is the cleavage plane; every other cutter face lies
	# outside the host's bounding sphere. This removes material, not a lens/bubble.
	var extent := radius+absf(d)+0.05
	var defect := GemDefect.new()
	defect.kind = "cleavage"
	defect.center_mm = n * ((d+extent)*size_mm)
	defect.orientation = Basis(along,across,n).get_rotation_quaternion().normalized()
	defect.half_extent_mm = Vector3(extent,extent,extent)*size_mm
	defect.finish = recipe.finish
	defect.seed = recipe.seed
	defect.source_note = recipe.source_note
	return {"error":"", "defect":defect,"report":{"normal_index":index,"normal_stone":[n.x,n.y,n.z],"plane_offset_mm":d*size_mm,
		"requested_depth_mm":recipe.depth_mm,"original_mm3":volume*pow(size_mm,3),"retained_mm3":retained*pow(size_mm,3),
		"host_cap_mm3":removed*pow(size_mm,3),"host_cap_fraction":fraction,"volume_reference":"tessellated_continuous_host" if continuous != null else ("tessellated_analytic_host" if analytic else "encoded_host_mesh"),
		"volume_discretization_gap_mm3":discretization_gap*pow(size_mm,3),"limit_includes_discretization_gap":continuous!=null,
		"volume_excludes_other_defects":true,
		"reference_triangles":mesh.triangle_count(),"source_note":recipe.source_note}}

static func _dot(a: Vector3,b: Vector3) -> float:
	return float(a.x)*b.x+float(a.y)*b.y+float(a.z)*b.z

## Divergence theorem with the origin on the cutting plane: the missing cap
## contributes zero signed volume. Clip each original triangle, retaining holes
## and concavity without constructing or triangulating the cap. Scalar binary64
## coordinates avoid rounding newly constructed intersections to Vector3/float32.
static func retained_volume(mesh: GemMesh, n: Vector3, d: float) -> float:
	var origin := [0.0,0.0,0.0]
	var axis := n.abs().max_axis_index()
	origin[axis] = d/float(n[axis])
	var sum := 0.0
	var correction := 0.0
	for triangle in mesh.triangle_count():
		var input := []
		for k in 3:
			var p := mesh.vertices[mesh.indices[triangle*3+k]]
			input.append([float(p.x),float(p.y),float(p.z)])
		var clipped := []
		for k in 3:
			var a: Array = input[k]
			var b: Array = input[(k+1)%3]
			var da: float = n.x*a[0]+n.y*a[1]+n.z*a[2]-d
			var db: float = n.x*b[0]+n.y*b[1]+n.z*b[2]-d
			if da <= 0:
				clipped.append(a)
			if (da < 0 and db > 0) or (da > 0 and db < 0):
				var t := da/(da-db)
				clipped.append([a[0]+t*(b[0]-a[0]),a[1]+t*(b[1]-a[1]),a[2]+t*(b[2]-a[2])])
		for k in range(1,clipped.size()-1):
			var a: Array = clipped[0]
			var b: Array = clipped[k]
			var c: Array = clipped[k+1]
			var ax: float=a[0]-origin[0]; var ay: float=a[1]-origin[1]; var az: float=a[2]-origin[2]
			var bx: float=b[0]-origin[0]; var by: float=b[1]-origin[1]; var bz: float=b[2]-origin[2]
			var cx: float=c[0]-origin[0]; var cy: float=c[1]-origin[1]; var cz: float=c[2]-origin[2]
			var term := (ax*(by*cz-bz*cy)+ay*(bz*cx-bx*cz)+az*(bx*cy-by*cx))/6.0-correction
			var total := sum+term
			correction=(total-sum)-term
			sum=total
	return sum
