class_name GemStoreGuard
extends RefCounted
## Cooperative reader/writer activity versus exclusive maintenance. Atomic mkdir
## arbitrates maintenance; workers register then recheck before touching cache.
## No timed stealing: a slow worker must never lose its data to a cleanup task.
var _path := ""
var _maintenance := false
static var _serial := 0

static func enter(root: String, purpose := "worker") -> GemStoreGuard:
	var base := ProjectSettings.globalize_path(root).simplify_path()
	if DirAccess.dir_exists_absolute(base.path_join(".maintenance")):
		return null
	_serial += 1
	var id := "%d-%d-%d" % [OS.get_process_id(), Time.get_ticks_usec(), _serial]
	var path := base.path_join(".active/" + id + ".json")
	var owner := {"pid": OS.get_process_id(), "purpose": purpose, "started_unix": Time.get_unix_time_from_system()}
	if not GemArtifactStore.atomic_write(path, JSON.stringify(owner).to_utf8_buffer()):
		return null
	if DirAccess.dir_exists_absolute(base.path_join(".maintenance")):
		DirAccess.remove_absolute(path)
		return null
	var guard := GemStoreGuard.new()
	guard._path = path
	return guard

static func exclusive(root: String) -> GemStoreGuard:
	var base := ProjectSettings.globalize_path(root).simplify_path()
	var path := base.path_join(".maintenance")
	if DirAccess.make_dir_absolute(path) != OK:
		return null
	# Workers that raced mkdir will withdraw before reading/writing. Conservatively
	# refuse any registered activity, including a token left by an interrupted process.
	if DirAccess.dir_exists_absolute(base.path_join(".active")) and not DirAccess.get_files_at(base.path_join(".active")).is_empty():
		DirAccess.remove_absolute(path)
		return null
	var guard := GemStoreGuard.new()
	guard._path = path
	guard._maintenance = true
	GemArtifactStore.atomic_write(path.path_join("owner.json"), JSON.stringify({"pid": OS.get_process_id(), "started_unix": Time.get_unix_time_from_system()}).to_utf8_buffer())
	return guard

func release() -> void:
	if _path.is_empty():
		return
	if _maintenance:
		DirAccess.remove_absolute(_path.path_join("owner.json"))
	DirAccess.remove_absolute(_path)
	_path = ""

func _notification(what: int) -> void:
	# RefCounted is already invalid for method dispatch during PREDELETE.
	# Release external files directly, without calling a method on self.
	if what == NOTIFICATION_PREDELETE and not _path.is_empty():
		if _maintenance:
			DirAccess.remove_absolute(_path.path_join("owner.json"))
		DirAccess.remove_absolute(_path)
