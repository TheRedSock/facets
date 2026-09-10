class_name GemGeometryWorker
extends RefCounted
## Content-addressed primary geometry, generated without accumulating optics.
var store: GemArtifactStore
var tracer: GemTracer
var counters := {"generated": 0, "cache_hits": 0}
var last_error := ""
var _compiled_key := ""
var _compiled := {}

func _init(output_root := "res://generated/gemfactory") -> void:
	store = GemArtifactStore.new(output_root)

func release() -> void:
	if tracer != null:
		tracer.release()
		tracer = null

func run(job: GemFrameJob, coverage_side := 4) -> Dictionary:
	last_error = GemGeometryPlan.validate(job, coverage_side)
	if not last_error.is_empty():
		return {}
	var ownership:=GemWorkClaim.acquire(store.root,GemGeometryPlan.key(job,coverage_side),"geometry")
	if ownership.has("error"):
		last_error=ownership.error;return {}
	if ownership.status=="busy":return ownership
	var claim:GemWorkClaim=ownership.claim
	var result := _run_active(job, coverage_side)
	claim.release()
	return result

func _run_active(job: GemFrameJob, coverage_side: int) -> Dictionary:
	var key := GemGeometryPlan.key(job, coverage_side)
	var expected := {"width": job.resolution.x, "height": job.resolution.y, "coverage_side": coverage_side}
	var record := store.read(key)
	if not record.is_empty() and GemGeometryPlan.payload_error(record, expected, GemGeometryPlan.source_digest()).is_empty():
		counters.cache_hits += 1
		return record.metadata
	var specimen_key := GemContentIdentity.digest(GemGeometryPlan.specimen_inputs(job.stone))
	if specimen_key != _compiled_key:
		_compiled = LapidaryStoneCompiler.compile(job.stone)
		_compiled_key = specimen_key
	if tracer == null or tracer.width != job.resolution.x or tracer.height != job.resolution.y:
		release()
		tracer = GemTracer.create(job.resolution.x, job.resolution.y)
	if tracer == null:
		last_error = "Geometry generation needs a supported GPU/display environment"
		return {}
	tracer.configure_stone(_compiled, GemLighting.analytic(PackedFloat32Array(), Vector4.ZERO), GemRung.policy(GemRung.INTERACT))
	tracer.set_clip_sample(GemFramePlan.canonical_orientation(job.orientation), 0.0, Vector4.ONE, job.ortho_half)
	var begin := Time.get_ticks_usec()
	var geometry := tracer.geometry_aov(coverage_side)
	if geometry == null:
		last_error = "Geometry pass failed"
		return {}
	var metadata := expected.duplicate()
	metadata.merge({"kind": "primary_geometry", "engine": GemGeometryPlan.source_digest(), "geometry_pipeline": GemGeometryPlan.source_digest(), "codec": "gao1", "status": "complete",
		"position_depth_unit": "mm", "normal_space": "object_incident_facing", "geometry_wall_ms": (Time.get_ticks_usec() - begin) / 1000.0,
		"optical_samples": tracer.samples_accumulated, "producer": {"source_engine": GemRenderIdentity.worker_digest(), "godot": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name()}})
	if not store.publish(key, geometry.encode(), metadata):
		last_error = "Cannot publish geometry companion"
		return {}
	counters.generated += 1
	return store.read(key).get("metadata", {})
