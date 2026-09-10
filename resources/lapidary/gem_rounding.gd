class_name GemRounding
extends Resource
## Experimental mesh reference for convex junction rounding, disabled at radius 0.
## Angular specular convergence is not established. Not a hardness/time wear law.
## The surface is (host eroded by radius) offset outward by that radius.
@export var radius_mm := 0.0
@export var angular_step_deg := 6.0
@export var max_removed_fraction := 0.25

func validate()->PackedStringArray:
	var errors:=PackedStringArray()
	if not is_finite(radius_mm) or radius_mm<0 or radius_mm>1000:errors.append("Rounding radius must be finite and in [0,1000] mm")
	if not is_finite(angular_step_deg) or angular_step_deg<1 or angular_step_deg>20:errors.append("Rounding angular step must be 1..20 degrees")
	if not is_finite(max_removed_fraction) or max_removed_fraction<=0 or max_removed_fraction>=1:errors.append("Rounding removal limit must be in (0,1)")
	return errors
