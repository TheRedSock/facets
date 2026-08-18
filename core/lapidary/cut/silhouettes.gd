extends RefCounted
## Lapidary silhouette library: the eight tier silhouettes (CUT_TAXONOMY.md)
## as star-convex radius(theta) profiles, plus the adaptive girdle sampler.
##
## Conventions (stone space, looking down +Z):
##   - Unit max girdle radius: every profile is normalized so max radius = 1.
##   - Long axis along +X (oval, diamond, rectangle, marquise, pear).
##   - Pear points toward +X; triangle has a vertex at +X.
##   - All outlines are CONVEX by construction:
##       circle/ellipse, superellipse (n >= 2), Minkowski-rounded regular
##       polygons, vesica (disc intersection), disc+point convex hull.
##   - `sectors` is the gameplay symmetry count used to anchor facet rows.
##     Profiles are oriented so multiples of TAU/sectors land on silhouette
##     features (vertices / edge centers) where the shape has them.

const SUPERSAMPLE := 720
const GIRDLE_MIN := 16
const GIRDLE_MAX := 44
const FAN_MAX := 10
## Share of the sampling measure distributed uniformly in theta (the rest
## follows turning angle, i.e. curvature mass).
const UNIFORM_MEASURE_SHARE := 0.35
## Minimum normal-angle gap between girdle planes (~6 deg). Near-parallel
## tangent planes on flat silhouette segments are redundant and make the
## outline fragile under girdle unevenness jitter.
const MIN_NORMAL_GAP_RAD := 0.1047

const KINDS: Array[StringName] = [
	&"round", &"square", &"triangle", &"oval",
	&"diamond", &"rectangle", &"marquise", &"pear",
]


class Silhouette:
	var kind: StringName = &"round"
	var sectors: int = 8
	# Rounded regular polygon (square / triangle / diamond).
	var poly_k: int = 0
	var poly_phase: float = 0.0
	var corner_r: float = 0.0
	# Superellipse (rectangle).
	var exponent: float = 4.0
	var semi_b: float = 1.0
	# Ellipse (oval).
	var ellipse_b: float = 1.0
	# Vesica lens (marquise): two discs radius ves_r centered (0, ±ves_c).
	var ves_c: float = 0.0
	var ves_r: float = 1.0
	# Teardrop (pear): disc radius pear_b at origin + apex at +X; tangent
	# contact azimuth pear_beta = acos(pear_b / apex_radius).
	var pear_b: float = 0.0
	var pear_beta: float = 0.0
	# Anisotropic y-scale applied to the base profile (diamond elongation).
	var scale_y: float = 1.0
	# Normalization so max radius == 1 (computed once in make()).
	var norm: float = 1.0
	# Cached boundary samples (SUPERSAMPLE points, normalized) for support queries.
	var _pts := PackedVector2Array()

	## Support function h(dir) = max over the outline of dot(dir, p): the
	## offset of the tangent line with outward normal `dir`. Facet planes MUST
	## use this (not the ray point radius) so they touch the silhouette instead
	## of cutting through it — critical on flat-sided and elongated shapes.
	func support(dir: Vector2) -> float:
		var best := -INF
		for p in _pts:
			best = maxf(best, dir.dot(p))
		return best

	## The boundary point attaining support(dir) (tangency point).
	func support_point(dir: Vector2) -> Vector2:
		var best := -INF
		var bp := Vector2.ZERO
		for p in _pts:
			var s := dir.dot(p)
			if s > best:
				best = s
				bp = p
		return bp

	func radius(theta: float) -> float:
		if scale_y == 1.0:
			return _base_radius(theta) / norm
		# Scaled body S = diag(1, scale_y): r_S(u) = r_base(w) / |S^-1 u|,
		# w = normalize(S^-1 u). Convexity is preserved under linear maps.
		var v := Vector2(cos(theta), sin(theta) / scale_y)
		var len := v.length()
		return _base_radius(v.angle()) / (len * norm)

	func point(theta: float) -> Vector2:
		return Vector2(cos(theta), sin(theta)) * radius(theta)

	## Outward unit normal of the outline at azimuth theta. Central difference:
	## exact on smooth arcs, bisector at tangent discontinuities (tips).
	func outward_normal(theta: float) -> Vector2:
		var h := 1.0e-3
		var t := point(theta + h) - point(theta - h)
		var n := Vector2(t.y, -t.x)
		if n.dot(point(theta)) < 0.0:
			n = -n
		return n.normalized()

	func _base_radius(theta: float) -> float:
		match kind:
			&"round":
				return 1.0
			&"oval":
				var c := cos(theta)
				var s := sin(theta)
				return ellipse_b / sqrt(ellipse_b * ellipse_b * c * c + s * s)
			&"square", &"triangle", &"diamond":
				return _rounded_polygon_radius(theta)
			&"rectangle":
				var cn := pow(absf(cos(theta)), exponent)
				var sn := pow(absf(sin(theta)) / semi_b, exponent)
				return pow(cn + sn, -1.0 / exponent)
			&"marquise":
				var c := cos(theta)
				return -ves_c * absf(sin(theta)) + sqrt(ves_r * ves_r - ves_c * ves_c * c * c)
			&"pear":
				var t := absf(wrapf(theta, -PI, PI))
				if t >= pear_beta:
					return pear_b
				return pear_b / cos(pear_beta - t)
		return 1.0

	## Minkowski-rounded regular k-gon: inner polygon circumradius (1 - rho)
	## dilated by a disc of radius rho -> vertex radius exactly 1. The ray
	## from the origin exits through an offset edge line or a vertex arc.
	func _rounded_polygon_radius(theta: float) -> float:
		var sector := TAU / float(poly_k)
		var rel := wrapf(theta - poly_phase, -PI, PI)
		var m := roundf(rel / sector)
		var v_ang := m * sector
		var delta := rel - v_ang
		var r_in := 1.0 - corner_r
		var apothem := r_in * cos(PI / float(poly_k))
		var edge_off := apothem + corner_r
		# Candidate 1: offset edge line (normal halfway to the next vertex).
		var edge_n_rel := v_ang + (sector * 0.5 if delta >= 0.0 else -sector * 0.5)
		var ang_from_edge := rel - edge_n_rel
		var tang := edge_off * tan(ang_from_edge)
		var half_edge := r_in * sin(PI / float(poly_k))
		if absf(tang) <= half_edge:
			return edge_off / cos(ang_from_edge)
		# Candidate 2: vertex arc (circle radius rho centered on the inner vertex).
		var c_ang := poly_phase + v_ang
		var b_dot := r_in * (cos(c_ang) * cos(theta) + sin(c_ang) * sin(theta))
		var disc := b_dot * b_dot - (r_in * r_in - corner_r * corner_r)
		return b_dot + sqrt(maxf(disc, 0.0))


