class_name GemSurfaceDamageProfile
extends Resource

## Surface wear profile for the gem tracer.
##
## Defines non-geometric surface wear that breaks specular reflection patterns,
## providing immediate visual quality differentiation by tier:
##   scratches   = thin frosted capsules on polished surfaces
##   abrasion    = soft frosted disc patches on polished surfaces
##   edge_wear   = rough frosted capsules along facet junctions
##   dirt        = large soft-edged discoloured patches
##
## Surface wear is stored as per-facet material masks. It never changes mesh
## topology and therefore cannot protrude from the silhouette or generate hard
## random polygons. The native tracer evaluates the masks at hit time and shades
## them as exterior-only frosted dielectric material.
##
## Geometric chipping is intentionally out of scope for this pipeline. A
## silhouette-safe chip design must be worked out separately before it can be
## reintroduced as a wear primitive.

# --- Scratch parameters ---

## Min/max total count of scratches to generate (distributed across clusters).
@export var scratch_count_range: Vector2i = Vector2i(6, 10)
## Minimum scratch length in model-space units.
@export_range(0.01, 0.5) var scratch_length_min: float = 0.06
## Maximum scratch length in model-space units.
@export_range(0.02, 1.0) var scratch_length_max: float = 0.20
## Width of the scratch ribbon on the surface.
@export_range(0.0005, 0.02) var scratch_width: float = 0.002

## Average number of scratches per cluster. Natural abrasive wear produces
## grouped parallel marks. Set to 1 to disable clustering (uniform random).
@export_range(1, 8) var scratch_cluster_size: int = 3
## Direction spread within a cluster in degrees. Scratches in a cluster share
## a primary direction with random variation within this range.
@export_range(0.0, 45.0) var scratch_cluster_spread_degrees: float = 25.0
## Fraction of scratches that continue across facet boundaries. The rest
## terminate at the facet edge. Lower values produce more natural patterns
## where scratches are confined to individual facets.
@export_range(0.0, 1.0) var scratch_facet_crossing_ratio: float = 0.3
## Taper ratio for scratch width along its length. 0 = uniform width (bar),
## 1 = fully tapered (lens). Real abrasive scratches are widest in the middle
## and narrower at the endpoints, a consequence of indentor contact geometry.
@export_range(0.0, 1.0) var scratch_taper_ratio: float = 0.6
## Per-scratch width jitter relative to the cluster base width. Each scratch
## gets a random multiplier in [1-jitter, 1+jitter]. Breaks "all scratches
## look identical" uniformity within clusters.
@export_range(0.0, 0.8) var scratch_width_jitter: float = 0.35

# --- Abrasion cluster parameters ---
#
# Abrasion is no longer a disc-shaped primitive. Each abrasion is rendered as a
# cluster of short scratch capsules seeded at a facet edge. The shading reuses
# the scratch path so abrasion inherits the grazing specular-line response that
# gives real scratches their characteristic look.
#
# Legacy field names are preserved to keep existing .tres files valid:
#   abrasion_count_range    -> number of clusters
#   abrasion_radius         -> cluster footprint radius (scatter around seed)
#   abrasion_density        -> segments-per-cluster density multiplier

## Min/max number of abrasion clusters. Each cluster emits several short
## scratch segments near a facet edge.
@export var abrasion_count_range: Vector2i = Vector2i(1, 3)
## Cluster footprint radius. Segments are scattered within this distance of the
## seed point along the facet plane.
@export_range(0.005, 0.15) var abrasion_radius: float = 0.03
## Segment density multiplier within a cluster. Higher values produce more
## short scratches per cluster footprint.
@export_range(0.0, 1.0) var abrasion_density: float = 0.4
## Bias toward seeding cluster centers at facet edges rather than facet
## interiors. 1.0 = always pick an edge point, 0.0 = pick a random surface
## point (old behaviour).
@export_range(0.0, 1.0) var abrasion_edge_bias: float = 0.85
## Length range for the short scratch segments emitted inside an abrasion
## cluster. Shorter than normal scratches so the cluster reads as a burst of
## micro-marks rather than a long groove.
@export var abrasion_segment_length_range: Vector2 = Vector2(0.015, 0.05)
## Width of each short scratch segment inside an abrasion cluster.
@export_range(0.0005, 0.02) var abrasion_segment_width: float = 0.003

# --- Disabled chip parameters ---
# Geometric chipping is out of scope. Fields removed in v4 wear revision.
# See plans/quartz_wear_revision_retrospective.md for rationale.

# --- Edge wear parameters ---

## Number of rough patches to place along facet junctions.
## Edge wear targets the ridges between adjacent facet zones (e.g., bezel-girdle,
## pavilion-girdle) where polishing is least effective.
@export_range(0, 30) var edge_wear_count: int = 0
## Size of each edge wear patch (radius from the edge point).
@export_range(0.003, 0.05) var edge_wear_size: float = 0.008
## Extra weight multiplier for edges that border the table. Real gems show
## table-rim wear much more visibly than other edges because the table is
## the most visible surface on a face-up gem. 1.0 = no preference.
@export_range(1.0, 4.0) var edge_wear_table_boost: float = 2.0

# --- Dirt parameters ---

## Number of dirt / discolouration patches. Unlike abrasion, these are large,
## soft-edged, and hue-shifted toward a neutral warm grey/brown (authored on
## the GemVisualResource as damage_dirt_tint). They introduce the "not clean"
## visual cue without reading as mechanical damage.
@export var dirt_count_range: Vector2i = Vector2i(0, 0)
## Minimum dirt patch radius in model-space units.
@export_range(0.01, 0.15) var dirt_radius_min: float = 0.04
## Maximum dirt patch radius.
@export_range(0.02, 0.25) var dirt_radius_max: float = 0.10
## Density / opacity of dirt patches. 0 = invisible, 1 = strongly discoloured.
@export_range(0.0, 1.0) var dirt_opacity: float = 0.5

# --- Targeting ---

## Which gem surface zones to place damage on. Empty = all surface zones.
## Example: [&"pavilion", &"bezel", &"girdle"] to restrict damage to those zones.
@export var target_zones: Array[StringName] = []

# --- Zone name overrides ---

## Zone tag applied to scratch sub-triangles.
@export var scratch_zone_name: StringName = &"scratch"
## Zone tag applied to abrasion sub-triangles.
@export var abrasion_zone_name: StringName = &"abrasion"
## Zone tag applied to edge wear sub-triangles.
@export var edge_wear_zone_name: StringName = &"edge_wear"
## Zone tag applied to dirt patches.
@export var dirt_zone_name: StringName = &"dirt"

# --- Determinism ---

## Seed offset for deterministic RNG. Added to the base seed for reproducible
## damage placement across bakes.
@export var seed_offset: int = 0
