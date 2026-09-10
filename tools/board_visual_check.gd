extends Node
## Board consumer verification. Requires a windowed run (RenderingDevice).
## Run AS A SCENE (never --script: that mode cannot compile scripts that
## reference autoload identifiers, which poisons the scene script cache):
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --path . res://tools/board_visual_check.tscn
##
## Requires a built generated/gem-assets.pck. Every configured tile must draw
## its delivered idle immediately; there is no runtime bake or waiting path.
const OUT_PATH := "res://artifacts/eval/board_live.png"
const SCENE_PATH := "res://scenes/run/run_scene.tscn"
const BOOT_FRAME_CAP := 120


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

	var total := _tile_views().size()
	var clips := _count("clip")
	var forge := get_node("/root/GemForge")
	print("  delivery: ", JSON.stringify(forge.delivery_report()))
	if clips != total:
		_finish(false, "%d/%d tiles have delivered idle frames" % [clips, total])
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUT_PATH))
	_finish(true, "%d/%d tiles on delivered clips; screenshot %s" % [clips, total, OUT_PATH])


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


## Classify the delivered TextureRect versus the missing-asset tint.
func _classify(view: Node) -> String:
	var bg: ColorRect = view.get("_background")
	var rect: TextureRect = view.get("_clip_rect")
	if bg != null and bg.visible:
		return "fallback"
	if rect != null and rect.visible and StringName(view.get("_clip_id")) != &"":
		return "clip"
	return "fallback"


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
