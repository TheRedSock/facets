class_name GemBoundarySet
extends RefCounted
## Explicit priority regions, clipped to the host. Air is material -1; host
## material is 0. A higher active region ID overrides a lower one. This handles
## overlapping voids without double-subtracting and permits filled fractures.
## Every region is a separate closed, outward-oriented surface. Exact coincident
## boundaries are unsupported; use overlap or a finite physical gap.
const MAX_REGIONS := 128
var mesh := GemMesh.new()
var materials := PackedInt32Array()

func add(surface: GemMesh, material: int) -> bool:
	if materials.size() >= MAX_REGIONS or not surface.validate().is_empty():
		return false
	mesh.append_region(surface, materials.size())
	materials.append(material)
	return true

func medium(active: Dictionary) -> int:
	if not active.get(0, false):
		return -1
	for region in range(materials.size() - 1, -1, -1):
		if active.get(region, false):
			return materials[region]
	return -1

## CPU reference for straight-ray medium segmentation. Used for independent
## length and overlap tests of the GPU boundary state machine.
func segments(origin: Vector3, direction: Vector3) -> Array[Dictionary]:
	var bvh := GemBvh.build(mesh)
	var active := {}
	var result: Array[Dictionary] = []
	var distance := 0.0
	for event in 4096:
		var hit := bvh.intersect(origin, direction)
		if hit.is_empty():
			break
		var material := medium(active)
		var next_distance: float = distance + hit["t"]
		if material >= 0:
			result.append({"begin": distance, "end": next_distance, "medium": material})
		active[hit["region"]] = direction.dot(hit["normal"]) < 0.0
		origin += direction * (hit["t"] + 0.000004)
		distance = next_distance + 0.000004
	return result
