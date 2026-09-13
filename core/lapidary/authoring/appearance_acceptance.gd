class_name GemAppearanceAcceptance
extends RefCounted
## Review is evidence about a frozen request, never inferred from admission.
static func subject(job: GemFrameJob) -> String:
	return GemContentIdentity.digest(["appearance-review-v1", job, GemRenderIdentity.worker_digest()])

static func status(job: GemFrameJob, record: Dictionary) -> Dictionary:
	var error := GemJobValidator.validate(job)
	if not error.is_empty(): return {"status": "invalid", "reason": error}
	if record.is_empty(): return {"status": "unreviewed", "reason": "No appearance evidence"}
	if record.get("subject") != subject(job): return {"status": "stale", "reason": "Specimen, policy, pipeline, print or evidence changed"}
	if record.get("decision") not in ["accepted", "rejected"] or str(record.get("reviewer", "")).strip_edges().is_empty() or not record.get("checks") is Dictionary or record.checks.is_empty():
		return {"status": "invalid", "reason": "Review needs an explicit decision, reviewer and measured checks"}
	return {"status": record.decision, "reason": str(record.get("reason", ""))}
