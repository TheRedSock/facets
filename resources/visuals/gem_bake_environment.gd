class_name GemBakeEnvironment extends Resource

@export var environment_id: StringName = &""
@export var environment_name: String = ""

## HDR equirectangular environment map. If null, uses the sky gradient + cards.
@export var environment_map: Texture2D = null

## Sky gradient (used when environment_map is null)
@export var sky_low: Color = Color(0.16, 0.19, 0.26)
@export var sky_top: Color = Color(0.36, 0.42, 0.54)
@export var horizon: Color = Color(0.68, 0.54, 0.36)
@export var ground_dark: Color = Color(0.02, 0.016, 0.013)
@export var ground_lift: Color = Color(0.10, 0.078, 0.052)

## Analytical light cards. Array of Dictionaries, each with:
##   dir: Vector3, color: Color, sharp_power: float, broad_power: float,
##   sharp_strength: float, broad_strength: float,
##   temperature_kelvin: float (0 = use color with spectral uplifting),
##   edge_color: Color (transparent = auto), gradient_power: float
@export var light_cards: Array[Dictionary] = []

## Blocker (negative light zone, e.g., camera obstruction)
@export var blocker_dir: Vector3 = Vector3(-0.18, -0.30, 0.94)
@export_range(0.0, 20.0) var blocker_power: float = 10.0
@export_range(0.0, 1.0) var blocker_strength: float = 0.19

## Virtual ground plane
@export_range(0.0, 1.0) var ground_albedo: float = 0.15
@export var ground_tint: Color = Color(0.92, 0.87, 0.80)
@export_range(0.0, 4.0) var ground_distance: float = 0.8

## Output exposure (applied in tonemapping, NOT a material property)
@export_range(0.1, 4.0) var exposure: float = 1.0

## Light energy multiplier
@export_range(0.0, 8.0) var light_energy: float = 2.4

## Environment energy multiplier
@export_range(0.0, 4.0) var environment_energy: float = 1.0

## Per-environment card power cap override.
## Controls the maximum angular sharpness of light card highlights.
## Higher values = tighter point-source highlights (more fire/sparkle, more noise).
## -1.0 = use kernel default (40.0, ~12° half-width).
## Dispersion environments may set 200-400 for visible prismatic splitting.
@export_range(-1.0, 5000.0) var card_power_cap: float = -1.0

## Dual-illuminant rendering: secondary illuminant for color-change gems.
## When secondary_illuminant_mix > 0, the tracer runs two independent spectral
## accumulations per pixel (primary D65-like and secondary at this temperature),
## combining at XYZ stage pre-tonemap. Used for alexandrite, blue garnet, etc.
## 0.0 = disabled (single-illuminant bake).
@export_range(1000.0, 10000.0) var secondary_illuminant_temperature: float = 2856.0
@export_range(0.0, 1.0) var secondary_illuminant_mix: float = 0.0


## Build a Dictionary suitable for passing as "environment_profile" in a trace request.
func to_trace_dict() -> Dictionary:
	var result := {
		"sky_low": sky_low,
		"sky_top": sky_top,
		"horizon": horizon,
		"ground_dark": ground_dark,
		"ground_lift": ground_lift,
		"blocker_dir": blocker_dir,
		"blocker_power": blocker_power,
		"blocker_strength": blocker_strength,
		"ground_albedo": ground_albedo,
		"ground_tint": ground_tint,
		"ground_distance": ground_distance,
		"exposure": exposure,
		"light_energy": light_energy,
		"environment_energy": environment_energy,
		"card_power_cap": card_power_cap,
		"secondary_illuminant_temperature": secondary_illuminant_temperature,
		"secondary_illuminant_mix": secondary_illuminant_mix,
		"cards": light_cards,
	}
	return result
