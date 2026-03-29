class_name GemCutGenerators
extends RefCounted

## Parametric generators for gemstone cut geometries.
##
## All generators produce vertices in unit space [0,1]x[0,1] centred at (0.5, 0.5).
## Every generated cut is auto-normalized to fit within a consistent cell margin
## via _normalize_to_fit(), so no shape clips regardless of aspect ratio.

const CENTER := Vector2(0.5, 0.5)
const GEM_RADIUS := 0.43
## Margin kept between the outermost vertex and the cell edge (fraction of 0.5).
const FIT_MARGIN := 0.07


# ===========================================================================
#  Factory
# ===========================================================================


static func generate(cut_id: StringName) -> GemCutResource:
	match cut_id:
		&"classic_round":    return generate_classic_round()
		&"cushion":          return generate_cushion()
		&"trillion":         return generate_trillion()
		&"radiant_diamond":  return generate_radiant_diamond()
		&"hex_brilliant":    return generate_hex_brilliant()
		&"emerald_step":     return generate_emerald_step()
		&"oval_brilliant":   return generate_oval_brilliant()
		&"pear_brilliant":   return generate_pear_brilliant()
	push_warning("GemCutGenerators: Unknown cut_id '%s'" % str(cut_id))
	return null


# ===========================================================================
#  T1  —  Classic Round Brilliant  (circle, N=8)
# ===========================================================================


static func generate_classic_round() -> GemCutResource:
	var cut := GemCutResource.new()
	cut.cut_id = &"classic_round"
	cut.display_name = "Classic Round Brilliant"
	cut.shape_category = &"round"

	var N := 8
	var table_r := 0.53
	var star_r := 0.72
	var step := TAU / N

	var star_tilt := 18.0
	var bezel_tilt := 32.0
	var girdle_tilt := 42.0

	var table_v: Array[Vector2] = []
	var star_v: Array[Vector2] = []
	var girdle_m: Array[Vector2] = []
	var girdle_h: Array[Vector2] = []

	for i in N:
		var main_a := float(i) * step - PI * 0.5
		var half_a := main_a + step * 0.5
		table_v.append(_polar(table_r, main_a))
		star_v.append(_polar(star_r, half_a))
		girdle_m.append(_polar(1.0, main_a))
		girdle_h.append(_polar(1.0, half_a))

	cut.add_facet(_pva(table_v), Vector3(0, 0, 1), "table")

	for i in N:
		var ni := (i + 1) % N
		var poly := _pva([table_v[i], star_v[i], table_v[ni]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), star_tilt), "star")

	for i in N:
		var pi2 := (i - 1 + N) % N
		var poly := _pva([star_v[pi2], table_v[i], star_v[i], girdle_m[i]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), bezel_tilt), "bezel")

	for i in N:
		var ni := (i + 1) % N
		var pl := _pva([star_v[i], girdle_m[i], girdle_h[i]])
		cut.add_facet(pl, _normal_for(_centroid_pva(pl), girdle_tilt), "girdle")
		var pr := _pva([star_v[i], girdle_h[i], girdle_m[ni]])
		cut.add_facet(pr, _normal_for(_centroid_pva(pr), girdle_tilt), "girdle")

	cut.silhouette = _circle_silhouette(64)
	_collect_edges(cut)
	_normalize_to_fit(cut)
	return cut


# ===========================================================================
#  T2  —  Cushion  (square with rounded/tapered corners)
# ===========================================================================


