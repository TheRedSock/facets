extends Node
## Game delivery service. Rendering belongs to the offline frame workers.
## Opening the catalog reads metadata only; frames upload bounded pages lazily.
signal library_changed

const DEFAULT_LIBRARY := "res://gem-assets/library.json"
var library := GemAssetLibrary.new()
var _attempted := false
var _load_ms := 0.0

func _ready() -> void:
	set_process(false)

## Explicit replacement is useful for the asset viewer and tests. A rejected
## replacement leaves the active library intact and does not notify consumers.
func open_library(path: String) -> bool:
	_attempted = true
	var t0 := Time.get_ticks_usec()
	if not library.open(path):
		return false
	_load_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	library_changed.emit()
	return true

func _ensure_open() -> void:
	if not _attempted:
		var default_pack := "res://generated/gem-assets.pck" if OS.has_feature("editor") else OS.get_executable_path().get_base_dir().path_join("gem-assets.pck")
		var pack_path: String = ProjectSettings.get_setting("lapidary/delivery/pack", default_pack)
		if FileAccess.file_exists(pack_path):
			ProjectSettings.load_resource_pack(pack_path, false)
		open_library(ProjectSettings.get_setting("lapidary/delivery/library", DEFAULT_LIBRARY))

## Metadata only: {frames: int, fps: float, loop: bool}.
func get_clip(tile_id: StringName, clip_id: StringName) -> Dictionary:
	_ensure_open()
	return library.clip_info(String(tile_id) + "/" + String(clip_id))

func get_frame(tile_id: StringName, clip_id: StringName, index: int) -> AtlasTexture:
	_ensure_open()
	return library.frame(String(tile_id) + "/" + String(clip_id), index)

## Warm only idle pages for the run's actual specimens. This is disk/decode/
## upload work, never a rendering job. Animation pages remain demand-loaded.
func ensure_required(tile_ids: Array) -> void:
	_ensure_open()
	if DisplayServer.get_name() == "headless":
		return
	for id in tile_ids:
		get_frame(StringName(id), &"idle", 0)

func delivery_report() -> Dictionary:
	return {"metadata_ms": _load_ms, "page_loads": library.page_loads,
		"cached_gpu_bytes": library.cache_bytes, "budget_bytes": library.cache_budget_bytes,
		"clips": library.manifest.get("clips", {}).size(), "error": library.last_error}
