extends "res://tests/game/game_test.gd"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	GameReplayCorpus.run(self)
	finish("test_game_replay")
