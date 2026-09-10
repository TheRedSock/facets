class_name GemCrystalPacket
extends RefCounted
## A coherent geometric ray, separate from a modal basis coefficient.
## Isotropic o/e components have the same k and MUST be added as fields.
## This is forward field/flux bookkeeping, not a rendering BSDF.
const V := preload("res://core/lapidary/crystal_modes.gd")

static func outgoing(interface: Dictionary, source: Dictionary, target: Dictionary,
		normal: PackedFloat64Array, incident: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if interface.has("error"):
		return result
	var n := V.unit(normal)
	var incoming_flux := V.dot(incident.poynting, n)
	for side in 2:
		var first: Dictionary = interface.branches[side * 2]
		var second: Dictionary = interface.branches[side * 2 + 1]
		var medium: Dictionary = source if side == 0 else target
		# At exact optic-axis degeneracy both eigenmodes coincide too. The
		# relative k tolerance is float64 roundoff, not a coherence-length model.
		var delta := V.subtract(first.mode.k_real, second.mode.k_real)
		var coincident: bool = medium.no == medium.ne or (V.dot(delta, delta) < 1e-26 and first.mode.degenerate and second.mode.degenerate)
		var groups := [[first, second]] if coincident else [[first], [second]]
		for group in groups:
			if group[0].mode.evanescent:
				continue
			var packet := combine(group)
			var sign_value := -1.0 if side == 0 else 1.0
			packet["normal_flux"] = V.dot(packet.poynting, n)
			packet["power"] = sign_value * packet.normal_flux / incoming_flux
			packet["reflected"] = side == 0
			if packet.power > 1e-25:
				result.append(packet)
	return result

## Combine only components that share one geometric wavevector. Fields retain
## their amplitudes: multiplying power again would double-count attenuation.
static func combine(branches: Array) -> Dictionary:
	var packet: Dictionary = branches[0].mode.duplicate(true)
	# The original eigenmode's boundary flux no longer describes these fields.
	packet.erase("normal_flux")
	for field in ["E_real", "E_imag", "H_real", "H_imag"]:
		packet[field] = V.vec(0, 0, 0)
	for branch in branches:
		var ar: float = branch.amplitude[0]
		var ai: float = branch.amplitude[1]
		for field in ["E", "H"]:
			var real_name: String = field + "_real"
			var imag_name: String = field + "_imag"
			packet[real_name] = V.add(packet[real_name], V.subtract(V.scale(branch.mode[real_name], ar), V.scale(branch.mode[imag_name], ai)))
			packet[imag_name] = V.add(packet[imag_name], V.add(V.scale(branch.mode[real_name], ai), V.scale(branch.mode[imag_name], ar)))
	packet["poynting"] = V.scale(V.add(V.cross(packet.E_real, packet.H_real), V.cross(packet.E_imag, packet.H_imag)), 0.5)
	packet["ray"] = V.unit(packet.poynting)
	return packet

## Electric Jones coordinates in a chosen right-handed transverse (u,v,k)
## frame. Useful at isotropic endpoints; a crystal E need not be transverse.
static func jones(packet: Dictionary, u: PackedFloat64Array, v: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([V.dot(packet.E_real, u), V.dot(packet.E_imag, u),
		V.dot(packet.E_real, v), V.dot(packet.E_imag, v)])
