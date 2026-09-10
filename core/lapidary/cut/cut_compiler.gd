extends RefCounted
## Material-independent facet program. Explicit proportions create the nominal
## shape; bounded workmanship errors change real plane normals and positions.
## compile(template, shape, seed, tolerances) uses tolerances in degrees for
## azimuth/polar and normalized stone units for inward/girdle offsets.
## No refractive-index or grade law changes the authored design.

const SilhouetteLib := preload("res://core/lapidary/cut/silhouettes.gd")
const HullValidator := preload("res://core/lapidary/cut/hull_validator.gd")

# Zone ids per KERNEL_CONTRACT.md.
const ZONE_TABLE := 0
const ZONE_CROWN := 1
const ZONE_UPPER_GIRDLE := 2
const ZONE_GIRDLE := 3
const ZONE_PAVILION_MAIN := 4
const ZONE_LOWER_GIRDLE := 5
const ZONE_CULET := 6
const ZONE_STEP := 7

const ROW_BREAK := &"break"
const ROW_STEP := &"step"
const ROW_STAR := &"star"
const PAVILION_FAN := &"fan_brilliant"
const PAVILION_STEP := &"step"

const GIRDLE_JITTER_SAFETY := 0.3
## Step-row planes closer than this (normal angle / offset) are duplicates
## produced by exact silhouette flats.
const STEP_DEDUP_ANGLE_RAD := 0.002
const STEP_DEDUP_OFFSET := 1.0e-4


static func compile(template: GemCutTemplate, shape: GemShape, seed: int, tolerances := Vector4.ZERO) -> Dictionary:
	if shape == null:
		push_error("Cut shape is missing")
		return _failure()
	if not tolerances.is_finite() or tolerances.x < 0 or tolerances.y < 0 or tolerances.z < 0 or tolerances.w < 0:
		push_error("Cut tolerances must be finite and nonnegative")
		return _failure()
	var silhouette := shape.outline
	var invalid_template := template_error(template)
	if invalid_template != "":
		push_error("cut_compiler: template '%s' invalid: %s" % [str(template), invalid_template])
		return _failure()
	var sil: SilhouetteLib.Silhouette = SilhouetteLib.make(silhouette, shape)
	if sil == null:
		push_error("cut_compiler: unknown silhouette '%s'" % silhouette)
		return _failure()

	var jn := tolerances
	var state := [_mix_seed(seed, silhouette, template.cut_id)]
	var pavilion_deg := template.pavilion_angle_deg

	var planes := PackedFloat32Array()
	var anchors := PackedVector3Array()

	# ---- crown rows + table ------------------------------------------------
	var table_eff := template.table_ratio
	_build_crown(planes, anchors, template, sil, jn, table_eff, state)

	# ---- girdle ring (drives the outline) ----------------------------------
	var supports: Dictionary = SilhouetteLib.girdle_supports(sil)
	var girdle_normals: PackedVector2Array = supports["normals"]
	var girdle_points: PackedVector2Array = supports["points"]
	var jitter_mask: PackedByteArray = supports.get("jitter", PackedByteArray())
	var girdle_ds := _girdle_offsets(girdle_normals, girdle_points, jn, state, jitter_mask)
	for i in girdle_points.size():
		var n2 := girdle_normals[i]
		var p2 := girdle_points[i]
		_emit(planes, anchors, Vector3(n2.x, n2.y, 0.0), girdle_ds[i], ZONE_GIRDLE,
			Vector3(p2.x, p2.y, 0.0))

	# ---- pavilion + culet ---------------------------------------------------
	_build_pavilion(planes, anchors, template, sil, jn, pavilion_deg, state)
	var axis_depth := INF
	for i in planes.size() / 8:
		var nz := planes[i * 8 + 2]
		if nz < -0.05:
			axis_depth = minf(axis_depth, planes[i * 8 + 3] / -nz)
	var culet_d := template.culet_depth_fraction * axis_depth
	_emit(planes, anchors, Vector3(0, 0, -1), culet_d, ZONE_CULET, Vector3(0, 0, -culet_d))

	# ---- outline + validation ----------------------------------------------
	var outline := _outline_from_lines(girdle_normals, girdle_ds)
	var warnings := PackedStringArray()
	if not HullValidator.check_bounded(planes):
		push_error("cut_compiler: hull unbounded (template '%s' on '%s')" % [template.cut_id, silhouette])
		return _failure()
	if outline.size() < 3:
		push_error("cut_compiler: degenerate outline (template '%s' on '%s')" % [template.cut_id, silhouette])
		return _failure()

	# Prune planes whose face is exactly empty. Redundant half-spaces cannot
	# change the solid; they appear when meeting-error jitter erases a sliver
	# facet (a real lapidary defect — knife-edge girdles, vanished facets on
	# soft corners) or when a fan facet cannot fit a pointed silhouette. The
	# 2D outline keeps ALL girdle lines: the sprite silhouette stays faithful
	# even where the 3D tip has gone knife-edge.
	var facet_ids := PackedInt32Array()
	for index in planes.size() / 8:
		facet_ids.append(index)
	var dead: PackedInt32Array = HullValidator.find_dead_planes(planes)
	var pruned := dead.size()
	if pruned > 0:
		var kept_planes := PackedFloat32Array()
		var kept_anchors := PackedVector3Array()
		var kept_ids := PackedInt32Array()
		var next_dead := 0
		for i in planes.size() / 8:
			if next_dead < dead.size() and dead[next_dead] == i:
				next_dead += 1
				continue
			for k in 8:
				kept_planes.append(planes[i * 8 + k])
			kept_anchors.append(anchors[i])
			kept_ids.append(facet_ids[i])
		planes = kept_planes
		anchors = kept_anchors
		facet_ids = kept_ids

	if not HullValidator.check_bounded(planes):
		push_error("cut_compiler: pruning produced an open hull")
		return _failure()

	if not HullValidator.is_outline_convex(outline):
		warnings.append("outline not convex")
		push_warning("cut_compiler: template '%s' on '%s': outline not convex" % [template.cut_id, silhouette])

	return {
		"planes": planes,
		"facet_ids": facet_ids,
		"outline": outline,
		"pavilion_deg": pavilion_deg,
		"sectors": sil.sectors,
		"warnings": warnings,
		"pruned_planes": pruned,
		"anchors": anchors,
	}


