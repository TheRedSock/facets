class_name GemCutTemplate
extends Resource
## A facet program in the Lapidary cut language (docs/lapidary-architecture.md §1).
## Silhouette-independent: the same template compiles against any of the eight
## tier silhouettes (CUT_TAXONOMY.md). Compiled by core/lapidary/cut/cut_compiler.gd
## into a convex plane set, optionally tessellated for nested boundaries.
##
## Family names (brilliant, step, rose, princess, radiant) are just .tres files
## in data/lapidary/cuts/ expanding into this grammar.

@export var cut_id: StringName = &""
## Explicit pavilion main (or deepest step) angle. Material changes never alter it.
@export_range(10.0, 70.0) var pavilion_angle_deg := 41.0
## Fraction of nominal axis depth retained by the flat culet plane.
@export_range(0.5, 1.0) var culet_depth_fraction := 0.96

## Girdle band half-height in stone units (girdle plane is z = 0).
@export_range(0.005, 0.15) var girdle_half_height: float = 0.03

## Ordered girdle→table. See GemCutTemplateRow for row semantics.
## Convexity constraint (validated): consecutive step rows must have strictly
## decreasing angles — a convex hull cannot express a crown that steepens
## toward the table.
@export var crown_rows: Array[GemCutTemplateRow] = []

## Table diameter as a fraction of girdle diameter, authored at quality 1.
## This authored proportion is independent of material and grade.
@export_range(0.05, 0.95) var table_ratio: float = 0.56

## &"fan_brilliant" — pavilion mains (sectors) + lower-girdle halves
##   (2 × sectors), main angle from pavilion_angle_deg.
## &"step" — pavilion_rows concentric frames; the DEEPEST row sits exactly at
##   pavilion_angle_deg and rows toward the girdle steepen by
##   pavilion_step_delta_deg each (convexity: a convex pavilion must flatten
##   toward the keel, which is also how real step cuts are proportioned).
@export var pavilion_style: StringName = &"fan_brilliant"

## Step pavilion only: number of concentric rows.
@export_range(2, 4) var pavilion_rows: int = 3

## Step pavilion only: per-row steepening toward the girdle, degrees.
@export_range(1.0, 15.0) var pavilion_step_delta_deg: float = 7.0

## Step pavilion only: silhouette scale where the keel terminates.
@export_range(0.02, 0.5) var pavilion_keel_scale: float = 0.14

## fan_brilliant only: lower-girdle halves sit this many degrees steeper
## than the authored mains.
@export_range(0.0, 15.0) var pavilion_lower_half_delta_deg: float = 6.0
