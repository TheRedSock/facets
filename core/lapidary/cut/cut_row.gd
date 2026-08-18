class_name GemCutTemplateRow
extends Resource
## One crown row in the Lapidary cut language (docs/lapidary-architecture.md §1).
## A row is a *program statement*, not geometry: the cut compiler expands it
## against the active silhouette into tagged half-space planes.
##
## Row kinds:
##   &"break" — ring of facets anchored on the girdle curve at `angle_deg`.
##              count = silhouette sectors × density. Brilliant mains and
##              upper-girdle halves are both break rows (the first break row
##              is tagged zone CROWN, later break rows zone UPPER_GIRDLE).
##   &"step"  — row following the silhouette at `angle_deg`, advancing the
##              crown inward by `span` (share of the girdle→table run).
##              Step cuts chain several of these. Zone STEP.
##   &"star"  — table-adjacent row anchored on the main-row cone at
##              placement `span` (0 = table edge, 1 = girdle). Requires a
##              preceding break row. Zone CROWN.

## &"break" | &"step" | &"star"
@export var kind: StringName = &"break"

## Facet angle from the girdle plane, degrees, authored at cut_quality = 1.
## The compiler scales all crown rows by the quality law applied to the
## first row: lerp(19°, authored, q) / authored.
@export_range(5.0, 80.0) var angle_deg: float = 34.5

## Facet count multiplier: count = silhouette sectors × density (break/star
## rows). Step rows always emit 2 × sectors planes and ignore density.
@export_range(1, 4) var density: int = 1

## Azimuthal phase in sector units (0.5 = half a sector offset). Break/star
## rows use it directly; only the first step row's phase is honoured (all
## step frames stay azimuth-aligned so the concentric read survives).
@export_range(0.0, 1.0) var phase: float = 0.0

## step: share of the crown run this row covers (normalized across step rows).
## star: placement between table edge (0) and girdle (1); 0 treated as 0.5.
## break: unused.
@export_range(0.0, 1.0) var span: float = 0.0
