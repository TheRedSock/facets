class_name GemFrameWorker
extends RefCounted
## Reusable GPU worker. Expensive optics, display processing and delivery have
## separate cache records. Work can be sharded without any shared mutable scene.
var store: GemArtifactStore
var tracer: GemTracer
var compiled_key := ""
var compiled: Dictionary = {}
var counters := {"rendered": 0, "reprinted": 0, "restyled": 0, "display_hits": 0, "resumed_samples": 0}
var last_error := ""

func _init(output_root := "res://generated/gemfactory") -> void:
	store = GemArtifactStore.new(output_root)

func release() -> void:
	if tracer != null:
		tracer.release()
		tracer = null

func run(job: GemFrameJob, sample_limit := 0) -> Dictionary:
	last_error = GemJobValidator.validate(job)
	if not last_error.is_empty():return _fail(last_error)
	var ownership:=GemWorkClaim.acquire(store.root,GemFramePlan.master_key(job),"render")
	if ownership.has("error"):return _fail(ownership.error)
	if ownership.status=="busy":return ownership
	var claim:GemWorkClaim=ownership.claim
	var result := _run_active(job, sample_limit)
	claim.release()
	return result

func _run_active(job: GemFrameJob, sample_limit: int) -> Dictionary:
	var display_key := GemFramePlan.display_key(job)
	var master_key := GemFramePlan.master_key(job)
	var existing := store.read(display_key)
	if _display_image(existing, job, GemFramePlan.display_engine(job)) != null:
		counters["display_hits"] += 1
		return existing["metadata"]
	var print_key := GemFramePlan.print_key(job)
	if display_key != print_key:
		var cached_print := _display_image(store.read(print_key), job, GemRenderIdentity.pipeline_digest("print"))
		if cached_print != null:
			return _publish_styled(job, cached_print)
	var master_record := store.read(master_key)
	var master: Image = null
	if not master_record.is_empty() and master_record["metadata"].get("kind") == "linear_master" and master_record.metadata.get("engine") == GemFramePlan.master_engine(job):
		master = GemArtifactStore.decode_linear(master_record["payload"])
		if master != null and master.get_size() != job.resolution:
			master = null
	if master == null:
		var stone_key := job.stone.fingerprint()
		if stone_key != compiled_key:
			compiled = LapidaryStoneCompiler.compile(job.stone)
			if compiled.has("compilation_error"):
				return _fail(compiled.compilation_error)
			if compiled.get("planes", PackedFloat32Array()).is_empty() and not compiled.has("mesh") and not compiled.has("analytic_shape") and not compiled.has("rounded_solid"):
				return _fail("Specimen compiler produced no closed host geometry")
			compiled_key = stone_key
	if tracer == null or tracer.width != job.resolution.x or tracer.height != job.resolution.y or (master == null and tracer._print_only):
		release()
		tracer = GemTracer.create(job.resolution.x, job.resolution.y, master != null)
	if tracer == null:
		return _fail("RenderingDevice unavailable; GPU workers need a supported display/Vulkan environment")
	var lighting := GemRigCompiler.compile(job.rig)
	tracer.set_print_white(lighting.white_xyz)
	if master == null:
		if not tracer.configure_stone(compiled, lighting, job.quality):
			return _fail(tracer.configuration_error)
		tracer.set_seed(job.sample_seed)
		tracer.set_clip_sample(GemFramePlan.canonical_orientation(job.orientation), GemFramePlan.canonical_yaw(job.rig_yaw), job.role_multipliers, job.ortho_half, job.camera_offset)
	var checkpoint_key := GemContentIdentity.digest(["checkpoint-v1", master_key])
	if master == null:
		var saved := store.read(checkpoint_key)
		var raw_length := int(saved.get("metadata", {}).get("raw_bytes", 0))
		if not saved.is_empty() and saved["metadata"].get("kind") == "checkpoint" and raw_length > 0 and raw_length <= job.resolution.x * job.resolution.y * 80 + 4096:
			var raw: PackedByteArray = saved["payload"].decompress(int(saved["metadata"].get("raw_bytes", 0)), FileAccess.COMPRESSION_ZSTD)
			var state: Variant = bytes_to_var(raw)
			if state is Dictionary and int(state.get("samples", 0)) <= job.samples and tracer.restore_checkpoint(state):
				counters["resumed_samples"] += tracer.samples_accumulated
		var target := mini(job.samples, tracer.samples_accumulated + sample_limit) if sample_limit > 0 else job.samples
		var batch := maxi(1, int(job.quality.get("batch", 8)))
		var last_checkpoint := Time.get_ticks_msec()
		while tracer.samples_accumulated < target:
			tracer.accumulate(mini(batch, target - tracer.samples_accumulated))
			var transport_error := tracer.transport_error()
			if not transport_error.is_empty():
				return _fail(transport_error)
			if Time.get_ticks_msec() - last_checkpoint >= 5000:
				if not _checkpoint(checkpoint_key):
					return _fail("Cannot publish render checkpoint")
				last_checkpoint = Time.get_ticks_msec()
		if tracer.samples_accumulated < job.samples:
			if not _checkpoint(checkpoint_key):
				return _fail("Cannot publish partial render")
			return {"status": "partial", "samples": tracer.samples_accumulated, "master": master_key}
		master = Image.create_from_data(tracer.width, tracer.height, false, Image.FORMAT_RGBAF, tracer.read_reconstructed_xyz().to_byte_array())
		var metadata := {"kind": "linear_master", "width": master.get_width(), "height": master.get_height(), "samples": job.samples,
			"space": "associated_XYZ_CIE1931_2deg", "reconstruction": job.quality.get("denoise_passes", 0),
			"engine": GemFramePlan.master_engine(job), "producer": {"source_engine": GemRenderIdentity.worker_digest(), "godot": Engine.get_version_info(), "adapter": RenderingServer.get_video_adapter_name()},
			"geometry_backend": compiled.get("geometry_backend", "general"), "condition_report": compiled.get("condition_report", {}), "profile": tracer.profile(), "crystal_transport": tracer.crystal_diagnostics(), "surface_transport": tracer.surface_diagnostics()}
		if not store.publish(master_key, GemArtifactStore.encode_linear(master), metadata):
			return _fail("Cannot publish linear master")
		counters["rendered"] += 1
	else:
		counters["reprinted"] += 1
	# All prints use the same normalized stored master, including the first one.
	if not tracer.load_linear_master(master):
		return _fail("Invalid master dimensions/format")
	var display := tracer.finalize_print(job.print_style, false, job.exposure, job.output_size, false)
	var metadata := {"kind": "display", "master": master_key, "engine": GemRenderIdentity.pipeline_digest("print"), "width": display.get_width(), "height": display.get_height(),
		"codec": "webp_lossless", "space": "srgb_straight_alpha", "status": "complete"}
	if not store.publish(print_key, display.save_webp_to_buffer(false), metadata):
		return _fail("Cannot publish mastered print")
	if display_key != print_key:
		return _publish_styled(job, display)
	return store.read(print_key).get("metadata", {})

