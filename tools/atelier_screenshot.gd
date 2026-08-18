extends SceneTree
## Atelier verification harness. Requires a windowed run (RenderingDevice).
## Run:
##   "C:/Godot/Godot_v4.6.1-stable_win64_console.exe" --path . --script res://tools/atelier_screenshot.gd
##
## Loads gem_atelier.tscn and verifies the progressive preview:
##   1. waits (state-based, frame-capped) until the tracer is configured and
##      accumulating — the first engine frame absorbs shader compiles and the
##      legacy autoload startup, so wall-clock waits alone are unreliable;
##   2. gives the loop a ~3 s accumulation window, captures a full-window
##      screenshot, and checks the preview is not black/empty;
##   3. sets clarity to 0.1 through the scene's debug API, waits for the
##      debounced rebuild to land, and checks the render visibly changed.
## Prints PASS/FAIL.

const OUT_DIR := "res://artifacts/lookdev"
const SCENE_PATH := "res://scenes/design/gem_atelier.tscn"
const BOOT_FRAME_CAP := 1200
const SETTLE_MS := 3000
const MIN_COMPARE_SPP := 96


func _initialize() -> void:
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var packed := load(SCENE_PATH) as PackedScene
	if packed == null:
		_finish(false, "cannot load %s" % SCENE_PATH)
		return
	var atelier: Control = packed.instantiate()
	get_root().add_child(atelier)

	if not await _wait_until(func() -> bool: return _spp(atelier) > 0, BOOT_FRAME_CAP):
		_finish(false, "tracer never configured — headless run or GPU failure: %s"
			% str(atelier.call("debug_status")))
		return
	print("  configured: %s" % str(atelier.call("debug_status")))

	var t0 := Time.get_ticks_msec()
	var frames := 0
	while Time.get_ticks_msec() - t0 < SETTLE_MS:
		await process_frame
		frames += 1
	var status: Dictionary = atelier.call("debug_status")
	print("  after %.1f s window (%d frames): %s" % [SETTLE_MS / 1000.0, frames, str(status)])

	var preview_a: Image = atelier.call("debug_get_preview_image")
	var shot_a_path := ProjectSettings.globalize_path(OUT_DIR + "/atelier_screenshot.png")
	get_root().get_texture().get_image().save_png(shot_a_path)
	print("  window screenshot: %s" % shot_a_path)
	if preview_a == null:
		_finish(false, "no preview image")
		return
	var mean_a := _mean_rgb(preview_a)
	var cover_a := _coverage(preview_a)
	print("  preview mean rgb %.4f, coverage %.3f" % [mean_a, cover_a])
	if mean_a < 0.01 or cover_a < 0.02:
		_finish(false, "preview is black/empty")
		return

	var fp_a := str(status.get("fingerprint", ""))
	atelier.call("debug_set_grade", "clarity", 0.1)
	var regraded := await _wait_until(func() -> bool:
		var s: Dictionary = atelier.call("debug_status")
		return str(s.get("fingerprint", "")) != fp_a and int(s.get("spp", 0)) >= MIN_COMPARE_SPP,
		BOOT_FRAME_CAP)
	if not regraded:
		_finish(false, "clarity rebuild never landed: %s" % str(atelier.call("debug_status")))
		return
	var preview_b: Image = atelier.call("debug_get_preview_image")
	var shot_b_path := ProjectSettings.globalize_path(OUT_DIR + "/atelier_screenshot_clarity01.png")
	get_root().get_texture().get_image().save_png(shot_b_path)
	print("  clarity 0.1 screenshot: %s" % shot_b_path)
	print("  regraded: %s" % str(atelier.call("debug_status")))
	var diff := _mean_abs_diff(preview_a, preview_b)
	print("  preview mean abs diff after clarity 0.1: %.4f" % diff)
	if diff < 0.002:
		_finish(false, "clarity change did not alter the render")
		return
	_finish(true, "spp %d in %.1f s window, last dispatch %.1f ms" % [
		int(status.get("spp", 0)), SETTLE_MS / 1000.0, float(status.get("last_ms", 0.0))])


func _finish(ok: bool, detail: String) -> void:
	print("ATELIER_SCREENSHOT %s (%s)" % ["PASS" if ok else "FAIL", detail])
	quit(0 if ok else 1)


func _spp(atelier: Control) -> int:
	var s: Dictionary = atelier.call("debug_status")
	return int(s.get("spp", 0))


func _wait_until(pred: Callable, max_frames: int) -> bool:
	for i in max_frames:
		if pred.call():
			return true
		await process_frame
	return pred.call()


static func _mean_rgb(img: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			var p := img.get_pixel(x, y)
			total += (p.r + p.g + p.b) / 3.0
			count += 1
	return total / maxf(1.0, float(count))


static func _coverage(img: Image) -> float:
	var covered := 0
	var count := 0
	for y in range(0, img.get_height(), 4):
		for x in range(0, img.get_width(), 4):
			if img.get_pixel(x, y).a > 0.5:
				covered += 1
			count += 1
	return float(covered) / maxf(1.0, float(count))


static func _mean_abs_diff(a: Image, b: Image) -> float:
	var total := 0.0
	var count := 0
	for y in range(0, a.get_height(), 2):
		for x in range(0, a.get_width(), 2):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			total += absf(pa.r - pb.r) + absf(pa.g - pb.g) + absf(pa.b - pb.b)
			count += 1
	return total / maxf(1.0, float(count * 3))
