class_name ExpeditionSave
extends RefCounted
## Canonical exact-integer saves with verified temp and last-known-good recovery.
const MAGIC := "FACP3SV1"
const HEADER := 48
var directory := "user://expeditions"

static func phase_of(run: ExpeditionState) -> String:
	if run.session == null: return run.phase
	if not run.session.reservation.is_empty(): return "reserved_command"
	return run.session.phase

static func checksum(bytes: PackedByteArray) -> PackedByteArray:
	var hash := HashingContext.new(); hash.start(HashingContext.HASH_SHA256); hash.update(bytes)
	return hash.finish()

static func encode(run: ExpeditionState) -> PackedByteArray:
	if run.current() == null: return PackedByteArray()
	var payload := CanonicalCodec.encode({"save":P3Content.SAVE,"content":P3Content.CONTENT,"phase":phase_of(run),"snapshot":run.snapshot()})
	if payload.is_empty() or payload.size() > CanonicalCodec.MAX_BYTES: return PackedByteArray()
	var bytes := MAGIC.to_ascii_buffer(); bytes.resize(16); bytes.encode_s64(8,payload.size())
	bytes.append_array(checksum(payload)); bytes.append_array(payload)
	return bytes

static func decode(bytes: PackedByteArray, pause_timed: bool = true) -> Dictionary:
	if bytes.size() < HEADER or bytes.size() > CanonicalCodec.MAX_BYTES+HEADER or bytes.slice(0,8).get_string_from_ascii() != MAGIC: return StateAdmission.fail("save_magic_or_size")
	var length := bytes.decode_s64(8)
	if length < 5 or length != bytes.size()-HEADER: return StateAdmission.fail("save_length")
	var payload := bytes.slice(HEADER)
	if checksum(payload) != bytes.slice(16,HEADER): return StateAdmission.fail("save_checksum")
	var decoded := CanonicalCodec.decode(payload)
	if not decoded.ok: return decoded
	var value: Variant = decoded.value
	if not StateAdmission.exact(value,["save","content","phase","snapshot"]) or value.save != P3Content.SAVE or value.content != P3Content.CONTENT: return StateAdmission.fail("save_incompatible")
	var admitted := ExpeditionState.restored(value.snapshot,false)
	if not admitted.ok: return admitted
	if value.phase != phase_of(admitted.run): return StateAdmission.fail("save_phase")
	if pause_timed and admitted.run.session != null:
		admitted.run.session = MergeReplay.restored(value.snapshot.session,true).session
	return admitted

static func valid_slot(slot: String) -> bool:
	if slot.is_empty() or slot.length() > 48: return false
	for code in slot.to_ascii_buffer():
		if not (code >= 97 and code <= 122) and not (code >= 48 and code <= 57) and code not in [45,95]: return false
	return slot.is_valid_ascii_identifier() or slot.replace("-","_").is_valid_ascii_identifier()

func path(slot: String, suffix: String = ".fac") -> String:
	return directory.path_join(slot+suffix)

func read_file(file_path: String, pause_timed: bool = true) -> Dictionary:
	var file := FileAccess.open(file_path,FileAccess.READ)
	if file == null: return StateAdmission.fail("save_missing_or_unreadable")
	var length := file.get_length()
	if length > CanonicalCodec.MAX_BYTES+HEADER: file.close(); return StateAdmission.fail("save_size")
	var bytes := file.get_buffer(length); file.close()
	return decode(bytes,pause_timed)

func load_slot(slot: String = "continue", pause_timed: bool = true) -> Dictionary:
	if not valid_slot(slot): return StateAdmission.fail("save_slot")
	var primary := read_file(path(slot),pause_timed)
	if primary.ok: primary.recovered = false; return primary
	var backup := read_file(path(slot,".bak"),pause_timed)
	if backup.ok: backup.recovered = true; backup.warning = primary.code; return backup
	return {"ok":false,"code":primary.code,"recovery_code":backup.code}

func write_slot(run: ExpeditionState, slot: String = "continue", fail_at: String = "") -> Dictionary:
	if not valid_slot(slot): return StateAdmission.fail("save_slot")
	var bytes := encode(run)
	if bytes.is_empty(): return StateAdmission.fail("save_empty_or_oversize")
	if fail_at == "before_write": return StateAdmission.fail("injected_before_write")
	if DirAccess.make_dir_recursive_absolute(directory) != OK: return StateAdmission.fail("save_directory")
	var temp := path(slot,".tmp"); var target := path(slot); var backup := path(slot,".bak")
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file == null: return StateAdmission.fail("save_write")
	if fail_at == "partial_temp": file.store_buffer(bytes.slice(0,bytes.size()/2)); file.flush(); file.close(); return StateAdmission.fail("injected_partial_temp")
	file.store_buffer(bytes); file.flush(); var error := file.get_error(); file.close()
	if error != OK: return StateAdmission.fail("save_flush")
	if fail_at == "after_flush": return StateAdmission.fail("injected_after_flush")
	var verified := read_file(temp,false)
	if not verified.ok: return StateAdmission.fail("save_verify/"+verified.code)
	if fail_at in ["after_verify","before_replace"]: return StateAdmission.fail("injected_"+fail_at)
	if FileAccess.file_exists(target):
		if read_file(target,false).ok:
			if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK: return StateAdmission.fail("save_backup_remove")
			if DirAccess.rename_absolute(target,backup) != OK: return StateAdmission.fail("save_backup_rename")
		elif DirAccess.remove_absolute(target) != OK: return StateAdmission.fail("save_corrupt_replace")
	if fail_at == "after_backup": return StateAdmission.fail("injected_after_backup")
	if DirAccess.rename_absolute(temp,target) != OK: return StateAdmission.fail("save_replace")
	return {"ok":true}
