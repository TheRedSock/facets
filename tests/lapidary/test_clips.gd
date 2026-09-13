extends SceneTree
## Shared clip sampling and production factory rendering. Headless-safe — the GPU
## section self-skips (prints "SKIP gpu") when no RenderingDevice exists.
##
## Run: godot --headless --script tests/lapidary/test_clips.gd

const ClipSamplerScript := preload("res://core/lapidary/clips/clip_sampler.gd")
const TracerScript := preload("res://core/lapidary/tracer/gem_tracer.gd")

var _pass := 0
var _fail := 0


func _init() -> void:
	print("\n=== Lapidary clip delivery tests ===\n")
	_test_clip_frame_math()
	_test_baker_sample_math()
	_test_orientation_tracks()
	_test_forge_service()
	_test_gpu_smoke()
	print("\n%d passed, %d failed" % [_pass, _fail])
	print("CHECK_COMPLETE: test_clips"); quit(1 if _fail > 0 else 0)


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  PASS %s" % name)
	else:
		_fail += 1
		printerr("  FAIL %s" % name)


# ------------------------------------------------------------------ fixtures

func _make_clip(clip_id: StringName, duration := 1.0, fps := 2.0) -> GemClip:
	var clip := GemClip.new()
	clip.clip_id = clip_id
	clip.orientation_keys = [GemOrientationKey.new()]
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

	_check(idle.frame_count() == 1 and idle.orientation_keys.size()==1,
		"idle is a 1-frame still")
	_check(is_equal_approx(idle.frame_time(0), 0.0), "idle frame_time(0) == 0")

	_check(turn.frame_count() == 12, "turn 0.4s @ 30fps -> 12 frames")
	_check(turn.orientation_keys.size()==5 and not turn.loop,"presentation turn has four explicit quarter-turn intervals")
	_check(turn.time_curve != null, "turn has a time curve")
	_check(turn.time_curve.sample(0.2) < 0.18, "turn time curve starts slow (accel)")
	_check(turn.time_curve.sample(0.8) > 0.82, "turn time curve finishes slow (decel)")
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

	var rest := Quaternion(Vector3.RIGHT,deg_to_rad(-12))
	var q0: Quaternion = ClipSamplerScript.frame_orientation(turn, 0.0)
	_check(q0.angle_to(rest) < 0.001, "turn t=0 orientation == rest tilt")
	var q1: Quaternion = ClipSamplerScript.frame_orientation(turn, 1.0)
	_check(q1.angle_to(rest) < 0.001, "turn t=1 (360 deg) returns to rest tilt")
	var qm: Quaternion = ClipSamplerScript.frame_orientation(turn, 0.5)
	_check(qm.angle_to(q0) > 1.0, "turn t=0.5 is far from rest (spin mid)")
	var q_early: Quaternion = ClipSamplerScript.frame_orientation(turn, 0.2)
	_check(q_early.angle_to(rest) < deg_to_rad(50.0),
		"turn t=0.2 has not spun far yet (accel)")

	var flash := load("res://data/lapidary/clips/flash.tres") as GemClip
	_check(absf(ClipSamplerScript.frame_exposure(flash, 0.5) - 1.8) < 0.01,
		"flash exposure at t=0.5 == 1.8")
	var idle := load("res://data/lapidary/clips/idle.tres") as GemClip
	_check(is_equal_approx(ClipSamplerScript.frame_exposure(idle, 0.0), 1.0),
		"idle exposure defaults to 1.0")

	var orbit := _make_clip(&"orbit_test")
	orbit.rig_orbit_degrees = 40.0
	_check(is_equal_approx(ClipSamplerScript.frame_rig_yaw_rad(orbit, 0.5), deg_to_rad(20.0)),
		"rig yaw is linear in t")
	_check(ClipSamplerScript.frame_role_mult(idle, 0.5).is_equal_approx(Vector4.ONE),
		"role multipliers default to 1")

	var lights: GemLighting = GemRigCompiler.compile(
		load("res://data/lapidary/rigs/gameplay_studio.tres") as GemLightRig)
	_check(lights.lights.size() % 8 == 0 and lights.lights.size() / 8 >= 1, "gameplay_studio packs >= 1 light")

