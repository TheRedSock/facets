class_name GemPavilionSolver
extends RefCounted

## Derives pavilion geometry from crown parameters and material refractive index.
##
## The solver implements three gemological principles:
## 1. Critical angle: pavilion facet angles must exceed arcsin(1/n) for TIR
## 2. Rule of thirds: crown ~1/3, pavilion ~2/3 of total depth
## 3. Angle-first priority: optical performance trumps proportion targets
##
## Usage:
##   var params = GemPavilionSolver.resolve(spec, ior)
##   # params contains fully resolved pavilion + adjusted crown_height

const GemCutPrimitivesScript = preload("res://core/visuals/gem_cut_primitives.gd")

## Default IOR when none is provided (topaz-range, reasonable midpoint).
const DEFAULT_IOR := 1.62

## Empirical pavilion angle range (degrees from girdle plane).
const MIN_PAVILION_ANGLE_DEG := 38.0
const MAX_PAVILION_ANGLE_DEG := 48.0

## Crown height clamps (pre-normalization unit space).
const MIN_CROWN_HEIGHT := 0.06
const MAX_CROWN_HEIGHT := 0.32

## Default total depth ratio (total depth / horizontal diameter).
const DEFAULT_TOTAL_DEPTH_RATIO := 0.62

## Default crown:pavilion height split.
const DEFAULT_CROWN_FRACTION := 1.0 / 3.0

## Culet defaults.
## flat_size is a truncation ratio: 0.0 = point, 1.0 = truncate at lower ring.
## Typical antique values: 0.15-0.35 for a visible but modest flat culet.
const DEFAULT_CULET_FLAT_SIZE := 0.25
const DEFAULT_CULET_FLAT_SIDES := -1  # -1 = match pavilion sector count


## Compute the critical angle for a given index of refraction.
## Returns radians. For IOR < 1.0, returns PI/2 (no TIR possible).
static func compute_critical_angle(ior: float) -> float:
	if ior <= 1.0:
		return PI * 0.5
	return asin(1.0 / ior)


## Compute the target pavilion main facet angle (degrees from girdle plane)
## for a given IOR using an empirical fit against known gemological data.
##
## Reference points:
##   Diamond (2.42) -> 40.7   Quartz (1.544) -> 43.4
##   Sapphire (1.76) -> 42.7  Fluorite (1.43) -> 43.7
static func compute_target_pavilion_angle_deg(ior: float) -> float:
	# Linear fit: higher IOR permits shallower pavilion.
	var angle := 45.0 - (ior - 1.0) * 3.0
	return clampf(angle, MIN_PAVILION_ANGLE_DEG, MAX_PAVILION_ANGLE_DEG)


## Convert a pavilion main angle (degrees from girdle plane) to depth,
## given the effective girdle radius.
static func angle_to_depth(angle_deg: float, effective_radius: float) -> float:
	return effective_radius * tan(deg_to_rad(angle_deg))


## Convert a pavilion depth to the effective main facet angle (degrees from
## girdle plane), given the effective girdle radius.
static func depth_to_angle_deg(depth: float, effective_radius: float) -> float:
	if effective_radius <= 0.0001:
		return 45.0
	return rad_to_deg(atan(depth / effective_radius))


## Compute the effective girdle radius for angle<->depth conversion.
## Uses the boundary mode to estimate the maximum radial extent.
## For non-circular boundaries, returns the largest axis radius.
static func compute_effective_radius(spec) -> float:
	var base_radius := GemCutPrimitivesScript.GEM_RADIUS
	var mode := StringName(spec.girdle.get("boundary_mode", &"circle"))
	var params: Dictionary = spec.girdle.get("boundary_params", {})
	match mode:
		&"ellipse":
			var ax := float(params.get("aspect_x", 1.0))
			var ay := float(params.get("aspect_y", 1.0))
			return base_radius * maxf(ax, ay)
		&"superellipse":
			var ax := float(params.get("aspect_x", 1.0))
			var ay := float(params.get("aspect_y", 1.0))
			return base_radius * maxf(ax, ay)
		&"marquise":
			var hh := float(params.get("half_height", 1.18))
			return base_radius * maxf(1.0, hh)
		&"pear":
			var ys := float(params.get("y_stretch", 1.15))
			return base_radius * maxf(1.0, ys)
		&"kite":
			var ax := float(params.get("aspect_x", 1.0))
			var ay := float(params.get("aspect_y", 1.0))
			return base_radius * maxf(ax, ay)
	# Circle, heart, and unknown modes: use base radius.
	return base_radius


