class_name GemStoreRecovery
extends RefCounted
## Explicit offline recovery. A PID from another machine cannot prove liveness.
## Preserve abandoned tokens in a quarantine; never delete rendered artifacts.
var last_error := ""

func inspect(root:String)->Dictionary:
	last_error=""
	var base:=ProjectSettings.globalize_path(root).replace("\\","/").simplify_path().trim_suffix("/")
	if not GemStorePath.owned_root(base):return _fail("Recovery requires an owned, unlinked store")
	var files:={}
	var claims:=[]
	for directory:String in [".active",".claims"]:
		if not GemStorePath.regular_path(base,directory):return _fail("Linked coordination directory")
		if not DirAccess.dir_exists_absolute(base.path_join(directory)):continue
		if directory==".active":
			if not DirAccess.get_directories_at(base.path_join(directory)).is_empty():return _fail("Unexpected activity directory")
			for name in DirAccess.get_files_at(base.path_join(directory)):
				if not _activity_name(name):return _fail("Unknown activity token: "+name)
				if not _record(base,directory.path_join(name),files):return {}
		else:
			if not DirAccess.get_files_at(base.path_join(directory)).is_empty():return _fail("Unexpected claim file")
			for key in DirAccess.get_directories_at(base.path_join(directory)):
				var relative:=directory.path_join(key)
				if not GemArtifactStore.valid_key(key) or not GemStorePath.regular_path(base,relative):return _fail("Invalid claim path")
				if not DirAccess.get_directories_at(base.path_join(relative)).is_empty():return _fail("Unexpected claim subtree")
				claims.append(relative)
				for name in DirAccess.get_files_at(base.path_join(relative)):
					if name!="owner.json" and not _temporary_name(name,"owner.json"):return _fail("Unknown claim file")
					if not _record(base,relative.path_join(name),files):return {}
	claims.sort()
	var paths:=files.keys();paths.sort()
	var ordered:=[]
	for path in paths:ordered.append([path,files[path]])
	return {"schema":1,"root":base,"snapshot":GemContentIdentity.digest([base,claims,ordered]),"files":files,"claims":claims}

func recover(root:String,expected_snapshot:String,workers_stopped:bool)->Dictionary:
	last_error=""
	if not workers_stopped:return _fail("Stop all workers and publishers before offline recovery")
	var base:=ProjectSettings.globalize_path(root).replace("\\","/").simplify_path().trim_suffix("/")
	if not GemStorePath.owned_root(base) or not GemStorePath.regular_path(base,".maintenance"):return _fail("Invalid recovery store")
	var gate:=base.path_join(".maintenance")
	if DirAccess.make_dir_absolute(gate)!=OK:return _fail("Maintenance is already owned; inspect its owner separately")
	var owner:={"pid":OS.get_process_id(),"purpose":"offline-recovery","started_unix":Time.get_unix_time_from_system(),"snapshot":expected_snapshot}
	if not GemArtifactStore.atomic_write(gate.path_join("owner.json"),JSON.stringify(owner).to_utf8_buffer()):
		DirAccess.remove_absolute(gate);return _fail("Cannot record recovery owner")
	var result:=_recover_locked(base,expected_snapshot)
	DirAccess.remove_absolute(gate.path_join("owner.json"))
	DirAccess.remove_absolute(gate)
	return result

func _recover_locked(base:String,expected:String)->Dictionary:
	var snapshot:=inspect(base)
	if snapshot.is_empty():return {}
	if expected!=snapshot.snapshot:return _fail("Coordination state changed; inspect a new snapshot")
	if snapshot.files.is_empty() and snapshot.claims.is_empty():return {"recovered":0,"snapshot":expected}
	if not GemStorePath.regular_path(base,".recovered"):return _fail("Linked recovery directory")
	var relative:=".recovered/%s-%d-%d"%[expected,OS.get_process_id(),Time.get_ticks_usec()]
	var destination:=base.path_join(relative)
	if DirAccess.make_dir_recursive_absolute(destination)!=OK:return _fail("Cannot create recovery quarantine")
	if not GemArtifactStore.atomic_write(destination.path_join("snapshot.json"),JSON.stringify(snapshot,"\t").to_utf8_buffer()):return _fail("Cannot save recovery inventory")
	var paths:=[]
	for path:String in snapshot.files:
		if path.begins_with(".active/"):paths.append(path)
	paths.append_array(snapshot.claims)
	paths.sort()
	for path:String in paths:
		var target:=relative.path_join(path)
		if not GemStorePath.regular_path(base,path) or not target.begins_with(relative+"/"):return _fail("Recovery path changed")
		if DirAccess.make_dir_recursive_absolute(base.path_join(target).get_base_dir())!=OK:return _fail("Cannot create quarantine parent")
		if not GemStorePath.regular_path(base,target):return _fail("Linked quarantine target")
		if DirAccess.rename_absolute(base.path_join(path),base.path_join(target))!=OK:return _fail("Recovery interrupted; inspect remaining tokens before retry")
	return {"recovered":paths.size(),"snapshot":expected,"quarantine":destination}

func _record(base:String,path:String,files:Dictionary)->bool:
	if not GemStorePath.regular_path(base,path):_fail("Linked coordination file");return false
	var file:=FileAccess.open(base.path_join(path),FileAccess.READ)
	if file==null or file.get_length()>1048576:_fail("Unreadable or oversized coordination file");return false
	files[path]=FileAccess.get_sha256(base.path_join(path))
	if files[path].is_empty():_fail("Coordination file changed during inspection");return false
	return true

static func _activity_name(name:String)->bool:
	var base:=name.trim_suffix(".json")
	var parts:=base.split("-")
	if name.ends_with(".json") and parts.size()==3:
		return parts[0].is_valid_int() and parts[1].is_valid_int() and parts[2].is_valid_int()
	var marker:=name.find(".json.")
	return marker>0 and _activity_name(name.left(marker+5)) and _temporary_name(name,name.left(marker+5))

static func _temporary_name(name:String,prefix:String)->bool:
	if not name.begins_with(prefix+".") or not name.ends_with(".tmp"):return false
	var parts:=name.trim_prefix(prefix+".").trim_suffix(".tmp").split(".")
	return parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int()

func _fail(message:String)->Dictionary:
	last_error=message
	return {}