static func generate_cushion() -> GemCutResource:
	var cut := GemCutResource.new()
	cut.cut_id = &"cushion"
	cut.display_name = "Cushion"
	cut.shape_category = &"square"

	# A cushion is an upright square with softened/tapered corners.
	# Corners at NE/SE/SW/NW (45° diagonals), flat sides face cardinal directions.
	# We use a superellipse (squircle) approach: r(a) = (|cos(a)|^n + |sin(a)|^n)^(-1/n)
	# where n > 2 gives a rounded square.  n=3.5 gives a nice cushion shape.
	var r := GEM_RADIUS
	var table_f := 0.38
	var star_f := 0.70
	var squircle_n := 3.5  # 2=circle, inf=square, 3-4=cushion

	var sil_pts := 48
	var outer_pts: Array[Vector2] = []
	for i in sil_pts:
		var a := float(i) / sil_pts * TAU - PI * 0.5
		outer_pts.append(_squircle_point(1.0, a, squircle_n))

	# For facet generation, sample N=8 main directions from the cushion curve.
	var N := 8
	var step := TAU / N
	var table_v: Array[Vector2] = []
	var star_v: Array[Vector2] = []
	var girdle_m: Array[Vector2] = []
	var girdle_h: Array[Vector2] = []

	for i in N:
		var main_a := float(i) * step - PI * 0.5
		var half_a := main_a + step * 0.5
		table_v.append(_squircle_point(table_f, main_a, squircle_n))
		star_v.append(_squircle_point(star_f, half_a, squircle_n))
		girdle_m.append(_squircle_point(1.0, main_a, squircle_n))
		girdle_h.append(_squircle_point(1.0, half_a, squircle_n))

	var star_tilt := 20.0
	var bezel_tilt := 33.0
	var girdle_tilt := 42.0

	cut.add_facet(_pva(table_v), Vector3(0, 0, 1), "table")

	for i in N:
		var ni := (i + 1) % N
		var poly := _pva([table_v[i], star_v[i], table_v[ni]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), star_tilt), "star")

	for i in N:
		var pi2 := (i - 1 + N) % N
		var poly := _pva([star_v[pi2], table_v[i], star_v[i], girdle_m[i]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), bezel_tilt), "bezel")

	for i in N:
		var ni := (i + 1) % N
		var pl := _pva([star_v[i], girdle_m[i], girdle_h[i]])
		cut.add_facet(pl, _normal_for(_centroid_pva(pl), girdle_tilt), "girdle")
		var pr := _pva([star_v[i], girdle_h[i], girdle_m[ni]])
		cut.add_facet(pr, _normal_for(_centroid_pva(pr), girdle_tilt), "girdle")

	cut.silhouette = _pva(outer_pts)
	_collect_edges(cut)
	_normalize_to_fit(cut)
	return cut


# ===========================================================================
#  T3  —  Trillion  (triangle with convex-bowed edges, 3-fold)
# ===========================================================================


