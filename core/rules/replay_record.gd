class_name ReplayRecord
extends RefCounted

static func verify(data: Variant) -> Dictionary:
	if not StateAdmission.exact(data,["version","initial","initial_digest","commands"]) or data.version not in ["facets-replay-v1","facets-replay-v2"] or not data.commands is Array or data.commands.size() > 100000: return StateAdmission.fail("replay_schema")
	if CanonicalCodec.digest(data.initial) != data.initial_digest: return StateAdmission.fail("replay_initial_digest")
	var controller := RunController.new()
	if not controller.restore_snapshot(data.initial): return StateAdmission.fail(controller.last_error)
	if (data.version == "facets-replay-v2") != (controller.run_state.room != null): return StateAdmission.fail("replay_profile")
	for i in data.commands.size():
		var entry: Variant = data.commands[i]
		if not StateAdmission.exact(entry,["command","state_digest","event_digest"]): return StateAdmission.fail("replay_entry")
		var command: Variant = RoomCommand.parse(entry.command) if data.version == "facets-replay-v2" else SwapCommand.parse(entry.command)
		if command == null: return StateAdmission.fail("replay_command")
		var result := controller.apply_action(command)
		if not result.ok: return {"ok":false,"code":"replay_action/" + result.code,"index":i}
		if result.state_digest != entry.state_digest or result.event_digest != entry.event_digest: return {"ok":false,"code":"replay_checkpoint","index":i}
	return {"ok":true,"state":controller.run_state,"controller":controller}
