extends SceneTree
## Compile a source CSV into a tracked text Translation for clean first import.
func _initialize() -> void:
	var input := FileAccess.open("res://data/localization/en.csv",FileAccess.READ)
	if input == null: quit(1); return
	var translation := Translation.new(); translation.locale = "en"
	input.get_csv_line()
	while not input.eof_reached():
		var row := input.get_csv_line()
		if row.size() == 2 and not row[0].is_empty(): translation.add_message(row[0],row[1])
	if ResourceSaver.save(translation,"res://data/localization/en.tres") != OK: quit(1); return
	print("CHECK_COMPLETE: build_vocabulary"); quit(0)