static func generate_trillion() -> GemCutResource:
	var cut := GemCutResource.new()
	cut.cut_id = &"trillion"
	cut.display_name = "Trillion"
	cut.shape_category = &"triangle"

	var h := GEM_RADIUS * 2.0
	var half_base := h / sqrt(3.0)
	var cy := 0.5 + h / 6.0

	# Sharp corner vertices of the base triangle.
	var v0 := Vector2(0.5, cy - h * 2.0 / 3.0)
	var v1 := Vector2(0.5 + half_base, cy + h / 3.0)
	var v2 := Vector2(0.5 - half_base, cy + h / 3.0)

	var centroid_v := (v0 + v1 + v2) / 3.0

	# Bowed edge midpoints: push outward from centroid for convex edges.
	var bow_strength := 0.10
	var e01_straight := (v0 + v1) * 0.5
	var e12_straight := (v1 + v2) * 0.5
	var e20_straight := (v2 + v0) * 0.5
	var e01 := e01_straight + (e01_straight - centroid_v).normalized() * bow_strength
	var e12 := e12_straight + (e12_straight - centroid_v).normalized() * bow_strength
	var e20 := e20_straight + (e20_straight - centroid_v).normalized() * bow_strength

	# Generate bowed boundary points along each edge (Bezier curves).
	# These replace the straight v0→v1 edges so the girdle facets follow the bow.
	var segs_per_side := 4
	var sides_v: Array[Array] = [
		[v0, e01, v1],  # side 0: v0→v1
		[v1, e12, v2],  # side 1: v1→v2
		[v2, e20, v0],  # side 2: v2→v0
	]
	# For each side, generate intermediate points along the quadratic Bezier.
	# bowed_side_pts[side] = Array[Vector2] with segs_per_side+1 points (start to end).
	var bowed_side_pts: Array[Array] = []
	for side in 3:
		var va: Vector2 = sides_v[side][0]
		var ctrl: Vector2 = sides_v[side][1]
		var vb: Vector2 = sides_v[side][2]
		var pts: Array[Vector2] = []
		for j in segs_per_side + 1:
			var frac := float(j) / segs_per_side
			var p := (1.0 - frac) * (1.0 - frac) * va + 2.0 * (1.0 - frac) * frac * ctrl + frac * frac * vb
			pts.append(p)
		bowed_side_pts.append(pts)

	# Table and star rings.
	var table_f := 0.35
	var t0 := centroid_v + (v0 - centroid_v) * table_f
	var t1 := centroid_v + (v1 - centroid_v) * table_f
	var t2 := centroid_v + (v2 - centroid_v) * table_f

	# Star points: toward the bowed edge midpoints.
	var star_f := 0.65
	var s01 := centroid_v + (e01 - centroid_v) * star_f
	var s12 := centroid_v + (e12 - centroid_v) * star_f
	var s20 := centroid_v + (e20 - centroid_v) * star_f

	var star_tilt := 18.0
	var bezel_tilt := 34.0
	var girdle_tilt := 42.0

	cut.add_facet(_pva([t0, t1, t2]), Vector3(0, 0, 1), "table")

	cut.add_facet(_pva([t0, s01, t1]), _normal_for(_centroid3(t0, s01, t1), star_tilt), "star")
	cut.add_facet(_pva([t1, s12, t2]), _normal_for(_centroid3(t1, s12, t2), star_tilt), "star")
	cut.add_facet(_pva([t2, s20, t0]), _normal_for(_centroid3(t2, s20, t0), star_tilt), "star")

	# Bezel kites: from table corners to outer corners (sharp corners, no bowing).
	cut.add_facet(_pva([s20, t0, s01, v0]),
		_normal_for(_centroid_pva(_pva([s20, t0, s01, v0])), bezel_tilt), "bezel")
	cut.add_facet(_pva([s01, t1, s12, v1]),
		_normal_for(_centroid_pva(_pva([s01, t1, s12, v1])), bezel_tilt), "bezel")
	cut.add_facet(_pva([s12, t2, s20, v2]),
		_normal_for(_centroid_pva(_pva([s12, t2, s20, v2])), bezel_tilt), "bezel")

	# Girdle facets: fan from star point to bowed boundary segments.
	# side 0 (v0→v1) is fanned from s01.
	# side 1 (v1→v2) is fanned from s12.
	# side 2 (v2→v0) is fanned from s20.
	var star_pts: Array[Vector2] = [s01, s12, s20]
	for side in 3:
		var sp: Vector2 = star_pts[side]
		var bpts: Array = bowed_side_pts[side]
		for j in segs_per_side:
			var pa: Vector2 = bpts[j]
			var pb: Vector2 = bpts[j + 1]
			var tri := _pva([sp, pa, pb])
			cut.add_facet(tri, _normal_for(_centroid_pva(tri), girdle_tilt), "girdle")

	# Bowed silhouette from the same Bezier curves.
	var sil := PackedVector2Array()
	var sil_segs := 16
	for side in 3:
		var va: Vector2 = sides_v[side][0]
		var ctrl: Vector2 = sides_v[side][1]
		var vb: Vector2 = sides_v[side][2]
		for j in sil_segs:
			var frac := float(j) / sil_segs
			sil.append((1.0 - frac) * (1.0 - frac) * va + 2.0 * (1.0 - frac) * frac * ctrl + frac * frac * vb)

	cut.silhouette = sil
	_collect_edges(cut)
	_normalize_to_fit(cut)
	return cut


# ===========================================================================
#  T4  —  Radiant Diamond  (rotated square ◆, 45° chevron)
# ===========================================================================


