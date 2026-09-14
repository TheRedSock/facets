class_name RoomAudio
extends Node
## Presentation-only bounded voices. Recipes and synthesis never run in-game.
static var muted := false
static var volume := 0.8
var streams := {}
var voices: Array[AudioStreamPlayer] = []
var generation := 0
var last_error := ""
var cues_played := 0

func _ready() -> void:
	for name in ["UI","GameSFX"]:
		if AudioServer.get_bus_index(name) < 0:
			AudioServer.add_bus(); var index := AudioServer.bus_count-1
			AudioServer.set_bus_name(index,name); AudioServer.set_bus_send(index,"Master")
	for i in 8:
		var voice := AudioStreamPlayer.new(); voice.bus = "UI" if i < 2 else "GameSFX"
		add_child(voice); voices.append(voice)
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/presentation/workshop_manifest.json"))
	for path: String in manifest.get("audio_resources",[]):
		var stream: AudioStream = load(path)
		if stream == null: last_error = "Cannot load sound: "+path; continue
		streams[path.get_file().get_basename()] = stream

func cancel() -> void:
	generation += 1
	for voice in voices: voice.stop(); voice.stream = null

func play(cue: String, owner: int = -1) -> void:
	if muted or volume <= 0 or not streams.has(cue) or (owner >= 0 and owner != generation): return
	var bus := "UI" if cue.begins_with("ui_") else "GameSFX"
	for voice in voices:
		if voice.bus == bus and not voice.playing:
			voice.stream = streams[cue]; voice.volume_db = linear_to_db(volume)
			voice.play(); cues_played += 1; return
	# Dense effects share the bounded voice pool; no queued stale audio.

func set_muted(value: bool) -> void:
	muted = value
	if muted: cancel()

func set_volume(value: float) -> void:
	volume = clampf(value,0,1)
	for voice in voices: voice.volume_db = linear_to_db(maxf(volume,0.0001))
	if volume == 0: cancel()

func _exit_tree() -> void: cancel()
