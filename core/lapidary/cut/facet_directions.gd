class_name GemFacetDirections
extends Resource
## Explicit index wheel. A 360-division wheel expresses azimuths in degrees.
## Boundary sampling uses the girdle normal at that ray; radial sampling uses
## the ray itself as the normal and the corresponding support point.
@export var set_id: StringName
@export_range(1, 4096) var divisions := 96
@export var indices := PackedFloat64Array()
@export var phase_degrees := 0.0
@export_enum("radial", "boundary") var sampling := "radial"

func validate() -> String:
	if not String(set_id).is_valid_identifier(): return "Direction set needs an identifier"
	if divisions < 1 or divisions > 4096 or indices.is_empty() or indices.size() > 256: return "Direction wheel needs 1..256 indices and 1..4096 divisions"
	if not is_finite(phase_degrees) or sampling not in ["radial", "boundary"]: return "Invalid direction phase or sampling"
	var seen := {}
	for index in indices:
		if not is_finite(index) or index < 0 or index >= divisions: return "Indices must be finite and inside the declared wheel"
		if seen.has(index): return "Duplicate direction index"
		seen[index] = true
	return ""
