class_name GemCondition
extends Resource
## Explicit specimen condition. Grade is a recipe/selection label; these fields
## describe realized physical features and remain stable under lighting/pose.
@export var defects: Array[GemDefect] = []
@export var finish: GemSurface = GemSurface.new()
## Spatial coefficient fields use physical millimeters in the host coordinate frame.
@export var volume_fields: Array[GemVolumeField] = []

func validate_volume_fields() -> PackedStringArray:
	var errors := PackedStringArray()
	if volume_fields.size() > 16:
		errors.append("At most 16 spatial fields are supported per host")
	for field in volume_fields:
		if field == null:
			errors.append("Spatial field is missing")
		else:
			errors.append_array(field.validate())
	return errors