func _publish_styled(job: GemFrameJob, mastered: Image) -> Dictionary:
	var display := GemStylePipeline.apply(mastered, job.game_style)
	if display == null:
		return _fail("Cannot process display style")
	var metadata := {"kind": "display", "master": GemFramePlan.master_key(job), "print": GemFramePlan.print_key(job),
		"engine": GemFramePlan.display_engine(job), "width": display.get_width(), "height": display.get_height(),
		"codec": "webp_lossless", "space": "srgb_straight_alpha", "status": "complete", "styling": "game_display"}
	var key := GemFramePlan.display_key(job)
	if not store.publish(key, display.save_webp_to_buffer(false), metadata):
		return _fail("Cannot publish styled display frame")
	counters["restyled"] += 1
	return store.read(key).get("metadata", {})

static func _display_image(record: Dictionary, job: GemFrameJob, engine: String) -> Image:
	var metadata: Dictionary = record.get("metadata", {})
	if metadata.get("kind") != "display" or metadata.get("engine") != engine or metadata.get("master") != GemFramePlan.master_key(job):
		return null
	if metadata.get("status") != "complete" or metadata.get("codec") != "webp_lossless" or metadata.get("space") != "srgb_straight_alpha":
		return null
	if Vector2i(int(metadata.get("width", 0)), int(metadata.get("height", 0))) != job.output_size:
		return null
	var decoded := Image.new()
	if decoded.load_webp_from_buffer(record.get("payload", PackedByteArray())) != OK or decoded.get_size() != job.output_size:
		return null
	# RGB-only lossless WebP may decode as RGB8 when every pixel is opaque.
	decoded.convert(Image.FORMAT_RGBA8)
	return decoded

func _checkpoint(key: String) -> bool:
	var raw := var_to_bytes(tracer.checkpoint())
	return store.publish(key, raw.compress(FileAccess.COMPRESSION_ZSTD), {"kind": "checkpoint", "raw_bytes": raw.size()})

func _fail(message: String) -> Dictionary:
	last_error = message
	push_error(message)
	return {}