static func generate_radiant_diamond() -> GemCutResource:
	var cut := GemCutResource.new()
	cut.cut_id = &"radiant_diamond"
	cut.display_name = "Radiant Diamond"
	cut.shape_category = &"rotated_square"

	var table_f := 0.35
	var t := table_f * GEM_RADIUS
	var r := GEM_RADIUS

	var o_top := CENTER + Vector2( 0, -r)
	var o_right := CENTER + Vector2( r,  0)
	var o_bottom := CENTER + Vector2( 0,  r)
	var o_left := CENTER + Vector2(-r,  0)
	var o_tr := (o_top + o_right) * 0.5
	var o_br := (o_right + o_bottom) * 0.5
	var o_bl := (o_bottom + o_left) * 0.5
	var o_tl := (o_left + o_top) * 0.5

	var t_top := CENTER + Vector2( 0, -t)
	var t_right := CENTER + Vector2( t,  0)
	var t_bottom := CENTER + Vector2( 0,  t)
	var t_left := CENTER + Vector2(-t,  0)
	var t_tr := (t_top + t_right) * 0.5
	var t_br := (t_right + t_bottom) * 0.5
	var t_bl := (t_bottom + t_left) * 0.5
	var t_tl := (t_left + t_top) * 0.5

	var star_tilt := 20.0
	var chevron_tilt := 35.0

	cut.add_facet(_pva([t_top, t_right, t_bottom, t_left]), Vector3(0, 0, 1), "table")

	var quads: Array = [
		[t_top,    t_tl, t_tr, o_top,    o_tl, o_tr],
		[t_right,  t_tr, t_br, o_right,  o_tr, o_br],
		[t_bottom, t_br, t_bl, o_bottom, o_br, o_bl],
		[t_left,   t_bl, t_tl, o_left,   o_bl, o_tl],
	]
	for q in quads:
		var tc: Vector2 = q[0]
		var tm_a: Vector2 = q[1]
		var tm_b: Vector2 = q[2]
		var oc: Vector2 = q[3]
		var om_a: Vector2 = q[4]
		var om_b: Vector2 = q[5]

		var kite := _pva([tc, om_a, oc, om_b])
		cut.add_facet(kite, _normal_for(_centroid_pva(kite), chevron_tilt), "bezel")
		var sa := _pva([tm_a, tc, om_a])
		cut.add_facet(sa, _normal_for(_centroid_pva(sa), star_tilt), "star")
		var sb := _pva([tm_b, om_b, tc])
		cut.add_facet(sb, _normal_for(_centroid_pva(sb), star_tilt), "star")

	cut.silhouette = _pva([o_top, o_right, o_bottom, o_left])
	_collect_edges(cut)
	_normalize_to_fit(cut)
	return cut


# ===========================================================================
#  T5  —  Hex Brilliant  (hexagon, N=6, true hex silhouette)
# ===========================================================================


static func generate_hex_brilliant() -> GemCutResource:
	var cut := GemCutResource.new()
	cut.cut_id = &"hex_brilliant"
	cut.display_name = "Hex Brilliant"
	cut.shape_category = &"hexagon"

	# Flat-top hexagon with N=6 radial symmetry.
	# Key difference from round: the girdle vertices sit exactly on the hex
	# boundary, and the silhouette is the 6-vertex hexagon (not 12-sided).
	var N := 6
	var table_r := 0.50
	var star_r := 0.70
	var step := TAU / N

	var star_tilt := 18.0
	var bezel_tilt := 32.0
	var girdle_tilt := 42.0

	var table_v: Array[Vector2] = []
	var star_v: Array[Vector2] = []
	var girdle_m: Array[Vector2] = []  # 6 vertices on the hex corners
	var girdle_h: Array[Vector2] = []  # 6 midpoints on hex edges

	for i in N:
		var main_a := float(i) * step - PI * 0.5  # flat-top orientation
		var half_a := main_a + step * 0.5
		table_v.append(_polar(table_r, main_a))
		star_v.append(_polar(star_r, half_a))
		girdle_m.append(_polar(1.0, main_a))
		# Hex edge midpoint: lies ON the hex edge, NOT on the circumscribed circle.
		# The inradius of a regular hex = circumradius * cos(30°) ≈ 0.866.
		var hex_edge_r := cos(PI / N)  # distance from centre to edge midpoint
		girdle_h.append(_polar(hex_edge_r, half_a))

	cut.add_facet(_pva(table_v), Vector3(0, 0, 1), "table")

	for i in N:
		var ni := (i + 1) % N
		var poly := _pva([table_v[i], star_v[i], table_v[ni]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), star_tilt), "star")

	for i in N:
		var pi2 := (i - 1 + N) % N
		var poly := _pva([star_v[pi2], table_v[i], star_v[i], girdle_m[i]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), bezel_tilt), "bezel")

	for i in N:
		var ni := (i + 1) % N
		var pl := _pva([star_v[i], girdle_m[i], girdle_h[i]])
		cut.add_facet(pl, _normal_for(_centroid_pva(pl), girdle_tilt), "girdle")
		var pr := _pva([star_v[i], girdle_h[i], girdle_m[ni]])
		cut.add_facet(pr, _normal_for(_centroid_pva(pr), girdle_tilt), "girdle")

	# Silhouette is the 6-vertex hexagon only.
	cut.silhouette = _pva(girdle_m)
	_collect_edges(cut)
	_normalize_to_fit(cut)
	return cut


