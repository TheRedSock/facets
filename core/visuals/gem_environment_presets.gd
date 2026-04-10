class_name GemEnvironmentPresets
extends RefCounted

## Environment preset definitions externalized from the native trace kernel.
## Edit these dictionaries to change traced environment lighting without
## recompiling the native extension. The kernel accepts these via the request
## dictionary's "environment_profile" key.
##
## Each preset defines: sky gradient, ground colors, light cards with spectral
## temperature and gradient properties, a blocker (negative light), and a
## virtual ground plane bounce surface.
##
## Card fields:
##   dir             - Local-space light direction (normalized by kernel)
##   color           - Center color of the card
##   sharp_power     - Specular exponent at roughness=0
##   broad_power     - Specular exponent at roughness=1
##   sharp_strength  - Card energy at roughness=0
##   broad_strength  - Card energy at roughness=1
##   temperature_kelvin - Planck blackbody temperature (0 = use color directly)
##   edge_color      - Color at card lobe periphery (transparent = auto from color)
##   gradient_power  - Controls center-to-edge gradient ramp shape

const PRESET_NEUTRAL := 0
const PRESET_DARK_STUDIO := 1
const PRESET_GEM_BOOTH := 2
const PRESET_GAMEPLAY_STUDIO := 3
const PRESET_DEEP_COLOR := 4


static func resolve_preset(preset_id: int) -> Dictionary:
	match preset_id:
		PRESET_DARK_STUDIO: return _dark_studio()
		PRESET_GEM_BOOTH: return _gem_booth()
		PRESET_GAMEPLAY_STUDIO: return _gameplay_studio()
		PRESET_DEEP_COLOR: return _deep_color()
		_: return _neutral()


static func get_preset_names() -> Dictionary:
	return {
		PRESET_NEUTRAL: "Neutral Sky",
		PRESET_DARK_STUDIO: "Dark Studio",
		PRESET_GEM_BOOTH: "Gem Booth",
		PRESET_GAMEPLAY_STUDIO: "Gameplay Studio",
		PRESET_DEEP_COLOR: "Deep Color",
	}


static func _make_card(
	dir: Vector3,
	color: Color,
	sharp_power: float,
	broad_power: float,
	sharp_strength: float,
	broad_strength: float,
	temperature_kelvin: float = 0.0,
	edge_color: Color = Color.TRANSPARENT,
	gradient_power: float = 1.0,
) -> Dictionary:
	return {
		"dir": dir,
		"color": color,
		"sharp_power": sharp_power,
		"broad_power": broad_power,
		"sharp_strength": sharp_strength,
		"broad_strength": broad_strength,
		"temperature_kelvin": temperature_kelvin,
		"edge_color": edge_color,
		"gradient_power": gradient_power,
	}


static func _neutral() -> Dictionary:
	return {
		"sky_low": Color(0.16, 0.19, 0.26, 1.0),
		"sky_top": Color(0.36, 0.42, 0.54, 1.0),
		"horizon": Color(0.68, 0.54, 0.36, 1.0),
		"ground_dark": Color(0.020, 0.016, 0.013, 1.0),
		"ground_lift": Color(0.10, 0.078, 0.052, 1.0),
		"cards": [
			# Key: 5500K daylight, warm center to neutral edge
			_make_card(Vector3(0.00, 0.24, 0.97), Color(1.0, 0.96, 0.88, 1.0), 900.0, 90.0, 4.6, 2.1,
				5500.0, Color(0.94, 0.96, 1.0, 1.0), 0.7),
			# Right fill: 6200K cool
			_make_card(Vector3(0.56, 0.18, 0.80), Color(0.95, 0.92, 0.98, 1.0), 48.0, 14.0, 0.42, 0.28,
				6200.0, Color(0.90, 0.92, 1.0, 1.0), 0.8),
			# Left fill: neutral
			_make_card(Vector3(-0.74, 0.14, 0.62), Color(1.0, 0.99, 0.97, 1.0), 64.0, 18.0, 0.36, 0.24,
				6200.0, Color(0.93, 0.96, 1.0, 1.0), 0.8),
		],
		"blocker_dir": Vector3(-0.18, -0.30, 0.94),
		"blocker_power": 10.0,
		"blocker_strength": 0.19,
		"ground_albedo": 0.15,
		"ground_tint": Color(0.92, 0.87, 0.80, 1.0),
		"ground_distance": 0.8,
	}


