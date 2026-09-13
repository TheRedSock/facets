class_name GemOpticalEvidence
extends Resource
## Evidence for one physical quantity, not a blanket certification of a mineral.
enum Kind { AUTHORED_APPROXIMATION, PUBLISHED_MODEL, FITTED_TARGETS, SUPPLIED_MEASUREMENT }
@export var kind := Kind.AUTHORED_APPROXIMATION
@export_multiline var citation := ""
@export var dataset_sha256 := ""
@export var method := ""
## Original supplied measurement interpretation, retained alongside raw SHA256.
@export var source_record: Dictionary = {}
## Zero means unknown; no temperature dependence is inferred from this metadata.
@export var temperature_kelvin := 0.0
## -1 means unreported. This is not a rendered noise or quality parameter.
@export var relative_uncertainty := -1.0
@export_multiline var assumptions := ""

static func derived(parent: GemOpticalEvidence, method_description: String) -> GemOpticalEvidence:
	# Repeated slider edits derive from the source evidence, not an unbounded
	# nested chain of intermediate drafts. Document undo retains those edits.
	var source := parent
	if parent != null and parent.source_record.get("derivation") == "authored-edit-v1" and parent.source_record.get("parent") is GemOpticalEvidence:
		source = parent.source_record.parent
	var result := GemOpticalEvidence.new()
	result.method = method_description
	result.assumptions = "Authored derivative; changed values are not the source measurement or published model."
	result.source_record = {"derivation": "authored-edit-v1", "parent_evidence": GemContentIdentity.digest(source), "parent": source.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) if source != null else null}
	return result

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if kind < 0 or kind > Kind.SUPPLIED_MEASUREMENT:
		errors.append("Unknown evidence kind")
	if not is_finite(temperature_kelvin) or temperature_kelvin < 0.0 or not is_finite(relative_uncertainty) or (relative_uncertainty < 0.0 and relative_uncertainty != -1.0):
		errors.append("Invalid evidence temperature or uncertainty")
	if kind != Kind.AUTHORED_APPROXIMATION and citation.strip_edges().is_empty():
		errors.append("Non-authored optical data needs a citation")
	if kind == Kind.SUPPLIED_MEASUREMENT:
		if dataset_sha256.length() != 64 or not dataset_sha256.is_valid_hex_number() or method.strip_edges().is_empty():
			errors.append("Supplied measurements need a raw dataset SHA256 and method")
	return errors
