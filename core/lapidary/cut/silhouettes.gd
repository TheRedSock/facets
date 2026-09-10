extends RefCounted
## Lapidary silhouette library: the eight tier silhouettes (CUT_TAXONOMY.md)
## as star-convex radius(theta) profiles, plus the adaptive girdle sampler.
##
## Conventions (stone space, looking down +Z):
##   - Unit max girdle radius: every profile is normalized so max radius = 1.
##   - Long axis along +X (oval, diamond, rectangle, marquise, pear).
##   - Pear points toward +X; triangle has a vertex at +X.
##   - All outlines are CONVEX by construction:
##       circle/ellipse, Minkowski-rounded regular polygons (square / triangle
##       / diamond / rectangle), vesica, disc+point convex hull.
##   - Polygon girdles: k exact edge planes plus a symmetric fan of support
##     planes on each corner arc. Flats stay flat; rounding is the same at
##     every corner. The old curvature walk broke 4-fold symmetry and read as
##     wobble. Girdle-unevenness jitter applies to the k edges only, never the
##     corner arcs.
##   - Smooth girdles: 32 support planes on a half-offset normal ring.
##   - `sectors` is the gameplay symmetry count used to anchor facet rows.
##     Profiles are oriented so multiples of TAU/sectors land on silhouette
##     features (vertices / edge centers) where the shape has them.

const SUPERSAMPLE := 720
const GIRDLE_SMOOTH := 32
## Support planes per rounded corner, not counting the two adjoining edges.
## 4 samples over 90 deg ≈ 18 deg — smooth at 112px, still 4-fold symmetric.
const CORNER_ARC_SAMPLES := 4

const KINDS: Array[StringName] = [
	&"round", &"square", &"triangle", &"oval",
	&"diamond", &"rectangle", &"marquise", &"pear",
]


class Silhouette:
	var kind: StringName = &"round"
	var sectors: int = 8
	var radial_segments: int = 32
	# Rounded regular polygon (square / triangle / diamond / rectangle).
	var poly_k: int = 0
	var poly_phase: float = 0.0
	var corner_r: float = 0.0
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
			&"square", &"triangle", &"diamond", &"rectangle":
				return _rounded_polygon_radius(theta)
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


static func make(kind: StringName, shape: GemShape = null) -> Silhouette:
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
			# Emerald-cut outline: elongated rounded rectangle, exact flats.
			s.poly_k = 4
			s.poly_phase = PI / 4.0
			s.corner_r = 0.10
			s.scale_y = 1.0 / 1.35
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
	if shape != null:
		if not is_finite(shape.aspect_ratio) or shape.aspect_ratio <= 0.0:
			return null
		var default_aspect: float = {&"oval": 1.0 / 0.78, &"diamond": 1.3, &"rectangle": 1.35, &"marquise": 1.8, &"pear": 1.4}.get(kind, 1.0)
		s.scale_y *= default_aspect / shape.aspect_ratio
		s.corner_r = clampf(shape.corner_radius, 0.0, 0.45)
		s.sectors = maxi(3, shape.sectors)
		s.radial_segments = clampi(shape.radial_segments, 8, 512)
	var peak := 0.0
	for i in SUPERSAMPLE:
		peak = maxf(peak, s.radius(TAU * float(i) / float(SUPERSAMPLE)))
	s.norm = peak
	for i in SUPERSAMPLE:
		s._pts.append(s.point(TAU * float(i) / float(SUPERSAMPLE)))
	return s


## Sample the silhouette into girdle supports: {points, normals, jitter}.
## `jitter` is a 0/1 mask: 1 = this plane may take girdle-unevenness; 0 =
## corner-arc planes that must stay symmetric. Smooth rings jitter every plane.
##
## Polygon kinds: k exact edge supports plus CORNER_ARC_SAMPLES arc supports
## per vertex (equal steps in the exterior angle). Smooth kinds: GIRDLE_SMOOTH
## normals, half-step offset so a vertex does not land on an axis of symmetry.
static func girdle_supports(sil: Silhouette) -> Dictionary:
	if sil.poly_k >= 3:
		return _polygon_supports(sil)
	return _support_ring(sil, sil.radial_segments, true)


static func _polygon_supports(sil: Silhouette) -> Dictionary:
	var out_p := PackedVector2Array()
	var out_n := PackedVector2Array()
	var jitter := PackedByteArray()
	var k := sil.poly_k
	var sector := TAU / float(k)
	var edge0 := sil.poly_phase + sector * 0.5
	var edge_n := PackedVector2Array()
	for i in k:
		var ang := edge0 + sector * float(i)
		var n := Vector2(cos(ang), sin(ang))
		if sil.scale_y != 1.0:
			n = Vector2(n.x, n.y / sil.scale_y).normalized()
		edge_n.append(n)
	var arc_n := 0 if sil.corner_r <= 1.0e-6 else CORNER_ARC_SAMPLES
	for i in k:
		out_p.append(sil.support_point(edge_n[i]))
		out_n.append(edge_n[i])
		jitter.append(1)
		if arc_n == 0:
			continue
		var a := edge_n[i]
		var b := edge_n[(i + 1) % k]
		var full := atan2(a.cross(b), a.dot(b))
		for s in arc_n:
			var t := float(s + 1) / float(arc_n + 1)
			var n := a.rotated(full * t).normalized()
			out_p.append(sil.support_point(n))
			out_n.append(n)
			jitter.append(0)
	return {"points": out_p, "normals": out_n, "jitter": jitter}


## `count` support planes whose normals are equally spaced on the circle.
## half_offset: start at 0.5 step so no normal sits on 0/90/180/270 — a vertex
## on those axes reads as a bump on an otherwise smooth cap (pear head, oval).
static func _support_ring(sil: Silhouette, count: int, half_offset: bool) -> Dictionary:
	var out_p := PackedVector2Array()
	var out_n := PackedVector2Array()
	var jitter := PackedByteArray()
	var shift := 0.5 if half_offset else 0.0
	for i in count:
		var ang := TAU * (float(i) + shift) / float(count)
		var n := Vector2(cos(ang), sin(ang))
		out_p.append(sil.support_point(n))
		out_n.append(n)
		jitter.append(1)
	return {"points": out_p, "normals": out_n, "jitter": jitter}
