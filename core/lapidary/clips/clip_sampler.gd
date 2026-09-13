class_name GemClipSampler
extends RefCounted
## Shared deterministic clip sampling for preview and frozen asset jobs.
## Absolute orientation, shortest-arc interpolation between explicit keys.
static func frame_orientation(clip: GemClip, t: float) -> Quaternion:
	assert(is_finite(t) and not clip.orientation_keys.is_empty(), "Sample an admitted orientation track at finite time")
	var keys := clip.orientation_keys
	if keys.size()==1: return keys[0].orientation
	var p := clampf(t, 0.0, 1.0)
	if clip.time_curve!=null: p=clip.time_curve.sample(p)
	for index in range(1,keys.size()):
		if p<=keys[index].time:
			var a:=keys[index-1];var b:=keys[index]
			return a.orientation.slerp(b.orientation,(p-a.time)/(b.time-a.time)).normalized()
	return keys.back().orientation


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