# ===========================================================================
#  T6  —  Emerald Step  (portrait rectangle, chamfered corners, concentric steps)
# ===========================================================================


static func generate_emerald_step() -> GemCutResource:
	var cut := GemCutResource.new()
	cut.cut_id = &"emerald_step"
	cut.display_name = "Emerald Step"
	cut.shape_category = &"rectangle"

	# Portrait orientation: taller than wide.
	var aspect := 1.35
	var rw := GEM_RADIUS / aspect   # narrow (horizontal)
	var rh := GEM_RADIUS            # tall (vertical)
	var chamfer := 0.22

	var ring_scales: Array[float] = [1.0, 0.65, 0.35]
	var ring_tilts: Array[float] = [42.0, 25.0, 0.0]
	var ring_zones: Array[String] = ["girdle", "step", "table"]
	var rings: Array[Array] = []

	for scale in ring_scales:
		var w := rw * scale
		var h := rh * scale
		var c := chamfer * w  # chamfer based on shorter dimension
		rings.append([
			CENTER + Vector2(-w + c, -h),
			CENTER + Vector2( w - c, -h),
			CENTER + Vector2( w,     -h + c),
			CENTER + Vector2( w,      h - c),
			CENTER + Vector2( w - c,  h),
			CENTER + Vector2(-w + c,  h),
			CENTER + Vector2(-w,      h - c),
			CENTER + Vector2(-w,     -h + c),
		])

	cut.add_facet(_pva(rings[2]), Vector3(0, 0, 1), "table")

	for r_idx in 2:
		var outer: Array = rings[r_idx]
		var inner: Array = rings[r_idx + 1]
		var tilt: float = ring_tilts[r_idx]
		var zone: String = ring_zones[r_idx]
		var n_pts := outer.size()

		for i in n_pts:
			var ni := (i + 1) % n_pts
			var quad := _pva([inner[i], inner[ni], outer[ni], outer[i]])
			cut.add_facet(quad, _normal_for(_centroid_pva(quad), tilt), zone)

	cut.silhouette = _pva(rings[0])
	_collect_edges(cut)
	_normalize_to_fit(cut)
	return cut


# ===========================================================================
#  T7  —  Oval Brilliant  (stretched round, N=8, portrait)
# ===========================================================================


