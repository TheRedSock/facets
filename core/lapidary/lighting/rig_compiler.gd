class_name GemRigCompiler
extends RefCounted
## Packs a GemLightRig into the kernel light buffer (KERNEL_CONTRACT.md).
## Emitters are ordered KEY, FILL, RIM, BOUNCE (kernel per-role power
## multipliers map by index), blockers appended after.

const ROLE_ORDER := [
	GemRigLight.Role.KEY,
	GemRigLight.Role.FILL,
	GemRigLight.Role.RIM,
	GemRigLight.Role.BOUNCE,
]


static func pack(rig: GemLightRig) -> PackedFloat32Array:
	var arr := PackedFloat32Array()
	for role in ROLE_ORDER:
		for light in rig.lights:
			if light.role == role and light.enabled:
				_append(arr, light, 0.0)
	for light in rig.lights:
		if light.role == GemRigLight.Role.BLOCKER and light.enabled:
			_append(arr, light, 1.0)
	return arr


static func background(rig: GemLightRig) -> Vector3:
	return Vector3(rig.bg_zenith, rig.bg_horizon, rig.bg_below)


static func _append(arr: PackedFloat32Array, light: GemRigLight, role_flag: float) -> void:
	var d := light.direction()
	var outer := cos(deg_to_rad(light.angular_radius_deg))
	var inner := cos(deg_to_rad(light.angular_radius_deg * clampf(light.inner_fraction, 0.05, 0.98)))
	arr.append_array(PackedFloat32Array([
		d.x, d.y, d.z, outer,
		light.kelvin, light.power, inner, role_flag,
	]))
