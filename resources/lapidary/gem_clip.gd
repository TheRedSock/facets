class_name GemClip
extends Resource
## A first-class authored animation: the asset gameplay consumes.
## A still is a 1-frame clip. Lighting-relative motion is part of the clip
## (stone turns under a fixed rig, or the rig orbits a fixed stone).
## There is no rotation/lighting lattice to harvest from.

@export var clip_id: StringName
@export var duration_s := 1.0
@export var fps := 12.0
@export var loop := true

@export_group("Stone track")
## One key at time 0 is a still. Motion tracks explicitly span 0..1.
## Adjacent keys take the shortest arc; subdivide full turns into quarter turns.
@export var orientation_keys: Array[GemOrientationKey] = []
## Optional monotone 0..1 -> 0..1 remap for the orientation track only.
@export var time_curve: Curve

@export_group("Rig track")
## Lighting-relative: rig yaw over the clip (degrees, on top of stone motion).
@export var rig_orbit_degrees := 0.0

@export_group("Effect track")
## Named envelopes sampled over normalized clip time and fed to tracer/print:
## "exposure_pulse", "key_boost", "rim_boost".
@export var effect_envelopes: Dictionary[String, Curve] = {}


func frame_count() -> int:
	return maxi(1, int(round(duration_s * fps)))


## Normalized time for a frame index.
func frame_time(frame: int) -> float:
	var n := frame_count()
	if n <= 1:
		return 0.0
	return float(frame) / float(n - 1 if not loop else n)


func fingerprint() -> String:
	return preload("res://resources/lapidary/content_identity.gd").digest(self)


func track_error() -> String:
	if orientation_keys.is_empty() or orientation_keys.size() > 256: return "Orientation track needs 1..256 keys"
	var previous := -1.0
	for key in orientation_keys:
		if key == null: return "Orientation key is missing"
		var why := key.validate()
		if not why.is_empty(): return why
		if key.time <= previous: return "Orientation key times must be strictly increasing"
		previous = key.time
	if orientation_keys[0].time != 0 or (orientation_keys.size()>1 and orientation_keys.back().time != 1):
		return "Orientation track must start at 0 and motion must end at 1"
	for index in range(1,orientation_keys.size()):
		if absf(orientation_keys[index-1].orientation.dot(orientation_keys[index].orientation)) < .00001:
			return "A 180-degree key interval is ambiguous; insert an intermediate orientation"
	if time_curve != null:
		if orientation_keys.size()==1: return "A still has no orientation time curve"
		var why := curve_error(time_curve,true)
		if not why.is_empty(): return "Orientation time curve: "+why
	if not is_finite(rig_orbit_degrees) or absf(rig_orbit_degrees)>360000: return "Invalid rig orbit angle"
	for name in effect_envelopes:
		if name not in ["exposure_pulse","key_boost","rim_boost"] or effect_envelopes[name]==null:
			return "Unsupported or missing clip envelope: "+name
		var why := curve_error(effect_envelopes[name],false)
		if not why.is_empty(): return name+": "+why
	if loop:
		if absf(orientation_keys[0].orientation.dot(orientation_keys.back().orientation)) < 1.0-.000001:
			return "Loop orientation endpoints must agree"
		if absf(wrapf(rig_orbit_degrees,-180,180))>.00001: return "Loop rig orbit must return to its initial direction"
		for name in effect_envelopes:
			var curve: Curve = effect_envelopes[name]
			if not is_equal_approx(curve.sample(0),curve.sample(1)): return "Loop envelope endpoints must agree: "+name
	return ""


## Conservative continuous bounds on Godot Curve's cubic Bezier control values.
## Ordered controls are a sufficient monotonicity condition for time remapping.
## See Godot 4.6 scene/resources/curve.cpp, Curve::sample_local_nocheck.
static func curve_error(curve: Curve, time_remap: bool) -> String:
	if curve.point_count<2 or curve.point_count>256: return "Curve needs 2..256 points"
	if curve.get_point_position(0).x!=0 or curve.get_point_position(curve.point_count-1).x!=1:
		return "Curve must explicitly cover normalized time 0..1"
	if time_remap and (curve.get_point_position(0).y!=0 or curve.get_point_position(curve.point_count-1).y!=1):
		return "Time remap must preserve 0 and 1 endpoints"
	var upper := 1.0 if time_remap else 1e10
	for index in range(curve.point_count-1):
		var a := curve.get_point_position(index);var b := curve.get_point_position(index+1)
		var right := curve.get_point_right_tangent(index);var left := curve.get_point_left_tangent(index+1)
		if not a.is_finite() or not b.is_finite() or not is_finite(right) or not is_finite(left) or b.x-a.x<.00001:
			return "Curve points/tangents must be finite and times separated by at least 0.00001"
		var controls := [a.y,a.y+(b.x-a.x)*right/3.0,b.y-(b.x-a.x)*left/3.0,b.y]
		for value: float in controls:
			if value<0 or value>upper: return "Curve control values leave the supported nonnegative range"
		if time_remap and (controls[0]>controls[1] or controls[1]>controls[2] or controls[2]>controls[3]):
			return "Time remap needs monotone Bezier controls"
	return ""
