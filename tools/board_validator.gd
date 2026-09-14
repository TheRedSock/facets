class_name BoardValidator
extends RefCounted
## Legacy string adapter. Pure structured admission is the single authority.
func validate(layout: BoardLayoutResource) -> Array[String]:
	var result := LayoutAdmission.admit(layout)
	var issues: Array[String] = []
	for item in result.issues:
		issues.append("[%s] %s: %s" % [item.severity.to_upper(), item.field_path, item.code.replace("_", " ")])
	return issues
