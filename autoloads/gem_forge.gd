extends Node

## GemForge — lazy clip launcher/service.
## Registration (project.godot): GemForge="*res://autoloads/gem_forge.gd"
##
## Serves baked gem clips (WebP frame strips via GemCache), bakes missing
## manifest entries incrementally in the background (one accumulation batch
## per _process tick — a clip is never traced inside a single frame), and
## renders a synchronous INTERACT still as the cold-start placeholder.
##
## Headless: every public call degrades gracefully ({} / null, no GPU work,
## no crash) so simulation tests keep passing.

signal clip_ready(tile_id: StringName, clip_id: StringName)

const STONES_DIR := "res://data/lapidary/stones/"
const CLIPS_DIR := "res://data/lapidary/clips/"
## Designed rig from the lighting workstream; placeholder until it lands.
const RIG_PATH := "res://data/lapidary/rigs/gameplay_studio.tres"

var _manifest: GemManifest = null
var _stones: Dictionary = {} # tile_id -> GemStone (positive cache only)
var _clips: Dictionary = {} # clip_id -> GemClip (positive cache only)
var _mem: Dictionary = {} # versioned cache key -> served clip Dictionary
var _placeholders: Dictionary = {} # tile_id -> ImageTexture
var _tracers: Dictionary = {} # internal resolution -> GemTracer
var _queue: Array[Dictionary] = []
var _queued_keys: Dictionary = {} # versioned key -> true (dedupe)
var _job: Dictionary = {}
var _gpu_dead := false

var _report := {"clips_baked": 0, "seconds_total": 0.0, "seconds_to_first_idle": -1.0}
var _cold_t0_ms := -1


func _ready() -> void:
	# Lazy service: wiring only. No loading, no GPU, no disk until asked.
	set_process(false)


func _exit_tree() -> void:
	for tracer: GemTracer in _tracers.values():
		tracer.release()
	_tracers.clear()


# ------------------------------------------------------------------ public API

## Served clip from cache: {texture: ImageTexture (horizontal frame strip),
## frames: int, fps: float, loop: bool, frame_size: Vector2i}. {} when the
## stone/clip resource is missing or nothing is cached yet.
func get_clip(tile_id: StringName, clip_id: StringName) -> Dictionary:
	var stone := _load_stone(tile_id)
	var clip := _load_clip(clip_id)
	if stone == null or clip == null:
		return {}
	var rung := _get_manifest().rung_for(tile_id, clip_id, GemRung.CLIP_BAKE)
	var key := GemCache.versioned_key(stone, clip, rung)
	if _mem.has(key):
		return _mem[key]
	var cached := GemCache.read(stone, clip, rung)
	if cached.is_empty():
		return {}
	var served := _serve(cached)
	_mem[key] = served
	return served


## Walks the manifest in priority order for the run's tile set, skips cache
## hits, queues misses for incremental background baking. Emits clip_ready
## per completed clip. No-op in headless.
func ensure_required(tile_ids: Array) -> void:
	if _headless() or _gpu_dead:
		return
	var queued_any := false
	for entry in _get_manifest().entries_for_tiles(tile_ids):
		var stone := _load_stone(entry["stone_id"])
		var clip := _load_clip(entry["clip_id"])
		if stone == null or clip == null:
			continue # stone/clip resource not landed yet (parallel workstream)
		var rung: int = entry["rung"]
		var key := GemCache.versioned_key(stone, clip, rung)
		if _mem.has(key) or _queued_keys.has(key):
			continue
		if GemCache.has(stone, clip, rung):
			continue
		_queue.append({
			"tile_id": entry["stone_id"], "clip_id": entry["clip_id"],
			"rung": rung, "stone": stone, "clip": clip, "key": key,
		})
		_queued_keys[key] = true
		queued_any = true
	if queued_any and _job.is_empty() and not is_processing():
		_report = {"clips_baked": 0, "seconds_total": 0.0, "seconds_to_first_idle": -1.0}
		_cold_t0_ms = Time.get_ticks_msec()
		set_process(true)


## Cold-start accounting for the current (or last) bake cycle.
func cold_start_report() -> Dictionary:
	var report := _report.duplicate()
	if _cold_t0_ms >= 0:
		report["seconds_total"] = float(Time.get_ticks_msec() - _cold_t0_ms) / 1000.0
	report["pending"] = _queue.size() + (0 if _job.is_empty() else 1)
	return report