# ------------------------------------------------------------------ crown

static func _build_crown(planes: PackedFloat32Array, anchors: PackedVector3Array,
		template: GemCutTemplate, sil: SilhouetteLib.Silhouette, jn: Vector4,
		table_eff: float, state: Array) -> void:
	var g := template.girdle_half_height
	var sectors := sil.sectors
	var main_auth := maxf(template.crown_rows[0].angle_deg, 1.0)
	var crown_factor := 1.0
	var main_eff_rad := deg_to_rad(main_auth * crown_factor)

	# Step rows: silhouette-following frames shrunk by PERPENDICULAR INSET
	# (support-function erosion) — the actual lapidary operation. Central
	# scaling is wrong on non-round shapes: azimuths advance at different
	# rates and later frames poke outside their own row neighbours. Erosion
	# keeps frames constant-width, makes the per-row z advance one scalar,
	# and each frame's anchors land EXACTLY on the previous row's planes.
	var step_count := 2 * sectors
	var step_phase := 0.5
	var span_sum := 0.0
	for row in template.crown_rows:
		if row.kind == ROW_STEP:
			if span_sum == 0.0:
				step_phase = row.phase
			span_sum += maxf(row.span, 1.0e-3)
	var step_m := PackedVector2Array()
	var step_p := PackedVector2Array()
	var inset_total := 0.0
	if span_sum > 0.0:
		var h_min := INF
		for j in step_count:
			var phi := TAU * (float(j) + step_phase) / float(step_count)
			var p2 := sil.point(phi)
			var m2 := sil.outward_normal(phi)
			step_m.append(m2)
			step_p.append(p2)
			h_min = minf(h_min, m2.dot(p2))
		# Erode until the SHORT axis is at table_eff of its half-width; long
		# axes keep more, so step tables read elongated (real emerald cuts).
		inset_total = (1.0 - table_eff) * h_min

	var o_state := 0.0	# accumulated perpendicular inset
	var z_state := g	# crown build height (scalar — exact under erosion)
	var has_steps := false
	var seen_break := false
	var crown_start := planes.size() / 8
	for row in template.crown_rows:
		var angle_eff_deg: float = row.angle_deg * crown_factor
		match row.kind:
			ROW_BREAK:
				var zone := ZONE_UPPER_GIRDLE if seen_break else ZONE_CROWN
				seen_break = true
				var count := sectors * maxi(row.density, 1)
				for j in count:
					var phi := TAU * (float(j) + row.phase) / float(count)
					var u := Vector2(cos(phi), sin(phi))
					# Anchor on the SUPPORT point so the facet grazes the
					# silhouette at girdle height. Ray-point anchoring
					# overcuts flat-sided shapes (plane dips below z = g
					# at other azimuths and eats the girdle band).
					var p2 := sil.support_point(u) - u * o_state
					var n := _facet_normal(_jitter_azimuth(u, jn, state),
						deg_to_rad(angle_eff_deg) + _jitter_polar(jn, state), false)
					var anchor := Vector3(p2.x, p2.y, z_state)
					var d := n.dot(anchor) - _offset_jitter(jn, state)
					_emit(planes, anchors, n, d, zone, anchor)
			ROW_STAR:
				# Table-adjacent fan anchored exactly on the crown surface
				# built so far, so it always cuts inward of its touch ring.
				var count := sectors * maxi(row.density, 1)
				var place := clampf(row.span if row.span > 0.0 else 0.5, 0.05, 0.95)
				var s_star := table_eff + place * (1.0 - table_eff)
				for j in count:
					var phi := TAU * (float(j) + row.phase) / float(count)
					var u := Vector2(cos(phi), sin(phi))
					var lat := sil.support_point(u) * s_star
					var z_anchor := _crown_surface_z(planes, crown_start, lat, g)
					var n := _facet_normal(_jitter_azimuth(u, jn, state),
						deg_to_rad(angle_eff_deg) + _jitter_polar(jn, state), false)
					var anchor := Vector3(lat.x, lat.y, z_anchor)
					var d := n.dot(anchor) - _offset_jitter(jn, state)
					_emit(planes, anchors, n, d, ZONE_CROWN, anchor)
			ROW_STEP:
				has_steps = true
				var d_o := (maxf(row.span, 1.0e-3) / span_sum) * inset_total
				var angle_rad := deg_to_rad(angle_eff_deg)
				_emit_step_row(planes, anchors, step_m, step_p, o_state, z_state,
					angle_rad, false, ZONE_STEP, jn, state)
				z_state += d_o * tan(angle_rad)
				o_state += d_o

	# Table plane: where the crown program reaches table scale. With step
	# rows the scalar z_state IS the table height (frames close exactly).
	var z_table: float
	if has_steps:
		z_table = z_state
	else:
		var first := template.crown_rows[0]
		var count := sectors * maxi(first.density, 1)
		var h_sum := 0.0
		for j in count:
			var phi := TAU * (float(j) + first.phase) / float(count)
			h_sum += sil.support(Vector2(cos(phi), sin(phi)))
		z_table = g + (1.0 - table_eff) * (h_sum / float(count)) * tan(main_eff_rad)
	_emit(planes, anchors, Vector3(0, 0, 1), z_table, ZONE_TABLE, Vector3(0, 0, z_table))


