class_name GemRigCompiler
extends RefCounted
## Packs a GemLightRig into the kernel light buffer (KERNEL_CONTRACT.md).
## Each light carries an explicit role id (0 key, 1 fill, 2 rim, 3 bounce,
## 4 blocker). Ordering is KEY, FILL, RIM, BOUNCE then blockers for
## deterministic buffer layout; the shader indexes role_mult by role field.

const ROLE_ORDER := [
	GemRigLight.Role.KEY,
	GemRigLight.Role.FILL,
	GemRigLight.Role.RIM,
	GemRigLight.Role.BOUNCE,
]

const ROLE_KERNEL := {
	GemRigLight.Role.KEY: 0.0,
	GemRigLight.Role.FILL: 1.0,
	GemRigLight.Role.RIM: 2.0,
	GemRigLight.Role.BOUNCE: 3.0,
	GemRigLight.Role.BLOCKER: 4.0,
}


static func pack(rig: GemLightRig) -> PackedFloat32Array:
	assert(rig != null and not rig.lights.is_empty(), "GemRigCompiler.pack: rig missing or empty")
	var arr := PackedFloat32Array()
	for role in ROLE_ORDER:
		for light in rig.lights:
			if light.role == role and light.enabled:
				_append(arr, light)
	for light in rig.lights:
		if light.role == GemRigLight.Role.BLOCKER and light.enabled:
			_append(arr, light)
	assert(not arr.is_empty(), "GemRigCompiler.pack: no enabled lights")
	return arr


## Everything about the rig that is not a light: the background gradient with
## its Planckian kelvin (0 = flat) and the as-shot white the print adapts to D65.
## Consumed by GemTracer.set_environment().
static func environment(rig: GemLightRig) -> Dictionary:
	assert(rig != null, "GemRigCompiler.environment: rig missing")
	return {
		"bg": Vector4(rig.bg_zenith, rig.bg_horizon, rig.bg_below, rig.bg_kelvin),
		"white_kelvin": rig.white_kelvin,
	}


static func _append(arr: PackedFloat32Array, light: GemRigLight) -> void:
	var d := light.direction()
	var outer := cos(deg_to_rad(light.angular_radius_deg))
	var inner := cos(deg_to_rad(light.angular_radius_deg * clampf(light.inner_fraction, 0.05, 0.98)))
	var role: float = ROLE_KERNEL.get(light.role, 0.0)
	arr.append_array(PackedFloat32Array([
		d.x, d.y, d.z, outer,
		light.kelvin, light.power, inner, role,
	]))