static func _dark_studio() -> Dictionary:
	return {
		"sky_low": Color(0.024, 0.026, 0.036, 1.0),
		"sky_top": Color(0.072, 0.078, 0.11, 1.0),
		"horizon": Color(0.20, 0.15, 0.11, 1.0),
		"ground_dark": Color(0.005, 0.005, 0.006, 1.0),
		"ground_lift": Color(0.026, 0.021, 0.016, 1.0),
		"cards": [
			# Key: 4800K warm studio, gradient to cooler edge
			_make_card(Vector3(0.02, 0.44, 0.90), Color(1.0, 0.99, 0.97, 1.0), 1150.0, 14.0, 4.4, 2.40,
				4800.0, Color(0.94, 0.96, 1.0, 1.0), 0.65),
			# Right fill: 5800K cool
			_make_card(Vector3(0.72, 0.12, 0.68), Color(0.96, 0.94, 1.0, 1.0), 120.0, 8.0, 0.52, 0.42,
				5800.0, Color(0.90, 0.93, 1.0, 1.0), 0.8),
			# Left fill: warm white
			_make_card(Vector3(-0.78, 0.18, 0.56), Color(1.0, 0.985, 0.95, 1.0), 220.0, 10.0, 0.56, 0.44,
				5800.0, Color(0.93, 0.95, 1.0, 1.0), 0.8),
			# Under: warm bounce
			_make_card(Vector3(-0.10, -0.70, 0.70), Color(1.0, 0.90, 0.80, 1.0), 42.0, 6.0, 0.26, 0.20,
				4000.0),
		],
		"blocker_dir": Vector3(-0.26, -0.30, 0.92),
		"blocker_power": 10.0,
		"blocker_strength": 0.30,
		"ground_albedo": 0.08,
		"ground_tint": Color(0.85, 0.80, 0.72, 1.0),
		"ground_distance": 0.8,
	}


static func _gem_booth() -> Dictionary:
	return {
		"sky_low": Color(0.08, 0.09, 0.12, 1.0),
		"sky_top": Color(0.21, 0.24, 0.29, 1.0),
		"horizon": Color(0.42, 0.36, 0.28, 1.0),
		"ground_dark": Color(0.016, 0.013, 0.013, 1.0),
		"ground_lift": Color(0.065, 0.052, 0.039, 1.0),
		"cards": [
			# Key: 5200K neutral-warm, gradient to neutral
			_make_card(Vector3(0.00, 0.36, 0.94), Color(1.0, 0.985, 0.96, 1.0), 900.0, 14.0, 3.8, 2.3,
				5200.0, Color(0.94, 0.96, 1.0, 1.0), 0.7),
			# Right fill: warm, gradient
			_make_card(Vector3(0.86, 0.08, 0.50), Color(1.0, 0.96, 0.92, 1.0), 160.0, 8.0, 0.46, 0.36,
				5800.0, Color(0.94, 0.96, 1.0, 1.0), 0.8),
			# Left fill: cool
			_make_card(Vector3(-0.72, 0.10, 0.62), Color(0.92, 0.96, 1.0, 1.0), 120.0, 8.0, 0.42, 0.34,
				6200.0, Color(0.88, 0.92, 1.0, 1.0), 0.8),
		],
		"blocker_dir": Vector3(-0.14, -0.24, 0.96),
		"blocker_power": 9.0,
		"blocker_strength": 0.17,
		"ground_albedo": 0.20,
		"ground_tint": Color(0.94, 0.90, 0.84, 1.0),
		"ground_distance": 0.8,
	}


