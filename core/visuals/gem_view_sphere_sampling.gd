class_name GemViewSphereSampling
extends RefCounted

## Fibonacci sphere directions and analytical pitch/yaw decomposition
## consistent with the tracer convention: basis = RotY(yaw) * RotX(pitch),
## view_dir = basis^{-1} * (0,0,1).

const MIN_FIBONACCI_POINTS := 16
const MAX_FIBONACCI_POINTS := 50000


## Informational angular spacing for showroom direction count (corrected 4π/n formula).
static func showroom_angular_resolution_degrees(direction_count: int) -> float:
	var n := maxi(direction_count, 1)
	return rad_to_deg(sqrt(4.0 * PI / float(n)))


static func fibonacci_point_count_for_theta_degrees(theta_degrees: float) -> int:
	var theta := maxf(theta_degrees, 0.25)
	var theta_rad := deg_to_rad(theta)
	var n := int(ceil(TAU / (theta_rad * theta_rad)))
	return clampi(n, MIN_FIBONACCI_POINTS, MAX_FIBONACCI_POINTS)


static func _least_aligned_world_axis(forward: Vector3) -> Vector3:
	var ax := absf(forward.x)
	var ay := absf(forward.y)
	var az := absf(forward.z)
	if ax <= ay and ax <= az:
		return Vector3.RIGHT
	if ay <= az:
		return Vector3.UP
	return Vector3.BACK


## Stable orthonormal camera frame with basis.z = view direction (model space).
## Columns: right, up, forward — matches tracer row convention for view_basis.
static func build_camera_frame_for_direction(view_dir: Vector3) -> Basis:
	var z := view_dir.normalized()
	if z.length_squared() < 1e-10:
		z = Vector3.BACK
	var up_ref := _least_aligned_world_axis(z)
	var x := up_ref.cross(z)
	if x.length_squared() < 1e-10:
		x = Vector3.RIGHT.cross(z)
	x = x.normalized()
	var y := z.cross(x).normalized()
	return Basis(x, y, z).orthonormalized()


## Full showroom orientation: camera frame + local roll around view axis (radians).
static func build_showroom_orientation(view_dir: Vector3, roll_radians: float) -> Basis:
	var basis := build_camera_frame_for_direction(view_dir)
	if is_zero_approx(roll_radians):
		return basis
	var cr := cos(roll_radians)
	var sr := sin(roll_radians)
	var rx: Vector3 = basis.x
	var ry: Vector3 = basis.y
	basis.x = cr * rx + sr * ry
	basis.y = -sr * rx + cr * ry
	return Basis(basis.x, basis.y, basis.z).orthonormalized()


static func build_fibonacci_unit_vectors(count: int) -> PackedVector3Array:
	var n := clampi(count, MIN_FIBONACCI_POINTS, MAX_FIBONACCI_POINTS)
	var out := PackedVector3Array()
	out.resize(n)
	var golden := PI * (3.0 - sqrt(5.0))
	for i in n:
		var y := 1.0 - (float(i) / float(max(n - 1, 1))) * 2.0
		y = clampf(y, -1.0, 1.0)
		var r := sqrt(maxf(1.0 - y * y, 0.0))
		var theta := golden * float(i)
		var x := cos(theta) * r
		var z := sin(theta) * r
		out[i] = Vector3(x, y, z).normalized()
	return out


## Analytical pitch/yaw from view direction. Deterministic — no iterative search.
## The tracer convention: view_dir = (-sin(yaw), sin(pitch)*cos(yaw), cos(pitch)*cos(yaw)).
## Returns Vector3(pitch_degrees, yaw_degrees, 0.0).
static func pitch_yaw_roll_for_view_dir(
	view_dir_model: Vector3,
	_visual,
	_mesh_includes_cut_rotation: bool,
) -> Vector3:
	var d := view_dir_model.normalized()
	if d.is_zero_approx():
		d = Vector3.BACK
	# cos(yaw)^2 = d.y^2 + d.z^2. When this is near zero the view is pure
	# side-on and pitch is degenerate — convention: pitch = 0.
	var cos_yaw_sq := d.y * d.y + d.z * d.z
	if cos_yaw_sq < 1e-10:
		var early_yaw_deg := -90.0 if d.x > 0.0 else 90.0
		return Vector3(0.0, early_yaw_deg, 0.0)
	var cos_yaw_mag := sqrt(cos_yaw_sq)
	# Hemisphere: keep pitch in [-90, 90] so cos(pitch) >= 0.
	# sign(cos(yaw)) = sign(d.z) when cos(pitch) > 0. For d.z = 0 (pitch = +/-90)
	# use positive cos_yaw so atan2 resolves pitch correctly from the d.y sign.
	var cos_yaw := cos_yaw_mag if d.z >= 0.0 else -cos_yaw_mag
	var yaw_deg := rad_to_deg(atan2(-d.x, cos_yaw))
	var pitch_deg := rad_to_deg(atan2(d.y / cos_yaw, d.z / cos_yaw))
	return Vector3(pitch_deg, yaw_deg, 0.0)


## Compute the 2D rotation (radians) to apply to a traced image so the gem
## appears upright on screen. Positive = counterclockwise (screen space).
## Camera basis follows the tracer convention: RotY(yaw) * RotX(pitch).
static func upright_correction_radians(pitch_deg: float, yaw_deg: float, roll_deg: float = 0.0) -> float:
	var basis := Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	basis = Basis(Vector3.UP, deg_to_rad(yaw_deg)) * basis
	if not is_zero_approx(roll_deg):
		basis = Basis(Vector3.BACK, deg_to_rad(roll_deg)) * basis
	var cam_up := basis * Vector3.UP
	var cam_forward := basis * Vector3(0.0, 0.0, -1.0)
	# Desired up: project world-Y perpendicular to the view direction.
	var view_dir := -cam_forward
	var desired_up := Vector3.UP - Vector3.UP.dot(view_dir) * view_dir
	if desired_up.length_squared() < 0.001:
		# Near-pole view (looking along world Y) — fall back to world -Z as up.
		desired_up = Vector3.BACK - Vector3.BACK.dot(view_dir) * view_dir
	if desired_up.length_squared() < 0.0001:
		return 0.0
	desired_up = desired_up.normalized()
	return cam_up.signed_angle_to(desired_up, cam_forward)
