class_name GemClip
extends Resource
## A first-class authored animation: the asset gameplay consumes.
## A still is a 1-frame clip. Lighting-relative motion is part of the clip
## (stone turns under a fixed rig, or the rig orbits a fixed stone).
## There is no rotation/lighting lattice to harvest from.

enum StoneMotion { STILL, TURNTABLE }

@export var clip_id: StringName
@export var duration_s := 1.0
@export var fps := 12.0
@export var loop := true

@export_group("Stone track")
@export var stone_motion := StoneMotion.STILL
## Rest orientation (face-up tilt etc.), applied before motion.
@export var rest_tilt_deg := Vector3.ZERO
@export var turntable_axis := Vector3(0, 1, 0)
@export var turntable_degrees := 90.0
## 0..1 -> 0..1 time remap for the motion (null = linear).
@export var easing: Curve

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
