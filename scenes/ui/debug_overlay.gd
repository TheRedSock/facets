class_name DebugOverlay
extends PanelContainer

signal reroll_requested
signal evaluate_requested
signal resolve_requested
signal coordinates_toggled(enabled: bool)

@onready var seed_value: Label = %SeedValue
@onready var moves_value: Label = %MovesValue
@onready var board_value: Label = %BoardValue
@onready var last_action_value: Label = %LastActionValue
@onready var coordinates_toggle: CheckButton = %CoordinatesToggle


func _ready() -> void:
	coordinates_toggle.button_pressed = DebugFlags.show_board_coordinates


func update_run_state(run_state: RunState) -> void:
	seed_value.text = str(run_state.seed)
	moves_value.text = str(run_state.moves_remaining)
	board_value.text = "%dx%d" % [run_state.board_size.x, run_state.board_size.y]


func update_last_action(text_value: String) -> void:
	last_action_value.text = text_value


func _on_reroll_button_pressed() -> void:
	reroll_requested.emit()


func _on_evaluate_button_pressed() -> void:
	evaluate_requested.emit()


func _on_resolve_button_pressed() -> void:
	resolve_requested.emit()


func _on_coordinates_toggle_toggled(toggled_on: bool) -> void:
	coordinates_toggled.emit(toggled_on)