## Synchronous single INTERACT-rung still (few ms; the accepted one-frame
## hitch on a cold board). Memory-cached per tile. null when headless or the
## stone resource is missing.
func get_placeholder_still(tile_id: StringName) -> ImageTexture:
	if _placeholders.has(tile_id):
		return _placeholders[tile_id]
	if _headless() or _gpu_dead:
		return null
	var stone := _load_stone(tile_id)
	if stone == null:
		return null
	var clip := _load_clip(&"idle")
	if clip == null:
		clip = GemClip.new()
		clip.clip_id = &"placeholder_still"
		clip.duration_s = 0.0 # 1 frame
		clip.rest_tilt_deg = Vector3(-12, 0, 0)
	var policy := GemRung.policy(GemRung.INTERACT)
	var tracer := _tracer_for(int(policy["res"]))
	if tracer == null:
		return null
	var baked := GemClipBaker.bake(stone, clip, GemRung.INTERACT,
		_active_rig_lights(), _active_rig_background(), tracer)
	if baked.is_empty():
		return null
	var tex := ImageTexture.create_from_image((baked["frames"] as Array)[0])
	_placeholders[tile_id] = tex
	return tex


# ------------------------------------------------------------------ incremental baking

func _process(_delta: float) -> void:
	if not _job.is_empty():
		_step_job()
		return
	if _queue.is_empty():
		_finish_cycle()
		return
	_job = _begin_job(_queue.pop_front())


## One-time job setup (stone compile + buffer upload). Runs in its own tick.
func _begin_job(item: Dictionary) -> Dictionary:
	var stone: GemStone = item["stone"]
	var instance := LapidaryStoneCompiler.compile(stone)
	var policy := GemRung.policy(item["rung"], GemRung.scatter_noisy(instance))
	var tracer := _tracer_for(int(policy["res"]))
	if tracer == null:
		_abort_queue()
		return {}
	tracer.configure_stone(instance, _active_rig_lights(), policy)
	tracer.set_seed(int(instance["seed"]))
	tracer.set_background(_active_rig_background())

	var job := item.duplicate()
	job["policy"] = policy
	job["tracer"] = tracer
	job["frame"] = 0
	job["spp_done"] = 0
	job["frames"] = [] as Array[Image]
	job["gpu_ms"] = 0.0
	job["t0_ms"] = Time.get_ticks_msec()
	_stage_frame(job)
	return job


func _stage_frame(job: Dictionary) -> void:
	var clip: GemClip = job["clip"]
	var t: float = clip.frame_time(int(job["frame"]))
	var tracer: GemTracer = job["tracer"]
	tracer.set_clip_sample(GemClipBaker.frame_orientation(clip, t),
		GemClipBaker.frame_rig_yaw_rad(clip, t),
		GemClipBaker.frame_role_mult(clip, t), GemClipBaker.ORTHO_HALF)


## One accumulation batch per tick; frame finalize (GPU print) piggybacks on
## the batch that completes the frame's spp target.
func _step_job() -> void:
	var tracer: GemTracer = _job["tracer"]
	var policy: Dictionary = _job["policy"]
	var spp := int(policy["spp"])
	var batch := mini(int(policy["batch"]), spp - int(_job["spp_done"]))
	_job["gpu_ms"] = float(_job["gpu_ms"]) + tracer.accumulate(batch)
	_job["spp_done"] = int(_job["spp_done"]) + batch
	if int(_job["spp_done"]) < spp:
		return

	var clip: GemClip = _job["clip"]
	var t: float = clip.frame_time(int(_job["frame"]))
	var img := tracer.finalize_print(GemClipBaker.load_house_print(), false,
		GemClipBaker.frame_exposure(clip, t))
	var out := int(policy["out"])
	if out != int(policy["res"]):
		img.resize(out, out, Image.INTERPOLATE_LANCZOS)
	(_job["frames"] as Array).append(img)
	_job["frame"] = int(_job["frame"]) + 1
	_job["spp_done"] = 0
	if int(_job["frame"]) >= clip.frame_count():
		_complete_job()
	else:
		tracer.reset_accumulation()
		_stage_frame(_job)


