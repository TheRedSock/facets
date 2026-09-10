class_name GemFramePlan
extends RefCounted
## An explicit animation request expands only the poses it actually needs.
## No automatic Cartesian product of rotations, cells, lights and conditions.
const POSE_GRID := 1000000.0

static func canonical_orientation(input: Quaternion) -> Quaternion:
	var q := input.normalized()
	if q.w < 0.0 or (q.w == 0.0 and (q.x < 0.0 or (q.x == 0.0 and q.y < 0.0))):
		q = -q
	# Render this canonical pose too. This is an explicit subpixel pose grid,
	# not hidden quantization of physical material properties or fingerprints.
	q = Quaternion(snappedf(q.x, 1.0 / POSE_GRID), snappedf(q.y, 1.0 / POSE_GRID), snappedf(q.z, 1.0 / POSE_GRID), snappedf(q.w, 1.0 / POSE_GRID)).normalized()
	return q

static func master_key(job: GemFrameJob) -> String:
	var policy := job.quality.duplicate(true)
	for key in ["res", "out", "spp", "batch", "device_memory_budget_mib"]:
		policy.erase(key)
	var lighting := GemRigCompiler.compile(job.rig)
	return GemContentIdentity.digest(["linear-master-v3", master_engine(job),
		job.stone.transport_inputs(), lighting.lights, lighting.spectra, lighting.background, policy,
		job.resolution, job.samples, job.sample_seed, canonical_orientation(job.orientation),
		canonical_yaw(job.rig_yaw), job.role_multipliers, job.ortho_half])

static func display_key(job: GemFrameJob) -> String:
	return GemContentIdentity.digest(["display-v2", GemRenderIdentity.pipeline_digest("print"), master_key(job), job.print_style,
		job.exposure, job.output_size, GemRigCompiler.compile(job.rig).white_xyz])

static func master_engine(job: GemFrameJob) -> String:
	return GemRenderIdentity.pipeline_digest(GemRenderIdentity.transport_domain(job.quality))

static func canonical_yaw(value: float) -> float:
	return snappedf(wrapf(value, -PI, PI), 1.0 / POSE_GRID)

static func animation(stone: GemStone, clip: GemClip, rig: GemLightRig, print_style: GemPrint, rung: int) -> Array[GemFrameJob]:
	var result: Array[GemFrameJob] = []
	var policy := GemRung.policy(rung)
	for frame in clip.frame_count():
		var t := clip.frame_time(frame)
		var job := GemFrameJob.new()
		job.stone = stone
		job.rig = rig
		job.print_style = print_style
		job.quality = policy.duplicate()
		job.resolution = Vector2i.ONE * int(policy["res"])
		job.output_size = Vector2i.ONE * int(policy["out"])
		job.samples = policy["spp"]
		job.sample_seed = stone.seed
		job.orientation = canonical_orientation(GemClipBaker.frame_orientation(clip, t))
		job.rig_yaw = canonical_yaw(GemClipBaker.frame_rig_yaw_rad(clip, t))
		job.role_multipliers = GemClipBaker.frame_role_mult(clip, t)
		job.exposure = GemClipBaker.frame_exposure(clip, t)
		result.append(job)
	return result

static func estimate(jobs: Array[GemFrameJob], measured_frame_ms := 0.0) -> Dictionary:
	var masters := {}
	var outputs := {}
	var raw_master_bytes := 0
	var rgba_bytes := 0
	for job in jobs:
		var master := master_key(job)
		if not masters.has(master):
			masters[master] = true
			raw_master_bytes += job.resolution.x * job.resolution.y * 16
		var display := display_key(job)
		if not outputs.has(display):
			outputs[display] = true
			rgba_bytes += job.output_size.x * job.output_size.y * 4
	return {"requested_frames": jobs.size(), "unique_masters": masters.size(), "unique_displays": outputs.size(),
		"uncompressed_linear_bytes": raw_master_bytes, "uncompressed_display_bytes": rgba_bytes,
		"trace_seconds_estimate": masters.size() * measured_frame_ms / 1000.0,
		"timing_is_measured": measured_frame_ms > 0.0}
