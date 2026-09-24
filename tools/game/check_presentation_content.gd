extends SceneTree
var failures: Array = []
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	TranslationServer.add_translation(load("res://data/localization/en.tres"))
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation/workshop_manifest.json"))
	if not manifest is Dictionary or manifest.get("schema") != 1: printerr("FAIL: presentation manifest"); quit(1); return
	var texture_bytes := 0
	var audio_bytes := 0
	for path: String in manifest.resources:
		if FileAccess.get_sha256(path) != manifest.resources[path]: failures.append("source hash mismatch/"+path)
		var resource: Resource = load(path)
		if resource == null: failures.append("missing resource/"+path); continue
		if resource is Texture2D:
			var expected := Vector2(112,112) if "/board/" in path else Vector2(64,64)
			if resource.get_size() != expected: failures.append("texture dimensions/"+path)
			texture_bytes += int(resource.get_width()*resource.get_height()*4)
		elif resource is AudioStreamWAV:
			if resource.stereo or resource.mix_rate != 48000 or resource.format != AudioStreamWAV.FORMAT_16_BITS: failures.append("audio format/"+path)
			audio_bytes += resource.data.size()
	if texture_bytes > 16*1024*1024: failures.append("non-gem texture budget")
	if audio_bytes > 2*1024*1024: failures.append("audio budget")
	var input := FileAccess.open("res://data/localization/en.csv",FileAccess.READ)
	input.get_csv_line()
	while not input.eof_reached():
		var row := input.get_csv_line()
		if row.size() == 2 and tr(row[0]) != row[1]: failures.append("compiled vocabulary mismatch/"+row[0])
	var output_directory := "res://artifacts/game/p2"
	if DirAccess.make_dir_recursive_absolute(output_directory) != OK:
		printerr("FAIL: cannot create presentation report directory"); quit(1); return
	var output := FileAccess.open(output_directory + "/presentation-content.json",FileAccess.WRITE)
	if output == null:
		printerr("FAIL: cannot write presentation report"); quit(1); return
	output.store_string(JSON.stringify({"failures":failures,"non_gem_texture_bytes":texture_bytes,
		"runtime_audio_bytes":audio_bytes,"audio_acceptance":manifest.audio_acceptance,"font_scene_decode_overhead":"not measured"},"\t"))
	for failure in failures: printerr("FAIL: "+failure)
	print("CHECK_COMPLETE: check_presentation_content"); quit(0 if failures.is_empty() else 1)
