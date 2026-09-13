class_name GemOrientationKey
extends Resource
## Absolute stone orientation at normalized track time. Interpolation is SLERP.
@export var time := 0.0
@export var orientation := Quaternion.IDENTITY

func _init(at_time := 0.0, rotation := Quaternion.IDENTITY) -> void:
	time = at_time
	orientation = rotation

func validate() -> String:
	if not is_finite(time) or time<0 or time>1: return "Orientation key time must be finite and within 0..1"
	if not orientation.is_finite() or absf(orientation.length_squared()-1.0)>.00001:
		return "Orientation key requires a unit quaternion"
	return ""
