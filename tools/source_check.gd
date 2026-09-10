extends Node
## Parse every tracked source area in normal project mode so autoload names
## resolve as they do in the editor/export. Does not execute the loaded tools.
var failures := 0
var checked := 0
func _ready() -> void:
	for directory in ["core", "resources", "autoloads", "scenes", "tools", "tests"]:
		_scan("res://" + directory)
	print("Source parse: %d scripts, %d failures" % [checked, failures])
	get_tree().quit(1 if failures else 0)

func _scan(path: String) -> void:
	for name in DirAccess.get_files_at(path):
		if name.ends_with(".gd"):
			var script := load(path.path_join(name)) as GDScript
			checked += 1
			if script == null or not script.can_instantiate():
				failures += 1
				printerr("FAIL: cannot parse " + path.path_join(name))
	for directory in DirAccess.get_directories_at(path):
		_scan(path.path_join(directory))