static func generate_oval_brilliant() -> GemCutResource:
	var cut := GemCutResource.new()
	cut.cut_id = &"oval_brilliant"
	cut.display_name = "Oval Brilliant"
	cut.shape_category = &"oval"

	var N := 8
	var table_r := 0.53
	var star_r := 0.72
	var step := TAU / N
	# Portrait: narrow X, tall Y.
	var aspect_x := 0.78
	var aspect_y := 1.10

	var star_tilt := 18.0
	var bezel_tilt := 32.0
	var girdle_tilt := 42.0

	var table_v: Array[Vector2] = []
	var star_v: Array[Vector2] = []
	var girdle_m: Array[Vector2] = []
	var girdle_h: Array[Vector2] = []

	for i in N:
		var main_a := float(i) * step - PI * 0.5
		var half_a := main_a + step * 0.5
		table_v.append(_polar_ellipse(table_r * aspect_x, table_r * aspect_y, main_a))
		star_v.append(_polar_ellipse(star_r * aspect_x, star_r * aspect_y, half_a))
		girdle_m.append(_polar_ellipse(aspect_x, aspect_y, main_a))
		girdle_h.append(_polar_ellipse(aspect_x, aspect_y, half_a))

	cut.add_facet(_pva(table_v), Vector3(0, 0, 1), "table")

	for i in N:
		var ni := (i + 1) % N
		var poly := _pva([table_v[i], star_v[i], table_v[ni]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), star_tilt), "star")

	for i in N:
		var pi2 := (i - 1 + N) % N
		var poly := _pva([star_v[pi2], table_v[i], star_v[i], girdle_m[i]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), bezel_tilt), "bezel")

	for i in N:
		var ni := (i + 1) % N
		var pl := _pva([star_v[i], girdle_m[i], girdle_h[i]])
		cut.add_facet(pl, _normal_for(_centroid_pva(pl), girdle_tilt), "girdle")
		var pr := _pva([star_v[i], girdle_h[i], girdle_m[ni]])
		cut.add_facet(pr, _normal_for(_centroid_pva(pr), girdle_tilt), "girdle")

	cut.silhouette = _ellipse_silhouette(aspect_x, aspect_y, 64)
	_collect_edges(cut)
	_normalize_to_fit(cut)
	return cut


# ===========================================================================
#  T8  —  Pear Brilliant  (teardrop: round bottom, pointed top, convex shoulders)
# ===========================================================================


static func generate_pear_brilliant() -> GemCutResource:
	var cut := GemCutResource.new()
	cut.cut_id = &"pear_brilliant"
	cut.display_name = "Pear Brilliant"
	cut.shape_category = &"pear"

	var N := 10
	var table_r := 0.48
	var star_r := 0.68
	var step := TAU / N

	var star_tilt := 18.0
	var bezel_tilt := 32.0
	var girdle_tilt := 42.0

	var table_v: Array[Vector2] = []
	var star_v: Array[Vector2] = []
	var girdle_m: Array[Vector2] = []
	var girdle_h: Array[Vector2] = []

	for i in N:
		var main_a := float(i) * step - PI * 0.5
		var half_a := main_a + step * 0.5
		table_v.append(_pear_point(table_r, main_a))
		star_v.append(_pear_point(star_r, half_a))
		girdle_m.append(_pear_point(1.0, main_a))
		girdle_h.append(_pear_point(1.0, half_a))

	cut.add_facet(_pva(table_v), Vector3(0, 0, 1), "table")

	for i in N:
		var ni := (i + 1) % N
		var poly := _pva([table_v[i], star_v[i], table_v[ni]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), star_tilt), "star")

	for i in N:
		var pi2 := (i - 1 + N) % N
		var poly := _pva([star_v[pi2], table_v[i], star_v[i], girdle_m[i]])
		cut.add_facet(poly, _normal_for(_centroid_pva(poly), bezel_tilt), "bezel")

	for i in N:
		var ni := (i + 1) % N
		var pl := _pva([star_v[i], girdle_m[i], girdle_h[i]])
		cut.add_facet(pl, _normal_for(_centroid_pva(pl), girdle_tilt), "girdle")
		var pr := _pva([star_v[i], girdle_h[i], girdle_m[ni]])
		cut.add_facet(pr, _normal_for(_centroid_pva(pr), girdle_tilt), "girdle")

	cut.silhouette = _pear_silhouette(64)
	_collect_edges(cut)
	_normalize_to_fit(cut)
	return cut


# ===========================================================================
#  Geometry helpers
# ===========================================================================


## Point on a circle at the given radius factor and angle.
static func _polar(radius_factor: float, angle: float) -> Vector2:
	return CENTER + Vector2(cos(angle), sin(angle)) * radius_factor * GEM_RADIUS


