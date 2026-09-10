class_name GemCondition
extends Resource
## Explicit specimen condition. Grade is a recipe/selection label; these fields
## describe realized physical features and remain stable under lighting/pose.
@export var defects: Array[GemDefect] = []
@export var finish: GemSurface = GemSurface.new()
@export var workmanship: GemWorkmanship = GemWorkmanship.new()
## Spatial coefficient fields use physical millimeters in the host coordinate frame.
@export var volume_fields: Array[GemVolumeField] = []
@export var banding: GemBanding = GemBanding.new()

func validate_volume_fields() -> PackedStringArray:
	var errors := PackedStringArray()
	if banding != null:
		errors.append_array(banding.validate())
	if volume_fields.size() > 16:
		errors.append("At most 16 spatial fields are supported per host")
	for field in volume_fields:
		if field == null:
			errors.append("Spatial field is missing")
		else:
			errors.append_array(field.validate())
	return errors
