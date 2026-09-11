class_name GemPresentationCompiler
extends RefCounted
## Compile framing once at the rest pose, never from noisy optical brightness.
## Bounds describe the manufactured outer host (including workmanship/rounding).
## Internal regions and missing chips do not redefine the nominal display anchor.
## Jobs retain only the resulting quaternion and camera-plane offset.
static var _cache: Dictionary = {}
static var _geometry_key := ""
static var _geometry: Dictionary = {}
const CACHE_LIMIT := 64

static func prepare(stone: GemStone, settings: GemPresentation, rest: Quaternion) -> Dictionary:
	if settings == null: return {"error": "", "native": true}
	if stone == null or stone.shape == null: return {"error": "Presentation requires a stone shape"}
	if not rest.is_finite() or rest.length_squared() < 0.0001: return {"error": "Presentation requires a finite rest orientation"}
	var error := settings.validate()
	if not error.is_empty(): return {"error": error}
	var base := Quaternion.IDENTITY
	if settings.orientation_mode == GemPresentation.OrientationMode.CUSTOM:
		base = Quaternion.from_euler(settings.orientation_deg * (PI / 180.0))
	elif settings.orientation_mode == GemPresentation.OrientationMode.SHAPE_DEFAULT and stone.shape.outline == &"pear" and stone.shape.outline_points.is_empty():
		# Native pear apex +X -> world -Y (screen down), before clip motion.
		base = Quaternion(Vector3.BACK, -PI / 2)
	var initial := GemFramePlan.canonical_orientation(GemFramePlan.canonical_orientation(rest) * base)
	var geometry_key := GemContentIdentity.digest([stone.shape, stone.cut, stone.seed, stone.size_mm,
		stone.condition.workmanship if stone.condition != null else null,
		stone.condition.rounding if stone.condition != null else null])
	var key := GemContentIdentity.digest([geometry_key, initial])
	var bounds: Dictionary
	if _cache.has(key): bounds = _cache[key]
	else:
		if geometry_key != _geometry_key:
			var compiled := LapidaryStoneCompiler.compile_geometry(stone)
			if compiled.has("compilation_error"): return {"error": compiled.compilation_error}
			if not compiled.has("mesh") and not compiled.has("analytic_shape") and not compiled.has("rounded_solid"):
				compiled.mesh = GemShapeCompiler.from_hull(compiled.planes, compiled.get("facet_ids", PackedInt32Array()))
			_geometry = compiled; _geometry_key = geometry_key
		var geometry := _geometry
		var lower := Vector3.ZERO
		var upper := Vector3.ZERO
		var body_lower := Vector3.ZERO
		var body_upper := Vector3.ZERO
		for axis in 3:
			var direction := Vector3.ZERO; direction[axis] = 1
			var native_direction := initial.inverse() * direction
			upper[axis] = _support(geometry, native_direction); lower[axis] = -_support(geometry, -native_direction)
			body_upper[axis] = _support(geometry, direction); body_lower[axis] = -_support(geometry, -direction)
		if not lower.is_finite() or not upper.is_finite(): return {"error": "Missing finite framing geometry"}
		bounds = {"lower": lower, "upper": upper, "body_center": (body_lower + body_upper) * 0.5}
		if _cache.size() >= CACHE_LIMIT: _cache.erase(_cache.keys()[0])
		_cache[key] = bounds
	var center := Vector2.ZERO
	if settings.center_mode == GemPresentation.CenterMode.REST_BOUNDS:
		var midpoint: Vector3 = (bounds.lower + bounds.upper) * 0.5
		center = Vector2(midpoint.x, midpoint.y)
	elif settings.center_mode == GemPresentation.CenterMode.CUSTOM: center = settings.custom_center
	var pivot := Vector3.ZERO
	match settings.pivot_mode:
		GemPresentation.PivotMode.REST_FRAME: pivot = initial.inverse() * Vector3(center.x, center.y, 0)
		GemPresentation.PivotMode.BODY_BOUNDS: pivot = bounds.body_center
		GemPresentation.PivotMode.CUSTOM: pivot = settings.custom_pivot
	return {"error": "", "native": false, "base": base, "initial": initial, "center": center, "pivot": pivot,
		"pixel_center": settings.center_mode != GemPresentation.CenterMode.ORIGIN, "bounds": bounds}

static func sample(prepared: Dictionary, clip_orientation: Quaternion, resolution: Vector2i, half_width: float) -> Dictionary:
	if prepared.get("native", false): return {"orientation": GemFramePlan.canonical_orientation(clip_orientation), "camera_offset": Vector2.ZERO}
	var orientation := GemFramePlan.canonical_orientation(GemFramePlan.canonical_orientation(clip_orientation) * prepared.base)
	# Q(x-p)+Q0*p-center: pure camera-plane translation around an independent pivot.
	var delta: Vector3 = orientation * prepared.pivot - prepared.initial * prepared.pivot
	var offset: Vector2 = prepared.center + Vector2(delta.x, delta.y)
	# Existing ray samples are centered at integer pixel coordinates. Align the
	# requested rest center with (width-1,height-1)/2 without changing raw probes.
	if prepared.pixel_center: offset += Vector2(half_width / resolution.x, -half_width / resolution.y)
	return {"orientation": orientation, "camera_offset": offset}

static func _support(geometry: Dictionary, direction: Vector3) -> float:
	if geometry.has("rounded_solid"): return geometry.rounded_solid.support(direction)
	if geometry.has("analytic_shape"):
		var shape: Vector4 = geometry.analytic_shape
		var radial := pow(shape.x * direction.x, 2) + pow(shape.y * direction.y, 2)
		return sqrt(radial + pow(shape.z * direction.z, 2)) if direction.z >= 0 else sqrt(radial) + shape.w * direction.z
	var maximum := -INF
	for point in geometry.mesh.vertices: maximum = maxf(maximum, direction.dot(point))
	return maximum
