class_name GemAtelierSessionFiles
extends RefCounted

## A replace can briefly make a mailbox unreadable on Windows. Keep the last
## complete message until another complete object is visible, never interpret
## that gap as cancellation or consume it as a response.
static func read_message(path: String, previous: Dictionary = {}) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return previous
	var content := file.get_as_text();file.close()
	if content.is_empty(): return previous
	var parser := JSON.new()
	if parser.parse(content) != OK or not parser.data is Dictionary: return previous
	return parser.data

## Only the render owner collects transient protocol files. Delivery stays durable.
static func collect(session: String, consumed_generation: int) -> String:
	var directory := DirAccess.open(session)
	if directory == null: return "Cannot open Atelier session for collection"
	var request_pattern := RegEx.create_from_string("^request-([0-9]+)\\.res$")
	var image_pattern := RegEx.create_from_string("^preview-([0-9]+)-([0-9]+)\\.png$")
	var images: Array[Dictionary] = []
	var remove: Array[String] = []
	for filename in directory.get_files():
		var request_match := request_pattern.search(filename)
		if request_match != null and int(request_match.get_string(1)) < consumed_generation:
			remove.append(filename)
		var image_match := image_pattern.search(filename)
		if image_match != null:
			images.append({"name": filename, "sequence": int(image_match.get_string(2))})
	images.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.sequence > b.sequence)
	for index in range(2, images.size()): remove.append(images[index].name)
	for filename in remove:
		if directory.remove(filename) != OK: return "Cannot collect Atelier temporary file: " + filename
	return ""