static func make(kind: StringName) -> Silhouette:
	var s := Silhouette.new()
	s.kind = kind
	match kind:
		&"round":
			pass
		&"oval":
			s.ellipse_b = 0.78
		&"square":
			# Edges axis-aligned (flat top reads "square" on the board),
			# corners on the diagonals -> every 45 deg is a feature azimuth.
			s.poly_k = 4
			s.poly_phase = PI / 4.0
			s.corner_r = 0.12
		&"triangle":
			# Vertex at +X; vertices and edge centers alternate every 60 deg.
			s.poly_k = 3
			s.poly_phase = 0.0
			s.corner_r = 0.14
			s.sectors = 6
		&"diamond":
			# Lozenge: rhombus vertices on the axes, elongated along +X.
			s.poly_k = 4
			s.poly_phase = 0.0
			s.corner_r = 0.07
			s.scale_y = 1.0 / 1.3
		&"rectangle":
			s.exponent = 5.0
			s.semi_b = 1.0 / 1.35
		&"marquise":
			# Vesica lens, points at +-X, aspect ~1.8.
			var w := 1.0 / 1.8
			s.ves_c = (1.0 - w * w) / (2.0 * w)
			s.ves_r = s.ves_c + w
		&"pear":
			# Teardrop: apex at +X (pre-norm radius 1), round end radius b.
			# Aspect (1 + b) / (2 b) = 1.4 -> b = 1 / 1.8.
			s.pear_b = 1.0 / 1.8
			s.pear_beta = acos(s.pear_b)
		_:
			return null
	var peak := 0.0
	for i in SUPERSAMPLE:
		peak = maxf(peak, s.radius(TAU * float(i) / float(SUPERSAMPLE)))
	s.norm = peak
	for i in SUPERSAMPLE:
		s._pts.append(s.point(TAU * float(i) / float(SUPERSAMPLE)))
	return s


