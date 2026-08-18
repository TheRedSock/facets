class_name GemCutTemplate
extends Resource
## A facet program in the Lapidary cut language (docs/lapidary-architecture.md §1).
## Silhouette-independent: the same template compiles against any of the eight
## tier silhouettes (CUT_TAXONOMY.md). Compiled by core/lapidary/cut/cut_compiler.gd
## into a convex plane set (KERNEL_CONTRACT.md "Plane") — never a mesh.
##
## Family names (brilliant, step, rose, princess, radiant) are just .tres files
## in data/lapidary/cuts/ expanding into this grammar.

@export var cut_id: StringName = &""

## Girdle band half-height in stone units (girdle plane is z = 0).
@export_range(0.005, 0.15) var girdle_half_height: float = 0.03

## Ordered girdle→table. See GemCutTemplateRow for row semantics.
## Convexity constraint (validated): consecutive step rows must have strictly
## decreasing angles — a convex hull cannot express a crown that steepens
## toward the table.
@export var crown_rows: Array[GemCutTemplateRow] = []

## Table diameter as a fraction of girdle diameter, authored at quality 1.
## Quality law: effective = clamp(table_ratio * lerp(1.25, 1.0, q), 0.1, 0.9).
@export_range(0.05, 0.95) var table_ratio: float = 0.56

## &"solved_brilliant" — pavilion mains (sectors) + lower-girdle halves
##   (2 × sectors), main angle from LapidaryStoneCompiler.solve_pavilion_deg.
## &"step" — pavilion_rows concentric frames; the DEEPEST row sits exactly at
##   the solver angle and rows toward the girdle steepen by
##   pavilion_step_delta_deg each (convexity: a convex pavilion must flatten
##   toward the keel, which is also how real step cuts are proportioned).
@export var pavilion_style: StringName = &"solved_brilliant"

## Step pavilion only: number of concentric rows.
@export_range(2, 4) var pavilion_rows: int = 3

## Step pavilion only: per-row steepening toward the girdle, degrees.
@export_range(1.0, 15.0) var pavilion_step_delta_deg: float = 7.0

## Step pavilion only: silhouette scale where the keel terminates.
@export_range(0.02, 0.5) var pavilion_keel_scale: float = 0.14

## solved_brilliant only: lower-girdle halves sit this many degrees steeper
## than the solved mains.
@export_range(0.0, 15.0) var pavilion_lower_half_delta_deg: float = 6.0
