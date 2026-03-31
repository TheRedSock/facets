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
@export_range(0.0, 1.0) var texture_blend: float = 1.0
@export_range(1.0, 4.0) var texture_zoom: float = 1.0
@export var texture_offset: Vector2 = Vector2.ZERO
@export_range(0.0, 1.0) var texture_facet_warp: float = 0.35

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

# ---- Rim lighting ----

## Bright edge glow on facets facing away from the viewer (Fresnel effect).
## Simulates light catching the gem perimeter.
@export_range(0.0, 1.0) var rim_intensity: float = 0.0
@export var rim_color: Color = Color.WHITE
## Controls the falloff curve: higher = tighter rim, lower = broader glow.
@export_range(1.0, 5.0) var rim_power: float = 2.0

# ---- Translucency ----

## Simulates light entering from behind the gem and bleeding through to the
## front (subsurface scattering approximation).  Additive on front-facing
## facets, unlike depth_tint which replaces colour on back-facing facets.
@export_range(0.0, 1.0) var translucency: float = 0.0
@export var translucency_color: Color = Color.WHITE

# ---- Secondary specular ----

## A second Blinn-Phong specular highlight from a different light angle,
## simulating internal reflections within a faceted stone.
@export_range(0.0, 1.0) var secondary_specular: float = 0.0
## Angle offset (degrees) from the primary light for the secondary highlight.
@export_range(0.0, 360.0) var secondary_light_angle: float = 120.0

# ---- Sparkle ----

## Dramatic brightness boost on facets whose specular alignment exceeds the
## threshold.  Simulates the intense white flashes seen in real gems.
@export_range(0.0, 3.0) var sparkle_intensity: float = 0.0
## Specular alignment above which the sparkle kicks in (0 = all facets, 1 = none).
@export_range(0.0, 1.0) var sparkle_threshold: float = 0.85

# ---- Color gradient ----

## Blends the base colour toward this colour from top to bottom of the gem,
## simulating natural colour zoning (e.g. amethyst purple-to-white).
@export var gradient_color: Color = Color.TRANSPARENT
@export_range(0.0, 1.0) var gradient_strength: float = 0.0

# ---- Zone brilliance ----

## Brightens table/star facets and darkens girdle facets, simulating the
## characteristic "window" of light through a well-cut gem's table.
@export_range(0.0, 1.0) var brilliance_contrast: float = 0.0

# ---- Extinction ----

## Simulates pavilion extinction — the geometric dark patterns caused by
## light bouncing off internal facets and failing to return to the viewer.
## This drives the projected pavilion overlay only, keeping the main facet
## lighting pipeline separate from the internal extinction pattern pass.
## Higher values produce stronger dark patches — effective for
## transparent/brilliant gems, should be low for opaque/matte stones.
@export_range(0.0, 1.0) var extinction: float = 0.0

# ---- Edge rendering ----

@export var edge_color: Color = Color(1.0, 1.0, 1.0, 0.0)
@export_range(0.0, 3.0) var edge_width: float = 0.0