## Sample the silhouette into girdle supports: {"points": PackedVector2Array,
## "normals": PackedVector2Array}, azimuth-ordered. Each support is a tangent
## contact for one vertical girdle plane. The plane count adapts to curvature
## concentration (16 for a circle, up to GIRDLE_MAX for pointed shapes) and
## the distribution follows turning angle, with explicit fans at tangent
## discontinuities (marquise / pear tips).
static func girdle_supports(sil: Silhouette) -> Dictionary:
	var m := SUPERSAMPLE
	var pts := sil._pts
	var seg_n := PackedVector2Array()
	seg_n.resize(m)
	for i in m:
		var t := pts[(i + 1) % m] - pts[i]
		seg_n[i] = Vector2(t.y, -t.x).normalized()
	var turn := PackedFloat32Array()
	turn.resize(m)
	var sum_t := 0.0
	var sum_t2 := 0.0
	for i in m:
		var a := seg_n[(i - 1 + m) % m]
		var b := seg_n[i]
		var ang := absf(atan2(a.cross(b), a.dot(b)))
		turn[i] = ang
		sum_t += ang
		sum_t2 += ang * ang
	# Effective corner count (inverse participation ratio): SUPERSAMPLE for a
	# circle, ~feature count for pointed shapes. Drives the plane budget.
	var ipr := sum_t * sum_t / maxf(sum_t2, 1.0e-12)
	var concentration := clampf(1.0 - ipr / float(m), 0.0, 1.0)
	var target := clampi(int(roundf(16.0 + 24.0 * concentration)), GIRDLE_MIN, GIRDLE_MAX)

	var uniform_step := UNIFORM_MEASURE_SHARE * sum_t / float(m)
	var quota := sum_t * (1.0 + UNIFORM_MEASURE_SHARE) / float(target)
	var out_p := PackedVector2Array()
	var out_n := PackedVector2Array()
	var cum := quota * 0.5
	for i in m:
		if turn[i] > quota * 1.5:
			# Tangent discontinuity: fan planes across the corner, all
			# touching the corner point (a polyhedral tip, no truncation).
			# Fan spacing respects MIN_NORMAL_GAP_RAD so no plane gets deduped.
			var fan := clampi(int(ceilf(turn[i] / quota)), 2, FAN_MAX)
			fan = mini(fan, maxi(int(floorf(turn[i] / MIN_NORMAL_GAP_RAD)), 2))
			var n_in := seg_n[(i - 1 + m) % m]
			var n_out := seg_n[i]
			var full := atan2(n_in.cross(n_out), n_in.dot(n_out))
			for f in fan:
				var nf := n_in.rotated(full * (float(f) + 0.5) / float(fan))
				_emit_support(out_p, out_n, pts[i], nf)
			cum = 0.0
		else:
			cum += turn[i] + uniform_step
			if cum >= quota:
				cum -= quota
				var nv := (seg_n[(i - 1 + m) % m] + seg_n[i]).normalized()
				_emit_support(out_p, out_n, pts[i], nv)
	# Wraparound dedup: last vs first.
	if out_n.size() >= 2:
		var a := out_n[out_n.size() - 1]
		var b := out_n[0]
		if absf(atan2(a.cross(b), a.dot(b))) < MIN_NORMAL_GAP_RAD:
			out_p.remove_at(out_p.size() - 1)
			out_n.remove_at(out_n.size() - 1)
	if out_p.size() < GIRDLE_MIN:
		# Degenerate walk (should not happen): uniform fallback ring.
		out_p.clear()
		out_n.clear()
		for j in GIRDLE_MIN:
			var theta := TAU * float(j) / float(GIRDLE_MIN)
			out_p.append(sil.point(theta))
			out_n.append(sil.outward_normal(theta))
	return {"points": out_p, "normals": out_n}


static func _emit_support(out_p: PackedVector2Array, out_n: PackedVector2Array,
		p: Vector2, n: Vector2) -> void:
	if out_n.size() > 0:
		var last := out_n[out_n.size() - 1]
		if absf(atan2(last.cross(n), last.dot(n))) < MIN_NORMAL_GAP_RAD:
			return
	out_p.append(p)
	out_n.append(n)
