extends RefCounted
## One declarative half-space compiler, with no crown/pavilion grammar branches.
const SilhouetteLib := preload("res://core/lapidary/cut/silhouettes.gd")
const HullValidator := preload("res://core/lapidary/cut/hull_validator.gd")
const MAX_PLANES := 512

static func template_error(template: GemCutTemplate) -> String:
	if template == null or template.groups.is_empty() or template.groups.size() > 32: return "Cut needs 1..32 facet groups"
	if template.parameters.size() > 64: return "Cut has more than 64 scalar parameters"
	for key in template.parameters:
		var value: Variant = template.parameters[key]
		if not (key is String or key is StringName) or not String(key).is_valid_identifier() or not (value is int or value is float) or not is_finite(float(value)) or absf(value) > 1e6:
			return "Cut parameters need identifiers and finite bounded scalar values"
	var seen := {}; var sets := {}; var count := 0; var used := {}
	var references_pattern := RegEx.new(); references_pattern.compile("\\bp\\.([A-Za-z_][A-Za-z_0-9]*)")
	for group in template.groups:
		if group == null: return "Null facet group"
		var error := group.validate()
		if not error.is_empty(): return error
		if seen.has(group.group_id): return "Duplicate facet group: " + String(group.group_id)
		for reference in group.meet_groups:
			if not seen.has(StringName(reference)): return "Meet needs an earlier named group: " + reference
		seen[group.group_id] = true
		var set_key := GemContentIdentity.digest(group.directions)
		if sets.has(group.directions.set_id) and sets[group.directions.set_id] != set_key: return "Direction set ID has conflicting definitions"
		sets[group.directions.set_id] = set_key
		for field in ["inclination", "scale", "inset", "height", "offset"]:
			for match_value in references_pattern.search_all(group.get(field)):
				var name := match_value.get_string(1)
				if not template.parameters.has(name): return "Unknown cut parameter: " + name
				used[name] = true
		count += group.directions.indices.size()
	for key in template.parameters:
		if not used.has(String(key)): return "Unused cut parameter: " + String(key)
	if count > MAX_PLANES: return "Facet program exceeds the plane budget"
	return ""

