class_name EventLog
extends RefCounted

## Structured event log for debugging, replay, and animation sequencing.
## All events are stored as dictionaries with a "type" key.

var entries: Array[Dictionary] = []
var _max_entries: int = 10000


func push(event_type: StringName, data: Dictionary = {}) -> void:
	var entry := data.duplicate()
	entry["type"] = event_type
	entry["index"] = entries.size()
	entries.append(entry)

	# Prevent unbounded growth
	if entries.size() > _max_entries:
		entries = entries.slice(entries.size() - _max_entries)


func clear() -> void:
	entries.clear()


func get_last(count: int = 1) -> Array[Dictionary]:
	var start: int = max(0, entries.size() - count)
	return entries.slice(start)


func get_by_type(event_type: StringName) -> Array[Dictionary]:
	var filtered: Array[Dictionary] = []
	for entry in entries:
		if entry.get("type") == event_type:
			filtered.append(entry)
	return filtered


func size() -> int:
	return entries.size()
