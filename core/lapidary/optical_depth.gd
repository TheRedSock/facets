class_name GemOpticalDepth
extends RefCounted
## CPU reference for integrated concentration along straight path segments.
## Integral[1+c sin(k·x+phase)] = length * [1+c sin(midphase)sinc(halfphase)].
## The centered form avoids cancellation when a ray is parallel to the bands.
## Transmittance uses exp(-alpha * column * size_mm), never a midpoint alpha.
static func zoning_column(position: Vector3, direction: Vector3, length: float,
		axis: Vector3, frequency: float, contrast: float, phase: float) -> float:
	if contrast == 0.0 or length <= 0.0:
		return maxf(length, 0.0)
	var half_phase := 0.5 * length * _dot(direction, axis) * frequency * PI
	var sinc := 1.0 - half_phase * half_phase / 6.0 if absf(half_phase) < 0.001 else sin(half_phase) / half_phase
	var mid_phase := _dot(position, axis) * frequency * PI + phase + half_phase
	return maxf(0.0, length * (1.0 + contrast * sin(mid_phase) * sinc))


static func _dot(a: Vector3, b: Vector3) -> float:
	# GDScript scalar arithmetic retains double precision in the CPU reference.
	return float(a.x) * b.x + float(a.y) * b.y + float(a.z) * b.z