# ------------------------------------------------------------------ pavilion

static func _build_pavilion(planes: PackedFloat32Array, anchors: PackedVector3Array,
		template: GemCutTemplate, sil: SilhouetteLib.Silhouette, jn: Vector4,
		authored_deg: float, state: Array) -> void:
	var g := template.girdle_half_height
	var sectors := sil.sectors
	match template.pavilion_style:
		PAVILION_FAN:
			# Radial fan; mains share the crown main phase (real brilliants
			# align crown bezels with pavilion mains). Support anchoring, as
			# in the crown, so facets graze the girdle instead of eating it.
			var pav_phase := template.crown_rows[0].phase
			var a_main := deg_to_rad(authored_deg)
			for j in sectors:
				var phi := TAU * (float(j) + pav_phase) / float(sectors)
				var u := Vector2(cos(phi), sin(phi))
				var p2 := sil.support_point(u)
				var n := _facet_normal(_jitter_azimuth(u, jn, state),
					a_main + _jitter_polar(jn, state), true)
				var anchor := Vector3(p2.x, p2.y, -g)
				var d := n.dot(anchor) - _offset_jitter(jn, state)
				_emit(planes, anchors, n, d, ZONE_PAVILION_MAIN, anchor)
			var a_half := deg_to_rad(authored_deg + template.pavilion_lower_half_delta_deg)
			var half_count := 2 * sectors
			for j in half_count:
				var phi := TAU * (float(j) + 0.5) / float(half_count) + pav_phase * TAU / float(sectors)
				var u := Vector2(cos(phi), sin(phi))
				var p2 := sil.support_point(u)
				var n := _facet_normal(_jitter_azimuth(u, jn, state),
					a_half + _jitter_polar(jn, state), true)
				var anchor := Vector3(p2.x, p2.y, -g)
				var d := n.dot(anchor) - _offset_jitter(jn, state)
				_emit(planes, anchors, n, d, ZONE_LOWER_GIRDLE, anchor)
		PAVILION_STEP:
			# Concentric frames, girdle -> keel, eroded like crown steps.
			# Convexity demands the pavilion flatten toward the keel, so the
			# DEEPEST row carries the authored angle exactly and rows toward
			# the girdle steepen by delta (real emerald pavilions ~57/49/43).
			var rows := clampi(template.pavilion_rows, 2, 4)
			var delta := template.pavilion_step_delta_deg
			var keel := clampf(template.pavilion_keel_scale, 0.02, 0.5)
			var count := 2 * sectors
			var phase := 0.5
			for row in template.crown_rows:
				if row.kind == ROW_STEP:
					phase = row.phase
					break
			var p2s := PackedVector2Array()
			var m2s := PackedVector2Array()
			var h_min := INF
			for j in count:
				var phi := TAU * (float(j) + phase) / float(count)
				var p2 := sil.point(phi)
				var m2 := sil.outward_normal(phi)
				p2s.append(p2)
				m2s.append(m2)
				h_min = minf(h_min, m2.dot(p2))
			var d_o := (1.0 - keel) * h_min / float(rows)
			var o := 0.0
			var z := -g
			for k in rows:
				var a_rad := deg_to_rad(authored_deg + float(rows - 1 - k) * delta)
				_emit_step_row(planes, anchors, m2s, p2s, o, z, a_rad, true, ZONE_STEP, jn, state)
				z -= d_o * tan(a_rad)
				o += d_o


