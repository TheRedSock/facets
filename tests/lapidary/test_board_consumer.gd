extends SceneTree
## Deterministic real delivery fixtures; no generated-library skips or tint path.
var failures:=0
func _initialize()->void:_run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL: "+label)
func _run()->void:
	var fixture:=GemDeliveryFixture.create("res://artifacts/board-consumer/%d"%Time.get_ticks_usec())
	check(not fixture.is_empty(),"Explicit synthetic delivery builds")
	if fixture.is_empty():_finish();return
	var corrupt_library:=GemAssetLibrary.new();check(corrupt_library.open(fixture.library),"Page corruption fixture opens metadata")
	var corrupt_key:String=corrupt_library.manifest.pages.keys()[0]
	var corrupt_path:String=fixture.library.get_base_dir().path_join(corrupt_library.manifest.pages[corrupt_key].path)
	var original_bytes:=FileAccess.get_file_as_bytes(corrupt_path)
	var bad_bytes:=original_bytes.duplicate();bad_bytes[bad_bytes.size()-1]^=1
	var bad_file:=FileAccess.open(corrupt_path,FileAccess.WRITE);bad_file.store_buffer(bad_bytes);bad_file.close()
	check(corrupt_library.load_page(corrupt_key)==null and "checksum" in corrupt_library.last_error and corrupt_library.page_loads==0,"Corrupt delivery bytes fail before decoding/upload")
	bad_file=FileAccess.open(corrupt_path,FileAccess.WRITE);bad_file.store_buffer(original_bytes.slice(0,4));bad_file.close()
	check(corrupt_library.load_page(corrupt_key)==null and "truncated" in corrupt_library.last_error,"Truncated page is rejected with its path")
	bad_file=FileAccess.open(corrupt_path,FileAccess.WRITE);bad_file.store_buffer(original_bytes);bad_file.close()
	check(corrupt_library.load_page(corrupt_key)!=null,"Repaired fixture page can load")
	corrupt_library=null
	var forge:Node=root.get_node("GemForge")
	check(forge.open_library(fixture.library,fixture.catalog),"Logical-to-physical presentation opens")
	forge.library.cache_budget_bytes=0
	forge.prefetch_budget_bytes=1
	check(not await forge.prepare_required([&"logical_tile"]) and "budget" in forge.last_error and forge.library.page_loads==0,"Oversized working set fails before allocating pages")
	forge.prefetch_budget_bytes=128*1024*1024
	check(forge.presentation.resolve(&"logical_tile",&"upgrade")=="physical_asset/celebrate","Semantic binding does not parse logical names")
	check(await forge.prepare_required([&"logical_tile",&"logical_upgrade"]),"Declared upcoming roles are prefetched")
	check(forge.assets_ready and forge.delivery_report().prefetched_pages>0,"Readiness owns the complete upcoming page set")
	var prefetch_loads:int=forge.library.page_loads
	check(forge.delivery_report().memory.cache_owned_bytes==0 and forge.delivery_report().memory.outside_cache_bytes>0,"Prefetch references remain accounted outside a zero-budget LRU")
	var invalid:GemDeliveryCatalog=fixture.catalog.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid.bindings[0].roles.erase(&"upgrade")
	check(not forge.open_library(fixture.library,invalid) and "upgrade" in forge.last_error,"Incomplete catalog fails admission with role reason")
	check(not forge.get_clip(&"logical_tile",&"rest").is_empty(),"Rejected replacement preserves admitted binding")
	var view:=load("res://scenes/tile/tile_view.tscn").instantiate() as TileView
	root.add_child(view);view.size=Vector2(112,112)
	var completed:Array[StringName]=[];var interrupted:Array[StringName]=[];var errors:Array[String]=[]
	view.playback_completed.connect(func(role:StringName):completed.append(role))
	view.playback_interrupted.connect(func(role:StringName):interrupted.append(role))
	view.delivery_failed.connect(func(message:String):errors.append(message))
	view.configure_from_data(&"logical_tile",1,Vector2i(2,3))
	check(view._clip_rect.texture is AtlasTexture and not view.is_processing(),"Rest still uses delivered texture and no frame loop")
	check(_mouse_ignored(view),"TileView and every child ignore mouse input")
	check(view.play_role(&"upgrade"),"Semantic upgrade starts")
	view._process(.11);check(view._frame==1,"Playback advances at authored timing")
	view.play_role(&"upgrade",false);check(view._frame==1 and interrupted.is_empty(),"No-restart preserves active playback")
	view.play_role(&"upgrade",true);check(view._frame==0 and interrupted==[&"upgrade"],"Explicit restart reports interruption and resets timing")
	view._process(.35);check(view._role==&"rest" and completed==[&"upgrade"] and not view.is_processing(),"Natural completion returns to rest and emits once")
	view.play_role(&"upgrade");view.show_upgrade_full(2,&"logical_upgrade")
	check(view.tile_id==&"logical_upgrade" and view.tier==2 and interrupted.size()==2 and view._role==&"rest","Changing tile interrupts old playback and resolves new rest")
	view.play_role(&"upgrade");view.return_to_rest();check(interrupted.size()==3 and view._role==&"rest","Explicit return to rest interrupts optical motion")
	check(not view.play_role(&"missing") and view._clip_rect.texture==null and not errors.is_empty(),"Missing role clears display and emits an actionable error")
	check(view.find_children("*","ColorRect",true,false).is_empty(),"There is no production tint substitution")
	check(forge.library.page_loads==prefetch_loads,"Prefetched pages do not reload after LRU eviction")
	view.return_to_rest()
	var retained:AtlasTexture=view._clip_rect.texture
	check(forge.open_library(fixture.library,fixture.catalog),"Explicit replacement admits a complete library")
	check(forge.delivery_report().memory.resident_pages==2,"Library replacement accounts for textures still held by old consumers")
	retained=null
	check(forge.delivery_report().memory.resident_pages==1,"Released old consumers leave the resident ledger")
	view.free();_finish()
func _mouse_ignored(node:Node)->bool:
	if node is Control and node.mouse_filter!=Control.MOUSE_FILTER_IGNORE:return false
	for child in node.get_children():
		if not _mouse_ignored(child):return false
	return true
func _finish()->void:
	print("Board consumer failures: ",failures);print("CHECK_COMPLETE: test_board_consumer");quit(1 if failures else 0)
