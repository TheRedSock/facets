extends Node

var _current_seed: int = 0
var _actions: Array[Dictionary] = []


func begin(replay_seed: int) -> void:
	_current_seed = replay_seed
	_actions.clear()


func record_action(action_type: StringName, payload: Dictionary = {}) -> void:
	_actions.append({
		"type": action_type,
		"payload": payload.duplicate(true),
		"index": _actions.size(),
	})


## Records a board state hash checkpoint for anti-cheat verification.
## The verifier replays actions and compares hashes at each checkpoint.
func record_checkpoint(board_hash: int) -> void:
	_actions.append({
		"type": &"checkpoint",
		"board_hash": board_hash,
		"index": _actions.size(),
	})


func export_replay() -> Dictionary:
	return {
		"seed": _current_seed,
		"actions": _actions.duplicate(true),
	}


func clear() -> void:
	_current_seed = 0
	_actions.clear()