static func compile(template: GemCutTemplate, shape: GemShape, seed: int, tolerances := Vector4.ZERO) -> Dictionary:
	var error := template_error(template)
	if not error.is_empty(): return _failure(error)
	if shape == null or shape.mode != "faceted": return _failure("Facet program requires a faceted girdle recipe")
	if not tolerances.is_finite() or minf(minf(tolerances.x, tolerances.y), minf(tolerances.z, tolerances.w)) < 0: return _failure("Invalid manufacturing tolerances")
	var silhouette: SilhouetteLib.Silhouette = SilhouetteLib.make(shape.outline, shape)
	if silhouette == null: return _failure("Unsupported or invalid girdle boundary")
	var samples := {}; var measures := {}; var parameters := {}
	for key in template.parameters: parameters[String(key)] = float(template.parameters[key])
	for group in template.groups:
		var directions: GemFacetDirections = group.directions
		if samples.has(directions.set_id): continue
		var points := PackedVector2Array(); var normals := PackedVector2Array()
		var minimum := INF; var total := 0.0
		for index in directions.indices:
			var phi := TAU * (index + directions.phase_degrees * directions.divisions / 360.0) / directions.divisions
			var normal := Vector2(cos(phi), sin(phi)) if directions.sampling == "radial" else silhouette.outward_normal(phi)
			var point := silhouette.support_point(normal) if directions.sampling == "radial" else silhouette.point(phi)
			var support := normal.dot(point)
			minimum = minf(minimum, support); total += support
			points.append(point); normals.append(normal)
		samples[directions.set_id] = {"points": points, "normals": normals}
		measures[String(directions.set_id)] = {"min_support": minimum, "mean_support": total / points.size()}
	var records := []; var by_group := {}; var diagnostics := []; var ids := {}
	for group in template.groups:
		var values := {}
		for field in ["inclination", "scale", "inset"]:
			var evaluated := GemCutExpression.evaluate(group.get(field), parameters, measures)
			if evaluated.has("error"): return _failure(String(group.group_id) + "." + field + ": " + evaluated.error)
			values[field] = evaluated.value
		if values.inclination < 0 or values.inclination > 90: return _failure("Inclination must be in [0, 90]: " + String(group.group_id))
		var source: Dictionary = samples[group.directions.set_id]
		var nominal := []
		for index in source.points.size():
			var xy: Vector2 = source.points[index] * values.scale - source.normals[index] * values.inset
			var meet := NAN; var contacts := []
			if not group.meet_groups.is_empty():
				var solved := _envelope(by_group, group.meet_groups, xy, group.side)
				if solved.has("error"): return _failure(String(group.group_id) + ": " + solved.error)
				meet = solved.height; contacts = solved.contacts
			var height := GemCutExpression.evaluate(group.height, parameters, measures, meet)
			var displacement := GemCutExpression.evaluate(group.offset, parameters, measures, meet)
			if height.has("error"): return _failure(String(group.group_id) + ".height: " + height.error)
			if displacement.has("error"): return _failure(String(group.group_id) + ".offset: " + displacement.error)
			var anchor := Vector3(xy.x, xy.y, height.value)
			var polar := deg_to_rad(values.inclination)
			var lateral: Vector2 = source.normals[index]
			var normal := Vector3(lateral.x * sin(polar), lateral.y * sin(polar), group.side * cos(polar)).normalized()
			if values.inclination == 90: normal.z = 0.0
			var d := float(PackedFloat32Array([normal.dot(anchor) + displacement.value])[0])
			var name := String(group.group_id) + "/" + str(group.directions.indices[index])
			var id := int(name.hash() & 0x7fffffff)
			if ids.has(id): return _failure("Facet identifier collision: " + name)
			ids[id] = name
			var record := {"normal": normal, "d": d, "anchor": anchor, "zone": group.zone, "id": id, "name": name,
				"group": String(group.group_id), "contacts": contacts, "inclination": values.inclination, "side": group.side, "lateral": lateral}
			nominal.append(record)
		# Exact flats can produce repeated boundary samples. Coalesce nominally
		# before manufacturing so jitter cannot split one physical support face.
		var kept := []
		for record in nominal:
			if not kept.is_empty() and _duplicate(record, kept.back()):
				diagnostics.append({"kind": "coincident", "facet": record.name, "retained": kept.back().name}); continue
			kept.append(record)
		while kept.size() > 1 and _duplicate(kept.back(), kept[0]):
			diagnostics.append({"kind": "coincident", "facet": kept.back().name, "retained": kept[0].name}); kept.pop_back()
		by_group[String(group.group_id)] = kept
		records.append_array(kept)
	var supports: Dictionary = SilhouetteLib.girdle_supports(silhouette)
	var girdle_normals: PackedVector2Array = supports.normals
	var girdle_points: PackedVector2Array = supports.points
	var mask: PackedByteArray = supports.get("jitter", PackedByteArray())
	var girdle_offsets := PackedFloat32Array()
	for index in girdle_points.size():
		var normal: Vector2 = girdle_normals[index]
		var d := normal.dot(girdle_points[index])
		var name := "girdle/" + str(index)
		var id := int(name.hash() & 0x7fffffff)
		if ids.has(id): return _failure("Girdle identifier collision")
		ids[id] = name
		if tolerances.w > 0 and (mask.is_empty() or mask[index] != 0):
			var prev := girdle_normals[posmod(index - 1, girdle_normals.size())]
			var next := girdle_normals[(index + 1) % girdle_normals.size()]
			var gap := minf(absf(normal.angle_to(prev)), absf(normal.angle_to(next)))
			d -= minf(0.3 * d * (1 - cos(gap)), tolerances.w) * _random(seed, id, 3)
		girdle_offsets.append(d)
		records.append({"normal": Vector3(normal.x, normal.y, 0), "d": d, "anchor": Vector3(girdle_points[index].x, girdle_points[index].y, 0),
			"zone": 3, "id": id, "name": name, "group": "girdle", "contacts": [], "inclination": 90.0, "side": 1})
	if records.size() > MAX_PLANES: return _failure("Program and girdle exceed 512 planes")
	var planes := PackedFloat32Array()
	for record in records:
		var normal: Vector3 = record.normal
		var d: float = record.d
		if record.group != "girdle" and (tolerances.x > 0 or tolerances.y > 0 or tolerances.z > 0):
			var lateral: Vector2 = record.lateral.rotated(deg_to_rad(tolerances.x) * (2 * _random(seed, record.id, 0) - 1))
			var polar := deg_to_rad(record.inclination + tolerances.y * (2 * _random(seed, record.id, 1) - 1))
			normal = Vector3(lateral.x * sin(polar), lateral.y * sin(polar), record.side * cos(polar)).normalized()
			d += normal.dot(record.anchor) - record.normal.dot(record.anchor)
			d -= tolerances.z * _random(seed, record.id, 2)
		planes.append_array(PackedFloat32Array([normal.x, normal.y, normal.z, d, record.zone, 0, 0, 0]))
	var outline := _outline_from_lines(girdle_normals, girdle_offsets)
	if outline.size() < 3 or not HullValidator.is_outline_convex(outline): return _failure("Invalid convex girdle outline")
	if not HullValidator.check_bounded(planes): return _failure("Facet program is unbounded; supply independent upper/lower termination")
	# The shared finite face clipper assumes normalized authoring geometry.
	# Test horizontal sections before pruning, so tall near-vertical programs
	# cannot be silently truncated by its seed polygon.
	for sign_value in [-1.0, 1.0]:
		var bounded := planes.duplicate()
		bounded.append_array(PackedFloat32Array([0, 0, sign_value, 4, 0, 0, 0, 0]))
		var cap := HullValidator._face_polygon(bounded, bounded.size()/8, bounded.size()/8-1, [], 0.0)
		if absf(HullValidator._polygon_area(cap)) > 1e-9: return _failure("Facet host exceeds the supported normalized height interval (-4, 4)")
	var dead: PackedInt32Array = HullValidator.find_dead_planes(planes)
	var kept_planes := PackedFloat32Array(); var facet_ids := PackedInt32Array(); var anchors := PackedVector3Array(); var facet_names := PackedStringArray()
	var meet_contacts := []
	var retained_groups := {}
	for index in records.size():
		var record: Dictionary = records[index]
		if index in dead:
			diagnostics.append({"kind": "vanished", "facet": record.name}); continue
		retained_groups[record.group] = true
		kept_planes.append_array(planes.slice(index * 8, index * 8 + 8)); facet_ids.append(record.id); anchors.append(record.anchor); facet_names.append(record.name)
		meet_contacts.append(record.contacts)
	for group in template.groups:
		for reference in group.meet_groups:
			if not retained_groups.has(reference): diagnostics.append({"kind": "meet_target_vanished", "group": String(group.group_id), "target": reference})
	if not HullValidator.check_bounded(kept_planes): return _failure("Facet constraints enclose no finite solid after pruning")
	return {"planes": kept_planes, "facet_ids": facet_ids, "facet_names": facet_names, "outline": outline, "anchors": anchors,
		"diagnostics": diagnostics, "pruned_planes": dead.size(), "program_measures": measures, "meet_contacts": meet_contacts}

