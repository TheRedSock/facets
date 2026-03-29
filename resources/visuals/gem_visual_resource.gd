class_name GemVisualResource
extends Resource

## Defines the visual appearance of a specific gem type.
## References a cut_id (resolved at runtime by GemVisualRegistry)
## and specifies colour, material properties, and edge rendering.

@export var visual_id: StringName = &""
@export var cut_id: StringName = &""

# ---- Colour ----

@export var base_color: Color = Color.WHITE

## If true, sample from color_texture instead of flat base_color.
## Useful for opals, agates, and other patterned gems.
@export var use_texture: bool = false
@export var color_texture: Texture2D = null

# ---- Material properties ----

@export_range(1.0, 256.0) var shininess: float = 32.0
@export_range(0.0, 1.0) var specular_intensity: float = 0.4
@export_range(0.0, 1.0) var transparency: float = 0.0

## Colour shift applied to facets facing away from the viewer,
## simulating light passing through a transparent stone.
@export var depth_tint: Color = Color.TRANSPARENT
@export_range(-0.5, 0.5) var saturation_boost: float = 0.0

## Controls the light-to-dark range across facets.
## 0.0 = flat, uniform shading (common stones).
## 1.0 = dramatic, high-contrast faceting (precious gems).
@export_range(0.0, 1.0) var contrast: float = 0.3

## Prismatic hue dispersion ("fire").  Each facet shifts its hue
## based on its angle, simulating light splitting into a spectrum.
## 0.0 = no dispersion (most gems).  0.3+ = visible rainbow fire (diamond).
@export_range(0.0, 0.5) var hue_dispersion: float = 0.0

# ---- Edge rendering ----

@export var edge_color: Color = Color(1.0, 1.0, 1.0, 0.0)
@export_range(0.0, 3.0) var edge_width: float = 0.0
@export var outline_color: Color = Color(0.0, 0.0, 0.0, 0.15)
@export_range(0.0, 4.0) var outline_width: float = 1.0
