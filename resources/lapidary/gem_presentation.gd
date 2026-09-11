class_name GemPresentation
extends Resource
## Presentation only. Does not move the cut, culet, defects or crystal lattice.
enum OrientationMode { SHAPE_DEFAULT, NATIVE, CUSTOM }
enum CenterMode { REST_BOUNDS, ORIGIN, CUSTOM }
enum PivotMode { REST_FRAME, ORIGIN, BODY_BOUNDS, CUSTOM }
@export var orientation_mode: OrientationMode = OrientationMode.SHAPE_DEFAULT
@export var orientation_deg := Vector3.ZERO
@export var center_mode: CenterMode = CenterMode.REST_BOUNDS
## Camera-plane point in normalized stone units at the initial pose.
@export var custom_center := Vector2.ZERO
@export var pivot_mode: PivotMode = PivotMode.REST_FRAME
## Native stone coordinates, in normalized stone units (not millimeters).
@export var custom_pivot := Vector3.ZERO

func validate() -> String:
	if orientation_mode not in [0, 1, 2] or center_mode not in [0, 1, 2] or pivot_mode not in [0, 1, 2, 3]:
		return "Unknown presentation mode"
	if not orientation_deg.is_finite() or not custom_center.is_finite() or not custom_pivot.is_finite():
		return "Presentation coordinates must be finite"
	if custom_center.length() > 10000 or custom_pivot.length() > 10000:
		return "Presentation coordinates exceed the camera range"
	if maxf(absf(orientation_deg.x), maxf(absf(orientation_deg.y), absf(orientation_deg.z))) > 360000:
		return "Presentation angles exceed 1000 revolutions"
	return ""
