extends SceneTree
## Delivery-layer tests: clip frame math, cache key stability + invalidation,
## manifest priority order, strip/sidecar roundtrip. Headless-safe — the GPU
## section self-skips (prints "SKIP gpu") when no RenderingDevice exists.
##
## Run: godot --headless --script tests/lapidary/test_clips.gd

const ClipBakerScript := preload("res://core/lapidary/clips/clip_baker.gd")
const CacheScript := preload("res://core/lapidary/clips/gem_cache.gd")
const ManifestScript := preload("res://core/lapidary/clips/gem_manifest.gd")
const TracerScript := preload("res://core/lapidary/tracer/gem_tracer.gd")

var _pass := 0
var _fail := 0


func _init() -> void:
	print("\n=== Lapidary clip delivery tests ===\n")
	_test_clip_frame_math()
	_test_baker_sample_math()
	_test_cache_keys()
	_test_manifest()
	_test_strip_roundtrip()
	_test_forge_service()
	_test_gpu_smoke()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  PASS %s" % name)
	else:
		_fail += 1
		printerr("  FAIL %s" % name)


# ------------------------------------------------------------------ fixtures

func _make_stone(seed_val := 1, size_mm := 5.0) -> GemStone:
	var species := GemSpecies.new()
	species.species_id = &"test_quartz"
	species.sellmeier_b = Vector3(0.6962, 0.4079, 0.8975)
	species.sellmeier_c_um2 = Vector3(0.0047, 0.0135, 97.93)
	var stone := GemStone.new()
	stone.stone_id = &"test_stone"
	stone.species = species
	stone.seed = seed_val
	stone.size_mm = size_mm
	return stone


func _make_clip(clip_id: StringName, duration := 1.0, fps := 2.0) -> GemClip:
	var clip := GemClip.new()
	clip.clip_id = clip_id
	clip.duration_s = duration
	clip.fps = fps
	clip.loop = false
	return clip


# ------------------------------------------------------------------ clip resources

func _test_clip_frame_math() -> void:
	print("[clip resources + frame math]")
	var idle := load("res://data/lapidary/clips/idle.tres") as GemClip
	var turn := load("res://data/lapidary/clips/turn.tres") as GemClip
	var flash := load("res://data/lapidary/clips/flash.tres") as GemClip
	_check(idle != null and turn != null and flash != null, "three catalog clips load")
	if idle == null or turn == null or flash == null:
		return

	_check(idle.frame_count() == 1 and idle.stone_motion == GemClip.StoneMotion.STILL,
		"idle is a 1-frame still")
	_check(is_equal_approx(idle.frame_time(0), 0.0), "idle frame_time(0) == 0")

	_check(turn.frame_count() == 12, "turn 0.4s @ 30fps -> 12 frames")
	_check(turn.stone_motion == GemClip.StoneMotion.TURNTABLE and not turn.loop,
		"turn is a non-looping turntable")
	_check(turn.turntable_axis.is_equal_approx(Vector3(0, 1, 0))
		and is_equal_approx(turn.turntable_degrees, 360.0), "turn: 360 deg around (0,1,0)")
	_check(turn.easing != null, "turn has an easing curve")
	_check(turn.easing.sample(0.2) < 0.18, "turn easing starts slow (accel)")
	_check(turn.easing.sample(0.8) > 0.82, "turn easing finishes slow (decel)")
	_check(is_equal_approx(turn.frame_time(0), 0.0)
		and is_equal_approx(turn.frame_time(11), 1.0), "turn frame_time spans 0..1")

	_check(flash.frame_count() == 6, "flash 0.3s @ 20fps -> 6 frames")
	var pulse: Curve = flash.effect_envelopes.get("exposure_pulse")
	_check(pulse != null, "flash has exposure_pulse envelope")
	if pulse != null:
		_check(absf(pulse.sample(0.5) - 1.8) < 0.01, "exposure_pulse peaks at 1.8")
		_check(absf(pulse.sample(0.0) - 1.0) < 0.01 and absf(pulse.sample(1.0) - 1.0) < 0.01,
			"exposure_pulse returns to 1.0")


# ------------------------------------------------------------------ baker sample math

