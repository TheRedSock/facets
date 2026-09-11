class_name GemClipBaker
extends RefCounted
## Bakes clip x stone x rung x rig -> frame sequence through the GPU tracer.
##
## Synchronous evaluation helper. The resumable factory uses the same frame
## sampling functions below. The game consumes a prebuilt delivery library.
##
## Requires a RenderingDevice (windowed run). bake() returns {} in --headless.

## House print (mastering) — required; hard-fails if the resource is absent.
const HOUSE_PRINT_PATH := "res://data/lapidary/print/house_print.tres"
## Board framing: camera ortho half-width in stone units (girdle radius = 1).
const ORTHO_HALF := 1.25


## Bake every frame of a clip at a quality rung.
## Returns {frames: Array[Image], fps: float, loop: bool, meta: Dictionary},
## or {} when no RenderingDevice exists or inputs are unusable.
## `shared_tracer`: optional pre-created tracer whose size matches the rung's
## internal resolution; caller keeps ownership (amortizes shader compiles).
static func bake(stone: GemStone, clip: GemClip, rung: int, lights: GemLighting,
		shared_tracer: GemTracer = null, presentation: GemPresentation = null) -> Dictionary:
	if stone == null or clip == null or stone.material.species == null or lights == null:
		return {}
	var framing := GemPresentationCompiler.prepare(stone, presentation if presentation != null else GemPresentation.new(), frame_orientation(clip, 0.0))
	if not framing.error.is_empty(): push_error(framing.error); return {}
	var instance := LapidaryStoneCompiler.compile(stone)
	var policy := GemRung.policy(rung)
	var res: int = policy["res"]
	var out: int = policy["out"]
	var spp: int = policy["spp"]
	var batch: int = policy["batch"]

	var tracer := shared_tracer
	if tracer == null:
		tracer = GemTracer.create(res, res)
	if tracer == null:
		return {}
	assert(tracer.width == res and tracer.height == res,
		"shared_tracer size must match the rung's internal resolution")

	var t0 := Time.get_ticks_usec()
	tracer.configure_stone(instance, lights, policy)
	tracer.set_seed(int(instance["seed"]))

	var print_res := load_house_print()
	var frames: Array[Image] = []
	var frame_accumulate_wall_ms: Array = []
	var n := clip.frame_count()
	for i in n:
		var t := clip.frame_time(i)
		if i > 0:
			tracer.reset_accumulation()
		var pose := GemPresentationCompiler.sample(framing, frame_orientation(clip, t), Vector2i(res, res), ORTHO_HALF)
		tracer.set_clip_sample(pose.orientation, frame_rig_yaw_rad(clip, t),
			frame_role_mult(clip, t), ORTHO_HALF, pose.camera_offset)
		var accumulate_wall_ms := 0.0
		var done := 0
		while done < spp:
			var step := mini(batch, spp - done)
			accumulate_wall_ms += tracer.accumulate(step)
			done += step
		var img := tracer.finalize_print(print_res, false, frame_exposure(clip, t), Vector2i(out, out))
		frames.append(img)
		frame_accumulate_wall_ms.append(accumulate_wall_ms)

	if shared_tracer == null:
		tracer.release()

	return {
		"frames": frames,
		"fps": clip.fps,
		"loop": clip.loop,
		"meta": {
			"stone_id": String(stone.stone_id),
			"clip_id": String(clip.clip_id),
			"rung": GemRung.rung_name(rung),
			"res": res,
			"out": out,
			"spp": spp,
			"frame_accumulate_wall_ms": frame_accumulate_wall_ms,
			"wall_ms": float(Time.get_ticks_usec() - t0) / 1000.0,
			"print": "house",
		},
	}


# ------------------------------------------------------------- frame sample math

## Stone orientation for a normalized clip time: rest tilt composed with the
## motion track (motion first, then tilt — the turntable axis tilts with the
## stone). TILT_PRESENT is not in the v1 catalog and holds the rest pose.
static func frame_orientation(clip: GemClip, t: float) -> Quaternion:
	var tilt := clip.rest_tilt_deg
	var rest := Quaternion.from_euler(Vector3(
		deg_to_rad(tilt.x), deg_to_rad(tilt.y), deg_to_rad(tilt.z)))
	if clip.stone_motion != GemClip.StoneMotion.TURNTABLE:
		return rest
	var p := clampf(t, 0.0, 1.0)
	if clip.easing != null:
		p = clip.easing.sample(p)
	var axis := clip.turntable_axis
	if axis.length_squared() < 0.0001:
		axis = Vector3.UP
	return rest * Quaternion(axis.normalized(), deg_to_rad(clip.turntable_degrees * p))


## Rig track: yaw in radians. The kernel rotates light directions around
## world +Y by this angle in-shader (lighting-relative motion, linear in t).
static func frame_rig_yaw_rad(clip: GemClip, t: float) -> float:
	return deg_to_rad(clip.rig_orbit_degrees * clampf(t, 0.0, 1.0))


## Effect track: exposure multiplier fed into the print pass.
static func frame_exposure(clip: GemClip, t: float) -> float:
	var curve: Curve = clip.effect_envelopes.get("exposure_pulse")
	if curve == null:
		return 1.0
	return curve.sample(clampf(t, 0.0, 1.0))


## Effect track: per-role power multipliers (key, fill, rim, bounce).
static func frame_role_mult(clip: GemClip, t: float) -> Vector4:
	var ct := clampf(t, 0.0, 1.0)
	var key: Curve = clip.effect_envelopes.get("key_boost")
	var rim: Curve = clip.effect_envelopes.get("rim_boost")
	return Vector4(
		key.sample(ct) if key != null else 1.0,
		1.0,
		rim.sample(ct) if rim != null else 1.0,
		1.0)


static func load_house_print() -> GemPrint:
	return GemPrint.load_house()
