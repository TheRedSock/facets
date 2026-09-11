class_name GemStyle
extends Resource
## Optional game art direction, applied to the mastered sprite at output size.
## These are display operations, never material properties or clarity grades.
@export var saturation := 1.0
@export var tint := Color.WHITE
@export var contrast := 1.0
@export var luminance_bands := 0
@export var contour_pixels := 0
@export var contour_opacity := 0.0
@export var contour_color := Color.BLACK

func validate() -> String:
	for value in [saturation, contrast]:
		if not is_finite(value) or value < 0 or value > 2:
			return "Style saturation and contrast must be finite and in [0, 2]"
	for color in [tint, contour_color]:
		for axis in 4:
			if not is_finite(color[axis]) or color[axis] < 0 or color[axis] > 1:
				return "Style colors must be finite and in [0, 1]"
		if color.a != 1:
			return "Style color alpha must be one; coverage is preserved"
	if luminance_bands != 0 and (luminance_bands < 2 or luminance_bands > 64):
		return "Style luminance bands must be zero or 2..64"
	if contour_pixels < 0 or contour_pixels > 4 or not is_finite(contour_opacity) or contour_opacity < 0 or contour_opacity > 1:
		return "Style contour needs 0..4 pixels and opacity in [0, 1]"
	return ""

func inputs() -> Array:
	# Inactive contour controls do not produce redundant assets.
	var contour := [contour_pixels, contour_opacity, contour_color] if contour_pixels > 0 and contour_opacity > 0 else []
	return [saturation, tint, contrast, luminance_bands, contour]

func is_identity() -> bool:
	return saturation == 1 and tint == Color.WHITE and contrast == 1 and luminance_bands == 0 and (contour_pixels == 0 or contour_opacity == 0)