## Point on an ellipse with separate X/Y radius factors.
static func _polar_ellipse(rx: float, ry: float, angle: float) -> Vector2:
	return CENTER + Vector2(cos(angle) * rx, sin(angle) * ry) * GEM_RADIUS


## Point on a squircle (superellipse) curve — produces a rounded square.
## n controls the shape: 2 = circle, ~3.5 = cushion, high values → sharp square.
## The flat sides naturally face cardinal directions (up/down/left/right)
## and corners sit at 45° diagonals.
static func _squircle_point(radius_factor: float, angle: float, n: float) -> Vector2:
	var ca := cos(angle)
	var sa := sin(angle)
	# Superellipse radius: r(a) = (|cos|^n + |sin|^n)^(-1/n)
	var abs_ca := absf(ca)
	var abs_sa := absf(sa)
	# Guard against zero (at exact cardinal directions one component is ~0)
	var rr := pow(pow(abs_ca, n) + pow(abs_sa, n), -1.0 / n) if (abs_ca > 0.001 or abs_sa > 0.001) else 1.0
	return CENTER + Vector2(ca, sa) * rr * GEM_RADIUS * radius_factor


## Point on a pear-shaped (teardrop) curve with convex shoulders.
##
## Uses vertical position (sin of angle) to determine width, so the curve
## is symmetric left-to-right.  Bottom is round, top narrows to a point.
static func _pear_point(radius_factor: float, angle: float) -> Vector2:
	# sin(angle): -1 at top (point), +1 at bottom (round base).
	var vertical := sin(angle)

	# t: 0 at bottom (wide), 1 at top (narrow).
	var t := clampf((-vertical + 1.0) * 0.5, 0.0, 1.0)

	# Width envelope: stays wide (convex shoulders) then drops to zero at the point.
	# cos(t * PI/2)^0.6  →  1.0 at bottom, ~0.76 at midpoint, 0.0 at tip.
	var width_f := pow(maxf(cos(t * PI * 0.5), 0.0), 0.6)

	# Vertical stretch: elongate slightly.
	var y_stretch := 1.15

	var x := cos(angle) * width_f * radius_factor * GEM_RADIUS
	var y := sin(angle) * y_stretch * radius_factor * GEM_RADIUS

	# Shift centroid downward so the point sits near the top of the cell.
	var shift_y := 0.06 * radius_factor * GEM_RADIUS
	return CENTER + Vector2(x, y + shift_y)


## Pseudo-3D normal from a 2D centroid and a tilt angle (degrees from vertical).
static func _normal_for(centroid: Vector2, tilt_deg: float) -> Vector3:
	if tilt_deg < 0.01:
		return Vector3(0.0, 0.0, 1.0)
	var radial := (centroid - CENTER)
	if radial.length_squared() < 0.0001:
		return Vector3(0.0, 0.0, 1.0)
	radial = radial.normalized()
	var tilt := deg_to_rad(tilt_deg)
	return Vector3(radial.x * sin(tilt), radial.y * sin(tilt), cos(tilt)).normalized()


## Shorthand: create a PackedVector2Array from an Array of Vector2.
static func _pva(points: Array) -> PackedVector2Array:
	var p := PackedVector2Array()
	p.resize(points.size())
	for i in points.size():
		p[i] = points[i]
	return p


## Centroid of a PackedVector2Array.
static func _centroid_pva(verts: PackedVector2Array) -> Vector2:
	var sum := Vector2.ZERO
	for v in verts:
		sum += v
	return sum / verts.size()


## Centroid of three points.
static func _centroid3(a: Vector2, b: Vector2, c: Vector2) -> Vector2:
	return (a + b + c) / 3.0


