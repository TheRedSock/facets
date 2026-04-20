class_name GemInclusionProfile
extends Resource

## Discrete inclusion geometry profile for the gem tracer.
##
## Generates actual geometric objects (needles, plates, crystals, fingerprints,
## veils, fingerprint_veins) inside the gem mesh that cast real shadows and
## refraction via the native ray tracer. Each inclusion type models a
## real-world mineralogical feature:
##   needles         = elongated hexagonal prisms (rutile silk in ruby/sapphire)
##   plates          = flat hexagonal discs (mica plates)
##   crystals        = small octahedra (crystal inclusions in emerald)
##   fingerprints    = clusters of small spheroids in disc arrangements
##   veil            = curved sheet of micro-triangles (healed fractures, jardin)
##   fingerprint_vein = gently-curving thin capsule chain (healed fissures)

## Type of inclusion geometry to generate.
## "needles" = elongated hexagonal prisms (rutile silk in ruby/sapphire)
## "plates" = flat hexagonal discs (mica plates)
## "crystals" = small octahedra (crystal inclusions in emerald)
## "fingerprints" = clusters of small spheroids in disc arrangements
## "veil" = curved sheet of micro-triangles (healed fractures, jardin films)
## "fingerprint_vein" = gently-curving thin capsule chain (healed fissures)
@export var inclusion_type: StringName = &"needles"

## Density scaling (0 = none, 1 = dense). Controls count relative to gem volume.
@export_range(0.0, 1.0) var density: float = 0.2

## Size range in model-space units [min, max].
@export var size_range: Vector2 = Vector2(0.02, 0.06)

## Preferred orientation axis (e.g., c-axis for silk needles).
@export var orientation_axis: Vector3 = Vector3(0, 1, 0)

## Angular spread around the orientation axis (0 = perfectly aligned, 1 = random).
@export_range(0.0, 1.0) var orientation_spread: float = 0.2

## IOR of the inclusion material (rutile ~2.6, fluid ~1.33, garnet ~1.76).
@export_range(1.0, 4.0) var material_ior: float = 1.5

## Absorption coefficient of the inclusion material.
@export_range(0.0, 20.0) var material_absorption: float = 2.0

## Additional scattering at inclusion surfaces.
@export_range(0.0, 5.0) var scatter_strength: float = 0.5

## Min/max count of inclusions to generate.
@export var count_range: Vector2i = Vector2i(3, 8)

## Deterministic seed offset for reproducible placement.
@export var seed_offset: int = 0

## Optional multi-scale inclusion hierarchy. Each entry is a Dictionary with:
##   size_range: Vector2       — [min, max] size for this scale layer
##   count_range: Vector2i     — [min, max] count for this scale layer
##   density: float            — density scaling for this layer
##   type_override: StringName — inclusion type for this layer (empty = use profile's inclusion_type)
## When non-empty, generate_and_merge iterates layers instead of using the
## single-scale fields above. When empty, falls back to existing behaviour.
@export var scale_layers: Array = []
