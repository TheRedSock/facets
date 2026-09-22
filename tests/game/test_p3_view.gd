extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var view := ExpeditionView.new(); root.add_child(view)
	await process_frame
	check(view.run != null and view.run.phase == "briefing","expedition view starts in briefing")
	check(view.panel != null and view.error.is_empty(),"briefing controls constructed")
	var controls := view.panel.find_children("*","Button",true,false)
	check(controls.size() >= 2,"keyboard-focusable menu and begin controls")
	view.queue_free(); await process_frame
	finish("test_p3_view")