## Resolve complete pavilion parameters from a spec and IOR.
##
## Returns a Dictionary with keys:
##   crown_height, pavilion_depth, girdle_thickness,
##   upper_depth_ratio, lower_depth_ratio, upper_scale, lower_scale,
##   rotation_fraction, sector_count,
##   culet_style, culet_flat_size, culet_flat_sides,
##   effective_pavilion_angle_deg, critical_angle_deg
##
## Spec pavilion keys act as overrides: if present and not flagged auto,
## the explicit value is used. Otherwise the solver derives it.
static func resolve(spec, ior: float = DEFAULT_IOR) -> Dictionary:
	var pav: Dictionary = spec.pavilion if spec.pavilion is Dictionary else {}
	var cul: Dictionary = spec.culet if spec.culet is Dictionary else {}
	var auto_depth: bool = _get_bool(pav, "auto_depth", true)
	var auto_crown: bool = _get_bool(pav, "auto_crown_height", true)

	# --- IOR-derived targets ---
	var critical_angle_deg := rad_to_deg(compute_critical_angle(ior))
	var target_angle_deg: float = float(pav.get("target_angle_degrees", -1.0))
	if target_angle_deg < 0.0:
		target_angle_deg = compute_target_pavilion_angle_deg(ior)

	var effective_radius := compute_effective_radius(spec)
	var girdle_thickness: float = spec.get_girdle_thickness()

	# --- Pavilion depth ---
	var pavilion_depth: float
	if auto_depth:
		pavilion_depth = angle_to_depth(target_angle_deg, effective_radius)
	else:
		pavilion_depth = spec.get_pavilion_depth()

	# --- Crown height (rule of thirds, angle-first) ---
	var crown_height: float
	if auto_crown:
		var total_depth_ratio := float(pav.get("total_depth_ratio", DEFAULT_TOTAL_DEPTH_RATIO))
		var crown_fraction := DEFAULT_CROWN_FRACTION
		var raw_split = pav.get("crown_pavilion_split", null)
		if raw_split is Array and raw_split.size() >= 2:
			var c := float(raw_split[0])
			var p := float(raw_split[1])
			if c + p > 0.0:
				crown_fraction = c / (c + p)

		# Target total depth from width ratio.
		var diameter := effective_radius * 2.0
		var target_total_depth := diameter * total_depth_ratio

		# Crown height = fraction of non-girdle depth, or what remains after pavilion.
		var available_for_crown := target_total_depth - pavilion_depth - girdle_thickness
		crown_height = available_for_crown * crown_fraction / (1.0 - crown_fraction) if crown_fraction < 1.0 else available_for_crown

		# With angle-first, crown absorbs the slack. But if pavilion is very deep
		# (low IOR), crown gets compressed. Apply clamps.
		crown_height = clampf(crown_height, MIN_CROWN_HEIGHT, MAX_CROWN_HEIGHT)

		# If the spec has an explicit crown height and auto_crown is still true
		# but pavilion auto is false, honour the crown height from the spec.
		if not auto_depth and spec.crown.has("height"):
			crown_height = spec.get_crown_height()
	else:
		crown_height = spec.get_crown_height()

	# --- Effective angle (diagnostic) ---
	var effective_angle_deg := depth_to_angle_deg(pavilion_depth, effective_radius)

	# --- Ring parameters (use spec overrides or defaults) ---
	var upper_depth_ratio := float(pav.get("upper_depth_ratio", 0.48))
	var lower_depth_ratio := float(pav.get("lower_depth_ratio", 0.82))
	var upper_scale := float(pav.get("upper_scale", 0.52))
	var lower_scale := float(pav.get("lower_scale", 0.20))
	var rotation_fraction := float(pav.get("rotation_fraction", 0.0))

	# --- Sector count ---
	var sector_count: int = spec.get_pavilion_sector_count()
	if sector_count <= 0:
		sector_count = spec.get_symmetry_sector_count()
	if sector_count <= 0:
		# Derive from ring point count for non-radial families.
		var ring_loops: Array = spec.get_ring_point_loops()
		if not ring_loops.is_empty():
			sector_count = ring_loops[0].size()
		# Fall back to outer points (radiant/princess).
		if sector_count <= 0:
			var outer: Array[Vector2] = spec.get_outer_points()
			sector_count = outer.size()

	# --- Culet ---
	var culet_style := String(cul.get("style", "point"))
	var culet_flat_size := float(cul.get("flat_size", DEFAULT_CULET_FLAT_SIZE))
	var culet_flat_sides := int(cul.get("flat_sides", DEFAULT_CULET_FLAT_SIDES))
	if culet_flat_sides < 0:
		culet_flat_sides = maxi(sector_count, 3)

	return {
		"crown_height": crown_height,
		"pavilion_depth": pavilion_depth,
		"girdle_thickness": girdle_thickness,
		"upper_depth_ratio": upper_depth_ratio,
		"lower_depth_ratio": lower_depth_ratio,
		"upper_scale": upper_scale,
		"lower_scale": lower_scale,
		"rotation_fraction": rotation_fraction,
		"sector_count": sector_count,
		"culet_style": culet_style,
		"culet_flat_size": culet_flat_size,
		"culet_flat_sides": culet_flat_sides,
		"effective_pavilion_angle_deg": effective_angle_deg,
		"critical_angle_deg": critical_angle_deg,
	}


