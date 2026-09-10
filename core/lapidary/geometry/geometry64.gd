class_name GemGeometry64
extends RefCounted
## Small binary64 vector algebra for construction/reference geometry. Godot's
## Vector3 arithmetic uses binary32 in the standard engine build.
static func vec(x: float, y: float, z: float) -> PackedFloat64Array:
	return PackedFloat64Array([x,y,z])

static func dot(a: PackedFloat64Array, b: PackedFloat64Array) -> float:
	return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]

static func cross(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return vec(a[1]*b[2]-a[2]*b[1],a[2]*b[0]-a[0]*b[2],a[0]*b[1]-a[1]*b[0])

static func add(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return vec(a[0]+b[0],a[1]+b[1],a[2]+b[2])

static func subtract(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	return vec(a[0]-b[0],a[1]-b[1],a[2]-b[2])

static func scale(a: PackedFloat64Array, s: float) -> PackedFloat64Array:
	return vec(a[0]*s,a[1]*s,a[2]*s)

static func unit(a: PackedFloat64Array) -> PackedFloat64Array:
	var length := sqrt(dot(a,a))
	return scale(a,1.0/length) if length>0 else vec(0,0,0)

static func finite(a: PackedFloat64Array) -> bool:
	return a.size()==3 and is_finite(a[0]) and is_finite(a[1]) and is_finite(a[2])

static func plane(normal: PackedFloat64Array, point: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([normal[0],normal[1],normal[2],dot(normal,point)])

static func plane_distance(halfspace: PackedFloat64Array, point: PackedFloat64Array) -> float:
	return halfspace[0]*point[0]+halfspace[1]*point[1]+halfspace[2]*point[2]-halfspace[3]