func _complete_job() -> void:
	var stone: GemStone = _job["stone"]
	var clip: GemClip = _job["clip"]
	var rung: int = _job["rung"]
	var frames: Array = _job["frames"]
	var meta := {
		"gpu_ms": _job["gpu_ms"],
		"wall_ms": Time.get_ticks_msec() - int(_job["t0_ms"]),
		"spp": _job["policy"]["spp"],
	}
	var tile_id: StringName = _job["tile_id"]
	var clip_id: StringName = _job["clip_id"]
	var key: String = _job["key"]
	_queued_keys.erase(key)
	_job = {}

	if not GemCache.write(stone, clip, rung, frames, meta):
		push_warning("GemForge: cache write failed for %s/%s" % [tile_id, clip_id])
		return
	# Serve exactly what landed on disk (validates the artifact roundtrip).
	var cached := GemCache.read(stone, clip, rung)
	if cached.is_empty():
		push_warning("GemForge: readback failed for %s/%s" % [tile_id, clip_id])
		return
	_mem[key] = _serve(cached)
	_report["clips_baked"] = int(_report["clips_baked"]) + 1
	if float(_report["seconds_to_first_idle"]) < 0.0 and clip_id == &"idle" and _cold_t0_ms >= 0:
		_report["seconds_to_first_idle"] = float(Time.get_ticks_msec() - _cold_t0_ms) / 1000.0
	clip_ready.emit(tile_id, clip_id)


func _finish_cycle() -> void:
	if _cold_t0_ms >= 0:
		_report["seconds_total"] = float(Time.get_ticks_msec() - _cold_t0_ms) / 1000.0
		_cold_t0_ms = -1
	set_process(false)


func _abort_queue() -> void:
	push_warning("GemForge: no RenderingDevice — background baking disabled this session.")
	_gpu_dead = true
	_queue.clear()
	_queued_keys.clear()
	set_process(false)


# ------------------------------------------------------------------ resources

func _get_manifest() -> GemManifest:
	if _manifest == null:
		_manifest = GemManifest.load_default()
	return _manifest


## Misses are NOT cached: stone resources land from a parallel workstream and
## may appear mid-session.
func _load_stone(tile_id: StringName) -> GemStone:
	if _stones.has(tile_id):
		return _stones[tile_id]
	var path := STONES_DIR + String(tile_id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var stone := load(path) as GemStone
	if stone == null or stone.species == null:
		push_warning("GemForge: %s is not a usable GemStone (missing species?)" % path)
		return null
	_stones[tile_id] = stone
	return stone


func _load_clip(clip_id: StringName) -> GemClip:
	if _clips.has(clip_id):
		return _clips[clip_id]
	var path := CLIPS_DIR + String(clip_id) + ".tres"
	if not ResourceLoader.exists(path):
		return null
	var clip := load(path) as GemClip
	if clip == null:
		return null
	_clips[clip_id] = clip
	return clip


func _serve(cached: Dictionary) -> Dictionary:
	return {
		"texture": ImageTexture.create_from_image(cached["strip"]),
		"frames": int(cached["frames"]),
		"fps": float(cached["fps"]),
		"loop": bool(cached["loop"]),
		"frame_size": Vector2i(int(cached["frame_w"]), int(cached["frame_h"])),
	}


func _tracer_for(res: int) -> GemTracer:
	if _tracers.has(res):
		return _tracers[res]
	var tracer := GemTracer.create(res, res)
	if tracer == null:
		return null
	_tracers[res] = tracer
	return tracer


func _headless() -> bool:
	return DisplayServer.get_name() == "headless"


# ------------------------------------------------------------------ lighting rig

## PLACEHOLDER — the lighting workstream replaces this hookup. Prefers the
## designed rig resource when it exists; falls back to the spike light set
## (GemClipBaker.placeholder_rig_lights).
func _active_rig_lights() -> PackedFloat32Array:
	if ResourceLoader.exists(RIG_PATH):
		var rig := load(RIG_PATH) as GemLightRig
		if rig != null and not rig.lights.is_empty():
			return GemClipBaker.pack_rig_lights(rig)
	return GemClipBaker.placeholder_rig_lights()


## PLACEHOLDER — background gradient companion to _active_rig_lights().
func _active_rig_background() -> Vector3:
	if ResourceLoader.exists(RIG_PATH):
		var rig := load(RIG_PATH) as GemLightRig
		if rig != null:
			return Vector3(rig.bg_zenith, rig.bg_horizon, rig.bg_below)
	return GemClipBaker.placeholder_rig_background()
