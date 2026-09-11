class_name GemRounding
extends Resource
## Explicit physical radius for continuous convex junction rounding.
## Disabled at radius 0; not a calibrated hardness/time wear law.
## The surface is (host eroded by radius) offset outward by that radius.
@export var radius_mm := 0.0
@export var max_removed_fraction := 0.25

func validate()->PackedStringArray:
	var errors:=PackedStringArray()
	if not is_finite(radius_mm) or radius_mm<0 or radius_mm>1000:errors.append("Rounding radius must be finite and in [0,1000] mm")
	if not is_finite(max_removed_fraction) or max_removed_fraction<=0 or max_removed_fraction>=1:errors.append("Rounding removal limit must be in (0,1)")
	return errors
