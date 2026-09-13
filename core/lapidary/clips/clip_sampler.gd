class_name GemClipSampler
extends RefCounted
## Shared deterministic clip sampling for preview and frozen asset jobs.
const ORTHO_HALF := 1.25

## Stone orientation for a normalized clip time: rest tilt composed with the
## motion track (motion first, then tilt — the turntable axis tilts with the
## stone). STILL is the only motion-free mode.
static func frame_orientation(clip: GemClip, t: float) -> Quaternion:
	var tilt := clip.rest_tilt_deg
	var rest := Quaternion.from_euler(Vector3(
		deg_to_rad(tilt.x), deg_to_rad(tilt.y), deg_to_rad(tilt.z)))
	assert(clip.stone_motion in [GemClip.StoneMotion.STILL, GemClip.StoneMotion.TURNTABLE], "Unsupported clip motion")
	if clip.stone_motion == GemClip.StoneMotion.STILL:
		return rest
	var p := clampf(t, 0.0, 1.0)
	if clip.easing != null:
		p = clip.easing.sample(p)
	var axis := clip.turntable_axis
	assert(axis.length_squared() >= 0.0001, "Turntable needs a nonzero axis")
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
