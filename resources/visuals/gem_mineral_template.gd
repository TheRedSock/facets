class_name GemMineralTemplate extends Resource

## Unique identifier for this mineral species.
@export var mineral_id: StringName = &""

## Human-readable name (e.g., "Corundum (Al₂O₃)").
@export var mineral_name: String = ""

## Sellmeier dispersion coefficients.
## n²(λ) = 1 + B1·λ²/(λ²-C1) + B2·λ²/(λ²-C2) + B3·λ²/(λ²-C3)
## B values are dimensionless. C values are in μm².
@export var sellmeier_b: Vector3 = Vector3(0.696, 0.408, 0.898)
@export var sellmeier_c: Vector3 = Vector3(0.00468, 0.01351, 97.934)

## Absorption spectrum: extinction coefficient at 5nm intervals, 380-780nm.
## 81 float values. Units: per model-space-unit.
## Empty = fully transparent mineral (no inherent absorption).
## For minerals with multiple chromophore variants (e.g., corundum → sapphire, ruby),
## this is the BASE absorption of the pure mineral. Per-gem absorption overrides are
## on the GemVisualResource.
@export var absorption_spectrum: PackedFloat32Array = PackedFloat32Array()

## Scattering coefficient (σ_s) in model-space units. 0 = no scattering.
@export_range(0.0, 50.0) var scattering_coefficient: float = 0.0

## Henyey-Greenstein anisotropy parameter.
## 0 = isotropic, positive = forward-scattering, negative = back-scattering.
@export_range(-0.99, 0.99) var scattering_anisotropy: float = 0.0

## Fluorescence: quantum yield (probability of re-emission per absorption event).
@export_range(0.0, 1.0) var fluorescence_quantum_yield: float = 0.0

## Fluorescence excitation band center (nm).
@export_range(300.0, 700.0) var fluorescence_excitation_center_nm: float = 550.0

## Fluorescence excitation band width (nm, Gaussian sigma).
@export_range(5.0, 100.0) var fluorescence_excitation_width_nm: float = 30.0

## Fluorescence emission band center (nm).
@export_range(400.0, 780.0) var fluorescence_emission_center_nm: float = 694.0

## Fluorescence emission band width (nm, Gaussian sigma).
@export_range(5.0, 100.0) var fluorescence_emission_width_nm: float = 15.0

## Birefringence Δn (difference between ordinary and extraordinary refractive indices).
## 0 = isotropic crystal (cubic system: diamond, garnet, fluorite).
@export_range(0.0, 0.2) var birefringence_delta_n: float = 0.0

## Pleochroism: absorption spectrum along the extraordinary axis.
## If empty, absorption is the same in all directions (no pleochroism).
## If provided, the base absorption_spectrum is treated as the ordinary-ray absorption,
## and this is the extraordinary-ray absorption. Actual absorption is interpolated
## based on the angle between the ray direction and the optic axis.
@export var pleochroism_absorption_spectrum: PackedFloat32Array = PackedFloat32Array()

## Default surface roughness (GGX α parameter) for typical polish of this mineral.
## 0.0 = perfect mirror polish, 0.01 = excellent polish, 0.05 = fair, 0.1+ = rough/frosted.
@export_range(0.0, 1.0) var default_surface_roughness: float = 0.01

## Surface roughness anisotropy for anisotropic GGX. 0 = isotropic, 1 = maximum elongation.
## Affects the shape of specular highlights — non-zero creates elongated specular lobes.
@export_range(0.0, 1.0) var surface_roughness_anisotropy: float = 0.0

## Preferred direction for surface anisotropy in model space.
## For uniaxial crystals, typically the c-axis.
@export var anisotropy_axis: Vector3 = Vector3(0, 1, 0)

## Display color for UI / procedural fallback (NOT used in ray transport).
@export var display_color: Color = Color.WHITE

## Default bake environment for gems using this mineral template.
## Individual GemVisualResource.bake_environment overrides this.
## null = inherit from bake profile or global default.
@export var bake_environment: Resource = null


## Compute the Sellmeier IOR at a reference wavelength (589nm sodium D-line).
## Useful for validation and display.
func get_reference_ior() -> float:
	var l := 0.589  # μm
	var l2 := l * l
	var n2 := 1.0 \
		+ sellmeier_b.x * l2 / (l2 - sellmeier_c.x) \
		+ sellmeier_b.y * l2 / (l2 - sellmeier_c.y) \
		+ sellmeier_b.z * l2 / (l2 - sellmeier_c.z)
	return sqrt(max(n2, 1.0))


const MINERAL_JSON_SCHEMA_VERSION := 1


func build_mineral_json_dict() -> Dictionary:
	var result := {"mineral_json_schema_version": MINERAL_JSON_SCHEMA_VERSION}
	for prop in get_property_list():
		if not (prop.usage & PROPERTY_USAGE_EDITOR):
			continue
		var n: StringName = prop.name
		if n.begins_with(&"resource_") or n == &"script":
			continue
		result[String(n)] = _mineral_to_json_safe(get(n))
	return result


func apply_mineral_json_dict(data: Dictionary) -> void:
	var ver := int(data.get("mineral_json_schema_version", 1))
	if ver > MINERAL_JSON_SCHEMA_VERSION:
		push_warning("GemMineralTemplate: JSON schema %d newer than supported %d" % [ver, MINERAL_JSON_SCHEMA_VERSION])
	var prop_types := {}
	for prop in get_property_list():
		if prop.usage & PROPERTY_USAGE_EDITOR:
			prop_types[StringName(prop.name)] = prop.type
	for key in data.keys():
		if String(key) == "mineral_json_schema_version":
			continue
		var sn := StringName(key)
		if not prop_types.has(sn):
			continue
		set(sn, _mineral_from_json_value(data[key], prop_types[sn]))


static func _mineral_to_json_safe(value) -> Variant:
	match typeof(value):
		TYPE_COLOR:
			return [value.r, value.g, value.b, value.a]
		TYPE_VECTOR3:
			return [value.x, value.y, value.z]
		TYPE_STRING_NAME:
			return String(value)
		TYPE_PACKED_FLOAT32_ARRAY:
			return Array(value)
		_:
			return value


static func _mineral_from_json_value(value, target_type: int) -> Variant:
	match target_type:
		TYPE_COLOR:
			if typeof(value) == TYPE_ARRAY and value.size() >= 4:
				return Color(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
			if typeof(value) == TYPE_ARRAY and value.size() >= 3:
				return Color(float(value[0]), float(value[1]), float(value[2]), 1.0)
		TYPE_VECTOR3:
			if typeof(value) == TYPE_ARRAY and value.size() >= 3:
				return Vector3(float(value[0]), float(value[1]), float(value[2]))
		TYPE_STRING_NAME:
			return StringName(String(value))
		TYPE_FLOAT:
			return float(value)
		TYPE_INT:
			return int(value)
		TYPE_BOOL:
			return bool(value)
		TYPE_STRING:
			return String(value)
		TYPE_PACKED_FLOAT32_ARRAY:
			if typeof(value) == TYPE_ARRAY:
				var arr := PackedFloat32Array()
				for v in value:
					arr.append(float(v))
				return arr
	return value