static func _envelope(groups: Dictionary, references: PackedStringArray, xy: Vector2, side: int) -> Dictionary:
	var height := INF if side > 0 else -INF
	var contacts := []
	for reference in references:
		var eligible := false
		for record: Dictionary in groups[reference]:
			var n: Vector3 = record.normal
			if n.z * side < 1e-6: continue
			eligible = true
			var z: float = (record.d - n.x * xy.x - n.y * xy.y) / n.z
			if (z < height if side > 0 else z > height): height = z; contacts = [record.name]
			elif absf(z - height) < 1e-7: contacts.append(record.name)
		if not eligible: return {"error": "Meet group has no correctly facing surface: " + reference}
	if not is_finite(height): return {"error": "No finite surface meet"}
	return {"height": height, "contacts": contacts}

static func _duplicate(a: Dictionary, b: Dictionary) -> bool:
	return a.normal.angle_to(b.normal) < 0.002 and absf(a.d - b.d) < 1e-4

static func _random(seed: int, facet_id: int, channel: int) -> float:
	var value := (seed * 747796405 + facet_id * 2891336453 + channel * 1013904223) & 0xffffffff
	var word := (((value >> ((value >> 28) + 4)) ^ value) * 277803737) & 0xffffffff
	return float(((word >> 22) ^ word) & 0xfffff) / 1048576.0

static func _failure(error: String) -> Dictionary:
	return {"planes": PackedFloat32Array(), "outline": PackedVector2Array(), "compilation_error": error}

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
