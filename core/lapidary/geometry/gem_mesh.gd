class_name GemMesh
extends RefCounted
## CPU mesh IR. Indexed, oriented closed surfaces; facet identities survive
## triangulation and BVH reordering. No scene-tree or imported mesh dependency.
var vertices := PackedVector3Array()
var indices := PackedInt32Array()
var facet_ids := PackedInt32Array()
## Closed region identity. Zero is the host; positive IDs select nested media.
var region_ids := PackedInt32Array()

func triangle_count() -> int:
	return indices.size() / 3

func add_triangle(a: int, b: int, c: int, facet: int, region := 0) -> void:
	indices.append_array(PackedInt32Array([a, b, c]))
	facet_ids.append(facet)
	region_ids.append(region)

func append_region(source: GemMesh, region: int) -> void:
	var offset := vertices.size()
	vertices.append_array(source.vertices)
	for triangle in source.triangle_count():
		add_triangle(offset + source.indices[triangle * 3], offset + source.indices[triangle * 3 + 1], offset + source.indices[triangle * 3 + 2], source.facet_ids[triangle], region)

# Buffers remain mutable authoring data. A content key prevents stale admission
# after in-place edits while avoiding repeated BVH/predicate work on a specimen.
var _validated_key := ""
var _validated_errors := PackedStringArray()
static var _admission_cache: Dictionary = {}
const ADMISSION_CACHE_LIMIT := 64

func signed_volume() -> float:
	var triangles: Array[int] = []
	for i in triangle_count():
		triangles.append(i)
	return component_volume(triangles)

func component_volume(triangles: Array[int]) -> float:
	if triangles.is_empty():
		return 0.0
	var origin := vertices[indices[triangles[0] * 3]]
	var volume := 0.0
	var correction := 0.0
	for i in triangles:
		var a := vertices[indices[i * 3]]
		var b := vertices[indices[i * 3 + 1]]
		var c := vertices[indices[i * 3 + 2]]
		# Scalar arithmetic stays binary64; Vector3 cross/dot would round to 32.
		var ax: float = float(a.x) - origin.x
		var ay: float = float(a.y) - origin.y
		var az: float = float(a.z) - origin.z
		var bx: float = float(b.x) - origin.x
		var by: float = float(b.y) - origin.y
		var bz: float = float(b.z) - origin.z
		var cx: float = float(c.x) - origin.x
		var cy: float = float(c.y) - origin.y
		var cz: float = float(c.z) - origin.z
		var term := (ax * (by * cz - bz * cy) + ay * (bz * cx - bx * cz) + az * (bx * cy - by * cx)) / 6.0 - correction
		var total := volume + term
		correction = (total - volume) - term
		volume = total
	return volume

func validate() -> PackedStringArray:
	var key := fingerprint()
	if key != _validated_key:
		if _admission_cache.has(key):
			_validated_errors = _admission_cache[key]
		else:
			_validated_errors = GemMeshValidation.validate(self)
			if _admission_cache.size() >= ADMISSION_CACHE_LIMIT:
				_admission_cache.erase(_admission_cache.keys()[0])
			_admission_cache[key] = _validated_errors.duplicate()
		_validated_key = key
	return _validated_errors.duplicate()

func fingerprint() -> String:
	return GemContentIdentity.digest([vertices, indices, facet_ids, region_ids])