func _test_baker_sample_math() -> void:
	print("[baker sample math]")
	var turn := load("res://data/lapidary/clips/turn.tres") as GemClip
	if turn == null:
		_check(false, "turn clip available")
		return

	var rest := Quaternion.from_euler(Vector3(deg_to_rad(turn.rest_tilt_deg.x),
		deg_to_rad(turn.rest_tilt_deg.y), deg_to_rad(turn.rest_tilt_deg.z)))
	var q0: Quaternion = ClipBakerScript.frame_orientation(turn, 0.0)
	_check(q0.angle_to(rest) < 0.001, "turn t=0 orientation == rest tilt")
	var q1: Quaternion = ClipBakerScript.frame_orientation(turn, 1.0)
	_check(q1.angle_to(rest) < 0.001, "turn t=1 (360 deg) returns to rest tilt")
	var qm: Quaternion = ClipBakerScript.frame_orientation(turn, 0.5)
	_check(qm.angle_to(q0) > 1.0, "turn t=0.5 is far from rest (spin mid)")
	var q_early: Quaternion = ClipBakerScript.frame_orientation(turn, 0.2)
	_check(q_early.angle_to(rest) < deg_to_rad(50.0),
		"turn t=0.2 has not spun far yet (accel)")

	var flash := load("res://data/lapidary/clips/flash.tres") as GemClip
	_check(absf(ClipBakerScript.frame_exposure(flash, 0.5) - 1.8) < 0.01,
		"flash exposure at t=0.5 == 1.8")
	var idle := load("res://data/lapidary/clips/idle.tres") as GemClip
	_check(is_equal_approx(ClipBakerScript.frame_exposure(idle, 0.0), 1.0),
		"idle exposure defaults to 1.0")

	var orbit := _make_clip(&"orbit_test")
	orbit.rig_orbit_degrees = 40.0
	_check(is_equal_approx(ClipBakerScript.frame_rig_yaw_rad(orbit, 0.5), deg_to_rad(20.0)),
		"rig yaw is linear in t")
	_check(ClipBakerScript.frame_role_mult(idle, 0.5).is_equal_approx(Vector4.ONE),
		"role multipliers default to 1")

	var lights: PackedFloat32Array = GemRigCompiler.pack(
		load("res://data/lapidary/rigs/gameplay_studio.tres") as GemLightRig)
	_check(lights.size() % 8 == 0 and lights.size() / 8 >= 1, "gameplay_studio packs >= 1 light")


# ------------------------------------------------------------------ cache keys

func _test_cache_keys() -> void:
	print("[cache keys]")
	var stone_a := _make_stone(1)
	var stone_b := _make_stone(1)
	var stone_c := _make_stone(2)
	var clip := _make_clip(&"keytest")

	var key_a: String = CacheScript.cache_key(stone_a, clip, GemRung.CLIP_BAKE)
	var key_b: String = CacheScript.cache_key(stone_b, clip, GemRung.CLIP_BAKE)
	_check(key_a == key_b, "identical stone+clip+rung -> identical key")
	_check(key_a != CacheScript.cache_key(stone_c, clip, GemRung.CLIP_BAKE),
		"stone seed change -> new key")
	_check(key_a != CacheScript.cache_key(stone_a, clip, GemRung.INTERACT),
		"rung change -> new key")
	_check(key_a.ends_with("@clip_bake"), "key carries rung name")

	var clip_changed := _make_clip(&"keytest", 2.0)
	_check(key_a != CacheScript.cache_key(stone_a, clip_changed, GemRung.CLIP_BAKE),
		"clip duration change -> new key (fingerprint)")

	var clip_ease := _make_clip(&"keytest")
	clip_ease.easing = Curve.new()
	clip_ease.easing.add_point(Vector2(0.0, 0.0))
	clip_ease.easing.add_point(Vector2(1.0, 1.0))
	_check(key_a != CacheScript.cache_key(stone_a, clip_ease, GemRung.CLIP_BAKE),
		"clip easing change -> new key (fingerprint)")

	var v1: String = CacheScript.versioned_key(stone_a, clip, GemRung.CLIP_BAKE, 1)
	var v2: String = CacheScript.versioned_key(stone_a, clip, GemRung.CLIP_BAKE, 2)
	_check(v1 != v2 and v1.begins_with("v1/") and v2.begins_with("v2/"),
		"look_version bump -> new versioned key")


# ------------------------------------------------------------------ manifest

