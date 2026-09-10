class_name GemVolumeField
extends Resource
## Smooth spatial variation in a specimen's bulk material.
## The default profile is max(0, 1-|local_position|²)^3 in an oriented ellipsoid.
## Overlapping fields add coefficients; there is no artificial optical boundary.
## This is an effective-medium construction, not a crystal-growth simulation.
@export var center_mm := Vector3.ZERO
@export var radius_mm := Vector3.ONE
@export var orientation := Quaternion.IDENTITY
enum Profile { COMPACT_ELLIPSOID, PLANAR_TRANSITION }
## Planar transition: local z <= -radius.z is zero, >= radius.z is one.
## A quintic C2 transition joins them; local x/y do not limit its extent.
@export var profile := Profile.COMPACT_ELLIPSOID
## Additional active absorbers at density=1, using the host species, atom
## density and crystal frame. These do not change refraction or phase function.
@export var absorbers: Array[GemAbsorber] = []
## Adds a multiple of the host's absorption spectrum at the density maximum.
@export var absorption_concentration := 0.0
## Adds wavelength-independent scattering at the density maximum, in /mm.
## Uses the host HG phase function. Resolved silk/crystals need other models.
@export var scatter_per_mm := 0.0
@export_multiline var source_note := "Authored spatial effective-medium field; not a measured inclusion distribution."

func validate() -> PackedStringArray:
	var errors := PackedStringArray()
	if profile not in [Profile.COMPACT_ELLIPSOID, Profile.PLANAR_TRANSITION] or absorbers.size()>64:
		errors.append("Unknown spatial profile or too many absorption terms")
	for term in absorbers:
		if term==null:
			errors.append("Spatial absorber is missing")
	if not center_mm.is_finite() or not radius_mm.is_finite():
		errors.append("Volume field coordinates must be finite")
	if minf(radius_mm.x, minf(radius_mm.y, radius_mm.z)) < 0.001:
		errors.append("Volume field radii must be at least 0.001 mm; use bulk coefficients below that scale")
	if maxf(radius_mm.x, maxf(radius_mm.y, radius_mm.z)) > 10000.0 or center_mm.abs().length() > 100000.0:
		errors.append("Volume field exceeds the supported millimeter coordinate range")
	if not orientation.is_finite() or absf(orientation.length_squared() - 1.0) > 0.00001:
		errors.append("Volume field orientation must be a unit quaternion")
	if not is_finite(absorption_concentration) or absorption_concentration < 0.0 or absorption_concentration > 10000.0:
		errors.append("Volume concentration must be finite and in [0,10000]")
	if not is_finite(scatter_per_mm) or scatter_per_mm < 0.0 or scatter_per_mm > 1000.0:
		errors.append("Volume scattering must be finite and in [0,1000] per mm")
	return errors

func packed(absorption_offset := -1, parallel := false) -> PackedByteArray:
	assert(validate().is_empty(), str(validate()))
	var bytes:=PackedFloat32Array([center_mm.x, center_mm.y, center_mm.z, absorption_concentration,
		radius_mm.x, radius_mm.y, radius_mm.z, scatter_per_mm,
		orientation.x, orientation.y, orientation.z, orientation.w]).to_byte_array()
	bytes.resize(64)
	bytes.encode_s32(48,absorption_offset)
	bytes.encode_s32(52,1 if parallel else 0)
	bytes.encode_s32(56,profile)
	return bytes

func density(point_mm: Vector3) -> float:
	var local := (orientation.inverse() * (point_mm - center_mm)) / radius_mm
	if profile==Profile.PLANAR_TRANSITION:return _transition(local.z)
	var value := maxf(0.0, 1.0 - local.length_squared())
	return value * value * value

func column(origin_mm: Vector3, direction: Vector3, distance_mm: float) -> float:
	var local := (orientation.inverse() * (origin_mm - center_mm)) / radius_mm
	var velocity := (orientation.inverse() * direction) / radius_mm
	if distance_mm<=0:return 0.0
	if profile==Profile.PLANAR_TRANSITION:return _transition_column(local.z,velocity.z,distance_mm)
	var speed_squared := velocity.length_squared()
	var closest := -local.dot(velocity) / speed_squared
	var perpendicular := local + velocity * closest
	var height := 1.0 - perpendicular.length_squared()
	if height <= 0.0 or distance_mm <= 0.0:
		return 0.0
	var half_span := sqrt(height / speed_squared)
	var begin := maxf(0.0, closest - half_span)
	var end := minf(distance_mm, closest + half_span)
	if end <= begin:
		return 0.0
	# Four-point Gauss-Legendre integrates the degree-six chord exactly.
	# Positive weights avoid subtracting nearly equal antiderivatives at grazing.
	var midpoint := (begin + end) * 0.5
	var half_length := (end - begin) * 0.5
	var total := 0.0
	for pair: Vector2 in [Vector2(0.3399810435848563, 0.6521451548625461), Vector2(0.8611363115940526, 0.3478548451374538)]:
		for sign_value: float in [-1.0, 1.0]:
			var offset := midpoint + sign_value * pair.x * half_length - closest
			var value := maxf(0.0, height - speed_squared * offset * offset)
			total += pair.y * value * value * value
	return total * half_length

static func _transition(z:float)->float:
	var u:=clampf(.5*(z+1),0,1)
	return u*u*u*(10+u*(-15+6*u))

static func _transition_column(origin:float,velocity:float,distance:float)->float:
	if velocity==0:return distance*_transition(origin)
	var low:=(-1-origin)/velocity
	var high:=(1-origin)/velocity
	var begin:=maxf(0,minf(low,high))
	var end:=minf(distance,maxf(low,high))
	var plateau:=distance-clampf(high,0,distance) if velocity>0 else clampf(high,0,distance)
	if end<=begin:return plateau
	var mid:=(begin+end)*.5
	var half:=(end-begin)*.5
	var total:=0.0
	for pair:Vector2 in [Vector2(.3399810435848563,.6521451548625461),Vector2(.8611363115940526,.3478548451374538)]:
		for sign_value in [-1.0,1.0]:
			total+=pair.y*_transition(origin+velocity*(mid+sign_value*pair.x*half))
	return plateau+total*half
