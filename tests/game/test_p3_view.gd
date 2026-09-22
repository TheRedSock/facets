extends "res://tests/game/game_test.gd"
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var view := ExpeditionView.new(); root.add_child(view)
	await process_frame
	check(view.run != null and view.run.phase == "briefing","expedition view starts in briefing")
	check(view.panel != null and view.error.is_empty(),"briefing controls constructed")
	var controls := view.panel.find_children("*","Button",true,false)
	check(controls.size() >= 2,"keyboard-focusable menu and begin controls")
	var deadline := Time.get_ticks_msec()+10000
	while view.find_children("*","TileView",true,false).size() != 8 and Time.get_ticks_msec() < deadline: await process_frame
	check(view.find_children("*","TileView",true,false).size() == 8,"all eight delivered ladder previews are live owners")
	view.queue_free(); await process_frame; await process_frame
	finish("test_p3_view")
