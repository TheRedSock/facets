class_name MatchDetector
extends RefCounted

## The directional axes along which matches are detected.
## Default: horizontal (RIGHT) and vertical (DOWN).
## Add Vector2i(1,1) for diagonal matching as a future modifier.
var match_axes: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.DOWN]


## Scans the board for all line matches along configured match axes.
## Uses local match-purpose adjacency; gravity portals never join lines.
## Respects the unmatchable tile flag.
## Returns an array of match dictionaries, each with "type", "cells", and "match_group".
## Does not mutate the board.
func find_matches(board: BoardState) -> Array[Dictionary]:
	var matches: Array[Dictionary] = []
	var visited := PackedByteArray()
	var num_axes: int = match_axes.size()
	var bw: int = board.size.x
	var bh: int = board.size.y
	visited.resize(bw * bh * num_axes)

	for axis_idx: int in num_axes:
		var axis: Vector2i = match_axes[axis_idx]
		var axis_name: StringName = _axis_name(axis)

		for y: int in bh:
			for x: int in bw:
				var pos := Vector2i(x, y)
				if board.is_blocked(pos):
					continue
				var visit_key: int = (y * bw + x) * num_axes + axis_idx
				if visited[visit_key] != 0:
					continue

				var run: Array[Vector2i] = _collect_run(board, pos, axis)
				for cell: Vector2i in run:
					visited[(cell.y * bw + cell.x) * num_axes + axis_idx] = 1

				if run.size() >= 3:
					var tile: TileState = board.get_tile(pos)
					matches.append({
						"type": axis_name,
						"cells": run,
						"match_group": tile.get_match_group(),
						"tier": tile.tier,
					})

	return matches


## Collects a run of tiles with the same match_group starting from a position in a direction.
## Uses board.neighbor_for(..., "match") for local traversal.
## Stops at null tiles, unmatchable tiles, out-of-bounds, and different match groups.
func _collect_run(board: BoardState, start: Vector2i, direction: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var start_tile: TileState = board.get_tile(start)
	if start_tile == null or start_tile.unmatchable:
		return cells

	var group: StringName = start_tile.get_match_group()
	var cursor := start
	while cursor != Vector2i(-1, -1) and cells.size() < board.size.x * board.size.y:
		var cell := board.get_cell(cursor)
		if cell == null or cell.blocked: break
		var tile: TileState = cell.tile
		if tile == null or tile.unmatchable or tile.get_match_group() != group:
			break
		cells.append(cursor)
		# Matching is always local and cardinal; avoid repeated portal/purpose
		# dispatch inside an already selected matching line.
		if abs(direction.x) + abs(direction.y) != 1: break
		cursor += direction

	return cells


## Maps a direction vector to a human-readable axis name for match type tagging.
func _axis_name(axis: Vector2i) -> StringName:
	match axis:
		Vector2i.RIGHT:
			return &"line_horizontal"
		Vector2i.DOWN:
			return &"line_vertical"
		_:
			return StringName("line_%d_%d" % [axis.x, axis.y])
