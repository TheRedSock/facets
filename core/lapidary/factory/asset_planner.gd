class_name GemAssetPlanner
extends RefCounted
## Delivery names never enter the physical specimen or optical cache identity.
## Validate the whole request list before expanding bounded frame allocations.
static func plan(batch: GemAssetBatch) -> Dictionary:
	if batch == null or batch.requests.is_empty() or batch.requests.size() > 4096:
		return {"error": "Asset batch needs 1..4096 requests"}
	if batch.frame_budget < 1 or batch.frame_budget > 65536 or batch.geometry_coverage_side not in [0, 1, 2, 4, 8]:
		return {"error": "Invalid batch frame budget or geometry coverage"}
	var names := {}
	var frame_count := 0
	for request in batch.requests:
		var error := _request_error(request)
		if not error.is_empty(): return {"error": error}
		if names.has(request.asset_id): return {"error": "Duplicate asset ID: " + String(request.asset_id)}
		names[request.asset_id] = true
		var clip_names := {}
		var retain := request.retain_prints and request.game_style != null and not request.game_style.is_identity()
		for clip in request.clips:
			error = _clip_error(clip, batch.frame_budget)
			if not error.is_empty(): return {"error": String(request.asset_id) + ": " + error}
			if clip_names.has(clip.clip_id): return {"error": "Duplicate clip ID in " + String(request.asset_id)}
			clip_names[clip.clip_id] = true
			frame_count += clip.frame_count() * (2 if retain else 1)
			if frame_count > batch.frame_budget: return {"error": "Requested frames exceed the explicit batch budget"}
	var jobs: Array[GemFrameJob] = []
	var clips := {}
	var specimens := {}
	for original in batch.requests:
		var request: GemAssetRequest = original.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
		var stone := request.stone
		if request.recipe != null:
			var realized := GemSpecimenFactory.realize(request.recipe, request.preset_id, request.specimen_seed)
			if not realized.error.is_empty(): return {"error": String(request.asset_id) + ": " + realized.error}
			stone = realized.stone
		var policy := GemRung.policy(GemRung.rung_from_name(request.rung))
		policy.merge(request.policy_overrides, true)
		var specimen_error := GemJobValidator.specimen_error(stone, policy.get("polarization", false) == true)
		if not specimen_error.is_empty(): return {"error": String(request.asset_id) + ": " + specimen_error}
		specimens[String(request.asset_id)] = stone.fingerprint()
		for clip in request.clips:
			var frames := GemFramePlan.animation(stone, clip, request.rig, request.print_style, GemRung.rung_from_name(request.rung))
			var framing := GemPresentationCompiler.prepare(stone, request.presentation, GemClipSampler.frame_orientation(clip, 0.0))
			if not framing.error.is_empty(): return {"error": framing.error}
			var ids := []
			for job in frames:
				job.game_style = request.game_style
				job.quality.merge(request.policy_overrides, true)
				if request.resolution != Vector2i.ZERO: job.resolution = request.resolution
				if request.output_size != Vector2i.ZERO: job.output_size = request.output_size
				if request.samples != 0: job.samples = request.samples
				var pose := GemPresentationCompiler.sample(framing, job.orientation, job.resolution, job.ortho_half)
				job.orientation = pose.orientation; job.camera_offset = pose.camera_offset
				var error := GemJobValidator.validate(job)
				if error.is_empty() and batch.geometry_coverage_side > 0:
					error = GemGeometryPlan.validate(job, batch.geometry_coverage_side)
				if not error.is_empty(): return {"error": String(request.asset_id) + ": " + error}
				ids.append(GemFramePlan.display_key(job))
				if request.retain_prints and job.game_style != null and not job.game_style.is_identity():
					var unstyled: GemFrameJob = job.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
					unstyled.game_style = null
					jobs.append(unstyled)
				jobs.append(job)
			clips[String(request.asset_id) + "/" + String(clip.clip_id)] = {"frames": ids, "fps": clip.fps, "loop": clip.loop}
	return {"error": "", "jobs": jobs, "clips": clips, "specimens": specimens, "estimate": GemFramePlan.estimate(jobs), "geometry_coverage_side": batch.geometry_coverage_side}

static func _request_error(request: GemAssetRequest) -> String:
	if request == null: return "Missing asset request"
	var graph := GemContentIdentity.graph_error(request)
	if not graph.is_empty(): return graph
	if not _identifier(request.asset_id): return "Asset ID needs 1..128 ASCII letters, digits, underscore, hyphen or dot"
	if (request.stone == null) == (request.recipe == null): return "Choose exactly one specimen or recipe for " + String(request.asset_id)
	if request.recipe != null and request.preset_id == &"": return "Recipe request needs an explicit preset ID"
	if request.recipe == null and request.preset_id != &"": return "Preset selection requires a recipe"
	if request.recipe != null and (request.specimen_seed < 0 or request.specimen_seed > 2147483647): return "Invalid specimen seed"
	if request.rig == null or request.print_style == null or request.clips.is_empty() or request.clips.size() > 256: return "Request needs rig, print and 1..256 clips"
	if GemRung.rung_from_name(request.rung) < 0: return "Unknown quality rung"
	for size in [request.resolution, request.output_size]:
		if size != Vector2i.ZERO and (size.x < 1 or size.y < 1 or size.x > 8192 or size.y > 8192): return "Invalid request resolution override"
	if request.samples < 0 or request.samples > 16777216: return "Invalid request sample override"
	for key in ["res", "out", "spp"]:
		if request.policy_overrides.has(key): return "Use explicit dimensions/samples instead of policy " + key
	if request.game_style != null and not request.game_style.validate().is_empty(): return request.game_style.validate()
	if request.presentation != null and not request.presentation.validate().is_empty(): return request.presentation.validate()
	return ""

static func _identifier(value: StringName) -> bool:
	var text := String(value)
	if text.is_empty() or text.length() > 128 or text in [".", ".."]: return false
	for character in text:
		if character not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-": return false
	return true

static func _clip_error(clip: GemClip, budget: int) -> String:
	if clip == null or not _identifier(clip.clip_id): return "Clip needs a valid ID"
	if not is_finite(clip.duration_s) or not is_finite(clip.fps) or clip.duration_s <= 0 or clip.fps <= 0: return "Clip timing must be finite and positive"
	var count := clip.duration_s * clip.fps
	if not is_finite(count) or roundf(count) > budget: return "Clip exceeds frame budget"
	return clip.track_error()