## Emit one silhouette-following frame row at perpendicular inset `o` and
## height `z`, skipping the exact duplicates that flat silhouette segments
## produce (dedup on the unjittered plane, cyclically, so jitter cannot split
## a duplicate pair into two dead-ish planes).
static func _emit_step_row(planes: PackedFloat32Array, anchors: PackedVector3Array,
		m2s: PackedVector2Array, p2s: PackedVector2Array, o: float, z: float,
		a_rad: float, downward: bool, zone: int, jn: Vector4, state: Array) -> void:
	var count := m2s.size()
	var base_n: Array[Vector3] = []
	var base_d := PackedFloat32Array()
	var keep := PackedInt32Array()
	for j in count:
		var n := _facet_normal(m2s[j], a_rad, downward)
		var lat := p2s[j] - m2s[j] * o
		base_n.append(n)
		base_d.append(n.dot(Vector3(lat.x, lat.y, z)))
	for j in count:
		var prev := keep[keep.size() - 1] if not keep.is_empty() else -1
		if prev >= 0 and _is_duplicate(base_n[j], base_d[j], base_n[prev], base_d[prev]):
			continue
		keep.append(j)
	while keep.size() >= 2 and _is_duplicate(base_n[keep[keep.size() - 1]], base_d[keep[keep.size() - 1]],
			base_n[keep[0]], base_d[keep[0]]):
		keep.remove_at(keep.size() - 1)
	for j in keep:
		var n := _facet_normal(_jitter_azimuth(m2s[j], jn, state),
			a_rad + _jitter_polar(jn, state), downward)
		var lat := p2s[j] - m2s[j] * o
		var anchor := Vector3(lat.x, lat.y, z)
		var d := n.dot(anchor) - _offset_jitter(jn, state)
		_emit(planes, anchors, n, d, zone, anchor)


static func _is_duplicate(n_a: Vector3, d_a: float, n_b: Vector3, d_b: float) -> bool:
	return n_a.angle_to(n_b) < STEP_DEDUP_ANGLE_RAD and absf(d_a - d_b) < STEP_DEDUP_OFFSET


## z of the crown surface built so far above a lateral point (min over the
## upward-facing planes emitted since crown_start).
static func _crown_surface_z(planes: PackedFloat32Array, crown_start: int,
		lat: Vector2, fallback: float) -> float:
	var z := INF
	for i in range(crown_start, planes.size() / 8):
		var nz := planes[i * 8 + 2]
		if nz < 0.2:
			continue
		var d := planes[i * 8 + 3]
		var lat_dot := planes[i * 8] * lat.x + planes[i * 8 + 1] * lat.y
		z = minf(z, (d - lat_dot) / nz)
	return z if z < INF else fallback


