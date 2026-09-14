extends "res://tests/game/game_test.gd"

func _initialize() -> void:
	var cases := GameFixtureAdapter.read_cases()
	check(cases.size() == 23, "23 frozen cases")
	check(GameFixtureAdapter.inventory(cases).issues.is_empty(), "every phase and expected field has an owner")
	var ledger: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/fixture-disposition.json"))
	check(ledger.size() == 23,"complete frozen fixture ledger")
	for row in GameFixtureAdapter.inventory(cases).cases:
		var recorded: Array = ledger.filter(func(entry: Dictionary) -> bool: return entry.id == row.id)
		check(recorded.size() == 1 and recorded[0].fields == row.fields,"ledger expected-field ownership: " + row.id)
	var smoke: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tests/game/smoke-disposition.json"))
	check(smoke.size() == 113,"all historical smoke assertions accounted for")
	var unknown := cases.duplicate(true)
	unknown[0].phase = "unknown"
	check(not GameFixtureAdapter.inventory(unknown).issues.is_empty(), "unknown phase rejects")
	unknown = cases.duplicate(true)
	unknown[0].expected["unhandled"] = true
	check(not GameFixtureAdapter.inventory(unknown).issues.is_empty(), "unknown expected field rejects")
	test_frozen_matching(cases)
	test_legality_edges()
	GameTopologyCases.run(self)
	test_openings()
	test_virtual_query()
	finish("test_game_rules")

func test_virtual_query() -> void:
	var catalog := GameTestCatalog.create()
	var rng := SeededRng.new(); rng.reseed(442)
	for sample in 12:
		var board := BoardState.new(Vector2i(8,8))
		for pos in board.all_cells():
			var tile := catalog.create_tile(rng.randi_range(1,4))
			tile.unmatchable = (sample == 1 and pos.x == 2)
			board.set_tile(pos,tile)
		for pos in board.all_cells():
			for direction in [Vector2i.RIGHT,Vector2i.DOWN]:
				var to: Vector2i = pos + direction
				if not board.in_bounds(to): continue
				var scratch := board.duplicate_board(); scratch.swap_cells(pos,to)
				var expected := false
				if board.get_tile(pos).get_match_group() != board.get_tile(to).get_match_group():
					for match_result in MatchDetector.new().find_matches(scratch):
						if pos in match_result.cells or to in match_result.cells: expected = true
				check(ActionLegality.can_apply(board,SwapCommand.new(pos,to)).ok == expected,"virtual query equals full scan")

func test_frozen_matching(cases: Array) -> void:
	for c in cases:
		var board := GameFixtureAdapter.board(c)
		if c.phase == "validate_action":
			var before := board.to_dict()
			var command := SwapCommand.new(GameFixtureAdapter.cell(c.swap[0]), GameFixtureAdapter.cell(c.swap[1]))
			check(not ActionLegality.can_apply(board, command).ok and board.to_dict() == before, c.id + ": rejection is pure")
		elif c.phase in ["match_snapshot", "swap_then_first_match"]:
			var pair: Array[Vector2i] = []
			if c.has("swap"):
				pair = [GameFixtureAdapter.cell(c.swap[0]), GameFixtureAdapter.cell(c.swap[1])]
				check(ActionLegality.can_apply(board, SwapCommand.new(pair[0], pair[1])).ok, c.id + ": legal swap")
				board.swap_cells(pair[0], pair[1])
			var components := MatchClassifier.new().classify(MatchDetector.new().find_matches(board))
			var sizes: Array = []
			var owned := {}
			for component in components:
				sizes.append(component.cells.size())
				for pos in component.cells:
					check(not owned.has(pos), c.id + ": single owner")
					owned[pos] = true
			check(sizes == c.expected.component_sizes.map(func(n: Variant) -> int: return int(n)), c.id + ": component sizes")
			if c.expected.has("unique_member_count"): check(owned.size() == c.expected.unique_member_count, c.id + ": unique members")
			if c.expected.has("survivor"):
				check(MatchClassifier.survivor(components[0].cells, pair) == GameFixtureAdapter.cell(c.expected.survivor), c.id + ": survivor")
			if c.expected.has("intersection"): check(components[0].intersection == c.expected.intersection, c.id + ": intersection")
			if c.phase == "swap_then_first_match":
				var count := EffectResolver.new(GameTestCatalog.create()).apply(board, EffectPlanner.new().build_base_plan(components, pair), EventLog.new())
				check(count == c.expected.removed_count, c.id + ": removed count")
				check(board.get_tile(GameFixtureAdapter.cell(c.expected.survivor)).tier == c.expected.promoted_tier, c.id + ": promotion")
		elif c.phase == "recovery_query":
			check(ActionLegality.enumerate_legal_swaps(board).size() == c.expected.legal_swaps_before, c.id + ": legal swaps before recovery")

func test_legality_edges() -> void:
	var c: Dictionary = GameFixtureAdapter.read_cases()[0]
	var board := GameFixtureAdapter.board(c)
	var command := SwapCommand.new(Vector2i(1, 1), Vector2i(1, 0))
	check(not ActionLegality.can_apply(board, command, 0).ok, "no budget")
	check(not ActionLegality.can_apply(board, command, 1, "resolving").ok, "wrong phase")
	check(not ActionLegality.can_apply(board, SwapCommand.new(Vector2i(-1, 0), Vector2i.ZERO)).ok, "out of bounds")
	var before := board.to_dict()
	var commands := ActionLegality.enumerate_legal_swaps(board)
	var directed := 0
	for cmd in commands:
		if [cmd.origin, cmd.destination] in [[command.origin, command.destination], [command.destination, command.origin]]: directed += 1
	check(directed == 2 and board.to_dict() == before, "enumeration preserves both directions without mutation")
	var raw: Array[Dictionary] = []
	for y in 2: raw.append({"type": &"line_horizontal", "cells": [Vector2i(0,y),Vector2i(1,y),Vector2i(2,y)], "tier": 1, "match_group": &"one"})
	check(MatchClassifier.new().classify(raw).size() == 2, "touching parallel runs are separate components")
	board = BoardState.new(Vector2i(3, 1))
	for x in 3: board.set_tile(Vector2i(x, 0), TileState.from_debug_tier(1))
	check(not ActionLegality.can_apply(board, SwapCommand.new(Vector2i.ZERO, Vector2i.RIGHT)).ok, "same-tier exchange cannot reuse existing match")

func test_openings() -> void:
	var catalog := GameTestCatalog.create()
	for seed_value in 10:
		var streams := RngStreamBank.new(seed_value)
		var before := streams.capture()
		var result := OpeningGenerator.generate(BoardLayoutResource.new(),catalog,streams)
		check(result.ok and streams.capture() == before, "opening generated detached")
		if result.ok:
			check(MatchDetector.new().find_matches(result.board).is_empty() and not ActionLegality.enumerate_legal_swaps(result.board).is_empty(), "opening match-free and playable")
	var impossible := BoardLayoutResource.new(); impossible.board_size = Vector2i.ONE
	var result := OpeningGenerator.generate(impossible,catalog,RngStreamBank.new(1))
	check(not result.ok and result.code == "opening_exhausted" and result.attempts == 64, "impossible opening fails at 64 attempts")