func _test_manifest() -> void:
	print("[manifest]")
	var shuffled := """
	{"version": 1, "entries": [
		{"stone_id": "ruby", "clip_id": "flash", "rung": "clip_bake", "priority": "later"},
		{"stone_id": "quartz", "clip_id": "idle", "rung": "clip_bake", "priority": "required_now"},
		{"stone_id": "ruby", "clip_id": "turn", "rung": "interact", "priority": "soon"},
		{"stone_id": "ruby", "clip_id": "idle", "rung": "clip_bake", "priority": "required_now"}
	]}
	"""
	var m: GemManifest = ManifestScript.from_json_text(shuffled)
	_check(m.size() == 4, "inline manifest parses 4 entries")
	var order: Array[Dictionary] = m.entries()
	_check(order[0]["priority"] == ManifestScript.PRIORITY_REQUIRED_NOW
		and order[1]["priority"] == ManifestScript.PRIORITY_REQUIRED_NOW
		and order[2]["priority"] == ManifestScript.PRIORITY_SOON
		and order[3]["priority"] == ManifestScript.PRIORITY_LATER,
		"entries sorted required_now -> soon -> later")
	_check(order[0]["stone_id"] == &"quartz" and order[1]["stone_id"] == &"ruby",
		"stable file order within a priority class")
	_check(m.required_now(["ruby"]).size() == 1, "required_now filters by tile set")
	_check(m.required_now(["unknown_gem"]).is_empty(), "required_now: unknown tile -> empty")
	_check(m.rung_for(&"ruby", &"turn") == GemRung.INTERACT, "rung_for reads catalog rung")
	_check(m.rung_for(&"ruby", &"missing") == GemRung.CLIP_BAKE, "rung_for fallback")

	var live: GemManifest = ManifestScript.load_default()
	_check(live.size() == 48, "shipped manifest has 48 entries (16 stones x 3 clips)")
	var ladder := ["quartz", "amethyst", "peridot", "topaz", "sapphire", "emerald", "ruby", "diamond"]
	_check(live.required_now(ladder).size() == 8, "shipped manifest: 8 required_now idles (main ladder)")
	var alternate := ["fluorite", "smoky_quartz", "tourmaline", "rhodolite",
		"aquamarine", "alexandrite", "painite", "blue_garnet"]
	_check(live.required_now(alternate).size() == 8, "shipped manifest: 8 required_now idles (alternate ladder)")
	for e: Dictionary in live.required_now(ladder):
		if e["clip_id"] != &"idle" or e["rung"] != GemRung.CLIP_BAKE:
			_check(false, "required_now entries are idle@clip_bake")
			return
	_check(true, "required_now entries are idle@clip_bake")
	_check(live.required_now(["quartz", "ruby"]).size() == 2,
		"shipped manifest filters to active tile set")
	var soon_n := 0
	var later_n := 0
	for e: Dictionary in live.entries():
		if e["priority"] == ManifestScript.PRIORITY_SOON:
			soon_n += 1
			if e["clip_id"] != &"turn":
				_check(false, "soon entries are turn")
				return
		elif e["priority"] == ManifestScript.PRIORITY_LATER:
			later_n += 1
			if e["clip_id"] != &"flash":
				_check(false, "later entries are flash")
				return
	_check(soon_n == 16, "shipped manifest: 16 soon turns")
	_check(later_n == 16, "shipped manifest: 16 later flashes")


# ------------------------------------------------------------------ strip roundtrip

func _test_strip_roundtrip() -> void:
	print("[strip/sidecar roundtrip]")
	var stone := _make_stone(99)
	var clip := _make_clip(&"roundtrip", 1.0, 2.0) # 2 frames
	_check(clip.frame_count() == 2, "synthetic clip has 2 frames")

	var f0 := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	f0.fill(Color(1, 0, 0, 1))
	var f1 := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	f1.fill(Color(0, 1, 0, 0.5))
	var frames := [f0, f1]

	CacheScript.invalidate(stone, clip, GemRung.CLIP_BAKE)
	_check(CacheScript.read(stone, clip, GemRung.CLIP_BAKE).is_empty(), "cold cache misses")
	_check(CacheScript.write(stone, clip, GemRung.CLIP_BAKE, frames, {"synthetic": true}),
		"write strip + sidecar to user://")
	_check(CacheScript.has(stone, clip, GemRung.CLIP_BAKE), "has() sees the artifact")

	var cached: Dictionary = CacheScript.read(stone, clip, GemRung.CLIP_BAKE)
	_check(not cached.is_empty(), "read returns the artifact")
	if cached.is_empty():
		return
	_check(int(cached["frames"]) == 2 and is_equal_approx(float(cached["fps"]), 2.0)
		and bool(cached["loop"]) == false, "sidecar playback fields roundtrip")
	_check(int(cached["frame_w"]) == 4 and int(cached["frame_h"]) == 4
		and (cached["strip"] as Image).get_width() == 8, "strip is frames*w x h")
	_check((cached["meta"] as Dictionary).get("synthetic", false) == true, "meta roundtrips")

	var sliced: Array[Image] = CacheScript.slice_frames(cached["strip"], 4, 4, 2)
	var p0 := sliced[0].get_pixel(1, 1)
	var p1 := sliced[1].get_pixel(2, 2)
	_check(p0.r > 0.99 and p0.g < 0.01 and p0.a > 0.99, "frame 0 pixels survive (red)")
	_check(p1.g > 0.99 and p1.r < 0.01 and absf(p1.a - 0.5) < 0.01,
		"frame 1 pixels + alpha survive (lossless)")

	# Invalidation: any fingerprint change makes the same path unreadable.
	var edited := _make_clip(&"roundtrip", 1.5, 2.0)
	_check(CacheScript.read(stone, edited, GemRung.CLIP_BAKE).is_empty(),
		"clip fingerprint change invalidates (key mismatch -> miss)")
	_check(not CacheScript.has(stone, edited, GemRung.CLIP_BAKE), "has() honours invalidation")

	CacheScript.invalidate(stone, clip, GemRung.CLIP_BAKE)
	_check(CacheScript.read(stone, clip, GemRung.CLIP_BAKE).is_empty(), "invalidate deletes user:// files")