## Girdle unevenness: inward-only offsets on the k long edges. Corner-arc
## planes (mask bit 0) stay at authored support so rounding stays symmetric.
## Amplitude adapts to the local normal gap so jitter can never swallow a plane.
static func _girdle_offsets(normals: PackedVector2Array, points: PackedVector2Array,
		jn: Vector4, state: Array, mask := PackedByteArray()) -> PackedFloat32Array:
	var count := normals.size()
	var ds := PackedFloat32Array()
	for i in count:
		var d := normals[i].dot(points[i])
		var allowed := mask.is_empty() or (i < mask.size() and mask[i] != 0)
		if jn.w > 0.0 and allowed:
			var prev := normals[(i - 1 + count) % count]
			var next := normals[(i + 1) % count]
			var gap := minf(absf(normals[i].angle_to(prev)), absf(normals[i].angle_to(next)))
			var amp := minf(GIRDLE_JITTER_SAFETY * d * (1.0 - cos(gap)), jn.w)
			d -= amp * _rndf(state)
		ds.append(d)
	return ds


# ------------------------------------------------------------------ template

static func template_error(template: GemCutTemplate) -> String:
	if template == null:
		return "missing cut template"
	if not is_finite(template.pavilion_angle_deg) or template.pavilion_angle_deg < 10 or template.pavilion_angle_deg > 70:
		return "pavilion angle must be 10..70 degrees"
	if not is_finite(template.culet_depth_fraction) or template.culet_depth_fraction < 0.5 or template.culet_depth_fraction > 1:
		return "culet depth fraction must be 0.5..1"
	if template.crown_rows.size() > 32:
		return "at most 32 crown rows supported"
	if template.crown_rows.is_empty():
		return "no crown rows"
	var seen_break := false
	var prev_step_angle := INF
	for row in template.crown_rows:
		if row == null:
			return "null crown row"
		if row.kind != ROW_BREAK and row.kind != ROW_STEP and row.kind != ROW_STAR:
			return "unknown row kind '%s'" % row.kind
		if not is_finite(row.angle_deg) or row.angle_deg <= 5.0 or row.angle_deg >= 80.0:
			return "row angle %.1f out of (5, 80)" % row.angle_deg
		if row.density < 1 or row.density > 4 or not is_finite(row.phase) or row.phase < 0 or row.phase > 1 or not is_finite(row.span) or row.span < 0 or row.span > 1:
			return "invalid row density, phase, or span"
		match row.kind:
			ROW_BREAK:
				seen_break = true
			ROW_STAR:
				if not seen_break:
					return "star row requires a preceding break row"
			ROW_STEP:
				if row.angle_deg >= prev_step_angle:
					return "step rows must have strictly decreasing angles (convexity)"
				prev_step_angle = row.angle_deg
	if template.pavilion_style != PAVILION_FAN and template.pavilion_style != PAVILION_STEP:
		return "unknown pavilion style '%s'" % template.pavilion_style
	if not is_finite(template.table_ratio) or template.table_ratio < 0.05 or template.table_ratio > 0.95:
		return "table_ratio %.2f out of [0.05, 0.95]" % template.table_ratio
	if not is_finite(template.girdle_half_height) or template.girdle_half_height <= 0.0 or template.girdle_half_height > 0.15:
		return "girdle_half_height %.3f out of (0, 0.15]" % template.girdle_half_height
	if template.pavilion_rows < 2 or template.pavilion_rows > 4:
		return "pavilion_rows must be 2..4"
	for setting in [[template.pavilion_step_delta_deg, 1.0, 15.0], [template.pavilion_keel_scale, 0.02, 0.5], [template.pavilion_lower_half_delta_deg, 0.0, 15.0]]:
		if not is_finite(setting[0]) or setting[0] < setting[1] or setting[0] > setting[2]:
			return "invalid pavilion proportions"
	var steepest := template.pavilion_angle_deg + (template.pavilion_rows - 1) * template.pavilion_step_delta_deg if template.pavilion_style == PAVILION_STEP else template.pavilion_angle_deg + template.pavilion_lower_half_delta_deg
	if steepest >= 85:
		return "combined pavilion rows must remain below 85 degrees"
	return ""


