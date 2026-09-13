class_name GemFacetGroup
extends Resource
## One independently indexed family of half-spaces. All lengths are normalized
## stone units. Scalar expressions reference p.<parameter>, s.<set>.<measure>
## and, with explicit meet groups, `meet` (the earlier surface at this anchor).
@export var group_id: StringName
@export var directions: GemFacetDirections
## Inclination from the girdle plane: 0 is horizontal, 90 is vertical.
@export var inclination := "34.5"
## +1 faces above the girdle; -1 faces below. No forced terminations.
@export_enum("Lower:-1", "Upper:1") var side := 1
## Anchor XY = sampled girdle point * scale - sampled normal * inset.
@export var scale := "1"
@export var inset := "0"
@export var height := "0.03"
## Signed displacement of the plane along its outward unit normal.
@export var offset := "0"
## Earlier groups whose upper/lower envelope supplies `meet` at anchor XY.
## Missing/wrong-facing construction surfaces are errors. If later construction
## or manufacture erases the target face, the compiler reports that explicitly.
@export var meet_groups: PackedStringArray = []
## Active kernel classification for diagnostic/primary-geometry consumers.
@export_range(0, 7) var zone := 1

func validate() -> String:
	if not String(group_id).is_valid_identifier() or group_id == &"girdle": return "Facet group needs a unique identifier other than girdle"
	if directions == null: return "Facet group needs explicit directions"
	var error := directions.validate()
	if not error.is_empty(): return error
	if side not in [-1, 1] or zone < 0 or zone > 7: return "Invalid facet side or zone"
	for expression in [inclination, scale, inset, height, offset]:
		error = GemCutExpression.syntax_error(expression)
		if not error.is_empty(): return String(group_id) + ": " + error
	return ""
