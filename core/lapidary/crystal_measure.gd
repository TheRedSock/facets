class_name GemCrystalMeasure
extends RefCounted
## Ray-solid-angle measure on the normalized wavevector surface.
## Lax & Nelson (1975), JOSA65,668: dOmega_ray*cos(beta)/K and L*K
## are invariant at a lossless interface (transmittance excluded).
## https://doi.org/10.1364/JOSA.65.000668
## These conversions alone do not define an adjoint polarized BSDF.
const V := preload("res://core/lapidary/crystal_modes.gd")

static func curvature(mode: Dictionary, medium: Dictionary) -> float:
	if mode.evanescent:
		return NAN
	var no: float = medium.no
	var ne: float = medium.ne
	if not mode.extraordinary:
		return 1.0 / (no * no)
	# For k^T M k=1, Gaussian curvature is det(M)/|M*k|^4.
	# M has eigenvalues 1/ne^2,1/ne^2,1/no^2. k is divided by k0,
	# so the common dimensional k0 factor cancels in interface ratios.
	var gradient := V.metric(mode.k_real, V.unit(medium.axis), no, ne)
	var squared_norm := V.dot(gradient, gradient)
	return 1.0 / (no * no * pow(ne, 4) * squared_norm * squared_norm)

## L_out / L_in for a forward ray, before modal power loss is applied.
static func forward_radiance_factor(incoming: Dictionary, source: Dictionary,
		outgoing: Dictionary, target: Dictionary) -> float:
	return curvature(incoming, source) / curvature(outgoing, target)

## When a camera path walks from current to next, it evaluates physical
## radiance travelling next -> current. Isotropic reduction: (n_current/n_next)^2.
static func camera_radiance_factor(current: Dictionary, current_medium: Dictionary,
		next: Dictionary, next_medium: Dictionary) -> float:
	return curvature(next, next_medium) / curvature(current, current_medium)
