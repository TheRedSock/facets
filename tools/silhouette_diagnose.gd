extends SceneTree
## Headless: quantify girdle-outline kinks vs the silhouette the tile claims.
##   godot --headless --path . --script res://tools/silhouette_diagnose.gd

const CutCompiler := preload("res://core/lapidary/cut/cut_compiler.gd")
const SilhouetteLib := preload("res://core/lapidary/cut/silhouettes.gd")

const SEED := 23


func _initialize() -> void:
	var brilliant: Resource = load("res://data/lapidary/cuts/brilliant.tres")
	var step: Resource = load("res://data/lapidary/cuts/step.tres")
	print("\n=== silhouette diagnose ===")
	print("q=1 is zero jitter. Extra verts / kinks there are the sampler, not grade.")
	for row in [
		[&"square", brilliant, 1.0], [&"square", brilliant, 0.38],
		[&"triangle", brilliant, 1.0], [&"triangle", brilliant, 0.46],
		[&"diamond", brilliant, 1.0], [&"diamond", brilliant, 0.6],
		[&"rectangle", step, 1.0], [&"rectangle", step, 0.72],
		[&"pear", brilliant, 1.0], [&"pear", brilliant, 1.0],
		[&"round", brilliant, 1.0], [&"round", brilliant, 0.3],
		[&"oval", brilliant, 1.0], [&"marquise", brilliant, 1.0],
	]:
		_report(StringName(row[0]), row[1], float(row[2]))
	print("=== done ===")
	quit(0)


func _report(sil_name: StringName, template: Resource, q: float) -> void:
	var sil: SilhouetteLib.Silhouette = SilhouetteLib.make(sil_name)
	var supports: Dictionary = SilhouetteLib.girdle_supports(sil)
	var nrm: PackedVector2Array = supports["normals"]
	var pts: PackedVector2Array = supports["points"]
	var result: Dictionary = CutCompiler.compile(template, GemShape.faceted_outline(sil_name), SEED, Vector4(2.8, 0.4, 0.004, 0.006) * (1.0 - q))
	var outline: PackedVector2Array = result["outline"]
	var max_turn := 0.0
	var turns := PackedFloat32Array()
	for i in outline.size():
		var e0 := outline[i] - outline[(i - 1 + outline.size()) % outline.size()]
		var e1 := outline[(i + 1) % outline.size()] - outline[i]
		var ang := absf(rad_to_deg(atan2(e0.x * e1.y - e0.y * e1.x, e0.dot(e1))))
		turns.append(ang)
		max_turn = maxf(max_turn, ang)
	var chord := _max_mid_edge_sagitta(outline)
	var gap_stats := _normal_gaps(nrm)
	print("%-10s q=%.2f  supports=%2d  outline=%2d  max_turn=%.1f deg  max_sagitta=%.4f  n_gap[min/med/max]=%.1f/%.1f/%.1f  extrema %s" % [
		sil_name, q, nrm.size(), outline.size(), max_turn, chord,
		gap_stats[0], gap_stats[1], gap_stats[2], _extrema(outline)])
	if sil_name == &"diamond" or sil_name == &"rectangle" or sil_name == &"pear" or sil_name == &"square":
		var ranked: Array = []
		for i in turns.size():
			ranked.append([turns[i], outline[i]])
		ranked.sort_custom(func(a, b): return a[0] > b[0])
		for k in mini(6, ranked.size()):
			var p: Vector2 = ranked[k][1]
			print("    turn %5.1f deg  at (%.3f, %.3f)  r=%.3f  theta=%.1f" % [
				ranked[k][0], p.x, p.y, p.length(), rad_to_deg(p.angle())])
		# Support-plane uniqueness: how many girdle normals are >6 deg apart.
		print("    unique-normal supports: %d   sample pts on +X-most / -Y-most: %s / %s" % [
			_unique_normals(nrm), _fmt(pts[_argmax_x(pts)]), _fmt(pts[_argmin_y(pts)])])


func _max_mid_edge_sagitta(outline: PackedVector2Array) -> float:
	# For every outline vertex, sagitta vs the chord of its two neighbours.
	# A true corner of a k-gon has large sagitta; a kink on a flat is small
	# but visible. Report the *smallest local maximum* among vertices whose
	# neighbours subtend a long chord — those are "extra angles on a side".
	var n := outline.size()
	var extra := 0.0
	for i in n:
		var a := outline[(i - 1 + n) % n]
		var b := outline[i]
		var c := outline[(i + 1) % n]
		var chord := c - a
		var len := chord.length()
		if len < 0.15:
			continue
		var t := clampf((b - a).dot(chord) / (len * len), 0.0, 1.0)
		var sag := (a + chord * t).distance_to(b)
		# Ignore the primary silhouette corners (sagitta vs a short-neighbour
		# pair is the shape itself). Keep mid-edge kinks on long sides.
		if sag > 0.002 and sag < 0.12:
			extra = maxf(extra, sag)
	return extra


func _normal_gaps(nrm: PackedVector2Array) -> Array:
	var gaps: Array[float] = []
	for i in nrm.size():
		var a := nrm[i]
		var b := nrm[(i + 1) % nrm.size()]
		gaps.append(absf(rad_to_deg(atan2(a.cross(b), a.dot(b)))))
	gaps.sort()
	if gaps.is_empty():
		return [0.0, 0.0, 0.0]
	return [gaps[0], gaps[gaps.size() / 2], gaps[gaps.size() - 1]]


func _unique_normals(nrm: PackedVector2Array) -> int:
	var n := 0
	for i in nrm.size():
		var a := nrm[i]
		var b := nrm[(i - 1 + nrm.size()) % nrm.size()]
		if absf(atan2(a.cross(b), a.dot(b))) >= 0.1047:
			n += 1
	return n


func _extrema(outline: PackedVector2Array) -> String:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in outline:
		lo.x = minf(lo.x, p.x)
		lo.y = minf(lo.y, p.y)
		hi.x = maxf(hi.x, p.x)
		hi.y = maxf(hi.y, p.y)
	return "x[%.3f,%.3f] y[%.3f,%.3f]" % [lo.x, hi.x, lo.y, hi.y]


func _argmax_x(pts: PackedVector2Array) -> int:
	var b := 0
	for i in pts.size():
		if pts[i].x > pts[b].x:
			b = i
	return b


func _argmin_y(pts: PackedVector2Array) -> int:
	var b := 0
	for i in pts.size():
		if pts[i].y < pts[b].y:
			b = i
	return b


func _fmt(p: Vector2) -> String:
	return "(%.3f,%.3f)" % [p.x, p.y]