static func _gameplay_studio() -> Dictionary:
	return {
		"sky_low": Color(0.11, 0.12, 0.16, 1.0),
		"sky_top": Color(0.26, 0.30, 0.39, 1.0),
		"horizon": Color(0.52, 0.46, 0.38, 1.0),
		"ground_dark": Color(0.020, 0.018, 0.018, 1.0),
		"ground_lift": Color(0.08, 0.068, 0.062, 1.0),
		"cards": [
			# Key: 5400K warm daylight, soft gradient to neutral edge
			_make_card(Vector3(0.02, 0.30, 0.95), Color(1.0, 0.99, 0.97, 1.0), 820.0, 12.0, 2.30, 1.70,
				5400.0, Color(0.92, 0.95, 1.0, 1.0), 0.7),
			# Right fill: 6000K slightly cool, gentle gradient
			_make_card(Vector3(0.72, 0.12, 0.68), Color(1.0, 0.94, 0.88, 1.0), 92.0, 8.0, 0.32, 0.34,
				6000.0, Color(0.94, 0.96, 1.0, 1.0), 0.8),
			# Left fill: cool white, gentle gradient
			_make_card(Vector3(-0.72, 0.14, 0.64), Color(0.92, 0.97, 1.0, 1.0), 92.0, 8.0, 0.30, 0.32,
				6000.0, Color(0.88, 0.94, 1.0, 1.0), 0.8),
			# Under fill: warm, no gradient (small lobe)
			_make_card(Vector3(-0.06, -0.54, 0.84), Color(1.0, 0.92, 0.82, 1.0), 24.0, 6.0, 0.12, 0.14,
				4800.0),
		],
		"blocker_dir": Vector3(-0.10, -0.18, 0.98),
		"blocker_power": 8.0,
		"blocker_strength": 0.10,
		"ground_albedo": 0.12,
		"ground_tint": Color(0.90, 0.86, 0.80, 1.0),
		"ground_distance": 0.8,
	}


static func _deep_color() -> Dictionary:
	return {
		"sky_low": Color(0.008, 0.009, 0.014, 1.0),
		"sky_top": Color(0.025, 0.028, 0.042, 1.0),
		"horizon": Color(0.08, 0.06, 0.04, 1.0),
		"ground_dark": Color(0.002, 0.002, 0.003, 1.0),
		"ground_lift": Color(0.012, 0.010, 0.008, 1.0),
		"cards": [
			# Key: 4200K warm halogen, pronounced gradient — hot white center to warm amber edge
			_make_card(Vector3(0.02, 0.48, 0.88), Color(1.0, 0.99, 0.97, 1.0), 1400.0, 16.0, 5.8, 3.2,
				4200.0, Color(1.0, 0.88, 0.72, 1.0), 0.6),
			# Right fill: 5500K cool white, subtle gradient
			_make_card(Vector3(0.68, 0.16, 0.72), Color(0.98, 0.96, 1.0, 1.0), 180.0, 10.0, 0.72, 0.52,
				5500.0, Color(0.92, 0.94, 1.0, 1.0), 0.75),
			# Left fill: warm white, subtle gradient
			_make_card(Vector3(-0.74, 0.20, 0.58), Color(1.0, 0.99, 0.96, 1.0), 280.0, 12.0, 0.78, 0.56,
				5500.0, Color(0.94, 0.96, 1.0, 1.0), 0.75),
			# Under fill: very warm bounce
			_make_card(Vector3(-0.08, -0.64, 0.76), Color(1.0, 0.92, 0.84, 1.0), 54.0, 8.0, 0.34, 0.24,
				3800.0),
		],
		"blocker_dir": Vector3(-0.22, -0.36, 0.90),
		"blocker_power": 12.0,
		"blocker_strength": 0.42,
		"ground_albedo": 0.06,
		"ground_tint": Color(0.80, 0.72, 0.62, 1.0),
		"ground_distance": 0.8,
	}


