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


static func compile(rig: GemLightRig) -> GemLighting:
	assert(rig != null, "GemRigCompiler: rig missing")
	var result := GemLighting.new()
	for role in ROLE_ORDER + [GemRigLight.Role.BLOCKER]:
		for light in rig.lights:
			if light.role == role and light.enabled:
				_append(result, light)
	var background_offset := result.add_spectrum(GemSpectrumCompiler.compile(rig.background_spectrum))
	result.background = Vector4(rig.bg_zenith, rig.bg_horizon, rig.bg_below, background_offset)
	if rig.white_spectrum != null:
		result.white_xyz = GemColorimetry.spectrum_xyz(GemSpectrumCompiler.compile(rig.white_spectrum))
		assert(result.white_xyz.y > 0.0, "Print neutral must have visible energy")
		result.white_xyz /= result.white_xyz.y
	return result


static func _append(result: GemLighting, light: GemRigLight) -> void:
	var d := light.direction()
	var outer := cos(deg_to_rad(light.angular_radius_deg))
	var inner := cos(deg_to_rad(light.angular_radius_deg * clampf(light.inner_fraction, 0.05, 0.98)))
	var role: float = ROLE_KERNEL.get(light.role, 0.0)
	var offset := result.add_spectrum(GemSpectrumCompiler.compile(light.spectrum))
	result.lights.append_array(PackedFloat32Array([
		d.x, d.y, d.z, outer,
		offset, light.power, inner, role,
	]))
