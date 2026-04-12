extends SceneTree

## Cross-family consistency tests for gem visuals and mineral templates.

var _pass_count := 0
var _fail_count := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	print("\n=== Gem Cross-Family Consistency Tests ===\n")

	var registry := get_root().get_node_or_null("GemVisualRegistry")
	if registry == null:
		_fail("GemVisualRegistry autoload not available")
		_print_summary()
		quit(1)
		return

	var visual_ids: Array = registry.get_visual_ids()
	if visual_ids.is_empty():
		_fail("No gem visuals loaded in registry")
		_print_summary()
		quit(1)
		return

	# Filter to gameplay gems (those with a tile definition)
	var tile_registry := get_root().get_node_or_null("TileRegistry")
	var gameplay_ids: Array = []
	for vid in visual_ids:
		if tile_registry != null and tile_registry.has_definitions():
			if tile_registry.get_definition(vid) != null:
				gameplay_ids.append(vid)
		else:
			gameplay_ids.append(vid)

	# 1. All gameplay gems reference a non-null mineral_template
	for vid in gameplay_ids:
		var visual: Resource = registry.get_visual(vid)
		if visual == null:
			continue
		var tmpl = visual.get("mineral_template")
		_assert(tmpl != null,
			"%s: gameplay gem should reference a non-null mineral_template" % str(vid))

	# 2. Same-family gems sharing a template have identical Sellmeier
	var template_map: Dictionary = {} # template_path -> { sellmeier_b, sellmeier_c, gems }
	for vid in visual_ids:
		var visual: Resource = registry.get_visual(vid)
		if visual == null:
			continue
		var tmpl = visual.get("mineral_template")
		if tmpl == null:
			continue
		var tmpl_path: String = tmpl.resource_path
		if not template_map.has(tmpl_path):
			template_map[tmpl_path] = {
				"sellmeier_b": tmpl.get("sellmeier_b"),
				"sellmeier_c": tmpl.get("sellmeier_c"),
				"gems": [],
			}
		template_map[tmpl_path]["gems"].append(vid)
		# Verify this gem sees the same Sellmeier as the first gem in the family
		var family: Dictionary = template_map[tmpl_path]
		var b: Vector3 = tmpl.get("sellmeier_b")
		var c: Vector3 = tmpl.get("sellmeier_c")
		_assert(b.is_equal_approx(family["sellmeier_b"]) and c.is_equal_approx(family["sellmeier_c"]),
			"%s: Sellmeier should match family (template=%s)" % [str(vid), tmpl_path])

	# 3. absorption_spectrum_override length is 0 or 81
	for vid in visual_ids:
		var visual: Resource = registry.get_visual(vid)
		if visual == null:
			continue
		var override_spec: PackedFloat32Array = visual.get("absorption_spectrum_override")
		_assert(override_spec.size() == 0 or override_spec.size() == 81,
			"%s: absorption_spectrum_override size should be 0 or 81, got %d" % [str(vid), override_spec.size()])

	# 4. absorption_strength_scale > 0
	for vid in visual_ids:
		var visual: Resource = registry.get_visual(vid)
		if visual == null:
			continue
		var scale: float = visual.get("absorption_strength_scale")
		_assert(scale > 0.0,
			"%s: absorption_strength_scale should be > 0, got %.4f" % [str(vid), scale])

	# 5. display_color not transparent for gameplay gems
	for vid in gameplay_ids:
		var visual: Resource = registry.get_visual(vid)
		if visual == null:
			continue
		var color: Color = visual.get("display_color")
		_assert(color.a > 0.01,
			"%s: display_color should not be transparent (alpha=%.3f)" % [str(vid), color.a])

	_print_summary()
	quit(1 if _fail_count > 0 else 0)


func _assert(condition: bool, message: String) -> void:
	if condition:
		_pass_count += 1
	else:
		_fail_count += 1
		print("  FAIL: %s" % message)


func _fail(message: String) -> void:
	_fail_count += 1
	print("  FAIL: %s" % message)


func _print_summary() -> void:
	print("\n=== Results: %d passed, %d failed ===\n" % [_pass_count, _fail_count])
