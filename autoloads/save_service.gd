extends Node

const SAVE_DIR := "user://saves"


func ensure_save_dir() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	dir.make_dir_recursive("saves")


func save_json(slot_name: String, payload: Dictionary) -> Error:
	ensure_save_dir()
	var file := FileAccess.open("%s/%s.json" % [SAVE_DIR, slot_name], FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return OK


func load_json(slot_name: String) -> Variant:
	var path := "%s/%s.json" % [SAVE_DIR, slot_name]
	if not FileAccess.file_exists(path):
		return null

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null

	var text := file.get_as_text()
	file.close()

	var parsed: Variant = JSON.parse_string(text)
	return parsed
