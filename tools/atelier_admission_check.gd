extends SceneTree
## Scene contract: invalid edits immediately retire the displayed result.
func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var scene: Control = load("res://scenes/design/gem_atelier.tscn").instantiate()
	root.add_child(scene)
	scene.set_process(false)
	scene.call("_rebuild_now")
	if not scene.get("_configured"): scene.free(); _fail("Valid preview was not admitted"); return
	var tracer: GemTracer = scene.get("_tracer")
	tracer.accumulate(4)
	scene.call("_update_preview")
	if scene.call("debug_get_preview_image") == null: scene.free(); _fail("Valid preview missing"); return
	var stone: GemStone = scene.get("_stone")
	var size := stone.size_mm
	stone.size_mm = -1.0
	scene.call("_queue_rebuild")
	if scene.get("_configured") or scene.get("_last_image") != null:
		scene.free(); _fail("Pending invalid edit retained stale output"); return
	scene.call("_rebuild_now")
	var controls: Dictionary = scene.get("_c")
	if scene.get("_configured") or controls.preview.texture != null or not controls.overlay.visible or "size" not in controls.overlay.text:
		scene.free(); _fail("Invalid preview did not expose shared admission reason"); return
	stone.size_mm = size
	scene.call("_on_pose_changed", 0.0)
	scene.call("_rebuild_now")
	if not scene.get("_configured") or controls.overlay.visible:
		scene.free(); _fail("Corrected configuration failed to recover"); return
	scene.free()
	print("Atelier admission PASS: valid image, immediate invalidation, actionable error, corrected recovery")
	print("CHECK_COMPLETE: atelier_admission_check"); quit()

func _fail(message: String) -> void:
	printerr("FAIL: " + message)
	print("CHECK_COMPLETE: atelier_admission_check"); quit(1)