func _test_orientation_tracks() -> void:
	var tilt:GemClip=load("res://data/lapidary/clips/tilt_return.tres")
	_check(tilt.track_error().is_empty(),"Saved tilt/return is an admitted generic track")
	_check(absf(ClipSamplerScript.frame_orientation(tilt,0).dot(ClipSamplerScript.frame_orientation(tilt,1)))>1-.000001,"Tilt loop closes at the rest orientation")
	_check(ClipSamplerScript.frame_orientation(tilt,.5).angle_to(ClipSamplerScript.frame_orientation(tilt,0))>.1,"Tilt has actual intermediate motion")
	var clip:=_make_clip(&"arbitrary_orientation")
	var a:=Quaternion(Vector3(1,2,3).normalized(),.3)
	var b:=a*Quaternion(Vector3(2,-1,1).normalized(),.8)
	clip.orientation_keys=[GemOrientationKey.new(0,a),GemOrientationKey.new(.25,a),GemOrientationKey.new(1,b)]
	_check(clip.track_error().is_empty(),"Uneven key times and an explicit hold are admitted")
	_check(absf(ClipSamplerScript.frame_orientation(clip,.125).dot(a))>1-.000001,"Hold interval keeps orientation fixed")
	var mid:Quaternion=ClipSamplerScript.frame_orientation(clip,.625)
	_check(absf(mid.angle_to(a)-.4)<.00001 and absf(mid.angle_to(b)-.4)<.00001,"Shortest arc midpoint has equal angular distance to arbitrary endpoints")
	clip.loop=true
	_check(not clip.track_error().is_empty(),"Open orientation endpoint cannot masquerade as a seamless loop")
	clip.loop=false;clip.orientation_keys[1].time=0
	_check(not clip.track_error().is_empty(),"Duplicate key times are rejected")
	clip.orientation_keys=[GemOrientationKey.new(),GemOrientationKey.new(1,Quaternion(Vector3.UP,PI))]
	_check(not clip.track_error().is_empty(),"Ambiguous half-turn interval requires an intermediate key")
	clip.orientation_keys=[GemOrientationKey.new(),GemOrientationKey.new(1,Quaternion(Vector3.UP,.2))]
	var curve:=Curve.new();curve.add_point(Vector2.ZERO);curve.add_point(Vector2.ONE)
	curve.set_point_right_tangent(0,-1)
	clip.time_curve=curve
	_check(not clip.track_error().is_empty(),"Time remap with continuous negative overshoot is rejected even if endpoints are valid")
	curve.set_point_right_tangent(0,0);curve.set_point_left_tangent(1,0)
	_check(clip.track_error().is_empty(),"Smooth endpoint-preserving time remap is admitted")
	curve.set_point_left_tangent(1,10)
	_check(not clip.track_error().is_empty(),"Interior curve reversal cannot pass via sampled clip endpoints")
	clip.time_curve=null;clip.orientation_keys=[GemOrientationKey.new()];clip.loop=true;clip.rig_orbit_degrees=20
	_check(not clip.track_error().is_empty(),"Loop lighting direction must close too")
	clip.rig_orbit_degrees=360
	_check(clip.track_error().is_empty(),"Complete rig orbit closes without a special stone-motion mode")


# ------------------------------------------------------------------ forge service

func _test_forge_service() -> void:
	print("[delivery service]")
	var forge: Node = (load("res://autoloads/gem_forge.gd") as GDScript).new()
	_check(forge.get_clip(&"no_such_gem", &"rest").is_empty(), "missing specimen -> empty metadata")
	_check(forge.get_frame(&"no_such_gem", &"rest", 0) == null, "missing frame -> null")
	_check(not forge.is_processing(), "delivery service has no runtime render loop")
	forge.free()


# ------------------------------------------------------------------ gpu smoke

func _test_gpu_smoke() -> void:
	print("[gpu]")
	if DisplayServer.get_name() == "headless":
		print("  SKIP gpu (run windowed for GPU coverage)")
		return
	var probe = TracerScript.create(64, 64)
	if probe == null:
		print("  SKIP gpu (no RenderingDevice — run windowed for GPU coverage)")
		return
	probe.release()

	var request := GemAssetRequest.new()
	request.asset_id = &"clip_test"
	request.stone = load("res://data/lapidary/stones/quartz.tres")
	request.rig = load("res://data/lapidary/rigs/gameplay_studio.tres")
	request.print_style = GemPrint.load_house()
	request.clips = [load("res://data/lapidary/clips/idle.tres"), load("res://data/lapidary/clips/flash.tres")]
	request.rung = "interact"
	request.resolution = Vector2i(64, 64)
	request.output_size = Vector2i(32, 32)
	request.samples = 16
	var batch := GemAssetBatch.new()
	batch.requests = [request]
	var plan := GemAssetPlanner.plan(batch)
	_check(plan.error.is_empty(), "public planner admits clip request")
	if not plan.error.is_empty(): return
	var worker := GemFrameWorker.new("res://artifacts/clip-factory/%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()])
	var frames: Array[Image] = []
	for job in plan.jobs:
		var result := worker.run(job)
		_check(result.get("status") == "complete", "factory completes sampled frame")
		if result.get("status") != "complete": worker.release(); return
		frames.append(GemFrameWorker._display_image(worker.store.read(GemFramePlan.display_key(job)), job, GemFramePlan.display_engine(job)))
	var img := frames[0]
	_check(img.get_size() == request.output_size, "factory resolves requested dimensions")
	var center := img.get_pixel(img.get_width() / 2, img.get_height() / 2)
	_check(center.a > 0.5, "stone covers the frame center (coverage alpha)")

	# Effect track reaches the print pass: flash mid-frames must be brighter.
	_check(frames.size() == 7, "idle and flash produce seven requested frames")
	var lum_first := _mean_covered_luminance(frames[1])
	var lum_mid := _mean_covered_luminance(frames[4]) # t=0.6, exposure ~1.77
	_check(lum_mid > lum_first * 1.1,
		"exposure_pulse brightens mid frames (%.3f -> %.3f)" % [lum_first, lum_mid])
	_check(worker.counters.rendered == 1, "exposure-only frames share one optical master")
	worker.release()


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