## Circular silhouette (N-point regular polygon).
static func _circle_silhouette(num_points: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(num_points)
	for i in num_points:
		var a := float(i) / num_points * TAU - PI * 0.5
		pts[i] = _polar(1.0, a)
	return pts


## Elliptical silhouette.
static func _ellipse_silhouette(rx: float, ry: float, num_points: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(num_points)
	for i in num_points:
		var a := float(i) / num_points * TAU - PI * 0.5
		pts[i] = _polar_ellipse(rx, ry, a)
	return pts


## Pear-shaped silhouette.
static func _pear_silhouette(num_points: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	pts.resize(num_points)
	for i in num_points:
		var a := float(i) / num_points * TAU - PI * 0.5
		pts[i] = _pear_point(1.0, a)
	return pts


# ===========================================================================
#  Auto-fit normalization
# ===========================================================================


## Scales and re-centres all geometry in a GemCutResource so that the
## outermost vertex sits exactly at FIT_MARGIN from the [0,1] cell edge.
## This guarantees consistent visual sizing regardless of shape/aspect ratio.
static func _normalize_to_fit(cut: GemCutResource) -> void:
	# 1. Find the bounding box of ALL vertices (facets + silhouette + edges).
	var min_pt := Vector2(INF, INF)
	var max_pt := Vector2(-INF, -INF)

	for poly in cut.facet_vertices:
		for v in poly:
			min_pt = Vector2(minf(min_pt.x, v.x), minf(min_pt.y, v.y))
			max_pt = Vector2(maxf(max_pt.x, v.x), maxf(max_pt.y, v.y))
	for v in cut.silhouette:
		min_pt = Vector2(minf(min_pt.x, v.x), minf(min_pt.y, v.y))
		max_pt = Vector2(maxf(max_pt.x, v.x), maxf(max_pt.y, v.y))
	for seg in cut.edge_segments:
		for v in seg:
			min_pt = Vector2(minf(min_pt.x, v.x), minf(min_pt.y, v.y))
			max_pt = Vector2(maxf(max_pt.x, v.x), maxf(max_pt.y, v.y))

	if min_pt.x >= max_pt.x or min_pt.y >= max_pt.y:
		return  # degenerate

	# 2. Current centre and extent.
	var current_center := (min_pt + max_pt) * 0.5
	var extent := max_pt - min_pt  # width, height

	# 3. Target: fit within [FIT_MARGIN, 1-FIT_MARGIN] on both axes.
	var target_size := 1.0 - 2.0 * FIT_MARGIN
	var scale_factor := target_size / maxf(extent.x, extent.y)

	# 4. Apply: translate to origin, scale, translate to centre.
	var _transform := func(v: Vector2) -> Vector2:
		return (v - current_center) * scale_factor + CENTER

	for i in cut.facet_vertices.size():
		var poly := cut.facet_vertices[i]
		var new_poly := PackedVector2Array()
		new_poly.resize(poly.size())
		for j in poly.size():
			new_poly[j] = _transform.call(poly[j])
		cut.facet_vertices[i] = new_poly

	var new_sil := PackedVector2Array()
	new_sil.resize(cut.silhouette.size())
	for j in cut.silhouette.size():
		new_sil[j] = _transform.call(cut.silhouette[j])
	cut.silhouette = new_sil

	var new_edges: Array[PackedVector2Array] = []
	for seg in cut.edge_segments:
		var new_seg := PackedVector2Array()
		new_seg.resize(seg.size())
		for j in seg.size():
			new_seg[j] = _transform.call(seg[j])
		new_edges.append(new_seg)
	cut.edge_segments = new_edges


## Collects all unique edges from facet boundaries and adds them to the cut.
static func _collect_edges(cut: GemCutResource) -> void:
	var seen := {}
	for fi in cut.facet_count():
		var verts := cut.facet_vertices[fi]
		for j in verts.size():
			var a := verts[j]
			var b := verts[(j + 1) % verts.size()]
			var key := _edge_key(a, b)
			if not seen.has(key):
				seen[key] = true
				cut.add_edge(a, b)


## Canonical string key for an edge, order-independent.
static func _edge_key(a: Vector2, b: Vector2) -> String:
	var ax: float = snapped(a.x, 0.0001)
	var ay: float = snapped(a.y, 0.0001)
	var bx: float = snapped(b.x, 0.0001)
	var by: float = snapped(b.y, 0.0001)
	if ax < bx or (ax == bx and ay < by):
		return "%s,%s-%s,%s" % [ax, ay, bx, by]
	return "%s,%s-%s,%s" % [bx, by, ax, ay]