## Default zone surface scales. These control per-zone lighting weight factors
## in the surface lighting model. Override by passing a "zone_surface_scales"
## dictionary in the trace request.
static func default_zone_surface_scales() -> Dictionary:
	return {
		"table":       {"front": 0.56, "back": 0.90, "spec": 0.62, "body": 0.92, "caustic": 1.06, "interface": 0.48},
		"rose_center": {"front": 0.54, "back": 0.92, "spec": 0.60, "body": 0.94, "caustic": 1.08, "interface": 0.50},
		"rose":        {"front": 0.72, "back": 1.00, "spec": 0.76, "body": 1.08, "caustic": 1.04, "interface": 0.72},
		"girdle":      {"front": 0.78, "back": 1.00, "spec": 0.80, "body": 1.06, "caustic": 1.02, "interface": 0.80},
		"step":        {"front": 0.80, "back": 1.00, "spec": 0.82, "body": 1.06, "caustic": 1.03, "interface": 0.78},
		"star":        {"front": 0.68, "back": 1.00, "spec": 0.72, "body": 0.96, "caustic": 1.02, "interface": 0.70},
		"bezel":       {"front": 0.76, "back": 1.00, "spec": 0.78, "body": 0.98, "caustic": 1.02, "interface": 0.76},
	}


## Returns the effective default values for all sentinel-based override properties
## given a visual's current state. The designer UI uses this to show what the
## "auto" value resolves to, without duplicating any preset constants.
static func resolve_effective_defaults(visual) -> Dictionary:
	var preset_id: int = visual.optics_environment_preset if visual != null else PRESET_NEUTRAL
	var preset := resolve_preset(preset_id)

	# Ground plane defaults from the preset
	var ground_albedo: float = preset.get("ground_albedo", 0.15)
	var ground_tint: Color = preset.get("ground_tint", Color(0.92, 0.87, 0.80, 1.0))
	var ground_distance: float = preset.get("ground_distance", 0.8)
	var blocker_strength: float = preset.get("blocker_strength", 0.0)

	# Key card temperature from the first card of the preset
	var light_temperature_kelvin: float = 5500.0
	var cards: Array = preset.get("cards", [])
	if not cards.is_empty():
		light_temperature_kelvin = cards[0].get("temperature_kelvin", 5500.0)

	# Auto cloudiness: mirrors the C++ formula in build_trace_flags()
	var scattering: float = visual.optics_scattering_strength if visual != null else 0.0
	var roughness: float = visual.optics_surface_roughness if visual != null else 0.02
	var transluc: float = visual.translucency if visual != null else 0.0
	var cloudiness: float = clampf(scattering * 1.2 + roughness * 0.3 + transluc * 0.1, 0.0, 0.5)

	# Auto transmission: mirrors C++ material::transmission_factor()
	var material_mode: int = visual.material_mode if visual != null else 0
	var transmission: float = 1.0
	if material_mode == 1:  # PATTERNED_OPAQUE
		transmission = 0.0
	elif material_mode == 2:  # PATTERNED_TRANSLUCENT
		transmission = 0.78

	# Auto exposure: mirrors C++ auto formula in apply_output_grade()
	var light_energy: float = visual.optics_light_energy if visual != null else 2.4
	var spec_intensity: float = visual.specular_intensity if visual != null else 0.4
	var sparkle_int: float = visual.sparkle_intensity if visual != null else 0.0
	var grade_exposure: float = 0.74 + light_energy * 0.07 + spec_intensity * 0.04 + sparkle_int * 0.005

	# Auto saturation: mirrors C++ auto formula in apply_output_grade()
	var sat_boost: float = visual.saturation_boost if visual != null else 0.0
	var contrast: float = visual.contrast if visual != null else 0.3
	var hue_disp: float = visual.hue_dispersion if visual != null else 0.0
	var abs_str: float = visual.optics_absorption_strength if visual != null else 1.1
	var grade_saturation: float = clampf(
		sat_boost + contrast * 0.10 + hue_disp * 0.14
		+ spec_intensity * 0.015 + minf(abs_str, 3.0) * 0.030
		+ 0.02,  # saturation_base default
		-0.1, 0.56
	)

	return {
		"ground_albedo": ground_albedo,
		"ground_tint": ground_tint,
		"ground_distance": ground_distance,
		"light_temperature_kelvin": light_temperature_kelvin,
		"cloudiness": cloudiness,
		"transmission": transmission,
		"grade_exposure": grade_exposure,
		"grade_saturation": grade_saturation,
		"blocker_strength": blocker_strength,
	}
