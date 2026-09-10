class_name GemWorkClaim
extends RefCounted
## Cooperative work ownership on filesystems with atomic directory creation.
## Claims never expire. Recovery requires a stopped store, not a guessed PID.
var _path := ""
var _owner_hash := ""
var _guard: GemStoreGuard

static func acquire(root: String, key: String, purpose: String) -> Dictionary:
	if not GemArtifactStore.valid_key(key):return {"error":"Invalid work key"}
	var base:=ProjectSettings.globalize_path(root).replace("\\","/").simplify_path().trim_suffix("/")
	if FileAccess.file_exists(base) or FileAccess.file_exists(base.path_join(".active")):
		return {"error":"Artifact-store activity path is not a directory"}
	var guard:=GemStoreGuard.enter(root,purpose)
	if guard==null:
		if DirAccess.dir_exists_absolute(base.path_join(".maintenance")):return {"status":"busy","work":key,"reason":"maintenance"}
		return {"error":"Cannot register artifact-store activity"}
	var store:=GemArtifactStore.new(base)
	if not store.initialize():
		guard.release()
		return {"error":"Cannot initialize owned artifact store"}
	if not GemStorePath.regular_path(base,".claims") or DirAccess.make_dir_recursive_absolute(base.path_join(".claims"))!=OK:
		guard.release();return {"error":"Invalid work-claim directory"}
	var path:=base.path_join(".claims/"+key)
	if not GemStorePath.regular_path(base,".claims/"+key):
		guard.release();return {"error":"Linked work claim"}
	var error:=DirAccess.make_dir_absolute(path)
	if error!=OK:
		guard.release()
		if DirAccess.dir_exists_absolute(path):return {"status":"busy","work":key,"reason":"claimed"}
		return {"error":"Cannot create work claim: "+error_string(error)}
	var owner:={"schema":1,"work":key,"purpose":purpose,"pid":OS.get_process_id(),"started_unix":Time.get_unix_time_from_system(),"activity":guard._path.get_file()}
	var bytes:=JSON.stringify(owner).to_utf8_buffer()
	if not GemArtifactStore.atomic_write(path.path_join("owner.json"),bytes):
		DirAccess.remove_absolute(path);guard.release();return {"error":"Cannot publish work owner"}
	var claim:=GemWorkClaim.new()
	claim._path=path;claim._owner_hash=FileAccess.get_sha256(path.path_join("owner.json"));claim._guard=guard
	return {"status":"acquired","claim":claim}

func release()->void:
	_clear(_path,_owner_hash)
	_path=""
	if _guard!=null:_guard.release();_guard=null

static func _clear(path:String,owner_hash:String)->void:
	if path.is_empty():return
	# An old owner must not release a replacement claim after offline recovery.
	if FileAccess.get_sha256(path.path_join("owner.json"))!=owner_hash:return
	DirAccess.remove_absolute(path.path_join("owner.json"))
	DirAccess.remove_absolute(path)

func _notification(what:int)->void:
	if what==NOTIFICATION_PREDELETE:
		GemWorkClaim._clear(_path,_owner_hash)
		if _guard!=null:_guard.release()
