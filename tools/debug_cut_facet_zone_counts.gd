extends SceneTree

## Headless: print per-zone facet counts and crown topology checks for a compiled cut.
## Run:
##   "/c/Godot/Godot_v4.6.1-stable_win64_console.exe" --headless --path . --script res://tools/debug_cut_facet_zone_counts.gd -- --spec_id=simple_octagon_step
##
## Expected for `simple_octagon_step` (fan_step family):
##   - 1× table (octagon → 8 vertices)
##   - 8× bezel (5 vertices each)
##   - 16× girdle_band quads, 32× pavilion quads, 16× culet tris (16-fold crown boundary → pavilion fan)

const GemCutGeneratorsScript = preload("res://core/visuals/gem_cut_generators.gd")

const CROWN_TOP_ZONES := {
	&"table": true,
	&"bezel": true,
	&"star": true,
	&"step": true,
	&"girdle": true,
	&"rose": true,
	&"rose_center": true,
}


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var spec_id: StringName = &"simple_octagon_step"
	for raw in OS.get_cmdline_user_args():
		var a := String(raw)
		if a.begins_with("--spec_id="):
			spec_id = StringName(a.get_slice("=", 1))

	print("\n=== Cut facet zone counts ===\n")
	print("spec_id: %s\n" % spec_id)

	var model = GemCutGeneratorsScript.generate_model_from_spec_id(spec_id)
	if model == null:
		push_error("compile_spec_id returned null (validation failed?)")
		quit(1)
		return

	var zone_counts: Dictionary = {}
	var table_verts := -1
	var bezel_vert_histogram: Dictionary = {}

	for i in model.facet_count():
		var zone: StringName = model.facet_zones[i] if i < model.facet_zones.size() else &""
		var zkey := zone if zone != StringName() else &"(empty)"
		zone_counts[zkey] = int(zone_counts.get(zkey, 0)) + 1

		var verts: PackedVector3Array = model.facet_vertices[i]
		if zone == &"table":
			table_verts = verts.size()
		elif zone == &"bezel":
			var n := verts.size()
			bezel_vert_histogram[n] = int(bezel_vert_histogram.get(n, 0)) + 1

	var crown_top := 0
	var pavilionish := 0
	for z in zone_counts.keys():
		var c := int(zone_counts[z])
		if CROWN_TOP_ZONES.has(z):
			crown_top += c
		if z == &"pavilion" or z == &"culet" or z == &"girdle_band":
			pavilionish += c

	print("Per-zone facet counts:")
	var keys: Array = zone_counts.keys()
	keys.sort_custom(func(a, b): return String(a) < String(b))
	for z in keys:
		print("  %s: %d" % [z, zone_counts[z]])

	print("\nCrown (orthographic top–visible zones): %d facets" % crown_top)
	print("Below girdle + vertical walls: %d facets" % pavilionish)

	print("\nReference checks (simple_octagon_step):")
	print("  table vertices: %d (expect 8 for octagon)" % table_verts)
	print("  bezel vertex histogram: %s (expect {5: 8} eight pentagons)" % str(bezel_vert_histogram))

	var ok: bool = (
		table_verts == 8
		and int(bezel_vert_histogram.get(5, 0)) == 8
		and int(zone_counts.get(&"table", 0)) == 1
	)
	if ok:
		print("\nPASS: crown matches flat octagon table + eight bezel facets.")
	else:
		push_warning("Counts differ from simple_octagon_step expectations — inspect spec or builder.")

	print("\nNote: mesh/trace triangulation fans each n-gon from verts[0]; pavilion uses 16 culet triangles to one apex when crown boundary has 16 vertices.\n")
	quit(0)
