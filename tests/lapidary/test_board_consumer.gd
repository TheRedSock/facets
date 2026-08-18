extends SceneTree
## Board-consumer tests: TileView driven by the GemForge autoload.
## Headless-safe — the forge serves cached clips from disk when present and
## degrades to {} otherwise; tiles without a lapidary stone always fall back
## to the ColorRect tier tint.
##
## Run: godot --headless --path . --script res://tests/lapidary/test_board_consumer.gd

const TILE_VIEW_SCENE := "res://scenes/tile/tile_view.tscn"

## Fabricated tile_ids with NO stone in data/lapidary/stones/, so
## GemForge.get_clip is guaranteed to return {} in every environment.
## (Every real tile_id now has an authored stone — both ladders shipped —
## so real ids can serve cached clips and defeat the fallback assertions.)
const STONELESS_TILE := &"test_stoneless_gem"
const STONELESS_TILE_TIER := 1
const STONELESS_UPGRADE_TILE := &"test_stoneless_upgrade"
const STONELESS_UPGRADE_TIER := 6

var _pass := 0
var _fail := 0
var _started := false


func _process(_delta: float) -> bool:
	# Autoloads are not in the tree during _initialize; run on the first tick.
	if _started:
		return true
	_started = true
	print("\n=== Board consumer tests (TileView x GemForge) ===\n")
	_run()
	print("\n%d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
	return true


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  PASS %s" % name)
	else:
		_fail += 1
		printerr("  FAIL %s" % name)


func _run() -> void:
	var forge: Node = root.get_node_or_null("GemForge")
	_check(forge != null, "GemForge autoload present")
	var registry: Node = root.get_node_or_null("TileRegistry")
	_check(registry != null and registry.has_definitions(), "TileRegistry has definitions")
	if forge == null or registry == null:
		return

	var view: TileView = (load(TILE_VIEW_SCENE) as PackedScene).instantiate()
	root.add_child(view)
	view.size = Vector2(112, 112)

	_test_colorrect_fallback(view, registry)
	_test_mouse_filters(view)
	_test_play_clip_noop(view)
	_test_upgrade_tier_color(view, registry)
	_test_cached_clip_path(forge, registry)

	view.queue_free()


# ---- ColorRect fallback (forge returns {} for stoneless tiles) ----

func _test_colorrect_fallback(view: TileView, registry: Node) -> void:
	print("[colorrect fallback]")
	view.configure_from_data(STONELESS_TILE, STONELESS_TILE_TIER, Vector2i.ZERO)
	var bg := _visible_background(view)
	_check(bg != null, "stoneless tile builds a visible ColorRect fallback")
	if bg == null:
		return
	var expected: Color = registry.get_tier_color(STONELESS_TILE_TIER)
	_check(bg.color.is_equal_approx(expected),
		"fallback tinted via TileRegistry.get_tier_color(%d)" % STONELESS_TILE_TIER)
	_check(not _has_visible_texture_rect(view), "no clip TextureRect shown on fallback")
	_check(not view.is_processing(), "fallback costs zero per-frame work")


# ---- Invariant #5: every node ignores mouse input ----

func _test_mouse_filters(view: TileView) -> void:
	print("[mouse filter invariant]")
	var offenders: Array[String] = []
	_collect_mouse_filter_offenders(view, offenders)
	_check(offenders.is_empty(),
		"TileView and all children use MOUSE_FILTER_IGNORE%s" %
		("" if offenders.is_empty() else " (offenders: %s)" % ", ".join(offenders)))


func _collect_mouse_filter_offenders(node: Node, offenders: Array[String]) -> void:
	if node is Control and (node as Control).mouse_filter != Control.MOUSE_FILTER_IGNORE:
		offenders.append(str(node.get_path()))
	for child in node.get_children():
		_collect_mouse_filter_offenders(child, offenders)


# ---- play_clip miss handling ----

func _test_play_clip_noop(view: TileView) -> void:
	print("[play_clip no-op]")
	view.configure_from_data(STONELESS_TILE, STONELESS_TILE_TIER, Vector2i.ZERO)
	view.play_clip(&"turn")
	view.play_clip(&"flash")
	view.play_clip(&"no_such_clip")
	view.play_special_rotation_animation()
	var bg := _visible_background(view)
	_check(bg != null and not view.is_processing(),
		"play_clip / play_special_rotation_animation no-op on forge miss")


# ---- show_upgrade_full tier tint ----

func _test_upgrade_tier_color(view: TileView, registry: Node) -> void:
	print("[show_upgrade_full]")
	view.configure_from_data(STONELESS_TILE, STONELESS_TILE_TIER, Vector2i.ZERO)
	var before: Color = registry.get_tier_color(STONELESS_TILE_TIER)
	var after: Color = registry.get_tier_color(STONELESS_UPGRADE_TIER)
	_check(not before.is_equal_approx(after), "tier colors differ (test precondition)")
	view.show_upgrade_full(STONELESS_UPGRADE_TIER, STONELESS_UPGRADE_TILE)
	var bg := _visible_background(view)
	_check(bg != null and bg.color.is_equal_approx(after),
		"show_upgrade_full retints the fallback to the new tier color")
	_check(view.tier == STONELESS_UPGRADE_TIER and view.tile_id == STONELESS_UPGRADE_TILE,
		"show_upgrade_full updates tile_id/tier")


# ---- Served clip path (cache-dependent; skips on fresh checkouts) ----

func _test_cached_clip_path(forge: Node, _registry: Node) -> void:
	print("[served clip path]")
	var served: Dictionary = forge.get_clip(&"quartz", &"idle")
	if served.is_empty():
		print("  SKIP served clips (no packaged gemcache — run tools/package_clips.gd)")
		return
	var view: TileView = (load(TILE_VIEW_SCENE) as PackedScene).instantiate()
	root.add_child(view)
	view.size = Vector2(112, 112)
	view.configure_from_data(&"quartz", 1, Vector2i.ZERO)
	_check(_has_visible_texture_rect(view), "cached idle clip shows the TextureRect path")
	_check(not view.is_processing(), "1-frame idle does not process per-frame")
	view.play_clip(&"turn")
	_check(view.is_processing(), "turn oneshot starts frame advancing")
	view.show_upgrade_full(2, &"amethyst")
	_check(view.tile_id == &"amethyst" and _has_visible_texture_rect(view),
		"upgrade swaps to the new tile's served visual")
	view.queue_free()


# ---- helpers ----

func _visible_background(view: TileView) -> ColorRect:
	for child in view.find_children("*", "ColorRect", true, false):
		if (child as ColorRect).visible:
			return child
	return null


func _has_visible_texture_rect(view: TileView) -> bool:
	for child in view.find_children("*", "TextureRect", true, false):
		var rect := child as TextureRect
		if rect.visible and rect.texture != null:
			return true
	return false
