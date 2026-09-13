extends SceneTree
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: " + label)

func _initialize() -> void:
	var batch: GemAssetBatch = load("res://data/lapidary/batches/quartz_quality_lighting.tres")
	var before := GemContentIdentity.digest(batch)
	var result := GemAssetPlanner.plan(batch)
	check(result.error.is_empty(), "authored two-quality/two-light batch plans")
	if not result.error.is_empty(): printerr(result.error); print("CHECK_COMPLETE: test_asset_planner"); quit(1); return
	check(result.jobs.size() == 52 and result.clips.size() == 8 and result.specimens.size() == 4, "only explicitly requested variants and clips expanded")
	check(GemContentIdentity.digest(batch) == before, "planning leaves authored resources unchanged")
	check(result.clips.has("quartz_softened_daylight/turn") and not result.clips.has("quartz/turn"), "delivery identity independent of base stone ID")
	check(result.jobs[0].stone.stone_id == &"quartz", "delivery names do not rename physical specimens")
	var first: GemFrameJob = result.jobs[0]
	var master := GemFramePlan.master_key(first)
	batch.requests[0].rig = batch.requests[1].rig.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	batch.requests[0].rig.bg_zenith *= 0.5
	check(GemFramePlan.master_key(first) == master, "returned jobs are detached from later authoring edits")
	batch = ResourceLoader.load("res://data/lapidary/batches/quartz_quality_lighting.tres", "", ResourceLoader.CACHE_MODE_IGNORE_DEEP)
	var alias: GemAssetRequest = batch.requests[0].duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	alias.asset_id = &"same_optics_other_delivery_name"
	batch.requests.append(alias); batch.frame_budget = 128
	var aliased := GemAssetPlanner.plan(batch)
	check(aliased.error.is_empty(), "second delivery alias admitted")
	check(aliased.estimate.unique_masters == result.estimate.unique_masters and aliased.estimate.unique_displays == result.estimate.unique_displays, "aliases share optical and display work")
	check(aliased.clips["quartz_reference/idle"].frames == aliased.clips["same_optics_other_delivery_name/idle"].frames, "aliases retain shared frame references")
	batch.requests.reverse()
	var reordered := GemAssetPlanner.plan(batch)
	check(reordered.clips == aliased.clips and reordered.specimens == aliased.specimens, "request ordering does not alter result identities")
	var retained: GemAssetBatch = batch.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	retained.requests.resize(1); retained.requests[0].clips.resize(1)
	retained.requests[0].game_style = load("res://data/lapidary/styles/illustrative_sprite.tres")
	retained.requests[0].retain_prints = true
	var styled := GemAssetPlanner.plan(retained)
	check(styled.jobs.size() == 2 and styled.clips.values()[0].frames.size() == 1, "retained print is offline work only")
	check(styled.jobs[0].game_style == null and styled.jobs[1].game_style != null and GemFramePlan.master_key(styled.jobs[0]) == GemFramePlan.master_key(styled.jobs[1]), "style retains one shared optical master")
	retained.frame_budget = 1
	check(not GemAssetPlanner.plan(retained).has("jobs"), "retained prints count against allocation budget")
	var invalid: GemAssetBatch = batch.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.requests[1].asset_id = invalid.requests[0].asset_id
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "duplicate asset IDs reject atomically")
	invalid = batch.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.requests[0].clips.append(invalid.requests[0].clips[0])
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "duplicate clip names reject")
	invalid = batch.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.requests[0].clips[0].duration_s = 1e30
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "huge clip rejected before frame allocation")
	invalid.requests[0].clips[0].duration_s = NAN
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "nonfinite timing rejected")
	invalid = batch.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.requests[0].stone = invalid.requests[0].recipe.base
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "conflicting specimen sources rejected")
	invalid = batch.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.requests[0].policy_overrides = {"spp": 1}
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "ambiguous policy override rejected")
	invalid.requests[0].policy_overrides = {"unknown_option": true}
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "unknown transport policy rejected")
	invalid = batch.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.requests[0].asset_id = &"invalid/name"
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "delivery path separator rejected")
	invalid = batch.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.requests[0].clips[0].effect_envelopes["unsupported_effect"] = Curve.new()
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "unsupported effects do not silently disappear")
	invalid = batch.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.requests[0].clips[1].orientation_keys[0].orientation = Quaternion(0,0,0,0)
	check(not GemAssetPlanner.plan(invalid).has("jobs"), "undefined orientation is rejected instead of silently replaced")
	print("Asset planner: %d checks, %d failures" % [checks, failures]); print("CHECK_COMPLETE: test_asset_planner"); quit(1 if failures else 0)
