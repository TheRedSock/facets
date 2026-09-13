class_name GemPhysicalIdentity
extends RefCounted
## Physical cache inputs only. Admission and provenance use GemContentIdentity.
## New fields participate conservatively; exclude only audited metadata.
const METADATA := ["script", "resource_path", "resource_name", "resource_local_to_scene", "source_note"]
const EXCLUDED := {
	"cut_template.gd": ["cut_id"],
	"gem_species.gd": ["display_name", "hardness_mohs"],
	"gem_material.gd": ["material_id"],
	"gem_chromophore.gd": ["chromophore_id", "display_name"],
}

static func inputs(value: Variant) -> Variant:
	if value is GemOpticalEvidence:
		return null
	if value is Resource:
		var script: Script = value.get_script()
		var path: String = script.resource_path if script != null else value.get_class()
		var fields := {"schema": path}
		for property: Dictionary in value.get_property_list():
			var name: String = property.name
			if int(property.usage) & PROPERTY_USAGE_STORAGE == 0 or name in METADATA or name.begins_with("metadata/") or name in EXCLUDED.get(path.get_file(), []):
				continue
			var child: Variant = value.get(name)
			if child is GemOpticalEvidence:
				continue
			fields[name] = inputs(child)
		return fields
	if value is Array:
		var result := []
		for child in value: result.append(inputs(child))
		return result
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = inputs(value[key])
		return result
	return value
