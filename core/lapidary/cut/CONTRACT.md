# Declarative facet programs

`GemStone.shape` supplies the faceted girdle boundary. `GemCutTemplate` supplies
named scalar parameters and ordered `GemFacetGroup` constraints. There is one
grammar: no special table, crown-row, pavilion or culet compiler. Horizontal
termination planes are ordinary groups and may be absent independently. A
program must produce a closed, finite convex solid within normalized z (-4,4),
with at most 512 planes including the girdle. Nonconvex lofts and analytic curved
hosts continue through their existing geometry construction; they are not
accepted as convex facet programs.

Each group names `GemFacetDirections`: an explicit wheel division count, indices,
phase in degrees, and radial-support or boundary-normal sampling. A 360-division
wheel expresses azimuths directly. Crown and pavilion indices are independent.
Triangle variants in the catalog explicitly use sixfold sets; changing an
outline no longer silently changes facet indices. The old shape `sectors`
property and cut-row schema are removed.

For each direction, the anchor's XY coordinates are the girdle sample times
`scale`, minus outward sample normal times `inset`. `inclination` is the facet
angle from the girdle plane in degrees; `side` chooses the sign of its vertical
normal. The plane offset is `dot(normal, anchor) + offset`. Lengths are normalized
stone units, converted to millimeters by `GemStone.size_mm` (the unit-radius
scale). Parameters are finite scalars and every declared parameter must be used.

Scalar expressions support arithmetic and an allowlist of scalar math functions,
with `p.<parameter>`, `s.<direction_set>.min_support`, and
`s.<direction_set>.mean_support`. Numeric literals use real division. No object
access, resource loading, side effects or RNG is allowed. Parsing/execution is
bounded and rejects nonfinite results. Godot's Expression arithmetic is used
with explicit inputs and no base object; see the
[Expression API](https://docs.godotengine.org/en/4.6/classes/class_expression.html).

`meet_groups` names earlier construction surfaces. Their upper/lower envelope at
the anchor's XY supplies `meet` to height/offset expressions. Missing references,
wrong-facing surfaces, forward/cyclic dependencies and nonfinite meets fail.
An envelope is a defined closest-surface operation, including coincident ridge
contacts; it is not an arbitrary three-plane CAD solver. The compiled result
records contact names for inspection. Subsequent cutting or manufacture can
erase an intermediate face; this is reported as `vanished` or
`meet_target_vanished`, without changing the already defined construction meet.

The brilliant's sequential star meets are explicit groups in data. Step rows
are explicit support-normal groups with inset/height expressions. All captured
nominal template/shape combinations retain facet counts; the migration audit
compares planes independent of ordering. Per-facet IDs are nonnegative int32
hashes of stable group/index names, checked for collisions and preserved through
pruning. Manufacture has independent seed channels per ID. Inserting a redundant
facet or renaming a cut label does not change existing manufactured faces.
Manufacture applies to every program group after nominal construction, including
horizontal terminations; the girdle has its own inward-offset tolerance. It never rewrites nominal angles
from grade or material. Condition variation may vary workmanship, not nominal
program parameters. A preset can explicitly select another complete cut.

Custom faceted girdles use `GemShape.outline_points`: 3..256 simple, strictly
convex CCW points, containing the origin, with maximum radius one. No hidden
recentering, normalization, welding or concavity repair occurs. Concave outlines
remain available to the existing loft constructor.

`data/lapidary/cut_examples/` contains admitted pointed-crown/flat-bottom,
independent-pavilion-index, mixed-row and custom-girdle specimens. They are normal
resources editable with `GemAuthoringDocument`; no compiler changes define them.

`GemCutInspection` reads the compiled hull for facet polygons, constraint anchors,
contact names, millimeter dimensions and arbitrary plane sections. Inspection
describes the manufactured facet program before rounding/cleavage. Headless
`tools/inspect_cut.gd -- --stone=res://... --output=res://artifacts/...` saves an
SVG overlay and JSON report. Godot's SVG rasterizer omits text; use an SVG viewer
for its labels and hover details.

`tools/optimize_cut.gd` varies explicitly named parameters via repeated
`--vary=name:value,value` options, with at most 128 combinations. It retains the
baseline, independent seed confirmation and held-out views; it neither promotes
catalog data nor claims certified grading. Unknown parameters are rejected.

Gates: `test_cut_compiler`, `test_cut_design`, `test_facet_program`,
`test_geometry`, `test_job_validation`, `inspect_cut`; GPU foundation,
polarization/crystal and cut-search checks. Historical migration inputs and
render comparisons live under ignored readiness-review artifacts.
