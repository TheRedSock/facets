class_name RunScene
extends Control

@onready var board_scene: BoardScene = %BoardScene
@onready var hud_label: Label = %HudLabel

var run_controller := RunController.new()
var _debug_panel: DebugPanel


func _ready() -> void:
	run_controller.board_changed.connect(_on_board_changed)
	run_controller.run_state_changed.connect(_on_run_state_changed)

	board_scene.swap_requested.connect(_on_swap_requested)

	# Debug panel — toggle with F1 (full-screen overlay)
	_debug_panel = DebugPanel.new()
	_debug_panel.anchor_right = 1.0
	_debug_panel.anchor_bottom = 1.0
	_debug_panel.offset_left = 16.0
	_debug_panel.offset_top = 40.0
	_debug_panel.offset_right = -16.0
	_debug_panel.offset_bottom = -16.0
	add_child(_debug_panel)

	run_controller.start_new_run()


func _on_board_changed(board: BoardState) -> void:
	board_scene.set_board_state(board)


func _on_run_state_changed(run_state: RunState) -> void:
	_update_hud()


func _on_swap_requested(cell_a: Vector2i, cell_b: Vector2i) -> void:
	# Lock input during the entire swap + cascade animation
	board_scene._input_locked = true

	var timeline := run_controller.attempt_swap(cell_a, cell_b)
	if timeline != null:
		# Valid swap: animate swap, then play cascade
		await board_scene.animate_swap(cell_a, cell_b)
		_update_hud()
		await board_scene.play_timeline(timeline)
	else:
		# Invalid swap: bounce-back animation
		await board_scene.animate_invalid_swap(cell_a, cell_b)

	board_scene._input_locked = false


func _update_hud() -> void:
	if hud_label == null:
		return
	var rs := run_controller.get_run_state()
	hud_label.text = "Moves: %d  |  Seed: %d" % [rs.moves_remaining, rs.seed]
