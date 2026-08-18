extends Node
## Board consumer verification. Requires a windowed run (RenderingDevice).
## Run AS A SCENE (never --script: that mode cannot compile scripts that
## reference autoload identifiers, which poisons the scene script cache):
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --path . res://tools/board_visual_check.tscn
##
## Instantiates the real run scene (auto-starts a run), then:
##   1. waits until every TileView on the board draws a forge visual (clip or
##      placeholder still) — the ColorRect fallback means the forge path broke;
##   2. waits further for baked idle CLIPS to replace stills (background bake);
##   3. captures a full-window screenshot to artifacts/eval/board_live.png;
##   4. reports clip/still/fallback counts.
## Prints PASS/FAIL and quits.

const OUT_PATH := "res://artifacts/eval/board_live.png"
const SCENE_PATH := "res://scenes/run/run_scene.tscn"
const BOOT_FRAME_CAP := 900
const CLIP_WAIT_MS := 60000


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_PATH).get_base_dir())
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_finish(false, "cannot load %s" % SCENE_PATH)
		return
	var scene: Node = packed.instantiate()
	add_child(scene)

	if not await _wait_until(func() -> bool: return _tile_views().size() >= 16, BOOT_FRAME_CAP):
		_finish(false, "board never populated (%d tile views)" % _tile_views().size())
		return
	print("  board populated: %d tile views" % _tile_views().size())

	# Phase 1: no tile may sit on the ColorRect fallback once the forge served
	# its synchronous INTERACT still.
	if not await _wait_until(func() -> bool: return _count("fallback") == 0, BOOT_FRAME_CAP):
		var stuck := {}
		for view in _tile_views():
			if _classify(view) == "fallback":
				var key := "%s(t%d)" % [view.get("tile_id"), view.get("tier")]
				stuck[key] = int(stuck.get(key, 0)) + 1
		_finish(false, "%d tiles stuck on ColorRect fallback: %s" % [_count("fallback"), str(stuck)])
		return
	print("  forge visuals on every tile (stills or clips)")

	# Phase 2: background bake should promote every tile to an animated idle.
	var total := _tile_views().size()
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < CLIP_WAIT_MS and _count("clip") < total:
		await get_tree().process_frame
	var clips := _count("clip")
	print("  after %.1f s: %d clips, %d stills, %d fallback (of %d tiles)" % [
		(Time.get_ticks_msec() - t0) / 1000.0, clips, _count("still"), _count("fallback"), total])

	var shot := ProjectSettings.globalize_path(OUT_PATH)
	get_viewport().get_texture().get_image().save_png(shot)
	print("  screenshot: %s" % shot)

	if clips == 0:
		_finish(false, "no tile ever received a baked idle clip")
		return
	_finish(clips >= total / 2, "%d/%d tiles on baked clips" % [clips, total])


func _finish(ok: bool, detail: String) -> void:
	print("BOARD_VISUAL_CHECK %s (%s)" % ["PASS" if ok else "FAIL", detail])
	get_tree().quit(0 if ok else 1)


## Configured, visible tile views only. BoardScene pre-creates spawn-pool
## views above the board with no tile assigned (tile_id empty, tier 0); those
## legitimately sit on the fallback until a spawn configures them.
func _tile_views() -> Array:
	var out: Array = []
	_collect(self, out)
	return out


func _collect(node: Node, out: Array) -> void:
	if node is TileView and node.visible and StringName(node.get("tile_id")) != &"":
		out.append(node)
	for child in node.get_children():
		_collect(child, out)


## Classify a TileView's current visual: "clip" (animated forge clip),
## "still" (placeholder), or "fallback" (ColorRect).
func _classify(view: Node) -> String:
	var bg: ColorRect = view.get("_background")
	var rect: TextureRect = view.get("_clip_rect")
	if bg != null and bg.visible:
		return "fallback"
	if rect != null and rect.visible and StringName(view.get("_clip_id")) != &"":
		return "clip"
	return "still"


func _count(kind: String) -> int:
	var n := 0
	for view in _tile_views():
		if _classify(view) == kind:
			n += 1
	return n


func _wait_until(pred: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await get_tree().process_frame
	return pred.call()