# ------------------------------------------------------------------ forge service

## GemForge is not autoload-registered yet; instantiate the script directly.
## Serving from disk cache is CPU-only and must work headless too; the
## placeholder path is GPU and only asserted windowed.
func _test_forge_service() -> void:
	print("[forge service]")
	var forge: Node = (load("res://autoloads/gem_forge.gd") as GDScript).new()
	var headless := DisplayServer.get_name() == "headless"

	var missing: Dictionary = forge.get_clip(&"no_such_gem", &"idle")
	_check(missing.is_empty(), "get_clip: missing stone -> {}")
	_check(forge.get_clip(&"quartz", &"no_such_clip").is_empty(), "get_clip: missing clip -> {}")

	# Serving depends on the packaged dev cache; skip gracefully when a fresh
	# checkout has not run tools/package_clips.gd yet.
	var served: Dictionary = forge.get_clip(&"quartz", &"idle")
	if served.is_empty():
		print("  SKIP forge serving (no packaged cache — run tools/package_clips.gd)")
	else:
		_check(served["texture"] is ImageTexture and int(served["frames"]) == 1
			and served["frame_size"] == Vector2i(112, 112),
			"get_clip serves packaged idle (1 frame @ 112px)")
		var again: Dictionary = forge.get_clip(&"quartz", &"idle")
		_check(again["texture"] == served["texture"], "get_clip memory-caches the served strip")

		var ladder := ["quartz", "amethyst", "peridot", "topaz", "sapphire", "emerald", "ruby", "diamond"]
		forge.ensure_required(ladder)
		var report: Dictionary = forge.cold_start_report()
		_check(int(report.get("pending", -1)) == 0 and int(report["clips_baked"]) == 0,
			"ensure_required skips full cache (nothing queued)")

	if headless:
		_check(forge.get_placeholder_still(&"quartz") == null,
			"headless: placeholder degrades to null")
	else:
		var still: ImageTexture = forge.get_placeholder_still(&"quartz")
		if still == null:
			print("  SKIP placeholder (quartz stone resource not landed)")
		else:
			_check(still.get_width() == 128, "placeholder still is a 128px INTERACT render")
			_check(forge.get_placeholder_still(&"quartz") == still, "placeholder memory-cached")
	forge.free()


# ------------------------------------------------------------------ gpu smoke

func _test_gpu_smoke() -> void:
	print("[gpu]")
	var probe = TracerScript.create(64, 64)
	if probe == null:
		print("  SKIP gpu (no RenderingDevice — run windowed for GPU coverage)")
		return
	probe.release()

	var stone := _make_stone(7)
	var lights: PackedFloat32Array = GemRigCompiler.pack(
		load("res://data/lapidary/rigs/gameplay_studio.tres") as GemLightRig)
	var idle := load("res://data/lapidary/clips/idle.tres") as GemClip
	var baked: Dictionary = ClipBakerScript.bake(stone, idle, GemRung.INTERACT, lights)
	_check(not baked.is_empty(), "INTERACT bake produces a result")
	if baked.is_empty():
		return
	var frames: Array = baked["frames"]
	_check(frames.size() == 1, "idle bakes exactly 1 frame")
	var img: Image = frames[0]
	var policy := GemRung.policy(GemRung.INTERACT)
	_check(img.get_width() == int(policy["out"]) and img.get_height() == int(policy["out"]),
		"INTERACT output matches rung out size")
	var center := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	_check(center.a > 0.5, "stone covers the frame center (coverage alpha)")

	# Effect track reaches the print pass: flash mid-frames must be brighter.
	var flash := load("res://data/lapidary/clips/flash.tres") as GemClip
	var flashed: Dictionary = ClipBakerScript.bake(stone, flash, GemRung.INTERACT, lights)
	_check(not flashed.is_empty(), "flash INTERACT bake produces a result")
	if flashed.is_empty():
		return
	var flash_frames: Array = flashed["frames"]
	_check(flash_frames.size() == 6, "flash bakes 6 frames")
	var lum_first := _mean_covered_luminance(flash_frames[0])
	var lum_mid := _mean_covered_luminance(flash_frames[3]) # t=0.6, exposure ~1.77
	_check(lum_mid > lum_first * 1.1,
		"exposure_pulse brightens mid frames (%.3f -> %.3f)" % [lum_first, lum_mid])


static func _mean_covered_luminance(img: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
				count += 1
	return total / maxf(1.0, float(count))
