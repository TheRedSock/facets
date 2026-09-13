class_name GemAuthoringAdmission
extends RefCounted
## Authoring uses the production admission functions; no parallel rule table.
static func error(resource: Resource) -> String:
	if resource == null: return "Resource is missing"
	var graph := GemContentIdentity.graph_error(resource)
	if not graph.is_empty(): return graph
	if resource is GemFrameJob: return GemJobValidator.validate(resource)
	if resource is GemStone: return GemJobValidator.specimen_error(resource)
	if resource is GemAssetBatch: return GemAssetPlanner.plan(resource).error
	if resource is GemAssetRequest:
		var batch := GemAssetBatch.new(); batch.requests = [resource]
		return GemAssetPlanner.plan(batch).error
	if resource is GemCutTemplate: return GemJobValidator.Cuts.template_error(resource)
	if resource is GemClip: return GemAssetPlanner._clip_error(resource, 65536)
	if resource is Curve: return GemClip.curve_error(resource,false)
	if resource is GemLightRig: return GemJobValidator._rig(resource)
	if resource is GemAbsorber: return "Edit absorption terms within their host material (species and density are required)"
	if resource.has_method("validate"):
		var result: Variant = resource.call("validate")
		return result if result is String else "; ".join(result)
	return "No public admission contract for " + (resource.get_script().resource_path if resource.get_script() != null else resource.get_class())

static func capabilities(job: GemFrameJob) -> Dictionary:
	var result := {"selected_error": GemJobValidator.validate(job), "backends": {}, "appearance": "unreviewed"}
	if job == null: return result
	for backend in ["scalar", "polarized", "crystal"]:
		var candidate := job.duplicate_deep(Resource.DEEP_DUPLICATE_ALL) as GemFrameJob
		candidate.quality["polarization"] = backend == "polarized"
		candidate.quality["crystal_transport"] = backend == "crystal"
		var why := GemJobValidator.validate(candidate)
		result.backends[backend] = {"admitted": why.is_empty(), "reason": why,
			"status": "unsupported" if not why.is_empty() else ("approximate" if backend == "scalar" else "supported"),
			"required_device_features": ["shaderFloat64"] if backend == "crystal" else [],
			"device_verified": false,
			"model": "Uniaxial Maxwell packets; smooth weak-loss media" if backend == "crystal" else ("Isotropic real refraction with Mueller transport" if backend == "polarized" else "Scalar transport; anisotropic refraction is approximate")}
	return result
