class_name GemClipBaker
extends RefCounted
## Bakes clip x stone x rung x rig -> frame sequence through the GPU tracer.
##
## Pure delivery logic: no scene tree, no autoload access. Callers (GemForge,
## tools/package_clips.gd, tests) supply the light set. All per-frame sample
## math (orientation, rig yaw, role multipliers, exposure) lives in the static
## helpers below so the synchronous path here and the incremental launcher
## path in GemForge produce identical frames.
##
## Requires a RenderingDevice (windowed run). bake() returns {} in --headless.

## House print (mastering) — applied when the print workstream lands the
## resource; until then finalize runs with neutral display-transform defaults.
const HOUSE_PRINT_PATH := "res://data/lapidary/print/house_print.tres"
## Board framing: camera ortho half-width in stone units (girdle radius = 1).
const ORTHO_HALF := 1.25


## Bake every frame of a clip at a quality rung.
## Returns {frames: Array[Image], fps: float, loop: bool, meta: Dictionary},
## or {} when no RenderingDevice exists or inputs are unusable.
## `shared_tracer`: optional pre-created tracer whose size matches the rung's
## internal resolution; caller keeps ownership (amortizes shader compiles).
static func bake(stone: GemStone, clip: GemClip, rung: int, lights: PackedFloat32Array,
		background := Vector3(0.30, 0.16, 0.05), shared_tracer: GemTracer = null) -> Dictionary:
	if stone == null or clip == null or stone.species == null or lights.is_empty():
		return {}
	var instance := LapidaryStoneCompiler.compile(stone)
	var policy := GemRung.policy(rung, GemRung.scatter_noisy(instance))
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
	tracer.set_background(background)

	var print_res := load_house_print()
	var frames: Array[Image] = []
	var frame_gpu_ms: Array = []
	var n := clip.frame_count()
	for i in n:
		var t := clip.frame_time(i)
		if i > 0:
			tracer.reset_accumulation()
		tracer.set_clip_sample(frame_orientation(clip, t), frame_rig_yaw_rad(clip, t),
			frame_role_mult(clip, t), ORTHO_HALF)
		var gpu_ms := 0.0
		var done := 0
		while done < spp:
			var step := mini(batch, spp - done)
			gpu_ms += tracer.accumulate(step)
			done += step
		var img := tracer.finalize_print(print_res, false, frame_exposure(clip, t))
		if out != res:
			img.resize(out, out, Image.INTERPOLATE_LANCZOS)
		frames.append(img)
		frame_gpu_ms.append(gpu_ms)

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
			"frame_gpu_ms": frame_gpu_ms,
			"wall_ms": float(Time.get_ticks_usec() - t0) / 1000.0,
			"print": "house" if print_res != null else "neutral",
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
	if ResourceLoader.exists(HOUSE_PRINT_PATH):
		return load(HOUSE_PRINT_PATH) as GemPrint
	return null


# ------------------------------------------------------------- rig packing

## Packs a designed GemLightRig into the kernel light format
## [dx,dy,dz,cos_outer, kelvin,power,cos_inner,role]. Disabled roles are skipped.
static func pack_rig_lights(rig: GemLightRig) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for l in rig.lights:
		if l == null or not l.enabled:
			continue
		var d := l.direction()
		var outer := deg_to_rad(maxf(l.angular_radius_deg, 0.1))
		var inner := outer * clampf(l.inner_fraction, 0.0, 1.0)
		var role := 1.0 if l.role == GemRigLight.Role.BLOCKER else 0.0
		arr.append_array(PackedFloat32Array([
			d.x, d.y, d.z, cos(outer),
			l.kelvin, l.power, cos(inner), role]))
	return arr


## PLACEHOLDER light set (spike pattern) used until the lighting workstream
## lands data/lapidary/rigs/*.tres. GemForge._active_rig_lights() prefers the
## rig file and falls back here; tools/package_clips.gd does the same.
static func placeholder_rig_lights() -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	_placeholder_light(arr, Vector3(-0.5, 0.8, 0.6), 14.0, 8.0, 5500.0, 3.2) # key, warm, broad
	_placeholder_light(arr, Vector3(0.65, 0.25, 0.72), 30.0, 18.0, 6500.0, 0.7) # fill, cool, soft
	_placeholder_light(arr, Vector3(0.35, -0.62, -0.70), 5.0, 2.5, 7000.0, 2.4) # kicker under pavilion
	return arr


static func placeholder_rig_background() -> Vector3:
	return Vector3(0.30, 0.16, 0.05)


static func _placeholder_light(arr: PackedFloat32Array, dir: Vector3, outer_deg: float,
		inner_deg: float, kelvin: float, power: float) -> void:
	var d := dir.normalized()
	arr.append_array(PackedFloat32Array([
		d.x, d.y, d.z, cos(deg_to_rad(outer_deg)),
		kelvin, power, cos(deg_to_rad(inner_deg)), 0.0]))
