extends SceneTree
## TRUE cold-start measurement for GemForge: stashes res://generated/gemcache
## and clears user://gemcache so every clip misses, then lets the forge's
## _process tick loop bake the full manifest while we time it in-tree.
## Restores the stash afterwards (also on timeout).
## Run:  godot --path . --script res://tools/forge_cold_start_check.gd

const LADDER := [&"quartz", &"amethyst", &"peridot", &"topaz", &"sapphire", &"emerald", &"ruby", &"diamond"]
const TIMEOUT_S := 120.0

var _stash_done := false
var _generated := ""
var _stash := ""
var _t0 := 0
var _first_idle_ms := -1
var _all_idle_ms := -1
var _all_done_ms := -1
var _ready_clips := {}
var _placeholder_ms := 0.0


func _initialize() -> void:
	_generated = ProjectSettings.globalize_path("res://generated/gemcache")
	_stash = ProjectSettings.globalize_path("res://generated/gemcache_stash")
	if DirAccess.dir_exists_absolute(_generated):
		var err := DirAccess.rename_absolute(_generated, _stash)
		if err != OK:
			print("COLD_START FAILED: cannot stash generated cache (err %d)" % err)
			quit(1)
			return
		_stash_done = true
	var user_cache := ProjectSettings.globalize_path("user://gemcache")
	if DirAccess.dir_exists_absolute(user_cache):
		OS.move_to_trash(user_cache)
	# Autoloads are not in the tree yet during _initialize; setup happens on
	# the first process tick (_start).


var _started := false


func _start() -> void:
	var forge: Node = root.get_node("GemForge")
	forge.clip_ready.connect(_on_clip_ready)

	# Placeholder latency: synchronous INTERACT still on a cold forge.
	var tp0 := Time.get_ticks_usec()
	var ph: Variant = forge.get_placeholder_still(&"sapphire")
	_placeholder_ms = float(Time.get_ticks_usec() - tp0) / 1000.0
	print("  placeholder_still(sapphire): %.1f ms, valid=%s" % [_placeholder_ms, str(ph != null)])

	_t0 = Time.get_ticks_msec()
	forge.ensure_required(LADDER)


func _on_clip_ready(tile_id: StringName, clip_id: StringName) -> void:
	var ms := Time.get_ticks_msec() - _t0
	_ready_clips["%s/%s" % [tile_id, clip_id]] = ms
	if clip_id == &"idle":
		if _first_idle_ms < 0:
			_first_idle_ms = ms
		var idle_count := 0
		for key: String in _ready_clips:
			if key.ends_with("/idle"):
				idle_count += 1
		if idle_count == LADDER.size():
			_all_idle_ms = ms


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_start()
		return false
	var elapsed := float(Time.get_ticks_msec() - _t0) / 1000.0
	if _ready_clips.size() >= LADDER.size() * 3:
		_all_done_ms = Time.get_ticks_msec() - _t0
		_finish(true)
		return true
	if elapsed > TIMEOUT_S:
		print("  TIMEOUT with %d/%d clips ready" % [_ready_clips.size(), LADDER.size() * 3])
		_finish(false)
		return true
	return false


func _finish(ok: bool) -> void:
	var forge: Node = root.get_node("/root/GemForge")
	var report: Dictionary = forge.cold_start_report()
	print("  first idle ready: %.2f s" % (_first_idle_ms / 1000.0))
	print("  all 8 idles ready: %.2f s" % (_all_idle_ms / 1000.0))
	if _all_done_ms >= 0:
		print("  full catalog (24 clips): %.2f s" % (_all_done_ms / 1000.0))
	print("  forge report: %s" % str(report))
	if _stash_done:
		var err := DirAccess.rename_absolute(_stash, _generated)
		print("  stash restored: %s" % ("OK" if err == OK else "FAILED err %d" % err))
	print("COLD_START %s" % ("COMPLETE" if ok else "FAILED"))
	quit(0 if ok else 1)