## Validate resolved pavilion parameters against optical constraints.
## Returns a Dictionary with "errors" and "warnings" arrays.
static func validate_optics(params: Dictionary, ior: float = DEFAULT_IOR) -> Dictionary:
	var report := {
		"errors": PackedStringArray(),
		"warnings": PackedStringArray(),
	}
	var critical_deg := rad_to_deg(compute_critical_angle(ior))
	var effective_deg: float = params.get("effective_pavilion_angle_deg", 0.0)

	if effective_deg < critical_deg:
		report["errors"].append(
			"Pavilion angle %.1f° is below critical angle %.1f° for IOR %.3f — TIR will fail" % [
				effective_deg, critical_deg, ior])
	elif effective_deg < critical_deg + 2.0:
		report["warnings"].append(
			"Pavilion angle %.1f° is within 2° of critical angle %.1f° — marginal TIR" % [
				effective_deg, critical_deg])

	var depth: float = params.get("pavilion_depth", 0.0)
	var crown: float = params.get("crown_height", 0.0)
	var girdle: float = params.get("girdle_thickness", 0.0)
	var total := crown + girdle + depth
	if total > 0.001:
		var crown_ratio := crown / total
		if crown_ratio < 0.15:
			report["warnings"].append(
				"Crown is only %.0f%% of total depth — unusually flat" % [crown_ratio * 100.0])
		elif crown_ratio > 0.45:
			report["warnings"].append(
				"Crown is %.0f%% of total depth — unusually tall" % [crown_ratio * 100.0])

	return report


static func _get_bool(dict: Dictionary, key: String, default_value: bool) -> bool:
	if not dict.has(key):
		return default_value
	var value = dict[key]
	if value is bool:
		return value
	return bool(value)