static func _emit(planes: PackedFloat32Array, anchors: PackedVector3Array,
		n: Vector3, d: float, zone: int, anchor: Vector3) -> void:
	var un := n.normalized()
	planes.append_array(PackedFloat32Array([un.x, un.y, un.z, d, float(zone), 0.0, 0.0, 0.0]))
	anchors.append(anchor)


static func _facet_normal(m: Vector2, polar: float, downward: bool) -> Vector3:
	var sp := sin(polar)
	var cp := cos(polar)
	return Vector3(m.x * sp, m.y * sp, -cp if downward else cp)


## Zero tolerance makes the nominal design independent of the seed.
static func _jitter_azimuth(m: Vector2, jn: Vector4, state: Array) -> Vector2:
	if jn.x <= 0.0:
		return m
	return m.rotated((_rndf(state) - 0.5) * 2.0 * deg_to_rad(jn.x))


static func _jitter_polar(jn: Vector4, state: Array) -> float:
	if jn.y <= 0.0:
		return 0.0
	return (_rndf(state) - 0.5) * 2.0 * deg_to_rad(jn.y)


static func _offset_jitter(jn: Vector4, state: Array) -> float:
	if jn.z <= 0.0:
		return 0.0
	return jn.z * _rndf(state)


## Girdle outline via half-plane intersection of the (jittered) girdle tangent
## lines. Lines arrive sorted by normal azimuth; the deque walk drops lines
## swallowed by jitter so the polygon stays convex by construction.
static func _outline_from_lines(normals: PackedVector2Array, ds: PackedFloat32Array) -> PackedVector2Array:
	var count := normals.size()
	if count < 3:
		return PackedVector2Array()
	var dq: Array[int] = []
	for i in count:
		while dq.size() >= 2 and not _line_contains(normals[i], ds[i],
				_line_isect(normals, ds, dq[dq.size() - 2], dq[dq.size() - 1])):
			dq.pop_back()
		while dq.size() >= 2 and not _line_contains(normals[i], ds[i],
				_line_isect(normals, ds, dq[0], dq[1])):
			dq.pop_front()
		dq.append(i)
	while dq.size() >= 3 and not _line_contains(normals[dq[0]], ds[dq[0]],
			_line_isect(normals, ds, dq[dq.size() - 2], dq[dq.size() - 1])):
		dq.pop_back()
	while dq.size() >= 3 and not _line_contains(normals[dq[dq.size() - 1]], ds[dq[dq.size() - 1]],
			_line_isect(normals, ds, dq[0], dq[1])):
		dq.pop_front()
	var out := PackedVector2Array()
	var n := dq.size()
	if n < 3:
		return out
	for i in n:
		var v := _line_isect(normals, ds, dq[i], dq[(i + 1) % n])
		if out.size() > 0 and out[out.size() - 1].distance_to(v) < 1.0e-6:
			continue
		out.append(v)
	if out.size() >= 2 and out[out.size() - 1].distance_to(out[0]) < 1.0e-6:
		out.remove_at(out.size() - 1)
	return out


static func _line_isect(normals: PackedVector2Array, ds: PackedFloat32Array, i: int, j: int) -> Vector2:
	var na := normals[i]
	var nb := normals[j]
	var det := na.x * nb.y - na.y * nb.x
	if absf(det) < 1.0e-12:
		return Vector2(1.0e9, 1.0e9)
	return Vector2((ds[i] * nb.y - ds[j] * na.y) / det, (na.x * ds[j] - nb.x * ds[i]) / det)


static func _line_contains(n: Vector2, d: float, p: Vector2) -> bool:
	return n.dot(p) <= d + 1.0e-9


static func _mix_seed(seed: int, silhouette: StringName, cut_id: StringName) -> int:
	var s := int(seed) * 747796405 + 2891336453
	s = s ^ (String(silhouette).hash() * 2654435761)
	s = s ^ (String(cut_id).hash() * 1013904223)
	return s


## Deterministic hash RNG — same construction as LapidaryStoneCompiler._rndf.
static func _rndf(state: Array) -> float:
	var s: int = (int(state[0]) * 747796405 + 2891336453) & 0xFFFFFFFF
	state[0] = s
	var word: int = (((s >> ((s >> 28) + 4)) ^ s) * 277803737) & 0xFFFFFFFF
	return float(((word >> 22) ^ word) & 0xFFFFF) / 1048576.0


static func _failure() -> Dictionary:
	return {"planes": PackedFloat32Array(), "outline": PackedVector2Array()}
